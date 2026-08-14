local matchValidation = {}

local lastResult = {valid = false, reasons = {"NO_MATCH_SESSION"}}
local lastLogKey = nil

local function value(getter)
    local ok, result = pcall(getter)
    if not ok or result == nil or tostring(result) == "" then
        return "Unknown"
    end
    return tostring(result)
end

local function normalizeSeed(seed)
    if seed == nil then return nil end
    return tostring(seed):upper():gsub("%s+", "")
end

local function quote(valueToQuote)
    return '"' .. tostring(valueToQuote):gsub('"', "'") .. '"'
end

local function appendReason(reasons, reason)
    table.insert(reasons, reason)
end

local function emitValidationLog(session, result, gameState)
    local reasonText = table.concat(result.reasons, ",")
    local logKey = tostring(result.valid) .. "|" .. reasonText
    if logKey == lastLogKey then return end
    lastLogKey = logKey

    if result.valid then
        Isaac.DebugString(
            "[Isaac1v1] MATCH_VALID " ..
            "character=" .. quote(value(gameState.getCharacterName)) .. " " ..
            "seed=" .. quote(value(gameState.getSeedString)) .. " " ..
            "difficulty=" .. quote(value(gameState.getDifficultyName)):upper()
        )
        return
    end

    Isaac.DebugString(
        "[Isaac1v1] MATCH_INVALID " ..
        "reason=" .. quote(result.reasons[1] or "UNKNOWN") .. " " ..
        "reasons=" .. quote(reasonText) .. " " ..
        "expected_player_type=" .. quote(session ~= nil and session.characterType or "Unknown") .. " " ..
        "actual_player_type=" .. quote(value(gameState.getPlayerTypeId)) .. " " ..
        "expected_seed=" .. quote(session ~= nil and session.seed or "ANY") .. " " ..
        "actual_seed=" .. quote(value(gameState.getSeedString)) .. " " ..
        "difficulty=" .. quote(value(gameState.getDifficultyName)) .. " " ..
        "greed_mode=" .. quote(value(gameState.isGreedMode))
    )
end

function matchValidation.Validate(session, gameState)
    if session == nil or session.active ~= true then
        lastResult = {valid = false, reasons = {"NO_MATCH_SESSION"}}
        emitValidationLog(session, lastResult, gameState)
        return lastResult
    end

    local reasons = {}
    local playerType = value(gameState.getPlayerTypeId)
    local stage = value(gameState.getStage)
    local seed = value(gameState.getSeedString)
    local difficulty = value(gameState.getDifficultyValue)
    local greedMode = value(gameState.isGreedMode)

    if playerType == "Unknown" then
        appendReason(reasons, "NO_PLAYER")
        appendReason(reasons, "UNKNOWN_CHARACTER")
    elseif session.characterType ~= nil and tonumber(playerType) ~= session.characterType then
        appendReason(reasons, "CHARACTER_MISMATCH")
    end

    if stage == "Unknown" or tonumber(stage) == 0 then
        appendReason(reasons, "NO_ACTIVE_RUN")
    end

    if session.seed ~= nil then
        if seed == "Unknown" then
            appendReason(reasons, "UNKNOWN_SEED")
        elseif normalizeSeed(seed) ~= normalizeSeed(session.seed) then
            appendReason(reasons, "SEED_MISMATCH")
        end
    end

    if session.gameMode == "STANDARD" then
        if greedMode == "Unknown" then
            appendReason(reasons, "UNKNOWN_GAME_MODE")
        elseif greedMode == "true" then
            appendReason(reasons, "INVALID_GAME_MODE")
        end
    end

    if session.difficulty == "HARD" then
        if difficulty == "Unknown" then
            appendReason(reasons, "UNKNOWN_DIFFICULTY")
        elseif tonumber(difficulty) ~= Difficulty.DIFFICULTY_HARD then
            appendReason(reasons, "NOT_HARD")
        end
    end

    lastResult = {valid = #reasons == 0, reasons = reasons}
    emitValidationLog(session, lastResult, gameState)
    return lastResult
end

function matchValidation.Reset()
    lastResult = {valid = false, reasons = {"NO_MATCH_SESSION"}}
    lastLogKey = nil
end

function matchValidation.IsValid() return lastResult.valid end
function matchValidation.GetReasons() return lastResult.reasons end
function matchValidation.GetLastResult() return lastResult end

return matchValidation
