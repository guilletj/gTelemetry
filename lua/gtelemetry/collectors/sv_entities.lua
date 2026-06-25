--[[
    gTelemetry: GMod Telemetry
    collectors/sv_entities.lua — Entity count metrics

    SPDX-License-Identifier: MIT
    Copyright (c) 2026 Edyone

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

local _typeNames = {
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

-- Entity classes that NEVER have physics objects (blacklist for GetPhysicsObject optimization)
local _noPhysicsPrefix = {
    env_ = true,
    point_ = true,
    info_ = true,
    path_ = true,
    logic_ = true,
    ai_ = true,
    trigger_ = true,
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
    if string_StartWith(class, "prop_physics") then
        return ENTITY_PROPS
    elseif class == "prop_ragdoll" then
        return ENTITY_RAGDOLL
    elseif string_StartWith(class, "prop_door") then
        return ENTITY_DOOR
    elseif string_StartWith(class, "prop_") then
        return ENTITY_PROPS
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
    return _typeNames[t] or "other"
end

function GTelemetry.Collectors.Entities.Init()
    if _initialized then return end
    _initialized = true
    MakeGauge = GTelemetry.OTLP.MakeGauge
    MakeDataPoint = GTelemetry.OTLP.MakeDataPoint
    Attribute = GTelemetry.OTLP.Attribute
end

function GTelemetry.Collectors.Entities.Undo()
    if not _initialized then return end
    _initialized = false
    MakeGauge = nil
    MakeDataPoint = nil
    Attribute = nil
    _cycleCount = 0
end

--- Collect entity count metrics.
-- @return table list of OTLP metric objects
function GTelemetry.Collectors.Entities.Collect()
    if not MakeGauge then GTelemetry.Collectors.Entities.Init() end

    -- Skip collection per gtelemetry_entities_interval to reduce CPU on large maps
    local skipEvery = GTelemetry.Config.GetEntitiesInterval()
    if skipEvery > 1 then
        _cycleCount = (_cycleCount + 1) % skipEvery
        if _cycleCount ~= 1 then
            return nil
        end
    end

    local metrics = {}
    local allEnts = ents.GetAll()
    local totalCount = #allEnts

    local worldTypeCounts = {}
    local playerTypeCounts = {}

    local perPlayer = {} -- [steamID] = { name, types: { [type] = count } }

    local trackPerPlayer = GTelemetry.Config.IsEntitiesPerPlayerEnabled()

    local physicsCount = 0

    for _, ent in ipairs(allEnts) do
        if IsValid(ent) then
            local class = ent:GetClass()
            local etype = ClassifyEntity(ent, class)

            -- Physics objects (only check classes that can have physics)
            if EntityHasPhysics(class) then
                local ok, phys = pcall(ent.GetPhysicsObject, ent)
                if ok and IsValid(phys) then
                    physicsCount = physicsCount + 1
                end
            end

            -- Owner detection (always — used for world vs player breakdown)
            local owner = ent.CPPIGetOwner and ent:CPPIGetOwner()
            if not IsValid(owner) then
                owner = ent.GetCreator and ent:GetCreator()
            end

            local isPlayerOwned = IsValid(owner) and owner:IsPlayer()
            if isPlayerOwned then
                playerTypeCounts[etype] = (playerTypeCounts[etype] or 0) + 1
            else
                worldTypeCounts[etype] = (worldTypeCounts[etype] or 0) + 1
            end

            -- Per-player ownership breakdown (gated by convar)
            if trackPerPlayer and isPlayerOwned then
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

    -- Players (entity count)
    metrics[#metrics + 1] = MakeGauge(
        "gmod.entities.players",
        "Number of player entities",
        "{entities}",
        {MakeDataPoint(player.GetCount())}
    )

    -- Physics objects
    metrics[#metrics + 1] = MakeGauge(
        "gmod.physics.objects",
        "Number of entities with an active physics object",
        "{objects}",
        {MakeDataPoint(physicsCount)}
    )

    -- Breakdown by type + owner
    local ownerBreakdownPoints = {}
    for etype, count in pairs(worldTypeCounts) do
        ownerBreakdownPoints[#ownerBreakdownPoints + 1] = MakeDataPoint(count, {
            Attribute("entity.type", TypeName(etype)),
            Attribute("entity.owner", "world"),
        })
    end
    for etype, count in pairs(playerTypeCounts) do
        ownerBreakdownPoints[#ownerBreakdownPoints + 1] = MakeDataPoint(count, {
            Attribute("entity.type", TypeName(etype)),
            Attribute("entity.owner", "player"),
        })
    end
    if #ownerBreakdownPoints > 0 then
        metrics[#metrics + 1] = MakeGauge(
            "gmod.entities.by_type",
            "Number of entities grouped by type and owner (world vs player)",
            "{entities}",
            ownerBreakdownPoints
        )
    end

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
