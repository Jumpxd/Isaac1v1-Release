-- Pure Steam P2P message codec and validation helpers.
local protocol = {}

protocol.VERSION = "1"
protocol.BUILD = "0.2.0-alpha.1"
protocol.CATALOG = "production-catalog-1"
protocol.MAGIC = "I1V1P2P"

local function escape(value)
    return tostring(value):gsub("([^%w%-%._~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function unescape(value)
    local malformed = value:find("%%[^%x]", 1) or value:find("%%$", 1)
    if malformed then return nil end
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function protocol.Encode(messageType, fields)
    local keys = {}
    for key in pairs(fields or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = { protocol.MAGIC, tostring(messageType) }
    for _, key in ipairs(keys) do
        parts[#parts + 1] = escape(key) .. "=" .. escape(fields[key])
    end
    return table.concat(parts, "|")
end

function protocol.Decode(payload)
    if type(payload) ~= "string" or #payload > 4096 then return nil, "MALFORMED_MESSAGE" end
    local parts = {}
    for part in (payload .. "|"):gmatch("(.-)|") do parts[#parts + 1] = part end
    if parts[1] ~= protocol.MAGIC or type(parts[2]) ~= "string" or parts[2] == "" then
        return nil, "MALFORMED_MESSAGE"
    end
    local fields = {}
    for index = 3, #parts do
        local rawKey, rawValue = parts[index]:match("^([^=]+)=(.*)$")
        local key = rawKey and unescape(rawKey) or nil
        local value = rawValue and unescape(rawValue) or nil
        if key == nil or key == "" or value == nil or fields[key] ~= nil then
            return nil, "MALFORMED_MESSAGE"
        end
        fields[key] = value
    end
    return { type = parts[2], fields = fields }
end

function protocol.EncodeList(values)
    local result = {}
    for _, value in ipairs(values or {}) do result[#result + 1] = tostring(value) end
    return table.concat(result, ",")
end

function protocol.DecodeStringList(value)
    local result, seen = {}, {}
    if type(value) ~= "string" or value == "" then return result end
    for item in (value .. ","):gmatch("(.-),") do
        if item == "" or seen[item] then return nil end
        seen[item] = true
        result[#result + 1] = item
    end
    return result
end

function protocol.DecodeIntegerList(value)
    local strings = protocol.DecodeStringList(value)
    if strings == nil then return nil end
    local result = {}
    for _, item in ipairs(strings) do
        local number = tonumber(item)
        if number == nil or number % 1 ~= 0 then return nil end
        result[#result + 1] = number
    end
    return result
end

function protocol.Intersection(left, right)
    local available, result = {}, {}
    for _, value in ipairs(right or {}) do available[tostring(value)] = true end
    for _, value in ipairs(left or {}) do
        if available[tostring(value)] then result[#result + 1] = value end
    end
    table.sort(result, function(a, b) return tostring(a) < tostring(b) end)
    return result
end

function protocol.ValidateCapabilities(message, expectedPeerSteamId)
    if message == nil or message.type ~= "HELLO" then return nil, "EXPECTED_HELLO" end
    local fields = message.fields
    if fields.steam_id ~= tostring(expectedPeerSteamId) then return nil, "PEER_STEAM_ID_MISMATCH" end
    if fields.protocol ~= protocol.VERSION then return nil, "PROTOCOL_MISMATCH" end
    if type(fields.build) ~= "string" or fields.build == "" then return nil, "BUILD_MISSING" end
    if type(fields.catalog) ~= "string" or fields.catalog == "" then return nil, "CATALOG_MISSING" end
    if type(fields.persona) ~= "string" or fields.persona == "" then return nil, "PERSONA_MISSING" end
    local characters = protocol.DecodeIntegerList(fields.characters)
    local destinations = protocol.DecodeStringList(fields.destinations)
    if characters == nil or destinations == nil then return nil, "INVALID_CAPABILITIES" end
    return {
        steamId = fields.steam_id,
        protocol = fields.protocol,
        build = fields.build,
        catalog = fields.catalog,
        persona = fields.persona,
        characterTypes = characters,
        destinationIds = destinations,
    }
end

local function contains(values, expected)
    for _, value in ipairs(values or {}) do if value == expected then return true end end
    return false
end

function protocol.ValidateMatchConfig(message, context)
    if message == nil or message.type ~= "MATCH_CONFIG" then return nil, "EXPECTED_MATCH_CONFIG" end
    local fields = message.fields
    if tostring(context.senderSteamId) ~= tostring(context.frozenOwnerSteamId)
        or fields.authority_steam_id ~= tostring(context.frozenOwnerSteamId) then
        return nil, "AUTHORITY_MISMATCH"
    end
    if fields.lobby_id ~= tostring(context.lobbyId) then return nil, "LOBBY_ID_MISMATCH" end
    if type(fields.match_id) ~= "string" or fields.match_id == "" then return nil, "MATCH_ID_MISSING" end
    if fields.protocol ~= protocol.VERSION then return nil, "PROTOCOL_MISMATCH" end
    if type(fields.build) ~= "string" or fields.build == "" then return nil, "BUILD_MISSING" end
    if type(fields.catalog) ~= "string" or fields.catalog == "" then return nil, "CATALOG_MISSING" end
    if type(fields.seed) ~= "string" or fields.seed == "" then return nil, "SEED_MISSING" end
    local characterType = tonumber(fields.character)
    if characterType == nil or characterType % 1 ~= 0
        or not contains(context.sharedCharacters, characterType) then return nil, "CHARACTER_NOT_SHARED" end
    if not contains(context.sharedDestinations, fields.target_destination_id) then
        return nil, "DESTINATION_NOT_SHARED"
    end
    if type(fields.target_destination_name) ~= "string" or fields.target_destination_name == "" then
        return nil, "DESTINATION_NAME_MISSING"
    end
    return {
        matchId = fields.match_id,
        lobbyId = fields.lobby_id,
        authoritySteamId = fields.authority_steam_id,
        seed = fields.seed,
        characterType = characterType,
        targetDestinationId = fields.target_destination_id,
        targetDestinationName = fields.target_destination_name,
        protocol = fields.protocol,
        build = fields.build,
        catalog = fields.catalog,
    }
end

return protocol
