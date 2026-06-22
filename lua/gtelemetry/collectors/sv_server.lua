--[[
    gTelemetry: GMod Telemetry
    collectors/sv_server.lua — Server performance metrics

    Collects: tick rate, frame time, FPS, Lua memory, uptime, max players.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Server = {}

local MakeGauge = nil
local MakeDataPoint = nil

--- Initialize references (called after OTLP module is loaded).
function GTelemetry.Collectors.Server.Init()
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
end

--- Collect server performance metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Server.Collect()
    if not MakeGauge then GTelemetry.Collectors.Server.Init() end

    local metrics = {}
    local tickInterval = engine.TickInterval()
    local frameTime = FrameTime()

    -- Tick rate (configured)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.tickrate",
        "Configured server tick rate",
        "Hz",
        {MakeDataPoint(math.Round(1 / tickInterval))}
    )

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

    -- Server FPS (derived from frame time, clamped to avoid infinity)
    local serverFPS = 0
    if frameTime > 0 then
        serverFPS = math.min(1 / frameTime, 1000)
    end
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.fps",
        "Server frames per second",
        "{fps}",
        {MakeDataPoint(math.Round(serverFPS, 2))}
    )

    -- Lua memory usage (in bytes)
    local luaMemoryKB = collectgarbage("count")
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.lua_memory",
        "Lua state memory usage",
        "By",
        {MakeDataPoint(math.floor(luaMemoryKB * 1024))}
    )

    -- Server uptime
    metrics[#metrics + 1] = MakeGauge(
        "gmod.server.uptime",
        "Server uptime since map load",
        "s",
        {MakeDataPoint(math.Round(CurTime(), 1))}
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

    return metrics
end
