--[[
    gTelemetry: GMod Telemetry
    collectors/sv_map.lua — Map & server info metrics

    Collects: server info label metric, map change counter.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Map = {}

-- Track map changes
local _mapChanges = 0
local _startTimeNano = nil
local _initialized = false

local MakeGauge = nil
local MakeDataPoint = nil
local MakeSum = nil
local MakeCumulativeDataPoint = nil
local Attribute = nil

function GTelemetry.Collectors.Map.Init()
    if _initialized then return end
    _initialized = true
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()

    -- Track map initialization
    hook.Add("InitPostEntity", "GTelemetry_MapInit", function()
        _mapChanges = _mapChanges + 1
        GTelemetry.Debug("Map initialized: " .. game.GetMap() .. " (change #" .. _mapChanges .. ")")
    end)
end

--- Collect map and server info metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Map.Collect()
    if not MakeGauge then GTelemetry.Collectors.Map.Init() end

    local metrics = {}

    local currentMap = game.GetMap() or "unknown"
    local gamemodeName = gmod.GetGamemode() and gmod.GetGamemode().Name or "unknown"
    local hostname = GetHostName and GetHostName() or "unknown"
    local serverIP = game.GetIPAddress and game.GetIPAddress() or "unknown"

    -- Server info (always value 1, metadata carried as labels)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.info",
        "Server information metric (value is always 1, metadata in labels)",
        "{info}",
        {MakeDataPoint(1, {
            Attribute("server.map", currentMap),
            Attribute("server.gamemode", gamemodeName),
            Attribute("server.hostname", hostname),
            Attribute("server.ip", serverIP),
        })}
    )

    -- Map changes counter
    metrics[#metrics + 1] = MakeSum(
        "gmod.map.changes",
        "Number of map changes since server process start",
        "{changes}",
        {MakeCumulativeDataPoint(_mapChanges, _startTimeNano)},
        true
    )

    return metrics
end
