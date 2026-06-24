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
local string_format = string.format
local table_insert = table.insert
local table_remove = table.remove
local pairs = pairs
local math_min = math.min
local math_floor = math.floor

local _logBuffer = {}
local _bufferSize = 0
local _initialized = false

GTelemetry.OTLP.Logs.SendFailures = 0
GTelemetry.OTLP.Logs.DroppedLogs = 0

local _backoffAttempts = 0
local _nextSendTime = 0
local _maxBackoff = 30
local _isFlushing = false
local _cachedGamemode = nil

hook.Add("gamemode.PostGamemodeLoaded", "GTelemetry_Logs_GamemodeCache", function()
    _cachedGamemode = nil
end)

function GTelemetry.OTLP.Logs.Init()
    if _initialized then return end
    _initialized = true
end

function GTelemetry.OTLP.Logs.Attribute(key, value)
    local valType = type(value)
    local otlpValue

    if valType == "number" then
        if value < math.huge and value > -math.huge then
            if value == math_floor(value) then
                otlpValue = {intValue = string_format("%.0f", value)}
            else
                otlpValue = {doubleValue = value}
            end
        else
            otlpValue = {stringValue = tostring(value)}
        end
    elseif valType == "boolean" then
        otlpValue = {boolValue = value}
    else
        otlpValue = {stringValue = tostring(value)}
    end

    return {key = key, value = otlpValue}
end

--- Add a log entry to the buffer.
function GTelemetry.OTLP.Logs.AddLog(severityNumber, severityText, body, attributes)
    if not _initialized then GTelemetry.OTLP.Logs.Init() end

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
        table_remove(_logBuffer, 1)
        GTelemetry.OTLP.Logs.DroppedLogs = GTelemetry.OTLP.Logs.DroppedLogs + 1
        _bufferSize = _bufferSize - 1
    end

    table_insert(_logBuffer, record)
    _bufferSize = _bufferSize + 1
end

--- Build the OTLP log payload.
function GTelemetry.OTLP.Logs.BuildPayload(logRecords)
    local hostname = GetHostName and GetHostName() or "unknown"
    local currentMap = game.GetMap() or "unknown"
    local serviceName = GTelemetry.Config.GetServiceName()

    if not _cachedGamemode then
        _cachedGamemode = (engine.ActiveGamemode and engine.ActiveGamemode()) or (gmod.GetGamemode() and gmod.GetGamemode().Name) or "unknown"
    end

    local payload = {
        resourceLogs = {
            {
                resource = {
                    attributes = {
                        GTelemetry.OTLP.Logs.Attribute("service.name", serviceName),
                        GTelemetry.OTLP.Logs.Attribute("service.version", GTelemetry.Version or "1.5.0"),
                        GTelemetry.OTLP.Logs.Attribute("host.name", hostname),
                        GTelemetry.OTLP.Logs.Attribute("gmod.map", currentMap),
                        GTelemetry.OTLP.Logs.Attribute("gmod.gamemode", _cachedGamemode),
                    },
                },
                scopeLogs = {
                    {
                        scope = {
                            name = "gTelemetry.logs",
                            version = GTelemetry.Version or "1.5.0",
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
function GTelemetry.OTLP.Logs.Send(jsonBody)
    local endpoint = GTelemetry.Config.GetLogEndpoint()
    if not endpoint or endpoint == "" then return false end

    local headers = {
        ["Content-Type"] = "application/json",
    }

    local token = GTelemetry.Config.GetAuthToken()
    if token then
        headers["Authorization"] = "Bearer " .. token
    end

    if SysTime() < _nextSendTime then
        GTelemetry.Debug("Skipping log send (backoff active, next in " .. math.ceil(_nextSendTime - SysTime()) .. "s)")
        return false
    end

    GTelemetry.Debug("Sending logs to: " .. endpoint .. " (" .. #jsonBody .. " bytes)")

    HTTP({
        url = endpoint,
        method = "POST",
        headers = headers,
        body = jsonBody,
        type = "application/json",

        success = function(code, body, respHeaders)
            if code >= 200 and code < 300 then
                _backoffAttempts = 0
                _nextSendTime = 0
                GTelemetry.Debug("Logs sent successfully (HTTP " .. code .. ")")
            else
                _backoffAttempts = _backoffAttempts + 1
                _nextSendTime = SysTime() + math_min(2 ^ _backoffAttempts, _maxBackoff)
                GTelemetry.OTLP.Logs.SendFailures = GTelemetry.OTLP.Logs.SendFailures + 1
                GTelemetry.Warn("Log endpoint returned HTTP " .. code .. ": " .. (body or "no body"))
            end
        end,

        failed = function(err)
            _backoffAttempts = _backoffAttempts + 1
            _nextSendTime = SysTime() + math_min(2 ^ _backoffAttempts, _maxBackoff)
            GTelemetry.OTLP.Logs.SendFailures = GTelemetry.OTLP.Logs.SendFailures + 1
            GTelemetry.Warn("Failed to send logs: " .. tostring(err))
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

    local records = _logBuffer
    _logBuffer = {}
    _bufferSize = 0

    local success, result = pcall(function()
        local jsonBody = GTelemetry.OTLP.Logs.BuildPayload(records)
        return GTelemetry.OTLP.Logs.Send(jsonBody)
    end)

    if not success then
        GTelemetry.Warn("Log flush failed: " .. tostring(result))
        for _, v in ipairs(records) do
            table_insert(_logBuffer, v)
        end
        _bufferSize = #_logBuffer
    elseif not result then
        -- Send() returned false (backoff skip) — re-insert records to avoid data loss
        GTelemetry.Debug("Log flush skipped (backoff active), re-inserting " .. #records .. " records")
        for _, v in ipairs(records) do
            table_insert(_logBuffer, v)
        end
        _bufferSize = #_logBuffer
    end
    _isFlushing = false
end

--- Clear buffer without sending.
function GTelemetry.OTLP.Logs.ClearBuffer()
    _logBuffer = {}
    _bufferSize = 0
end
