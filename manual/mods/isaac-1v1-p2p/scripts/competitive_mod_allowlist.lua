-- Datele ALLOWLIST: ID-uri Workshop, nume și aliasuri verificate pentru modurile
-- care pot rămâne active în competitive. Acest fișier nu scanează singur modurile.
local allowlist = {}

-- Lista oficială pentru competitive. ID-urile și aliasurile au fost citite din
-- metadata.xml ale modurilor instalate; nu trebuie înlocuite cu nume ghicite din UI.
-- Jucătorul poate activa orice combinație a intrărilor din această listă.
allowlist.entries = {
    {workshopId = "3388446591", canonicalName = "Dynamic Minisaacs Forever!", aliases = {"minisaacs_inherit_weapons"}},
    {workshopId = "2487822714", canonicalName = "Very Haunted Chests", aliases = {"very haunted chests"}},
    {workshopId = "2652244684", canonicalName = "cry", aliases = {"tlostcry"}},
    {workshopId = "2697721144", canonicalName = "Unique MEGAIsaacs", aliases = {"!!!!!unique megaisaacs"}},
    {workshopId = "2821675000", canonicalName = "Unique C-Section Fetuses!", aliases = {"!!fetusmany"}},
    {workshopId = "3402926130", canonicalName = "Alternate Hairstyles!", aliases = {"extra hair"}},
    {workshopId = "2769063897", canonicalName = "unintrusive pause menu", aliases = {"unintrusive pause menu"}},
    {workshopId = "3397128781", canonicalName = "Fireworks for Good Items", aliases = {"fireworks for good items"}},
    {workshopId = "836319872", canonicalName = "[AB+|Rep(+)] External Item Descriptions", aliases = {"external item descriptions"}},
    {workshopId = "2617557401", canonicalName = "TimeMachine[Repentance]", aliases = {"timemachine"}},
    {workshopId = "2487805547", canonicalName = "Luckier Pennies", aliases = {"luckier pennies"}},
    {workshopId = "2612456876", canonicalName = "Not Mad, Just Disappointed for Quality 0 Items", aliases = {"not mad, just disappointed for quality 0 items"}},
    {workshopId = "2879232973", canonicalName = "Better Explosions", aliases = {"better explosions"}},
    {workshopId = "2851861015", canonicalName = "Improved Chargebars [REP+]", aliases = {"improved chargebars", "!!! (rep) improved chargebar"}},
    {workshopId = "1547034524", canonicalName = "Antibirth music++ [OBSOLETE]", aliases = {"antibirth music++"}},
    {workshopId = "2489635144", canonicalName = "Custom Mr Dollys", aliases = {"custom mr dollys"}},
    {workshopId = "2788453409", canonicalName = "Garry's Mod Death Animation", aliases = {"garrys mod death animation"}},
    {workshopId = "2570913695", canonicalName = "Animated Items", aliases = {"animated items"}},
    {workshopId = "2766379837", canonicalName = "Regret Pedestals", aliases = {"regret pedestals"}},
    {workshopId = "835236871", canonicalName = "Better Character Menu", aliases = {"better character menu"}},
    {workshopId = "2635267643", canonicalName = "[REP(+)] Enhanced Boss Bars", aliases = {"enhanced boss bars"}},
    {workshopId = "2489006943", canonicalName = "Planetarium Chance [REP+]", aliases = {"planetarium chance"}},
    {workshopId = "2575911103", canonicalName = "Specialist Dance for Good Items", aliases = {"specialistforgooditems"}},
}

allowlist.implicitAliases = {"isaac-1v1-p2p", "repentogon"}
-- Numai modul P2P și REPENTOGON sunt infrastructură permisă. Modul legacy
-- isaac-1v1 trebuie dezactivat pentru a evita două sisteme competitive simultan.

return allowlist
