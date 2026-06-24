--[[
    gTelemetry: GMod Telemetry
    sv_otlp.lua — OTLP/HTTP JSON builder & transport

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Builds ExportMetricsServiceRequest payloads in OTLP JSON format
    and sends them to a Grafana Alloy otelcol.receiver.otlp endpoint.
]]

GTelemetry.OTLP = GTelemetry.OTLP or {}

-- Cache for performance
local util_TableToJSON = util.TableToJSON
local SysTime = SysTime
local os_time = os.time
local tostring = tostring
local string_format = string.format
local table_insert = table.insert
local pairs = pairs
local ipairs = ipairs
local math_floor = math.floor

-- Capture SysTime and os.time at module load to compute accurate Unix time
-- without drifting into the future: epoch = _epochAtLoad + (SysTime() - _sysTimeStart)
local _sysTimeStart = SysTime()
local _epochAtLoad = os_time()

-- Health counters exposed to sv_server for metric emission
GTelemetry.OTLP.CollectionErrors = 0
GTelemetry.OTLP.SendFailures = 0

-- Cached timestamp for one collection cycle (avoid 200+ GetTimeNano calls)
GTelemetry.OTLP._cycleTimeNano = nil

-- Exponential backoff for HTTP retries
local _backoffAttempts = 0
local _nextSendTime = 0
local _maxBackoff = 30
local _cachedGamemode = nil

-- Reset gamemode cache when the gamemode changes
hook.Add("gamemode.PostGamemodeLoaded", "GTelemetry_GamemodeCache", function()
    _cachedGamemode = nil
end)

-- Guard to prevent concurrent collection cycles from stacking
local _isCollecting = false

--- Returns the current time in nanoseconds since Unix epoch as a string.
-- OTLP requires timestamps as nanosecond strings.
-- Uses _epochAtLoad captured at module load to avoid drifting into the future.
-- SysTime() only provides the fractional sub-second offset.
-- @return string nanosecond timestamp
function GTelemetry.OTLP.GetTimeNano()
    local now = SysTime()
    local epochSeconds = _epochAtLoad + (now - _sysTimeStart)
    return string_format("%.0f", epochSeconds * 1e9)
end

--- Create an OTLP attribute object.
-- @param key string attribute key
-- @param value any attribute value
-- @return table OTLP attribute
function GTelemetry.OTLP.Attribute(key, value)
    local valType = type(value)
    local otlpValue

    if valType == "number" then
        -- Check if finite, then if integer or float
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

--- Create a data point for a metric.
-- @param value number the metric value
-- @param attributes table|nil optional list of OTLP attributes
-- @return table OTLP data point
function GTelemetry.OTLP.MakeDataPoint(value, attributes)
    local timeNano = GTelemetry.OTLP._cycleTimeNano or GTelemetry.OTLP.GetTimeNano()
    local dp = {
        timeUnixNano = timeNano,
    }

    -- Set value type (NaN/Inf fall back to int = 0 for JSON safety)
    if value < math.huge and value > -math.huge then
        if value == math_floor(value) and value < 1e15 and value > -1e15 then
            dp.asInt = string_format("%.0f", value)
        else
            dp.asDouble = value
        end
    else
        dp.asInt = "0"
    end

    if attributes and #attributes > 0 then
        dp.attributes = attributes
    end

    return dp
end

--- Create a data point for a cumulative sum metric (includes startTimeUnixNano).
-- @param value number the cumulative value
-- @param startTimeNano string the start time in nanoseconds
-- @param attributes table|nil optional list of OTLP attributes
-- @return table OTLP data point
function GTelemetry.OTLP.MakeCumulativeDataPoint(value, startTimeNano, attributes)
    local dp = GTelemetry.OTLP.MakeDataPoint(value, attributes)
    dp.startTimeUnixNano = startTimeNano
    return dp
end

--- Create a Gauge metric.
-- @param name string metric name (e.g., "gmod.server.fps")
-- @param description string human-readable description
-- @param unit string metric unit (e.g., "By", "s", "{fps}")
-- @param dataPoints table list of data points
-- @return table OTLP metric object
function GTelemetry.OTLP.MakeGauge(name, description, unit, dataPoints)
    return {
        name = name,
        description = description,
        unit = unit,
        gauge = {
            dataPoints = dataPoints,
        },
    }
end

--- Create a Sum (counter) metric.
-- @param name string metric name
-- @param description string human-readable description
-- @param unit string metric unit
-- @param dataPoints table list of data points
-- @param isMonotonic boolean whether the counter only goes up
-- @return table OTLP metric object
function GTelemetry.OTLP.MakeSum(name, description, unit, dataPoints, isMonotonic)
    return {
        name = name,
        description = description,
        unit = unit,
        sum = {
            -- aggregationTemporality: 2 = CUMULATIVE
            aggregationTemporality = 2,
            isMonotonic = isMonotonic or false,
            dataPoints = dataPoints,
        },
    }
end

--- Build the full ExportMetricsServiceRequest payload.
-- @param metrics table list of OTLP metric objects from collectors
-- @return string JSON-encoded payload
function GTelemetry.OTLP.BuildPayload(metrics)
    local hostname = GetHostName and GetHostName() or "unknown"
    local currentMap = game.GetMap() or "unknown"
    local serviceName = GTelemetry.Config.GetServiceName()

    if not _cachedGamemode then
        _cachedGamemode = (engine.ActiveGamemode and engine.ActiveGamemode()) or (gmod.GetGamemode() and gmod.GetGamemode().Name) or "unknown"
    end

    local payload = {
        resourceMetrics = {
            {
                resource = {
                    attributes = {
                        GTelemetry.OTLP.Attribute("service.name", serviceName),
                        GTelemetry.OTLP.Attribute("service.version", GTelemetry.Version or "1.5.0"),
                        GTelemetry.OTLP.Attribute("host.name", hostname),
                        GTelemetry.OTLP.Attribute("gmod.map", currentMap),
                        GTelemetry.OTLP.Attribute("gmod.gamemode", _cachedGamemode),
                    },
                },
                scopeMetrics = {
                    {
                        scope = {
                            name = "gTelemetry",
                            version = GTelemetry.Version or "1.5.0",
                        },
                        metrics = metrics,
                    },
                },
            },
        },
    }

    return util_TableToJSON(payload)
end

--- Send the OTLP payload to the configured endpoint.
-- @param jsonBody string JSON-encoded ExportMetricsServiceRequest
function GTelemetry.OTLP.Send(jsonBody)
    local endpoint = GTelemetry.Config.GetEndpoint()
    if not endpoint or endpoint == "" then
        return
    end

    local headers = {
        ["Content-Type"] = "application/json",
    }

    -- Add auth token if configured
    local token = GTelemetry.Config.GetAuthToken()
    if token then
        headers["Authorization"] = "Bearer " .. token
    end

    -- Exponential backoff: skip if still in cooldown window
    if SysTime() < _nextSendTime then
        GTelemetry.Debug("Skipping send (backoff active, next in " .. math.ceil(_nextSendTime - SysTime()) .. "s)")
        return
    end

    GTelemetry.Debug("Sending metrics to: " .. endpoint .. " (" .. #jsonBody .. " bytes)")

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
                GTelemetry.Debug("Metrics sent successfully (HTTP " .. code .. ")")
            else
                _backoffAttempts = _backoffAttempts + 1
                _nextSendTime = SysTime() + math.min(2 ^ _backoffAttempts, _maxBackoff)
                GTelemetry.OTLP.SendFailures = GTelemetry.OTLP.SendFailures + 1
                GTelemetry.Warn("Alloy returned HTTP " .. code .. ": " .. (body or "no body"))
            end
        end,

        failed = function(err)
            _backoffAttempts = _backoffAttempts + 1
            _nextSendTime = SysTime() + math.min(2 ^ _backoffAttempts, _maxBackoff)
            GTelemetry.OTLP.SendFailures = GTelemetry.OTLP.SendFailures + 1
            GTelemetry.Warn("Failed to send metrics: " .. tostring(err))
            GTelemetry.Warn("Ensure Alloy is running and the server was started with -allowlocalhttp")
        end,
    })
end

--- Collect all metrics from registered collectors, build, and send the payload.
-- This is the main function called by the collection timer.
-- The body is wrapped in pcall so _isCollecting is always reset, preventing
-- the guard from getting stuck permanently on unexpected errors.
function GTelemetry.OTLP.CollectAndSend()
    if not GTelemetry.Config.IsEnabled() then return end
    if _isCollecting then
        GTelemetry.Debug("Skipping collection — previous cycle still in progress")
        return
    end
    _isCollecting = true

    GTelemetry.Debug("Collection cycle started")

    local ok, err = pcall(function()
        GTelemetry.OTLP._cycleTimeNano = GTelemetry.OTLP.GetTimeNano()
        local startWall = SysTime()

        local allMetrics = {}
        local collectorCount = 0

        for name, collector in pairs(GTelemetry.Collectors) do
            if collector.Collect then
                local ok2, result = pcall(collector.Collect)
                if ok2 and result then
                    local count = #result
                    GTelemetry.Debug("Collector '" .. name .. "' returned " .. count .. " metrics")
                    for _, metric in ipairs(result) do
                        table_insert(allMetrics, metric)
                    end
                    collectorCount = collectorCount + 1
                elseif not ok2 then
                    GTelemetry.OTLP.CollectionErrors = GTelemetry.OTLP.CollectionErrors + 1
                    GTelemetry.Warn("Collector '" .. name .. "' failed: " .. tostring(result))
                else
                    GTelemetry.Debug("Collector '" .. name .. "' returned nil (skipped)")
                end
            end
        end

        if #allMetrics == 0 then
            GTelemetry.Debug("No metrics collected from " .. collectorCount .. " collectors")
            GTelemetry.Debug("Total collectors: " .. table.Count(GTelemetry.Collectors))
            return
        end

        GTelemetry.Debug("Collected " .. #allMetrics .. " metrics from " .. collectorCount .. " collectors")

        local jsonBody = GTelemetry.OTLP.BuildPayload(allMetrics)
        GTelemetry.OTLP.Send(jsonBody)

        GTelemetry.LastCollectionDuration = SysTime() - startWall
    end)

    if not ok then
        GTelemetry.Warn("CollectAndSend failed: " .. tostring(err))
    end
    GTelemetry.OTLP._cycleTimeNano = nil
    _isCollecting = false
end
