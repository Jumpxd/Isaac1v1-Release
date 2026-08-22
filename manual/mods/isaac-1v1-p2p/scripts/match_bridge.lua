-- Production run_launcher keeps this bridge parameter for local SaveData launches.
-- P2P starts are memory-only and arrive through p2p_transport.GetStartRequest().
local bridge = {}
function bridge.Load(_, matchSession)
    if matchSession ~= nil and type(matchSession.Clear) == "function" then matchSession.Clear() end
    return true
end
function bridge.GetLaunchRequest() return nil end
function bridge.ConsumeLaunchRequest() return false end
return bridge
