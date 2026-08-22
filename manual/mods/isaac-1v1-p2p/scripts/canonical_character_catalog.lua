-- Stable character names shared by MATCH_CONFIG, UI and stats. These values
-- mirror Production's backend character catalog and never depend on localization.
local catalog = {}

catalog.names = {
    [0] = "Isaac", [1] = "Magdalene", [2] = "Cain", [3] = "Judas",
    [4] = "Blue Baby", [5] = "Eve", [6] = "Samson", [7] = "Azazel",
    [8] = "Lazarus", [9] = "Eden", [10] = "The Lost", [11] = "Lazarus II",
    [12] = "Black Judas", [13] = "Lilith", [14] = "Keeper", [15] = "Apollyon",
    [16] = "The Forgotten", [18] = "Bethany", [19] = "Jacob",
    [21] = "Tainted Isaac", [22] = "Tainted Magdalene", [23] = "Tainted Cain",
    [24] = "Tainted Judas", [25] = "Tainted Blue Baby", [26] = "Tainted Eve",
    [27] = "Tainted Samson", [28] = "Tainted Azazel", [29] = "Tainted Lazarus",
    [30] = "Tainted Eden", [31] = "Tainted Lost", [32] = "Tainted Lilith",
    [33] = "Tainted Keeper", [34] = "Tainted Apollyon",
    [35] = "Tainted Forgotten", [36] = "Tainted Bethany", [37] = "Tainted Jacob",
}

function catalog.GetName(characterType)
    return catalog.names[characterType]
end

return catalog
