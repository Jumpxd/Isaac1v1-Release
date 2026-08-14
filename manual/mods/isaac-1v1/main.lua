Isaac.DebugString("[Isaac1v1] MAIN LUA EXECUTED")

local mod = RegisterMod("Isaac 1v1", 1)

Isaac.DebugString("Isaac 1v1 loaded")

if REPENTOGON ~= nil then
    local version = REPENTOGON.Version or "unknown"
    Isaac.DebugString("Isaac 1v1: REPENTOGON detected (version " .. tostring(version) .. ")")
else
    Isaac.DebugString("Isaac 1v1: REPENTOGON not detected")
end

local function loadScript(path)
    local ok, result = pcall(include, path)
    if not ok then
        Isaac.DebugString("Isaac 1v1 ERROR: failed to load " .. path .. ": " .. tostring(result))
        return nil
    end
    return result
end

local gameState = loadScript("scripts/game_state.lua")
local lifecycle = loadScript("scripts/lifecycle.lua")
local matchSession = loadScript("scripts/match_session.lua")
local matchBridge = loadScript("scripts/match_bridge.lua")
local localBridge = loadScript("scripts/local_bridge.lua")
local liveIPC = loadScript("scripts/live_ipc.lua")
local runLauncher = loadScript("scripts/run_launcher.lua")
local matchValidation = loadScript("scripts/match_validation.lua")
local menuPrototype = loadScript("scripts/menu_prototype.lua")
local matchResult = loadScript("scripts/match_result.lua")
local characterAvailability = loadScript("scripts/character_availability.lua")
local competitiveRun = loadScript("scripts/competitive_run.lua")
local competitiveConsoleGuard = loadScript("scripts/competitive_console_guard.lua")
local modCompatibility = loadScript("scripts/mod_compatibility.lua")

if modCompatibility ~= nil and liveIPC ~= nil then
    if modCompatibility.SetActiveModProvider ~= nil and liveIPC.GetActiveMods ~= nil then
        pcall(modCompatibility.SetActiveModProvider, liveIPC.GetActiveMods)
    end
    if modCompatibility.GetAllowedModMetadata ~= nil and liveIPC.SetCompetitiveModAllowlist ~= nil then
        local metadataOk, metadata = pcall(modCompatibility.GetAllowedModMetadata)
        if metadataOk then pcall(liveIPC.SetCompetitiveModAllowlist, metadata) end
    end
end

if matchBridge ~= nil and matchBridge.Load ~= nil and matchSession ~= nil then
    local ok, err = pcall(matchBridge.Load, mod, matchSession)
    if not ok then
        Isaac.DebugString("Isaac 1v1 ERROR: failed to initialize match bridge: " .. tostring(err))
    end
else
    Isaac.DebugString("Isaac 1v1 ERROR: match bridge is unavailable")
end

if localBridge ~= nil and localBridge.Initialize ~= nil then
    local ok, err = pcall(localBridge.Initialize, mod, matchSession)
    if not ok then
        Isaac.DebugString("Isaac 1v1 ERROR: failed to initialize local bridge: " .. tostring(err))
    end
else
    Isaac.DebugString("Isaac 1v1 ERROR: local bridge is unavailable")
end

-- Development-only: uncomment once to write the sample SaveData payload, then comment it again.
-- matchBridge.WriteDevelopmentPayload(mod)

if gameState ~= nil and lifecycle ~= nil and lifecycle.Register ~= nil then
    local ok, err = pcall(lifecycle.Register, mod, gameState, matchValidation, matchSession, liveIPC, competitiveRun, matchBridge, matchResult)
    if not ok then
        Isaac.DebugString("Isaac 1v1 ERROR: failed to initialize lifecycle: " .. tostring(err))
    end
else
    Isaac.DebugString("Isaac 1v1 ERROR: lifecycle is unavailable")
end

if runLauncher ~= nil and runLauncher.Register ~= nil and matchSession ~= nil then
    local ok, err = pcall(runLauncher.Register, mod, matchSession, gameState, matchValidation, matchBridge, liveIPC, competitiveRun, modCompatibility)
    if not ok then
        Isaac.DebugString("Isaac 1v1 ERROR: failed to initialize run launcher: " .. tostring(err))
    end
else
    Isaac.DebugString("Isaac 1v1 ERROR: run launcher is unavailable")
end

if matchSession == nil or matchValidation == nil or matchBridge == nil then
    Isaac.DebugString("Isaac 1v1 ERROR: match validation is unavailable")
end

if liveIPC ~= nil and liveIPC.SetMatchResetHandler ~= nil then
    pcall(liveIPC.SetMatchResetHandler, function(previousMatchId, newMatchId, session)
        if matchSession ~= nil and matchSession.Clear ~= nil then pcall(matchSession.Clear) end
        if competitiveRun ~= nil and competitiveRun.BeginNewMatch ~= nil then
            pcall(competitiveRun.BeginNewMatch, session, previousMatchId)
        end
        if lifecycle ~= nil and lifecycle.BeginNewMatch ~= nil then pcall(lifecycle.BeginNewMatch, newMatchId) end
        if runLauncher ~= nil and runLauncher.BeginNewMatch ~= nil then pcall(runLauncher.BeginNewMatch, newMatchId) end
        if matchResult ~= nil and matchResult.BeginNewMatch ~= nil then pcall(matchResult.BeginNewMatch, newMatchId) end
        if menuPrototype ~= nil and menuPrototype.BeginNewMatch ~= nil then pcall(menuPrototype.BeginNewMatch, newMatchId) end
    end)
end


if liveIPC ~= nil and liveIPC.Initialize ~= nil then
    local ok, available = pcall(liveIPC.Initialize)
    if not ok or available ~= true then
        Isaac.DebugString("[Isaac1v1] IPC initialization failed")
    else
        local function updateLiveIPC(submitScore)
            local updateOk, updateError = pcall(liveIPC.Update)
            if not updateOk then
                Isaac.DebugString("[Isaac1v1] IPC update error: " .. tostring(updateError))
            end
            if submitScore == true and competitiveRun ~= nil and competitiveRun.IsActiveFor ~= nil
                and competitiveRun.IsActiveFor(matchSession ~= nil and matchSession.Get() or nil)
                and gameState ~= nil and liveIPC.MaybeSubmitScore ~= nil
                and gameState.isRunActive ~= nil and gameState.isRunActive() then
                local score = gameState.getVanillaScore ~= nil and gameState.getVanillaScore() or nil
                pcall(liveIPC.MaybeSubmitScore, score, gameState.getRunTime ~= nil and gameState.getRunTime() or nil)
            end
        end
        mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function() updateLiveIPC(true) end)
        if ModCallbacks.MC_POST_RENDER ~= nil then
            mod:AddCallback(ModCallbacks.MC_POST_RENDER, function() updateLiveIPC(false) end)
        end
        if ModCallbacks.MC_MAIN_MENU_RENDER ~= nil then
        mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function() updateLiveIPC(false) end)
        if characterAvailability ~= nil and characterAvailability.ReportIfChanged ~= nil then
            mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function()
                pcall(characterAvailability.ReportIfChanged, liveIPC)
            end)
        end
        end
        if ModCallbacks.MC_PRE_MOD_UNLOAD ~= nil then
            mod:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function()
                if competitiveRun ~= nil and competitiveRun.Deactivate ~= nil then pcall(competitiveRun.Deactivate, "MOD_UNLOAD") end
                pcall(liveIPC.Shutdown)
            end)
        end
    end
else
    Isaac.DebugString("[Isaac1v1] IPC module unavailable")
end

if matchResult ~= nil and matchResult.Register ~= nil then
    local ok, err = pcall(matchResult.Register, mod, liveIPC, matchSession, menuPrototype, competitiveRun)
    if not ok then Isaac.DebugString("[Isaac1v1] ERROR: result screen unavailable: " .. tostring(err)) end
end

if menuPrototype ~= nil and menuPrototype.Register ~= nil then
    local ok, err = pcall(menuPrototype.Register, mod, localBridge, liveIPC, modCompatibility, runLauncher)
    if not ok then
        Isaac.DebugString("Isaac 1v1 ERROR: failed to initialize in-game menu prototype: " .. tostring(err))
    end
else
    Isaac.DebugString("Isaac 1v1 ERROR: in-game menu prototype is unavailable")
end

if competitiveConsoleGuard ~= nil and competitiveConsoleGuard.Register ~= nil then
    local ok, registered = pcall(competitiveConsoleGuard.Register, mod, competitiveRun)
    if not ok or registered ~= true then
        Isaac.DebugString("[Isaac1v1] ERROR: competitive console guard unavailable")
    end
else
    Isaac.DebugString("[Isaac1v1] ERROR: competitive console guard module unavailable")
end
