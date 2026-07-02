--[[
    gTelemetry: GMod Telemetry
    sv_otlp_logs.lua � OTLP LogRecord builder & HTTP transport

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Builds ExportLogsServiceRequest payloads in OTLP JSON format
    and sends them to a Grafana Alloy otelcol.receiver.otlp endpoint
    for routing to Loki.
]]

GTelemetry.OTLP.Logs = GTelemetry.OTLP.Logs or {}

local util_TableToJSON = util.TableToJSON
local SysTime = SysTime
local tostring = tostring
local math_min = math.min
local math_ceil = math.ceil

local _logBuffer = {}
local _bufferSize = 0
local _bufferStart = 1
local _initialized = false
local _logGeneration = 0

GTelemetry.OTLP.Logs.SendFailures = 0
GTelemetry.OTLP.Logs.DroppedLogs = 0
GTelemetry.OTLP.Logs.TruncatedLogs = 0

local _backoffAttempts = 0
local _nextSendTime = 0
local _maxBackoff = 30
local _isFlushing = false
local _stopped = false

--- Prepend records to buffer, using a new buffer to avoid O(n) shifting.
local function _reinsertRecords(records)
    if not records or #records == 0 then return end
    local failedCount = #records
    local currentSize = _bufferSize
    local maxSize = GTelemetry.Config.GetLogBufferSize()
    local toInsert = math.min(failedCount, maxSize - currentSize)
    local newSize = currentSize + toInsert
    local newBuf = {}
    local idx = 1
    for i = 1, toInsert do
        newBuf[idx] = records[i]
        idx = idx + 1
    end
    for i = 0, currentSize - 1 do
        newBuf[idx] = _logBuffer[_bufferStart + i]
        _logBuffer[_bufferStart + i] = nil
        idx = idx + 1
    end
    _logBuffer = newBuf
    _bufferStart = 1
    _bufferSize = newSize
    if toInsert < failedCount then
        GTelemetry.OTLP.Logs.DroppedLogs = GTelemetry.OTLP.Logs.DroppedLogs + (failedCount - toInsert)
    end
end

function GTelemetry.OTLP.Logs.ResetBackoff()
    _backoffAttempts = 0
    _nextSendTime = 0
end

function GTelemetry.OTLP.Logs.Init()
    _stopped = false
    if _initialized then return end
    _initialized = true
end

--- Add a log entry to the buffer.
function GTelemetry.OTLP.Logs.AddLog(severityNumber, severityText, body, attributes)
    if not _initialized then GTelemetry.OTLP.Logs.Init() end

    body = tostring(body)
    local maxBodyLen = 16384
    if #body > maxBodyLen then
        body = body:sub(1, maxBodyLen):gsub("[\128-\191]$", "") .. "..."
        GTelemetry.OTLP.Logs.TruncatedLogs = GTelemetry.OTLP.Logs.TruncatedLogs + 1
    end
    body = body:gsub("[\000-\008\011\012\014-\031\127]", "")

    local record = {
        timeUnixNano = GTelemetry.OTLP.GetTimeNano(),
        severityNumber = severityNumber,
        severityText = severityText,
        body = {stringValue = body},
    }

    if attributes and #attributes > 0 then
        record.attributes = attributes
    end

    local maxSize = GTelemetry.Config.GetLogBufferSize()
    if _bufferSize >= maxSize then
        _logBuffer[_bufferStart] = nil
        _bufferStart = _bufferStart + 1
        GTelemetry.OTLP.Logs.DroppedLogs = GTelemetry.OTLP.Logs.DroppedLogs + 1
        _bufferSize = _bufferSize - 1
    end

    if _bufferStart > maxSize + math.ceil(maxSize / 2) then
        local newBuf = {}
        for i = 1, _bufferSize do
            newBuf[i] = _logBuffer[_bufferStart + i - 1]
        end
        _logBuffer = newBuf
        _bufferStart = 1
    end

    _logBuffer[_bufferStart + _bufferSize] = record
    _bufferSize = _bufferSize + 1
end

--- Build the OTLP log payload.
function GTelemetry.OTLP.Logs.BuildPayload(logRecords)
    if not GTelemetry.OTLP._cachedHostname then GTelemetry.OTLP._cachedHostname = GetHostName and GetHostName() or "unknown" end
    local currentMap = game.GetMap() or "unknown"
    local serviceName = GTelemetry.Config.GetServiceName()

    if not GTelemetry.OTLP._cachedGamemode then
        local gm = gmod.GetGamemode()
        GTelemetry.OTLP._cachedGamemode = (engine.ActiveGamemode and engine.ActiveGamemode()) or (gm and gm.Name) or "unknown"
    end

    local payload = {
        resourceLogs = {
            {
                resource = {
                    attributes = {
                        GTelemetry.OTLP.Attribute("service.name", serviceName),
                        GTelemetry.OTLP.Attribute("service.version", GTelemetry.Version or "1.5.8"),
                        GTelemetry.OTLP.Attribute("host.name", GTelemetry.OTLP._cachedHostname),
                        GTelemetry.OTLP.Attribute("gmod.map", currentMap),
                        GTelemetry.OTLP.Attribute("gmod.gamemode", GTelemetry.OTLP._cachedGamemode),
                    },
                },
                scopeLogs = {
                    {
                        scope = {
                            name = "gTelemetry.logs",
                            version = GTelemetry.Version or "1.5.8",
                        },
                        logRecords = logRecords,
                    },
                },
            },
        },
    }

    return util_TableToJSON(payload)
end

--- Send log payload HTTP POST to the configured endpoint.
--- Returns true if a request was initiated, false if skipped (backoff).
--- @param jsonBody string JSON-encoded ExportLogsServiceRequest
--- @param recordsToRetry table|nil records to re-insert on HTTP failure
function GTelemetry.OTLP.Logs.Send(jsonBody, recordsToRetry)
    local endpoint = GTelemetry.Config.GetLogEndpoint()
    if not endpoint or endpoint == "" then return false end

    if SysTime() < _nextSendTime then
        GTelemetry.Debug("Skipping log send (backoff active, next in " .. math_ceil(_nextSendTime - SysTime()) .. "s)")
        return false
    end

    local flushGen = _logGeneration
    GTelemetry.OTLP._DoHTTPPost(endpoint, jsonBody, {
        onSuccess = function()
            _backoffAttempts = 0
            _nextSendTime = 0
            GTelemetry.Debug("Logs sent successfully")
        end,
        onFailure = function(errMsg)
_backoffAttempts = _backoffAttempts + 1
            _backoffAttempts = math.min(_backoffAttempts, _maxBackoff)
            _nextSendTime = SysTime() + math_min(2 ^ _backoffAttempts, _maxBackoff)
            GTelemetry.OTLP.Logs.SendFailures = GTelemetry.OTLP.Logs.SendFailures + 1
            GTelemetry.Warn("Failed to send logs: " .. errMsg)
            if not _stopped and flushGen == _logGeneration then
                _reinsertRecords(recordsToRetry)
            end
        end,
    })

    return true
end

--- Flush buffered log entries.
function GTelemetry.OTLP.Logs.Flush()
    if _bufferSize == 0 then return end
    if _isFlushing then
        GTelemetry.Debug("Skipping log flush � previous flush still in progress")
        return
    end
    _isFlushing = true

    _logGeneration = _logGeneration + 1
    local records = {}
    for i = 0, _bufferSize - 1 do
        records[i + 1] = _logBuffer[_bufferStart + i]
        _logBuffer[_bufferStart + i] = nil
    end
    _bufferStart = 1
    _bufferSize = 0

    local flushGen = _logGeneration
    local success, result = pcall(function()
        local jsonBody = GTelemetry.OTLP.Logs.BuildPayload(records)
        return GTelemetry.OTLP.Logs.Send(jsonBody, records)
    end)

    if not success then
        GTelemetry.Warn("Log flush failed: " .. tostring(result))
        if not _stopped and flushGen == _logGeneration then
            _reinsertRecords(records)
        end
    elseif not result then
        GTelemetry.Debug("Log flush skipped (backoff active), re-inserting " .. #records .. " records")
        if not _stopped and flushGen == _logGeneration then
            _reinsertRecords(records)
        end
    end

    _isFlushing = false
end

--- Disable log collection: set stopped flag to prevent re-insertion on failure.
-- Does NOT clear the buffer — call Flush() after for best-effort send.
function GTelemetry.OTLP.Logs.Disable()
    _stopped = true
    GTelemetry.Debug("Log collector disabled — no further re-insertions")
end

--- Clear buffer without sending.
function GTelemetry.OTLP.Logs.ClearBuffer()
    _stopped = true
    _logGeneration = _logGeneration + 1
    _logBuffer = {}
    _bufferStart = 1
    _bufferSize = 0
end
