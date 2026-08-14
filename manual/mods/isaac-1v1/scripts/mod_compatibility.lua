local compatibility = {}
local allowlist = include("scripts/competitive_mod_allowlist.lua")

local activeModProvider = nil
local lastLogSignature = nil

local function normalized(value)
    local result = tostring(value or ""):lower():gsub("\\", "/")
    result = result:gsub("_%d+$", "")
    result = result:gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return result
end

local byWorkshopId = {}
local byAlias = {}
for _, entry in ipairs(allowlist.entries) do
    byWorkshopId[tostring(entry.workshopId)] = entry
    byAlias[normalized(entry.canonicalName)] = entry
    for _, alias in ipairs(entry.aliases or {}) do byAlias[normalized(alias)] = entry end
end

local implicitAliases = {}
for _, alias in ipairs(allowlist.implicitAliases or {}) do implicitAliases[normalized(alias)] = true end

local function resolve(active)
    local workshopId = tostring(active.workshopId or active.id or "")
    if workshopId ~= "" and byWorkshopId[workshopId] ~= nil then return byWorkshopId[workshopId], false end
    for _, value in ipairs({active.folder, active.directory, active.displayName, active.name}) do
        local key = normalized(value)
        if key ~= "" and implicitAliases[key] then return nil, true end
        if key ~= "" and byAlias[key] ~= nil then return byAlias[key], false end
    end
    return nil, false
end

local function loadedModuleFallback()
    local active = {}
    if Isaac == nil or type(Isaac.GetLoadedModules) ~= "function" then return active, "UNAVAILABLE" end
    local ok, modules = pcall(Isaac.GetLoadedModules)
    if not ok or type(modules) ~= "table" then return active, "UNAVAILABLE" end
    local seen = {}
    for key, _ in pairs(modules) do
        local path = tostring(key):lower():gsub("\\", "/")
        local folder = path:match("mods/([^/]+)/")
        if folder ~= nil and not seen[folder] then
            seen[folder] = true
            active[#active + 1] = {folder = folder, displayName = folder}
        end
    end
    return active, "LOADED_MODULE_PATHS_FALLBACK"
end

local function logResult(active, allowed, conflicts)
    local keys = {}
    for _, item in ipairs(active) do keys[#keys + 1] = tostring(item.workshopId or item.folder or item.displayName or "") end
    table.sort(keys)
    local signature = table.concat(keys, "|")
    if signature == lastLogSignature then return end
    lastLogSignature = signature
    Isaac.DebugString('[Isaac1v1] COMPETITIVE_MOD_SCAN active_count="' .. tostring(#active) .. '"')
    for _, item in ipairs(allowed) do
        Isaac.DebugString('[Isaac1v1] COMPETITIVE_MOD_ALLOWED id="' .. tostring(item.canonicalId)
            .. '" name="' .. tostring(item.displayName):gsub('"', "'") .. '"')
    end
    for _, item in ipairs(conflicts) do
        Isaac.DebugString('[Isaac1v1] COMPETITIVE_MOD_BLOCKED id="' .. tostring(item.canonicalId)
            .. '" name="' .. tostring(item.displayName):gsub('"', "'") .. '"')
    end
end

function compatibility.SetActiveModProvider(provider)
    if provider ~= nil and type(provider) ~= "function" then return false end
    activeModProvider = provider
    return true
end

function compatibility.GetAllowedCanonicalIds()
    local ids = {}
    for _, entry in ipairs(allowlist.entries) do ids[#ids + 1] = tostring(entry.workshopId) end
    table.sort(ids)
    return ids
end

function compatibility.GetAllowedModMetadata()
    return allowlist.entries
end

function compatibility.GetCompetitiveModCompatibility()
    local active, detection = nil, "COMPANION_ENABLED_MOD_METADATA"
    if type(activeModProvider) == "function" then
        local ok, value = pcall(activeModProvider)
        if ok and type(value) == "table" then active = value end
    end
    if active == nil then active, detection = loadedModuleFallback() end

    local allowed, conflicts = {}, {}
    for _, item in ipairs(active) do
        local entry, implicit = resolve(item)
        if not implicit then
            if entry ~= nil then
                allowed[#allowed + 1] = {
                    canonicalId = entry.workshopId,
                    canonicalName = entry.canonicalName,
                    displayName = item.displayName or item.name or entry.canonicalName,
                }
            else
                conflicts[#conflicts + 1] = {
                    canonicalId = item.workshopId or item.id or normalized(item.folder or item.displayName),
                    displayName = item.displayName or item.name or item.folder or "Unknown mod",
                }
            end
        end
    end
    table.sort(allowed, function(a, b) return tostring(a.canonicalId) < tostring(b.canonicalId) end)
    table.sort(conflicts, function(a, b) return tostring(a.displayName) < tostring(b.displayName) end)
    logResult(active, allowed, conflicts)
    return {
        compatible = #conflicts == 0,
        activeAllowedMods = allowed,
        conflictingMods = conflicts,
        detection = detection,
    }
end

return compatibility
