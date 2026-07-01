--[[
    gTelemetry: GMod Telemetry
    sv_otlp_logs.lua — OTLP LogRecord builder & HTTP transport

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
local table_insert = table.insert
local pairs = pairs
local math_min = math.min
local math_ceil = math.ceil

local _logBuffer = {}
local _bufferSize = 0
local _bufferStart = 1
local _initialized = false
local _logGeneration = 0
local _flushSnapshot = {}  -- { start, size } captured at flush extraction

GTelemetry.OTLP.Logs.SendFailures = 0
GTelemetry.OTLP.Logs.DroppedLogs = 0
GTelemetry.OTLP.Logs.TruncatedLogs = 0

local _backoffAttempts = 0
local _nextSendTime = 0
local _maxBackoff = 30
local _isFlushing = false
local _cachedGamemode = nil
local _cachedHostname = nil

--- Prepend records to buffer, using the snapshot captured at flush extraction.
-- This ensures correct buffer positioning even if AddLog ran between extraction
-- and reinsertion (e.g., from an async HTTP callback).
local function _reinsertRecords(records)
    if not records or #records == 0 then return end
    local failedCount = #records
    local snapStart = _flushSnapshot.start
    local snapSize = _flushSnapshot.size
    local currentStart = _bufferStart
    local currentSize = _bufferSize
    local maxSize = GTelemetry.Config.GetLogBufferSize()
    local toInsert = math.min(failedCount, maxSize - currentSize)
    -- Shift existing records (added after flush) to make room at snapshot position
    for i = currentSize, 1, -1 do
        _logBuffer[snapStart + toInsert + i - 1] = _logBuffer[currentStart + i - 1]
        _logBuffer[currentStart + i - 1] = nil
    end
    for i = 1, toInsert do
        _logBuffer[snapStart + i - 1] = records[i]
    end
    _bufferStart = snapStart
    _bufferSize = currentSize + toInsert
    if toInsert < failedCount then
        GTelemetry.OTLP.Logs.DroppedLogs = GTelemetry.OTLP.Logs.DroppedLogs + (failedCount - toInsert)
    end
end

hook.Add("gamemode.PostGamemodeLoaded", "GTelemetry_Logs_GamemodeCache", function()
    _cachedGamemode = nil
end)

cvars.AddChangeCallback("hostname", function()
    _cachedHostname = nil
end, "GTelemetry_Logs_HostnameCache")

function GTelemetry.OTLP.Logs.ResetBackoff()
    _backoffAttempts = 0
    _nextSendTime = 0
end

function GTelemetry.OTLP.Logs.Init()
    if _initialized then return end
    _initialized = true
end

--- Add a log entry to the buffer.
function GTelemetry.OTLP.Logs.AddLog(severityNumber, severityText, body, attributes)
    if not _initialized then GTelemetry.OTLP.Logs.Init() end

    local maxBodyLen = 16384
    if #body > maxBodyLen then
        body = body:sub(1, maxBodyLen):gsub("[\128-\191]$", "") .. "..."
        GTelemetry.OTLP.Logs.TruncatedLogs = GTelemetry.OTLP.Logs.TruncatedLogs + 1
    end
    body = tostring(body):gsub("[\000-\008\011\012\014-\031\127]", "")

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

    if _bufferStart > maxSize * 2 then
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
    if not _cachedHostname then _cachedHostname = GetHostName and GetHostName() or "unknown" end
    local currentMap = game.GetMap() or "unknown"
    local serviceName = GTelemetry.Config.GetServiceName()

    if not _cachedGamemode then
        local gm = gmod.GetGamemode()
        _cachedGamemode = (engine.ActiveGamemode and engine.ActiveGamemode()) or (gm and gm.Name) or "unknown"
    end

    local payload = {
        resourceLogs = {
            {
                resource = {
                    attributes = {
                        GTelemetry.OTLP.Attribute("service.name", serviceName),
                        GTelemetry.OTLP.Attribute("service.version", GTelemetry.Version or "1.5.8"),
                        GTelemetry.OTLP.Attribute("host.name", _cachedHostname),
                        GTelemetry.OTLP.Attribute("gmod.map", currentMap),
                        GTelemetry.OTLP.Attribute("gmod.gamemode", _cachedGamemode),
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
            pcall(function()
                _backoffAttempts = 0
                _nextSendTime = 0
                GTelemetry.Debug("Logs sent successfully")
            end)
        end,
        onFailure = function(errMsg)
            pcall(function()
                _backoffAttempts = _backoffAttempts + 1
                _nextSendTime = SysTime() + math_min(2 ^ _backoffAttempts, _maxBackoff)
                GTelemetry.OTLP.Logs.SendFailures = GTelemetry.OTLP.Logs.SendFailures + 1
                GTelemetry.Warn("Failed to send logs: " .. errMsg)
                if timer.Exists("GTelemetry_LogFlush") and flushGen == _logGeneration then
                    _reinsertRecords(recordsToRetry)
                end
            end)
        end,
    })

    return true
end

--- Flush buffered log entries.
function GTelemetry.OTLP.Logs.Flush()
    if _bufferSize == 0 then return end
    if _isFlushing then
        GTelemetry.Debug("Skipping log flush — previous flush still in progress")
        return
    end
    _isFlushing = true

    _logGeneration = _logGeneration + 1
    local records = {}
    _flushSnapshot.start = _bufferStart
    _flushSnapshot.size = _bufferSize
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
        if timer.Exists("GTelemetry_LogFlush") and flushGen == _logGeneration then
            _reinsertRecords(records)
        end
    elseif not result then
        GTelemetry.Debug("Log flush skipped (backoff active), re-inserting " .. #records .. " records")
        if timer.Exists("GTelemetry_LogFlush") and flushGen == _logGeneration then
            _reinsertRecords(records)
        end
    end

    _isFlushing = false
end

--- Clear buffer without sending.
function GTelemetry.OTLP.Logs.ClearBuffer()
    _logGeneration = _logGeneration + 1
    _logBuffer = {}
    _bufferStart = 1
    _bufferSize = 0
end
