--[[
    gTelemetry: GMod Telemetry
    sv_blogs.lua — bLogs (Billy's Logs) bridge: MODULE:Hook + LogPhrase interceptor

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Two strategies side by side, dispatched by gtelemetry_log_blogs_mode:
    - replace: register as GAS.Logging module via MODULE:Hook()
    - intercept: wrap LogPhrase/Phrase on GAS module metatable
    - hybrid: both strategies active simultaneously
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.BLogs = {}

local _initialized = false
local _initMode = nil
local _module = nil
local _modulePrevMap = nil
local _serverStartLogged = false

local SEVERITY_INFO = 9
local SEVERITY_WARN = 13
local SEVERITY_ERROR = 17

local AddLog = nil
local Attribute = nil
local tostring = tostring
local table_concat = table.concat
local safeConcat = GTelemetry.Util.safeConcat

function GTelemetry.Collectors.BLogs.IsAvailable()
    return GAS and GAS.Logging and type(GAS.Logging.MODULE) == "function"
end

function GTelemetry.Collectors.BLogs.Init()
    if _initialized then return end

    if not GTelemetry.Collectors.BLogs.IsAvailable() then
        GTelemetry.Warn("bLogs bridge: GAS.Logging not available")
        return
    end

    if not GTelemetry.OTLP.Logs then
        GTelemetry.Warn("bLogs bridge: GTelemetry.OTLP.Logs not available")
        return
    end

    AddLog = GTelemetry.OTLP.Logs.AddLog
    Attribute = GTelemetry.OTLP.Attribute

    _initMode = GTelemetry.Config.ConVars.log_blogs_mode:GetString()
    local mode = _initMode

    local validModes = {off = true, replace = true, intercept = true, hybrid = true}
    if not validModes[mode] then
        GTelemetry.Warn("Unknown gtelemetry_log_blogs_mode '" .. tostring(mode) .. "', treating as 'off'")
    end

    _initialized = true

    if mode == "replace" or mode == "hybrid" then
        _setupModule()
    end

    if mode == "intercept" or mode == "hybrid" then
        GTelemetry.Collectors.BLogs.Interceptor.Install()
    end

    -- Late-init: emit server start if map already loaded (InitPostEntity already fired)
    if (mode == "replace" or mode == "hybrid") and game.GetMap() and game.GetMap() ~= "" and not _serverStartLogged then
        _serverStartLogged = true
        _modulePrevMap = game.GetMap()
        AddLog(SEVERITY_INFO, "INFO", "Server started — " .. (GetHostName and GetHostName() or "unknown") .. ", map: " .. _modulePrevMap .. ", gamemode: " .. (engine.ActiveGamemode and engine.ActiveGamemode() or "unknown") .. ", version: " .. (GTelemetry.Version or "?"), {Attribute("log.source", "system"), Attribute("log.event", "server_start")})
    end

    GTelemetry.Debug("bLogs bridge initialized (mode: " .. mode .. ")")
end

function GTelemetry.Collectors.BLogs.Undo()
    if not _initialized then return end
    _initialized = false

    local mode = _initMode

    if mode == "replace" or mode == "hybrid" then
        _cleanupModule()
    end

    if mode == "intercept" or mode == "hybrid" then
        GTelemetry.Collectors.BLogs.Interceptor.Uninstall()
    end

    _module = nil
    _initMode = nil
    GTelemetry.OTLP.Logs.ClearBuffer()
    GTelemetry.Debug("bLogs bridge stopped")
end

local _hookSpecs = {
    {event = "PlayerSay", id = "GTelemetry_BLogs_chat", fn = function(ply, text, teamOnly)
        if not IsValid(ply) then return end
        AddLog(SEVERITY_INFO, "INFO", (teamOnly and "[TEAM] " or "") .. "[" .. ply:Nick() .. "] " .. text, {Attribute("log.source", "chat")})
    end},
    {event = "PlayerInitialSpawn", id = "GTelemetry_BLogs_join", fn = function(ply)
        if not IsValid(ply) then return end
        AddLog(SEVERITY_INFO, "INFO", ply:Nick() .. " (" .. ply:SteamID() .. ") connected", {Attribute("log.source", "player"), Attribute("log.event", "connect")})
    end},
    {event = "PlayerDisconnected", id = "GTelemetry_BLogs_leave", fn = function(ply)
        if not IsValid(ply) then return end
        AddLog(SEVERITY_INFO, "INFO", ply:Nick() .. " (" .. ply:SteamID() .. ") disconnected", {Attribute("log.source", "player"), Attribute("log.event", "disconnect")})
    end},
    {event = "PlayerHurt", id = "GTelemetry_BLogs_hurt", fn = function(victim, attacker, health, damage)
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
        AddLog(SEVERITY_INFO, "INFO", body, {Attribute("log.source", "combat"), Attribute("log.event", "hurt")})
    end},
    {event = "PlayerDeath", id = "GTelemetry_BLogs_death", fn = function(victim, inflictor, attacker)
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
        AddLog(SEVERITY_INFO, "INFO", body, {Attribute("log.source", "player"), Attribute("log.event", "death")})
    end},
    {event = "PlayerChangedTeam", id = "GTelemetry_BLogs_team", fn = function(ply, oldTeam, newTeam)
        if not IsValid(ply) then return end
        local oldName = team.GetName and team.GetName(oldTeam) or tostring(oldTeam)
        local newName = team.GetName and team.GetName(newTeam) or tostring(newTeam)
        AddLog(SEVERITY_INFO, "INFO", ply:Nick() .. " joined " .. newName .. " (from " .. oldName .. ")", {Attribute("log.source", "player"), Attribute("log.event", "team_change")})
    end},
    {event = "PlayerEnteredVehicle", id = "GTelemetry_BLogs_vehicle_enter", fn = function(ply, vehicle, role)
        if not IsValid(ply) or not IsValid(vehicle) then return end
        AddLog(SEVERITY_INFO, "INFO", ply:Nick() .. " entered " .. vehicle:GetClass(), {Attribute("log.source", "vehicle"), Attribute("log.event", "enter")})
    end},
    {event = "PlayerExitedVehicle", id = "GTelemetry_BLogs_vehicle_exit", fn = function(ply, vehicle)
        if not IsValid(ply) then return end
        AddLog(SEVERITY_INFO, "INFO", ply:Nick() .. " exited " .. (IsValid(vehicle) and vehicle:GetClass() or "unknown"), {Attribute("log.source", "vehicle"), Attribute("log.event", "exit")})
    end},
    {event = "OnLuaError", id = "GTelemetry_BLogs_error", fn = function(error, stacktrace, realm)
        local body = tostring(error)
        if stacktrace then body = body .. "\n" .. tostring(stacktrace) end
        AddLog(SEVERITY_ERROR, "ERROR", body, {Attribute("log.source", "error"), Attribute("log.realm", realm or "SERVER")})
    end},
    {event = "ULibCommandCalled", id = "GTelemetry_BLogs_ulx", fn = function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        AddLog(SEVERITY_INFO, "INFO", "[Admin/ULX] " .. who .. " ran: " .. tostring(cmd) .. " " .. GTelemetry.Util.safeArgs(args, ""), {Attribute("log.source", "admin"), Attribute("admin.mod", "ulx")})
    end},
    {event = "SAM.RanCommand", id = "GTelemetry_BLogs_sam", fn = function(ply, cmd_name, args)
        local who = type(ply) == "string" and ply or (IsValid(ply) and ply:Nick() or "Console")
        AddLog(SEVERITY_INFO, "INFO", "[Admin/SAM] " .. who .. " ran: " .. tostring(cmd_name) .. " " .. GTelemetry.Util.safeArgs(args), {Attribute("log.source", "admin"), Attribute("admin.mod", "sam")})
    end},
    {event = "SAM.PlayerCommand", id = "GTelemetry_BLogs_sam_legacy", fn = function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        AddLog(SEVERITY_INFO, "INFO", "[Admin/SAM] " .. who .. " ran: " .. tostring(cmd) .. " " .. GTelemetry.Util.safeArgs(args), {Attribute("log.source", "admin"), Attribute("admin.mod", "sam")})
    end},
    {event = "FAdmin_CommandCalled", id = "GTelemetry_BLogs_fadmin", fn = function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        AddLog(SEVERITY_INFO, "INFO", "[Admin/FAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. GTelemetry.Util.safeArgs(args), {Attribute("log.source", "admin"), Attribute("admin.mod", "fadmin")})
    end},
    {event = "FAdmin.Server.PlayerCommand", id = "GTelemetry_BLogs_fadmin_server", fn = function(ply, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        AddLog(SEVERITY_INFO, "INFO", "[Admin/FAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. GTelemetry.Util.safeArgs(args), {Attribute("log.source", "admin"), Attribute("admin.mod", "fadmin")})
    end},
    {event = "FAdmin_OnCommandExecuted", id = "GTelemetry_BLogs_fadmin_exec", fn = function(ply, cmd, args, results)
        local who = IsValid(ply) and ply:Nick() or "Console"
        AddLog(SEVERITY_INFO, "INFO", "[Admin/FAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. GTelemetry.Util.safeArgs(args), {Attribute("log.source", "admin"), Attribute("admin.mod", "fadmin")})
    end},
    {event = "xAdminCanRunCommand", id = "GTelemetry_BLogs_xadmin", fn = function(ply, cmd, args, fromConsole)
        local who = IsValid(ply) and ply:Nick() or "Console"
        AddLog(SEVERITY_INFO, "INFO", "[Admin/xAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. GTelemetry.Util.safeArgs(args), {Attribute("log.source", "admin"), Attribute("admin.mod", "xadmin")})
    end},
    {event = "xAdminCommandRun", id = "GTelemetry_BLogs_xadmin_paid", fn = function(ply, target, cmd, args)
        local who = IsValid(ply) and ply:Nick() or "Console"
        AddLog(SEVERITY_INFO, "INFO", "[Admin/xAdmin] " .. who .. " ran: " .. tostring(cmd) .. " " .. GTelemetry.Util.safeArgs(args), {Attribute("log.source", "admin"), Attribute("admin.mod", "xadmin")})
    end},
    {event = "PlayerSpawnedProp", id = "GTelemetry_BLogs_spawn_prop", fn = function(ply, model, ent)
        if not GTelemetry.Config.IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        AddLog(SEVERITY_INFO, "INFO", "[Prop] " .. ply:Nick() .. " spawned " .. tostring(model), {Attribute("log.source", "spawn"), Attribute("spawn.type", "prop")})
    end},
    {event = "PlayerSpawnedVehicle", id = "GTelemetry_BLogs_spawn_vehicle", fn = function(ply, ent)
        if not GTelemetry.Config.IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        AddLog(SEVERITY_INFO, "INFO", "[Vehicle] " .. ply:Nick() .. " spawned " .. (IsValid(ent) and ent:GetClass() or "unknown"), {Attribute("log.source", "spawn"), Attribute("spawn.type", "vehicle")})
    end},
    {event = "PlayerSpawnedNPC", id = "GTelemetry_BLogs_spawn_npc", fn = function(ply, ent)
        if not GTelemetry.Config.IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        AddLog(SEVERITY_INFO, "INFO", "[NPC] " .. ply:Nick() .. " spawned " .. (IsValid(ent) and ent:GetClass() or "unknown"), {Attribute("log.source", "spawn"), Attribute("spawn.type", "npc")})
    end},
    {event = "PlayerSpawnedSENT", id = "GTelemetry_BLogs_spawn_sent", fn = function(ply, ent)
        if not GTelemetry.Config.IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        AddLog(SEVERITY_INFO, "INFO", "[SENT] " .. ply:Nick() .. " spawned " .. (IsValid(ent) and ent:GetClass() or "unknown"), {Attribute("log.source", "spawn"), Attribute("spawn.type", "sent")})
    end},
    {event = "PlayerSpawnedSWEP", id = "GTelemetry_BLogs_spawn_swep", fn = function(ply, swep)
        if not GTelemetry.Config.IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        AddLog(SEVERITY_INFO, "INFO", "[SWEP] " .. ply:Nick() .. " spawned " .. (IsValid(swep) and swep:GetClass() or "unknown"), {Attribute("log.source", "spawn"), Attribute("spawn.type", "swep")})
    end},
    {event = "PlayerSpawnedRagdoll", id = "GTelemetry_BLogs_spawn_ragdoll", fn = function(ply, model, ent)
        if not GTelemetry.Config.IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        AddLog(SEVERITY_INFO, "INFO", "[Ragdoll] " .. ply:Nick() .. " spawned " .. tostring(model), {Attribute("log.source", "spawn"), Attribute("spawn.type", "ragdoll")})
    end},
    {event = "PlayerSpawnedEffect", id = "GTelemetry_BLogs_spawn_effect", fn = function(ply, model, ent)
        if not GTelemetry.Config.IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        AddLog(SEVERITY_INFO, "INFO", "[Effect] " .. ply:Nick() .. " spawned " .. tostring(model), {Attribute("log.source", "spawn"), Attribute("spawn.type", "effect")})
    end},
    {event = "PlayerPickupItem", id = "GTelemetry_BLogs_pickup", fn = function(ply, item)
        if not GTelemetry.Config.IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        AddLog(SEVERITY_INFO, "INFO", ply:Nick() .. " picked up " .. (IsValid(item) and item:GetClass() or "unknown"), {Attribute("log.source", "item"), Attribute("log.event", "pickup")})
    end},
    {event = "PlayerDroppedWeapon", id = "GTelemetry_BLogs_drop", fn = function(ply, weapon)
        if not GTelemetry.Config.IsLogSpawnEnabled() or not IsValid(ply) or not ply:IsPlayer() then return end
        AddLog(SEVERITY_INFO, "INFO", ply:Nick() .. " dropped " .. (IsValid(weapon) and weapon:GetClass() or "unknown"), {Attribute("log.source", "item"), Attribute("log.event", "drop")})
    end},
    {event = "InitPostEntity", id = "GTelemetry_BLogs_map", fn = function()
        local currentMap = game.GetMap() or "unknown"
        if not _serverStartLogged then
            _serverStartLogged = true
            _modulePrevMap = currentMap
            AddLog(SEVERITY_INFO, "INFO", "Server started — " .. (GetHostName and GetHostName() or "unknown") .. ", map: " .. currentMap .. ", gamemode: " .. (engine.ActiveGamemode and engine.ActiveGamemode() or "unknown") .. ", version: " .. (GTelemetry.Version or "?"), {Attribute("log.source", "system"), Attribute("log.event", "server_start")})
        elseif _modulePrevMap ~= currentMap then
            AddLog(SEVERITY_INFO, "INFO", "Map changed: " .. _modulePrevMap .. " -> " .. currentMap, {Attribute("log.source", "system"), Attribute("log.event", "map_change")})
            _modulePrevMap = currentMap
        else
            _modulePrevMap = currentMap
        end
    end},
    {event = "gamemode.PostGamemodeLoaded", id = "GTelemetry_BLogs_gamemode", fn = function()
        AddLog(SEVERITY_INFO, "INFO", "Gamemode loaded: " .. (engine.ActiveGamemode and engine.ActiveGamemode() or "unknown"), {Attribute("log.source", "system"), Attribute("log.event", "gamemode_change")})
    end},
}
-- NOTE: ShutDown is NOT in _hookSpecs. It's registered via hook.Add() directly in _setupModule()
-- with priority 10 to ensure it runs BEFORE the main flush hook at default priority 0.

local function _shutdownHook()
    AddLog(SEVERITY_WARN, "WARN", "Server shutting down", {Attribute("log.source", "system"), Attribute("log.event", "server_stop")})
end

local function _setupModule()
    local ok, err = pcall(function()
        _module = GAS.Logging:MODULE()
        _module.Category = "gTelemetry"
        _module.Name = "Loki Export"
        _module.Colour = Color(0, 255, 200)

        _module:Setup(function()
            for _, spec in ipairs(_hookSpecs) do
                _module:Hook(spec.event, spec.id, spec.fn)
            end
        end)

        -- Register ShutDown directly with priority 10 so it runs BEFORE the main flush (priority 0)
        hook.Add("ShutDown", "GTelemetry_BLogsShutdown", _shutdownHook, 10)

        GAS.Logging:AddModule(_module)
        GTelemetry.Debug("bLogs bridge registered " .. #_hookSpecs .. " hooks via MODULE:Hook()")
    end)
    if not ok then
        GTelemetry.Warn("bLogs bridge: failed to setup GAS module: " .. tostring(err))
    end
end

local function _cleanupModule()
    for _, spec in ipairs(_hookSpecs) do
        pcall(hook.Remove, spec.event, spec.id)
    end
    hook.Remove("ShutDown", "GTelemetry_BLogsShutdown")
    pcall(function() GAS.Logging:RemoveModule(_module) end)
    _module = nil
    GTelemetry.Debug("bLogs bridge hooks removed")
end

GTelemetry.Collectors.BLogs.Interceptor = {}

local _interceptorActive = false
local _origLogPhrase = nil
local _origAddModule = nil
local _restoreTarget = nil
local _restoreKey = nil
local _wrappedModules = nil -- { mod = originalFunction } for fallback path

function GTelemetry.Collectors.BLogs.Interceptor.Install()
    if _interceptorActive then return end

    AddLog = AddLog or GTelemetry.OTLP.Logs.AddLog
    Attribute = Attribute or GTelemetry.OTLP.Attribute

    local ok, found = pcall(function()
        local testModule = GAS.Logging:MODULE()
        local mt = getmetatable(testModule)
        if not mt then return false end

        local target = mt
        local key

        if type(rawget(mt, "LogPhrase")) == "function" then
            target = mt
            key = "LogPhrase"
        elseif type(rawget(mt, "__index")) == "table" and type(rawget(rawget(mt, "__index"), "LogPhrase")) == "function" then
            target = rawget(mt, "__index")
            key = "LogPhrase"
        elseif type(rawget(mt, "Phrase")) == "function" then
            target = mt
            key = "Phrase"
        elseif type(rawget(mt, "__index")) == "table" and type(rawget(rawget(mt, "__index"), "Phrase")) == "function" then
            target = rawget(mt, "__index")
            key = "Phrase"
        else
            return false
        end

        _origLogPhrase = rawget(target, key)
        _restoreTarget = target
        _restoreKey = key

        target[key] = function(self, ...)
            local ok, r1, r2, r3 = pcall(_origLogPhrase, self, ...)
            pcall(GTelemetry.Collectors.BLogs.Interceptor.OnLog, self, ...)
            if ok then return r1, r2, r3 end
        end

        return true
    end)

    if ok and found then
        _interceptorActive = true
        GTelemetry.Debug("bLogs bridge: wrapped " .. _restoreKey .. " on module metatable")
    else
        GTelemetry.Warn("bLogs bridge: could not find LogPhrase on metatable — wrapping AddModule as fallback")
        GTelemetry.Collectors.BLogs.Interceptor._WrapAddModule()
    end
end

function GTelemetry.Collectors.BLogs.Interceptor._WrapAddModule()
    if type(GAS.Logging.AddModule) ~= "function" then
        GTelemetry.Warn("bLogs bridge: GAS.Logging.AddModule not available")
        return
    end

    _wrappedModules = _wrappedModules or {}

    _origAddModule = GAS.Logging.AddModule
    GAS.Logging.AddModule = function(self, mod)
        local result = _origAddModule(self, mod)

        local entry = {}
        if type(mod.LogPhrase) == "function" then
            entry.LogPhrase = mod.LogPhrase
            local orig = mod.LogPhrase
            mod.LogPhrase = function(innerSelf, ...)
                local ok, r1, r2, r3 = pcall(orig, innerSelf, ...)
                pcall(GTelemetry.Collectors.BLogs.Interceptor.OnLog, innerSelf, ...)
                if ok then return r1, r2, r3 end
            end
        end
        if type(mod.Phrase) == "function" then
            entry.Phrase = mod.Phrase
            local orig = mod.Phrase
            mod.Phrase = function(innerSelf, ...)
                local ok, r1, r2, r3 = pcall(orig, innerSelf, ...)
                pcall(GTelemetry.Collectors.BLogs.Interceptor.OnLog, innerSelf, ...)
                if ok then return r1, r2, r3 end
            end
        end
        if next(entry) then
            _wrappedModules[mod] = entry
        end

        return result
    end

    _interceptorActive = true
    GTelemetry.Debug("bLogs bridge: wrapped GAS.Logging.AddModule")
end

function GTelemetry.Collectors.BLogs.Interceptor.OnLog(self, phraseKey, ...)
    local category = self.Category or "unknown"
    local name = self.Name or "unknown"
    local args = {...}

    local parts = {}
    for i = 1, #args do
        parts[#parts + 1] = tostring(args[i])
    end

    local body = "[bLogs/" .. category .. "/" .. name .. "] " .. tostring(phraseKey)
    if #parts > 0 then
        body = body .. ": " .. table_concat(parts, " | ")
    end

    AddLog(SEVERITY_INFO, "INFO", body, {
        Attribute("log.source", "blogs"),
        Attribute("blogs.category", category),
        Attribute("blogs.module", name),
        Attribute("blogs.phrase", tostring(phraseKey)),
    })
end

function GTelemetry.Collectors.BLogs.Interceptor.Uninstall()
    if not _interceptorActive then return end
    _interceptorActive = false

    if _restoreTarget and _restoreKey and _origLogPhrase then
        _restoreTarget[_restoreKey] = _origLogPhrase
        GTelemetry.Debug("bLogs bridge: restored original " .. _restoreKey)
    end

    if _wrappedModules then
        local count = 0
        for mod, entry in pairs(_wrappedModules) do
            count = count + 1
            if entry.LogPhrase and type(mod.LogPhrase) == "function" and mod.LogPhrase ~= entry.LogPhrase then
                mod.LogPhrase = entry.LogPhrase
            end
            if entry.Phrase and type(mod.Phrase) == "function" and mod.Phrase ~= entry.Phrase then
                mod.Phrase = entry.Phrase
            end
        end
        _wrappedModules = nil
        GTelemetry.Debug("bLogs bridge: restored " .. count .. " wrapped modules")
    end

    if _origAddModule then
        GAS.Logging.AddModule = _origAddModule
        _origAddModule = nil
        GTelemetry.Debug("bLogs bridge: restored original AddModule")
    end

    _origLogPhrase = nil
    _restoreTarget = nil
    _restoreKey = nil
end
