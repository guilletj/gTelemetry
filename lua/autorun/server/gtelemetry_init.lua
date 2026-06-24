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
GTelemetry.Version = "1.1.0"
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
        MsgC(white, "🌐 Web:     ", cyan, "https://alienhost.net\n")
        MsgC(white, "💬 Discord: ", cyan, "https://discord.gg/alienhost\n")
        MsgC(white, "💻 GitHub:  ", cyan, "https://github.com/Edyone\n")
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

-- Load collectors
include("gtelemetry/collectors/sv_server.lua")
include("gtelemetry/collectors/sv_players.lua")
include("gtelemetry/collectors/sv_entities.lua")
include("gtelemetry/collectors/sv_network.lua")
include("gtelemetry/collectors/sv_hooks.lua")
include("gtelemetry/collectors/sv_map.lua")
include("gtelemetry/collectors/sv_chat.lua")
include("gtelemetry/collectors/sv_darkrp.lua")

--- Start (or restart) the metric collection timer.
function GTelemetry.StartCollection()
    local interval = GTelemetry.Config.GetInterval()

    timer.Create("GTelemetry_Collect", interval, 0, function()
        GTelemetry.OTLP.CollectAndSend()
    end)

    GTelemetry.Log("Collection timer started (interval: " .. interval .. "s)")
end

-- Initialize on server start
hook.Add("InitPostEntity", "GTelemetry_Init", function()
    if not GTelemetry.Config.IsEnabled() then
        GTelemetry.Log("Telemetry is disabled. Set gtelemetry_enabled 1 to enable.")
        return
    end

    GTelemetry.StartCollection()

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
            GTelemetry.StartCollection()

            -- Count current map since InitPostEntity already fired before module load
            if GTelemetry.Collectors.Map and GTelemetry.Collectors.Map.CountChange then
                GTelemetry.Collectors.Map.CountChange()
            end

            GTelemetry.Log("v" .. GTelemetry.Version .. " late-initialized")
            if GTelemetry.PrintBanner then
                GTelemetry.PrintBanner()
            end
            GTelemetry.Log("Endpoint: " .. GTelemetry.Config.GetEndpoint())
            GTelemetry.Log("Interval: " .. GTelemetry.Config.GetInterval() .. "s")
            GTelemetry.Log("Service: " .. GTelemetry.Config.GetServiceName())
        end
    end)
end

-- Clean shutdown
hook.Add("ShutDown", "GTelemetry_Shutdown", function()
    -- Attempt one final metrics push before shutting down.
    -- NOTE: HTTP() is asynchronous; the server may close before the
    -- request completes, causing the final payload to be lost.
    if GTelemetry.Config.IsEnabled() then
        GTelemetry.Debug("Server shutting down, sending final metrics...")
        GTelemetry.OTLP.CollectAndSend()
    end
end)

GTelemetry.Log("v" .. GTelemetry.Version .. " loaded — waiting for InitPostEntity...")
