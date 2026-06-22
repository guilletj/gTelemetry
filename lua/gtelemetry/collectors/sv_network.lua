--[[
    gTelemetry: GMod Telemetry
    collectors/sv_network.lua — Network metrics

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
local _startTimeNano = nil

local MakeGauge = nil
local MakeDataPoint = nil
local MakeSum = nil
local MakeCumulativeDataPoint = nil

function GTelemetry.Collectors.Network.Init()
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()

    -- Wrap net.Start to count outgoing messages
    local originalNetStart = net.Start
    net.Start = function(messageName, unreliable)
        _netMessagesSent = _netMessagesSent + 1
        local msgStr = tostring(messageName)
        _netMessagesSentByName[msgStr] = (_netMessagesSentByName[msgStr] or 0) + 1
        return originalNetStart(messageName, unreliable)
    end

    -- Track incoming messages via a hook on net.Receive registrations
    -- We increment a counter each time any net message is received
    local originalNetReceive = net.Receive
    net.Receive = function(messageName, callback)
        local msgStr = tostring(messageName)
        return originalNetReceive(messageName, function(len, ply)
            _netMessagesReceived = _netMessagesReceived + 1
            _netMessagesReceivedByName[msgStr] = (_netMessagesReceivedByName[msgStr] or 0) + 1
            return callback(len, ply)
        end)
    end

    GTelemetry.Debug("Network collector initialized with net.Start/Receive wrappers")
end

--- Collect network metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Network.Collect()
    if not MakeGauge then GTelemetry.Collectors.Network.Init() end

    local metrics = {}

    -- Aggregate per-player network stats
    local totalBytesIn = 0
    local totalBytesOut = 0

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and not ply:IsBot() then
            -- Player:PacketLoss() returns 0-100 percentage
            -- Player:Ping() is in ms (already tracked in players collector)
            -- There are no direct bytes_in/bytes_out Lua functions per player.
            -- We use net message count tracking as the best available proxy.
        end
    end

    -- Net messages sent (server → clients)
    metrics[#metrics + 1] = MakeSum(
        "gmod.network.net_messages_out",
        "Total net library messages sent by the server",
        "{messages}",
        {MakeCumulativeDataPoint(_netMessagesSent, _startTimeNano)},
        true
    )

    -- Net messages received (clients → server)
    metrics[#metrics + 1] = MakeSum(
        "gmod.network.net_messages_in",
        "Total net library messages received by the server",
        "{messages}",
        {MakeCumulativeDataPoint(_netMessagesReceived, _startTimeNano)},
        true
    )

    -- Net messages sent per name
    local outPoints = {}
    for msgName, count in pairs(_netMessagesSentByName) do
        outPoints[#outPoints + 1] = MakeCumulativeDataPoint(count, _startTimeNano, {
            GTelemetry.OTLP.Attribute("net.message", msgName)
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
            GTelemetry.OTLP.Attribute("net.message", msgName)
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

    -- Active Net Receivers
    if net.Receivers then
        local activeReceivers = 0
        for _, _ in pairs(net.Receivers) do
            activeReceivers = activeReceivers + 1
        end
        metrics[#metrics + 1] = MakeGauge(
            "gmod.network.active_receivers",
            "Total number of registered net message receivers",
            "{receivers}",
            {MakeDataPoint(activeReceivers)}
        )
    end

    -- Average packet loss across all players
    local players = player.GetAll()
    local totalLoss = 0
    local humanCount = 0
    for _, ply in ipairs(players) do
        if IsValid(ply) and not ply:IsBot() then
            totalLoss = totalLoss + (ply.PacketLoss and ply:PacketLoss() or 0)
            humanCount = humanCount + 1
        end
    end

    if humanCount > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.network.packet_loss_avg",
            "Average packet loss percentage across all human players",
            "%",
            {MakeDataPoint(math.Round(totalLoss / humanCount, 2))}
        )
    end

    -- Per-player packet loss
    local lossPoints = {}
    for _, ply in ipairs(players) do
        if IsValid(ply) and not ply:IsBot() and ply.PacketLoss then
            local loss = ply:PacketLoss()
            if loss > 0 then
                lossPoints[#lossPoints + 1] = MakeDataPoint(loss, {
                    GTelemetry.OTLP.Attribute("player.name", ply:Nick()),
                    GTelemetry.OTLP.Attribute("player.steam_id", ply:SteamID()),
                })
            end
        end
    end

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
