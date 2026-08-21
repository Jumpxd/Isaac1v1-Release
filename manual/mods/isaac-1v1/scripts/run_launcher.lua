-- Pornește run-ul competitiv controlat. Preia un MATCH_START valid, pregătește
-- destinația de save, apelează Isaac.StartNewGame și confirmă STARTED.
local runLauncher = {}
local characterCatalog = include("scripts/character_catalog.lua")

local attemptedMatchKey = nil
local requestedMatchId = nil
local status = "WAITING"
local lastError = nil
local triggerLogged = false
local idleLogged = false
local resetMatchId = nil

local function quote(value)
    return '"' .. tostring(value):gsub('"', "'") .. '"'
end

local function normalizeSeed(seed)
    return tostring(seed):upper():gsub("%s+", "")
end

local function isLaunchableSource(source)
    return source == "COMPANION" or source == "SERVER"
end

local function unavailable(reason)
    status = "ERROR"
    lastError = reason
    Isaac.DebugString("[Isaac1v1] RUN_LAUNCH_UNAVAILABLE reason=" .. quote(reason))
end

local function getCompetitiveSaveSlot()
    if type(Isaac1v1IPC) ~= "table"
        or type(Isaac1v1IPC.GetCompetitiveSaveSlot) ~= "function" then return "Unknown" end
    local ok, slot = pcall(Isaac1v1IPC.GetCompetitiveSaveSlot)
    if not ok or slot == nil then return "Unknown" end
    return tostring(slot)
end

local function failConsumedLaunch(reason, detail, session, liveIPC, competitiveRun)
    if competitiveRun ~= nil and competitiveRun.ClearIntent ~= nil then
        competitiveRun.ClearIntent()
    end
    unavailable(reason)
    Isaac.DebugString(
        "[Isaac1v1] COMPETITIVE_LAUNCH_FAILED " ..
        "match_id=" .. quote(session ~= nil and session.matchId or "Unknown") .. " " ..
        "slot=" .. quote(getCompetitiveSaveSlot()) .. " " ..
        "reason=" .. quote(reason) .. " " ..
        "detail=" .. quote(detail or "Unknown")
    )
    if liveIPC ~= nil and liveIPC.CancelMatch ~= nil then
        local cancelOk, cancelled, cancelError = pcall(liveIPC.CancelMatch)
        Isaac.DebugString(
            "[Isaac1v1] COMPETITIVE_LAUNCH_CANCEL_SENT " ..
            "match_id=" .. quote(session ~= nil and session.matchId or "Unknown") .. " " ..
            "sent=" .. quote(cancelOk and cancelled == true) .. " " ..
            "error=" .. quote(cancelOk and cancelError or cancelled)
        )
    end
    return false
end

local function getSession(matchSession)
    if matchSession == nil or matchSession.Get == nil then return nil end
    local ok, session = pcall(matchSession.Get)
    if ok then return session end
    return nil
end

local function isLaunchMenuActive()
    -- F8 schimbă meniul activ la ID-ul custom Isaac 1v1. Dacă verificarea s-ar
    -- limita la MainMenuType.GAME, mesajele MATCH_START sosite în meniul custom
    -- s-ar pierde, iar sesiunea ar rămâne în STARTING până la restart.
    if MenuManager == nil or type(MenuManager.IsActive) ~= "function" then
        return false
    end

    local activeOk, active = pcall(MenuManager.IsActive)
    if not activeOk or active ~= true then
        return false
    end

    return true
end

local function canStart(session, gameState, launchRequest)
    -- Verificare strictă înainte de consumarea cererii. Controlează identitatea și
    -- configurația sesiunii, API-urile necesare, seed-ul și starea curentă a jocului.
    if session == nil or session.active ~= true then
        return false, "NO_MATCH_SESSION"
    end
    if launchRequest == nil or launchRequest.requested ~= true then
        return false, "NO_LAUNCH_REQUEST"
    end
    if launchRequest.matchId ~= session.matchId then
        return false, "LAUNCH_REQUEST_MISMATCH"
    end
    if not isLaunchableSource(session.source) then
        return false, "SOURCE_NOT_LAUNCHABLE"
    end
    if session.characterType == nil then
        return false, "CHARACTER_NOT_CONFIGURED"
    end
    if characterCatalog == nil or type(characterCatalog.IsSupported) ~= "function"
        or not characterCatalog.IsSupported(session.characterType) then
        return false, "CHARACTER_NOT_SUPPORTED"
    end
    if session.seed == nil or tostring(session.seed) == "" then
        return false, "SEED_NOT_CONFIGURED"
    end
    if session.difficulty ~= "HARD" then
        return false, "DIFFICULTY_NOT_HARD"
    end
    if session.gameMode ~= "STANDARD" then
        return false, "GAME_MODE_NOT_STANDARD"
    end
    if REPENTOGON == nil or type(Isaac.StartNewGame) ~= "function" then
        return false, "START_NEW_GAME_UNAVAILABLE"
    end
    if Seeds == nil or type(Seeds.IsStringValidSeed) ~= "function" or type(Seeds.String2Seed) ~= "function" then
        return false, "SEED_API_UNAVAILABLE"
    end

    local validOk, validSeed = pcall(Seeds.IsStringValidSeed, session.seed)
    if not validOk or not validSeed then
        return false, "INVALID_SEED"
    end

    if gameState ~= nil and gameState.isRunActive ~= nil then
        local activeOk, active = pcall(gameState.isRunActive)
        if activeOk and active then
            return false, "RUN_ALREADY_ACTIVE"
        end
    end
    return true, nil
end

local function startFromSession(session, gameState, matchBridge, liveIPC, liveStart, competitiveRun, modCompatibility)
    -- Fluxul de PORNIRE, apelat din callback-ul meniului după sosirea MATCH_START.
    -- Întoarce true numai după StartNewGame și verificarea destinației de save.
    if liveIPC ~= nil and liveIPC.IsCancelled ~= nil then
        local cancelledOk, cancelled = pcall(liveIPC.IsCancelled, session and session.matchId)
        if cancelledOk and cancelled == true then
            Isaac.DebugString("[Isaac1v1] RUN_START_CANCELLED_IGNORED match_id=" .. quote(session.matchId))
            return false
        end
    end
    local launchRequest = nil
    if liveStart ~= nil then
        launchRequest = {requested = true, matchId = liveStart.matchId}
    elseif matchBridge ~= nil and matchBridge.GetLaunchRequest ~= nil then
        local requestOk, requestValue = pcall(matchBridge.GetLaunchRequest)
        if requestOk then launchRequest = requestValue end
    end

    local canStartNow, reason = canStart(session, gameState, launchRequest)
    if not canStartNow then
        unavailable(reason)
        return false
    end
    if modCompatibility ~= nil and modCompatibility.GetCompetitiveModCompatibility ~= nil then
        -- ALLOWLIST: repetă verificarea chiar înainte de pornire. Dacă modurile au
        -- fost schimbate după intrarea în coadă, run-ul competitiv este blocat.
        local compatibilityOk, result = pcall(modCompatibility.GetCompetitiveModCompatibility)
        if compatibilityOk and result ~= nil and result.compatible == false then
            local names = {}
            for _, conflict in ipairs(result.conflictingMods or {}) do
                names[#names + 1] = type(conflict) == "table" and tostring(conflict.displayName) or tostring(conflict)
            end
            unavailable("MOD_NOT_ALLOWED")
            Isaac.DebugString('[Isaac1v1] MATCHMAKING_BLOCKED reason="MOD_NOT_ALLOWED"')
            Isaac.DebugString("[Isaac1v1] COMPETITIVE_MOD_CONFLICT mods=" .. quote(table.concat(names, ",")))
            if liveIPC ~= nil and liveIPC.CancelMatch ~= nil then pcall(liveIPC.CancelMatch) end
            return false
        end
    end

    local seedOk, numericSeed = pcall(Seeds.String2Seed, session.seed)
    if not seedOk or type(numericSeed) ~= "number" or numericSeed == 0 then
        unavailable("INVALID_SEED")
        return false
    end

    local consumeOk, consumed
    if liveStart ~= nil and liveIPC ~= nil and liveIPC.ConsumeStart ~= nil then
        consumeOk, consumed = pcall(liveIPC.ConsumeStart, session.matchId, liveStart.startGeneration)
    elseif matchBridge ~= nil and matchBridge.ConsumeLaunchRequest ~= nil then
        consumeOk, consumed = pcall(matchBridge.ConsumeLaunchRequest, session.matchId)
    else
        unavailable("LAUNCH_REQUEST_CONSUME_UNAVAILABLE")
        return false
    end
    if not consumeOk or consumed ~= true then
        unavailable("LAUNCH_REQUEST_CONSUME_FAILED")
        return false
    end
    Isaac.DebugString("[Isaac1v1] RUN_LAUNCH_REQUEST_CONSUMED match_id=" .. quote(session.matchId))

    Isaac.DebugString(
        "[Isaac1v1] RUN_LAUNCH_REQUESTED " ..
        "match_id=" .. quote(session.matchId or "Unknown") .. " " ..
        "character=" .. quote(session.characterName) .. " " ..
        "seed=" .. quote(session.seed)
    )
    Isaac.DebugString(
        "[Isaac1v1] RUN_START_REQUESTED " ..
        "match_id=" .. quote(session.matchId or "Unknown") .. " " ..
        "generation=" .. quote(liveStart ~= nil and liveStart.startGeneration or "<none>")
    )

    requestedMatchId = session.matchId
    status = "REQUESTED"
    lastError = nil
    -- Intenția ajută MC_POST_GAME_STARTED să deosebească această pornire controlată
    -- de un run normal sau de apăsarea opțiunii Continue.
    if competitiveRun == nil or competitiveRun.SetIntent == nil or competitiveRun.SetIntent(session) ~= true then
        unavailable("COMPETITIVE_INTENT_FAILED")
        return false
    end
    local saveSlot = getCompetitiveSaveSlot()
    Isaac.DebugString(
        "[Isaac1v1] COMPETITIVE_LAUNCH_BEGIN " ..
        "match_id=" .. quote(session.matchId) .. " slot=" .. quote(saveSlot)
    )
    if type(Isaac1v1IPC) ~= "table"
        or type(Isaac1v1IPC.PrepareCompetitiveSaveSlot) ~= "function" then
        return failConsumedLaunch(
            "COMPETITIVE SAVE INIT FAILED", "COMPETITIVE_SAVE_SLOT_PREPARE_UNAVAILABLE",
            session, liveIPC, competitiveRun)
    end
    local slotOk, slotPrepared, slotError = pcall(
        Isaac1v1IPC.PrepareCompetitiveSaveSlot, session.matchId)
    -- DESTINAȚIA DE SAVE: inițializarea trebuie să reușească înainte de StartNewGame.
    -- La eroare, meciul este anulat clar și nu lasă jucătorii blocați în STARTING.
    if not slotOk or slotPrepared ~= true then
        return failConsumedLaunch(
            "COMPETITIVE SAVE INIT FAILED",
            "COMPETITIVE_SAVE_SLOT_PREPARE_FAILED: "
                .. tostring(slotOk and slotError or slotPrepared),
            session, liveIPC, competitiveRun)
    end

    Isaac.DebugString(
        "[Isaac1v1] START_NEW_GAME_CALL " ..
        "match_id=" .. quote(session.matchId) .. " slot=" .. quote(saveSlot)
    )
    local startOk, startError = pcall(
        Isaac.StartNewGame,
        session.characterType,
        Challenge.CHALLENGE_NULL,
        Difficulty.DIFFICULTY_HARD,
        numericSeed,
        false
    )
    if not startOk then
        return failConsumedLaunch(
            "START NEW GAME FAILED", "START_NEW_GAME_ERROR: " .. tostring(startError),
            session, liveIPC, competitiveRun)
    end
    Isaac.DebugString(
        "[Isaac1v1] START_NEW_GAME_RETURN " ..
        "match_id=" .. quote(session.matchId) .. " slot=" .. quote(saveSlot)
    )
    if type(Isaac1v1IPC.VerifyCompetitiveSaveTarget) ~= "function" then
        return failConsumedLaunch(
            "COMPETITIVE SAVE INIT FAILED", "COMPETITIVE_SAVE_TARGET_VERIFY_UNAVAILABLE",
            session, liveIPC, competitiveRun)
    end
    local targetOk, targetValid, targetError = pcall(
        Isaac1v1IPC.VerifyCompetitiveSaveTarget, "AFTER_START_NEW_GAME")
    -- Verifică din nou după apelul engine-ului, deoarece StartNewGame poate schimba save context-ul.
    if not targetOk or targetValid ~= true then
        return failConsumedLaunch(
            "COMPETITIVE SAVE INIT FAILED",
            "COMPETITIVE_SAVE_PATH_INIT_FAILED: "
                .. tostring(targetOk and targetError or targetValid),
            session, liveIPC, competitiveRun)
    end
    return true
end

local function confirmStarted(session, gameState, matchValidation, competitiveRun)
    -- Confirmarea STARTED apelată din MC_POST_GAME_STARTED. Compară run-ul real cu
    -- sesiunea, activează starea competitivă și întoarce ID-ul meciului.
    if requestedMatchId == nil or session == nil or session.matchId ~= requestedMatchId then
        return
    end

    local valid = false
    if matchValidation ~= nil and matchValidation.GetLastResult ~= nil then
        local resultOk, result = pcall(matchValidation.GetLastResult)
        valid = resultOk and result ~= nil and result.valid == true
    end

    local actualSeed = "Unknown"
    local actualCharacter = "Unknown"
    local actualDifficulty = "Unknown"
    local actualGameMode = "Unknown"
    if gameState ~= nil then
        actualSeed = tostring(gameState.getSeedString())
        actualCharacter = tostring(gameState.getPlayerTypeId())
        actualDifficulty = tostring(gameState.getDifficultyName()):upper()
        actualGameMode = tostring(gameState.getGameModeName())
    end

    valid = valid and actualCharacter == tostring(session.characterType)
        and normalizeSeed(actualSeed) == normalizeSeed(session.seed)
        and actualDifficulty == "HARD"
        and actualGameMode == "STANDARD"

    if not valid then
        unavailable("RUN_VALIDATION_FAILED")
        return
    end

    local activated = competitiveRun ~= nil and competitiveRun.IsActiveFor ~= nil
        and competitiveRun.IsActiveFor(session)
    if not activated and competitiveRun ~= nil and competitiveRun.Activate ~= nil then
        activated = competitiveRun.Activate(session) == true
    end
    if not activated then
        unavailable("COMPETITIVE_ACTIVATION_FAILED")
        return
    end

    status = "STARTED"
    lastError = nil
    Isaac.DebugString(
        "[Isaac1v1] RUN_LAUNCH_STARTED match_id=" ..
        quote(session.matchId or "Unknown")
    )
    Isaac.DebugString(
        "[Isaac1v1] RUN_START_EXECUTED match_id=" ..
        quote(session.matchId or "Unknown")
    )
    Isaac.DebugString(
        "[Isaac1v1] COMPETITIVE_RUN_STATE active=true match_id=" ..
        quote(session.matchId or "Unknown")
    )
end

function runLauncher.BeginNewMatch(matchId)
    -- Resetează încercarea și eroarea pentru o nouă generație validă de meci.
    if type(matchId) ~= "string" or matchId == "" then return false end
    if resetMatchId == matchId then return true end
    resetMatchId = matchId
    attemptedMatchKey = nil
    requestedMatchId = nil
    status = "WAITING"
    lastError = nil
    triggerLogged = false
    idleLogged = false
    return true
end

function runLauncher.ResetTerminal()
    attemptedMatchKey = nil
    requestedMatchId = nil
    status = "WAITING"
    lastError = nil
    triggerLogged = false
    idleLogged = false
    resetMatchId = nil
    return true
end

function runLauncher.StartFromSession(session, gameState, matchBridge, competitiveRun, modCompatibility)
    local key = session ~= nil and (session.matchId .. ":local") or nil
    if session ~= nil and attemptedMatchKey == key then
        return false
    end
    if session ~= nil then attemptedMatchKey = key end
    return startFromSession(session, gameState, matchBridge, nil, nil, competitiveRun, modCompatibility)
end

function runLauncher.CanStart(session, gameState, launchRequest)
    return canStart(session, gameState, launchRequest)
end

function runLauncher.GetStatus() return status end
function runLauncher.GetLastError() return lastError end

function runLauncher.Register(mod, matchSession, gameState, matchValidation, matchBridge, liveIPC, competitiveRun, modCompatibility)
    -- Instalează cele două callback-uri ale pornirii: consumarea cererii din meniu
    -- și confirmarea după ce run-ul a pornit.
    mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function()
        -- MATCH_START poate fi consumat în siguranță numai cât timp meniul Isaac este activ.
        if not isLaunchMenuActive() then
            return
        end

        if not triggerLogged then
            triggerLogged = true
            Isaac.DebugString("[Isaac1v1] RUN_LAUNCH_MAIN_MENU_TRIGGER")
        end

        local session = getSession(matchSession)
        if session ~= nil and liveIPC ~= nil and liveIPC.IsCancelled ~= nil then
            local cancelledOk, cancelled = pcall(liveIPC.IsCancelled, session.matchId)
            if cancelledOk and cancelled == true then
                if matchSession ~= nil and matchSession.Clear ~= nil then pcall(matchSession.Clear) end
                requestedMatchId = nil
                if competitiveRun ~= nil and competitiveRun.Deactivate ~= nil then competitiveRun.Deactivate("CANCEL") end
                attemptedMatchKey = nil
                status = "WAITING"
                Isaac.DebugString("[Isaac1v1] RUN_START_CANCELLED_IGNORED match_id=" .. quote(session.matchId))
                return
            end
        end
        local liveStart = nil
        if liveIPC ~= nil and liveIPC.GetStartRequest ~= nil then
            local startOk, startValue = pcall(liveIPC.GetStartRequest)
            if startOk then liveStart = startValue end
            if liveStart ~= nil and matchSession ~= nil and matchSession.Set ~= nil then
                pcall(matchSession.Set, liveStart)
                session = getSession(matchSession)
            end
        end
        if liveStart ~= nil and liveIPC ~= nil and liveIPC.IsCancelled ~= nil then
            local cancelledOk, cancelled = pcall(liveIPC.IsCancelled, liveStart.matchId)
            if cancelledOk and cancelled == true then
                Isaac.DebugString("[Isaac1v1] RUN_START_CANCELLED_IGNORED match_id=" .. quote(liveStart.matchId))
                return
            end
        end
        local startKey = session ~= nil and (session.matchId .. ":" .. tostring(liveStart ~= nil and liveStart.startGeneration or "local")) or nil
        if session == nil or attemptedMatchKey == startKey then return end
        local launchRequest = nil
        if matchBridge ~= nil and matchBridge.GetLaunchRequest ~= nil then
            local requestOk, requestValue = pcall(matchBridge.GetLaunchRequest)
            if requestOk then launchRequest = requestValue end
        end
        if liveStart ~= nil then
            launchRequest = {requested = true}
        end
        if launchRequest == nil or launchRequest.requested ~= true then
            if not idleLogged then
                idleLogged = true
                Isaac.DebugString("[Isaac1v1] RUN_LAUNCH_IDLE reason=\"NO_LAUNCH_REQUEST\"")
            end
            return
        end
        attemptedMatchKey = startKey
        Isaac.DebugString("[Isaac1v1] MATCH_SESSION_APPLIED match_id=" .. quote(session.matchId)
            .. " generation=" .. quote(liveStart ~= nil and liveStart.startGeneration or "<none>"))
        startFromSession(session, gameState, matchBridge, liveIPC, liveStart, competitiveRun, modCompatibility)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
        -- Isaac apelează acest callback după crearea run-ului. Aici se fac, în ordine:
        -- verificarea save-ului, validarea run-ului, activarea și MATCH_STARTED.
        local session = getSession(matchSession)
        if session ~= nil and requestedMatchId == session.matchId then
            local targetOk, targetValid, targetError = pcall(
                Isaac1v1IPC.VerifyCompetitiveSaveTarget, "POST_GAME_STARTED")
            if not targetOk or targetValid ~= true then
                failConsumedLaunch(
                    "COMPETITIVE SAVE INIT FAILED",
                    "COMPETITIVE_SAVE_PATH_INIT_FAILED: "
                        .. tostring(targetOk and targetError or targetValid),
                    session, liveIPC, competitiveRun)
                return
            end
        end
        confirmStarted(session, gameState, matchValidation, competitiveRun)
        if liveIPC ~= nil and liveIPC.AcknowledgeStarted ~= nil and session ~= nil
            and requestedMatchId == session.matchId and competitiveRun ~= nil
            and competitiveRun.IsActiveFor ~= nil and competitiveRun.IsActiveFor(session) then
            local generation = nil
            if liveIPC.GetStatus ~= nil then
                local statusOk, statusValue = pcall(liveIPC.GetStatus)
                if statusOk and statusValue.match ~= nil then generation = statusValue.match.startGeneration end
            end
            if generation ~= nil then
                local ackOk, ackSent = pcall(liveIPC.AcknowledgeStarted, session.matchId, generation)
                if ackOk and ackSent == true then
                    Isaac.DebugString(
                        "[Isaac1v1] MATCH_STARTED_ACK_SENT " ..
                        "match_id=" .. quote(session.matchId) .. " " ..
                        "slot=" .. quote(getCompetitiveSaveSlot())
                    )
                end
            end
        end
    end)

    Isaac.DebugString("[Isaac1v1] Run launcher initialized")
end

return runLauncher
