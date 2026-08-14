local MatchBridge = {}

local status = "NO DATA"
local lastError = nil
local sessionModule = nil
local modInstance = nil
local launchRequest = nil
local rootPayload = nil
local jsonModule = nil

local DEVELOPMENT_PAYLOAD = [[
{"bridgeVersion":1,"matchSession":{"matchId":"local-save-001","playerId":"local-player","characterType":0,"characterName":"Isaac","seed":null,"difficulty":"HARD","gameMode":"STANDARD","source":"SAVE_DATA","active":true}}
]]

local function quote(value)
    return '"' .. tostring(value):gsub('"', "'") .. '"'
end

local function bridgeError(reason)
    status = "ERROR"
    lastError = reason
    Isaac.DebugString("[Isaac1v1] MATCH_BRIDGE_ERROR reason=" .. quote(reason))
    return nil
end

local function validatePayload(payload)
    if type(payload) ~= "table" then return false end
    if type(payload.matchId) ~= "string" then return false end
    if type(payload.playerId) ~= "string" then return false end
    if type(payload.characterType) ~= "number" then return false end
    if type(payload.characterName) ~= "string" then return false end
    if payload.seed ~= nil and type(payload.seed) ~= "string" then return false end
    if type(payload.difficulty) ~= "string" then return false end
    if type(payload.gameMode) ~= "string" then return false end
    if type(payload.active) ~= "boolean" then return false end

    payload.difficulty = string.upper(payload.difficulty)
    payload.gameMode = string.upper(payload.gameMode)
    if type(payload.source) ~= "string" or payload.source == "" then
        payload.source = "SAVE_DATA"
    end
    return true
end

local function validateLaunchRequest(request)
    if request == nil then return true end
    if type(request) ~= "table" then return false end
    if type(request.requested) ~= "boolean" then return false end
    if type(request.matchId) ~= "string" or request.matchId == "" then return false end
    if type(request.token) ~= "string" or request.token == "" then return false end
    return true
end

local function startupStatus(session)
    if type(session) == "table" and type(session.status) == "string" then
        return session.status
    end
    return "PERSISTED"
end

-- SaveData belongs to the previous Isaac process.  It may contain a legacy
-- pre-launch handoff, but it is never evidence that the current process has
-- received a live MATCH_START.
local function clearStartupPendingState(root)
    local savedSession = root.matchSession
    Isaac.DebugString(
        "[Isaac1v1] STARTUP_PENDING_MATCH " ..
        "match_id=" .. quote(type(savedSession) == "table" and savedSession.matchId or "<none>") .. " " ..
        "status=" .. quote(startupStatus(savedSession)) .. " " ..
        "generation=" .. quote(type(savedSession) == "table" and savedSession.startGeneration or "<none>") .. " " ..
        "source=" .. quote(type(savedSession) == "table" and savedSession.source or "SAVE_DATA")
    )

    -- Keep the document structurally valid for the legacy local bridge, but
    -- remove every pre-game session/one-shot field from the old process.
    root.matchSession = {
        matchId = "startup-cleared",
        playerId = "startup-cleared",
        characterType = 0,
        characterName = "Isaac",
        seed = nil,
        difficulty = "HARD",
        gameMode = "STANDARD",
        source = "STARTUP_CLEAR",
        active = false,
    }
    root.launchRequest = {
        requested = false,
        matchId = "startup-cleared",
        token = "startup-cleared",
    }
end

local function loadJson()
    local ok, json = pcall(require, "json")
    if not ok or json == nil or json.decode == nil then
        return nil, "JSON_UNAVAILABLE"
    end
    return json
end

function MatchBridge.Load(mod, matchSession)
    if mod ~= nil then modInstance = mod end
    if matchSession ~= nil then sessionModule = matchSession end
    if mod == nil or mod.HasData == nil or mod.LoadData == nil then
        return bridgeError("MOD_DATA_API_UNAVAILABLE")
    end
    launchRequest = nil
    rootPayload = nil
    jsonModule = nil

    local hasOk, hasData = pcall(mod.HasData, mod)
    if not hasOk or not hasData then
        status = "NO DATA"
        lastError = "NO_DATA"
        Isaac.DebugString('[Isaac1v1] STARTUP_PENDING_MATCH match_id="<none>" status="NO_DATA" generation="<none>" source="SAVE_DATA"')
        Isaac.DebugString("[Isaac1v1] MATCH_BRIDGE_ERROR reason=\"NO_DATA\"")
        if sessionModule ~= nil and sessionModule.Clear ~= nil then sessionModule.Clear() end
        return nil
    end

    local loadOk, rawData = pcall(mod.LoadData, mod)
    if not loadOk or rawData == nil or rawData == "" then
        status = "NO DATA"
        lastError = "NO_DATA"
        Isaac.DebugString('[Isaac1v1] STARTUP_PENDING_MATCH match_id="<none>" status="NO_DATA" generation="<none>" source="SAVE_DATA"')
        Isaac.DebugString("[Isaac1v1] MATCH_BRIDGE_ERROR reason=\"NO_DATA\"")
        if sessionModule ~= nil and sessionModule.Clear ~= nil then sessionModule.Clear() end
        return nil
    end

    local json, jsonError = loadJson()
    if json == nil then return bridgeError(jsonError) end
    jsonModule = json

    local decodeOk, root = pcall(json.decode, rawData)
    if not decodeOk or type(root) ~= "table" then
        return bridgeError("INVALID_JSON")
    end
    if sessionModule == nil or sessionModule.Set == nil then
        return bridgeError("SESSION_UNAVAILABLE")
    end

    -- A previous version stored abandoned-match metadata here. It must never
    -- create a session or influence vanilla Continue in this process.
    root.competitiveAbandonment = nil
    root["recon" .. "nectPending"] = nil
    -- Clear before validating legacy fields: malformed old handoff data must
    -- not survive merely because it cannot be parsed as a launch request.
    clearStartupPendingState(root)
    local encodeOk, encoded = pcall(json.encode, root)
    if not encodeOk or encoded == nil then return bridgeError("STARTUP_CLEAR_ENCODE_ERROR") end
    local saveOk, saveError = pcall(mod.SaveData, mod, encoded)
    if not saveOk then return bridgeError("STARTUP_CLEAR_SAVE_ERROR: " .. tostring(saveError)) end

    -- Never populate MatchSession or launchRequest from SaveData.  A session
    -- becomes active only when live_ipc.lua receives MATCH_START this process.
    if sessionModule.Clear ~= nil then sessionModule.Clear() end
    rootPayload = root
    launchRequest = nil
    status = "STARTUP_CLEARED"
    lastError = nil
    return root.matchSession
end

local function saveRoot()
    if modInstance == nil or modInstance.SaveData == nil then return false end
    if jsonModule == nil then
        local json = loadJson()
        jsonModule = json
    end
    if jsonModule == nil or jsonModule.encode == nil then return false end
    if rootPayload == nil then rootPayload = {bridgeVersion = 1} end
    local encodeOk, encoded = pcall(jsonModule.encode, rootPayload)
    return encodeOk and encoded ~= nil and pcall(modInstance.SaveData, modInstance, encoded)
end

function MatchBridge.GetLaunchRequest()
    return launchRequest
end

function MatchBridge.ConsumeLaunchRequest(matchId)
    if launchRequest == nil or launchRequest.requested ~= true
        or launchRequest.matchId ~= matchId then
        return false
    end
    if modInstance == nil or modInstance.SaveData == nil
        or rootPayload == nil or jsonModule == nil or jsonModule.encode == nil then
        return false
    end

    local consumed = {
        requested = false,
        matchId = launchRequest.matchId,
        token = launchRequest.token,
    }
    rootPayload.launchRequest = consumed
    local encodeOk, encoded = pcall(jsonModule.encode, rootPayload)
    if not encodeOk or encoded == nil then return false end
    local saveOk = pcall(modInstance.SaveData, modInstance, encoded)
    if not saveOk then return false end
    launchRequest = consumed
    return true
end

function MatchBridge.Reload()
    return MatchBridge.Load(modInstance)
end

-- Development-only manual writer. This is never called automatically.
function MatchBridge.WriteDevelopmentPayload(mod)
    if mod == nil or mod.SaveData == nil then
        return bridgeError("MOD_DATA_API_UNAVAILABLE")
    end
    local ok, err = pcall(mod.SaveData, mod, DEVELOPMENT_PAYLOAD)
    if not ok then return bridgeError("SAVE_DATA_ERROR: " .. tostring(err)) end
    Isaac.DebugString("[Isaac1v1] MATCH_BRIDGE_DEV_DATA_WRITTEN")
    return true
end

function MatchBridge.GetStatus() return status end
function MatchBridge.GetLastError() return lastError end

return MatchBridge
