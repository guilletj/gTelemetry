--[[
    gTelemetry: GMod Telemetry
    collectors/sv_hooks.lua — Hook performance & error tracking

    Collects: total hook count, Think/Tick call count & timing, Lua errors,
    hook count per event type.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Hooks = {}

-- Performance tracking state
local _thinkCount = 0       -- Cumulative Think hook call count
local _tickCount = 0         -- Cumulative Tick hook call count
local _thinkTime = 0         -- Last Think hook execution time (seconds)
local _tickTime = 0          -- Last Tick hook execution time (seconds)
local _startThinkTime = 0    -- SysTime at start of Think chain
local _startTickTime = 0     -- SysTime at start of Tick chain
local _luaErrors = 0         -- Cumulative Lua error count
local _startTimeNano = nil
local _initialized = false

local MakeGauge = nil
local MakeDataPoint = nil
local MakeSum = nil
local MakeCumulativeDataPoint = nil
local Attribute = nil
local table_sort = table.sort

local _maxHookCardinality = 20  -- Max unique hook events to report

function GTelemetry.Collectors.Hooks.Init()
    if _initialized then return end
    _initialized = true

    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()

    -- Measure Think execution time via pre/post hooks.
    -- Priority 10 runs before all default-priority (0) hooks.
    -- Priority -10 runs after all default-priority hooks.
    hook.Add("Think", "GTelemetry_ThinkStart", function()
        _startThinkTime = SysTime()
    end, 10)

    hook.Add("Think", "GTelemetry_ThinkEnd", function()
        _thinkTime = SysTime() - _startThinkTime
        _thinkCount = _thinkCount + 1
    end, -10)

    -- Measure Tick execution time via pre/post hooks.
    hook.Add("Tick", "GTelemetry_TickStart", function()
        _startTickTime = SysTime()
    end, 10)

    hook.Add("Tick", "GTelemetry_TickEnd", function()
        _tickTime = SysTime() - _startTickTime
        _tickCount = _tickCount + 1
    end, -10)

    -- Track Lua errors
    hook.Add("OnLuaError", "GTelemetry_LuaErrors", function(error, realm, stack, name, id)
        _luaErrors = _luaErrors + 1
    end)

    GTelemetry.Debug("Hooks collector initialized")
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

    -- Think hook calls (cumulative counter)
    metrics[#metrics + 1] = MakeSum(
        "gmod.hooks.think_total",
        "Cumulative count of Think hook executions since server start",
        "{calls}",
        {MakeCumulativeDataPoint(_thinkCount, _startTimeNano)},
        true
    )

    -- Tick hook calls (cumulative counter)
    metrics[#metrics + 1] = MakeSum(
        "gmod.hooks.tick_total",
        "Cumulative count of Tick hook executions since server start",
        "{calls}",
        {MakeCumulativeDataPoint(_tickCount, _startTimeNano)},
        true
    )

    -- Think hook execution time (last frame)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.hooks.think_time",
        "Time spent executing Think hooks in the last frame",
        "s",
        {MakeDataPoint(math.Round(_thinkTime, 6))}
    )

    -- Tick hook execution time (last tick)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.hooks.tick_time",
        "Time spent executing Tick hooks in the last tick",
        "s",
        {MakeDataPoint(math.Round(_tickTime, 6))}
    )

    -- Lua errors (cumulative counter)
    metrics[#metrics + 1] = MakeSum(
        "gmod.lua.errors",
        "Cumulative count of Lua errors since server start",
        "{errors}",
        {MakeCumulativeDataPoint(_luaErrors, _startTimeNano)},
        true
    )

    -- Hooks by event (limited cardinality)
    local eventPoints = {}
    local sortedEvents = {}
    for eventName, count in pairs(eventCounts) do
        if count >= 2 then
            sortedEvents[#sortedEvents + 1] = {name = eventName, count = count}
        end
    end
    table_sort(sortedEvents, function(a, b) return a.count > b.count end)
    for i = 1, math.min(#sortedEvents, _maxHookCardinality) do
        local ev = sortedEvents[i]
        eventPoints[#eventPoints + 1] = MakeDataPoint(ev.count, {
            Attribute("hook.event", ev.name),
        })
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
