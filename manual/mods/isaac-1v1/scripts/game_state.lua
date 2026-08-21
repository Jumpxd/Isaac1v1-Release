-- O vedere doar pentru citire asupra run-ului curent. Celelalte module folosesc
-- aceste funcții pentru validare, loguri, scor live și scorul de final.
local gameState = {}

local characterNames = {
    [0] = "Isaac",
    [1] = "Magdalene",
    [2] = "Cain",
    [3] = "Judas",
    [4] = "???",
    [5] = "Eve",
    [6] = "Samson",
    [7] = "Azazel",
    [8] = "Lazarus",
    [9] = "Eden",
    [10] = "The Lost",
    [11] = "Lazarus II",
    [12] = "Dark Judas",
    [13] = "Lilith",
    [14] = "Keeper",
    [15] = "Apollyon",
    [16] = "The Forgotten",
    [17] = "The Soul",
    [18] = "Bethany",
    [19] = "Jacob",
    [20] = "Esau",
    [21] = "Tainted Isaac",
    [22] = "Tainted Magdalene",
    [23] = "Tainted Cain",
    [24] = "Tainted Judas",
    [25] = "Tainted ???",
    [26] = "Tainted Eve",
    [27] = "Tainted Samson",
    [28] = "Tainted Azazel",
    [29] = "Tainted Lazarus",
    [30] = "Tainted Eden",
    [31] = "Tainted Lost",
    [32] = "Tainted Lilith",
    [33] = "Tainted Keeper",
    [34] = "Tainted Apollyon",
    [35] = "Tainted Forgotten",
    [36] = "Tainted Bethany",
    [37] = "Tainted Jacob",
    [38] = "Dead Tainted Lazarus",
    [39] = "Tainted Jacob (Lost)",
    [40] = "Tainted Soul"
}

local stageNames = {
    [LevelStage.STAGE1_1] = "Basement I",
    [LevelStage.STAGE1_2] = "Basement II",
    [LevelStage.STAGE2_1] = "Caves I",
    [LevelStage.STAGE2_2] = "Caves II",
    [LevelStage.STAGE3_1] = "Depths I",
    [LevelStage.STAGE3_2] = "Depths II",
    [LevelStage.STAGE4_1] = "Womb I",
    [LevelStage.STAGE4_2] = "Womb II",
    [LevelStage.STAGE4_3] = "???",
    [LevelStage.STAGE5] = "Sheol / The Cathedral",
    [LevelStage.STAGE6] = "Dark Room / The Chest",
    [LevelStage.STAGE7] = "The Void",
    [LevelStage.STAGE8] = "Home"
}

local function safeCall(callback, fallback)
    -- API-urile Isaac nu sunt disponibile în orice meniu sau stare. Dacă citirea
    -- eșuează, funcția întoarce o valoare sigură în loc să oprească un callback.
    local ok, value = pcall(callback)
    if ok and value ~= nil and tostring(value) ~= "" then
        return value
    end
    return fallback
end

function gameState.getCharacterName()
    -- Întoarce numele personajului jucătorului 0 sau "Unknown" dacă nu există run activ.
    return safeCall(function()
        local player = Isaac.GetPlayer(0)
        if player == nil then
            return "Unknown"
        end
        return characterNames[player:GetPlayerType()] or "Unknown"
    end, "Unknown")
end

function gameState.getPlayerTypeId()
    -- Întoarce PlayerType numeric, folosit pentru comparația cu MATCH_START.
    return safeCall(function()
        local player = Isaac.GetPlayer(0)
        if player == nil then
            return "Unknown"
        end
        return player:GetPlayerType()
    end, "Unknown")
end

function gameState.getSeedString()
    -- Întoarce seed-ul de start în formatul afișat, de exemplu ABCD EFGH.
    return safeCall(function()
        local seed = Game():GetSeeds():GetStartSeed()
        return Seeds.Seed2String(seed)
    end, "Unknown")
end

function gameState.getFloorName()
    -- Creează un nume ușor de citit pentru etaj, folosit în logurile meciului.
    return safeCall(function()
        local level = Game():GetLevel()
        local name = level:GetName()
        if name ~= nil and name ~= "" then
            return name
        end
        return stageNames[level:GetStage()] or "Unknown"
    end, "Unknown")
end

function gameState.getStage()
    return safeCall(function()
        return Game():GetLevel():GetStage()
    end, "Unknown")
end

function gameState.getStageType()
    return safeCall(function()
        return Game():GetLevel():GetStageType()
    end, "Unknown")
end

function gameState.getDifficultyValue()
    return safeCall(function()
        return Game().Difficulty
    end, "Unknown")
end

function gameState.getDifficultyName()
    -- Transformă constantele de dificultate Isaac în numele folosite de protocol.
    return safeCall(function()
        local difficulty = Game().Difficulty
        if difficulty == Difficulty.DIFFICULTY_NORMAL then
            return "Normal"
        elseif difficulty == Difficulty.DIFFICULTY_HARD then
            return "Hard"
        elseif difficulty == Difficulty.DIFFICULTY_GREED then
            return "Greed"
        elseif difficulty == Difficulty.DIFFICULTY_GREEDIER then
            return "Greedier"
        end
        return "Unknown"
    end, "Unknown")
end

function gameState.isGreedMode()
    return safeCall(function()
        return Game():IsGreedMode()
    end, "Unknown")
end

function gameState.getGameModeName()
    -- Meciurile competitive cer STANDARD; variantele Greed sunt identificate aici.
    return safeCall(function()
        local game = Game()
        if not game:IsGreedMode() then
            return "STANDARD"
        end
        if game.Difficulty == Difficulty.DIFFICULTY_GREEDIER then
            return "GREEDIER"
        end
        return "GREED"
    end, "Unknown")
end

function gameState.getRunTime()
    return safeCall(function()
        local totalSeconds = math.floor(Game():GetFrameCount() / 30)
        local minutes = math.floor(totalSeconds / 60)
        local seconds = totalSeconds % 60
        return string.format("%02d:%02d", minutes, seconds)
    end, "Unknown")
end

function gameState.getVanillaScore()
    -- Citește scorul REPENTOGON folosit în MATCH_SCORE_UPDATE și la finalul meciului.
    return safeCall(function()
        if REPENTOGON == nil or ScoreSheet == nil or type(ScoreSheet.GetTotalScore) ~= "function" then
            return nil
        end

        if type(ScoreSheet.Calculate) == "function" then
            ScoreSheet.Calculate()
        end

        local score = ScoreSheet.GetTotalScore()
        if type(score) ~= "number" then
            return nil
        end
        return score
    end, nil)
end

function gameState.getVanillaScoreStatus()
    if REPENTOGON == nil or ScoreSheet == nil or type(ScoreSheet.GetTotalScore) ~= "function" then
        return "UNAVAILABLE"
    end
    if type(ScoreSheet.Calculate) == "function" then
        return "LIVE"
    end
    return "CACHED"
end

function gameState.getRepentogonStatus()
    if REPENTOGON == nil then
        return "MISSING"
    end
    return "OK " .. tostring(REPENTOGON.Version or "Unknown")
end

function gameState.isRunActive()
    -- Întoarce true numai dacă Game():GetFrameCount() arată că este încărcat un run real.
    return safeCall(function()
        local game = Game()
        return game:GetFrameCount() > 0 and game:GetLevel():GetStage() > 0
    end, false)
end

return gameState
