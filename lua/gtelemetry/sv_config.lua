--[[
    gTelemetry: GMod Telemetry
    sv_config.lua — ConVar definitions & configuration helpers

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    All server configuration is managed through ConVars,
    allowing admins to configure via server.cfg or console.
]]

GTelemetry.Config = GTelemetry.Config or {}

local table_insert = table.insert
local table_concat = table.concat
local string_match = string.match

-- ConVar definitions
GTelemetry.Config.ConVars = {
    enabled = CreateConVar(
        "gtelemetry_enabled", "1",
        FCVAR_ARCHIVE + FCVAR_NOTIFY,
        "Enable or disable gTelemetry telemetry collection and export.",
        0, 1
    ),

    endpoint = CreateConVar(
        "gtelemetry_endpoint", "http://localhost:4318/v1/metrics",
        FCVAR_ARCHIVE + FCVAR_PROTECTED,
        "The Grafana Alloy OTLP HTTP endpoint URL."
    ),

    interval = CreateConVar(
        "gtelemetry_interval", "10",
        FCVAR_ARCHIVE,
        "Metrics collection and push interval in seconds.",
        1, 300
    ),

    service_name = CreateConVar(
        "gtelemetry_service_name", "gmod-server",
        FCVAR_ARCHIVE,
        "OTLP service.name resource attribute. Used to identify this server in Grafana."
    ),

    auth_token = CreateConVar(
        "gtelemetry_auth_token", "",
        FCVAR_ARCHIVE + FCVAR_PROTECTED,
        "Optional Bearer token for Alloy authentication. Leave empty to disable."
    ),

    debug = CreateConVar(
        "gtelemetry_debug", "0",
        FCVAR_ARCHIVE,
        "Enable verbose debug logging to server console.",
        0, 1
    ),

    darkrp = CreateConVar(
        "gtelemetry_darkrp", "1",
        FCVAR_ARCHIVE,
        "Enable DarkRP economic metrics (auto-detected).",
        0, 1
    ),

    entities_per_player = CreateConVar(
        "gtelemetry_entities_per_player", "1",
        FCVAR_ARCHIVE,
        "Enable per-player entity ownership breakdown metrics.",
        0, 1
    ),

    entities_interval = CreateConVar(
        "gtelemetry_entities_interval", "1",
        FCVAR_ARCHIVE,
        "Collect entity metrics every N cycles (1 = every cycle, 2 = every other, etc.). Higher values reduce CPU on large maps.",
        1, 20
    ),

    network_details = CreateConVar(
        "gtelemetry_network_details", "0",
        FCVAR_ARCHIVE,
        "Enable detailed net message name breakdown metrics (may cause high cardinality).",
        0, 1
    ),

    version = CreateConVar(
        "gtelemetry_version", GTelemetry.Version or "1.1.0",
        FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED,
        "Version of gTelemetry currently running."
    ),
}

--- Returns whether gTelemetry is enabled.
-- @return boolean
function GTelemetry.Config.IsEnabled()
    return GTelemetry.Config.ConVars.enabled:GetBool()
end

--- Returns the OTLP endpoint URL.
-- @return string
function GTelemetry.Config.GetEndpoint()
    local url = GTelemetry.Config.ConVars.endpoint:GetString()
    if url == "" then
        GTelemetry.Warn("No endpoint configured. Set gtelemetry_endpoint ConVar.")
    elseif not string_match(url, "^https?://") then
        GTelemetry.Warn("Invalid endpoint URL (must start with http:// or https://): " .. url)
    end
    return url
end

--- Returns the collection interval in seconds.
-- @return number
function GTelemetry.Config.GetInterval()
    return GTelemetry.Config.ConVars.interval:GetInt()
end

--- Returns the service name for OTLP resource attributes.
-- @return string
function GTelemetry.Config.GetServiceName()
    return GTelemetry.Config.ConVars.service_name:GetString()
end

--- Returns the Bearer auth token, or nil if empty.
-- @return string|nil
function GTelemetry.Config.GetAuthToken()
    local token = GTelemetry.Config.ConVars.auth_token:GetString()
    if token == "" then return nil end
    return token
end

--- Returns whether debug logging is enabled.
-- @return boolean
function GTelemetry.Config.IsDebug()
    return GTelemetry.Config.ConVars.debug:GetBool()
end

--- Returns whether DarkRP metrics are enabled.
-- @return boolean
function GTelemetry.Config.IsDarkRPEnabled()
    return GTelemetry.Config.ConVars.darkrp:GetBool()
end

--- Returns whether per-player entity breakdown is enabled.
-- @return boolean
function GTelemetry.Config.IsEntitiesPerPlayerEnabled()
    return GTelemetry.Config.ConVars.entities_per_player:GetBool()
end

--- Returns how often entity metrics are collected (every N cycles, 1 = every cycle).
-- @return number
function GTelemetry.Config.GetEntitiesInterval()
    return GTelemetry.Config.ConVars.entities_interval:GetInt()
end

--- Returns whether detailed net message breakdown is enabled.
-- @return boolean
function GTelemetry.Config.IsNetworkDetailsEnabled()
    return GTelemetry.Config.ConVars.network_details:GetBool()
end

--- Print a debug message to server console (only when debug mode is on).
-- @param ... any values to print
function GTelemetry.Debug(...)
    if not GTelemetry.Config.IsDebug() then return end
    local args = {...}
    local parts = {"[gTelemetry DEBUG]"}
    for _, v in ipairs(args) do
        table_insert(parts, tostring(v))
    end
    print(table_concat(parts, " "))
end

--- Print an info message to server console.
-- @param ... any values to print
function GTelemetry.Log(...)
    local args = {...}
    local parts = {"[gTelemetry]"}
    for _, v in ipairs(args) do
        table_insert(parts, tostring(v))
    end
    print(table_concat(parts, " "))
end

--- Print a warning message to server console.
-- @param ... any values to print
function GTelemetry.Warn(...)
    local args = {...}
    local parts = {"[gTelemetry WARNING]"}
    for _, v in ipairs(args) do
        table_insert(parts, tostring(v))
    end
    if Color then
        MsgC(Color(255, 200, 0), table_concat(parts, " ") .. "\n")
    else
        print(table_concat(parts, " "))
    end
end

-- Listen for interval changes to recreate the timer
cvars.AddChangeCallback("gtelemetry_interval", function(_, _, newVal)
    local interval = tonumber(newVal) or 10
    if interval < 1 then interval = 1 end

    if timer.Exists("GTelemetry_Collect") then
        timer.Adjust("GTelemetry_Collect", interval)
        GTelemetry.Log("Collection interval changed to " .. interval .. "s")
    end
end, "gtelemetry_interval_change")

-- Listen for network details toggle
cvars.AddChangeCallback("gtelemetry_network_details", function(_, _, newVal)
    if newVal == "1" then
        GTelemetry.Log("Network details enabled (may increase metric cardinality)")
    else
        GTelemetry.Log("Network details disabled")
    end
end, "gtelemetry_network_details_change")

-- Listen for enable/disable changes
cvars.AddChangeCallback("gtelemetry_enabled", function(_, _, newVal)
    local enabled = newVal == "1"
    if enabled then
        GTelemetry.Log("Telemetry enabled")
        if GTelemetry.StartCollection then
            if not timer.Exists("GTelemetry_Collect") then
                GTelemetry.StartCollection()
            end
        else
            GTelemetry.Warn("GTelemetry.StartCollection not available yet (modules still loading)")
        end
    else
        GTelemetry.Log("Telemetry disabled")
        if timer.Exists("GTelemetry_Collect") then
            timer.Remove("GTelemetry_Collect")
        end
        if GTelemetry.Collectors.Network and GTelemetry.Collectors.Network.Undo then
            GTelemetry.Collectors.Network.Undo()
        end
    end
end, "gtelemetry_enabled_change")


