-- Stable competitive destination IDs and explicit route metadata. This is the
-- confirmed vanilla Daily membership, not a live Daily Challenge integration.
local destinationCatalog = {}

destinationCatalog.entries = {
    { id = "MOM", name = "Mom", endStage = 6, route = "MAIN", achievement = nil, competitiveSelectable = true },
    { id = "MOMS_HEART", name = "Mom's Heart / It Lives", endStage = 8, route = "MAIN", achievement = "WOMB", competitiveSelectable = true },
    { id = "SATAN", name = "Satan", endStage = 10, route = "DARK", achievement = "IT_LIVES", competitiveSelectable = true },
    { id = "ISAAC", name = "Isaac", endStage = 10, route = "LIGHT", achievement = "IT_LIVES", competitiveSelectable = true },
    { id = "THE_LAMB", name = "The Lamb", endStage = 11, route = "DARK", achievement = "NEGATIVE", competitiveSelectable = true },
    { id = "BLUE_BABY", name = "??? / Blue Baby", endStage = 11, route = "LIGHT", achievement = "POLAROID", competitiveSelectable = true },
    { id = "MEGA_SATAN", name = "Mega Satan", endStage = 11, route = "MEGA_SATAN", achievement = "NEGATIVE", competitiveSelectable = true, megaSatan = true },
    { id = "DELIRIUM", name = "Delirium", endStage = 12, route = "VOID", achievement = nil, competitiveSelectable = false, disabledReason = "DELIRIUM_ROUTE_NOT_DETERMINISTIC_IN_NORMAL_CHALLENGE_NULL" },
    { id = "MOTHER", name = "Mother", endStage = 8, route = "SECRET", achievement = "SECRET_EXIT", competitiveSelectable = true },
    { id = "THE_BEAST", name = "The Beast", endStage = 13, route = "HOME", achievement = "STRANGE_DOOR", competitiveSelectable = true }
}

destinationCatalog.byId = {}
for _, destination in ipairs(destinationCatalog.entries) do
    destinationCatalog.byId[destination.id] = destination
end

function destinationCatalog.Get(destinationId)
    return destinationCatalog.byId[destinationId]
end

function destinationCatalog.IsCompetitiveSelectable(destinationId)
    local destination = destinationCatalog.Get(destinationId)
    return destination ~= nil and destination.competitiveSelectable == true
end

return destinationCatalog
