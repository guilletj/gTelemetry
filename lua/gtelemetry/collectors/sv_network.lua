--[[
    gTelemetry: GMod Telemetry
    collectors/sv_network.lua — Network metrics

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Collects: per-player network bytes in/out aggregated, net message counts.
    Note: GMod's Lua API has limited native access to raw network I/O stats.
    This collector uses best-effort methods with available APIs.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Network = {}

-- Track net messages sent/received
local _netMessagesSent = 0
local _netMessagesReceived = 0
local _netMessagesSentByName = {}
local _netMessagesReceivedByName = {}
local _netDetailCount = 0  -- incremental counter for unique message names
local _startTimeNano = nil  -- for detail counters (reset on overflow)
local _startTimeNanoTotals = nil  -- for total counters (never reset)
local _initialized = false
local _cachedReceiverCount = nil
local _lastReceiverDetailCount = 0

-- Reset detail tables when they exceed this many entries to prevent unbounded growth.
-- Cumulative counters (_netMessagesSent/_netMessagesReceived) remain accurate.
local _maxDetailEntries = 1000
-- Capture GMod built-ins at module load to avoid stale references on re-init
local _realNetStart = net.Start
local _realNetReceive = net.Receive

local pairs = pairs
local ipairs = ipairs
local math_Round = math.Round
local MakeGauge = nil
local MakeDataPoint = nil
local MakeSum = nil
local MakeCumulativeDataPoint = nil
local Attribute = nil

function GTelemetry.Collectors.Network.Init()
    if _initialized then return end
    _initialized = true
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()
    _startTimeNanoTotals = _startTimeNano

    -- NOTE: These wrappers permanently override net.Start/net.Receive globally.
    -- Pre-existing net.Receive registrations (before this Init) are NOT counted.
    -- Also, every net.Start call is counted even if the message is never sent
    -- (no net.SendToServer / net.Broadcast follows).
    -- This is a best-effort measurement, not byte-exact accounting.

    -- Wrap net.Start to count outgoing messages
    net.Start = function(messageName, unreliable)
        _netMessagesSent = _netMessagesSent + 1
        local msgStr = tostring(messageName)
        if not _netMessagesSentByName[msgStr] then
            _netDetailCount = _netDetailCount + 1
        end
        _netMessagesSentByName[msgStr] = (_netMessagesSentByName[msgStr] or 0) + 1
        return _realNetStart(messageName, unreliable)
    end

    -- Track incoming messages via a hook on net.Receive registrations
    -- We increment a counter each time any net message is received
    net.Receive = function(messageName, callback)
        local msgStr = tostring(messageName)
        return _realNetReceive(messageName, function(len, ply)
            _netMessagesReceived = _netMessagesReceived + 1
            if not _netMessagesReceivedByName[msgStr] then
                _netDetailCount = _netDetailCount + 1
            end
            _netMessagesReceivedByName[msgStr] = (_netMessagesReceivedByName[msgStr] or 0) + 1
            return callback(len, ply)
        end)
    end

    GTelemetry.Debug("Network collector initialized with net.Start/Receive wrappers")
end

--- Restore original net.Start/net.Receive and reset counters.
function GTelemetry.Collectors.Network.Undo()
    net.Start = _realNetStart
    net.Receive = _realNetReceive
    _netMessagesSent = 0
    _netMessagesReceived = 0
    _netMessagesSentByName = {}
    _netMessagesReceivedByName = {}
    _startTimeNano = nil
    _startTimeNanoTotals = nil
    _initialized = false
    _netDetailCount = 0
    _cachedReceiverCount = nil
    _lastReceiverDetailCount = 0
    MakeGauge = nil
    MakeDataPoint = nil
    MakeSum = nil
    MakeCumulativeDataPoint = nil
    Attribute = nil
    GTelemetry.Debug("Network collector wrappers restored")
end

--- Collect network metrics.
-- @param players table|nil pre-cached player list from CollectAndSend
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Network.Collect(players)
    if not MakeGauge then GTelemetry.Collectors.Network.Init() end

    -- Failsafe: if another addon overwrote our wrappers, restore and stop counting
    if _initialized and net.Start ~= _realNetStart then
        GTelemetry.Warn("Network collector: net.Start was overwritten externally — restoring originals")
        GTelemetry.Collectors.Network.Undo()
        return {}
    end

    local metrics = {}

    -- Net messages sent (server → clients)
    metrics[#metrics + 1] = MakeSum(
        "gmod.network.net_messages_out",
        "Total net library messages sent by the server",
        "{messages}",
        {MakeCumulativeDataPoint(_netMessagesSent, _startTimeNanoTotals)},
        true
    )

    -- Net messages received (clients → server)
    metrics[#metrics + 1] = MakeSum(
        "gmod.network.net_messages_in",
        "Total net library messages received by the server",
        "{messages}",
        {MakeCumulativeDataPoint(_netMessagesReceived, _startTimeNanoTotals)},
        true
    )

    -- Reset detail name tables when they exceed _maxDetailEntries to prevent unbounded growth.
    -- Uses incrementally-updated count to avoid O(n) scan.
    if _netDetailCount > _maxDetailEntries then
        _netMessagesSentByName = {}
        _netMessagesReceivedByName = {}
        _netDetailCount = 0
        _startTimeNano = GTelemetry.OTLP.GetTimeNano()
    end

    -- Net messages sent per name (high cardinality — gated)
    if GTelemetry.Config.IsNetworkDetailsEnabled() then
        local outPoints = {}
        for msgName, count in pairs(_netMessagesSentByName) do
            outPoints[#outPoints + 1] = MakeCumulativeDataPoint(count, _startTimeNano, {
                Attribute("net.message", msgName)
            })
        end
        if #outPoints > 0 then
            metrics[#metrics + 1] = MakeSum(
                "gmod.network.messages_out_details",
                "Net library messages sent by the server per message name",
                "{messages}",
                outPoints,
                true
            )
        end

        -- Net messages received per name
        local inPoints = {}
        for msgName, count in pairs(_netMessagesReceivedByName) do
            inPoints[#inPoints + 1] = MakeCumulativeDataPoint(count, _startTimeNano, {
                Attribute("net.message", msgName)
            })
        end
        if #inPoints > 0 then
            metrics[#metrics + 1] = MakeSum(
                "gmod.network.messages_in_details",
                "Net library messages received by the server per message name",
                "{messages}",
                inPoints,
                true
            )
        end
    end

    -- Active Net Receivers (cached between cycles)
    if net.Receivers then
        if not _cachedReceiverCount or _netDetailCount ~= _lastReceiverDetailCount then
            _cachedReceiverCount = 0
            for _, _ in pairs(net.Receivers) do
                _cachedReceiverCount = _cachedReceiverCount + 1
            end
            _lastReceiverDetailCount = _netDetailCount
        end
        metrics[#metrics + 1] = MakeGauge(
            "gmod.network.active_receivers",
            "Total number of registered net message receivers",
            "{receivers}",
            {MakeDataPoint(_cachedReceiverCount)}
        )
    end

    -- Packet loss: single pass for both average and per-player
    players = players or player.GetAll()
    local totalLoss = 0
    local humanCount = 0
    local lossPoints = {}
    for _, ply in ipairs(players) do
        if IsValid(ply) and not ply:IsBot() then
            local loss = (ply.PacketLoss and ply:PacketLoss() or 0) * 100
            totalLoss = totalLoss + loss
            humanCount = humanCount + 1
            if loss > 0 then
                lossPoints[#lossPoints + 1] = MakeDataPoint(loss, {
                    Attribute("player.name", ply:Nick()),
                    Attribute("player.steam_id", ply:SteamID()),
                })
            end
        end
    end

    local avgLoss = humanCount > 0 and math_Round(totalLoss / humanCount, 2) or 0
    metrics[#metrics + 1] = MakeGauge(
        "gmod.network.packet_loss_avg",
        "Average packet loss percentage across all human players",
        "%",
        {MakeDataPoint(avgLoss)}
    )

    if #lossPoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.network.packet_loss",
            "Per-player packet loss percentage",
            "%",
            lossPoints
        )
    end

    return metrics
end
