-- Match transport backed by the standalone Steam P2P extension.
local transport = {}
local protocol = include("scripts/protocol.lua")
local destinationCatalog = include("scripts/destination_catalog.lua")
local statsSnapshot = include("scripts/stats_snapshot.lua")

local componentInstalled = false
local identity = nil
local playerState = nil
local queueState = "IDLE"
local onlineError = nil
local transportActive = false
local lastUpdateAt = nil
local lastTransportPhase = nil
local lobbyId = "0"
local ownerSteamId = "0"
local peerSteamId = "0"
local peerPersona = "Unknown"
local frozenOwnerSteamId = nil
local outboundSequence = 0
local lastInboundSequence = 0
local lastNativeSequence = 0
local nextHeartbeatAt = 0
local leaveRequestedAt = nil

local availableCharacterTypes = nil
local availableDestinationIds = nil
local localHello = nil
local peerHello = nil
local helloSent = false
local sharedCharacters = nil
local sharedDestinations = nil
local matchConfig = nil
local matchState = nil
local matchControl = nil
local startRequest = nil
local startConsumed = false
local startGeneration = 1
local localReady = false
local peerReady = false
local localStarted = false
local peerStarted = false
local configSent = false
local configAccepted = false
local configAcked = false
local commitSent = false
local cancelledMatchIds = {}
local lifecycleMatchId = nil
local matchResetHandler = nil

local localScore = 0
local peerScore = 0
local localRunTime = "00:00"
local peerRunTime = "00:00"
local lastScore = nil
local nextScoreAt = 0
local localTerminal = nil
local peerTerminal = nil
local finalizedMatchId = nil
local resultState = nil
local competitiveResultTransition = false
local terminalResetHandler = nil
local networkCleanupAt = nil
local networkCleanupDone = false
local statsSubmittedMatchIds = {}

local function now()
    if Isaac ~= nil and type(Isaac.GetTime) == "function" then return Isaac.GetTime() / 1000 end
    return os.clock()
end

local function log(message)
    Isaac.DebugString("[Isaac1v1P2P] " .. tostring(message))
end

local function quote(value)
    return '"' .. tostring(value == nil and "<nil>" or value):gsub('"', "'") .. '"'
end

local function setQueue(nextState)
    if queueState == nextState then return end
    log("MATCHMAKING_STATE previous=" .. quote(queueState) .. " state=" .. quote(nextState))
    queueState = nextState
end

local function apiAvailable()
    local names = {
        "SteamP2PGetIdentity", "SteamP2PStartMatchmaking", "SteamP2PCancelMatchmaking",
        "SteamP2PGetState", "SteamP2PSend", "SteamP2PPollEvents", "SteamP2PLeave",
    }
    for _, name in ipairs(names) do if type(_G[name]) ~= "function" then return false end end
    return true
end

local function copyList(values)
    local copy = {}
    for _, value in ipairs(values or {}) do copy[#copy + 1] = value end
    return copy
end

local function resetMatchNetwork()
    frozenOwnerSteamId = nil
    outboundSequence = 0
    lastInboundSequence = 0
    lastNativeSequence = 0
    nextHeartbeatAt = 0
    localHello = nil
    peerHello = nil
    helloSent = false
    sharedCharacters = nil
    sharedDestinations = nil
    matchConfig = nil
    matchState = nil
    matchControl = nil
    startRequest = nil
    startConsumed = false
    startGeneration = 1
    localReady = false
    peerReady = false
    localStarted = false
    peerStarted = false
    configSent = false
    configAccepted = false
    configAcked = false
    commitSent = false
    localScore = 0
    peerScore = 0
    localRunTime = "00:00"
    peerRunTime = "00:00"
    lastScore = nil
    nextScoreAt = 0
    localTerminal = nil
    peerTerminal = nil
    networkCleanupAt = nil
    networkCleanupDone = false
end

local function closeNetwork(useCancel)
    if transportActive then
        if useCancel and type(SteamP2PCancelMatchmaking) == "function" then pcall(SteamP2PCancelMatchmaking)
        elseif type(SteamP2PLeave) == "function" then pcall(SteamP2PLeave) end
    end
    transportActive = false
    lobbyId = "0"
    ownerSteamId = "0"
    peerSteamId = "0"
    frozenOwnerSteamId = nil
end

local function beginNewMatch(payload)
    if type(payload) ~= "table" or type(payload.matchId) ~= "string" or payload.matchId == "" then return false end
    if lifecycleMatchId == payload.matchId then return true end
    local previous = lifecycleMatchId or finalizedMatchId
    lifecycleMatchId = payload.matchId
    finalizedMatchId = nil
    resultState = nil
    competitiveResultTransition = false
    if type(matchResetHandler) == "function" then
        local ok, reason = pcall(matchResetHandler, previous, payload.matchId, payload)
        if not ok then
            onlineError = "MATCH_RESET_FAILED"
            log("COMPETITIVE_MATCH_RESET_FAILED match_id=" .. quote(payload.matchId)
                .. " reason=" .. quote(reason))
            return false
        end
    end
    return true
end

local function sendMessage(messageType, fields)
    if not transportActive or peerSteamId == "0" then return false, "PEER_NOT_CONNECTED" end
    outboundSequence = outboundSequence + 1
    local payload = {}
    for key, value in pairs(fields or {}) do payload[key] = value end
    payload.protocol = protocol.VERSION
    payload.build = protocol.BUILD
    payload.catalog = protocol.CATALOG
    payload.lobby_id = lobbyId
    payload.sender_steam_id = identity.steamId64
    payload.sequence = outboundSequence
    if matchConfig ~= nil and payload.match_id == nil then payload.match_id = matchConfig.matchId end
    local ok, sent, reason = pcall(SteamP2PSend, protocol.Encode(messageType, payload))
    if not ok or sent ~= true then return false, tostring(ok and reason or sent) end
    return true
end

local function fail(reason, notifyPeer)
    reason = tostring(reason or "P2P_ERROR")
    onlineError = reason
    log("MATCH_FAILED reason=" .. quote(reason) .. " lobby_id=" .. quote(lobbyId))
    if notifyPeer and peerSteamId ~= "0" then sendMessage("MATCH_FAIL", { reason = reason }) end
    closeNetwork(false)
    setQueue("ERROR")
end

local function generateSeed()
    if Seeds == nil or type(Seeds.Seed2String) ~= "function"
        or type(Seeds.IsStringValidSeed) ~= "function" then return nil end
    for _ = 1, 128 do
        local number = type(Random) == "function" and Random() or math.random(1, 2147483646)
        number = math.abs(tonumber(number) or 0)
        if number ~= 0 then
            local encodedOk, seed = pcall(Seeds.Seed2String, number)
            local validOk, valid = false, false
            if encodedOk then validOk, valid = pcall(Seeds.IsStringValidSeed, seed) end
            if validOk and valid == true then return seed end
        end
    end
    return nil
end

local function randomIndex(count)
    if count <= 1 then return 1 end
    local value = type(Random) == "function" and Random() or math.random(1, 2147483646)
    return (math.abs(tonumber(value) or 0) % count) + 1
end

local function characterName(characterType)
    if EntityConfig ~= nil and type(EntityConfig.GetPlayer) == "function" then
        local ok, config = pcall(EntityConfig.GetPlayer, characterType)
        if ok and config ~= nil and type(config.GetName) == "function" then
            local nameOk, name = pcall(config.GetName, config)
            if nameOk and type(name) == "string" and name ~= "" then return name end
        end
    end
    return "PlayerType " .. tostring(characterType)
end

local function sessionForLocal(config)
    return {
        matchId = config.matchId,
        playerId = identity.steamId64,
        opponentId = peerSteamId,
        opponentPersonaName = peerPersona,
        characterType = config.characterType,
        characterName = config.characterName,
        seed = config.seed,
        difficulty = "HARD",
        gameMode = "STANDARD",
        targetDestinationId = config.targetDestinationId,
        targetDestinationName = config.targetDestinationName,
        startGeneration = startGeneration,
        startToken = config.matchId .. ":" .. tostring(startGeneration),
        sessionToken = config.matchId,
        source = "STEAM_P2P",
        active = true,
    }
end

local function rebuildMatchControl(status)
    if matchConfig == nil then return end
    matchState = sessionForLocal(matchConfig)
    matchState.status = status or queueState
    matchControl = matchState
    matchControl.players = {
        { playerId = identity.steamId64, state = localStarted and "STARTED" or (localReady and "READY" or "FOUND") },
        { playerId = peerSteamId, state = peerStarted and "STARTED" or (peerReady and "READY" or "FOUND") },
    }
end

local function enterMatchFound()
    if matchConfig == nil or not beginNewMatch(sessionForLocal(matchConfig)) then return false end
    setQueue("MATCH_FOUND")
    rebuildMatchControl("MATCH_FOUND")
    onlineError = nil
    log("MATCH_FOUND match_id=" .. quote(matchConfig.matchId)
        .. " opponent=" .. quote(peerPersona)
        .. " character=" .. quote(matchConfig.characterName)
        .. " seed=" .. quote(matchConfig.seed)
        .. " target=" .. quote(matchConfig.targetDestinationId))
    return true
end

local function makeAuthorityConfig()
    local seed = generateSeed()
    if seed == nil then return nil, "VALID_SEED_GENERATION_FAILED" end
    local characterType = sharedCharacters[randomIndex(#sharedCharacters)]
    local targetId = sharedDestinations[randomIndex(#sharedDestinations)]
    local destination = destinationCatalog.Get(targetId)
    if destination == nil then return nil, "DESTINATION_CATALOG_MISSING" end
    local nonce = type(Random) == "function" and math.abs(Random()) or math.random(1, 2147483646)
    return {
        matchId = "p2p-" .. lobbyId .. "-" .. ownerSteamId .. "-" .. tostring(nonce),
        lobbyId = lobbyId,
        authoritySteamId = ownerSteamId,
        seed = seed,
        characterType = characterType,
        characterName = characterName(characterType),
        targetDestinationId = targetId,
        targetDestinationName = destination.name,
        build = protocol.BUILD,
        catalog = protocol.CATALOG,
    }
end

local function sendHello()
    if helloSent then return true end
    if type(availableCharacterTypes) ~= "table" or #availableCharacterTypes == 0 then
        return false, "CHARACTER_AVAILABILITY_UNAVAILABLE"
    end
    if type(availableDestinationIds) ~= "table" or #availableDestinationIds == 0 then
        return false, "DESTINATION_AVAILABILITY_UNAVAILABLE"
    end
    localHello = {
        steamId = identity.steamId64,
        persona = identity.personaName,
        build = protocol.BUILD,
        catalog = protocol.CATALOG,
        characterTypes = copyList(availableCharacterTypes),
        destinationIds = copyList(availableDestinationIds),
    }
    local sent, reason = sendMessage("HELLO", {
        steam_id = localHello.steamId,
        persona = localHello.persona,
        characters = protocol.EncodeList(localHello.characterTypes),
        destinations = protocol.EncodeList(localHello.destinationIds),
    })
    if sent then
        helloSent = true
        log("HELLO_SENT local=" .. quote(localHello.steamId)
            .. " character_count=" .. quote(#localHello.characterTypes)
            .. " destination_count=" .. quote(#localHello.destinationIds))
    end
    return sent, reason
end

local function maybeSendConfig()
    if identity.steamId64 ~= ownerSteamId or configSent or peerHello == nil then return true end
    matchConfig = makeAuthorityConfig()
    if matchConfig == nil then return false, "MATCH_CONFIG_GENERATION_FAILED" end
    local sent, reason = sendMessage("MATCH_CONFIG", {
        match_id = matchConfig.matchId,
        authority_steam_id = matchConfig.authoritySteamId,
        seed = matchConfig.seed,
        character = matchConfig.characterType,
        character_name = matchConfig.characterName,
        target_destination_id = matchConfig.targetDestinationId,
        target_destination_name = matchConfig.targetDestinationName,
    })
    if not sent then return false, reason end
    configSent = true
    log("MATCH_CONFIG_SENT match_id=" .. quote(matchConfig.matchId)
        .. " authority=" .. quote(ownerSteamId)
        .. " character=" .. quote(matchConfig.characterType)
        .. " seed=" .. quote(matchConfig.seed)
        .. " target=" .. quote(matchConfig.targetDestinationId))
    return true
end

local function handleHello(message)
    if peerHello ~= nil then return false, "DUPLICATE_HELLO" end
    local hello, reason = protocol.ValidateCapabilities(message, peerSteamId)
    if hello == nil then return false, reason end
    if hello.build ~= protocol.BUILD then return false, "BUILD_MISMATCH" end
    if hello.catalog ~= protocol.CATALOG then return false, "CATALOG_MISMATCH" end
    peerHello = hello
    if peerPersona == "Unknown" or peerPersona == "" then peerPersona = hello.persona end
    sharedCharacters = protocol.Intersection(localHello.characterTypes, hello.characterTypes)
    sharedDestinations = protocol.Intersection(localHello.destinationIds, hello.destinationIds)
    log("HELLO_RECEIVED peer=" .. quote(hello.steamId)
        .. " character_count=" .. quote(#hello.characterTypes)
        .. " destination_count=" .. quote(#hello.destinationIds))
    log("CAPABILITY_INTERSECTION characters=" .. quote(#sharedCharacters)
        .. " destinations=" .. quote(#sharedDestinations))
    if #sharedCharacters == 0 then return false, "NO_SHARED_CHARACTERS" end
    if #sharedDestinations == 0 then return false, "NO_SHARED_DESTINATIONS" end
    return maybeSendConfig()
end

local function handleConfig(message, senderSteamId)
    if identity.steamId64 == ownerSteamId then return false, "AUTHORITY_RECEIVED_CONFIG" end
    if configAccepted or matchConfig ~= nil then return false, "DUPLICATE_MATCH_CONFIG" end
    if peerHello == nil then return false, "HELLO_NOT_COMPLETE" end
    local config, reason = protocol.ValidateMatchConfig(message, {
        senderSteamId = senderSteamId,
        frozenOwnerSteamId = frozenOwnerSteamId,
        lobbyId = lobbyId,
        sharedCharacters = sharedCharacters,
        sharedDestinations = sharedDestinations,
    })
    if config == nil then return false, reason end
    if config.build ~= peerHello.build or config.catalog ~= peerHello.catalog then
        return false, "CONFIG_VERSION_MISMATCH"
    end
    local seedOk, validSeed = pcall(Seeds.IsStringValidSeed, config.seed)
    if not seedOk or validSeed ~= true then return false, "INVALID_MATCH_SEED" end
    local destination = destinationCatalog.Get(config.targetDestinationId)
    if destination == nil or destination.name ~= config.targetDestinationName then
        return false, "DESTINATION_CONFIG_MISMATCH"
    end
    config.characterName = message.fields.character_name
    if type(config.characterName) ~= "string" or config.characterName == "" then return false, "CHARACTER_NAME_MISSING" end
    if config.characterName ~= characterName(config.characterType) then
        return false, "CHARACTER_CONFIG_MISMATCH"
    end
    matchConfig = config
    configAccepted = true
    if not enterMatchFound() then return false, "MATCH_RESET_FAILED" end
    local sent, sendReason = sendMessage("MATCH_CONFIG_ACK", {
        match_id = matchConfig.matchId,
        authority_steam_id = ownerSteamId,
    })
    if sent then log("MATCH_CONFIG_ACK_SENT match_id=" .. quote(matchConfig.matchId)) end
    return sent, sendReason
end

local function handleConfigAck(message)
    if identity.steamId64 ~= ownerSteamId then return false, "NON_AUTHORITY_RECEIVED_ACK" end
    if not configSent or matchConfig == nil or configAcked then return false, "INVALID_CONFIG_ACK" end
    local fields = message.fields
    if fields.match_id ~= matchConfig.matchId or fields.authority_steam_id ~= ownerSteamId then
        return false, "ACK_CONFIG_MISMATCH"
    end
    configAcked = true
    log("MATCH_CONFIG_ACK_RECEIVED match_id=" .. quote(matchConfig.matchId))
    return enterMatchFound()
end

local function tryCommit()
    if identity.steamId64 ~= ownerSteamId or commitSent or not configAcked
        or not localReady or not peerReady then return true end
    local sent, reason = sendMessage("MATCH_COMMIT", {
        match_id = matchConfig.matchId,
        authority_steam_id = ownerSteamId,
        start_generation = startGeneration,
        start_token = matchConfig.matchId .. ":" .. tostring(startGeneration),
    })
    if not sent then return false, reason end
    commitSent = true
    startRequest = sessionForLocal(matchConfig)
    setQueue("STARTING")
    rebuildMatchControl("STARTING")
    log("MATCH_COMMIT_SENT match_id=" .. quote(matchConfig.matchId))
    return true
end

local function handleReady()
    if matchConfig == nil or queueState ~= "MATCH_FOUND" then return false, "READY_OUT_OF_STATE" end
    peerReady = true
    rebuildMatchControl("MATCH_FOUND")
    log("PEER_READY match_id=" .. quote(matchConfig.matchId))
    return tryCommit()
end

local function handleCommit(message, senderSteamId)
    if identity.steamId64 == ownerSteamId or not configAccepted or not localReady then
        return false, "COMMIT_OUT_OF_STATE"
    end
    local fields = message.fields
    if tostring(senderSteamId) ~= frozenOwnerSteamId or fields.authority_steam_id ~= frozenOwnerSteamId
        or fields.match_id ~= matchConfig.matchId then return false, "COMMIT_CONFIG_MISMATCH" end
    startGeneration = tonumber(fields.start_generation) or 0
    if startGeneration < 1 or fields.start_token ~= matchConfig.matchId .. ":" .. tostring(startGeneration) then
        return false, "COMMIT_TOKEN_MISMATCH"
    end
    commitSent = true
    startRequest = sessionForLocal(matchConfig)
    setQueue("STARTING")
    rebuildMatchControl("STARTING")
    log("MATCH_COMMIT_RECEIVED match_id=" .. quote(matchConfig.matchId))
    return true
end

local function statsLog(message)
    Isaac.DebugString("[Isaac1v1P2PStats] " .. tostring(message))
end

local function utcTimestamp()
    if type(Isaac1v1P2P) ~= "table" or type(Isaac1v1P2P.GetUtcTimestamp) ~= "function" then
        return nil
    end
    local ok, value = pcall(Isaac1v1P2P.GetUtcTimestamp)
    return ok and type(value) == "string" and value or nil
end

local function attachStatsSnapshot(result, completedAt, authorityScore, otherScore,
    authorityRunTime, otherRunTime, authorityPersona, otherPersona)
    completedAt = completedAt or utcTimestamp()
    if completedAt == nil then
        statsLog("SNAPSHOT_SKIPPED reason=\"UTC_UNAVAILABLE\" match_id=" .. quote(result.matchId))
        return false
    end
    local authorityIsLocal = identity.steamId64 == ownerSteamId
    authorityPersona = authorityPersona or (authorityIsLocal and identity.personaName
        or (peerHello ~= nil and peerHello.persona or peerPersona))
    otherPersona = otherPersona or (authorityIsLocal
        and (peerHello ~= nil and peerHello.persona or peerPersona) or identity.personaName)
    local snapshot, reason = statsSnapshot.Build({
        matchId = result.matchId,
        protocol = protocol.VERSION,
        build = protocol.BUILD,
        completedAt = completedAt,
        characterType = matchConfig.characterType,
        characterName = matchConfig.characterName,
        targetDestinationId = matchConfig.targetDestinationId,
        targetDestinationName = matchConfig.targetDestinationName,
        authoritySteamId = ownerSteamId,
        authorityPersona = authorityPersona,
        authorityScore = authorityScore,
        authorityRunTime = authorityRunTime,
        peerSteamId = authorityIsLocal and peerSteamId or identity.steamId64,
        peerPersona = otherPersona,
        peerScore = otherScore,
        peerRunTime = otherRunTime,
        winnerSteamId = result.winnerPlayerId,
        isDraw = result.isDraw,
        terminalReason = result.terminalReason,
    })
    if snapshot == nil then
        statsLog("SNAPSHOT_SKIPPED reason=" .. quote(reason) .. " match_id=" .. quote(result.matchId))
        return false
    end
    result.statsSnapshot = snapshot
    return true
end

local function attachCurrentAuthorityStats(result, completedAt)
    local authorityIsLocal = identity.steamId64 == ownerSteamId
    return attachStatsSnapshot(result, completedAt,
        authorityIsLocal and localScore or peerScore,
        authorityIsLocal and peerScore or localScore,
        authorityIsLocal and localRunTime or peerRunTime,
        authorityIsLocal and peerRunTime or localRunTime)
end

local function submitFinalStats(result)
    if result == nil or result.statsSnapshot == nil
        or statsSubmittedMatchIds[result.matchId] then return false end
    if type(Isaac1v1P2P) ~= "table" or type(Isaac1v1P2P.SubmitFinalStats) ~= "function" then
        statsLog("SUBMIT_UNAVAILABLE match_id=" .. quote(result.matchId))
        return false
    end
    local payload, reason = statsSnapshot.Serialize(result.statsSnapshot)
    if payload == nil then
        statsLog("SERIALIZE_FAILED reason=" .. quote(reason) .. " match_id=" .. quote(result.matchId))
        return false
    end
    local ok, queued, queueReason = pcall(Isaac1v1P2P.SubmitFinalStats, payload)
    if not ok or queued ~= true then
        statsLog("QUEUE_FAILED reason=" .. quote(ok and queueReason or queued)
            .. " match_id=" .. quote(result.matchId))
        return false
    end
    statsSubmittedMatchIds[result.matchId] = true
    statsLog("QUEUED match_id=" .. quote(result.matchId) .. " bytes=" .. quote(#payload))
    return true
end

local function resultForLocal(winnerId, isDraw, terminalReason, terminalPlayerId, ownerScore, otherScore)
    local authorityIsLocal = identity.steamId64 == ownerSteamId
    local scoreById = {
        [ownerSteamId] = ownerScore,
        [authorityIsLocal and peerSteamId or identity.steamId64] = otherScore,
    }
    -- On the non-authority client, the second key above must be its own SteamID.
    if not authorityIsLocal then scoreById[identity.steamId64] = otherScore end
    local ownScore = scoreById[identity.steamId64] or localScore
    local opponentScore = scoreById[peerSteamId] or peerScore
    local localResult = isDraw and "DRAW" or (winnerId == identity.steamId64 and "WIN" or "LOSS")
    return {
        matchId = matchConfig.matchId,
        playerId = identity.steamId64,
        opponentId = peerSteamId,
        winnerPlayerId = isDraw and nil or winnerId,
        terminalPlayerId = terminalPlayerId,
        terminalReason = terminalReason,
        isDraw = isDraw == true,
        localResult = localResult,
        results = {
            { playerId = identity.steamId64, score = ownScore },
            { playerId = peerSteamId, score = opponentScore },
        },
        character = matchConfig.characterName,
        characterName = matchConfig.characterName,
        seed = matchConfig.seed,
        difficulty = "HARD",
        mode = "STANDARD",
        gameMode = "STANDARD",
        targetDestinationId = matchConfig.targetDestinationId,
        targetDestinationName = matchConfig.targetDestinationName,
    }
end

local function finalize(result, notifyPeer)
    if finalizedMatchId ~= nil then
        if result ~= nil and result.matchId == finalizedMatchId and result.statsSnapshot ~= nil then
            resultState = result
            submitFinalStats(result)
        end
        return true
    end
    finalizedMatchId = result.matchId
    resultState = result
    startRequest = nil
    setQueue("RESULT")
    networkCleanupAt = now() + 2
    log("MATCH_RESULT_FINAL match_id=" .. quote(result.matchId)
        .. " local_result=" .. quote(result.localResult)
        .. " terminal_reason=" .. quote(result.terminalReason))
    submitFinalStats(result)
    if notifyPeer then
        local authorityScore = identity.steamId64 == ownerSteamId and localScore or peerScore
        local nonAuthorityScore = identity.steamId64 == ownerSteamId and peerScore or localScore
        local authorityRunTime = identity.steamId64 == ownerSteamId and localRunTime or peerRunTime
        local nonAuthorityRunTime = identity.steamId64 == ownerSteamId and peerRunTime or localRunTime
        local snapshot = result.statsSnapshot
        sendMessage("RESULT", {
            match_id = result.matchId,
            winner_steam_id = result.winnerPlayerId or "0",
            terminal_player_id = result.terminalPlayerId or "0",
            terminal_reason = result.terminalReason or "RUN_COMPLETED",
            is_draw = result.isDraw and "1" or "0",
            authority_score = authorityScore,
            peer_score = nonAuthorityScore,
            authority_run_time = authorityRunTime,
            peer_run_time = nonAuthorityRunTime,
            completed_at = snapshot ~= nil and snapshot.completedAt or "",
            authority_persona = snapshot ~= nil and snapshot.players[1].persona or "",
            peer_persona = snapshot ~= nil and snapshot.players[2].persona or "",
        })
    end
    return true
end

local function evaluateTerminals()
    if finalizedMatchId ~= nil or matchConfig == nil then return end
    local losing = { DEATH = true, WRONG_DESTINATION = true, ABANDON = true }
    if localTerminal ~= nil and losing[localTerminal.reason] then
        local result = resultForLocal(peerSteamId, false, localTerminal.reason, identity.steamId64,
            identity.steamId64 == ownerSteamId and localScore or peerScore,
            identity.steamId64 == ownerSteamId and peerScore or localScore)
        if identity.steamId64 == ownerSteamId then attachCurrentAuthorityStats(result) end
        finalize(result, identity.steamId64 == ownerSteamId)
        return
    end
    if peerTerminal ~= nil and losing[peerTerminal.reason] then
        local result = resultForLocal(identity.steamId64, false, peerTerminal.reason, peerSteamId,
            ownerSteamId == identity.steamId64 and localScore or peerScore,
            ownerSteamId == identity.steamId64 and peerScore or localScore)
        if identity.steamId64 == ownerSteamId then attachCurrentAuthorityStats(result) end
        finalize(result, identity.steamId64 == ownerSteamId)
        return
    end
    if localTerminal ~= nil and peerTerminal ~= nil
        and localTerminal.reason == "RUN_COMPLETED" and peerTerminal.reason == "RUN_COMPLETED"
        and identity.steamId64 == ownerSteamId then
        local draw = localScore == peerScore
        local winner = draw and nil or (localScore > peerScore and identity.steamId64 or peerSteamId)
        local result = resultForLocal(winner, draw, "RUN_COMPLETED", nil, localScore, peerScore)
        attachCurrentAuthorityStats(result)
        finalize(result, true)
    end
end

local function handleResult(message, senderSteamId)
    if tostring(senderSteamId) ~= frozenOwnerSteamId or identity.steamId64 == ownerSteamId then
        return false, "RESULT_AUTHORITY_MISMATCH"
    end
    local fields = message.fields
    if fields.match_id ~= matchConfig.matchId then return false, "RESULT_MATCH_MISMATCH" end
    local authorityScore = tonumber(fields.authority_score)
    local nonAuthorityScore = tonumber(fields.peer_score)
    if authorityScore == nil or nonAuthorityScore == nil then return false, "RESULT_SCORE_INVALID" end
    local draw = fields.is_draw == "1"
    local winner = fields.winner_steam_id ~= "0" and fields.winner_steam_id or nil
    local terminalPlayer = fields.terminal_player_id ~= "0" and fields.terminal_player_id or nil
    local result = resultForLocal(winner, draw, fields.terminal_reason, terminalPlayer,
        authorityScore, nonAuthorityScore)
    if fields.completed_at ~= "" then
        attachStatsSnapshot(result, fields.completed_at, authorityScore, nonAuthorityScore,
            fields.authority_run_time, fields.peer_run_time,
            fields.authority_persona, fields.peer_persona)
    end
    return finalize(result, false)
end

local function validateEnvelope(event, message)
    local fields = message.fields
    local nativeSequence = tonumber(event.sequence) or 0
    local applicationSequence = tonumber(fields.sequence) or 0
    if nativeSequence <= lastNativeSequence or applicationSequence <= lastInboundSequence then
        log("MESSAGE_REJECTED reason=\"DUPLICATE_OR_STALE\"")
        return false
    end
    if tostring(event.steam_id64) ~= peerSteamId or tostring(event.lobby_id) ~= lobbyId
        or fields.sender_steam_id ~= peerSteamId or fields.lobby_id ~= lobbyId then
        fail("MESSAGE_ENVELOPE_MISMATCH", true)
        return false
    end
    if fields.protocol ~= protocol.VERSION then fail("PROTOCOL_MISMATCH", true) return false end
    if frozenOwnerSteamId ~= nil and tostring(ownerSteamId) ~= frozenOwnerSteamId then
        fail("LOBBY_OWNER_CHANGED", true)
        return false
    end
    if matchConfig ~= nil and message.type ~= "HELLO" and message.type ~= "HEARTBEAT"
        and message.type ~= "MATCH_FAIL"
        and fields.match_id ~= matchConfig.matchId then
        fail("MATCH_ID_MISMATCH", true)
        return false
    end
    lastNativeSequence = nativeSequence
    lastInboundSequence = applicationSequence
    return true
end

local function handleDataEvent(event)
    local message, reason = protocol.Decode(event.payload)
    if message == nil then fail(reason, true) return end
    if not validateEnvelope(event, message) then return end
    if message.type == "MATCH_FAIL" then fail(message.fields.reason or "PEER_REJECTED_MATCH", false) return end
    local ok, failure = true, nil
    if message.type == "HELLO" then ok, failure = handleHello(message)
    elseif message.type == "MATCH_CONFIG" then ok, failure = handleConfig(message, event.steam_id64)
    elseif message.type == "MATCH_CONFIG_ACK" then ok, failure = handleConfigAck(message)
    elseif message.type == "READY" then ok, failure = handleReady()
    elseif message.type == "MATCH_COMMIT" then ok, failure = handleCommit(message, event.steam_id64)
    elseif message.type == "STARTED" then
        peerStarted = true
        rebuildMatchControl("STARTED")
    elseif message.type == "SCORE" then
        local score = tonumber(message.fields.score)
        if score == nil then ok, failure = false, "INVALID_SCORE" else
            peerScore = math.floor(score)
            peerRunTime = message.fields.run_time or peerRunTime
        end
    elseif message.type == "DEATH" or message.type == "RUN_COMPLETED"
        or message.type == "WRONG_DESTINATION" or message.type == "ABANDON" then
        local score = tonumber(message.fields.final_score)
        if score == nil then ok, failure = false, "INVALID_TERMINAL_SCORE"
        else
            peerScore = math.floor(score)
            peerRunTime = message.fields.run_time or peerRunTime
            peerTerminal = { reason = message.type, score = peerScore, runTime = peerRunTime }
            evaluateTerminals()
        end
    elseif message.type == "RESULT" then ok, failure = handleResult(message, event.steam_id64)
    elseif message.type == "MATCH_CANCEL" then
        closeNetwork(false)
        resetMatchNetwork()
        setQueue("IDLE")
    elseif message.type == "HEARTBEAT" then
        -- Native heartbeats own timeout detection; this message binds liveness to match identity.
    else ok, failure = false, "UNEXPECTED_MESSAGE_" .. tostring(message.type) end
    if ok ~= true then fail(failure, true) end
end

local function observeState(snapshot)
    local phase = tostring(snapshot.phase or "UNKNOWN")
    if phase ~= lastTransportPhase then
        lastTransportPhase = phase
        log("STEAM_TRANSPORT_STATE state=" .. quote(phase))
    end
    lobbyId = tostring(snapshot.lobby_id or lobbyId)
    ownerSteamId = tostring(snapshot.owner_steam_id64 or ownerSteamId)
    peerSteamId = tostring(snapshot.peer_steam_id64 or peerSteamId)
    local persona = tostring(snapshot.peer_persona_name or "")
    if persona ~= "" and persona ~= "[unknown]" then peerPersona = persona end
    if frozenOwnerSteamId ~= nil and ownerSteamId ~= frozenOwnerSteamId then
        fail("LOBBY_OWNER_CHANGED", true)
        return false
    end
    if queueState == "SEARCHING" and lobbyId ~= "0" and peerSteamId ~= "0" then
        if ownerSteamId ~= identity.steamId64 and ownerSteamId ~= peerSteamId then
            fail("INVALID_LOBBY_OWNER", true)
            return false
        end
        frozenOwnerSteamId = ownerSteamId
        setQueue("NEGOTIATING")
        log("LOBBY_FULL lobby_id=" .. quote(lobbyId) .. " local=" .. quote(identity.steamId64)
            .. " peer=" .. quote(peerSteamId) .. " authority=" .. quote(ownerSteamId))
        local sent, reason = sendHello()
        if not sent then fail(reason, true) return false end
    end
    return true
end

function transport.Initialize()
    if REPENTOGON == nil or not apiAvailable() then
        componentInstalled = false
        onlineError = "P2P_COMPONENT_NOT_AVAILABLE"
        return false
    end
    local steamIdentity, reason = SteamP2PGetIdentity()
    if type(steamIdentity) ~= "table" then
        componentInstalled = false
        onlineError = reason or "STEAM_IDENTITY_NOT_FOUND"
        return false
    end
    identity = {
        steamId64 = tostring(steamIdentity.steam_id64),
        personaName = tostring(steamIdentity.persona_name or "Unknown"),
    }
    playerState = {
        playerId = identity.steamId64,
        steamId64 = identity.steamId64,
        personaName = identity.personaName,
        displayName = identity.personaName,
        avatar = type(steamIdentity.avatar_path) == "string"
            and steamIdentity.avatar_path or nil,
    }
    componentInstalled = true
    onlineError = nil
    log("P2P_COMPONENT_READY steam_id=" .. quote(identity.steamId64)
        .. " persona=" .. quote(identity.personaName))
    return true
end

function transport.Update()
    if not componentInstalled then return end
    local current = now()
    if lastUpdateAt == current then return end
    lastUpdateAt = current
    if queueState == "RESULT" and networkCleanupAt ~= nil and current >= networkCleanupAt
        and not networkCleanupDone then
        closeNetwork(false)
        networkCleanupDone = true
        log("MATCH_NETWORK_CLEANUP_COMPLETE result_presentation=\"PRESERVED\"")
        return
    end
    if not transportActive then return end
    local snapshot = SteamP2PGetState()
    if type(snapshot) ~= "table" or not observeState(snapshot) then return end
    for _, event in ipairs(SteamP2PPollEvents() or {}) do
        if event.type == "MESSAGE" then handleDataEvent(event)
        elseif event.type == "DISCONNECTED" or event.type == "ERROR" then
            if queueState == "STARTED" or localStarted then
                peerTerminal = { reason = "ABANDON", score = peerScore }
                local result = resultForLocal(identity.steamId64, false, "DISCONNECT", peerSteamId,
                    ownerSteamId == identity.steamId64 and localScore or peerScore,
                    ownerSteamId == identity.steamId64 and peerScore or localScore)
                attachCurrentAuthorityStats(result)
                finalize(result, false)
            elseif queueState ~= "RESULT" and queueState ~= "IDLE" then
                fail(event.detail or "PEER_DISCONNECTED", false)
            end
        end
        if queueState == "ERROR" then return end
    end
    if transportActive and peerSteamId ~= "0" and current >= nextHeartbeatAt then
        nextHeartbeatAt = current + 2
        sendMessage("HEARTBEAT", {})
    end
end

function transport.JoinQueue()
    if not componentInstalled then return false, "P2P_COMPONENT_NOT_AVAILABLE" end
    if queueState ~= "IDLE" then return false, "REQUEST_IN_FLIGHT" end
    if type(availableCharacterTypes) ~= "table" or #availableCharacterTypes == 0
        or type(availableDestinationIds) ~= "table" or #availableDestinationIds == 0 then
        return false, "PLAYER_AVAILABILITY_NOT_READY"
    end
    resetMatchNetwork()
    resultState = nil
    finalizedMatchId = nil
    competitiveResultTransition = false
    onlineError = nil
    peerPersona = "Unknown"
    local ok, reason = SteamP2PStartMatchmaking()
    if ok ~= true then onlineError = tostring(reason); return false, onlineError end
    transportActive = true
    setQueue("SEARCHING")
    log("QUEUE_SEARCHING")
    return true
end

function transport.LeaveQueue()
    if queueState == "STARTED" then return false, "MATCH_ALREADY_STARTED" end
    leaveRequestedAt = now()
    if transportActive and peerSteamId ~= "0" then sendMessage("MATCH_CANCEL", {}) end
    closeNetwork(true)
    resetMatchNetwork()
    setQueue("IDLE")
    log("QUEUE_CANCELLED")
    return true
end

function transport.CancelMatch()
    if matchConfig ~= nil then cancelledMatchIds[matchConfig.matchId] = true end
    return transport.LeaveQueue()
end

function transport.Ready()
    if queueState ~= "MATCH_FOUND" or matchConfig == nil then return false, "MATCH_NOT_FOUND" end
    if localReady then return false, "ALREADY_READY" end
    localReady = true
    rebuildMatchControl("MATCH_FOUND")
    local sent, reason = sendMessage("READY", {})
    if not sent then return false, reason end
    log("MATCH_READY_SENT match_id=" .. quote(matchConfig.matchId))
    local committed, commitReason = tryCommit()
    if not committed then return false, commitReason end
    return true
end

function transport.IsCancelled(matchId)
    return type(matchId) == "string" and cancelledMatchIds[matchId] == true
end
function transport.GetStartRequest() return startRequest end
function transport.ConsumeStart(matchId, generation)
    if startRequest == nil or startConsumed or startRequest.matchId ~= matchId
        or startRequest.startGeneration ~= generation then return nil end
    startConsumed = true
    startRequest = nil
    return true
end

function transport.AcknowledgeStarted(matchId, generation)
    if matchConfig == nil or matchConfig.matchId ~= matchId or generation ~= startGeneration then
        return false, "START_ACK_MISMATCH"
    end
    localStarted = true
    setQueue("STARTED")
    rebuildMatchControl("STARTED")
    local sent, reason = sendMessage("STARTED", { start_generation = generation })
    if sent then log("STARTED_SENT match_id=" .. quote(matchId)) end
    return sent, reason
end

function transport.SubmitScore(score, runTime, final)
    if queueState ~= "STARTED" or type(score) ~= "number" then return false, "INVALID_SCORE" end
    localScore = math.floor(score)
    if type(runTime) == "string" then localRunTime = runTime end
    return sendMessage("SCORE", { score = localScore, run_time = runTime or "Unknown", final = final and "1" or "0" })
end

function transport.MaybeSubmitScore(score, runTime)
    local current = now()
    if queueState ~= "STARTED" or type(score) ~= "number" or current < nextScoreAt then return false end
    nextScoreAt = current + 1
    score = math.floor(score)
    if lastScore == score then return false end
    lastScore = score
    return transport.SubmitScore(score, runTime, false)
end

function transport.SubmitTerminal(reason, score, runTime)
    if finalizedMatchId ~= nil then return false, "RESULT_ALREADY_FINAL" end
    if matchConfig == nil or (queueState ~= "STARTED" and not localStarted) then return false, "MATCH_NOT_STARTED" end
    if reason ~= "DEATH" and reason ~= "RUN_COMPLETED" and reason ~= "WRONG_DESTINATION" then
        return false, "INVALID_TERMINAL_REASON"
    end
    localScore = math.floor(tonumber(score) or localScore or 0)
    if type(runTime) == "string" then localRunTime = runTime end
    transport.SubmitScore(localScore, runTime, true)
    local sent, sendReason = sendMessage(reason, { final_score = localScore, run_time = runTime or "Unknown" })
    localTerminal = { reason = reason, score = localScore, runTime = localRunTime }
    log("MATCH_TERMINAL_EVENT reason=" .. quote(reason) .. " score=" .. quote(localScore))
    evaluateTerminals()
    return sent, sendReason
end

function transport.DisconnectMatch(matchId)
    if matchConfig == nil or matchConfig.matchId ~= matchId then return false, "INVALID_MATCH_ID" end
    localScore = math.floor(tonumber(localScore) or 0)
    if transportActive then sendMessage("ABANDON", { final_score = localScore, run_time = localRunTime }) end
    localTerminal = { reason = "ABANDON", score = localScore, runTime = localRunTime }
    evaluateTerminals()
    closeNetwork(false)
    return true
end
function transport.SubmitDisconnect(matchId) return transport.DisconnectMatch(matchId) end

function transport.SetMatchResetHandler(handler)
    if handler ~= nil and type(handler) ~= "function" then return false end
    matchResetHandler = handler
    return true
end
function transport.SetAvailableCharacterTypes(value)
    if type(value) ~= "table" or #value == 0 then return false, "INVALID_AVAILABLE_CHARACTERS" end
    availableCharacterTypes = copyList(value)
    return true
end
function transport.SetAvailableDestinationIds(value)
    if type(value) ~= "table" or #value == 0 then return false, "INVALID_AVAILABLE_DESTINATIONS" end
    availableDestinationIds = copyList(value)
    return true
end
function transport.SetTerminalResetHandler(handler)
    if handler ~= nil and type(handler) ~= "function" then return false end
    terminalResetHandler = handler
    return true
end
function transport.SetCompetitiveModAllowlist() return true end
function transport.GetActiveMods() return nil end

function transport.BeginCompetitiveResultTransition(matchId)
    if finalizedMatchId ~= matchId then return false end
    competitiveResultTransition = true
    return true
end
function transport.IsCompetitiveResultTransition()
    return competitiveResultTransition == true and finalizedMatchId ~= nil
end
function transport.IsMatchFinalized() return finalizedMatchId ~= nil end

function transport.ClearResult()
    local matchId = finalizedMatchId or lifecycleMatchId
    closeNetwork(false)
    resultState = nil
    finalizedMatchId = nil
    competitiveResultTransition = false
    networkCleanupAt = nil
    networkCleanupDone = false
    resetMatchNetwork()
    setQueue("IDLE")
    if type(terminalResetHandler) == "function" and matchId ~= nil then
        pcall(terminalResetHandler, matchId)
    end
    lifecycleMatchId = nil
    log("MATCH_RESULT_CLEARED")
end

function transport.GetLeaveElapsed()
    return leaveRequestedAt ~= nil and (now() - leaveRequestedAt) or nil
end

function transport.GetStatus()
    return {
        component = componentInstalled and "INSTALLED" or "NOT INSTALLED",
        transport = componentInstalled and "READY" or "UNAVAILABLE",
        player = playerState,
        queue = queueState,
        match = resultState or matchState,
        matchControl = resultState or matchControl,
        startRequest = startRequest,
        error = onlineError,
        result = queueState == "RESULT" and resultState or nil,
    }
end

function transport.Shutdown()
    closeNetwork(false)
    if type(Isaac1v1P2P) == "table" and type(Isaac1v1P2P.ShutdownStats) == "function" then
        pcall(Isaac1v1P2P.ShutdownStats)
    end
end

return transport
