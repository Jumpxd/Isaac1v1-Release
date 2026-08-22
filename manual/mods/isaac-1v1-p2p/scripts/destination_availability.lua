-- Reports only destination IDs available through normal progression on this save.
local destinationAvailability = {}
local destinationCatalog = include("scripts/destination_catalog.lua")
local lastSignature = nil

local function isUnlocked(destination, persistent)
    if destination.competitiveSelectable ~= true then return false end
    if destination.achievement == nil then return destination.id == "MOM" end
    if Achievement == nil or Achievement[destination.achievement] == nil then return false end
    local ok, unlocked = pcall(persistent.Unlocked, persistent, Achievement[destination.achievement])
    return ok and unlocked == true
end

function destinationAvailability.ReportIfChanged(liveIPC)
    if liveIPC == nil or type(liveIPC.SetAvailableDestinationIds) ~= "function"
        or Isaac == nil or type(Isaac.GetPersistentGameData) ~= "function" then return end
    local dataOk, persistent = pcall(Isaac.GetPersistentGameData)
    if not dataOk or persistent == nil or type(persistent.Unlocked) ~= "function" then return end
    local available = {}
    for _, destination in ipairs(destinationCatalog.entries) do
        if isUnlocked(destination, persistent) then
            available[#available + 1] = destination.id
        end
    end
    local signature = table.concat(available, ",")
    if signature == lastSignature then return end
    lastSignature = signature
    local sent = liveIPC.SetAvailableDestinationIds(available)
    Isaac.DebugString("[Isaac1v1P2P] DESTINATION_CAPABILITIES ids=[" .. signature .. "] sent=\"" .. tostring(sent) .. "\"")
end

return destinationAvailability
