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

function consoleGuard.ShouldAllowAction(competitiveRun, action)
    if not active(competitiveRun) then return true end
    if ButtonAction == nil or action ~= ButtonAction.ACTION_CONSOLE then return true end
    logBlocked()
    return false
end

function consoleGuard.Register(mod, competitiveRun)
    if ModCallbacks == nil or ModCallbacks.MC_INPUT_ACTION == nil
        or ButtonAction == nil or ButtonAction.ACTION_CONSOLE == nil then
        Isaac.DebugString('[Isaac1v1] COMPETITIVE_CONSOLE_GUARD_UNAVAILABLE reason="INPUT_API_MISSING"')
        return false
    end
    -- Defense in depth only: REPENTOGON's ImGui console can bypass this action
    -- callback. The native IPC extension authoritatively rejects the player
    -- submission at Console::SubmitInput while competitive mode is active.
    mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, inputHook, action)
        if consoleGuard.ShouldAllowAction(competitiveRun, action) then return nil end
        return false
    end)
    Isaac.DebugString('[Isaac1v1] COMPETITIVE_CONSOLE_GUARD_READY api="MC_INPUT_ACTION/ACTION_CONSOLE"')
    return true
end

return consoleGuard
