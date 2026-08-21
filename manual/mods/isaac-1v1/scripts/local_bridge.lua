-- Bridge local VECHI/INACTIV care scrie comenzi de lobby în SaveData. Meniul F8
-- actual nu apelează Emit, ci folosește liveIPC.
local LocalBridge = {}

local BRIDGE_VERSION = 2
local DEFAULT_PLAYER_ID = "player-a"
local commandCounter = 0
local modInstance = nil
local sessionModule = nil
local status = "NOT_INITIALIZED"
local lastError = nil
local lastCommand = nil

local allowedCommands = {
    CREATE_LOBBY = true,
    JOIN_LOBBY = true,
    SET_READY = true,
    SET_UNREADY = true,
    LEAVE_LOBBY = true,
    REFRESH_LOBBY = true,
    LAUNCH_MATCH = true,
}

local function quote(value)
    return "\"" .. tostring(value):gsub("\"", "'") .. "\""
end

local function loadJson()
    local ok, json = pcall(require, "json")
    if not ok or json == nil or type(json.encode) ~= "function" then
        return nil
    end
    return json
end

local function inactiveSession()
    return {
        matchId = "menu-bridge",
        playerId = DEFAULT_PLAYER_ID,
        characterType = 0,
        characterName = "Isaac",
        seed = nil,
        difficulty = "HARD",
        gameMode = "STANDARD",
        source = "MENU_BRIDGE",
        active = false,
    }
end

local function nextCommandId()
    commandCounter = commandCounter + 1
    local frame = 0
    if Game ~= nil then
        local ok, game = pcall(Game)
        if ok and game ~= nil and type(game.GetFrameCount) == "function" then
            local frameOk, frameValue = pcall(game.GetFrameCount, game)
            if frameOk then frame = frameValue end
        end
    end
    local randomPart = math.random(1, 2147483646)
    return "cmd-" .. tostring(frame) .. "-" .. tostring(commandCounter) .. "-" .. tostring(randomPart)
end

local function commandError(reason)
    status = "ERROR"
    lastError = reason
    Isaac.DebugString("[Isaac1v1] BRIDGE_ERROR reason=" .. quote(reason))
    return nil
end

function LocalBridge.Initialize(mod, matchSession)
    -- Păstrează legăturile către mod și sesiune, necesare unei comenzi locale vechi.
    modInstance = mod
    sessionModule = matchSession
    status = "READY"
    lastError = nil
    return true
end

function LocalBridge.Emit(commandType, payload)
    -- Scrie în SaveData o comandă cu versiune, precum CREATE_LOBBY/JOIN_LOBBY/READY.
    -- Întoarce succes și ID-ul comenzii sau false și motivul exact.
    if not allowedCommands[commandType] then
        return commandError("UNSUPPORTED_COMMAND")
    end
    if modInstance == nil or type(modInstance.SaveData) ~= "function" then
        return commandError("MOD_DATA_API_UNAVAILABLE")
    end
    if payload ~= nil and type(payload) ~= "table" then
        return commandError("INVALID_COMMAND_PAYLOAD")
    end

    local json = loadJson()
    if json == nil then return commandError("JSON_UNAVAILABLE") end

    local session = nil
    if sessionModule ~= nil and type(sessionModule.Get) == "function" then
        local sessionOk, current = pcall(sessionModule.Get)
        if sessionOk then session = current end
    end
    if session == nil then session = inactiveSession() end

    local command = {
        id = nextCommandId(),
        type = commandType,
        playerId = session.playerId or DEFAULT_PLAYER_ID,
        payload = payload or {},
    }
    local root = {
        bridgeVersion = 1,
        matchSession = session,
        localBridge = {
            bridgeVersion = BRIDGE_VERSION,
            command = command,
        },
        launchRequest = {
            requested = false,
            matchId = session.matchId or "menu-bridge",
            token = "menu-bridge",
        },
    }

    local encodeOk, encoded = pcall(json.encode, root)
    if not encodeOk or encoded == nil then return commandError("JSON_ENCODE_ERROR") end
    local saveOk, saveError = pcall(modInstance.SaveData, modInstance, encoded)
    if not saveOk then return commandError("SAVE_DATA_ERROR: " .. tostring(saveError)) end

    lastCommand = command
    status = "COMMAND_WRITTEN"
    lastError = nil
    Isaac.DebugString(
        "[Isaac1v1] BRIDGE_COMMAND type=" .. quote(commandType) ..
        " id=" .. quote(command.id)
    )
    return command
end

function LocalBridge.GetStatus()
    return status
end

function LocalBridge.GetLastError()
    return lastError
end

function LocalBridge.GetLastCommand()
    return lastCommand
end

function LocalBridge.GetRuntimeState()
    return {
        companion = "UNKNOWN",
        backend = "UNKNOWN",
        limitation = "SAVE_DATA_COMMAND_ONLY",
    }
end

return LocalBridge
