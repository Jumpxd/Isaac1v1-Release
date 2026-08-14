local liveIPC = {}

local PROTOCOL_VERSION = 1
local RETRY_SECONDS = 2
local STALE_SECONDS = 6

local nativeAPI = nil
local jsonModule = nil
local componentInstalled = false
local phase = "DISCONNECTED"
local nextRetryAt = 0
local lastMessageAt = 0
local pingCounter = 0
local pendingPingId = nil
local availableCharacterTypes = nil
local activeMods = nil
local competitiveModAllowlistIds = {}
local competitiveModAllowlist = {}
local nextActiveModScanAt = 0
local backendConnected = false
local playerState = nil
local queueState = "IDLE"
local findMatchInFlight = false
local leaveQueueInFlight = false
local matchState = nil
local matchControl = nil
local startRequest = nil
local cancelledMatchIds = {}
local lastStartKey = nil
local processStartNonce = tostring(math.floor(os.clock() * 1000)) .. "-" .. tostring(math.random(1, 2147483646))
local onlineError = nil
local lastUpdateAt = -1
local nextScoreAt = 0
local scoreSequence = 0
local lastScore = nil
local pendingTerminal = nil
local finalizedMatchId = nil
local competitiveResultTransition = false
local leaveRequestedAt = nil
local nextSteamIdentityPollAt = 0
local lastSteamIdentityKey = nil
local steamIdentityReady = false
local steamIdentityAvailableLogged = false
local lastSteamIdentityMissingReason = nil
local lifecycleMatchId = nil
local matchResetHandler = nil

local function now()
    if Isaac ~= nil and type(Isaac.GetTime) == "function" then
        return Isaac.GetTime() / 1000
    end
    return os.clock()
end

local function log(message)
    Isaac.DebugString("[Isaac1v1] " .. message)
end

-- Session diagnostics must never depend on a global formatter or throw while
-- reporting malformed input.
local function quote(value)
    return "\"" .. tostring(value == nil and "<nil>" or value):gsub("\"", "'") .. "\""
end

local function beginNewMatch(payload)
    if type(payload) ~= "table" or type(payload.matchId) ~= "string" or payload.matchId == "" then return false end
    if lifecycleMatchId == payload.matchId then return true end
    local previousMatchId = lifecycleMatchId or finalizedMatchId
    if previousMatchId == nil and type(matchState) == "table" and matchState.matchId ~= payload.matchId then
        previousMatchId = matchState.matchId
    end
    pendingTerminal = nil
    finalizedMatchId = nil
    competitiveResultTransition = false
    scoreSequence = 0
    lastScore = nil
    nextScoreAt = 0
    leaveRequestedAt = nil
    lastStartKey = nil
    lifecycleMatchId = payload.matchId
    if type(matchResetHandler) == "function" then
        local ok, resetError = pcall(matchResetHandler, previousMatchId, payload.matchId, payload)
        if not ok then
            log("COMPETITIVE_MATCH_RESET_FAILED match_id=" .. quote(payload.matchId)
                .. " reason=" .. quote(resetError))
            return false
        end
    end
    return true
end

local function disconnect(reason)
    if nativeAPI ~= nil then pcall(nativeAPI.Disconnect) end
    local wasConnected = phase == "CONNECTED"
    phase = "DISCONNECTED"
    pendingPingId = nil
    backendConnected = false
    lastSteamIdentityKey = nil
    nextRetryAt = now() + RETRY_SECONDS
    if wasConnected then
        log("IPC_DISCONNECTED reason=\"" .. tostring(reason or "closed") .. "\"")
    end
end

local function sendEnvelope(messageType, payload)
    if phase ~= "CONNECTED" or nativeAPI == nil or jsonModule == nil then
        return false, "COMPANION_NOT_RUNNING"
    end
    local encoded = jsonModule.encode({
        protocolVersion = PROTOCOL_VERSION,
        type = messageType,
        payload = payload or {}
    })
    local sent, errorMessage = nativeAPI.Send(encoded)
    if not sent then
        disconnect(errorMessage or "SEND_FAILED")
        return false, errorMessage or "SEND_FAILED"
    end
    return true, nil
end

local function sendPing()
    pingCounter = pingCounter + 1
    pendingPingId = "isaac-" .. tostring(pingCounter) .. "-" .. tostring(math.floor(now() * 1000))
    local encoded = jsonModule.encode({
        protocolVersion = PROTOCOL_VERSION,
        type = "PING",
        requestId = pendingPingId,
        payload = {}
    })
    local sent, errorMessage = nativeAPI.Send(encoded)
    if sent then
        log("IPC_PING_SENT id=\"" .. pendingPingId .. "\"")
    else
        disconnect(errorMessage or "SEND_FAILED")
    end
end

local function logSteamIdentityMissing(reason)
    reason = tostring(reason or "IDENTITY_NOT_RECEIVED")
    if reason ~= lastSteamIdentityMissingReason then
        lastSteamIdentityMissingReason = reason
        log("STEAM_IDENTITY_NOT_FOUND reason=" .. quote(reason))
    end
end

local function refreshSteamIdentity()
    if type(nativeAPI.GetSteamIdentity) ~= "function" then
        steamIdentityReady = false
        logSteamIdentityMissing("STEAM_API_UNAVAILABLE")
        return
    end
    local identity, identityError = nativeAPI.GetSteamIdentity()
    if type(identity) ~= "table" or type(identity.steamId64) ~= "string"
        or type(identity.personaName) ~= "string" or identity.personaName == "" then
        steamIdentityReady = false
        logSteamIdentityMissing(identityError or "IDENTITY_NOT_RECEIVED")
        return
    end
    if #identity.steamId64 ~= 17 or not identity.steamId64:match("^7656119%d%d%d%d%d%d%d%d%d%d$") then
        steamIdentityReady = false
        logSteamIdentityMissing("INVALID_STEAM_ID")
        return
    end
    steamIdentityReady = true
    lastSteamIdentityMissingReason = nil
    local avatar = type(identity.avatarPath) == "string" and identity.avatarPath or nil
    local key = identity.steamId64 .. "\n" .. identity.personaName .. "\n" .. tostring(avatar or "")
    if key == lastSteamIdentityKey then return end
    local sent = sendEnvelope("STEAM_IDENTITY", {steamId64 = identity.steamId64, personaName = identity.personaName, avatar = avatar})
    if sent then
        lastSteamIdentityKey = key
        if not steamIdentityAvailableLogged then
            steamIdentityAvailableLogged = true
            log("STEAM_IDENTITY_AVAILABLE steam_id=" .. quote(identity.steamId64) .. " persona=" .. quote(identity.personaName))
        end
    end
end

local function markConnected()
    if phase == "CONNECTED" then return end
    phase = "CONNECTED"
    lastMessageAt = now()
    log("IPC_CONNECTED transport=\"NATIVE_TCP_LOOPBACK\"")
    sendPing()
    nextSteamIdentityPollAt = now() + 2
    refreshSteamIdentity()
    sendEnvelope("GET_PLAYER_STATE", {})
    sendEnvelope("GET_ACTIVE_MODS", {allowlistIds = competitiveModAllowlistIds, allowlist = competitiveModAllowlist})
    nextActiveModScanAt = now() + 2
    if availableCharacterTypes ~= nil then
        sendEnvelope("PLAYER_AVAILABILITY", {availableCharacterTypes = availableCharacterTypes})
    end
    if pendingTerminal ~= nil then
        sendEnvelope("MATCH_SCORE_UPDATE", pendingTerminal.scorePayload)
        sendEnvelope("MATCH_TERMINAL_EVENT", pendingTerminal.terminalPayload)
    end
end

local function validMatch(payload)
    return type(payload.matchId) == "string"
        and type(payload.playerId) == "string"
        and type(payload.opponentId) == "string"
        and type(payload.characterType) == "number"
        and type(payload.characterName) == "string"
        and type(payload.seed) == "string"
        and payload.difficulty == "HARD"
        and payload.gameMode == "STANDARD"
end

local function sessionPayloadLog(payload)
    local fields = {"matchId", "playerId", "opponentId", "characterType", "characterName", "seed", "difficulty", "gameMode", "startGeneration", "startToken"}
    local parts = {}
    for _, field in ipairs(fields) do
        local value = payload ~= nil and payload[field] or nil
        parts[#parts + 1] = field .. "=" .. quote(value == nil and "<nil>" or value)
            .. " type=" .. quote(type(value))
    end
    log("MATCH_SESSION_PAYLOAD " .. table.concat(parts, " "))
end

local function sessionValidationReason(payload)
    if type(payload) ~= "table" then return "MISSING_FIELD" end
    if type(payload.matchId) ~= "string" or payload.matchId == "" then return "INVALID_MATCH_ID" end
    if type(payload.playerId) ~= "string" or payload.playerId == "" then return "INVALID_PLAYER_ID" end
    if type(payload.opponentId) ~= "string" or payload.opponentId == "" then return "INVALID_OPPONENT_ID" end
    if type(payload.characterType) ~= "number" then return "INVALID_CHARACTER" end
    if type(payload.characterName) ~= "string" or payload.characterName == "" then return "INVALID_CHARACTER" end
    if type(payload.seed) ~= "string" or not payload.seed:match("^[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9] [A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]$") then return "INVALID_SEED" end
    if payload.difficulty ~= "HARD" then return "INVALID_DIFFICULTY" end
    if payload.gameMode ~= "STANDARD" then return "INVALID_MODE" end
    if type(payload.startGeneration) ~= "number" then return "INVALID_GENERATION" end
    if type(payload.startToken) ~= "string" or payload.startToken == "" then return "INVALID_START_TOKEN" end
    return nil
end

local function handleMessage(encoded)
    local decodedOk, message = pcall(jsonModule.decode, encoded)
    if not decodedOk or type(message) ~= "table" then
        disconnect("INVALID_JSON")
        return false
    end
    if message.protocolVersion ~= PROTOCOL_VERSION then
        disconnect("UNSUPPORTED_PROTOCOL_VERSION")
        return false
    end
    local payload = message.payload
    if type(payload) ~= "table" then
        disconnect("INVALID_PAYLOAD")
        return false
    end
    lastMessageAt = now()
    log("IPC_MESSAGE_RECEIVED type=" .. quote(message.type) .. " process=" .. quote(processStartNonce))

    if message.type == "PONG" then
        if message.requestId ~= pendingPingId or type(payload.message) ~= "string" then
            disconnect("INVALID_PONG")
            return false
        end
        backendConnected = payload.backendConnected == true
        log("IPC_PONG_RECEIVED id=\"" .. message.requestId
            .. "\" message=\"" .. payload.message .. "\"")
        pendingPingId = nil
    elseif message.type == "PLAYER_STATE" then
        if type(payload.playerId) ~= "string" or type(payload.displayName) ~= "string" then
            disconnect("INVALID_PLAYER_STATE")
            return false
        end
        playerState = payload
        log("PLAYER_STATE player_id=\"" .. payload.playerId .. "\"")
    elseif message.type == "ACTIVE_MODS" then
        if type(payload.mods) ~= "table" then
            disconnect("INVALID_ACTIVE_MODS")
            return false
        end
        activeMods = payload.mods
    elseif message.type == "QUEUE_STATE" then
        if payload.status ~= "IDLE" and payload.status ~= "SEARCHING" then
            disconnect("INVALID_QUEUE_STATE")
            return false
        end
        local previous = queueState
        findMatchInFlight = false
        leaveQueueInFlight = false
        queueState = payload.status
        onlineError = nil
        if queueState == "IDLE" then
            if matchState ~= nil and type(matchState.matchId) == "string" then
                cancelledMatchIds[matchState.matchId] = true
            end
            matchState = nil
            matchControl = nil
            startRequest = nil
            if previous == "CANCEL_PENDING" or previous == "SEARCHING" then
                log("QUEUE_CANCELLED")
            end
            if previous == "CANCEL_PENDING" then log("QUEUE_STATE_IDLE_RECEIVED") end
            leaveRequestedAt = nil
        elseif previous ~= "SEARCHING" then
            log("QUEUE_SEARCHING")
        end
    elseif message.type == "MATCH_FOUND" then
        findMatchInFlight = false
        if queueState == "RESULT" then
            log("MATCH_MESSAGE_IGNORED_AFTER_RESULT type=\"MATCH_FOUND\"")
            return true
        end
        if not validMatch(payload) then
            disconnect("INVALID_MATCH_FOUND")
            return false
        end
        if cancelledMatchIds[payload.matchId] then
            log("MATCH_SESSION_IGNORED_AFTER_CANCEL match_id=\"" .. payload.matchId .. "\"")
            return true
        end
        queueState = "MATCH_FOUND"
        matchState = payload
        onlineError = nil
        log("MATCH_FOUND match_id=\"" .. payload.matchId
            .. "\" character_type=\"" .. tostring(payload.characterType)
            .. "\" seed=\"" .. payload.seed .. "\"")
    elseif message.type == "MATCH_STATE" then
        if queueState == "RESULT" then
            log("MATCH_MESSAGE_IGNORED_AFTER_RESULT type=\"MATCH_STATE\"")
            return true
        end
        if not validMatch(payload) or type(payload.status) ~= "string" then
            disconnect("INVALID_MATCH_STATE")
            return false
        end
        if cancelledMatchIds[payload.matchId] then
            log("MATCH_SESSION_IGNORED_AFTER_CANCEL match_id=\"" .. payload.matchId .. "\"")
            return true
        end
        matchState = payload
        matchControl = payload
        if payload.status == "STARTING" then queueState = "STARTING"
        elseif payload.status == "STARTED" then queueState = "STARTED"
        else queueState = "MATCH_FOUND" end
        log("MATCH_STATE match_id=\"" .. payload.matchId .. "\" status=\"" .. payload.status .. "\"")
    elseif message.type == "MATCH_START" then
        sessionPayloadLog(payload)
        local validationReason = sessionValidationReason(payload)
        if validationReason ~= nil then
            onlineError = validationReason
            startRequest = nil
            log("MATCH_SESSION_REJECTED reason=\"" .. validationReason .. "\"")
            return true
        end
        if not beginNewMatch(payload) then
            onlineError = "MATCH_RESET_FAILED"
            startRequest = nil
            return true
        end
        if matchState == nil or payload.matchId ~= matchState.matchId then
            onlineError = "MATCH_START_NOT_ACTIVE"
            startRequest = nil
            log("MATCH_SESSION_REJECTED reason=\"MATCH_START_NOT_ACTIVE\" match_id=" .. quote(payload.matchId))
            return true
        end
        if matchControl == nil or matchControl.status ~= "STARTING" then
            onlineError = "MATCH_START_NOT_STARTING"
            startRequest = nil
            log("MATCH_SESSION_REJECTED reason=\"MATCH_START_NOT_STARTING\" match_id=" .. quote(payload.matchId))
            return true
        end
        if payload.startGeneration ~= matchControl.startGeneration or payload.startToken ~= matchControl.startToken then
            onlineError = "MATCH_START_TOKEN_MISMATCH"
            startRequest = nil
            log("MATCH_SESSION_REJECTED reason=\"MATCH_START_TOKEN_MISMATCH\" match_id=" .. quote(payload.matchId))
            return true
        end
        if cancelledMatchIds[payload.matchId] then
            log("MATCH_SESSION_IGNORED_AFTER_CANCEL match_id=\"" .. payload.matchId .. "\"")
            return true
        end
        local key = payload.matchId .. ":" .. tostring(payload.startGeneration)
        if lastStartKey == key then
            log("MATCH_START_DUPLICATE_IGNORED key=\"" .. key .. "\"")
        else
            log("MATCH_SESSION_VALIDATED match_id=" .. quote(payload.matchId)
                .. " generation=" .. quote(payload.startGeneration)
                .. " token=" .. quote(payload.startToken))
            lastStartKey = key
            startRequest = payload
            matchState = payload
            matchControl = payload
            queueState = "STARTING"
            log("MATCH_SESSION_APPLIED match_id=" .. quote(payload.matchId)
                .. " generation=" .. quote(payload.startGeneration))
            log("MATCH_START_RECEIVED match_id=\"" .. payload.matchId .. "\" generation=\"" .. tostring(payload.startGeneration) .. "\"")
        end
    elseif message.type == "MATCH_RESULT_FINAL" then
        if type(payload.matchId) ~= "string" or type(payload.results) ~= "table" then
            disconnect("INVALID_MATCH_RESULT")
            return false
        end
        matchState = payload
        matchControl = payload
        startRequest = nil
        lastStartKey = nil
        nextScoreAt = 0
        pendingTerminal = nil
        finalizedMatchId = payload.matchId
        queueState = "RESULT"
        log("MATCH_RESULT_FINAL match_id=\"" .. payload.matchId .. "\"")
    elseif message.type == "ERROR" then
        if type(payload.code) ~= "string" then
            disconnect("INVALID_ERROR_MESSAGE")
            return false
        end
        findMatchInFlight = false
        leaveQueueInFlight = false
        queueState = "ERROR"
        onlineError = payload.code
        log("ONLINE_ERROR code=\"" .. payload.code .. "\"")
    elseif message.type == "HEARTBEAT" then
        backendConnected = payload.backendConnected == true
    else
        disconnect("UNKNOWN_MESSAGE_TYPE")
        return false
    end
    return true
end

function liveIPC.Initialize()
    if type(Isaac1v1IPC) ~= "table"
        or type(Isaac1v1IPC.Connect) ~= "function"
        or type(Isaac1v1IPC.Disconnect) ~= "function"
        or type(Isaac1v1IPC.IsConnected) ~= "function"
        or type(Isaac1v1IPC.Send) ~= "function"
        or type(Isaac1v1IPC.Receive) ~= "function" then
        log("IPC_COMPONENT_MISSING expected=\"Isaac1v1IPC\"")
        return false
    end
    local jsonLoaded, loadedJson = pcall(require, "json")
    if not jsonLoaded or type(loadedJson) ~= "table"
        or type(loadedJson.encode) ~= "function" or type(loadedJson.decode) ~= "function" then
        log("IPC_UNAVAILABLE reason=\"JSON_MISSING\" detail=\"" .. tostring(loadedJson) .. "\"")
        return false
    end
    nativeAPI = Isaac1v1IPC
    jsonModule = loadedJson
    componentInstalled = true
    local offlineSent, offlineError = nativeAPI.Send("{}")
    local oversizedSent, oversizedError = nativeAPI.Send(string.rep("x", 64 * 1024))
    if offlineSent == false and offlineError == "NOT_CONNECTED"
        and oversizedSent == false and oversizedError == "IPC_MESSAGE_TOO_LARGE" then
        log("IPC_NATIVE_SELF_TEST_OK offline=\"NOT_CONNECTED\" oversized=\"IPC_MESSAGE_TOO_LARGE\"")
    else
        log("IPC_NATIVE_SELF_TEST_FAILED offline=\"" .. tostring(offlineError)
            .. "\" oversized=\"" .. tostring(oversizedError) .. "\"")
    end
    nextRetryAt = 0
    log("IPC_COMPONENT_READY version=\"" .. tostring(nativeAPI.Version or "unknown")
        .. "\" transport=\"" .. tostring(nativeAPI.Transport or "unknown") .. "\"")
    return true
end

function liveIPC.Update()
    if nativeAPI == nil then return end
    local current = now()
    if current == lastUpdateAt then return end
    lastUpdateAt = current

    if phase == "DISCONNECTED" then
        if current < nextRetryAt then return end
        local connected, errorMessage = nativeAPI.Connect()
        if connected then
            markConnected()
        elseif errorMessage == "CONNECTING" then
            phase = "CONNECTING"
        else
            nextRetryAt = current + RETRY_SECONDS
        end
        return
    end

    if phase == "CONNECTING" then
        local connected, errorMessage = nativeAPI.IsConnected()
        if connected then
            markConnected()
        elseif errorMessage ~= nil then
            phase = "DISCONNECTED"
            nextRetryAt = current + RETRY_SECONDS
        end
        return
    end

    for _ = 1, 8 do
        local encoded, receiveError = nativeAPI.Receive()
        if receiveError ~= nil then
            disconnect(receiveError)
            return
        end
        if encoded == nil then break end
        if not handleMessage(encoded) then return end
    end
    if phase == "CONNECTED" and now() >= nextSteamIdentityPollAt then
        nextSteamIdentityPollAt = now() + 2
        refreshSteamIdentity()
    end
    if phase == "CONNECTED" and now() >= nextActiveModScanAt then
        nextActiveModScanAt = now() + 2
        sendEnvelope("GET_ACTIVE_MODS", {allowlistIds = competitiveModAllowlistIds, allowlist = competitiveModAllowlist})
    end
    if phase == "CONNECTED" and now() - lastMessageAt > STALE_SECONDS then
        disconnect("STALE_CONNECTION")
    end

end

function liveIPC.JoinQueue()
    if phase ~= "CONNECTED" then return false, "COMPANION_NOT_RUNNING" end
    if not steamIdentityReady then
        onlineError = "STEAM_IDENTITY_NOT_FOUND"
        log("MATCHMAKING_BLOCKED reason=\"STEAM_IDENTITY_NOT_FOUND\"")
        return false, "STEAM_IDENTITY_NOT_FOUND"
    end
    if findMatchInFlight then return false, "REQUEST_IN_FLIGHT" end
    onlineError = nil
    local sent, errorMessage = sendEnvelope("JOIN_QUEUE", {})
    if sent then
        findMatchInFlight = true
        queueState = "JOIN_PENDING"
    end
    return sent, errorMessage
end

function liveIPC.LeaveQueue()
    if phase ~= "CONNECTED" then return false, "COMPANION_NOT_RUNNING" end
    if queueState == "STARTED" then
        return false, "MATCH_ALREADY_STARTED"
    end
    if leaveQueueInFlight then return false, "REQUEST_IN_FLIGHT" end
    local sent, errorMessage = sendEnvelope("LEAVE_QUEUE", {})
    if sent then
        leaveQueueInFlight = true
        queueState = "CANCEL_PENDING"
        leaveRequestedAt = now()
        log("QUEUE_LEAVE_REQUEST")
    end
    return sent, errorMessage
end

function liveIPC.Ready()
    if phase ~= "CONNECTED" then return false, "COMPANION_NOT_RUNNING" end
    local sent, errorMessage = sendEnvelope("MATCH_READY", {})
    if sent then queueState = "MATCH_FOUND"; log("MATCH_READY_SENT") end
    return sent, errorMessage
end

function liveIPC.CancelMatch()
    if phase ~= "CONNECTED" then return false, "COMPANION_NOT_RUNNING" end
    if matchState ~= nil and type(matchState.matchId) == "string" then
        cancelledMatchIds[matchState.matchId] = true
    end
    startRequest = nil
    matchControl = nil
    matchState = nil
    queueState = "CANCEL_PENDING"
    return sendEnvelope("MATCH_CANCEL", {})
end

function liveIPC.IsCancelled(matchId)
    return type(matchId) == "string" and cancelledMatchIds[matchId] == true
end

function liveIPC.GetStartRequest()
    return startRequest
end

function liveIPC.ConsumeStart(matchId, generation)
    if startRequest == nil or startRequest.matchId ~= matchId or startRequest.startGeneration ~= generation then return nil end
    local value = startRequest
    startRequest = nil
    return true
end

function liveIPC.AcknowledgeStarted(matchId, generation)
    if phase ~= "CONNECTED" then return false, "COMPANION_NOT_RUNNING" end
    return sendEnvelope("MATCH_STARTED", {matchId = matchId, startGeneration = generation})
end

function liveIPC.SubmitScore(score, runTime, final)
    if phase ~= "CONNECTED" then return false, "COMPANION_NOT_RUNNING" end
    if type(score) ~= "number" then return false, "INVALID_SCORE" end
    scoreSequence = scoreSequence + 1
    local sent, errorMessage = sendEnvelope("MATCH_SCORE_UPDATE", {score = math.floor(score), runTime = runTime, sequence = scoreSequence, final = final == true})
    if sent then log("LIVE_SCORE_UPDATE score=\"" .. tostring(math.floor(score)) .. "\"") end
    return sent, errorMessage
end

function liveIPC.MaybeSubmitScore(score, runTime)
    local current = now()
    if current < nextScoreAt or queueState ~= "STARTED" or type(score) ~= "number" then return false end
    nextScoreAt = current + 1
    if lastScore == score then
        return false
    end
    lastScore = score
    return liveIPC.SubmitScore(score, runTime, false)
end

function liveIPC.SubmitTerminal(reason, score, runTime)
    if finalizedMatchId ~= nil then
        log("TERMINAL_EVENT_SUPPRESSED reason=\"RESULT_ALREADY_FINAL\" match_id=\"" .. tostring(finalizedMatchId) .. "\"")
        return false, "RESULT_ALREADY_FINAL"
    end
    if phase ~= "CONNECTED" then return false, "COMPANION_NOT_RUNNING" end
    scoreSequence = scoreSequence + 1
    local scoreSent, scoreError = sendEnvelope("MATCH_SCORE_UPDATE", {score = math.floor(score or 0), runTime = runTime, sequence = scoreSequence, final = true})
    local terminalSent, terminalError = sendEnvelope("MATCH_TERMINAL_EVENT", {reason = reason, finalScore = math.floor(score or 0), runTime = runTime, sequence = scoreSequence})
    if terminalSent then log("MATCH_TERMINAL event=\"" .. tostring(reason) .. "\" score=\"" .. tostring(math.floor(score or 0)) .. "\"") end
    if not scoreSent or not terminalSent then
        pendingTerminal = {scorePayload = {score = math.floor(score or 0), runTime = runTime, sequence = scoreSequence, final = true}, terminalPayload = {reason = reason, finalScore = math.floor(score or 0), runTime = runTime, sequence = scoreSequence}}
    else
        pendingTerminal = nil
    end
    return scoreSent and terminalSent, terminalError or scoreError
end

function liveIPC.DisconnectMatch(matchId)
    if type(matchId) ~= "string" or matchId == "" then return false, "INVALID_MATCH_ID" end
    if phase ~= "CONNECTED" then return false, "COMPANION_NOT_RUNNING" end
    local sent, errorMessage = sendEnvelope("MATCH_DISCONNECT", {matchId = matchId})
    if sent then
        log("MATCH_DISCONNECT_SENT match_id=" .. quote(matchId) .. " outcome=\"LOSS\"")
    end
    return sent, errorMessage
end

function liveIPC.SubmitDisconnect(matchId)
    return liveIPC.DisconnectMatch(matchId)
end

function liveIPC.SetMatchResetHandler(handler)
    if handler ~= nil and type(handler) ~= "function" then return false end
    matchResetHandler = handler
    return true
end

function liveIPC.SetAvailableCharacterTypes(value)
    if type(value) ~= "table" or #value == 0 then return false, "INVALID_AVAILABLE_CHARACTERS" end
    availableCharacterTypes = value
    if phase == "CONNECTED" then
        return sendEnvelope("PLAYER_AVAILABILITY", {availableCharacterTypes = availableCharacterTypes})
    end
    return true
end

function liveIPC.SetCompetitiveModAllowlist(value)
    if type(value) ~= "table" then return false end
    competitiveModAllowlist = value
    competitiveModAllowlistIds = {}
    for _, entry in ipairs(value) do
        if type(entry) == "table" and entry.workshopId ~= nil then
            competitiveModAllowlistIds[#competitiveModAllowlistIds + 1] = tostring(entry.workshopId)
        elseif type(entry) == "string" then
            competitiveModAllowlistIds[#competitiveModAllowlistIds + 1] = entry
        end
    end
    if phase == "CONNECTED" then
        return sendEnvelope("GET_ACTIVE_MODS", {allowlistIds = competitiveModAllowlistIds, allowlist = competitiveModAllowlist})
    end
    return true
end

function liveIPC.GetActiveMods()
    return activeMods
end

function liveIPC.BeginCompetitiveResultTransition(matchId)
    if finalizedMatchId == nil or tostring(finalizedMatchId) ~= tostring(matchId) then return false end
    if not competitiveResultTransition then
        competitiveResultTransition = true
        log("COMPETITIVE_RESULT_TRANSITION_BEGIN match_id=\"" .. tostring(matchId) .. "\"")
    end
    return true
end

function liveIPC.IsCompetitiveResultTransition()
    return competitiveResultTransition == true and finalizedMatchId ~= nil
end

function liveIPC.IsMatchFinalized()
    return finalizedMatchId ~= nil
end

function liveIPC.ClearResult()
    matchState = nil
    matchControl = nil
    startRequest = nil
    pendingTerminal = nil
    lastScore = nil
    nextScoreAt = 0
    finalizedMatchId = nil
    competitiveResultTransition = false
    leaveRequestedAt = nil
    queueState = "IDLE"
    log("MATCH_RESULT_CLEARED")
end

function liveIPC.GetLeaveElapsed()
    if leaveRequestedAt == nil then return nil end
    return now() - leaveRequestedAt
end

function liveIPC.GetStatus()
    return {
        component = componentInstalled and "INSTALLED" or "NOT INSTALLED",
        companion = phase == "CONNECTED" and "CONNECTED" or "NOT RUNNING",
        backend = backendConnected and "CONNECTED" or "DISCONNECTED",
        player = playerState,
        queue = queueState,
        match = matchState,
        matchControl = matchControl,
        startRequest = startRequest,
        error = onlineError,
        result = (queueState == "RESULT" and matchState or nil),
    }
end

function liveIPC.Shutdown()
    disconnect("mod_unload")
end

return liveIPC
