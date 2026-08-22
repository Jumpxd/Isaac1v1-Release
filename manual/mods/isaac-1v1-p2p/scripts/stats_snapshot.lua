-- Canonical, deterministic final snapshot shared by both Steam peers.
local stats = {}
local canonicalCharacters = include("scripts/canonical_character_catalog.lua")

local function jsonString(value)
    local text = tostring(value or "")
    text = text:gsub("[\0-\31\\\"]", function(character)
        local byte = string.byte(character)
        if character == "\\" then return "\\\\" end
        if character == '"' then return '\\"' end
        if character == "\b" then return "\\b" end
        if character == "\f" then return "\\f" end
        if character == "\n" then return "\\n" end
        if character == "\r" then return "\\r" end
        if character == "\t" then return "\\t" end
        return string.format("\\u%04x", byte)
    end)
    return '"' .. text .. '"'
end

function stats.RunTimeSeconds(value)
    if type(value) ~= "string" then return nil end
    local minutes, seconds = value:match("^(%d+):(%d%d)$")
    minutes, seconds = tonumber(minutes), tonumber(seconds)
    if minutes == nil or seconds == nil or seconds >= 60 then return nil end
    return (minutes * 60) + seconds
end

local function normalizedRunTime(value)
    return stats.RunTimeSeconds(value) ~= nil and value or "00:00"
end

function stats.Build(context)
    if type(context) ~= "table" or type(context.matchId) ~= "string"
        or type(context.completedAt) ~= "string" then return nil, "INVALID_STATS_CONTEXT" end
    local characterName = canonicalCharacters.GetName(context.characterType)
    if characterName == nil then return nil, "INVALID_STATS_CHARACTER" end
    local authorityRunTime = normalizedRunTime(context.authorityRunTime)
    local peerRunTime = normalizedRunTime(context.peerRunTime)
    local draw = context.isDraw == true
    local function resultFor(steamId)
        if draw then return "DRAW" end
        return steamId == context.winnerSteamId and "WIN" or "LOSS"
    end
    return {
        matchId = context.matchId,
        protocol = context.protocol,
        build = context.build,
        completedAt = context.completedAt,
        durationSeconds = math.max(
            stats.RunTimeSeconds(authorityRunTime) or 0,
            stats.RunTimeSeconds(peerRunTime) or 0),
        character = { type = context.characterType, name = characterName },
        target = { id = context.targetDestinationId, name = context.targetDestinationName },
        players = {
            {
                steamId = context.authoritySteamId,
                persona = context.authorityPersona,
                score = math.floor(tonumber(context.authorityScore) or 0),
                result = resultFor(context.authoritySteamId),
                runTime = authorityRunTime,
            },
            {
                steamId = context.peerSteamId,
                persona = context.peerPersona,
                score = math.floor(tonumber(context.peerScore) or 0),
                result = resultFor(context.peerSteamId),
                runTime = peerRunTime,
            },
        },
        terminalReason = context.terminalReason,
    }
end

local function playerJson(player)
    return "{" ..
        '"steamId":' .. jsonString(player.steamId) .. "," ..
        '"persona":' .. jsonString(player.persona) .. "," ..
        '"score":' .. tostring(player.score) .. "," ..
        '"result":' .. jsonString(player.result) .. "," ..
        '"runTime":' .. jsonString(player.runTime) ..
        "}"
end

function stats.Serialize(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.players) ~= "table"
        or #snapshot.players ~= 2 then return nil, "INVALID_STATS_SNAPSHOT" end
    return "{" ..
        '"matchId":' .. jsonString(snapshot.matchId) .. "," ..
        '"protocol":' .. jsonString(snapshot.protocol) .. "," ..
        '"build":' .. jsonString(snapshot.build) .. "," ..
        '"completedAt":' .. jsonString(snapshot.completedAt) .. "," ..
        '"durationSeconds":' .. tostring(snapshot.durationSeconds) .. "," ..
        '"character":{"type":' .. tostring(snapshot.character.type) ..
            ',"name":' .. jsonString(snapshot.character.name) .. "}," ..
        '"target":{"id":' .. jsonString(snapshot.target.id) ..
            ',"name":' .. jsonString(snapshot.target.name) .. "}," ..
        '"players":[' .. playerJson(snapshot.players[1]) .. "," ..
            playerJson(snapshot.players[2]) .. "]," ..
        '"terminalReason":' .. jsonString(snapshot.terminalReason) ..
        "}"
end

return stats
