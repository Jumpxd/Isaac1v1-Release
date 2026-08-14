local lifecycle = {}

local STATE_IDLE = "IDLE"
local STATE_IN_RUN = "IN_RUN"
local STATE_ENDED = "ENDED"

local state = STATE_IDLE
local currentFloorKey = nil
local deathLogged = false
local endedLogged = false
local terminalSuppressionLogged = false
local trackedMatchId = nil
local FINAL_DEATH_CALLBACK_PRIORITY = 1000000

local function value(getter)
    local ok, result = pcall(getter)
    if not ok or result == nil or tostring(result) == "" then
        return "Unknown"
    end
    return tostring(result)
end

local function quote(result)
    return '"' .. tostring(result):gsub('"', "'") .. '"'
end

local function logEvent(name, fields)
    local parts = {"[Isaac1v1] EVENT " .. name}
    for _, field in ipairs(fields) do
        table.insert(parts, field[1] .. "=" .. quote(field[2]))
    end
    Isaac.DebugString(table.concat(parts, " "))
end

local function floorKey(gameState)
    return value(gameState.getStage) .. ":" .. value(gameState.getStageType)
end

local function addMatchIdentity(fields, matchSession)
    if matchSession ~= nil and matchSession.IsActive ~= nil and matchSession.IsActive() then
        local session = matchSession.Get()
        if session ~= nil then
            table.insert(fields, 1, {"match_id", session.matchId or "Unknown"})
        end
    end
end

local function logFloorEntered(gameState, matchSession)
    local key = floorKey(gameState)
    if key == currentFloorKey then
        return
    end

    currentFloorKey = key
    local fields = {
        {"floor", value(gameState.getFloorName)},
        {"stage", value(gameState.getStage)},
        {"stage_type", value(gameState.getStageType)},
        {"run_time", value(gameState.getRunTime)},
        {"vanilla_score", value(gameState.getVanillaScore)}
    }
    addMatchIdentity(fields, matchSession)
    logEvent("FLOOR_ENTERED", fields)
end

local function submitTerminal(liveIPC, gameState, matchSession, reason, competitiveRun)
    local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
    if liveIPC == nil or liveIPC.SubmitTerminal == nil or matchSession == nil
        or not matchSession.IsActive() or competitiveRun == nil
        or competitiveRun.IsActiveFor == nil or not competitiveRun.IsActiveFor(session) then return end
    if liveIPC.IsMatchFinalized ~= nil and liveIPC.IsMatchFinalized() then
        if not terminalSuppressionLogged then
            terminalSuppressionLogged = true
            Isaac.DebugString("[Isaac1v1] TERMINAL_EVENT_SUPPRESSED reason=\"RESULT_ALREADY_FINAL\"")
        end
        return
    end
    local score = gameState.getVanillaScore()
    if type(score) ~= "number" then
        Isaac.DebugString("[Isaac1v1] MATCH_TERMINAL_DEFERRED reason=\"SCORE_UNAVAILABLE\"")
        return
    end
    local sent, errorMessage = liveIPC.SubmitTerminal(reason, score, gameState.getRunTime())
    Isaac.DebugString("[Isaac1v1] MATCH_TERMINAL_EVENT reason=\"" .. reason .. "\" score=\"" .. tostring(score) .. "\" sent=\"" .. tostring(sent) .. "\"")
end

local function logFinalDeath(gameState, matchSession, liveIPC, competitiveRun)
    if deathLogged then
        return false
    end

    deathLogged = true
    local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
    Isaac.DebugString("[Isaac1v1] COMPETITIVE_FINAL_DEATH match_id="
        .. quote(session ~= nil and session.matchId or "Unknown"))
    local fields = {
        {"character", value(gameState.getCharacterName)},
        {"floor", value(gameState.getFloorName)},
        {"run_time", value(gameState.getRunTime)},
        {"seed", value(gameState.getSeedString)},
        {"vanilla_score", value(gameState.getVanillaScore)}
    }
    addMatchIdentity(fields, matchSession)
    logEvent("PLAYER_DIED", fields)
    submitTerminal(liveIPC, gameState, matchSession, "DEATH", competitiveRun)
    return true
end

local function logPlayerRevived(player, matchSession, competitiveRun)
    local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
    local competitive = competitiveRun ~= nil and competitiveRun.IsActiveFor ~= nil
        and competitiveRun.IsActiveFor(session)
    if state ~= STATE_IN_RUN or not competitive then return end
    local playerType = value(function() return player:GetPlayerType() end)
    Isaac.DebugString("[Isaac1v1] COMPETITIVE_PLAYER_REVIVED match_id="
        .. quote(session ~= nil and session.matchId or "Unknown")
        .. " player_type=" .. quote(playerType))
end

local function logRunEnded(gameState, reason, matchSession)
    if endedLogged or state == STATE_IDLE then
        return
    end

    endedLogged = true
    state = STATE_ENDED
    local fields = {
        {"reason", reason},
        {"character", value(gameState.getCharacterName)},
        {"floor", value(gameState.getFloorName)},
        {"run_time", value(gameState.getRunTime)},
        {"seed", value(gameState.getSeedString)},
        {"vanilla_score", value(gameState.getVanillaScore)}
    }
    addMatchIdentity(fields, matchSession)
    logEvent("RUN_ENDED", fields)
end

local function activeSession(matchSession, competitiveRun)
    local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
    return session, competitiveRun ~= nil and competitiveRun.IsActiveFor ~= nil
        and competitiveRun.IsActiveFor(session)
end

function lifecycle.BeginNewMatch(matchId)
    if type(matchId) ~= "string" or matchId == "" then return false end
    if trackedMatchId == matchId then return true end
    trackedMatchId = matchId
    state = STATE_IDLE
    currentFloorKey = nil
    deathLogged = false
    endedLogged = false
    terminalSuppressionLogged = false
    return true
end

local function startRun(gameState, isContinued, matchValidation, matchSession, competitiveRun)
    if state == STATE_IN_RUN then
        local existingSession = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
        if competitiveRun ~= nil and competitiveRun.IsActiveFor ~= nil
            and competitiveRun.IsActiveFor(existingSession) then return end
        state = STATE_IDLE
    end

    local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
    if isContinued ~= true and session ~= nil then
        local saveSlot = "Unknown"
        if type(Isaac1v1IPC) == "table"
            and type(Isaac1v1IPC.GetCompetitiveSaveSlot) == "function" then
            local slotOk, slotValue = pcall(Isaac1v1IPC.GetCompetitiveSaveSlot)
            if slotOk and slotValue ~= nil then saveSlot = tostring(slotValue) end
        end
        Isaac.DebugString("[Isaac1v1] MC_POST_GAME_STARTED match_id=" .. quote(session.matchId)
            .. " slot=" .. quote(saveSlot))
    end
    if competitiveRun == nil or competitiveRun.IsIntentFor == nil
        or not competitiveRun.IsIntentFor(session) or isContinued == true then
        state = STATE_IDLE
        if competitiveRun ~= nil and competitiveRun.Deactivate ~= nil then
            competitiveRun.Deactivate(isContinued == true and "CONTINUE" or "NORMAL_RUN_STARTED")
        end
        if matchSession ~= nil and matchSession.Clear ~= nil then matchSession.Clear() end
        return
    end

    state = STATE_IN_RUN
    trackedMatchId = session.matchId
    currentFloorKey = nil
    deathLogged = false
    endedLogged = false
    terminalSuppressionLogged = false

    local matchResult = {valid = false}
    if matchValidation ~= nil and matchValidation.Validate ~= nil then
        if matchValidation.Reset ~= nil then
            matchValidation.Reset()
        end
        local validationOk, result = pcall(matchValidation.Validate, session, gameState)
        if validationOk and result ~= nil then
            matchResult = result
        end
    end

    if matchResult.valid ~= true or competitiveRun.Activate == nil
        or competitiveRun.Activate(session) ~= true then
        state = STATE_IDLE
        competitiveRun.ClearIntent()
        if matchSession ~= nil and matchSession.Clear ~= nil then matchSession.Clear() end
        return
    end

    if session.devReviveTest == "DEAD_CAT" then
        local setupOk, setupError = pcall(function()
            Isaac.GetPlayer(0):AddCollectible(CollectibleType.COLLECTIBLE_DEAD_CAT, 0, true)
        end)
        Isaac.DebugString("[Isaac1v1] DEV_REVIVE_TEST_SETUP match_id=" .. quote(session.matchId)
            .. " item=\"DEAD_CAT\" success=" .. quote(setupOk)
            .. (setupOk and "" or " error=" .. quote(setupError)))
    end

    local fields = {
        {"character", value(gameState.getCharacterName)},
        {"player_type", value(gameState.getPlayerTypeId)},
        {"seed", value(gameState.getSeedString)},
        {"floor", value(gameState.getFloorName)},
        {"difficulty", value(gameState.getDifficultyName):upper()},
        {"game_mode", value(gameState.getGameModeName)},
        {"run_time", value(gameState.getRunTime)},
        {"match_valid", tostring(matchResult.valid == true)},
        {"continued", tostring(isContinued == true)}
    }
    addMatchIdentity(fields, matchSession)
    logEvent("RUN_STARTED", fields)
    logFloorEntered(gameState, matchSession)
end

function lifecycle.Register(mod, gameState, matchValidation, matchSession, liveIPC, competitiveRun, matchBridge, matchResult)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
        startRun(gameState, isContinued, matchValidation, matchSession, competitiveRun)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
        local _, competitive = activeSession(matchSession, competitiveRun)
        if state == STATE_IN_RUN and competitive then
            logFloorEntered(gameState, matchSession)
        end
    end)

    -- This callback runs only after vanilla revive checks. Register it very
    -- late so mod-provided revives using the same REPENTOGON callback can run
    -- first and short-circuit the remaining death callbacks.
    mod:AddPriorityCallback(ModCallbacks.MC_TRIGGER_PLAYER_DEATH_POST_CHECK_REVIVES,
        FINAL_DEATH_CALLBACK_PRIORITY, function(_, player)
            local _, competitive = activeSession(matchSession, competitiveRun)
            if state ~= STATE_IN_RUN or not competitive then return end
            if logFinalDeath(gameState, matchSession, liveIPC, competitiveRun) then
                local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
                if matchResult ~= nil and matchResult.MarkFinalDeathPending ~= nil and session ~= nil then
                    pcall(matchResult.MarkFinalDeathPending, session.matchId)
                end
                logRunEnded(gameState, "GAME_OVER", matchSession)
                competitiveRun.Deactivate("DEATH")
            end
        end)

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_REVIVE, function(_, player)
        logPlayerRevived(player, matchSession, competitiveRun)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_GAME_END, function(_, isGameOver)
        local _, competitive = activeSession(matchSession, competitiveRun)
        if state ~= STATE_IN_RUN or not competitive then return end
        if liveIPC ~= nil and liveIPC.IsCompetitiveResultTransition ~= nil
            and liveIPC.IsCompetitiveResultTransition() then
            if not terminalSuppressionLogged then
                terminalSuppressionLogged = true
                Isaac.DebugString("[Isaac1v1] TERMINAL_EVENT_SUPPRESSED reason=\"RESULT_ALREADY_FINAL\"")
            end
            logRunEnded(gameState, "RESULT_TRANSITION", matchSession)
            competitiveRun.Deactivate("RESULT")
            return
        end
        if isGameOver == true then
            if logFinalDeath(gameState, matchSession, liveIPC, competitiveRun) then
                local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
                if matchResult ~= nil and matchResult.MarkFinalDeathPending ~= nil and session ~= nil then
                    pcall(matchResult.MarkFinalDeathPending, session.matchId)
                end
            end
            logRunEnded(gameState, "GAME_OVER", matchSession)
            competitiveRun.Deactivate("DEATH")
        else
            submitTerminal(liveIPC, gameState, matchSession, "RUN_COMPLETED", competitiveRun)
            logRunEnded(gameState, "ENDING", matchSession)
            competitiveRun.Deactivate("RUN_COMPLETED")
        end
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
        local session, competitive = activeSession(matchSession, competitiveRun)
        if state == STATE_IN_RUN and competitive then
            Isaac.DebugString("[Isaac1v1] COMPETITIVE_EXIT_DETECTED match_id=\""
                .. tostring(session ~= nil and session.matchId or "")
                .. "\" state=\"STARTED\"")
            if liveIPC ~= nil and liveIPC.DisconnectMatch ~= nil and session ~= nil then
                pcall(liveIPC.DisconnectMatch, session.matchId)
            end
            logRunEnded(gameState, "ABANDONED", matchSession)
            competitiveRun.Deactivate("ABANDON")
        end
    end)

    Isaac.DebugString("[Isaac1v1] Lifecycle initialized")
end

return lifecycle
