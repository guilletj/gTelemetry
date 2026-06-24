--[[
    gTelemetry: GMod Telemetry
    collectors/sv_chat.lua — Chat & admin command tracking

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

    Collects: chat message count, admin command count.
    Supports auto-detection of common admin mods (ULX, SAM, FAdmin).
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Chat = {}

-- Tracking state
local _chatMessages = 0
local _adminCommands = 0
local _startTimeNano = nil
local _initialized = false

local MakeSum = nil
local MakeCumulativeDataPoint = nil

function GTelemetry.Collectors.Chat.Init()
    if _initialized then return end
    _initialized = true

    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()

    -- Track chat messages (admin commands are tracked via admin mod hooks below)
    hook.Add("PlayerSay", "GTelemetry_ChatTracker", function(ply, text, teamOnly)
        _chatMessages = _chatMessages + 1
    end)

    -- Hook into ULX/SAM (safe even if events don't exist yet)
    hook.Add("ULibCommandCalled", "GTelemetry_ULXTracker", function(ply, cmd, args)
        _adminCommands = _adminCommands + 1
    end)

    hook.Add("SAM.PlayerCommand", "GTelemetry_SAMTracker", function(ply, cmd, args)
        _adminCommands = _adminCommands + 1
    end)

    GTelemetry.Debug("Chat collector initialized")
end

function GTelemetry.Collectors.Chat.Undo()
    if not _initialized then return end
    _initialized = false

    hook.Remove("PlayerSay", "GTelemetry_ChatTracker")
    hook.Remove("ULibCommandCalled", "GTelemetry_ULXTracker")
    hook.Remove("SAM.PlayerCommand", "GTelemetry_SAMTracker")

    _chatMessages = 0
    _adminCommands = 0
    _startTimeNano = nil
    MakeSum = nil
    MakeCumulativeDataPoint = nil

    GTelemetry.Debug("Chat collector stopped")
end

--- Collect chat and admin metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Chat.Collect()
    if not MakeSum then GTelemetry.Collectors.Chat.Init() end

    local metrics = {}

    -- Chat messages (cumulative counter)
    metrics[#metrics + 1] = MakeSum(
        "gmod.chat.messages",
        "Total chat messages since server start",
        "{messages}",
        {MakeCumulativeDataPoint(_chatMessages, _startTimeNano)},
        true
    )

    -- Admin commands (cumulative counter)
    metrics[#metrics + 1] = MakeSum(
        "gmod.admin.commands",
        "Total admin commands executed since server start",
        "{commands}",
        {MakeCumulativeDataPoint(_adminCommands, _startTimeNano)},
        true
    )

    return metrics
end
