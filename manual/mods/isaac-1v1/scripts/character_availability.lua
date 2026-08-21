-- Trimite către Companion personajele competitive deblocate local. Verificarea
-- se face în meniul principal, iar lista este retrimisă numai dacă s-a schimbat.
local characterAvailability = {}
local characterCatalog = include("scripts/character_catalog.lua")
local lastSignature = nil

local function getConfig(characterType)
    local ok, config = pcall(EntityConfig.GetPlayer, characterType)
    return ok and config or nil
end

local function isUnlocked(characterType, persistent, config)
    -- Citește EntityConfig și PersistentGameData și exclude personajele ascunse sau blocate.
    if config == nil or type(config.GetAchievementID) ~= "function" then return characterType == 0 end
    local achievementOk, achievement = pcall(config.GetAchievementID, config)
    if not achievementOk then return characterType == 0 end
    if achievement == -2 then return false end -- hidden vanilla entry, not selectable
    if achievement == -1 then
        -- Personajul nu cere achievement, dar este exclus dacă meniul de personaje
        -- îl marchează în mod explicit ca ascuns.
        local hiddenOk, hidden = type(config.IsHidden) == "function" and pcall(config.IsHidden, config)
        return not (hiddenOk and hidden == true)
    end
    local unlockedOk, unlocked = pcall(persistent.Unlocked, persistent, achievement)
    return unlockedOk and unlocked == true
end

function characterAvailability.ReportIfChanged(liveIPC)
    -- Este apelată din MC_MAIN_MENU_RENDER în main.lua. Construiește lista de
    -- personaje permise și deblocate, apoi trimite PLAYER_AVAILABILITY dacă s-a schimbat.
    if liveIPC == nil or type(liveIPC.SetAvailableCharacterTypes) ~= "function"
        or Isaac == nil or type(Isaac.GetPersistentGameData) ~= "function"
        or EntityConfig == nil or type(EntityConfig.GetPlayer) ~= "function" then return end
    local dataOk, persistent = pcall(Isaac.GetPersistentGameData)
    if not dataOk or persistent == nil or type(persistent.Unlocked) ~= "function" then return end
    local available = {}
    local names = {}
    for _, characterType in ipairs(characterCatalog.types) do
        local config = getConfig(characterType)
        local unlocked = isUnlocked(characterType, persistent, config)
        local nameOk, name = config ~= nil and type(config.GetName) == "function" and pcall(config.GetName, config)
        local achievementOk, achievement = config ~= nil and type(config.GetAchievementID) == "function" and pcall(config.GetAchievementID, config)
        Isaac.DebugString("[Isaac1v1] CHARACTER_AVAILABILITY_DECISION player_type=" .. tostring(characterType)
            .. " name=" .. tostring(nameOk and name or "Unknown")
            .. " achievement_id=" .. tostring(achievementOk and achievement or "Unknown")
            .. " available=" .. tostring(unlocked))
        if unlocked then
            table.insert(available, characterType)
            table.insert(names, nameOk and tostring(name) or tostring(characterType))
        end
    end
    local signature = table.concat(available, ",")
    if signature == lastSignature then return end
    lastSignature = signature
    local sent = liveIPC.SetAvailableCharacterTypes(available)
    Isaac.DebugString("[Isaac1v1] CHARACTER_AVAILABILITY types=[" .. signature .. "] names=[" .. table.concat(names, ",") .. "]")
    Isaac.DebugString("[Isaac1v1] PLAYER_AVAILABILITY_REPORTED character_types=\"" .. signature .. "\" sent=\"" .. tostring(sent) .. "\"")
end

return characterAvailability
