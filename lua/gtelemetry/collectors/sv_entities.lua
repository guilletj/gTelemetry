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
local string_match = string.match
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

local _allTypes = {
    ENTITY_PROPS, ENTITY_RAGDOLL, ENTITY_NPC, ENTITY_WEAPON,
    ENTITY_VEHICLE, ENTITY_DOOR, ENTITY_SCRIPTED, ENTITY_CONSTRAINT,
    ENTITY_EFFECT, ENTITY_OTHER,
}

-- Class cache: class names never change, so cache classification results.
-- Normal table is fine (<200 unique classes per map).
local _classCache = {}
local _noPhysicsCache = {}  -- classes confirmed to have no physics object
local _hasPhysicsCache = {} -- classes confirmed to have a physics object

-- Non-physics prefix pattern. Covers env_, ai_, logic_, math_, light_, trigger_.
-- 'i' is split explicitly: info_ (no physics) excluded here, item_ (has physics) not.
-- 'p' and 's' prefixes are disambiguated in EntityHasPhysics (prop_/sent_ have physics,
-- point_/path_/scene_/shadow_/sprite_ don't).
local _physicsNoMatch = "^[aelmt]"

--- Classify an entity into a numeric type. Results cached by class string.
-- @param ent Entity
-- @param class string pre-fetched class name
-- @return number entity type constant
local function ClassifyEntity(ent, class)
    local cached = _classCache[class]
    if cached then return cached end
    local result
    if string_StartWith(class, "prop_physics") then
        result = ENTITY_PROPS
    elseif class == "prop_ragdoll" then
        result = ENTITY_RAGDOLL
    elseif string_StartWith(class, "prop_door") then
        result = ENTITY_DOOR
    elseif string_StartWith(class, "npc_") then
        result = ENTITY_NPC
    elseif ent:IsWeapon() then
        result = ENTITY_WEAPON
    elseif ent:IsVehicle() then
        result = ENTITY_VEHICLE
    elseif string_StartWith(class, "prop_") then
        result = ENTITY_PROPS
    elseif string_StartWith(class, "func_door") then
        result = ENTITY_DOOR
    elseif string_StartWith(class, "sent_") or string_StartWith(class, "gmod_") then
        result = ENTITY_SCRIPTED
    elseif string_StartWith(class, "constraint_") or string_StartWith(class, "rope_") or string_StartWith(class, "hydraulic_") then
        result = ENTITY_CONSTRAINT
    elseif string_StartWith(class, "env_") then
        result = ENTITY_EFFECT
    else
        result = ENTITY_OTHER
    end
    _classCache[class] = result
    return result
end

--- Check if an entity class may have a physics object (avoids expensive GetPhysicsObject call on known non-physics entities).
-- Regex for 6 non-physics prefixes + explicit disambiguation for 'i', 'p', and 's' prefixes
-- (info_ has no physics, item_ does; point_/path_ have no physics, prop_ does;
--  scene_/shadow_/sprite_ have no physics, sent_ does).
-- Matches: env_, ai_, logic_, math_, light_, trigger_, info_, point_, path_, scene_, shadow_, sprite_
-- @param class string class name
-- @return boolean
local function EntityHasPhysics(class)
    if string_match(class, _physicsNoMatch) then return false end
    if string_StartWith(class, "info_") then return false end
    if string_StartWith(class, "point_") or string_StartWith(class, "path_") then return false end
    if string_StartWith(class, "scene_") or string_StartWith(class, "shadow_") or string_StartWith(class, "sprite_") or string_StartWith(class, "predicted_") or string_StartWith(class, "move_") or string_StartWith(class, "nav_") then return false end
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
    _cycleCount = 0
end

function GTelemetry.Collectors.Entities.Undo()
    if not _initialized then return end
    _initialized = false
    MakeGauge = nil
    MakeDataPoint = nil
    Attribute = nil
    _cycleCount = 0
    _classCache = {}
_noPhysicsCache = {}
    _hasPhysicsCache = {}
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
    for _, v in ipairs(_allTypes) do
        worldTypeCounts[v] = 0
        playerTypeCounts[v] = 0
    end

    local perPlayer = {} -- [steamID] = { name, types: { [type] = count } }

    local trackPerPlayer = GTelemetry.Config.IsEntitiesPerPlayerEnabled()

    local physicsCount = 0

    for _, ent in ipairs(allEnts) do
        if IsValid(ent) then
            local class = ent:GetClass()
            local etype = ClassifyEntity(ent, class)

            -- Physics objects (only check classes that can have physics)
            if EntityHasPhysics(class) then
                if not _noPhysicsCache[class] and not _hasPhysicsCache[class] then
                    local ok, phys = pcall(ent.GetPhysicsObject, ent)
                    if ok and IsValid(phys) then
                        _hasPhysicsCache[class] = true
                        physicsCount = physicsCount + 1
                    else
                        _noPhysicsCache[class] = true
                    end
                elseif _hasPhysicsCache[class] then
                    physicsCount = physicsCount + 1
                end
            end

            -- Owner detection (always — used for world vs player breakdown)
            local owner
            local cppiFn = ent.CPPIGetOwner
            local okOwner
            if type(cppiFn) == "function" then
                okOwner, owner = pcall(cppiFn, ent)
            end
            if not okOwner or not IsValid(owner) then
                local okCreator, creator = pcall(ent.GetCreator, ent)
                if okCreator then owner = creator end
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
        if count > 0 then
            ownerBreakdownPoints[#ownerBreakdownPoints + 1] = MakeDataPoint(count, {
                Attribute("entity.type", TypeName(etype)),
                Attribute("entity.owner", "world"),
            })
        end
    end
    for etype, count in pairs(playerTypeCounts) do
        if count > 0 then
            ownerBreakdownPoints[#ownerBreakdownPoints + 1] = MakeDataPoint(count, {
                Attribute("entity.type", TypeName(etype)),
                Attribute("entity.owner", "player"),
            })
        end
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
                local attrs = GTelemetry.OTLP.PlayerAttrs(data.name, sid)
                attrs[#attrs + 1] = Attribute("entity.type", etype)
                ownedPoints[#ownedPoints + 1] = MakeDataPoint(count, attrs)
            end
            for class, count in pairs(data.others) do
                local attrs = GTelemetry.OTLP.PlayerAttrs(data.name, sid)
                attrs[#attrs + 1] = Attribute("entity.type", "other")
                attrs[#attrs + 1] = Attribute("entity.class", class)
                ownedPoints[#ownedPoints + 1] = MakeDataPoint(count, attrs)
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
