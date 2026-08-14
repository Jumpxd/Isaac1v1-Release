-- Canonical selectable PlayerType values for controlled 1v1 runs.  The Soul
-- (17) and Esau (20) are co-player forms, not standalone character selections.
local characterCatalog = {}

characterCatalog.types = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    18, 19,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
}

local supported = {}
for _, playerType in ipairs(characterCatalog.types) do
    supported[playerType] = true
end

function characterCatalog.IsSupported(playerType)
    return type(playerType) == "number"
        and playerType % 1 == 0
        and supported[playerType] == true
end

return characterCatalog
