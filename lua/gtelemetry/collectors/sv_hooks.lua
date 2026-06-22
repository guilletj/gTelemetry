--[[
    gTelemetry: GMod Telemetry
    collectors/sv_hooks.lua — Hook performance & error tracking

    Collects: total hook count, Think/Tick execution time, Lua errors,
    hook count per event type.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Hooks = {}

-- Performance tracking state
local _thinkTime = 0      -- Last measured Think hook execution time
local _tickTime = 0        -- Last measured Tick hook execution time
local _luaErrors = 0       -- Cumulative Lua error count
local _startTimeNano = nil
local _initialized = false

local MakeGauge = nil
local MakeDataPoint = nil
local MakeSum = nil
local MakeCumulativeDataPoint = nil
local Attribute = nil

function GTelemetry.Collectors.Hooks.Init()
    if _initialized then return end
    _initialized = true

    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()

    -- Measure Think hook total time
    -- We add a high-priority pre/post wrapper around Think
    local thinkStartTime = 0
    hook.Add("Think", "GTelemetry_ThinkPre", function()
        if not GTelemetry.Config.IsEnabled() then return end
        thinkStartTime = SysTime()
    end)

    -- PostThink-like measurement: use a timer that runs every tick
    -- to capture the Think hook duration from the previous frame
    timer.Create("GTelemetry_ThinkMeasure", 0, 0, function()
        if thinkStartTime > 0 then
            _thinkTime = SysTime() - thinkStartTime
        end
    end)

    -- Measure Tick hook total time
    local tickStartTime = 0
    hook.Add("Tick", "GTelemetry_TickPre", function()
        if not GTelemetry.Config.IsEnabled() then return end
        tickStartTime = SysTime()
    end)

    timer.Create("GTelemetry_TickMeasure", engine.TickInterval(), 0, function()
        if tickStartTime > 0 then
            _tickTime = SysTime() - tickStartTime
        end
    end)

    -- Track Lua errors
    hook.Add("OnLuaError", "GTelemetry_LuaErrors", function(error, realm, stack, name, id)
        _luaErrors = _luaErrors + 1
    end)

    GTelemetry.Debug("Hooks collector initialized with Think/Tick profiling")
end

--- Count total hooks and hooks per event from the hook table.
-- @return number totalHooks
-- @return table eventCounts — {[eventName] = count}
local function CountHooks()
    local hookTable = hook.GetTable()
    local totalHooks = 0
    local eventCounts = {}

    for eventName, hooks in pairs(hookTable) do
        local count = 0
        for _ in pairs(hooks) do
            count = count + 1
        end
        totalHooks = totalHooks + count
        eventCounts[eventName] = count
    end

    return totalHooks, eventCounts
end

--- Collect hook performance metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Hooks.Collect()
    if not MakeGauge then GTelemetry.Collectors.Hooks.Init() end

    local metrics = {}
    local totalHooks, eventCounts = CountHooks()

    -- Total hook count
    metrics[#metrics + 1] = MakeGauge(
        "gmod.hooks.count",
        "Total number of registered hooks",
        "{hooks}",
        {MakeDataPoint(totalHooks)}
    )

    -- Think hook execution time
    metrics[#metrics + 1] = MakeGauge(
        "gmod.hooks.think_time",
        "Time spent executing Think hooks",
        "s",
        {MakeDataPoint(_thinkTime)}
    )

    -- Tick hook execution time
    metrics[#metrics + 1] = MakeGauge(
        "gmod.hooks.tick_time",
        "Time spent executing Tick hooks",
        "s",
        {MakeDataPoint(_tickTime)}
    )

    -- Lua errors (cumulative counter)
    metrics[#metrics + 1] = MakeSum(
        "gmod.lua.errors",
        "Cumulative count of Lua errors since server start",
        "{errors}",
        {MakeCumulativeDataPoint(_luaErrors, _startTimeNano)},
        true
    )

    -- Hooks by event (top events only, to avoid excessive cardinality)
    local eventPoints = {}
    for eventName, count in pairs(eventCounts) do
        if count >= 2 then -- Only report events with 2+ hooks to limit cardinality
            eventPoints[#eventPoints + 1] = MakeDataPoint(count, {
                Attribute("hook.event", eventName),
            })
        end
    end

    if #eventPoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.hooks.by_event",
            "Number of hooks registered per event type",
            "{hooks}",
            eventPoints
        )
    end

    return metrics
end
