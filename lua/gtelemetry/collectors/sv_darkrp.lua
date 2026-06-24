--[[
    gTelemetry: GMod Telemetry
    collectors/sv_darkrp.lua — DarkRP economic metrics

    Auto-loaded only when DarkRP is detected.
    Collects: money in circulation, average money, jobs, props per player,
    wanted/arrested counts.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.DarkRP = {}

local pairs = pairs
local ipairs = ipairs
local MakeGauge = nil
local MakeDataPoint = nil
local Attribute = nil
local _initialized = false

function GTelemetry.Collectors.DarkRP.Init()
    if _initialized then return end
    _initialized = true
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
end

--- Check if DarkRP is available.
-- @return boolean
function GTelemetry.Collectors.DarkRP.IsAvailable()
    return DarkRP ~= nil and DarkRP.getPhrase ~= nil
end

--- Collect DarkRP economic metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.DarkRP.Collect()
    if not MakeGauge then GTelemetry.Collectors.DarkRP.Init() end

    -- Skip if DarkRP is not available or disabled
    -- Return nil so CollectAndSend skips the iteration gracefully
    if not GTelemetry.Collectors.DarkRP.IsAvailable() then return nil end
    if not GTelemetry.Config.IsDarkRPEnabled() then return nil end

    local metrics = {}
    local players = player.GetAll()

    local totalMoney = 0
    local humanCount = 0
    local moneyPoints = {}
    local jobCounts = {}   -- [jobName] = count
    local wantedCount = 0
    local arrestedCount = 0
    local propsPerPlayer = {}

    for _, ply in ipairs(players) do
        if not IsValid(ply) or ply:IsBot() then continue end

        humanCount = humanCount + 1

        -- Money
        local money = ply.getDarkRPVar and ply:getDarkRPVar("money") or 0
        totalMoney = totalMoney + (money or 0)
        if money and money > 0 then
            moneyPoints[#moneyPoints + 1] = MakeDataPoint(money, {
                Attribute("player.name", ply:Nick()),
                Attribute("player.steam_id", ply:SteamID()),
            })
        end

        -- Job
        local jobTable = ply.getJobTable and ply:getJobTable()
        if jobTable and jobTable.name then
            local jobName = jobTable.name
            jobCounts[jobName] = (jobCounts[jobName] or 0) + 1
        end

        -- Wanted status
        if ply.getDarkRPVar and ply:getDarkRPVar("wanted") then
            wantedCount = wantedCount + 1
        end

        -- Arrested status
        if ply.isArrested and ply:isArrested() then
            arrestedCount = arrestedCount + 1
        end

        -- Props count (using Cleanup system)
        if ply.GetCount then
            local propCount = ply:GetCount("props") or 0
            if propCount > 0 then
                propsPerPlayer[#propsPerPlayer + 1] = {
                    player = ply,
                    count = propCount,
                }
            end
        end
    end

    -- Total money in circulation
    metrics[#metrics + 1] = MakeGauge(
        "gmod.darkrp.money_total",
        "Total money in circulation across all players",
        "{currency}",
        {MakeDataPoint(totalMoney)}
    )

    -- Average money per player
    if humanCount > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.darkrp.money_avg",
            "Average money per player",
            "{currency}",
            {MakeDataPoint(math.Round(totalMoney / humanCount, 2))}
        )
    end

    -- Money per player
    if #moneyPoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.darkrp.money_per_player",
            "Money per individual player",
            "{currency}",
            moneyPoints
        )
    end

    -- Job distribution
    local jobPoints = {}
    for jobName, count in pairs(jobCounts) do
        jobPoints[#jobPoints + 1] = MakeDataPoint(count, {
            Attribute("darkrp.job", jobName),
        })
    end

    if #jobPoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.darkrp.job_count",
            "Number of players per DarkRP job",
            "{players}",
            jobPoints
        )
    end

    -- Props per player
    local propPoints = {}
    for _, data in ipairs(propsPerPlayer) do
        local ply = data.player
        if IsValid(ply) then
            propPoints[#propPoints + 1] = MakeDataPoint(data.count, {
                Attribute("player.name", ply:Nick()),
                Attribute("player.steam_id", ply:SteamID()),
            })
        end
    end

    if #propPoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.darkrp.props_per_player",
            "Number of props spawned per player",
            "{props}",
            propPoints
        )
    end

    -- Wanted count
    metrics[#metrics + 1] = MakeGauge(
        "gmod.darkrp.wanted_count",
        "Number of wanted players",
        "{players}",
        {MakeDataPoint(wantedCount)}
    )

    -- Arrested count
    metrics[#metrics + 1] = MakeGauge(
        "gmod.darkrp.arrested_count",
        "Number of arrested players",
        "{players}",
        {MakeDataPoint(arrestedCount)}
    )

    return metrics
end
