-- HUD de dezvoltare INACTIV pentru verificarea run-ului, sesiunii și punctajului.
-- main.lua nu încarcă acest modul, deci nu este afișat în fluxul curent.
local debugHud = {}
local renderLogged = false
local renderErrorLogged = false
local lastScoreDisplay = "Unknown"

local function readValue(getter)
    local ok, value = pcall(getter)
    if ok and value ~= nil and tostring(value) ~= "" then
        return tostring(value)
    end
    return "Unknown"
end

local function readScore(gameState)
    local ok, score = pcall(gameState.getVanillaScore)
    local display = "Unknown"
    if ok and score ~= nil and tostring(score) ~= "" then
        display = tostring(score)
    end

    if display ~= lastScoreDisplay then
        Isaac.DebugString("[Isaac1v1] SCORE_CHANGED old=\"" .. lastScoreDisplay .. "\" new=\"" .. display .. "\"")
        lastScoreDisplay = display
    end
    return display
end

function debugHud.Register(mod, gameState, matchValidation, matchSession, matchBridge, liveIPC)
    -- Dacă este înregistrat manual, MC_POST_RENDER afișează date de diagnostic pentru
    -- run-ul activ și citește punctajul adversarului din liveIPC în STARTED.
    mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
        local ok, err = pcall(function()
            local activeOk, active = pcall(gameState.isRunActive)
            if not activeOk or not active then
                return
            end

            local matchResult = {valid = false, reasons = {"UNKNOWN"}}
            if matchValidation ~= nil and matchValidation.GetLastResult ~= nil then
                local resultOk, result = pcall(matchValidation.GetLastResult)
                if resultOk and result ~= nil then
                    matchResult = result
                end
            end
            local session = nil
            if matchSession ~= nil and matchSession.Get ~= nil then
                local sessionOk, sessionValue = pcall(matchSession.Get)
                if sessionOk then session = sessionValue end
            end
            local expectedCharacter = session ~= nil and session.characterName or "Unknown"
            local expectedSeed = session ~= nil and session.seed or "ANY"
            local requiredDifficulty = session ~= nil and session.difficulty or "Unknown"
            local matchId = session ~= nil and session.matchId or "Unknown"
            local sessionState = session ~= nil and session.active == true and "ACTIVE" or "INACTIVE"
            local sessionSource = session ~= nil and session.source or "Unknown"
            local firstReason = matchResult.reasons ~= nil and matchResult.reasons[1] or "UNKNOWN"

            local lines = {
                "ISAAC 1V1 DEBUG",
                "Character: " .. readValue(gameState.getCharacterName),
                "Seed: " .. readValue(gameState.getSeedString),
                "Floor: " .. readValue(gameState.getFloorName),
                "Run Time: " .. readValue(gameState.getRunTime),
                "Vanilla Score: " .. readScore(gameState),
                "Score Status: " .. readValue(gameState.getVanillaScoreStatus),
                "Difficulty: " .. readValue(gameState.getDifficultyName):upper(),
                "Required: " .. requiredDifficulty,
                "Game Mode: " .. readValue(gameState.getGameModeName),
                "REPENTOGON: " .. readValue(gameState.getRepentogonStatus),
                "Match: " .. (matchResult.valid and "VALID" or "INVALID"),
                "Reason: " .. firstReason,
                "Match ID: " .. tostring(matchId),
                "Session: " .. sessionState,
                "Source: " .. tostring(sessionSource),
                "Bridge: " .. (matchBridge ~= nil and readValue(matchBridge.GetStatus) or "ERROR"),
                "Expected Character: " .. tostring(expectedCharacter),
                "Expected Seed: " .. tostring(expectedSeed)
            }

            if liveIPC ~= nil and liveIPC.GetStatus ~= nil then
                local statusOk, status = pcall(liveIPC.GetStatus)
                if statusOk and status.queue == "STARTED" then
                    local opponent = "Unknown"
                    if status.matchControl ~= nil and status.matchControl.players ~= nil then
                        for _, player in ipairs(status.matchControl.players) do
                            if status.player == nil or player.playerId ~= status.player.playerId then
                                opponent = tostring(player.score or "Unknown")
                            end
                        end
                    end
                    table.insert(lines, 1, "OPPONENT: " .. opponent)
                    table.insert(lines, 1, "YOUR SCORE: " .. readScore(gameState))
                end
            end

            for index, line in ipairs(lines) do
                local renderOk = pcall(Isaac.RenderText, line, 24, 90 + ((index - 1) * 16), 1, 1, 1, 1)
                if renderOk and not renderLogged then
                    renderLogged = true
                    Isaac.DebugString("[Isaac1v1] Debug HUD render active")
                elseif not renderOk and not renderErrorLogged then
                    renderErrorLogged = true
                    Isaac.DebugString("[Isaac1v1] ERROR: Debug HUD text render failed")
                end
            end
        end)

        if not ok and not renderErrorLogged then
            renderErrorLogged = true
            Isaac.DebugString("[Isaac1v1] ERROR: Debug HUD render failed: " .. tostring(err))
        end
    end)

    Isaac.DebugString("[Isaac1v1] Debug HUD initialized")
end

return debugHud
