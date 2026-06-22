--[[
    gTelemetry: GMod Telemetry
    cl_gtelemetry.lua — Client-side FPS reporter

    Sends the client's FPS to the server periodically via the net library.
    This data is used by the server-side Players collector.
]]

local SEND_INTERVAL = 5 -- Send FPS every 5 seconds

timer.Create("GTelemetry_ClientFPS", SEND_INTERVAL, 0, function()
    local frameTime = FrameTime()
    if frameTime <= 0 then return end

    local fps = math.min(1 / frameTime, 999)

    net.Start("GTelemetry_ClientData")
        net.WriteFloat(fps)
    net.SendToServer()
end)
