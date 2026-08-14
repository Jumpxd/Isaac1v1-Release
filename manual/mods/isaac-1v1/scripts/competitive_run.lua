local competitiveRun = {}

local active = false
local intentMatchId = nil
local activeMatchId = nil
local lastCompetitiveMatchId = nil
local trackedMatchId = nil
local completedMatchIds = {}

local function setNativeCompetitiveMode(enabled)
    if type(Isaac1v1IPC) ~= "table" or type(Isaac1v1IPC.SetCompetitiveMode) ~= "function" then
        Isaac.DebugString('[Isaac1v1] COMPETITIVE_CONSOLE_NATIVE_UNAVAILABLE reason="API_MISSING"')
        return false
    end
    local ok, changed, err = pcall(Isaac1v1IPC.SetCompetitiveMode, enabled == true)
    if not ok or changed ~= true then
        Isaac.DebugString('[Isaac1v1] COMPETITIVE_CONSOLE_NATIVE_UNAVAILABLE reason="'
            .. tostring(ok and err or changed):gsub('"', "'") .. '"')
        return false
    end
    return true
end

local function quote(value)
    return '"' .. tostring(value):gsub('"', "'") .. '"'
end

function competitiveRun.Reset()
    setNativeCompetitiveMode(false)
    active = false
    intentMatchId = nil
    activeMatchId = nil
    lastCompetitiveMatchId = nil
    trackedMatchId = nil
    completedMatchIds = {}
end

function competitiveRun.BeginNewMatch(session, previousMatchId)
    if session == nil or type(session.matchId) ~= "string" or session.matchId == "" then return false end
    if trackedMatchId == session.matchId then return true end
    local previous = trackedMatchId or previousMatchId
    setNativeCompetitiveMode(false)
    active = false
    activeMatchId = nil
    intentMatchId = session.matchId
    trackedMatchId = session.matchId
    Isaac.DebugString("[Isaac1v1] COMPETITIVE_MATCH_RESET previous_match_id=" .. quote(previous or "<none>")
        .. " new_match_id=" .. quote(session.matchId))
    return true
end

function competitiveRun.SetIntent(session)
    if session == nil or type(session.matchId) ~= "string" then return false end
    if trackedMatchId ~= session.matchId then
        return competitiveRun.BeginNewMatch(session, trackedMatchId)
    end
    setNativeCompetitiveMode(false)
    active = false
    activeMatchId = nil
    intentMatchId = session.matchId
    return true
end

function competitiveRun.ClearIntent()
    setNativeCompetitiveMode(false)
    intentMatchId = nil
end

function competitiveRun.IsIntentFor(session)
    return not active and session ~= nil and session.active == true
        and intentMatchId ~= nil and session.matchId == intentMatchId
end

function competitiveRun.Activate(session)
    if active and session ~= nil and session.matchId == activeMatchId then return true end
    if not competitiveRun.IsIntentFor(session) then return false end
    active = true
    activeMatchId = session.matchId
    lastCompetitiveMatchId = session.matchId
    intentMatchId = nil
    local saveSlot = "Unknown"
    if type(Isaac1v1IPC) == "table"
        and type(Isaac1v1IPC.GetCompetitiveSaveSlot) == "function" then
        local slotOk, slotValue = pcall(Isaac1v1IPC.GetCompetitiveSaveSlot)
        if slotOk and slotValue ~= nil then saveSlot = tostring(slotValue) end
    end
    Isaac.DebugString("[Isaac1v1] COMPETITIVE_RUN_ACTIVATED match_id=" .. quote(activeMatchId)
        .. " slot=" .. quote(saveSlot))
    setNativeCompetitiveMode(true)
    return true
end

function competitiveRun.IsActiveFor(session)
    return active and session ~= nil and session.active == true
        and activeMatchId ~= nil and session.matchId == activeMatchId
end

function competitiveRun.IsActive()
    return active == true
end

function competitiveRun.WasCompetitiveMatch(matchId)
    return matchId ~= nil and (lastCompetitiveMatchId == matchId or completedMatchIds[matchId] == true)
end

function competitiveRun.Deactivate(reason)
    local matchId = activeMatchId or intentMatchId
    if active and matchId ~= nil then
        Isaac.DebugString("[Isaac1v1] COMPETITIVE_RUN_DEACTIVATED match_id=" .. quote(matchId)
            .. " reason=" .. quote(reason or "UNKNOWN"))
    end
    if matchId ~= nil then completedMatchIds[matchId] = true end
    setNativeCompetitiveMode(false)
    active = false
    intentMatchId = nil
    activeMatchId = nil
end

competitiveRun.Reset()
return competitiveRun
