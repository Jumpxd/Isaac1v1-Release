-- Punctul de pornire al modului Isaac 1v1. Încarcă toate modulele folosite în joc,
-- le conectează între ele și înregistrează callback-urile Isaac/REPENTOGON.
Isaac.DebugString("[Isaac1v1P2P] MAIN LUA EXECUTED")

local mod = RegisterMod("Isaac 1v1 P2P", 1)

Isaac.DebugString("[Isaac1v1P2P] loaded")

if REPENTOGON ~= nil then
    local version = REPENTOGON.Version or "unknown"
    Isaac.DebugString("[Isaac1v1P2P] REPENTOGON detected (version " .. tostring(version) .. ")")
else
    Isaac.DebugString("[Isaac1v1P2P] REPENTOGON not detected")
end

local function loadScript(path)
    -- Încarcă fiecare modul în siguranță. Dacă lipsește un script, logul Isaac
    -- arată exact ce parte a inițializării a eșuat.
    local ok, result = pcall(include, path)
    if not ok then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: failed to load " .. path .. ": " .. tostring(result))
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
local transport = loadScript("scripts/p2p_transport.lua")
local runLauncher = loadScript("scripts/run_launcher.lua")
local matchValidation = loadScript("scripts/match_validation.lua")
local menu = loadScript("scripts/menu.lua")
local matchResult = loadScript("scripts/match_result.lua")
local characterAvailability = loadScript("scripts/character_availability.lua")
local destinationAvailability = loadScript("scripts/destination_availability.lua")
local targetHud = loadScript("scripts/target_hud.lua")
local routeAccessSetup = loadScript("scripts/route_access.lua")
local competitiveRun = loadScript("scripts/competitive_run.lua")
local competitiveConsoleGuard = loadScript("scripts/competitive_console_guard.lua")
local modCompatibility = loadScript("scripts/mod_compatibility.lua")

if modCompatibility ~= nil and transport ~= nil then
    -- ALLOWLIST: transportul oferă lista modurilor active, iar Lua trimite
    -- lista oficială de moduri permise folosită la verificare.
    if modCompatibility.SetActiveModProvider ~= nil and transport.GetActiveMods ~= nil then
        pcall(modCompatibility.SetActiveModProvider, transport.GetActiveMods)
    end
    if modCompatibility.GetAllowedModMetadata ~= nil and transport.SetCompetitiveModAllowlist ~= nil then
        local metadataOk, metadata = pcall(modCompatibility.GetAllowedModMetadata)
        if metadataOk then pcall(transport.SetCompetitiveModAllowlist, metadata) end
    end
end

if matchBridge ~= nil and matchBridge.Load ~= nil and matchSession ~= nil then
    -- Curăță din SaveData datele vechi despre sesiune și pornire. O sesiune
    -- competitivă nouă poate începe doar după un mesaj valid MATCH_START.
    local ok, err = pcall(matchBridge.Load, mod, matchSession)
    if not ok then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: failed to initialize match bridge: " .. tostring(err))
    end
else
    Isaac.DebugString("[Isaac1v1P2P] ERROR: match bridge is unavailable")
end

if localBridge ~= nil and localBridge.Initialize ~= nil then
    local ok, err = pcall(localBridge.Initialize, mod, matchSession)
    if not ok then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: failed to initialize local bridge: " .. tostring(err))
    end
else
    Isaac.DebugString("[Isaac1v1P2P] ERROR: local bridge is unavailable")
end

if gameState ~= nil and lifecycle ~= nil and lifecycle.Register ~= nil then
    -- CICLUL MECIULUI: instalează callback-urile pentru start, etaj, moarte/revive,
    -- terminarea run-ului și ieșirea din joc.
    local ok, err = pcall(lifecycle.Register, mod, gameState, matchValidation, matchSession, transport, competitiveRun, matchBridge, matchResult)
    if not ok then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: failed to initialize lifecycle: " .. tostring(err))
    end
else
    Isaac.DebugString("[Isaac1v1P2P] ERROR: lifecycle is unavailable")
end

if runLauncher ~= nil and runLauncher.Register ~= nil and matchSession ~= nil then
    -- PORNIRE: preia un MATCH_START valid cât timp meniul este activ, pornește
    -- run-ul controlat și confirmă pornirea după ce Isaac a intrat în run.
    local ok, err = pcall(runLauncher.Register, mod, matchSession, gameState, matchValidation, matchBridge, transport, competitiveRun, modCompatibility)
    if not ok then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: failed to initialize run launcher: " .. tostring(err))
    end
else
    Isaac.DebugString("[Isaac1v1P2P] ERROR: run launcher is unavailable")
end

if matchSession == nil or matchValidation == nil or matchBridge == nil then
    Isaac.DebugString("[Isaac1v1P2P] ERROR: match validation is unavailable")
end

if transport ~= nil and transport.SetMatchResetHandler ~= nil then
    -- La fiecare ID nou de meci, resetează împreună toate modulele care păstrează
    -- date despre meci. Astfel, un RESULT vechi nu ajunge în meciul următor.
    pcall(transport.SetMatchResetHandler, function(previousMatchId, newMatchId, session)
        if matchSession ~= nil and matchSession.Clear ~= nil then pcall(matchSession.Clear) end
        if competitiveRun ~= nil and competitiveRun.BeginNewMatch ~= nil then
            pcall(competitiveRun.BeginNewMatch, session, previousMatchId)
        end
        if lifecycle ~= nil and lifecycle.BeginNewMatch ~= nil then pcall(lifecycle.BeginNewMatch, newMatchId) end
        if runLauncher ~= nil and runLauncher.BeginNewMatch ~= nil then pcall(runLauncher.BeginNewMatch, newMatchId) end
        if matchResult ~= nil and matchResult.BeginNewMatch ~= nil then pcall(matchResult.BeginNewMatch, newMatchId) end
        if menu ~= nil and menu.BeginNewMatch ~= nil then pcall(menu.BeginNewMatch, newMatchId) end
        if routeAccessSetup ~= nil and routeAccessSetup.BeginNewMatch ~= nil then
            pcall(routeAccessSetup.BeginNewMatch, newMatchId)
        end
    end)
end


if transport ~= nil and transport.Initialize ~= nil then
    local ok, available = pcall(transport.Initialize)
    if not ok or available ~= true then
        Isaac.DebugString("[Isaac1v1P2P] P2P transport initialization failed")
    else
        local function updateTransport(submitScore)
            -- Procesează transportul P2P în meniu, la randare și în timpul jocului.
            -- Doar callback-ul de update cere trimiterea scorului live, cu limitare în transport.
            local updateOk, updateError = pcall(transport.Update)
            if not updateOk then
                Isaac.DebugString("[Isaac1v1P2P] P2P transport update error: " .. tostring(updateError))
            end
            if submitScore == true and competitiveRun ~= nil and competitiveRun.IsActiveFor ~= nil
                and competitiveRun.IsActiveFor(matchSession ~= nil and matchSession.Get() or nil)
                and gameState ~= nil and transport.MaybeSubmitScore ~= nil
                and gameState.isRunActive ~= nil and gameState.isRunActive() then
                local score = gameState.getVanillaScore ~= nil and gameState.getVanillaScore() or nil
                pcall(transport.MaybeSubmitScore, score, gameState.getRunTime ~= nil and gameState.getRunTime() or nil)
            end
        end
        mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function() updateTransport(true) end)
        if ModCallbacks.MC_POST_RENDER ~= nil then
            -- Randarea continuă și când update-urile de gameplay sunt limitate,
            -- deci poate procesa în continuare mesajele RESULT și de conexiune.
            mod:AddCallback(ModCallbacks.MC_POST_RENDER, function() updateTransport(false) end)
        end
        if ModCallbacks.MC_MAIN_MENU_RENDER ~= nil then
        -- Procesarea din meniul principal este necesară pentru matchmaking și MATCH_START.
        mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function() updateTransport(false) end)
        if characterAvailability ~= nil and characterAvailability.ReportIfChanged ~= nil then
            -- Trimite din meniu lista actualizată de personaje deblocate.
            mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function()
                pcall(characterAvailability.ReportIfChanged, transport)
            end)
        end
        if destinationAvailability ~= nil and destinationAvailability.ReportIfChanged ~= nil then
            mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function()
                pcall(destinationAvailability.ReportIfChanged, transport)
            end)
        end
        end
        if ModCallbacks.MC_PRE_MOD_UNLOAD ~= nil then
            -- CURĂȚARE: dezactivează modul competitiv nativ și închide
            -- transportul atunci când mod-ul este oprit.
            mod:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function()
                if competitiveRun ~= nil and competitiveRun.Deactivate ~= nil then pcall(competitiveRun.Deactivate, "MOD_UNLOAD") end
                pcall(transport.Shutdown)
            end)
        end
    end
else
    Isaac.DebugString("[Isaac1v1P2P] P2P transport unavailable")
end


if transport ~= nil and transport.SetTerminalResetHandler ~= nil then
    -- După expirarea ferestrei RESULT, elimină toate datele volatile ale
    -- meciului terminat. Nu modifică nicio stare globală vanilla.
    pcall(transport.SetTerminalResetHandler, function(matchId)
        if matchSession ~= nil and matchSession.Clear ~= nil then pcall(matchSession.Clear) end
        if competitiveRun ~= nil and competitiveRun.Deactivate ~= nil then
            pcall(competitiveRun.Deactivate, "TERMINAL_CLEANUP")
        end
        if lifecycle ~= nil and lifecycle.ResetTerminal ~= nil then pcall(lifecycle.ResetTerminal, matchId) end
        if runLauncher ~= nil and runLauncher.ResetTerminal ~= nil then pcall(runLauncher.ResetTerminal, matchId) end
        if matchResult ~= nil and matchResult.ResetTerminal ~= nil then pcall(matchResult.ResetTerminal, matchId) end
        if menu ~= nil and menu.ResetTerminal ~= nil then pcall(menu.ResetTerminal, matchId) end
        if routeAccessSetup ~= nil and routeAccessSetup.ResetMatch ~= nil then pcall(routeAccessSetup.ResetMatch) end
    end)
end

if targetHud ~= nil and targetHud.Register ~= nil then
    pcall(targetHud.Register, mod, matchSession, competitiveRun)
end

if routeAccessSetup ~= nil and routeAccessSetup.Register ~= nil then
    local ok, registered = pcall(routeAccessSetup.Register, mod, matchSession, competitiveRun)
    if not ok or registered ~= true then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: starting resources unavailable")
    end
else
    Isaac.DebugString("[Isaac1v1P2P] ERROR: starting resources module unavailable")
end

if matchResult ~= nil and matchResult.Register ~= nil then
    -- RESULT: așteaptă rezultatul final valid și face tranziția sigură către meniu.
    local ok, err = pcall(matchResult.Register, mod, transport, matchSession, menu, competitiveRun)
    if not ok then Isaac.DebugString("[Isaac1v1P2P] ERROR: result screen unavailable: " .. tostring(err)) end
end

if menu ~= nil and menu.Register ~= nil then
    -- HUD/UI: instalează meniul F8 pentru matchmaking și afișarea rezultatului.
    local ok, err = pcall(menu.Register, mod, localBridge, transport, modCompatibility, runLauncher)
    if not ok then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: failed to initialize in-game menu: " .. tostring(err))
    end
else
    Isaac.DebugString("[Isaac1v1P2P] ERROR: in-game menu is unavailable")
end

if competitiveConsoleGuard ~= nil and competitiveConsoleGuard.Register ~= nil then
    -- ANTI-CHEAT: protecție la nivel de input pentru consolă; codul nativ are decizia finală.
    local ok, registered = pcall(competitiveConsoleGuard.Register, mod, competitiveRun)
    if not ok or registered ~= true then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: competitive console guard unavailable")
    end
else
    Isaac.DebugString("[Isaac1v1P2P] ERROR: competitive console guard module unavailable")
end
