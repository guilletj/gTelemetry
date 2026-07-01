--[[
    gTelemetry: GMod Telemetry
    collectors/sv_map.lua — Map & server info metrics

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Collects: server info label metric, map change counter.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Map = {}

-- Track map changes
local _mapChanges = 0
local _mapChangesAtInit = 0
local _startTimeNano = nil
local _initialized = false
local _mapCountedThisLoad = false

local MakeGauge = nil
local MakeDataPoint = nil
local MakeSum = nil
local MakeCumulativeDataPoint = nil
local Attribute = nil

--- Manually increment the map change counter.
-- Used by the late-init path when InitPostEntity has already fired.
function GTelemetry.Collectors.Map.CountChange()
    if _mapCountedThisLoad then return end
    _mapCountedThisLoad = true
    _mapChanges = _mapChanges + 1
    GTelemetry.Debug("Map counted externally: " .. game.GetMap() .. " (change #" .. _mapChanges .. ")")
end

function GTelemetry.Collectors.Map.Init()
    if _initialized then return end
    _initialized = true
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
    hook.Add("InitPostEntity", "GTelemetry_MapInit", function()
        _mapChanges = _mapChanges + 1
        GTelemetry.Debug("Map initialized: " .. game.GetMap() .. " (change #" .. _mapChanges .. ")")
    end)

    GTelemetry.Collectors.Map.CountChange()
    _mapChangesAtInit = _mapChanges
end

function GTelemetry.Collectors.Map.Undo()
    if not _initialized then return end
    _initialized = false
    hook.Remove("InitPostEntity", "GTelemetry_MapInit")
    _mapChanges = 0
    _startTimeNano = nil
    _mapChangesAtInit = 0
    _mapCountedThisLoad = false
    MakeGauge = nil
    MakeDataPoint = nil
    MakeSum = nil
    MakeCumulativeDataPoint = nil
    Attribute = nil
end

--- Collect map and server info metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Map.Collect()
    if not MakeGauge then GTelemetry.Collectors.Map.Init() end

    local metrics = {}

    local currentMap = game.GetMap() or "unknown"
    local gm = gmod.GetGamemode()
    local gamemodeName = gm and gm.Name or "unknown"
    if not GTelemetry.OTLP._cachedHostname then GTelemetry.OTLP._cachedHostname = GetHostName and GetHostName() or "unknown" end

    -- Server info (always value 1, metadata carried as labels)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.info",
        "Server information metric (value is always 1, metadata in labels)",
        "{info}",
        {MakeDataPoint(1, {
            Attribute("server.map", currentMap),
            Attribute("server.gamemode", gamemodeName),
            Attribute("server.hostname", GTelemetry.OTLP._cachedHostname),
        })}
    )

    -- Map changes counter
    metrics[#metrics + 1] = MakeSum(
        "gmod.map.changes",
        "Number of map changes since server process start",
        "{changes}",
        {MakeCumulativeDataPoint(_mapChanges - _mapChangesAtInit, _startTimeNano)},
        true
    )

    return metrics
end
