-- Lista oficială de PlayerType care pot fi aleși într-un run 1v1 controlat.
-- The Soul (17) și Esau (20) sunt forme ajutătoare, nu personaje independente.
-- Lista este folosită la raportarea personajelor și înainte de MATCH_START.
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
    -- Întoarce true doar dacă valoarea este un PlayerType întreg aflat în listă.
    return type(playerType) == "number"
        and playerType % 1 == 0
        and supported[playerType] == true
end

return characterCatalog
