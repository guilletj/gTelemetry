--[[
    gTelemetry: GMod Telemetry
    collectors/sv_entities.lua — Entity count metrics

    Collects: total entities, props, NPCs, players, weapons, vehicles.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Entities = {}

local MakeGauge = nil
local MakeDataPoint = nil

function GTelemetry.Collectors.Entities.Init()
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
end

--- Collect entity count metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Entities.Collect()
    if not MakeGauge then GTelemetry.Collectors.Entities.Init() end

    local metrics = {}
    local allEnts = ents.GetAll()
    local totalCount = #allEnts

    local propCount = 0
    local npcCount = 0
    local weaponCount = 0
    local vehicleCount = 0

    for _, ent in ipairs(allEnts) do
        if not IsValid(ent) then continue end

        local class = ent:GetClass()

        if string.StartWith(class, "prop_physics") or class == "prop_dynamic" then
            propCount = propCount + 1
        elseif string.StartWith(class, "npc_") then
            npcCount = npcCount + 1
        elseif ent:IsWeapon() then
            weaponCount = weaponCount + 1
        elseif ent:IsVehicle() then
            vehicleCount = vehicleCount + 1
        end
    end

    -- Total entities
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.total",
        "Total number of entities in the world",
        "{entities}",
        {MakeDataPoint(totalCount)}
    )

    -- Props
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.props",
        "Number of prop entities",
        "{entities}",
        {MakeDataPoint(propCount)}
    )

    -- NPCs
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.npcs",
        "Number of NPC entities",
        "{entities}",
        {MakeDataPoint(npcCount)}
    )

    -- Players (entity count)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.players",
        "Number of player entities",
        "{entities}",
        {MakeDataPoint(player.GetCount())}
    )

    -- Weapons
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.weapons",
        "Number of weapon entities",
        "{entities}",
        {MakeDataPoint(weaponCount)}
    )

    -- Vehicles
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.vehicles",
        "Number of vehicle entities",
        "{entities}",
        {MakeDataPoint(vehicleCount)}
    )

    return metrics
end
