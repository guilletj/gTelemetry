--[[
    gTelemetry: GMod Telemetry
    collectors/sv_chat.lua — Chat & admin command tracking

    Collects: chat message count, admin command count.
    Supports auto-detection of common admin mods (ULX, SAM, FAdmin).
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Chat = {}

-- Tracking state
local _chatMessages = 0
local _adminCommands = 0
local _startTimeNano = nil

local MakeSum = nil
local MakeCumulativeDataPoint = nil

function GTelemetry.Collectors.Chat.Init()
    MakeSum = GTelemetry.OTLP.MakeSum
    MakeCumulativeDataPoint = GTelemetry.OTLP.MakeCumulativeDataPoint
    _startTimeNano = GTelemetry.OTLP.GetTimeNano()

    -- Track chat messages
    hook.Add("PlayerSay", "GTelemetry_ChatTracker", function(ply, text, teamOnly)
        _chatMessages = _chatMessages + 1

        -- Detect admin commands by prefix
        -- Common admin command prefixes: !, /, @
        if string.StartWith(text, "!") or string.StartWith(text, "/") or string.StartWith(text, "@") then
            -- Check if this looks like an admin command (not just a regular message)
            local firstWord = string.match(text, "^[!/@](%w+)")
            if firstWord and #firstWord >= 2 then
                _adminCommands = _adminCommands + 1
            end
        end
    end)

    -- Hook into ULX if available
    if ulx then
        hook.Add("ULibCommandCalled", "GTelemetry_ULXTracker", function(ply, cmd, args)
            _adminCommands = _adminCommands + 1
        end)
        GTelemetry.Debug("ULX admin mod detected, tracking admin commands")
    end

    -- Hook into SAM if available
    if sam then
        hook.Add("SAM.PlayerCommand", "GTelemetry_SAMTracker", function(ply, cmd, args)
            _adminCommands = _adminCommands + 1
        end)
        GTelemetry.Debug("SAM admin mod detected, tracking admin commands")
    end

    GTelemetry.Debug("Chat collector initialized")
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
