--[[
    gTelemetry: GMod Telemetry
    collectors/sv_players.lua — Player metrics + client FPS data receiver

    Collects: player count, bots, pings, client FPS, kills, deaths, connection time, load time.
    Receives client-side FPS data via the net library.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Players = {}

local ipairs = ipairs

-- Per-player state tracking
local _playerData = {} -- [SteamID] = { fps, kills, deaths, connectTime, loadStart, loadTime }
local _startTimeNano = nil
local _initialized = false
local _clientLoadTimeout = 120 -- seconds before marking a missing ClientReady as timed out
local math_Round = math.Round

local MakeGauge = nil
local MakeDataPoint = nil
local MakeSum = nil
local MakeCumulativeDataPoint = nil
local Attribute = nil

-- Register net messages for client data (must be outside Init to avoid race conditions)
util.AddNetworkString("GTelemetry_ClientData")
util.AddNetworkString("GTelemetry_ClientReady")

net.Receive("GTelemetry_ClientData", function(len, ply)
    if not IsValid(ply) then return end
    if ply:IsBot() then return end
    local steamID = ply:SteamID()
    if not _playerData[steamID] then
        _playerData[steamID] = {fps = 0, kills = 0, deaths = 0, connectTime = CurTime(), loadStart = SysTime(), loadTime = nil}
    end
    local fps = net.ReadFloat()
    if fps then
        _playerData[steamID].fps = fps
    end
end)

-- Client signals that its code is loaded and the player is ready to play
net.Receive("GTelemetry_ClientReady", function(len, ply)
    if not IsValid(ply) then return end
    if ply:IsBot() then return end
    local steamID = ply:SteamID()
    if not _playerData[steamID] then
        _playerData[steamID] = {fps = 0, kills = 0, deaths = 0, connectTime = CurTime(), loadStart = SysTime(), loadTime = nil}
    end
    local data = _playerData[steamID]
    if data and not data.loadTime then
        data.loadTime = math_Round(SysTime() - data.loadStart, 2)
    end
end)

--- Initialize references and hooks.
function GTelemetry.Collectors.Players.Init()
    if _initialized then return end
    _initialized = true
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()


    -- Track kills and deaths
    hook.Add("PlayerDeath", "GTelemetry_PlayerDeath", function(victim, inflictor, attacker)
        if IsValid(victim) then
            local vid = victim:SteamID()
            if _playerData[vid] then
                _playerData[vid].deaths = _playerData[vid].deaths + 1
            end
        end

        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
            local aid = attacker:SteamID()
            if _playerData[aid] then
                _playerData[aid].kills = _playerData[aid].kills + 1
            end
        end
    end)

    -- Track player connections
    hook.Add("PlayerInitialSpawn", "GTelemetry_PlayerConnect", function(ply)
        local steamID = ply:SteamID()
        _playerData[steamID] = _playerData[steamID] or {
            fps = 0,
            kills = 0,
            deaths = 0,
            connectTime = CurTime(),
            loadStart = SysTime(),
            loadTime = nil,
        }
    end)

    -- Clean up on disconnect
    hook.Add("PlayerDisconnected", "GTelemetry_PlayerDisconnect", function(ply)
        local steamID = ply:SteamID()
        _playerData[steamID] = nil
    end)

end

--- Collect player metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Players.Collect()
    if not MakeGauge then GTelemetry.Collectors.Players.Init() end

    local metrics = {}
    local players = player.GetAll()
    local playerCount = player.GetCount()
    local botCount = 0
    local totalPing = 0
    local pingPoints = {}
    local fpsPoints = {}
    local killPoints = {}
    local deathPoints = {}
    local connectionPoints = {}
    local loadTimePoints = {}

    for _, ply in ipairs(players) do
        if not IsValid(ply) then continue end

        if ply:IsBot() then
            botCount = botCount + 1
            continue
        end

        local steamID = ply:SteamID()
        local playerName = ply:Nick()
        local ping = ply:Ping()
        totalPing = totalPing + ping

        local attrs = {
            Attribute("player.name", playerName),
            Attribute("player.steam_id", steamID),
        }

        -- Per-player ping
        pingPoints[#pingPoints + 1] = MakeDataPoint(ping, attrs)

        -- Per-player data from tracking table
        local data = _playerData[steamID]
        if data then
            -- Client FPS (if received)
            if data.fps > 0 then
                fpsPoints[#fpsPoints + 1] = MakeDataPoint(math_Round(data.fps, 1), attrs)
            end

            -- Kills
            killPoints[#killPoints + 1] = MakeCumulativeDataPoint(data.kills, _startTimeNano, attrs)

            -- Deaths
            deathPoints[#deathPoints + 1] = MakeCumulativeDataPoint(data.deaths, _startTimeNano, attrs)

            -- Connection time
            local connTime = CurTime() - data.connectTime
            connectionPoints[#connectionPoints + 1] = MakeDataPoint(math_Round(connTime, 1), attrs)

            -- Load time (reported once, after first spawn)
            if data.loadTime then
                if data.loadTime > 0 then
                    loadTimePoints[#loadTimePoints + 1] = MakeDataPoint(data.loadTime, attrs)
                end
            elseif CurTime() - data.connectTime > _clientLoadTimeout then
                data.loadTime = -1
                GTelemetry.Debug("Player '" .. playerName .. "' (" .. steamID .. ") did not send ClientReady within " .. _clientLoadTimeout .. "s")
            end
        end
    end

    -- Player count
    metrics[#metrics + 1] = MakeGauge(
        "gmod.players.count",
        "Number of connected players",
        "{players}",
        {MakeDataPoint(playerCount)}
    )

    -- Bot count
    metrics[#metrics + 1] = MakeGauge(
        "gmod.players.bots",
        "Number of connected bots",
        "{players}",
        {MakeDataPoint(botCount)}
    )

    -- Per-player pings
    if #pingPoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.players.ping",
            "Per-player ping to server",
            "ms",
            pingPoints
        )
    end

    -- Average ping
    local humanCount = playerCount - botCount
    if humanCount > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.players.ping_avg",
            "Average ping across all human players",
            "ms",
            {MakeDataPoint(math_Round(totalPing / humanCount, 1))}
        )
    end

    -- Client FPS
    if #fpsPoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.players.client_fps",
            "Client-reported FPS per player",
            "{fps}",
            fpsPoints
        )
    end

    -- Kills (cumulative counter)
    if #killPoints > 0 then
        metrics[#metrics + 1] = MakeSum(
            "gmod.players.kills",
            "Total kills per player since server start",
            "{kills}",
            killPoints,
            true
        )
    end

    -- Deaths (cumulative counter)
    if #deathPoints > 0 then
        metrics[#metrics + 1] = MakeSum(
            "gmod.players.deaths",
            "Total deaths per player since server start",
            "{deaths}",
            deathPoints,
            true
        )
    end

    -- Connection time
    if #connectionPoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.players.connection_time",
            "Time since player connected",
            "s",
            connectionPoints
        )
    end

    -- Load time (time from PlayerInitialSpawn to client-ready signal)
    if #loadTimePoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.players.load_time",
            "Time from connect to client fully loaded",
            "s",
            loadTimePoints
        )
    end

    return metrics
end
