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
local safeConcat = GTelemetry.Util.safeConcat

local SEVERITY_INFO = 9
local SEVERITY_WARN = 13
local SEVERITY_ERROR = 17

function GTelemetry.Collectors.LogEvents.Init()
    if _initialized then return end

    if not GTelemetry.OTLP.Logs then
        GTelemetry.Warn("LogEvents collector: GTelemetry.OTLP.Logs not available")
        return
    end

    _initialized = true

    AddLog = GTelemetry.OTLP.Logs.AddLog
    Attribute = GTelemetry.OTLP.Attribute

    -- Local ref for perf
    local IsLogSpawnEnabled = GTelemetry.Config.IsLogSpawnEnabled

    -- ════════════════════════════════════════════════════════════
    -- Chat messages
    -- ════════════════════════════════════════════════════════════
    hook.Add("PlayerSay", "GTelemetry_LogChat", function(ply, text, teamOnly)
        if not IsValid(ply) then return end
        local prefix = teamOnly and "[TEAM] " or ""
        local body = prefix .. "[" .. ply:Nick() .. "] " .. text
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "chat"),
        })
    end)

    -- ════════════════════════════════════════════════════════════
    -- Player joins / leaves
    -- ════════════════════════════════════════════════════════════
    hook.Add("PlayerInitialSpawn", "GTelemetry_LogJoin", function(ply)
        if not IsValid(ply) then return end
        local body = ply:Nick() .. " (" .. ply:SteamID() .. ") connected"
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "player"),
            Attribute("log.event", "connect"),
        })
    end)

    hook.Add("PlayerDisconnected", "GTelemetry_LogLeave", function(ply)
        if not IsValid(ply) then return end
        local body = ply:Nick() .. " (" .. ply:SteamID() .. ") disconnected"
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "player"),
            Attribute("log.event", "disconnect"),
        })
    end)

    -- ════════════════════════════════════════════════════════════
    -- Combat
    -- ════════════════════════════════════════════════════════════
    hook.Add("PlayerHurt", "GTelemetry_LogHurt", function(victim, attacker, health, damage)
        if not IsValid(victim) then return end
        local vicName = victim:Nick()
        local body

        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
            body = attacker:Nick() .. " dealt " .. tostring(damage) .. " damage to " .. vicName
        elseif IsValid(attacker) and attacker:IsNPC() then
            body = vicName .. " was hurt by a " .. attacker:GetClass() .. " (" .. tostring(damage) .. " damage)"
        else
            body = vicName .. " took " .. tostring(damage) .. " damage"
        end

        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "combat"),
            Attribute("log.event", "hurt"),
        })
    end)

    -- Player deaths (PvP, NPC, environmental)
    hook.Add("PlayerDeath", "GTelemetry_LogDeath", function(victim, inflictor, attacker)
        if not IsValid(victim) then return end
        local vicName = victim:Nick()
        local body

        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
            local wpn = IsValid(inflictor) and inflictor:GetClass() or "unknown"
            body = vicName .. " was killed by " .. attacker:Nick() .. " with " .. wpn
        elseif IsValid(attacker) and attacker:IsNPC() then
            body = vicName .. " was killed by a " .. attacker:GetClass()
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

    -- ════════════════════════════════════════════════════════════
    -- Player state changes
    -- ════════════════════════════════════════════════════════════
    hook.Add("PlayerChangedTeam", "GTelemetry_LogTeam", function(ply, oldTeam, newTeam)
        if not IsValid(ply) then return end
        local oldName = team.GetName and team.GetName(oldTeam) or tostring(oldTeam)
        local newName = team.GetName and team.GetName(newTeam) or tostring(newTeam)
        local body = ply:Nick() .. " joined " .. newName .. " (from " .. oldName .. ")"
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "player"),
            Attribute("log.event", "team_change"),
        })
    end)

    -- ════════════════════════════════════════════════════════════
    -- Vehicle enter / exit
    -- ════════════════════════════════════════════════════════════
    hook.Add("PlayerEnteredVehicle", "GTelemetry_LogVehicleEnter", function(ply, vehicle, role)
        if not IsValid(ply) or not IsValid(vehicle) then return end
        local body = ply:Nick() .. " entered " .. vehicle:GetClass()
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "vehicle"),
            Attribute("log.event", "enter"),
        })
    end)

    hook.Add("PlayerExitedVehicle", "GTelemetry_LogVehicleExit", function(ply, vehicle)
        if not IsValid(ply) then return end
        local vClass = IsValid(vehicle) and vehicle:GetClass() or "unknown"
        local body = ply:Nick() .. " exited " .. vClass
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "vehicle"),
            Attribute("log.event", "exit"),
        })
    end)

    -- ════════════════════════════════════════════════════════════
    -- Lua errors
    -- ════════════════════════════════════════════════════════════
    hook.Add("OnLuaError", "GTelemetry_LogError", function(error, realm, stack, name)
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

    -- ════════════════════════════════════════════════════════════
    -- Admin commands — ULX / SAM / FAdmin / xAdmin
    -- ════════════════════════════════════════════════════════════
    -- ULX
    hook.Add("ULibCommandCalled", "GTelemetry_LogULX", function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = args and safeConcat(args) or ""
        local body = "[Admin/ULX] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "ulx"),
        })
    end)

    -- SAM (current hook: SAM.RanCommand)
    hook.Add("SAM.RanCommand", "GTelemetry_LogSAM", function(ply, cmd_name, args)
        local who = type(ply) == "string" and ply or (IsValid(ply) and ply:Nick() or "Console")
        local argsStr = type(args) == "table" and safeConcat(args) or tostring(args)
        local body = "[Admin/SAM] " .. who .. " ran: " .. tostring(cmd_name) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "sam"),
        })
    end)

    -- SAM fallback (older versions)
    hook.Add("SAM.PlayerCommand", "GTelemetry_LogSAMLegacy", function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = type(args) == "table" and safeConcat(args) or tostring(args)
        local body = "[Admin/SAM] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "sam"),
        })
    end)

    -- FAdmin (multiple hook names for version compat)
    hook.Add("FAdmin_CommandCalled", "GTelemetry_LogFAdmin", function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = type(args) == "table" and safeConcat(args) or tostring(args)
        local body = "[Admin/FAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "fadmin"),
        })
    end)

    hook.Add("FAdmin.Server.PlayerCommand", "GTelemetry_LogFAdmin_Server", function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = type(args) == "table" and safeConcat(args) or tostring(args)
        local body = "[Admin/FAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "fadmin"),
        })
    end)

    hook.Add("FAdmin_OnCommandExecuted", "GTelemetry_LogFAdmin_Exec", function(ply, cmd, args, results)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = type(args) == "table" and safeConcat(args) or tostring(args)
        local body = "[Admin/FAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "fadmin"),
        })
    end)

    -- xAdmin free version (pre-execution)
    hook.Add("xAdminCanRunCommand", "GTelemetry_LogxAdmin", function(ply, cmd, args, fromConsole)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = type(args) == "table" and safeConcat(args) or tostring(args)
        local body = "[Admin/xAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "xadmin"),
        })
    end)

    -- xAdmin paid version (post-execution)
    hook.Add("xAdminCommandRun", "GTelemetry_LogxAdminPaid", function(ply, target, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        local argsStr = type(args) == "table" and safeConcat(args) or tostring(args)
        local body = "[Admin/xAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. argsStr
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "admin"),
            Attribute("admin.mod", "xadmin"),
        })
    end)

    -- ════════════════════════════════════════════════════════════
    -- Spawn tracking (props, vehicles, NPCs, SENTs, SWEPs, rags, effects)
    -- Gated behind gtelemetry_log_spawn
    -- ════════════════════════════════════════════════════════════
    hook.Add("PlayerSpawnedProp", "GTelemetry_LogSpawnProp", function(ply, model, ent)
        if not IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        local body = "[Prop] " .. ply:Nick() .. " spawned " .. tostring(model)
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "spawn"),
            Attribute("spawn.type", "prop"),
        })
    end)

    hook.Add("PlayerSpawnedVehicle", "GTelemetry_LogSpawnVehicle", function(ply, ent)
        if not IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        local vClass = IsValid(ent) and ent:GetClass() or "unknown"
        local body = "[Vehicle] " .. ply:Nick() .. " spawned " .. vClass
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "spawn"),
            Attribute("spawn.type", "vehicle"),
        })
    end)

    hook.Add("PlayerSpawnedNPC", "GTelemetry_LogSpawnNPC", function(ply, ent)
        if not IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        local npcClass = IsValid(ent) and ent:GetClass() or "unknown"
        local body = "[NPC] " .. ply:Nick() .. " spawned " .. npcClass
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "spawn"),
            Attribute("spawn.type", "npc"),
        })
    end)

    hook.Add("PlayerSpawnedSENT", "GTelemetry_LogSpawnSENT", function(ply, ent)
        if not IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        local class = IsValid(ent) and ent:GetClass() or "unknown"
        local body = "[SENT] " .. ply:Nick() .. " spawned " .. class
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "spawn"),
            Attribute("spawn.type", "sent"),
        })
    end)

    hook.Add("PlayerSpawnedSWEP", "GTelemetry_LogSpawnSWEP", function(ply, swep)
        if not IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        local class = IsValid(swep) and swep:GetClass() or "unknown"
        local body = "[SWEP] " .. ply:Nick() .. " spawned " .. class
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "spawn"),
            Attribute("spawn.type", "swep"),
        })
    end)

    hook.Add("PlayerSpawnedRagdoll", "GTelemetry_LogSpawnRagdoll", function(ply, model, ent)
        if not IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        local body = "[Ragdoll] " .. ply:Nick() .. " spawned " .. tostring(model)
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "spawn"),
            Attribute("spawn.type", "ragdoll"),
        })
    end)

    hook.Add("PlayerSpawnedEffect", "GTelemetry_LogSpawnEffect", function(ply, model, ent)
        if not IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        local body = "[Effect] " .. ply:Nick() .. " spawned " .. tostring(model)
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "spawn"),
            Attribute("spawn.type", "effect"),
        })
    end)

    -- ════════════════════════════════════════════════════════════
    -- Item pickups / weapon drops (gated behind gtelemetry_log_spawn)
    -- ════════════════════════════════════════════════════════════
    hook.Add("PlayerPickupItem", "GTelemetry_LogPickup", function(ply, item)
        if not IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        local class = IsValid(item) and item:GetClass() or "unknown"
        local body = ply:Nick() .. " picked up " .. class
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "item"),
            Attribute("log.event", "pickup"),
        })
    end)

    hook.Add("PlayerDroppedWeapon", "GTelemetry_LogDrop", function(ply, weapon)
        if not IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        local class = IsValid(weapon) and weapon:GetClass() or "unknown"
        local body = ply:Nick() .. " dropped " .. class
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "item"),
            Attribute("log.event", "drop"),
        })
    end)

    -- ════════════════════════════════════════════════════════════
    -- Server start / map change / gamemode change / shutdown
    -- ════════════════════════════════════════════════════════════
    hook.Add("InitPostEntity", "GTelemetry_LogMap", function()
        local currentMap = game.GetMap() or "unknown"

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
        else
            local body = "Map changed: " .. _prevMap .. " -> " .. currentMap
            AddLog(SEVERITY_INFO, "INFO", body, {
                Attribute("log.source", "system"),
                Attribute("log.event", "map_change"),
            })
            _prevMap = currentMap
        end
    end)

    hook.Add("gamemode.PostGamemodeLoaded", "GTelemetry_LogGamemode", function()
        local gm = (engine.ActiveGamemode and engine.ActiveGamemode()) or "unknown"
        local body = "Gamemode loaded: " .. gm
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "system"),
            Attribute("log.event", "gamemode_change"),
        })
    end)

    hook.Add("ShutDown", "GTelemetry_LogShutdown", function()
        AddLog(SEVERITY_WARN, "WARN", "Server shutting down", {
            Attribute("log.source", "system"),
            Attribute("log.event", "server_stop"),
        })
    end, 10)

    -- Late-init: emit server start if map already loaded (InitPostEntity already fired)
    if game.GetMap() and game.GetMap() ~= "" and not _serverStarted then
        _serverStarted = true
        _prevMap = game.GetMap()
        local hostname = GetHostName and GetHostName() or "unknown"
        local gm = (engine.ActiveGamemode and engine.ActiveGamemode()) or "unknown"
        local body = "Server started — " .. hostname .. ", map: " .. _prevMap .. ", gamemode: " .. gm .. ", version: " .. (GTelemetry.Version or "?")
        AddLog(SEVERITY_INFO, "INFO", body, {
            Attribute("log.source", "system"),
            Attribute("log.event", "server_start"),
        })
    end

    GTelemetry.Debug("LogEvents collector initialized")
end

--- Remove all hooks registered by this collector.
function GTelemetry.Collectors.LogEvents.Undo()
    if not _initialized then return end
    _initialized = false

    hook.Remove("PlayerSay", "GTelemetry_LogChat")
    hook.Remove("PlayerInitialSpawn", "GTelemetry_LogJoin")
    hook.Remove("PlayerDisconnected", "GTelemetry_LogLeave")
    hook.Remove("PlayerHurt", "GTelemetry_LogHurt")
    hook.Remove("PlayerDeath", "GTelemetry_LogDeath")
    hook.Remove("PlayerChangedTeam", "GTelemetry_LogTeam")
    hook.Remove("PlayerEnteredVehicle", "GTelemetry_LogVehicleEnter")
    hook.Remove("PlayerExitedVehicle", "GTelemetry_LogVehicleExit")
    hook.Remove("OnLuaError", "GTelemetry_LogError")
    hook.Remove("ULibCommandCalled", "GTelemetry_LogULX")
    hook.Remove("SAM.RanCommand", "GTelemetry_LogSAM")
    hook.Remove("SAM.PlayerCommand", "GTelemetry_LogSAMLegacy")
    hook.Remove("FAdmin_CommandCalled", "GTelemetry_LogFAdmin")
    hook.Remove("FAdmin.Server.PlayerCommand", "GTelemetry_LogFAdmin_Server")
    hook.Remove("FAdmin_OnCommandExecuted", "GTelemetry_LogFAdmin_Exec")
    hook.Remove("xAdminCanRunCommand", "GTelemetry_LogxAdmin")
    hook.Remove("xAdminCommandRun", "GTelemetry_LogxAdminPaid")
    hook.Remove("PlayerSpawnedProp", "GTelemetry_LogSpawnProp")
    hook.Remove("PlayerSpawnedVehicle", "GTelemetry_LogSpawnVehicle")
    hook.Remove("PlayerSpawnedNPC", "GTelemetry_LogSpawnNPC")
    hook.Remove("PlayerSpawnedSENT", "GTelemetry_LogSpawnSENT")
    hook.Remove("PlayerSpawnedSWEP", "GTelemetry_LogSpawnSWEP")
    hook.Remove("PlayerSpawnedRagdoll", "GTelemetry_LogSpawnRagdoll")
    hook.Remove("PlayerSpawnedEffect", "GTelemetry_LogSpawnEffect")
    hook.Remove("PlayerPickupItem", "GTelemetry_LogPickup")
    hook.Remove("PlayerDroppedWeapon", "GTelemetry_LogDrop")
    hook.Remove("InitPostEntity", "GTelemetry_LogMap")
    hook.Remove("gamemode.PostGamemodeLoaded", "GTelemetry_LogGamemode")
    hook.Remove("ShutDown", "GTelemetry_LogShutdown")

    _prevMap = nil
    _serverStarted = false
    GTelemetry.OTLP.Logs.ClearBuffer()
    GTelemetry.Debug("LogEvents collector stopped")
end
