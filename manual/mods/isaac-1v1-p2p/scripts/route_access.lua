-- One-shot competitive starting resources. Route selection remains vanilla and
-- entirely under player control.
local routeAccessSetup = {}

local STARTING_RESOURCES = {
    MOTHER = {
        pickups = {
            { variant = PickupVariant.PICKUP_KEY, subType = KeySubType.KEY_NORMAL },
            { variant = PickupVariant.PICKUP_BOMB, subType = BombSubType.BOMB_NORMAL },
            { variant = PickupVariant.PICKUP_BOMB, subType = BombSubType.BOMB_NORMAL },
        },
    },
    MEGA_SATAN = {
        collectibles = {
            CollectibleType.COLLECTIBLE_KEY_PIECE_1,
            CollectibleType.COLLECTIBLE_KEY_PIECE_2,
        },
    },
}

routeAccessSetup.STARTING_RESOURCES = STARTING_RESOURCES

local setupMatchId = nil
local resetMatchId = nil

local function activeSession(matchSession, competitiveRun)
    local session = matchSession ~= nil and type(matchSession.Get) == "function" and matchSession.Get() or nil
    if session == nil or type(session.matchId) ~= "string"
        or type(session.targetDestinationId) ~= "string" then return nil end
    if competitiveRun == nil or type(competitiveRun.IsActiveFor) ~= "function"
        or not competitiveRun.IsActiveFor(session) then return nil end
    return session
end

local function spawnPickup(room, player, pickup, offset)
    local desired = player.Position + offset
    local position = desired
    if type(room.FindFreePickupSpawnPosition) == "function" then
        local ok, free = pcall(room.FindFreePickupSpawnPosition, room, desired, 0, true, false, true)
        if ok and free ~= nil then position = free end
    end
    return Isaac.Spawn(
        EntityType.ENTITY_PICKUP,
        pickup.variant,
        pickup.subType,
        position,
        Vector.Zero,
        nil
    )
end

local function applyStartingResources(matchSession, competitiveRun)
    local session = activeSession(matchSession, competitiveRun)
    if session == nil or setupMatchId == session.matchId then return false end
    local resources = STARTING_RESOURCES[session.targetDestinationId]
    if resources == nil then return false end

    -- Claim the match before spawning/granting so duplicate callbacks can never
    -- duplicate resources, even if an individual engine call fails.
    setupMatchId = session.matchId
    local player = Isaac.GetPlayer(0)

    if type(resources.pickups) == "table" then
        local room = Game():GetRoom()
        local offsets = { Vector(-40, 20), Vector(0, 40), Vector(40, 20) }
        for index, pickup in ipairs(resources.pickups) do
            pcall(spawnPickup, room, player, pickup, offsets[index] or Vector.Zero)
        end
    end

    if type(resources.collectibles) == "table" then
        for _, collectible in ipairs(resources.collectibles) do
            pcall(player.AddCollectible, player, collectible, 0, false)
        end
    end

    Isaac.DebugString("[Isaac1v1P2P] STARTING_RESOURCES_APPLIED match_id=\""
        .. tostring(session.matchId) .. "\" target=\"" .. tostring(session.targetDestinationId) .. "\"")
    return true
end

function routeAccessSetup.BeginNewMatch(matchId)
    if type(matchId) ~= "string" or matchId == "" then return false end
    if resetMatchId == matchId then return true end
    resetMatchId = matchId
    setupMatchId = nil
    return true
end

function routeAccessSetup.ResetMatch()
    setupMatchId = nil
end

function routeAccessSetup.Register(mod, matchSession, competitiveRun)
    if mod == nil or ModCallbacks == nil then return false end

    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
        applyStartingResources(matchSession, competitiveRun)
    end)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_END, function()
        routeAccessSetup.ResetMatch()
    end)
    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
        routeAccessSetup.ResetMatch()
    end)

    Isaac.DebugString("[Isaac1v1P2P] Starting resources initialized")
    return true
end

return routeAccessSetup
