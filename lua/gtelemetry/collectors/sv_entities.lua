--[[
    gTelemetry: GMod Telemetry
    collectors/sv_entities.lua — Entity count metrics

    Collects: total entities, props, NPCs, players, weapons, vehicles.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Entities = {}

local MakeGauge = nil
local MakeDataPoint = nil
local Attribute = nil

function GTelemetry.Collectors.Entities.Init()
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
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
    local ragdollCount = 0
    local constraintCount = 0
    local scriptedEntCount = 0
    local doorCount = 0
    local effectCount = 0
    local physicsCount = 0

    local perPlayer = {} -- [steamID] = { name, types: { [type] = count } }

    local trackPerPlayer = GTelemetry.Config.IsEntitiesPerPlayerEnabled()

    for _, ent in ipairs(allEnts) do
        if not IsValid(ent) then continue end

        local class = ent:GetClass()

        if string.StartWith(class, "prop_physics") or class == "prop_dynamic" then
            propCount = propCount + 1
        elseif class == "prop_ragdoll" then
            ragdollCount = ragdollCount + 1
        elseif string.StartWith(class, "npc_") then
            npcCount = npcCount + 1
        elseif ent:IsWeapon() then
            weaponCount = weaponCount + 1
        elseif ent:IsVehicle() then
            vehicleCount = vehicleCount + 1
        elseif string.StartWith(class, "prop_door") or string.StartWith(class, "func_door") then
            doorCount = doorCount + 1
        elseif string.StartWith(class, "sent_") or string.StartWith(class, "gmod_") then
            scriptedEntCount = scriptedEntCount + 1
        elseif string.StartWith(class, "constraint_") or string.StartWith(class, "rope_") or string.StartWith(class, "hydraulic_") then
            constraintCount = constraintCount + 1
        elseif string.StartWith(class, "env_") then
            effectCount = effectCount + 1
        end

        -- Physics objects
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            physicsCount = physicsCount + 1
        end

        -- Per-player ownership tracking
        if trackPerPlayer then
            local owner = ent:CPPIGetOwner and ent:CPPIGetOwner()
            if not IsValid(owner) then
                owner = ent:GetCreator and ent:GetCreator()
            end

            if IsValid(owner) and owner:IsPlayer() then
                local sid = owner:SteamID()
                if not perPlayer[sid] then
                    perPlayer[sid] = { name = owner:Nick(), types = {}, others = {} }
                end
                local entityType = "other"
                if string.StartWith(class, "prop_physics") or class == "prop_dynamic" then
                    entityType = "prop"
                elseif class == "prop_ragdoll" then
                    entityType = "ragdoll"
                elseif string.StartWith(class, "prop_door") or string.StartWith(class, "func_door") then
                    entityType = "door"
                elseif string.StartWith(class, "sent_") or string.StartWith(class, "gmod_") then
                    entityType = "scripted_ent"
                elseif string.StartWith(class, "constraint_") or string.StartWith(class, "rope_") or string.StartWith(class, "hydraulic_") then
                    entityType = "constraint"
                elseif ent:IsVehicle() then
                    entityType = "vehicle"
                elseif ent:IsWeapon() then
                    entityType = "weapon"
                end
                if entityType == "other" then
                    perPlayer[sid].others[class] = (perPlayer[sid].others[class] or 0) + 1
                else
                    perPlayer[sid].types[entityType] = (perPlayer[sid].types[entityType] or 0) + 1
                end
            end
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

    -- Ragdolls
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.ragdolls",
        "Number of ragdoll entities",
        "{entities}",
        {MakeDataPoint(ragdollCount)}
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

    -- Doors
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.doors",
        "Number of door entities",
        "{entities}",
        {MakeDataPoint(doorCount)}
    )

    -- Scripted entities (SENTs)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.scripted_ents",
        "Number of scripted entities (SENTs)",
        "{entities}",
        {MakeDataPoint(scriptedEntCount)}
    )

    -- Constraints
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.constraints",
        "Number of constraint/rope/hydraulic entities",
        "{entities}",
        {MakeDataPoint(constraintCount)}
    )

    -- Effects
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.effects",
        "Number of effect entities",
        "{entities}",
        {MakeDataPoint(effectCount)}
    )

    -- Physics objects
    metrics[#metrics + 1] = MakeGauge(
        "gmod.physics.objects",
        "Number of entities with an active physics object",
        "{objects}",
        {MakeDataPoint(physicsCount)}
    )

    -- Per-player entity ownership breakdown
    if trackPerPlayer then
        local ownedPoints = {}
        for sid, data in pairs(perPlayer) do
            for etype, count in pairs(data.types) do
                ownedPoints[#ownedPoints + 1] = MakeDataPoint(count, {
                    Attribute("player.name", data.name),
                    Attribute("player.steam_id", sid),
                    Attribute("entity.type", etype),
                })
            end
            for class, count in pairs(data.others) do
                ownedPoints[#ownedPoints + 1] = MakeDataPoint(count, {
                    Attribute("player.name", data.name),
                    Attribute("player.steam_id", sid),
                    Attribute("entity.type", "other"),
                    Attribute("entity.class", class),
                })
            end
        end
        if #ownedPoints > 0 then
            metrics[#metrics + 1] = MakeGauge(
                "gmod.entities.owned_by_player",
                "Number of entities owned per player, grouped by type",
                "{entities}",
                ownedPoints
            )
        end
    end

    return metrics
end
