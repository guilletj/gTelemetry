--[[
    gTelemetry: GMod Telemetry
    collectors/sv_log_events.lua — Log event hooks for OTLP log export

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Captures server events in real-time and feeds them to the OTLP
    log buffer for periodic flush to Loki via Alloy.

    This collector is event-driven (no Collect() method).
    Use Init() to register hooks and Undo() to remove them.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.LogEvents = {}

local _initialized = false
local _prevMap = nil
local _serverStarted = false
local tostring = tostring
local AddLog = nil
local Attribute = nil

local SEVERITY_INFO = 9
local SEVERITY_WARN = 13
local SEVERITY_ERROR = 17

function GTelemetry.Collectors.LogEvents.Init()
    if _initialized then return end
    _initialized = true

    if not GTelemetry.OTLP.Logs then
        GTelemetry.Warn("LogEvents collector: GTelemetry.OTLP.Logs not available")
        return
    end

    AddLog = function(severity, text, body, attrs)
        GTelemetry.OTLP.Logs.AddLog(severity, text, body, attrs)
    end
    Attribute = GTelemetry.OTLP.Logs.Attribute

    -- Chat messages
    hook.Add("PlayerSay", "GTelemetry_LogChat", function(ply, text, teamOnly)
        if not IsValid(ply) then return end
        local prefix = teamOnly and "[TEAM] " or ""
        local body = prefix .. "[" .. ply:Nick() .. "] " .. text
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "chat"),
        })
    end)

    -- Player joins
    hook.Add("PlayerInitialSpawn", "GTelemetry_LogJoin", function(ply)
        if not IsValid(ply) then return end
        local body = ply:Nick() .. " (" .. ply:SteamID() .. ") connected"
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "player"),
            Attribute("log.event", "connect"),
        })
    end)

    -- Player disconnects
    hook.Add("PlayerDisconnected", "GTelemetry_LogLeave", function(ply)
        if not IsValid(ply) then return end
        local body = ply:Nick() .. " (" .. ply:SteamID() .. ") disconnected"
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "player"),
            Attribute("log.event", "disconnect"),
        })
    end)

    -- Player deaths
    hook.Add("PlayerDeath", "GTelemetry_LogDeath", function(victim, inflictor, attacker)
        if not IsValid(victim) then return end
        local vicName = victim:Nick()
        local body

        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
            local atkName = attacker:Nick()
            local wpn = IsValid(inflictor) and inflictor:GetClass() or "unknown"
            body = vicName .. " was killed by " .. atkName .. " with " .. wpn
        elseif IsValid(attacker) and attacker:IsNPC() then
            local npcClass = attacker:GetClass()
            body = vicName .. " was killed by a " .. npcClass
        elseif attacker == victim or not IsValid(attacker) then
            body = vicName .. " died"
        else
            body = vicName .. " was killed"
        end

        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "player"),
            Attribute("log.event", "death"),
        })
    end)

    -- Lua errors
    hook.Add("OnLuaError", "GTelemetry_LogError", function(error, realm, stack, name, id)
        local source = name and "[" .. name .. "]" or ""
        local body = source .. " " .. tostring(error)
        if stack then
            body = body .. "\n" .. tostring(stack)
        end
        AddLog(SEVERITY_ERROR, "ERROR", body, {
            Attribute("log.source", "error"),
            Attribute("log.realm", realm or "SERVER"),
        })
    end)

    -- ULX admin commands
    hook.Add("ULibCommandCalled", "GTelemetry_LogULX", function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = args and table.concat(args, " ") or ""
        local body = "[Admin/ULX] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "ulx"),
        })
    end)

    -- SAM admin commands
    hook.Add("SAM.PlayerCommand", "GTelemetry_LogSAM", function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = type(args) == "table" and table.concat(args, " ") or tostring(args)
        local body = "[Admin/SAM] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "sam"),
        })
    end)

    -- FAdmin admin commands
    hook.Add("FAdmin_CommandCalled", "GTelemetry_LogFAdmin", function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = type(args) == "table" and table.concat(args, " ") or tostring(args)
        local body = "[Admin/FAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "fadmin"),
        })
    end)

    hook.Add("FAdmin.Server.PlayerCommand", "GTelemetry_LogFAdmin2", function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = type(args) == "table" and table.concat(args, " ") or tostring(args)
        local body = "[Admin/FAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "fadmin"),
        })
    end)

    -- Map change detection + server start
    hook.Add("InitPostEntity", "GTelemetry_LogMap", function()
        local currentMap = game.GetMap() or "unknown"
        local now = SysTime()

        if not _serverStarted then
            _serverStarted = true
            _prevMap = currentMap
            local hostname = GetHostName and GetHostName() or "unknown"
            local gm = (engine.ActiveGamemode and engine.ActiveGamemode()) or "unknown"
            local body = "Server started — " .. hostname .. ", map: " .. currentMap .. ", gamemode: " .. gm .. ", version: " .. (GTelemetry.Version or "?")
            AddLog(SEVERITY_INFO, "INFO", body, {
                Attribute("log.source", "system"),
                Attribute("log.event", "server_start"),
            })
        elseif _prevMap and _prevMap ~= currentMap then
            local body = "Map changed: " .. _prevMap .. " -> " .. currentMap
            AddLog(SEVERITY_INFO, "INFO", body, {
                Attribute("log.source", "system"),
                Attribute("log.event", "map_change"),
            })
            _prevMap = currentMap
        else
            _prevMap = currentMap
        end
    end)

    -- Server shutdown
    hook.Add("ShutDown", "GTelemetry_LogShutdown", function()
        AddLog(SEVERITY_WARN, "WARN", "Server shutting down", {
            Attribute("log.source", "system"),
            Attribute("log.event", "server_stop"),
        })
    end)

    GTelemetry.Debug("LogEvents collector initialized")
end

--- Remove all hooks registered by this collector.
function GTelemetry.Collectors.LogEvents.Undo()
    if not _initialized then return end
    _initialized = false

    hook.Remove("PlayerSay", "GTelemetry_LogChat")
    hook.Remove("PlayerInitialSpawn", "GTelemetry_LogJoin")
    hook.Remove("PlayerDisconnected", "GTelemetry_LogLeave")
    hook.Remove("PlayerDeath", "GTelemetry_LogDeath")
    hook.Remove("OnLuaError", "GTelemetry_LogError")
    hook.Remove("ULibCommandCalled", "GTelemetry_LogULX")
    hook.Remove("SAM.PlayerCommand", "GTelemetry_LogSAM")
    hook.Remove("FAdmin_CommandCalled", "GTelemetry_LogFAdmin")
    hook.Remove("FAdmin.Server.PlayerCommand", "GTelemetry_LogFAdmin2")
    hook.Remove("InitPostEntity", "GTelemetry_LogMap")
    hook.Remove("ShutDown", "GTelemetry_LogShutdown")

    GTelemetry.OTLP.Logs.ClearBuffer()
    GTelemetry.Debug("LogEvents collector stopped")
end
