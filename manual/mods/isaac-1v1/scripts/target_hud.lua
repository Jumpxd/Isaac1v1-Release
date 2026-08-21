local targetHud = {}

-- Vanilla gfx/ui/hudpickups.anm2, animation "Destination".
local VANILLA_DESTINATION_FRAMES = {
    MOM = 0,
    MOMS_HEART = 1,
    SATAN = 2,
    ISAAC = 3,
    THE_LAMB = 4,
    BLUE_BABY = 5,
    MEGA_SATAN = 6,
    MOTHER = 11,
    THE_BEAST = 12
}

local HUDPICKUPS_PATH = "gfx/ui/hudpickups.anm2"
local DESTINATION_ANIMATION = "Destination"

-- Sit beside the Hard Mode icon that vanilla already renders. This anchor
-- centers the combined pair beneath the pickup counters at the game's HUD scale.
local DESTINATION_POSITION = Vector(20, 75)
local HUD_OFFSET_SCALE = Vector(20, 12)
local TEXT_POSITION_FALLBACK = Vector(20, 75)

local destinationSprite = Sprite()
local assetsAttempted = false
local destinationSpriteReady = false

local function loadVanillaHudAssets()
    if assetsAttempted then return end
    assetsAttempted = true

    local destinationLoaded = pcall(destinationSprite.Load, destinationSprite, HUDPICKUPS_PATH, true)
    local destinationAnimationSet = destinationLoaded
        and pcall(destinationSprite.SetAnimation, destinationSprite, DESTINATION_ANIMATION, true)
    destinationSpriteReady = destinationAnimationSet == true
end

local function getHudOffset()
    local amount = Options ~= nil and tonumber(Options.HUDOffset) or 0
    return HUD_OFFSET_SCALE * (amount or 0)
end

local function isHudVisible()
    local ok, visible = pcall(function()
        return Game():GetHUD():IsVisible()
    end)
    return not ok or visible == true
end

local function renderFallback(name, position)
    pcall(Isaac.RenderText, "TARGET: " .. name, position.X, position.Y, 1, 1, 1, 1)
end

local function renderTarget(session)
    local destinationId = session.targetDestinationId
    local destinationName = session.targetDestinationName
    if type(destinationId) ~= "string" or destinationId == ""
        or type(destinationName) ~= "string" or destinationName == "" then return end

    loadVanillaHudAssets()

    local offset = getHudOffset()
    local frame = VANILLA_DESTINATION_FRAMES[destinationId]
    local iconRendered = false
    if destinationSpriteReady and frame ~= nil then
        local frameOk = pcall(destinationSprite.SetFrame, destinationSprite, frame)
        iconRendered = frameOk
            and pcall(destinationSprite.RenderLayer, destinationSprite, 0, DESTINATION_POSITION + offset)
    end

    if not iconRendered then
        renderFallback(destinationName, TEXT_POSITION_FALLBACK + offset)
    end
end

function targetHud.Register(mod, matchSession, competitiveRun)
    if mod == nil or ModCallbacks == nil then return false end
    local renderCallback = ModCallbacks.MC_POST_HUD_RENDER or ModCallbacks.MC_POST_RENDER
    if renderCallback == nil then return false end

    mod:AddCallback(renderCallback, function()
        if not isHudVisible() then return end
        if competitiveRun == nil or type(competitiveRun.IsActive) ~= "function" or not competitiveRun.IsActive() then return end
        local session = matchSession ~= nil and type(matchSession.Get) == "function" and matchSession.Get() or nil
        if type(session) ~= "table" or session.active ~= true then return end
        renderTarget(session)
    end)
    return true
end

return targetHud
