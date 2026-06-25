--[[
    gTelemetry: GMod Telemetry
    collectors/sv_server.lua — Server performance metrics

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Collects: tick rate, frame time, FPS, Lua memory, uptime, max players.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Server = {}

local MakeGauge = nil
local MakeDataPoint = nil
local MakeSum = nil
local MakeCumulativeDataPoint = nil
local _startTimeNano = nil
local _initialized = false
local math_floor = math.floor
local math_Round = math.Round
local math_min = math.min

--- Initialize references (called after OTLP module is loaded).
function GTelemetry.Collectors.Server.Init()
    if _initialized then return end
    _initialized = true
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()
end

function GTelemetry.Collectors.Server.Undo()
    if not _initialized then return end
    _initialized = false
    MakeGauge = nil
    MakeDataPoint = nil
    MakeSum = nil
    MakeCumulativeDataPoint = nil
    _startTimeNano = nil
end

--- Collect server performance metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Server.Collect()
    if not MakeGauge then GTelemetry.Collectors.Server.Init() end

    local metrics = {}
    local tickInterval = engine.TickInterval()
    local frameTime = FrameTime()
    local curTime = CurTime()

    -- Tick rate (configured)
    if tickInterval and tickInterval > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.server.tickrate",
            "Configured server tick rate",
            "Hz",
            {MakeDataPoint(math_Round(1 / tickInterval))}
        )
    end

    -- Tick interval
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.tick_interval",
        "Time between server ticks",
        "s",
        {MakeDataPoint(tickInterval)}
    )

    -- Server frame time (actual time the last frame took)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.frametime",
        "Actual server frame time",
        "s",
        {MakeDataPoint(frameTime)}
    )

    -- Tick duration ratio (frameTime / tickInterval — how loaded the server is)
    -- > 1.0 means the server cannot keep up with the configured tick rate
    if tickInterval > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.server.tick_duration",
            "Ratio of frame time to tick interval — server load indicator. >1 means overloaded.",
            "{ratio}",
            {MakeDataPoint(math_Round(frameTime / tickInterval, 4))}
        )
    end

    -- Server FPS (derived from frame time, clamped to avoid infinity)
    local serverFPS = 0
    if frameTime > 0 then
        serverFPS = math_min(1 / frameTime, 1000)
    end
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.fps",
        "Server frames per second",
        "{fps}",
        {MakeDataPoint(math_Round(serverFPS, 2))}
    )

    -- Lua memory usage (in bytes)
    local luaMemoryKB = collectgarbage("count")
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.lua_memory",
        "Lua state memory usage",
        "By",
        {MakeDataPoint(math_floor(luaMemoryKB * 1024))}
    )

    -- Server uptime
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.uptime",
        "Server uptime since map load",
        "s",
        {MakeDataPoint(math_Round(curTime, 1))}
    )

    -- Max players
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.max_players",
        "Maximum player slots on the server",
        "{players}",
        {MakeDataPoint(game.MaxPlayers())}
    )

    -- Telemetry health indicator (always 1 if this metric is being emitted)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.telemetry.active",
        "Indicates gTelemetry is active and collecting (always 1)",
        "{flag}",
        {MakeDataPoint(1)}
    )

    -- Time spent collecting and sending metrics in the last cycle
    if GTelemetry.LastCollectionDuration then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.server.collection_duration",
            "Time spent collecting and sending metrics in the last cycle",
            "s",
            {MakeDataPoint(GTelemetry.LastCollectionDuration)}
        )
    end

    -- Cumulative collector errors (from sv_otlp)
    metrics[#metrics + 1] = MakeSum(
        "gmod.telemetry.collection_errors",
        "Cumulative number of collector errors since server start",
        "{errors}",
        {MakeCumulativeDataPoint(GTelemetry.OTLP.CollectionErrors or 0, _startTimeNano)},
        true
    )

    -- Cumulative send failures (from sv_otlp)
    metrics[#metrics + 1] = MakeSum(
        "gmod.telemetry.send_failures",
        "Cumulative number of HTTP send failures since server start",
        "{failures}",
        {MakeCumulativeDataPoint(GTelemetry.OTLP.SendFailures or 0, _startTimeNano)},
        true
    )

    return metrics
end
