--[[
    gTelemetry: GMod Telemetry
    cl_gtelemetry.lua — Client-side FPS reporter + ready signal

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Sends the client's FPS to the server periodically via the net library.
    Also signals the server immediately when the client code is loaded.
    This data is used by the server-side Players collector.
]]

local SEND_INTERVAL = 5 -- Send FPS every 5 seconds

-- Signal server that this client's addon code is loaded (one-shot next frame)
-- Deferred via timer.Simple so net is fully initialized.
local function SendClientReady()
    local ok, err = pcall(function()
        net.Start("GTelemetry_ClientReady")
        net.SendToServer()
    end)
    if not ok and GTelemetry and GTelemetry.Debug then
        GTelemetry.Debug("Failed to send client ready: " .. tostring(err))
    end
end

timer.Simple(0, SendClientReady)

-- Retransmit ready signal if server requests it (e.g. after hot-reload)
net.Receive("GTelemetry_RequestReady", function() SendClientReady() end)

timer.Create("GTelemetry_ClientFPS", SEND_INTERVAL, 0, function()
    local frameTime = FrameTime()
    if frameTime <= 0 then return end

    local fps = math.min(1 / frameTime, 999)

    local ok, err = pcall(function()
        net.Start("GTelemetry_ClientData")
            net.WriteFloat(fps)
        net.SendToServer()
    end)
    if not ok and GTelemetry and GTelemetry.Debug then
        GTelemetry.Debug("Failed to send client FPS: " .. tostring(err))
    end
end)
