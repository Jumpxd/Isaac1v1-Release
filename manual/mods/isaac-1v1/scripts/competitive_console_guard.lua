-- Protecție ANTI-CHEAT suplimentară pentru deschiderea consolei în timpul unui
-- run competitiv. Verificarea nativă Console::SubmitInput are decizia finală.
local consoleGuard = {}

local LOG_INTERVAL_MS = 1000
local lastBlockedAt = -LOG_INTERVAL_MS

local function nowMs()
    if Isaac ~= nil and type(Isaac.GetTime) == "function" then
        return Isaac.GetTime()
    end
    return math.floor(os.clock() * 1000)
end

local function active(competitiveRun)
    return competitiveRun ~= nil
        and type(competitiveRun.IsActive) == "function"
        and competitiveRun.IsActive() == true
end

local function logBlocked()
    local current = nowMs()
    if current - lastBlockedAt < LOG_INTERVAL_MS then return end
    lastBlockedAt = current
    Isaac.DebugString('[Isaac1v1] COMPETITIVE_CONSOLE_BLOCKED command="<toggle>"')
end

local function nativeDevConsoleUnlocked()
    -- API-ul există exclusiv într-un DLL compilat DEV; Production nu poate
    -- activa bypass-ul printr-un mesaj IPC sau printr-un apel Lua manual.
    if type(Isaac1v1IPC) ~= "table" or type(Isaac1v1IPC.IsDevConsoleUnlocked) ~= "function" then
        return false
    end
    local ok, unlocked = pcall(Isaac1v1IPC.IsDevConsoleUnlocked)
    return ok and unlocked == true
end

function consoleGuard.ShouldAllowAction(competitiveRun, action)
    -- Este apelată de MC_INPUT_ACTION. Întoarce false doar pentru ACTION_CONSOLE în STARTED.
    if not active(competitiveRun) then return true end
    if ButtonAction == nil or action ~= ButtonAction.ACTION_CONSOLE then return true end
    if nativeDevConsoleUnlocked() then return true end
    logBlocked()
    return false
end

function consoleGuard.Register(mod, competitiveRun)
    -- Instalează callback-ul de input dacă REPENTOGON oferă API-ul necesar.
    if ModCallbacks == nil or ModCallbacks.MC_INPUT_ACTION == nil
        or ButtonAction == nil or ButtonAction.ACTION_CONSOLE == nil then
        Isaac.DebugString('[Isaac1v1] COMPETITIVE_CONSOLE_GUARD_UNAVAILABLE reason="INPUT_API_MISSING"')
        return false
    end
    -- Aceasta este doar o protecție suplimentară: consola ImGui REPENTOGON poate
    -- ocoli callback-ul. Extensia IPC nativă blochează comanda jucătorului direct
    -- în Console::SubmitInput cât timp modul competitiv este activ.
    mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, inputHook, action)
        if consoleGuard.ShouldAllowAction(competitiveRun, action) then return nil end
        return false
    end)
    Isaac.DebugString('[Isaac1v1] COMPETITIVE_CONSOLE_GUARD_READY api="MC_INPUT_ACTION/ACTION_CONSOLE"')
    return true
end

return consoleGuard
