-- Sesiunea validă a meciului păstrată în memorie. Este creată dintr-un MATCH_START
-- live verificat și nu este restaurată dintr-un SaveData vechi.
local MatchSession = {}
local activeSession = nil

local function quote(value)
    return "\"" .. tostring(value):gsub("\"", "'") .. "\""
end

local function copySession(session)
    -- Copiază numai câmpurile cunoscute de mod. Astfel, mesajul de transport original
    -- nu poate schimba sesiunea după ce aceasta a devenit activă.
    return {
        matchId = session.matchId,
        playerId = session.playerId,
        opponentId = session.opponentId,
        characterType = session.characterType,
        characterName = session.characterName,
        seed = session.seed,
        difficulty = session.difficulty,
        gameMode = session.gameMode,
        targetDestinationId = session.targetDestinationId,
        targetDestinationName = session.targetDestinationName,
        startGeneration = session.startGeneration,
        startToken = session.startToken,
        sessionToken = session.sessionToken,
        matchStatus = session.matchStatus,
        players = session.players,
        scores = session.scores,
        source = session.source,
        active = session.active ~= false
    }
end

function MatchSession.Set(session)
    -- Este apelată de run_launcher după acceptarea MATCH_START. Înlocuiește toate
    -- datele sesiunii și întoarce copia salvată sau nil pentru date invalide.
    if session == nil then
        MatchSession.Clear()
        return nil
    end

    activeSession = copySession(session)
    if activeSession.active then
        Isaac.DebugString(
            "[Isaac1v1P2P] MATCH_SESSION_LOADED " ..
            "match_id=" .. quote(activeSession.matchId or "Unknown") .. " " ..
            "character=" .. quote(activeSession.characterName or "Unknown") .. " " ..
            "seed=" .. quote(activeSession.seed or "ANY") .. " " ..
            "target=" .. quote(activeSession.targetDestinationName or "Unknown")
        )
    end
    return activeSession
end

function MatchSession.Get()
    -- Întoarce sesiunea curentă din memorie; matchId este identitatea ei.
    return activeSession
end

function MatchSession.Clear()
    -- Este apelată la reset, la un run normal sau la Continue, ca să elimine datele vechi.
    if activeSession ~= nil then
        Isaac.DebugString(
            "[Isaac1v1P2P] MATCH_SESSION_CLEARED match_id=" ..
            quote(activeSession.matchId or "Unknown")
        )
    end
    activeSession = nil
end

function MatchSession.IsActive()
    -- Verificare simplă folosită de validare și de lifecycle.
    return activeSession ~= nil and activeSession.active == true
end

return MatchSession
