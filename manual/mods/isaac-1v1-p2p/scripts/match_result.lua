-- Coordonează RESULT. Așteaptă MATCH_RESULT_FINAL valid, îl trimite meniului 1v1
-- și face o singură tranziție sigură din run-ul terminat.
local matchResult = {}
local exitRequested = false
local lastResultMatchId = nil
local exitRequestedAt = nil
local exitFailureLogged = false
local resetMatchId = nil
local terminalResultPendingMatchId = nil
local pendingResult = nil
local resultTransitionScheduled = false
local resultTransitionExecuted = false
local resultTransitionUpdates = 0
local waitingForPeerResultLogged = false
local waitingForSafeUpdateLogged = false
local liveIPC = nil
local SAFE_TRANSITION_UPDATE_DELAY = 30

local function quote(value)
    return '"' .. tostring(value):gsub('"', "'") .. '"'
end

local function now()
    if Isaac ~= nil and type(Isaac.GetTime) == "function" then return Isaac.GetTime() / 1000 end
    return os.clock()
end

local function stopCompetitiveRun(result)
    -- Face tranziția vizuală către meniul de save o singură dată pentru fiecare rezultat.
    -- Întoarce true numai dacă Game.Fadeout a acceptat cererea.
    if exitRequested then return false end
    exitRequested = true
    exitRequestedAt = now()
    exitFailureLogged = false
    if liveIPC ~= nil and liveIPC.BeginCompetitiveResultTransition ~= nil then
        pcall(liveIPC.BeginCompetitiveResultTransition, result.matchId)
    end
    if Game ~= nil then
        local ok, game = pcall(Game)
        if ok and game ~= nil and type(game.Fadeout) == "function"
            and FadeoutTarget ~= nil and FadeoutTarget.SAVEFILE_MENU ~= nil then
            local fadeOk = pcall(game.Fadeout, game, 0.25, FadeoutTarget.SAVEFILE_MENU)
            if fadeOk then
                Isaac.DebugString("[Isaac1v1P2P] COMPETITIVE_RUN_EXIT_REQUESTED method=\"Game.Fadeout\" target=\"SAVEFILE_MENU\"")
                Isaac.DebugString("[Isaac1v1P2P] RESULT_TRANSITION_EXECUTED match_id=" .. quote(result.matchId))
                return true
            end
        end
    end
    Isaac.DebugString("[Isaac1v1P2P] COMPETITIVE_RUN_EXIT_FAILED")
    exitFailureLogged = true
    return false
end

local function checkExitFailure()
    if not exitRequested or exitFailureLogged or exitRequestedAt == nil then return end
    if now() - exitRequestedAt < 5 then return end
    if MenuManager ~= nil and type(MenuManager.IsActive) == "function" then
        local ok, active = pcall(MenuManager.IsActive)
        if ok and active == true then
            return
        end
    end
    exitFailureLogged = true
    Isaac.DebugString("[Isaac1v1P2P] COMPETITIVE_RUN_EXIT_FAILED reason=\"MENU_CONTEXT_TIMEOUT\"")
end

function matchResult.BeginNewMatch(matchId)
    -- Șterge toate stările de rezultat și tranziție pentru un ID nou de meci.
    if type(matchId) ~= "string" or matchId == "" then return false end
    if resetMatchId == matchId then return true end
    resetMatchId = matchId
    exitRequested = false
    exitRequestedAt = nil
    exitFailureLogged = false
    lastResultMatchId = nil
    terminalResultPendingMatchId = nil
    pendingResult = nil
    resultTransitionScheduled = false
    resultTransitionExecuted = false
    resultTransitionUpdates = 0
    waitingForPeerResultLogged = false
    waitingForSafeUpdateLogged = false
    Isaac.DebugString("[Isaac1v1P2P] RESULT_STATE_RESET match_id=" .. quote(matchId))
    return true
end

function matchResult.ResetTerminal()
    exitRequested = false
    exitRequestedAt = nil
    exitFailureLogged = false
    lastResultMatchId = nil
    terminalResultPendingMatchId = nil
    pendingResult = nil
    resultTransitionScheduled = false
    resultTransitionExecuted = false
    resultTransitionUpdates = 0
    waitingForPeerResultLogged = false
    waitingForSafeUpdateLogged = false
    resetMatchId = nil
    return true
end

function matchResult.MarkFinalDeathPending(matchId)
    -- MOARTE: memorează faptul că run-ul se poate opri înainte să vină rezultatul,
    -- astfel încât MATCH_RESULT_FINAL să rămână legat de meciul corect.
    if type(matchId) ~= "string" or matchId == "" then return false end
    if terminalResultPendingMatchId == matchId then return true end
    terminalResultPendingMatchId = matchId
    pendingResult = nil
    resultTransitionScheduled = false
    resultTransitionExecuted = false
    resultTransitionUpdates = 0
    waitingForPeerResultLogged = false
    waitingForSafeUpdateLogged = false
    Isaac.DebugString("[Isaac1v1P2P] FINAL_DEATH_RESULT_PENDING match_id=" .. quote(matchId))
    return true
end

local function scheduleResultTransition(result)
    -- Păstrează datele rezultatului și pornește o scurtă așteptare măsurată în actualizări.
    if resultTransitionScheduled or resultTransitionExecuted then return end
    pendingResult = result
    resultTransitionScheduled = true
    resultTransitionUpdates = 0
    Isaac.DebugString("[Isaac1v1P2P] RESULT_TRANSITION_SCHEDULED match_id=" .. quote(result.matchId))
end

local function advanceResultTransition()
    -- Este apelată de callback-ul rezultatului; după așteptare face un singur fadeout.
    if not resultTransitionScheduled or resultTransitionExecuted or pendingResult == nil then return end
    resultTransitionUpdates = resultTransitionUpdates + 1
    if resultTransitionUpdates <= SAFE_TRANSITION_UPDATE_DELAY then
        if not waitingForSafeUpdateLogged then
            waitingForSafeUpdateLogged = true
            Isaac.DebugString("[Isaac1v1P2P] RESULT_TRANSITION_WAITING reason=\"SAFE_UPDATE_DELAY\" match_id="
                .. quote(pendingResult.matchId))
        end
        return
    end
    if stopCompetitiveRun(pendingResult) then
        resultTransitionExecuted = true
        resultTransitionScheduled = false
    end
end

function matchResult.Register(mod, transport, session, menu, competitiveRun)
    -- Folosește POST_RENDER sau, ca rezervă, POST_UPDATE. Astfel poate continua
    -- să verifice rezultatul și după game over, când alte callback-uri se pot opri.
    liveIPC = transport
    local resultCallback = ModCallbacks.MC_POST_RENDER or ModCallbacks.MC_POST_UPDATE
    mod:AddCallback(resultCallback, function()
        -- RESULT: așteaptă status.result din transport, ignoră rezultate din alte meciuri,
        -- afișează ecranul dedicat și continuă tranziția la apelurile următoare.
        if liveIPC == nil or liveIPC.GetStatus == nil then return end
        local ok, status = pcall(liveIPC.GetStatus)
        if not ok or status == nil then return end
        if status.result == nil then
            if terminalResultPendingMatchId ~= nil and not waitingForPeerResultLogged then
                waitingForPeerResultLogged = true
                Isaac.DebugString("[Isaac1v1P2P] RESULT_TRANSITION_WAITING reason=\"PEER_RESULT\" match_id="
                    .. quote(terminalResultPendingMatchId))
            end
            return
        end
        local resultMatchId = status.result.matchId
        local isPendingFinalDeath = terminalResultPendingMatchId ~= nil
            and terminalResultPendingMatchId == resultMatchId
        local wasCompetitive = competitiveRun ~= nil and competitiveRun.WasCompetitiveMatch ~= nil
            and competitiveRun.WasCompetitiveMatch(resultMatchId)
        if not isPendingFinalDeath and not wasCompetitive then return end
        if lastResultMatchId ~= resultMatchId then
            exitRequested = false
            exitRequestedAt = nil
            exitFailureLogged = false
            lastResultMatchId = resultMatchId
            if competitiveRun.Deactivate ~= nil then competitiveRun.Deactivate("RESULT") end
            Isaac.DebugString("[Isaac1v1P2P] MATCH_RESULT_RECEIVED match_id=" .. quote(resultMatchId))
            if menu ~= nil and menu.ShowResult ~= nil then
                pcall(menu.ShowResult, status.result)
            end
            scheduleResultTransition(status.result)
            return
        end
        advanceResultTransition()
        checkExitFailure()
    end)
    Isaac.DebugString("[Isaac1v1P2P] Match result transition initialized")
end

return matchResult
