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

-- Track FPS via Think hook using SysTime.
-- FrameTime() in client timers returns the server tick interval, not the
-- rendering frame time, so it would show server FPS instead of client FPS.
local _lastThinkTime = SysTime()
local _currentFps = 0

hook.Add("Think", "GTelemetry_FPSTracker", function()
    local now = SysTime()
    local dt = now - _lastThinkTime
    _lastThinkTime = now
    if dt <= 0 or dt > 1 then return end
    _currentFps = math.min(1 / dt, 999)
end)

-- Signal server that this client's addon code is loaded (one-shot next frame)
-- Deferred via timer.Simple so net is fully initialized.
local function SendClientReady()
    local ok, err = pcall(function()
        net.Start("GTelemetry_ClientReady")
        net.SendToServer()
    end)
    if not ok then
        print("[gTelemetry] Failed to send client ready: " .. tostring(err))
    end
end

timer.Simple(0, SendClientReady)

-- Retransmit ready signal if server requests it (e.g. after hot-reload)
net.Receive("GTelemetry_RequestReady", function() SendClientReady() end)

timer.Create("GTelemetry_ClientFPS", SEND_INTERVAL, 0, function()
    if _currentFps <= 0 then return end

    local ok, err = pcall(function()
        net.Start("GTelemetry_ClientData")
            net.WriteFloat(_currentFps)
        net.SendToServer()
    end)
    if not ok then
        print("[gTelemetry] Failed to send client FPS: " .. tostring(err))
    end
end)
