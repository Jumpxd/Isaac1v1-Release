-- Exemplu de dezvoltare INACTIV pentru vechiul flux de sesiune LOCAL. main.lua
-- nu îl încarcă, deci nu participă la matchmaking-ul actual.
local MatchConfig = {
    matchId = "local-test-001",
    playerId = "local-player",
    characterType = 0,
    characterName = "Isaac",
    seed = nil,
    difficulty = "HARD",
    gameMode = "STANDARD",
    source = "LOCAL",
    active = true
}

return MatchConfig
