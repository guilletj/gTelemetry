--[[
    gTelemetry: GMod Telemetry
    gtelemetry_init.lua — Server entry point

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Initializes the gTelemetry telemetry system:
    - Creates the GTelemetry global namespace
    - Loads all modules and collectors
    - Starts the periodic collection timer
    - Sends client-side files to connecting players

    Configuration is done via ConVars (see sv_config.lua).
    For documentation, see README.md.
]]

-- Initialize global namespace
GTelemetry = GTelemetry or {}
GTelemetry.Version = "1.5.7"
GTelemetry.Collectors = GTelemetry.Collectors or {}

-- Client files in autorun/client are automatically sent to the client

--- Prints a stylized startup banner for the telemetry addon.
function GTelemetry.PrintBanner()
    if Color then
        local cyan = Color(0, 255, 255)
        local purple = Color(180, 100, 255)
        local white = Color(240, 240, 240)
        local gray = Color(150, 150, 150)
        local yellow = Color(255, 215, 0)

        MsgC(cyan, "\n==================================================\n")
        MsgC(cyan, "[gTelemetry] ", purple, "GMod Telemetry (v" .. GTelemetry.Version .. ")\n")
        MsgC(white, "Desarrollado por: ", yellow, "Edyone ", white, "para ", cyan, "Alienhost\n")
        MsgC(gray, "--------------------------------------------------\n")
        MsgC(white, "[WEB]     ", cyan, "https://alienhost.net\n")
        MsgC(white, "[DISCORD] ", cyan, "https://discord.gg/alienhost\n")
        MsgC(white, "[GITHUB]  ", cyan, "https://github.com/Edyone\n")
        MsgC(cyan, "==================================================\n\n")
    else
        local sep = string.rep("=", 50)
        print(sep)
        print("[gTelemetry] GMod Telemetry (v" .. GTelemetry.Version .. ")")
        print("Desarrollado por: Edyone para Alienhost")
        print(sep)
    end
end

-- Load core modules
include("gtelemetry/sv_config.lua")
include("gtelemetry/sv_otlp.lua")
include("gtelemetry/sv_otlp_logs.lua")

-- Load collectors
include("gtelemetry/collectors/sv_server.lua")
include("gtelemetry/collectors/sv_players.lua")
include("gtelemetry/collectors/sv_entities.lua")
include("gtelemetry/collectors/sv_network.lua")
include("gtelemetry/collectors/sv_hooks.lua")
include("gtelemetry/collectors/sv_map.lua")
include("gtelemetry/collectors/sv_chat.lua")
include("gtelemetry/collectors/sv_darkrp.lua")

-- bLogs bridge: always include the module definition (it's small)
include("gtelemetry/collectors/sv_blogs.lua")

-- Log events collector: always included. StartLogCollection() dispatches at runtime
-- between bLogs bridge and core log events based on gtelemetry_log_blogs_mode.
include("gtelemetry/collectors/sv_log_events.lua")

--- Start (or restart) the metric collection timer.
function GTelemetry.StartCollection()
    if GTelemetry.OTLP and GTelemetry.OTLP.ResetBackoff then
        GTelemetry.OTLP.ResetBackoff()
    end

    local interval = GTelemetry.Config.GetInterval()

    timer.Create("GTelemetry_Collect", interval, 0, function()
        GTelemetry.OTLP.CollectAndSend()
    end)

    GTelemetry.Log("Collection timer started (interval: " .. interval .. "s)")
end

--- Start (or restart) the log flush timer.
function GTelemetry.StartLogCollection()
    if not GTelemetry.Config.IsLogEnabled() then return end

    if GTelemetry.Config.IsBlogsActive() and GTelemetry.Config.IsBlogsAvailable() then
        if GTelemetry.Collectors.BLogs and GTelemetry.Collectors.BLogs.Init then
            GTelemetry.Collectors.BLogs.Init()
        end
        GTelemetry._activeLogCollector = "blogs"
    else
        GTelemetry.Collectors.LogEvents.Init()
        GTelemetry._activeLogCollector = "logevents"
    end

    if not GTelemetry.OTLP.Logs then
        GTelemetry.Warn("GTelemetry.OTLP.Logs not available — log flush timer not created")
        return
    end

    if timer.Exists("GTelemetry_LogFlush") then
        GTelemetry.Debug("Log flush timer already active")
        return
    end

    local interval = GTelemetry.Config.GetLogInterval()
    timer.Create("GTelemetry_LogFlush", interval, 0, function()
        GTelemetry.OTLP.Logs.Flush()
    end)

    GTelemetry.Log("Log collection started (interval: " .. interval .. "s, endpoint: " .. GTelemetry.Config.GetLogEndpoint() .. ")")
end

-- Initialize on server start (one-shot: removes itself on first fire)
hook.Add("InitPostEntity", "GTelemetry_Init", function()
    hook.Remove("InitPostEntity", "GTelemetry_Init")
    if not GTelemetry.Config.IsEnabled() then
        GTelemetry.Log("Telemetry is disabled. Set gtelemetry_enabled 1 to enable.")
        return
    end

    if timer.Exists("GTelemetry_Collect") then return end

    local hibernateCvar = GetConVar("sv_hibernate_think")
    if hibernateCvar and hibernateCvar:GetInt() == 0 then
        GTelemetry.Log("WARNING: sv_hibernate_think is 0 — timers will NOT fire when no players are connected.")
        GTelemetry.Log("Set sv_hibernate_think 1 in server.cfg or add +sv_hibernate_think 1 to your launch args.")
    end

    GTelemetry.StartCollection()

    if GTelemetry.Config.IsLogEnabled() then
        GTelemetry.StartLogCollection()
    end

    -- Log DarkRP detection
    if GTelemetry.Collectors.DarkRP and GTelemetry.Collectors.DarkRP.IsAvailable() then
        GTelemetry.Log("DarkRP detected — economic metrics enabled")
    end

    if GTelemetry.PrintBanner then
        GTelemetry.PrintBanner()
    else
        GTelemetry.Log("v" .. GTelemetry.Version .. " initialized successfully")
    end
    GTelemetry.Log("Endpoint: " .. GTelemetry.Config.GetEndpoint())
    GTelemetry.Log("Interval: " .. GTelemetry.Config.GetInterval() .. "s")
    GTelemetry.Log("Service: " .. GTelemetry.Config.GetServiceName())
end)

-- Also start immediately if the map is already loaded (e.g., after lua_openscript)
if game.GetMap() and game.GetMap() ~= "" then
    timer.Simple(1, function()
        if not timer.Exists("GTelemetry_Collect") and GTelemetry.Config.IsEnabled() then
            local hibernateCvar = GetConVar("sv_hibernate_think")
            if hibernateCvar and hibernateCvar:GetInt() == 0 then
                GTelemetry.Log("WARNING: sv_hibernate_think is 0 — timers will NOT fire when no players are connected.")
                GTelemetry.Log("Set sv_hibernate_think 1 in server.cfg or add +sv_hibernate_think 1 to your launch args.")
            end

            GTelemetry.StartCollection()

            if GTelemetry.Config.IsLogEnabled() and not timer.Exists("GTelemetry_LogFlush") then
                GTelemetry.StartLogCollection()
            end

            -- Re-request client-ready signals from already-connected players
            pcall(function()
                for _, ply in ipairs(player.GetAll()) do
                    net.Start("GTelemetry_RequestReady")
                    net.Send(ply)
                end
            end)

            GTelemetry.Log("v" .. GTelemetry.Version .. " late-initialized")
            if GTelemetry.PrintBanner then
                GTelemetry.PrintBanner()
            end
            GTelemetry.Log("Endpoint: " .. GTelemetry.Config.GetEndpoint())
            GTelemetry.Log("Interval: " .. GTelemetry.Config.GetInterval() .. "s")
            GTelemetry.Log("Service: " .. GTelemetry.Config.GetServiceName())
            if GTelemetry.Config.IsLogEnabled() then
                GTelemetry.Log("Log endpoint: " .. GTelemetry.Config.GetLogEndpoint())
            end
        end
    end)
end

-- Clean shutdown
hook.Add("ShutDown", "GTelemetry_Shutdown", function()
    -- Attempt one final metrics push before shutting down.
    -- NOTE: HTTP() is asynchronous; the server may close before the
    -- request completes, causing the final payload to be lost.
    -- Wrap in pcall in case engine state is partially torn down.
    if GTelemetry.Config.IsEnabled() then
        GTelemetry.Debug("Server shutting down, sending final metrics...")
        local ok, err = pcall(GTelemetry.OTLP.CollectAndSend)
        if not ok then
            GTelemetry.Warn("Final metrics send failed: " .. tostring(err))
        end
    end

    if GTelemetry.Config.IsLogEnabled() and GTelemetry.OTLP.Logs then
        GTelemetry.Debug("Server shutting down, flushing logs...")
        local ok, err = pcall(GTelemetry.OTLP.Logs.Flush)
        if not ok then
            GTelemetry.Warn("Final log flush failed: " .. tostring(err))
        end
    end
end)

GTelemetry.Log("v" .. GTelemetry.Version .. " loaded — waiting for InitPostEntity...")
