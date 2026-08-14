local MatchSession = {}
local activeSession = nil

local function quote(value)
    return "\"" .. tostring(value):gsub("\"", "'") .. "\""
end

local function copySession(session)
    return {
        matchId = session.matchId,
        playerId = session.playerId,
        opponentId = session.opponentId,
        characterType = session.characterType,
        characterName = session.characterName,
        seed = session.seed,
        difficulty = session.difficulty,
        gameMode = session.gameMode,
        startGeneration = session.startGeneration,
        startToken = session.startToken,
        sessionToken = session.sessionToken,
        devReviveTest = session.devReviveTest,
        matchStatus = session.matchStatus,
        players = session.players,
        scores = session.scores,
        source = session.source,
        active = session.active ~= false
    }
end

function MatchSession.Set(session)
    if session == nil then
        MatchSession.Clear()
        return nil
    end

    activeSession = copySession(session)
    if activeSession.active then
        Isaac.DebugString(
            "[Isaac1v1] MATCH_SESSION_LOADED " ..
            "match_id=" .. quote(activeSession.matchId or "Unknown") .. " " ..
            "character=" .. quote(activeSession.characterName or "Unknown") .. " " ..
            "seed=" .. quote(activeSession.seed or "ANY")
        )
    end
    return activeSession
end

function MatchSession.Get()
    return activeSession
end

function MatchSession.Clear()
    if activeSession ~= nil then
        Isaac.DebugString(
            "[Isaac1v1] MATCH_SESSION_CLEARED match_id=" ..
            quote(activeSession.matchId or "Unknown")
        )
    end
    activeSession = nil
end

function MatchSession.IsActive()
    return activeSession ~= nil and activeSession.active == true
end

return MatchSession
