-- Callback-urile pentru CICLUL MECIULUI: activare, etaje, moarte finală, terminarea
-- run-ului, revive și raportarea abandonului prin Exit Game.
local lifecycle = {}

local STATE_IDLE = "IDLE"
local STATE_IN_RUN = "IN_RUN"
local STATE_ENDED = "ENDED"

local state = STATE_IDLE
local currentFloorKey = nil
local deathLogged = false
local endedLogged = false
local targetCompletionLogged = false
local terminalSuppressionLogged = false
local trackedMatchId = nil
local localRunCompletedMatchId = nil
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
    local parts = {"[Isaac1v1P2P] EVENT " .. name}
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
    -- Cererea de final folosită de DEATH și RUN_COMPLETED. Rulează numai pentru
    -- sesiunea activă exactă și trimite către peer punctajul și timpul curent.
    local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
    if liveIPC == nil or liveIPC.SubmitTerminal == nil or matchSession == nil
        or not matchSession.IsActive() or competitiveRun == nil
        or competitiveRun.IsActiveFor == nil or not competitiveRun.IsActiveFor(session) then return false end
    if liveIPC.IsMatchFinalized ~= nil and liveIPC.IsMatchFinalized() then
        if not terminalSuppressionLogged then
            terminalSuppressionLogged = true
            Isaac.DebugString("[Isaac1v1P2P] TERMINAL_EVENT_SUPPRESSED reason=\"RESULT_ALREADY_FINAL\"")
        end
        return false
    end
    local score = gameState.getVanillaScore()
    if type(score) ~= "number" then
        Isaac.DebugString("[Isaac1v1P2P] MATCH_TERMINAL_DEFERRED reason=\"SCORE_UNAVAILABLE\"")
        return false
    end
    local sent, errorMessage = liveIPC.SubmitTerminal(reason, score, gameState.getRunTime())
    Isaac.DebugString("[Isaac1v1P2P] MATCH_TERMINAL_EVENT reason=\"" .. reason .. "\" score=\"" .. tostring(score) .. "\" sent=\"" .. tostring(sent) .. "\"")
    return true, sent == true, errorMessage, score, gameState.getRunTime()
end

local function logFinalDeath(gameState, matchSession, liveIPC, competitiveRun)
    -- MOARTE: este apelată numai după ce Isaac a verificat toate posibilitățile de
    -- revive. Trimite un singur eveniment final și așteaptă rezultatul serverului.
    if deathLogged then
        return false
    end

    deathLogged = true
    local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
    Isaac.DebugString("[Isaac1v1P2P] COMPETITIVE_FINAL_DEATH match_id="
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
    -- REVIVE: scrie doar un log. Nu trimite un eveniment final și nu schimbă
    -- starea competitivă a run-ului.
    local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
    local competitive = competitiveRun ~= nil and competitiveRun.IsActiveFor ~= nil
        and competitiveRun.IsActiveFor(session)
    if state ~= STATE_IN_RUN or not competitive then return end
    local playerType = value(function() return player:GetPlayerType() end)
    Isaac.DebugString("[Isaac1v1P2P] COMPETITIVE_PLAYER_REVIVED match_id="
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

-- Acestea sunt numai formele de progression/destination care pot decide un
-- outcome. Boss-ii obișnuiți nu apar aici și nu pot produce WRONG_DESTINATION.
local PROGRESSION_BOSS_MATCHERS = {
    MOM = function(npc) return npc.Type == EntityType.ENTITY_MOM and npc.Variant == 10 end,
    MOMS_HEART = function(npc) return npc.Type == EntityType.ENTITY_MOMS_HEART
        and (npc.Variant == 0 or npc.Variant == 1) end, -- Mom's Heart / It Lives
    SATAN = function(npc) return npc.Type == EntityType.ENTITY_SATAN
        and npc.Variant == 10 and npc.Child == nil end, -- final Satan leg
    ISAAC = function(npc) return npc.Type == EntityType.ENTITY_ISAAC and npc.Variant == 0 end,
    THE_LAMB = function(npc) return npc.Type == EntityType.ENTITY_THE_LAMB and npc.Variant == 0 end,
    BLUE_BABY = function(npc) return npc.Type == EntityType.ENTITY_ISAAC and npc.Variant == 1 end,
    MEGA_SATAN = function(npc) return npc.Type == EntityType.ENTITY_MEGA_SATAN_2
        and npc.Variant == 0 end, -- phase 2 only
    MOTHER = function(npc) return npc.Type == EntityType.ENTITY_MOTHER and npc.Variant == 10 end,
    DOGMA = function(npc) return npc.Type == EntityType.ENTITY_DOGMA and npc.Variant == 2 end,
    THE_BEAST = function(npc) return npc.Type == EntityType.ENTITY_BEAST and npc.Variant == 0 end,
}

-- Central outcome policy. The allowed set contains only bosses that may be
-- killed before the target on the real vanilla route.
local TARGET_BOSS_OUTCOMES = {
    MOM = { completion = "MOM", allowed = {} },
    MOMS_HEART = { completion = "MOMS_HEART", allowed = { MOM = true } },
    SATAN = { completion = "SATAN", allowed = { MOM = true, MOMS_HEART = true } },
    ISAAC = { completion = "ISAAC", allowed = { MOM = true, MOMS_HEART = true } },
    THE_LAMB = {
        completion = "THE_LAMB",
        allowed = { MOM = true, MOMS_HEART = true, SATAN = true },
    },
    BLUE_BABY = {
        completion = "BLUE_BABY",
        allowed = { MOM = true, MOMS_HEART = true, ISAAC = true },
    },
    MEGA_SATAN = {
        completion = "MEGA_SATAN",
        allowed = { MOM = true, MOMS_HEART = true, SATAN = true, ISAAC = true },
    },
    MOTHER = { completion = "MOTHER", allowed = { MOM = true } },
    THE_BEAST = { completion = "THE_BEAST", allowed = { MOM = true, DOGMA = true } },
}

lifecycle.PROGRESSION_BOSS_MATCHERS = PROGRESSION_BOSS_MATCHERS
lifecycle.TARGET_BOSS_OUTCOMES = TARGET_BOSS_OUTCOMES

local function classifyProgressionBoss(npc)
    for bossId, matches in pairs(PROGRESSION_BOSS_MATCHERS) do
        if matches(npc) == true then return bossId end
    end
    return nil
end

local function resolveBossOutcome(gameState, matchSession, liveIPC, competitiveRun, matchResult, npc)
    if targetCompletionLogged or state ~= STATE_IN_RUN then return false end
    local session, competitive = activeSession(matchSession, competitiveRun)
    if not competitive or session == nil or type(session.targetDestinationId) ~= "string" then return false end

    local defeatedBossId = classifyProgressionBoss(npc)
    if defeatedBossId == nil then return false end
    local profile = TARGET_BOSS_OUTCOMES[session.targetDestinationId]
    if profile == nil then return false end

    if defeatedBossId == profile.completion then
        targetCompletionLogged = true
        Isaac.DebugString("[Isaac1v1P2P] COMPETITIVE_TARGET_DEFEATED match_id=" .. quote(session.matchId)
            .. " destination=" .. quote(session.targetDestinationId))
        local submitted, _, _, finalScore, finalRunTime =
            submitTerminal(liveIPC, gameState, matchSession, "RUN_COMPLETED", competitiveRun)
        if not submitted then
            Isaac.DebugString("[Isaac1v1P2P] LOCAL_COMPLETION_DEFERRED reason=\"TERMINAL_CAPTURE_FAILED\"")
            return false
        end
        localRunCompletedMatchId = session.matchId
        if matchResult ~= nil and matchResult.MarkLocalCompletionPending ~= nil then
            pcall(matchResult.MarkLocalCompletionPending, session.matchId, finalScore, finalRunTime)
        end
        logRunEnded(gameState, "TARGET_DEFEATED", matchSession)
        competitiveRun.Deactivate("RUN_COMPLETED")
        return true
    end

    if profile.allowed[defeatedBossId] == true then
        Isaac.DebugString("[Isaac1v1P2P] COMPETITIVE_PROGRESSION_BOSS match_id=" .. quote(session.matchId)
            .. " target=" .. quote(session.targetDestinationId)
            .. " defeated=" .. quote(defeatedBossId))
        return false
    end

    targetCompletionLogged = true
    Isaac.DebugString("[Isaac1v1P2P] COMPETITIVE_WRONG_DESTINATION match_id=" .. quote(session.matchId)
        .. " target=" .. quote(session.targetDestinationId)
        .. " defeated=" .. quote(defeatedBossId))
    submitTerminal(liveIPC, gameState, matchSession, "WRONG_DESTINATION", competitiveRun)
    logRunEnded(gameState, "WRONG_DESTINATION", matchSession)
    competitiveRun.Deactivate("WRONG_DESTINATION")
    return true
end

function lifecycle.BeginNewMatch(matchId)
    -- Șterge stările lifecycle ale meciului anterior, inclusiv protecția împotriva
    -- duplicatelor. Dacă acest ID a fost deja resetat, nu repetă operația.
    if type(matchId) ~= "string" or matchId == "" then return false end
    if trackedMatchId == matchId then return true end
    trackedMatchId = matchId
    state = STATE_IDLE
    currentFloorKey = nil
    deathLogged = false
    endedLogged = false
    targetCompletionLogged = false
    terminalSuppressionLogged = false
    localRunCompletedMatchId = nil
    return true
end

function lifecycle.ResetTerminal()
    trackedMatchId = nil
    state = STATE_IDLE
    currentFloorKey = nil
    deathLogged = false
    endedLogged = false
    targetCompletionLogged = false
    terminalSuppressionLogged = false
    localRunCompletedMatchId = nil
    return true
end

local function startRun(gameState, isContinued, matchValidation, matchSession, competitiveRun)
    -- Funcția apelată de MC_POST_GAME_STARTED. Un Continue sau run normal curăță datele
    -- competitive vechi; numai intenția care corespunde sesiunii poate fi activată.
    if state == STATE_IN_RUN then
        local existingSession = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
        if competitiveRun ~= nil and competitiveRun.IsActiveFor ~= nil
            and competitiveRun.IsActiveFor(existingSession) then return end
        state = STATE_IDLE
    end

    local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
    if isContinued ~= true and session ~= nil then
        local saveSlot = "Unknown"
        if type(Isaac1v1P2P) == "table"
            and type(Isaac1v1P2P.GetCompetitiveSaveSlot) == "function" then
            local slotOk, slotValue = pcall(Isaac1v1P2P.GetCompetitiveSaveSlot)
            if slotOk and slotValue ~= nil then saveSlot = tostring(slotValue) end
        end
        Isaac.DebugString("[Isaac1v1P2P] MC_POST_GAME_STARTED match_id=" .. quote(session.matchId)
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
    targetCompletionLogged = false
    terminalSuppressionLogged = false
    localRunCompletedMatchId = nil

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
    -- Înregistrează toate callback-urile ciclului de joc. matchBridge rămâne în
    -- parametri pentru compatibilitate, dar sesiunea live vine din matchSession.
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
        -- Rulează ori de câte ori Isaac pornește sau continuă un run, nu doar în 1v1.
        startRun(gameState, isContinued, matchValidation, matchSession, competitiveRun)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
        -- STARTED: înregistrează intrarea pe un etaj pentru sesiunea competitivă activă.
        local _, competitive = activeSession(matchSession, competitiveRun)
        if state == STATE_IN_RUN and competitive then
            logFloorEntered(gameState, matchSession)
        end
    end)

    -- REPENTOGON/Isaac emite acest callback când NPC-ul a murit efectiv.
    mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, function(_, npc)
        resolveBossOutcome(gameState, matchSession, liveIPC, competitiveRun, matchResult, npc)
    end)

    -- Acest callback rulează după verificările vanilla de revive. Este înregistrat
    -- foarte târziu, astfel încât revive-urile altor moduri care folosesc același
    -- callback REPENTOGON să poată rula primele și să oprească moartea finală.
    mod:AddPriorityCallback(ModCallbacks.MC_TRIGGER_PLAYER_DEATH_POST_CHECK_REVIVES,
        FINAL_DEATH_CALLBACK_PRIORITY, function(_, player)
            -- MOARTE/REVIVE: acest hook REPENTOGON rulează după rezolvarea revive-ului.
            -- Astfel, un revive valid nu este raportat greșit ca pierdere.
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
        -- Confirmă un revive reușit fără să termine sau să repornească meciul.
        logPlayerRevived(player, matchSession, competitiveRun)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_GAME_END, function(_, isGameOver)
        -- RESULT: raportează moartea finală ca rezervă sau RUN_COMPLETED la final normal.
        local _, competitive = activeSession(matchSession, competitiveRun)
        if state ~= STATE_IN_RUN or not competitive then return end
        if liveIPC ~= nil and liveIPC.IsCompetitiveResultTransition ~= nil
            and liveIPC.IsCompetitiveResultTransition() then
            if not terminalSuppressionLogged then
                terminalSuppressionLogged = true
                Isaac.DebugString("[Isaac1v1P2P] TERMINAL_EVENT_SUPPRESSED reason=\"RESULT_ALREADY_FINAL\"")
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
            -- A vanilla ending is not proof that the selected target died. The
            -- target callback above is the sole completion authority.
            submitTerminal(liveIPC, gameState, matchSession, "WRONG_DESTINATION", competitiveRun)
            logRunEnded(gameState, "WRONG_DESTINATION", matchSession)
            competitiveRun.Deactivate("WRONG_DESTINATION")
        end
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
        -- ABANDON/DECONECTARE: Exit Game în STARTED trimite MATCH_DISCONNECT înainte
        -- de dezactivarea locală. Sistemul extern decide apoi rezultatul LOSS.
        local session = matchSession ~= nil and matchSession.Get ~= nil and matchSession.Get() or nil
        if localRunCompletedMatchId ~= nil and session ~= nil
            and session.matchId == localRunCompletedMatchId then
            Isaac.DebugString("[Isaac1v1P2P] PROGRAMMATIC_COMPLETION_EXIT_IGNORED match_id="
                .. quote(localRunCompletedMatchId))
            return
        end
        local competitive = competitiveRun ~= nil and competitiveRun.IsActiveFor ~= nil
            and competitiveRun.IsActiveFor(session)
        if state == STATE_IN_RUN and competitive then
            Isaac.DebugString("[Isaac1v1P2P] COMPETITIVE_EXIT_DETECTED match_id=\""
                .. tostring(session ~= nil and session.matchId or "")
                .. "\" state=\"STARTED\"")
            if liveIPC ~= nil and liveIPC.DisconnectMatch ~= nil and session ~= nil then
                pcall(liveIPC.DisconnectMatch, session.matchId)
            end
            logRunEnded(gameState, "ABANDONED", matchSession)
            competitiveRun.Deactivate("ABANDON")
        end
    end)

    Isaac.DebugString("[Isaac1v1P2P] Lifecycle initialized")
end

function lifecycle.IsLocalRunCompleted(matchId)
    return type(matchId) == "string" and localRunCompletedMatchId == matchId
end

return lifecycle
