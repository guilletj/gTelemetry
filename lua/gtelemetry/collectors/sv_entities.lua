--[[
    gTelemetry: GMod Telemetry
    collectors/sv_entities.lua — Entity count metrics

    Collects: total entities, props, NPCs, players, weapons, vehicles.
]]

GTelemetry.Collectors = GTelemetry.Collectors or {}
GTelemetry.Collectors.Entities = {}

local pairs = pairs
local ipairs = ipairs
local string_StartWith = string.StartWith
local MakeGauge = nil
local MakeDataPoint = nil
local Attribute = nil
local _initialized = false
local _cycleCount = 0

-- Entity type classification constants
local ENTITY_PROPS = 1
local ENTITY_RAGDOLL = 2
local ENTITY_NPC = 3
local ENTITY_WEAPON = 4
local ENTITY_VEHICLE = 5
local ENTITY_DOOR = 6
local ENTITY_SCRIPTED = 7
local ENTITY_CONSTRAINT = 8
local ENTITY_EFFECT = 9
local ENTITY_OTHER = 10

-- Entity classes that NEVER have physics objects (blacklist for GetPhysicsObject optimization)
local _noPhysicsPrefix = {
    env_ = true,
    point_ = true,
    info_ = true,
    path_ = true,
    logic_ = true,
    ai_ = true,
    trigger_ = true,
    func_ = true,
    item_ = true,
    math_ = true,
    scene_ = true,
    shadow_ = true,
    sprite_ = true,
    light_ = true,
}

--- Classify an entity into a numeric type.
-- @param ent Entity
-- @param class string pre-fetched class name
-- @return number entity type constant
local function ClassifyEntity(ent, class)
    if string_StartWith(class, "prop_physics") or class == "prop_dynamic" then
        return ENTITY_PROPS
    elseif class == "prop_ragdoll" then
        return ENTITY_RAGDOLL
    elseif string_StartWith(class, "npc_") then
        return ENTITY_NPC
    elseif ent:IsWeapon() then
        return ENTITY_WEAPON
    elseif ent:IsVehicle() then
        return ENTITY_VEHICLE
    elseif string_StartWith(class, "prop_door") or string_StartWith(class, "func_door") then
        return ENTITY_DOOR
    elseif string_StartWith(class, "sent_") or string_StartWith(class, "gmod_") then
        return ENTITY_SCRIPTED
    elseif string_StartWith(class, "constraint_") or string_StartWith(class, "rope_") or string_StartWith(class, "hydraulic_") then
        return ENTITY_CONSTRAINT
    elseif string_StartWith(class, "env_") then
        return ENTITY_EFFECT
    end
    return ENTITY_OTHER
end

--- Check if an entity class may have a physics object (avoids expensive GetPhysicsObject call on known non-physics entities).
-- @param class string class name
-- @return boolean
local function EntityHasPhysics(class)
    for prefix in pairs(_noPhysicsPrefix) do
        if string_StartWith(class, prefix) then return false end
    end
    return true
end

local function TypeName(t)
    local names = {
        [ENTITY_PROPS] = "prop",
        [ENTITY_RAGDOLL] = "ragdoll",
        [ENTITY_NPC] = "npc",
        [ENTITY_WEAPON] = "weapon",
        [ENTITY_VEHICLE] = "vehicle",
        [ENTITY_DOOR] = "door",
        [ENTITY_SCRIPTED] = "scripted_ent",
        [ENTITY_CONSTRAINT] = "constraint",
        [ENTITY_EFFECT] = "effect",
    }
    return names[t] or "other"
end

function GTelemetry.Collectors.Entities.Init()
    if _initialized then return end
    _initialized = true
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
end

--- Collect entity count metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Entities.Collect()
    if not MakeGauge then GTelemetry.Collectors.Entities.Init() end

    -- Skip collection per gtelemetry_entities_interval to reduce CPU on large maps
    local skipEvery = GTelemetry.Config.GetEntitiesInterval()
    if skipEvery > 1 then
        _cycleCount = _cycleCount + 1
        if _cycleCount % skipEvery ~= 0 then
            return nil
        end
    end

    local metrics = {}
    local allEnts = ents.GetAll()
    local totalCount = #allEnts

    local typeCounts = {}

    local perPlayer = {} -- [steamID] = { name, types: { [type] = count } }

    local trackPerPlayer = GTelemetry.Config.IsEntitiesPerPlayerEnabled()

    local physicsCount = 0

    for _, ent in ipairs(allEnts) do
        if not IsValid(ent) then continue end

        local class = ent:GetClass()
        local etype = ClassifyEntity(ent, class)

        typeCounts[etype] = (typeCounts[etype] or 0) + 1

        -- Physics objects (only check classes that can have physics)
        if EntityHasPhysics(class) then
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                physicsCount = physicsCount + 1
            end
        end

        -- Per-player ownership tracking
        if trackPerPlayer then
            local owner = ent.CPPIGetOwner and ent:CPPIGetOwner()
            if not IsValid(owner) then
                owner = ent.GetCreator and ent:GetCreator()
            end

            if IsValid(owner) and owner:IsPlayer() then
                local sid = owner:SteamID()
                if not perPlayer[sid] then
                    perPlayer[sid] = { name = owner:Nick(), types = {}, others = {} }
                end
                if etype == ENTITY_OTHER then
                    perPlayer[sid].others[class] = (perPlayer[sid].others[class] or 0) + 1
                else
                    local name = TypeName(etype)
                    perPlayer[sid].types[name] = (perPlayer[sid].types[name] or 0) + 1
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
        {MakeDataPoint(typeCounts[ENTITY_PROPS] or 0)}
    )

    -- Ragdolls
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.ragdolls",
        "Number of ragdoll entities",
        "{entities}",
        {MakeDataPoint(typeCounts[ENTITY_RAGDOLL] or 0)}
    )

    -- NPCs
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.npcs",
        "Number of NPC entities",
        "{entities}",
        {MakeDataPoint(typeCounts[ENTITY_NPC] or 0)}
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
        {MakeDataPoint(typeCounts[ENTITY_WEAPON] or 0)}
    )

    -- Vehicles
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.vehicles",
        "Number of vehicle entities",
        "{entities}",
        {MakeDataPoint(typeCounts[ENTITY_VEHICLE] or 0)}
    )

    -- Doors
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.doors",
        "Number of door entities",
        "{entities}",
        {MakeDataPoint(typeCounts[ENTITY_DOOR] or 0)}
    )

    -- Scripted entities (SENTs)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.scripted_ents",
        "Number of scripted entities (SENTs)",
        "{entities}",
        {MakeDataPoint(typeCounts[ENTITY_SCRIPTED] or 0)}
    )

    -- Constraints
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.constraints",
        "Number of constraint/rope/hydraulic entities",
        "{entities}",
        {MakeDataPoint(typeCounts[ENTITY_CONSTRAINT] or 0)}
    )

    -- Effects
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.effects",
        "Number of effect entities",
        "{entities}",
        {MakeDataPoint(typeCounts[ENTITY_EFFECT] or 0)}
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
