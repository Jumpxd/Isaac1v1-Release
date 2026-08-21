-- Punctul de pornire al modului Isaac 1v1. Încarcă toate modulele folosite în joc,
-- le conectează între ele și înregistrează callback-urile Isaac/REPENTOGON.
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
    -- Încarcă fiecare modul în siguranță. Dacă lipsește un script, logul Isaac
    -- arată exact ce parte a inițializării a eșuat.
    local ok, result = pcall(include, path)
    if not ok then
        Isaac.DebugString("Isaac 1v1 ERROR: failed to load " .. path .. ": " .. tostring(result))
        return nil
    end
    return result
end

-- Aici sunt încărcate modulele. Callback-urile lor devin active abia când sunt
-- apelate mai jos funcțiile Register.
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
local destinationAvailability = loadScript("scripts/destination_availability.lua")
local targetHud = loadScript("scripts/target_hud.lua")
local routeAccessSetup = loadScript("scripts/route_access.lua")
local competitiveRun = loadScript("scripts/competitive_run.lua")
local competitiveConsoleGuard = loadScript("scripts/competitive_console_guard.lua")
local modCompatibility = loadScript("scripts/mod_compatibility.lua")

if modCompatibility ~= nil and liveIPC ~= nil then
    -- ALLOWLIST + IPC: Companion trimite lista modurilor active, iar Lua trimite
    -- lista oficială de moduri permise folosită la verificare.
    if modCompatibility.SetActiveModProvider ~= nil and liveIPC.GetActiveMods ~= nil then
        pcall(modCompatibility.SetActiveModProvider, liveIPC.GetActiveMods)
    end
    if modCompatibility.GetAllowedModMetadata ~= nil and liveIPC.SetCompetitiveModAllowlist ~= nil then
        local metadataOk, metadata = pcall(modCompatibility.GetAllowedModMetadata)
        if metadataOk then pcall(liveIPC.SetCompetitiveModAllowlist, metadata) end
    end
end

if matchBridge ~= nil and matchBridge.Load ~= nil and matchSession ~= nil then
    -- Curăță din SaveData datele vechi despre sesiune și pornire. O sesiune
    -- competitivă nouă poate începe doar după un mesaj valid MATCH_START.
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

-- Doar pentru dezvoltare: decomentează o singură dată ca să scrii exemplul în SaveData, apoi comentează la loc.
-- matchBridge.WriteDevelopmentPayload(mod)

if gameState ~= nil and lifecycle ~= nil and lifecycle.Register ~= nil then
    -- CICLUL MECIULUI: instalează callback-urile pentru start, etaj, moarte/revive,
    -- terminarea run-ului și ieșirea din joc.
    local ok, err = pcall(lifecycle.Register, mod, gameState, matchValidation, matchSession, liveIPC, competitiveRun, matchBridge, matchResult)
    if not ok then
        Isaac.DebugString("Isaac 1v1 ERROR: failed to initialize lifecycle: " .. tostring(err))
    end
else
    Isaac.DebugString("Isaac 1v1 ERROR: lifecycle is unavailable")
end

if runLauncher ~= nil and runLauncher.Register ~= nil and matchSession ~= nil then
    -- PORNIRE: preia un MATCH_START valid cât timp meniul este activ, pornește
    -- run-ul controlat și confirmă pornirea după ce Isaac a intrat în run.
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
    -- La fiecare ID nou de meci, resetează împreună toate modulele care păstrează
    -- date despre meci. Astfel, un RESULT vechi nu ajunge în meciul următor.
    pcall(liveIPC.SetMatchResetHandler, function(previousMatchId, newMatchId, session)
        if matchSession ~= nil and matchSession.Clear ~= nil then pcall(matchSession.Clear) end
        if competitiveRun ~= nil and competitiveRun.BeginNewMatch ~= nil then
            pcall(competitiveRun.BeginNewMatch, session, previousMatchId)
        end
        if lifecycle ~= nil and lifecycle.BeginNewMatch ~= nil then pcall(lifecycle.BeginNewMatch, newMatchId) end
        if runLauncher ~= nil and runLauncher.BeginNewMatch ~= nil then pcall(runLauncher.BeginNewMatch, newMatchId) end
        if matchResult ~= nil and matchResult.BeginNewMatch ~= nil then pcall(matchResult.BeginNewMatch, newMatchId) end
        if menuPrototype ~= nil and menuPrototype.BeginNewMatch ~= nil then pcall(menuPrototype.BeginNewMatch, newMatchId) end
        if routeAccessSetup ~= nil and routeAccessSetup.BeginNewMatch ~= nil then
            pcall(routeAccessSetup.BeginNewMatch, newMatchId)
        end
    end)
end


if liveIPC ~= nil and liveIPC.Initialize ~= nil then
    local ok, available = pcall(liveIPC.Initialize)
    if not ok or available ~= true then
        Isaac.DebugString("[Isaac1v1] IPC initialization failed")
    else
        local function updateLiveIPC(submitScore)
            -- Procesează IPC-ul local în meniu, la randare și în timpul jocului.
            -- Doar callback-ul de update cere trimiterea scorului live, cu limitare în IPC.
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
            -- Randarea continuă și când update-urile de gameplay sunt limitate,
            -- deci poate procesa în continuare mesajele RESULT și de conexiune.
            mod:AddCallback(ModCallbacks.MC_POST_RENDER, function() updateLiveIPC(false) end)
        end
        if ModCallbacks.MC_MAIN_MENU_RENDER ~= nil then
        -- Procesarea din meniul principal este necesară pentru matchmaking și MATCH_START.
        mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function() updateLiveIPC(false) end)
        if characterAvailability ~= nil and characterAvailability.ReportIfChanged ~= nil then
            -- Trimite din meniu lista actualizată de personaje deblocate.
            mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function()
                pcall(characterAvailability.ReportIfChanged, liveIPC)
            end)
        end
        if destinationAvailability ~= nil and destinationAvailability.ReportIfChanged ~= nil then
            mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function()
                pcall(destinationAvailability.ReportIfChanged, liveIPC)
            end)
        end
        end
        if ModCallbacks.MC_PRE_MOD_UNLOAD ~= nil then
            -- CURĂȚARE ANTI-CHEAT/IPC: dezactivează modul competitiv nativ și închide
            -- conexiunea locală atunci când mod-ul este oprit.
            mod:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function()
                if competitiveRun ~= nil and competitiveRun.Deactivate ~= nil then pcall(competitiveRun.Deactivate, "MOD_UNLOAD") end
                pcall(liveIPC.Shutdown)
            end)
        end
    end
else
    Isaac.DebugString("[Isaac1v1] IPC module unavailable")
end


if liveIPC ~= nil and liveIPC.SetTerminalResetHandler ~= nil then
    -- După expirarea ferestrei RESULT, elimină toate datele volatile ale
    -- meciului terminat. Nu modifică nicio stare globală vanilla.
    pcall(liveIPC.SetTerminalResetHandler, function(matchId)
        if matchSession ~= nil and matchSession.Clear ~= nil then pcall(matchSession.Clear) end
        if competitiveRun ~= nil and competitiveRun.Deactivate ~= nil then
            pcall(competitiveRun.Deactivate, "TERMINAL_CLEANUP")
        end
        if lifecycle ~= nil and lifecycle.ResetTerminal ~= nil then pcall(lifecycle.ResetTerminal, matchId) end
        if runLauncher ~= nil and runLauncher.ResetTerminal ~= nil then pcall(runLauncher.ResetTerminal, matchId) end
        if matchResult ~= nil and matchResult.ResetTerminal ~= nil then pcall(matchResult.ResetTerminal, matchId) end
        if menuPrototype ~= nil and menuPrototype.ResetTerminal ~= nil then pcall(menuPrototype.ResetTerminal, matchId) end
        if routeAccessSetup ~= nil and routeAccessSetup.ResetMatch ~= nil then pcall(routeAccessSetup.ResetMatch) end
    end)
end

if targetHud ~= nil and targetHud.Register ~= nil then
    pcall(targetHud.Register, mod, matchSession, competitiveRun)
end

if routeAccessSetup ~= nil and routeAccessSetup.Register ~= nil then
    local ok, registered = pcall(routeAccessSetup.Register, mod, matchSession, competitiveRun)
    if not ok or registered ~= true then
        Isaac.DebugString("[Isaac1v1] ERROR: starting resources unavailable")
    end
else
    Isaac.DebugString("[Isaac1v1] ERROR: starting resources module unavailable")
end

if matchResult ~= nil and matchResult.Register ~= nil then
    -- RESULT: așteaptă rezultatul final valid și face tranziția sigură către meniu.
    local ok, err = pcall(matchResult.Register, mod, liveIPC, matchSession, menuPrototype, competitiveRun)
    if not ok then Isaac.DebugString("[Isaac1v1] ERROR: result screen unavailable: " .. tostring(err)) end
end

if menuPrototype ~= nil and menuPrototype.Register ~= nil then
    -- HUD/UI: instalează meniul F8 pentru matchmaking și afișarea rezultatului.
    local ok, err = pcall(menuPrototype.Register, mod, localBridge, liveIPC, modCompatibility, runLauncher)
    if not ok then
        Isaac.DebugString("Isaac 1v1 ERROR: failed to initialize in-game menu prototype: " .. tostring(err))
    end
else
    Isaac.DebugString("Isaac 1v1 ERROR: in-game menu prototype is unavailable")
end

if competitiveConsoleGuard ~= nil and competitiveConsoleGuard.Register ~= nil then
    -- ANTI-CHEAT: protecție la nivel de input pentru consolă; codul nativ are decizia finală.
    local ok, registered = pcall(competitiveConsoleGuard.Register, mod, competitiveRun)
    if not ok or registered ~= true then
        Isaac.DebugString("[Isaac1v1] ERROR: competitive console guard unavailable")
    end
else
    Isaac.DebugString("[Isaac1v1] ERROR: competitive console guard module unavailable")
end
