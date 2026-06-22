--[[
    gTelemetry: GMod Telemetry
    sv_otlp.lua — OTLP/HTTP JSON builder & transport

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

-- Track the SysTime offset to get nanosecond-precision timestamps
-- os.time() gives epoch seconds, SysTime() gives high-res relative time
local _epochOffset = os_time() - SysTime()

-- Cooldown counter to avoid console spam on persistent failures
local _consecutiveFailures = 0
local _maxFailuresBeforeSkip = 5

-- Guard to prevent concurrent collection cycles from stacking
local _isCollecting = false

--- Returns the current time in nanoseconds since Unix epoch as a string.
-- OTLP requires timestamps as nanosecond strings.
-- @return string nanosecond timestamp
function GTelemetry.OTLP.GetTimeNano()
    local epochSeconds = _epochOffset + SysTime()
    -- Convert to nanoseconds: seconds * 1e9
    -- We use string.format to avoid floating point precision issues
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
        -- Check if integer or float
        if value == math.floor(value) then
            otlpValue = {intValue = tostring(value)}
        else
            otlpValue = {doubleValue = value}
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
    local timeNano = GTelemetry.OTLP.GetTimeNano()
    local dp = {
        timeUnixNano = timeNano,
    }

    -- Set value type
    if value == math.floor(value) and value < 1e15 and value > -1e15 then
        dp.asInt = tostring(value)
    else
        dp.asDouble = value
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

    local payload = {
        resourceMetrics = {
            {
                resource = {
                    attributes = {
                        GTelemetry.OTLP.Attribute("service.name", serviceName),
                        GTelemetry.OTLP.Attribute("service.version", GTelemetry.Version or "1.0.0"),
                        GTelemetry.OTLP.Attribute("host.name", hostname),
                        GTelemetry.OTLP.Attribute("gmod.map", currentMap),
                        GTelemetry.OTLP.Attribute("gmod.gamemode", (engine.ActiveGamemode and engine.ActiveGamemode()) or (gmod.GetGamemode() and gmod.GetGamemode().Name) or "unknown"),
                    },
                },
                scopeMetrics = {
                    {
                        scope = {
                            name = "gTelemetry",
                            version = GTelemetry.Version or "1.0.0",
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
        GTelemetry.Warn("No endpoint configured. Set gtelemetry_endpoint ConVar.")
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

    -- Skip sending after persistent failures to avoid console spam
    if _consecutiveFailures >= _maxFailuresBeforeSkip then
        GTelemetry.Debug("Skipping send (" .. _consecutiveFailures .. " consecutive failures)")
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
                _consecutiveFailures = 0
                GTelemetry.Debug("Metrics sent successfully (HTTP " .. code .. ")")
            else
                _consecutiveFailures = _consecutiveFailures + 1
                GTelemetry.Warn("Alloy returned HTTP " .. code .. ": " .. (body or "no body"))
            end
        end,

        failed = function(err)
            _consecutiveFailures = _consecutiveFailures + 1
            GTelemetry.Warn("Failed to send metrics: " .. tostring(err))
            GTelemetry.Warn("Ensure Alloy is running and the server was started with -allowlocalhttp")
        end,
    })
end

--- Collect all metrics from registered collectors, build, and send the payload.
-- This is the main function called by the collection timer.
function GTelemetry.OTLP.CollectAndSend()
    if not GTelemetry.Config.IsEnabled() then return end
    if _isCollecting then
        GTelemetry.Debug("Skipping collection — previous cycle still in progress")
        return
    end
    _isCollecting = true
    local startWall = SysTime()

    local allMetrics = {}
    local collectorCount = 0

    for name, collector in pairs(GTelemetry.Collectors) do
        if collector.Collect then
            local ok, metrics = pcall(collector.Collect)
            if ok and metrics then
                for _, metric in ipairs(metrics) do
                    table_insert(allMetrics, metric)
                end
                collectorCount = collectorCount + 1
            elseif not ok then
                GTelemetry.Warn("Collector '" .. name .. "' failed: " .. tostring(metrics))
            end
        end
    end

    if #allMetrics == 0 then
        GTelemetry.Debug("No metrics collected from " .. collectorCount .. " collectors")
        _isCollecting = false
        return
    end

    GTelemetry.Debug("Collected " .. #allMetrics .. " metrics from " .. collectorCount .. " collectors")

    local jsonBody = GTelemetry.OTLP.BuildPayload(allMetrics)
    GTelemetry.OTLP.Send(jsonBody)

    GTelemetry.LastCollectionDuration = SysTime() - startWall
    _isCollecting = false
end
