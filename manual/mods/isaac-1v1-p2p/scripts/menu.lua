-- F8 UI for Steam P2P matchmaking, synchronized starts, and match results.
local menu = {}

local STATE_MAIN = "MAIN_1V1"
local STATE_SEARCHING = "SEARCHING"
local STATE_CANCELLING = "CANCELLING"
local STATE_MATCH_FOUND = "MATCH_FOUND"
local STATE_STARTING = "STARTING"
local STATE_ERROR = "ONLINE_ERROR"
local STATE_PENDING = "COMMAND_PENDING"
local STATE_RESULT = "RESULT"

local active = false
local state = STATE_MAIN
local selection = 1
local localReady = false
local localBridge = nil
local liveIPC = nil
local modCompatibility = nil
local runLauncher = nil
local pendingCommand = nil
local pendingError = nil
local pendingConflictName = nil
local previousMenu = nil
local previousInputMask = nil
local pollingOwnedInput = false
-- MC_MENU_INPUT_ACTION poate fi apelat înainte ca verificarea din randare să vadă
-- input-ul. Memorăm acțiunea deja procesată ca să nu selecteze READY încă o dată
-- în același frame.
local callbackActionConsumed = nil
local hostLayerRecords = {}
local hostLayersCaptured = false
local hostExtraRecords = {}
local hostExtrasCaptured = false
local resultSnapshot = nil
local resultMappingLoggedMatchId = nil

local function resetOpeningState()
    -- Șterge starea temporară a interfeței când meniul custom este deschis sau închis.
    -- Deschiderea din GAME începe mereu o sesiune nouă de meniu, fără comenzi vechi.
    state = STATE_MAIN
    selection = 1
    localReady = false
    pendingCommand = nil
    pendingError = nil
    pendingConflictName = nil
    callbackActionConsumed = nil
end

local font = Font()
local fontLoaded = false
local paperSprite = Sprite()
local paperLoaded = false
local backdropSprite = Sprite()
local backdropLoaded = false
local mainEntrySprite = Sprite()
local mainEntryLoaded = false
local avatarSprite = Sprite()
local avatarPathLoaded = nil
local avatarLoaded = false

-- Versiunea Alpha arată numai matchmaking-ul public. Suportul neterminat pentru
-- lobby este inactiv și nu poate fi accesat din meniul Production.
local mainOptions = {"FIND MATCH", "BACK"}
local searchingOptions = {"BACK - CANCEL"}
local matchFoundOptions = {"READY", "BACK - CANCEL"}
local startingOptions = {"BACK - CANCEL"}
local errorOptions = {"RETRY", "BACK"}
local leaveFailedOptions = {"BACK"}
local pendingOptions = {"BACK"}
local resultOptions = {"PLAY AGAIN", "BACK TO 1V1", "MAIN MENU"}

-- REPENTOGON acceptă ID-uri custom diferite de zero. Un ID separat împiedică
-- afișarea elementelor vanilla, dar păstrează randarea și comenzile meniului.
-- ID-ul 0 nu este folosit deoarece REPENTOGON îl rezervă intern.
local HOST_MENU = MainMenuType and 31031 or nil

local function getActiveMenu()
    if MenuManager == nil or type(MenuManager.IsActive) ~= "function"
        or type(MenuManager.GetActiveMenu) ~= "function" then
        return nil
    end

    local activeOk, managerActive = pcall(MenuManager.IsActive)
    if not activeOk or managerActive ~= true then return nil end

    local menuOk, menu = pcall(MenuManager.GetActiveMenu)
    if not menuOk then return nil end
    return menu
end

local function menuName(menu)
    if MainMenuType == nil then return "Unknown" end
    if menu == MainMenuType.GAME then return "GAME" end
    if menu == MainMenuType.BESTIARY then return "BESTIARY" end
    if menu == HOST_MENU then return "ISAAC_1V1" end
    if menu == MainMenuType.TITLE then return "TITLE" end
    if menu == MainMenuType.SAVES then return "SAVES" end
    return tostring(menu or "Unknown")
end

local function currentOptions()
    if state == STATE_MAIN then return mainOptions end
    if state == STATE_SEARCHING then return searchingOptions end
    if state == STATE_MATCH_FOUND then return matchFoundOptions end
    if state == STATE_STARTING then return startingOptions end
    if state == STATE_ERROR then return pendingError == "LEAVE_FAILED" and leaveFailedOptions or errorOptions end
    if state == STATE_PENDING then return pendingOptions end
    if state == STATE_RESULT then return resultOptions end
    return nil
end

local function logSelection(option)
    Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_SELECTION option=\"" .. option .. "\"")
end

local function captureAndHideSprite(sprite, sourceName)
    -- UI: memorează vizibilitatea imaginilor vanilla înainte să le ascundă,
    -- pentru ca exitContext să poată restaura meniul original.
    if sprite == nil or type(sprite.GetAllLayers) ~= "function" then return false end

    local layersOk, layers = pcall(sprite.GetAllLayers, sprite)
    if not layersOk or type(layers) ~= "table" then return false end

    local captured = false
    for _, layer in ipairs(layers) do
        if layer ~= nil and type(layer.IsVisible) == "function"
            and type(layer.SetVisible) == "function" then
            local alreadyRecorded = false
            for _, existing in ipairs(hostLayerRecords) do
                if existing.layer == layer then
                    alreadyRecorded = true
                    break
                end
            end
            if alreadyRecorded then
                pcall(layer.SetVisible, layer, false)
                captured = true
            else
                local visibleOk, wasVisible = pcall(layer.IsVisible, layer)
                if visibleOk then
                    table.insert(hostLayerRecords, {
                        layer = layer,
                        visible = wasVisible == true,
                        source = sourceName or "BestiaryMenu"
                    })
                    pcall(layer.SetVisible, layer, false)
                    local getterOk, getName = pcall(function() return layer.GetName end)
                    local nameOk, layerName = false, "UNKNOWN"
                    if getterOk and type(getName) == "function" then
                        nameOk, layerName = pcall(getName, layer)
                    end
                    Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_BESTIARY_LAYER source=\""
                        .. (sourceName or "BestiaryMenu") .. "\" name=\""
                        .. (nameOk and tostring(layerName) or "UNKNOWN") .. "\"")
                    captured = true
                end
            end
        end
    end
    return captured
end

local function hostKeyIsVisual(key)
    local name = string.lower(tostring(key or ""))
    return string.find(name, "sprite", 1, true) ~= nil
        or string.find(name, "tab", 1, true) ~= nil
        or string.find(name, "page", 1, true) ~= nil
        or string.find(name, "arrow", 1, true) ~= nil
        or string.find(name, "header", 1, true) ~= nil
        or string.find(name, "label", 1, true) ~= nil
        or string.find(name, "navigation", 1, true) ~= nil
end

local function captureHostValue(value, depth)
    if value == nil or depth > 2 then return false end
    if type(value) == "userdata" or type(value) == "table" then
        local directOk, directGetter = pcall(function() return value.GetAllLayers end)
        if directOk and type(directGetter) == "function" then
            local captureOk, captured = pcall(captureAndHideSprite, value)
            if captureOk and captured then return true end
        end
    end
    if type(value) ~= "table" then return false end
    local captured = false
    for key, child in pairs(value) do
        if hostKeyIsVisual(key) then
            if type(child) == "function" then
                local ok, result = pcall(child)
                if ok and result ~= nil and captureHostValue(result, depth + 1) then
                    captured = true
                end
            elseif captureHostValue(child, depth + 1) then
                captured = true
            end
        end
    end
    return captured
end

local function captureHostLayers()
    if hostLayersCaptured or BestiaryMenu == nil then return end

    local captured = false
    local getters = {
        -- Componentele de randare Bestiary documentate de REPENTOGON.
        "GetBestiaryMenuSprite",
        "GetEnemySprite",
        "GetDeathScreenSprite",
        -- Păstrează compatibilitatea cu versiunile care au imagini decorative separate.
        "GetBestiarySprite",
        "GetHeaderSprite",
        "GetTabsSprite",
        "GetPageSprite",
        "GetNavigationSprite",
        "GetArrowSprite"
    }

    for _, getterName in ipairs(getters) do
        local getter = BestiaryMenu[getterName]
        if type(getter) == "function" then
            local spriteOk, sprite = pcall(getter)
            if spriteOk and captureAndHideSprite(sprite, getterName) then
                captured = true
            end
        end
    end

    -- Unele versiuni REPENTOGON expun tab-uri și controale Bestiary cu alte nume.
    -- Sunt căutate numai câmpurile care par vizuale și sunt ascunse straturile lor,
    -- fără să fie ascuns fundalul global al meniului.
    local discoveredOk, discovered = pcall(function()
        return captureHostValue(BestiaryMenu, 0)
    end)
    if discoveredOk and discovered then captured = true end

    hostLayersCaptured = captured
    if captured then
        Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_HOST_UI_HIDDEN layers="
            .. tostring(#hostLayerRecords))
    end
end

local function captureAndHideRepentogonBestiaryExtras()
    if hostExtrasCaptured or REPENTOGON == nil or REPENTOGON.Extras == nil
        or type(REPENTOGON.Extras.BestiaryMenu) ~= "table" then
        return
    end

    local extras = REPENTOGON.Extras.BestiaryMenu
    local fields = {"BestiarySheetSpritePos", "PageWidgetPos", "PageTextPos"}
    for _, field in ipairs(fields) do
        local original = extras[field]
        if original ~= nil then
            table.insert(hostExtraRecords, {
                owner = extras,
                field = field,
                value = original
            })
            extras[field] = Vector(-10000, -10000)
        end
    end

    hostExtrasCaptured = #hostExtraRecords > 0
    if hostExtrasCaptured then
        Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_REPENTOGON_BESTIARY_EXTRAS_HIDDEN fields="
            .. tostring(#hostExtraRecords))
    end
end

local function enforceHostHidden()
    if HOST_MENU ~= MainMenuType.BESTIARY then return end
    captureHostLayers()
    captureAndHideRepentogonBestiaryExtras()
    for _, record in ipairs(hostLayerRecords) do
        if record.layer ~= nil and type(record.layer.SetVisible) == "function" then
            pcall(record.layer.SetVisible, record.layer, false)
        end
    end
    for _, record in ipairs(hostExtraRecords) do
        if record.owner ~= nil then
            record.owner[record.field] = Vector(-10000, -10000)
        end
    end
end

local function restoreHostLayers()
    if HOST_MENU ~= MainMenuType.BESTIARY then return end
    for _, record in ipairs(hostLayerRecords) do
        if record.layer ~= nil and type(record.layer.SetVisible) == "function" then
            pcall(record.layer.SetVisible, record.layer, record.visible)
        end
    end
    for _, record in ipairs(hostExtraRecords) do
        if record.owner ~= nil then
            record.owner[record.field] = record.value
        end
    end
    hostLayerRecords = {}
    hostLayersCaptured = false
    hostExtraRecords = {}
    hostExtrasCaptured = false
    Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_HOST_UI_RESTORED")
end

local function getCustomInputMask()
    if ButtonActionBitwise == nil then return nil end
    return ButtonActionBitwise.ACTION_MENUUP
        + ButtonActionBitwise.ACTION_MENUDOWN
        + ButtonActionBitwise.ACTION_MENUCONFIRM
        + ButtonActionBitwise.ACTION_MENUBACK
end

local function enterContext()
    -- Este apelată prin F8/Open din meniul vanilla GAME. Preia ID-ul de meniu și
    -- input-ul REPENTOGON, apoi deschide starea MAIN_1V1.
    if active or HOST_MENU == nil then return false end

    local currentMenu = getActiveMenu()
    if currentMenu ~= MainMenuType.GAME then return false end

    local inputMask = getCustomInputMask()
    if inputMask == nil then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: 1v1 menu input mask unavailable")
        return false
    end

    previousMenu = currentMenu
    previousInputMask = nil
    if type(MenuManager.GetInputMask) == "function" then
        local maskOk, mask = pcall(MenuManager.GetInputMask)
        if maskOk then previousInputMask = mask end
    end

    local menuOk = pcall(MenuManager.SetActiveMenu, HOST_MENU)
    if not menuOk then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: unable to enter 1v1 menu context")
        previousMenu = nil
        previousInputMask = nil
        return false
    end

    local maskOk = pcall(MenuManager.SetInputMask, inputMask)
    if not maskOk then
        pcall(MenuManager.SetActiveMenu, previousMenu)
        Isaac.DebugString("[Isaac1v1P2P] ERROR: unable to own 1v1 menu input")
        previousMenu = nil
        previousInputMask = nil
        return false
    end

    resetOpeningState()
    active = true
    enforceHostHidden()

    Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_CONTEXT_ENTER from=\""
        .. menuName(previousMenu) .. "\" to=\"" .. menuName(HOST_MENU) .. "\"")
    Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_OPENED state=\"MAIN_1V1\" selection=1")
    return true
end

local function exitContext()
    -- Restaurează meniul anterior, filtrul de comenzi și straturile vizuale ascunse.
    if not active then return end

    local targetMenu = previousMenu or MainMenuType.GAME
    restoreHostLayers()
    active = false
    resetOpeningState()

    pcall(MenuManager.SetActiveMenu, targetMenu)
    if previousInputMask ~= nil then
        pcall(MenuManager.SetInputMask, previousInputMask)
    end

    Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_CONTEXT_EXIT to=\""
        .. menuName(targetMenu) .. "\"")
    previousMenu = nil
    previousInputMask = nil
end

local function clearResult()
    -- RESULT: șterge atât copia locală afișată, cât și starea finală din liveIPC.
    resultSnapshot = nil
    if liveIPC ~= nil and type(liveIPC.ClearResult) == "function" then
        pcall(liveIPC.ClearResult)
    end
end

local function beginFindMatch()
    -- CICLUL MECIULUI: intrarea în coadă. Verifică mai întâi allowlist-ul, apoi
    -- trimite JOIN_QUEUE și trece UI-ul în SEARCHING dacă cererea reușește.
    if modCompatibility ~= nil and modCompatibility.GetCompetitiveModCompatibility ~= nil then
        local compatibilityOk, result = pcall(modCompatibility.GetCompetitiveModCompatibility)
        if compatibilityOk and result ~= nil and result.compatible == false then
            local conflict = type(result.conflictingMods) == "table" and result.conflictingMods[1] or nil
            pendingConflictName = type(conflict) == "table" and conflict.displayName or tostring(conflict or "")
            pendingError = "MOD_NOT_ALLOWED"
            state = STATE_ERROR
            selection = 1
            Isaac.DebugString('[Isaac1v1P2P] MATCHMAKING_BLOCKED reason="MOD_NOT_ALLOWED"')
            return
        end
    end
    if liveIPC == nil or type(liveIPC.JoinQueue) ~= "function" then
        pendingError = "P2P_COMPONENT_NOT_AVAILABLE"
        state = STATE_ERROR
        return
    end
    local joined, sent, errorMessage = pcall(liveIPC.JoinQueue)
    if joined and sent == true then
        state = STATE_SEARCHING
        selection = 1
        Isaac.DebugString("[Isaac1v1P2P] MENU_FIND_MATCH")
    else
        pendingError = errorMessage or "STEAM_P2P_UNAVAILABLE"
        state = STATE_ERROR
    end
end

local requestCancel

local function back()
    -- Acțiunea Back depinde de context: închide meniul sau cere anularea cozii/meciului.
    Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_BACK")
    if state == STATE_MAIN then
        exitContext()
    elseif state == STATE_SEARCHING then
        requestCancel()
    elseif state == STATE_MATCH_FOUND or state == STATE_STARTING then
        requestCancel()
    elseif state == STATE_CANCELLING then
        return
    else
        state = STATE_MAIN
        selection = 1
        Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_STATE state=\"MAIN_1V1\"")
    end
end

local function activateSelection()
    -- Execută opțiunea selectată. READY trimite MATCH_READY; opțiunile rezultatului
    -- curăță starea finală înainte de un meci nou sau de ieșirea din meniul 1v1.
    local options = currentOptions()
    if options == nil then return end
    local option = options[selection]
    if option == nil then return end
    logSelection(option)

    if state == STATE_MAIN then
        if option == "FIND MATCH" then
            Isaac.DebugString("[Isaac1v1P2P] MENU_FIND_MATCH")
            if liveIPC == nil or type(liveIPC.GetStatus) ~= "function"
                or type(liveIPC.JoinQueue) ~= "function" then
                pendingError = "P2P_COMPONENT_NOT_AVAILABLE"
                state = STATE_ERROR
                selection = 1
                return
            end
            local statusOk, status = pcall(liveIPC.GetStatus)
            if not statusOk or type(status) ~= "table"
                or status.transport ~= "READY" then
                pendingError = "STEAM_P2P_UNAVAILABLE"
                state = STATE_ERROR
                selection = 1
                return
            end
            beginFindMatch()
        else
            back()
        end
    elseif state == STATE_SEARCHING then
        requestCancel()
    elseif state == STATE_MATCH_FOUND then
        if option == "READY" then
            if liveIPC == nil or type(liveIPC.Ready) ~= "function" then
                pendingError = "P2P_COMPONENT_NOT_AVAILABLE"
                state = STATE_ERROR
            else
                local ok, sent, errorMessage = pcall(liveIPC.Ready)
                if not ok or sent ~= true then
                    pendingError = errorMessage or "PEER_SYNC_FAILED"
                    state = STATE_ERROR
                else
                    state = STATE_STARTING
                    Isaac.DebugString("[Isaac1v1P2P] MATCH_READY_SENT")
                end
            end
        else
            requestCancel()
        end
    elseif state == STATE_STARTING then
        requestCancel()
    elseif state == STATE_ERROR then
        if option == "RETRY" then
            Isaac.DebugString("[Isaac1v1P2P] MENU_FIND_MATCH")
            beginFindMatch()
        else
            back()
        end
    elseif state == STATE_PENDING then
        if option == "BACK" then
            back()
        end
    elseif state == STATE_RESULT then
        if option == "PLAY AGAIN" then
            clearResult()
            state = STATE_MAIN
            selection = 1
            beginFindMatch()
        elseif option == "BACK TO 1V1" then
            clearResult()
            state = STATE_MAIN
            selection = 1
            Isaac.DebugString("[Isaac1v1P2P] MATCH_RESULT_BACK_TO_1V1")
        else
            clearResult()
            exitContext()
        end
    end
end

requestCancel = function()
    -- Transport: SEARCHING folosește LEAVE_QUEUE, iar MATCH_FOUND/STARTING folosește
    -- MATCH_CANCEL. UI-ul așteaptă răspunsul IDLE înainte să revină la MAIN_1V1.
    if liveIPC == nil then
        pendingError = "P2P_COMPONENT_NOT_AVAILABLE"
        state = STATE_ERROR
        selection = 1
        return
    end
    local cancellingState = state
    if cancellingState == STATE_MATCH_FOUND or cancellingState == STATE_STARTING then
        Isaac.DebugString("[Isaac1v1P2P] MENU_MATCH_CANCEL_REQUEST state=\"" .. cancellingState .. "\"")
    elseif cancellingState == STATE_SEARCHING then
        Isaac.DebugString("[Isaac1v1P2P] MENU_QUEUE_CANCEL_REQUEST state=\"SEARCHING\"")
    end
    local cancel = (cancellingState == STATE_MATCH_FOUND or cancellingState == STATE_STARTING)
        and liveIPC.CancelMatch or liveIPC.LeaveQueue
    if type(cancel) ~= "function" then
        pendingError = "P2P_COMPONENT_NOT_AVAILABLE"
        state = STATE_ERROR
        selection = 1
        return
    end
    local leaveOk, sent, leaveError = pcall(cancel)
    if leaveOk and sent == true then
        state = STATE_CANCELLING
        selection = 1
    else
        pendingError = leaveError or "STEAM_P2P_UNAVAILABLE"
        state = STATE_ERROR
        selection = 1
    end
end

local function handleAction(action)
    if action == ButtonAction.ACTION_MENUBACK then
        back()
        return
    end

    local options = currentOptions()
    if action == ButtonAction.ACTION_MENUUP and options ~= nil then
        selection = selection - 1
        if selection < 1 then selection = #options end
    elseif action == ButtonAction.ACTION_MENUDOWN and options ~= nil then
        selection = selection + 1
        if selection > #options then selection = 1 end
    elseif action == ButtonAction.ACTION_MENUCONFIRM then
        activateSelection()
    end
end

local function isActionTriggeredAll(action)
    if Input == nil or type(Input.IsActionTriggered) ~= "function" then return false end

    pollingOwnedInput = true
    for controllerIndex = 0, 3 do
        local inputOk, triggered = pcall(Input.IsActionTriggered, action, controllerIndex)
        if inputOk and triggered == true then
            pollingOwnedInput = false
            return true
        end
    end
    pollingOwnedInput = false
    return false
end

local function processOwnedInput()
    -- Verifică toate controllerele locale și nu procesează de două ori o acțiune
    -- deja preluată de MC_MENU_INPUT_ACTION în același frame.
    if callbackActionConsumed ~= nil then
        callbackActionConsumed = nil
        return
    end
    if isActionTriggeredAll(ButtonAction.ACTION_MENUBACK) then
        handleAction(ButtonAction.ACTION_MENUBACK)
    elseif isActionTriggeredAll(ButtonAction.ACTION_MENUUP) then
        handleAction(ButtonAction.ACTION_MENUUP)
    elseif isActionTriggeredAll(ButtonAction.ACTION_MENUDOWN) then
        handleAction(ButtonAction.ACTION_MENUDOWN)
    elseif isActionTriggeredAll(ButtonAction.ACTION_MENUCONFIRM) then
        handleAction(ButtonAction.ACTION_MENUCONFIRM)
    end
end

local function renderText(text, x, y, color)
    if not fontLoaded then return end
    font:DrawStringUTF8(text, x, y, color, 0, false)
end

local function menuPosition(menu, x, y)
    if Isaac ~= nil and type(Isaac.WorldToMenuPosition) == "function" then
        local positionOk, position = pcall(Isaac.WorldToMenuPosition, menu, Vector(x, y))
        if positionOk and position ~= nil then return position end
    end
    return Vector(x, y)
end

local function renderCenteredText(text, centerX, y, color)
    if not fontLoaded then return end
    local widthOk, width = pcall(font.GetStringWidthUTF8, font, text)
    if not widthOk or type(width) ~= "number" then width = 0 end
    renderText(text, centerX - (width / 2), y, color)
end

local function renderMainMenuEntry()
    local center = menuPosition(MainMenuType.GAME, 350, 70)
    if mainEntryLoaded then
        pcall(function()
            mainEntrySprite.Scale = Vector(0.42, 0.22)
            mainEntrySprite:Render(center)
        end)
    end

    local color = KColor(0.20, 0.15, 0.10, 1)
    local accent = KColor(0.75, 0.25, 0.10, 1)
    renderCenteredText("ISAAC 1V1", center.X, center.Y - 12, color)
    renderCenteredText("[F8] OPEN", center.X, center.Y + 7, accent)
end

local function playerPersona(player)
    local name = player ~= nil and player.displayName or nil
    if type(name) ~= "string" or name == "" then return "PLAYER" end
    -- Păstrează numele în zona sigură a meniului și nu afișează SteamID-ul ca rezervă.
    if #name > 24 then return string.sub(name, 1, 23) .. "…" end
    return name
end

local function renderAvatar(player, x, y)
    -- HUD/UI: afișează numai avataruri ale căror căi au fost aprobate de extensia nativă.
    local path = player ~= nil and player.avatar or nil
    if type(path) ~= "string" or path == "" then return end
    if type(Isaac1v1P2P) ~= "table" or type(Isaac1v1P2P.IsSteamAvatarPath) ~= "function" then return end
    local safeOk, safe = pcall(Isaac1v1P2P.IsSteamAvatarPath, path)
    if not safeOk or safe ~= true then return end
    if avatarPathLoaded ~= path then
        avatarLoaded = false
        avatarPathLoaded = path
        local loaded = pcall(function()
            avatarSprite:Load("gfx/ui/isaac_1v1_avatar.anm2", true)
            avatarSprite:ReplaceSpritesheet(0, path, false)
            avatarSprite:LoadGraphics()
            avatarSprite:SetFrame("Idle", 0)
        end)
        avatarLoaded = loaded
        if not loaded then Isaac.DebugString("[Isaac1v1P2P] STEAM_AVATAR_UNAVAILABLE reason=\"SPRITE_LOAD_FAILED\"") end
    end
    if avatarLoaded then
        pcall(function()
            avatarSprite.Scale = Vector(0.5, 0.5)
            avatarSprite:Render(Vector(x, y))
        end)
    end
end

local function renderDedicatedScreen()
    -- Actualizează și desenează starea principală a UI-ului. Transportul decide
    -- SEARCHING/MATCH_FOUND/STARTING/RESULT, iar o eroare de launch oprește STARTING.
    local inputMask = getCustomInputMask()
    if inputMask ~= nil then
        pcall(MenuManager.SetInputMask, inputMask)
    end
    enforceHostHidden()
    if backdropLoaded then
        pcall(function()
            backdropSprite.Scale = Vector(1.95, 1.15)
            backdropSprite:Render(Vector(240, 135))
        end)
    end
    if paperLoaded then
        pcall(function()
            if state == STATE_RESULT then
                paperSprite.Scale = Vector(1.08, 1.16)
            else
                paperSprite.Scale = Vector(1, 1)
            end
            paperSprite:Render(Vector(240, 135))
        end)
    end

    local color = KColor(0.20, 0.15, 0.10, 1)
    local selectedColor = KColor(0.75, 0.25, 0.10, 1)

    local ipcStatus = {
        component = "NOT INSTALLED",
        transport = "UNAVAILABLE",
        player = nil,
        queue = "IDLE",
        match = nil,
        error = nil
    }
    if liveIPC ~= nil and type(liveIPC.GetStatus) == "function" then
        local statusOk, status = pcall(liveIPC.GetStatus)
        if statusOk and type(status) == "table" then ipcStatus = status end
    end

    if ipcStatus.queue == "STARTING" then
        if state ~= STATE_STARTING then selection = 1 end
        state = STATE_STARTING
    elseif ipcStatus.queue == "RESULT" or resultSnapshot ~= nil then
        state = STATE_RESULT
        selection = math.min(selection, #resultOptions)
        if ipcStatus.result ~= nil then resultSnapshot = ipcStatus.result end
    elseif ipcStatus.queue == "MATCH_FOUND" then
        if state ~= STATE_MATCH_FOUND and state ~= STATE_STARTING then
            selection = 1
        end
        if state ~= STATE_STARTING then state = STATE_MATCH_FOUND end
    elseif state == STATE_CANCELLING and ipcStatus.queue == "IDLE" then
        state = STATE_MAIN
        selection = 1
        Isaac.DebugString("[Isaac1v1P2P] MENU_1V1_STATE state=\"MAIN_1V1\"")
        Isaac.DebugString("[Isaac1v1P2P] QUEUE_CANCELLED")
        Isaac.DebugString("[Isaac1v1P2P] MENU_LEAVE_QUEUE_COMPLETE")
    elseif (state == STATE_SEARCHING or ipcStatus.queue == "SEARCHING")
        and ipcStatus.queue == "SEARCHING" then
        state = STATE_SEARCHING
    elseif ipcStatus.queue == "ERROR" and state ~= STATE_MAIN then
        state = STATE_ERROR
        pendingError = ipcStatus.error
        selection = 1
    end
    if runLauncher ~= nil and type(runLauncher.GetStatus) == "function"
        and type(runLauncher.GetLastError) == "function" then
        local launcherOk, launcherStatus = pcall(runLauncher.GetStatus)
        local errorOk, launcherError = pcall(runLauncher.GetLastError)
        if launcherOk and launcherStatus == "ERROR" and errorOk
            and type(launcherError) == "string" and launcherError ~= "" then
            state = STATE_ERROR
            pendingError = launcherError
            selection = 1
        end
    end
    if state == STATE_CANCELLING and liveIPC ~= nil and type(liveIPC.GetLeaveElapsed) == "function" then
        local elapsedOk, elapsed = pcall(liveIPC.GetLeaveElapsed)
        if elapsedOk and type(elapsed) == "number" and elapsed >= 7 then
            state = STATE_ERROR
            pendingError = "LEAVE_FAILED"
            selection = 1
            Isaac.DebugString("[Isaac1v1P2P] QUEUE_LEAVE_TIMEOUT elapsed=\"" .. tostring(math.floor(elapsed)) .. "\"")
        end
    end

    if state ~= STATE_RESULT then
        renderText("ISAAC 1V1", 205, 42, color)
    end

    local subtitle = nil
    if state == STATE_SEARCHING then subtitle = "SEARCHING FOR OPPONENT" end
    if state == STATE_CANCELLING then subtitle = "LEAVING QUEUE" end
    if state == STATE_MATCH_FOUND then subtitle = "MATCH FOUND" end
    if state == STATE_STARTING then subtitle = "STARTING MATCH..." end
    if state == STATE_ERROR then subtitle = "ONLINE ERROR" end
    if state == STATE_PENDING then subtitle = "COMMAND SENT" end
    if state == STATE_RESULT then subtitle = nil end
    if subtitle ~= nil then renderText(subtitle, 165, 66, color) end

    local options = currentOptions()
    local optionStartY = 118
    if state == STATE_MAIN then optionStartY = 96 end
    if state == STATE_SEARCHING then optionStartY = 172 end
    if state == STATE_MATCH_FOUND then optionStartY = 190 end
    if state == STATE_ERROR then optionStartY = 166 end
    if options ~= nil and state ~= STATE_RESULT then
        for index, option in ipairs(options) do
            local prefix = index == selection and "> " or "  "
            renderText(prefix .. option, 178, optionStartY + ((index - 1) * 28),
                index == selection and selectedColor or color)
        end
    end

    if state == STATE_SEARCHING then
        local dots = string.rep(".", (math.floor(Isaac.GetTime() / 500) % 3) + 1)
        renderText("SEARCHING" .. dots, 190, 112, color)
    elseif state == STATE_CANCELLING then
        renderText("WAITING FOR PEER", 186, 116, color)
    elseif state == STATE_MATCH_FOUND then
        local match = ipcStatus.match or {}
        renderText("OPPONENT: " .. tostring(match.opponentPersonaName or "FOUND"), 164, 88, color)
        renderText("CHARACTER: " .. tostring(match.characterName or "ISAAC"), 169, 112, color)
        renderText("SEED: " .. tostring(match.seed or "---- ----"), 181, 134, color)
        local players = (ipcStatus.matchControl and ipcStatus.matchControl.players) or {}
        local you = "NOT READY"
        local opponent = "NOT READY"
        local playerId = ipcStatus.player and ipcStatus.player.playerId
        for _, player in ipairs(players) do
            if player.playerId == playerId and player.state == "READY" then you = "READY" end
            if player.playerId ~= playerId and player.state == "READY" then opponent = "READY" end
        end
        renderText("YOU: " .. you, 198, 158, color)
        renderText("OPPONENT: " .. opponent, 180, 178, color)
    elseif state == STATE_STARTING then
        renderText("SYNCING MATCH SETTINGS", 158, 144, color)
    elseif state == STATE_ERROR then
        local message = pendingError == "P2P_COMPONENT_NOT_AVAILABLE" and "P2P COMPONENT NOT INSTALLED"
            or pendingError == "STEAM_P2P_UNAVAILABLE" and "STEAM P2P UNAVAILABLE"
            or pendingError == "PEER_SYNC_FAILED" and "MATCH SYNC FAILED"
            or pendingError == "STEAM_IDENTITY_NOT_FOUND" and "STEAM UNAVAILABLE"
            or pendingError == "MOD_NOT_ALLOWED" and "MOD NOT ALLOWED"
            or pendingError == "MOD_CONFIGURATION_CHANGED" and "MOD CONFIGURATION CHANGED"
            or pendingError == "LEAVE_FAILED" and "LEAVE FAILED"
            or tostring(pendingError or "ONLINE ERROR")
        renderText(message, 170, 112, selectedColor)
        if pendingError == "MOD_NOT_ALLOWED" then
            if pendingConflictName ~= nil and pendingConflictName ~= "" then
                local display = tostring(pendingConflictName):upper()
                if #display > 34 then display = display:sub(1, 31) .. "..." end
                renderText(display, 170, 136, selectedColor)
                renderText("CHECK THE LIST OF ALLOWED MODS", 140, 158, color)
            else
                renderText("CHECK THE LIST OF ALLOWED MODS", 140, 142, color)
            end
        elseif pendingError == "MOD_CONFIGURATION_CHANGED" then
            renderText("RESTORE THE ALLOWED MOD SET", 150, 142, color)
        end
    elseif state == STATE_PENDING then
        renderText("REQUESTING LOBBY", 180, 112, color)
        if pendingError ~= nil then
            renderText("CONNECTION UNAVAILABLE", 160, 140, selectedColor)
        else
            renderText("PLEASE WAIT", 195, 140, color)
        end
    elseif state == STATE_MAIN then
        if ipcStatus.component ~= "INSTALLED" or ipcStatus.transport ~= "READY" then
            renderText("P2P COMPONENT NOT INSTALLED", 145, 72, selectedColor)
        else
            renderAvatar(ipcStatus.player, 164, 79)
            renderText("PLAYER: " .. playerPersona(ipcStatus.player), 184, 72, color)
        end
    elseif state == STATE_RESULT then
        -- RESULT: compară câștigătorul și cauza finală cu playerul Steam local,
        -- apoi afișează VICTORY, DEFEAT sau DRAW.
        local result = resultSnapshot or ipcStatus.result or {}
        local playerId = ipcStatus.player and ipcStatus.player.playerId
        local ownScore, opponentScore = "UNKNOWN", "UNKNOWN"
        local opponentPlayerId = result.opponentId
        for _, entry in ipairs(result.results or {}) do
            if tostring(entry.playerId) == tostring(playerId) then
                ownScore = tostring(entry.score)
            else
                opponentScore = tostring(entry.score)
                if opponentPlayerId == nil then opponentPlayerId = entry.playerId end
            end
        end
        local computedResult
        if result.terminalReason == "DEATH" or result.terminalReason == "WRONG_DESTINATION" then
            computedResult = tostring(result.terminalPlayerId) == tostring(playerId) and "LOSS" or "WIN"
        elseif result.isDraw == true then
            computedResult = "DRAW"
        elseif result.localResult == "WIN" or result.localResult == "LOSS" or result.localResult == "DRAW" then
            computedResult = result.localResult
        else
            computedResult = tostring(result.winnerPlayerId) == tostring(playerId) and "WIN" or "LOSS"
        end
        if resultMappingLoggedMatchId ~= result.matchId then
            resultMappingLoggedMatchId = result.matchId
            Isaac.DebugString("[Isaac1v1P2P] RESULT_MAPPING local_player_id=\"" .. tostring(playerId)
                .. "\" opponent_player_id=\"" .. tostring(opponentPlayerId)
                .. "\" winner_player_id=\"" .. tostring(result.winnerPlayerId)
                .. "\" terminal_player_id=\"" .. tostring(result.terminalPlayerId)
                .. "\" terminal_reason=\"" .. tostring(result.terminalReason)
                .. "\" local_score=\"" .. ownScore
                .. "\" opponent_score=\"" .. opponentScore
                .. "\" computed_local_result=\"" .. computedResult .. "\"")
        end
        local title = computedResult == "DRAW" and "DRAW" or (computedResult == "WIN" and "VICTORY" or "DEFEAT")
        local reason
        if result.terminalReason == "DEATH" then
            reason = result.terminalPlayerId == playerId and "YOU DIED" or "OPPONENT DIED"
        elseif result.terminalReason == "WRONG_DESTINATION" then
            reason = result.terminalPlayerId == playerId and "WRONG DESTINATION" or "OPPONENT CHOSE WRONG DESTINATION"
        elseif result.terminalReason == "ABANDON" then
            reason = result.terminalPlayerId == playerId and "YOU ABANDONED" or "OPPONENT ABANDONED"
        elseif result.terminalReason == "ABANDON_BOTH" then
            reason = "BOTH PLAYERS DISCONNECTED"
        else
            reason = "RUN COMPLETED - SCORE"
        end
        -- Rezultatul folosește toată foaia: un singur titlu, zone verticale fixe
        -- și navigare deasupra indicațiilor vanilla de jos.
        renderCenteredText("ISAAC 1V1", 240, 40, color)
        renderCenteredText(title, 240, 58, selectedColor)
        renderCenteredText("YOUR SCORE", 240, 78, color)
        renderCenteredText(ownScore, 240, 91, color)
        renderCenteredText("OPPONENT SCORE", 240, 107, color)
        renderCenteredText(opponentScore, 240, 120, color)
        renderCenteredText("RESULT: " .. computedResult, 240, 137, color)
        renderCenteredText("REASON: " .. reason, 240, 150, color)
        renderCenteredText("CHARACTER: " .. string.upper(tostring(result.character or result.characterName or "ISAAC")), 240, 168, color)
        renderCenteredText("SEED: " .. tostring(result.seed or "---- ----"), 240, 181, color)
        renderCenteredText(tostring(result.difficulty or "HARD") .. " / " .. tostring(result.mode or result.gameMode or "STANDARD"), 240, 194, color)
        for index, option in ipairs(resultOptions) do
            local prefix = index == selection and "> " or "  "
            renderCenteredText(prefix .. option, 240, 209 + ((index - 1) * 13),
                index == selection and selectedColor or color)
        end
    end
end

function menu.Open()
    -- Funcția publică folosită de F8; întoarce dacă deschiderea meniului a reușit.
    return enterContext()
end

function menu.ShowResult(result)
    -- Este apelată de match_result după acceptarea MATCH_RESULT_FINAL. Păstrează o
    -- copie pentru ca rezultatul să rămână disponibil după ieșirea din run.
    if type(result) ~= "table" or type(result.matchId) ~= "string" then return false end
    resetOpeningState()
    resultSnapshot = result
    if active then
        state = STATE_RESULT
        selection = 1
    end
    Isaac.DebugString("[Isaac1v1P2P] MATCH_RESULT_MENU_PENDING match_id=\"" .. result.matchId .. "\"")
    return true
end

function menu.BeginNewMatch(matchId)
    -- Un ID nou invalidează toate prompturile, selecțiile și rezultatele vechi.
    if type(matchId) ~= "string" or matchId == "" then return false end
    resultSnapshot = nil
    resultMappingLoggedMatchId = nil
    resetOpeningState()
    return true
end

function menu.ResetTerminal()
    resultSnapshot = nil
    resultMappingLoggedMatchId = nil
    resetOpeningState()
    return true
end

local function renderMenu()
    -- MC_MAIN_MENU_RENDER: afișează indicația F8, deschide automat un rezultat în
    -- așteptare, procesează input-ul și desenează ecranul 1v1.
    local currentMenu = getActiveMenu()

    if not active then
        if resultSnapshot ~= nil and currentMenu == MainMenuType.GAME then
            Isaac.DebugString("[Isaac1v1P2P] MAIN_MENU_CONTEXT_READY menu=\"GAME\"")
            if enterContext() then
                state = STATE_RESULT
                selection = 1
                Isaac.DebugString("[Isaac1v1P2P] RESULT_MENU_OPENED match_id=\"" .. tostring(resultSnapshot.matchId) .. "\"")
            end
            return
        end
        if currentMenu ~= MainMenuType.GAME then return end
        if Input ~= nil and Keyboard ~= nil
            and type(Input.IsButtonTriggered) == "function"
            and Keyboard.KEY_F8 ~= nil
            and Input.IsButtonTriggered(Keyboard.KEY_F8, 0) then
            menu.Open()
            return
        end

        renderMainMenuEntry()
        return
    end

    if currentMenu ~= HOST_MENU then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: 1v1 menu context ownership lost")
        exitContext()
        return
    end

    processOwnedInput()
    if not active then return end
    renderDedicatedScreen()
end

local function isOwnedAction(action)
    return action == ButtonAction.ACTION_MENUUP
        or action == ButtonAction.ACTION_MENUDOWN
        or action == ButtonAction.ACTION_MENUCONFIRM
        or action == ButtonAction.ACTION_MENUBACK
end

local function onMenuInput(_, hook, action)
    -- MC_MENU_INPUT_ACTION: controlează navigarea cât timp meniul custom este activ
    -- și împiedică meniul vanilla să folosească același input.
    if not active or not isOwnedAction(action) then return nil end
    if pollingOwnedInput then return nil end

    if hook == InputHook.IS_ACTION_TRIGGERED then
        -- Procesează Back/Escape direct la intrarea în meniu, fără să depindă de
        -- opțiunea selectată. REPENTOGON folosește aceeași cale pentru Cancel pe controller.
        if callbackActionConsumed == action then return false end
        callbackActionConsumed = action
        handleAction(action)
        return false
    end

    if hook == InputHook.IS_ACTION_PRESSED then return false end
    if hook == InputHook.GET_ACTION_VALUE then return 0 end
    return nil
end

function menu.Register(mod, bridge, transport, compatibility, launcher)
    -- Încarcă fișierele UI, păstrează legăturile către module și înregistrează cele
    -- două callback-uri. Bridge-ul local vechi este verificat, dar matchmaking-ul folosește Steam P2P.
    localBridge = bridge
    liveIPC = transport
    modCompatibility = compatibility
    runLauncher = launcher
    if Font == nil or Sprite == nil then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: dedicated 1v1 menu rendering API unavailable")
        return
    end

    if HOST_MENU == nil or ButtonActionBitwise == nil
        or MenuManager == nil or type(MenuManager.SetActiveMenu) ~= "function"
        or type(MenuManager.SetInputMask) ~= "function" then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: dedicated 1v1 menu context API unavailable")
        return
    end

    local fontOk = pcall(function()
        font:Load("font/teammeatex/teammeatex10.fnt")
        fontLoaded = font:IsLoaded()
    end)
    if not fontOk or not fontLoaded then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: dedicated 1v1 menu font unavailable")
    end

    local paperOk = pcall(function()
        paperSprite:Load("gfx/ui/isaac_1v1_menu_paper.anm2", true)
        paperSprite:SetFrame("Idle", 0)
        paperLoaded = #paperSprite:GetDefaultAnimation() > 0
        backdropSprite:Load("gfx/ui/isaac_1v1_menu_paper.anm2", true)
        backdropSprite:SetFrame("Idle", 0)
        backdropLoaded = #backdropSprite:GetDefaultAnimation() > 0
        mainEntrySprite:Load("gfx/ui/isaac_1v1_menu_paper.anm2", true)
        mainEntrySprite:SetFrame("Idle", 0)
        mainEntryLoaded = #mainEntrySprite:GetDefaultAnimation() > 0
    end)
    if not paperOk or not paperLoaded or not backdropLoaded or not mainEntryLoaded then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: dedicated 1v1 paper asset unavailable")
    end

    if ModCallbacks.MC_MAIN_MENU_RENDER == nil
        or ModCallbacks.MC_MENU_INPUT_ACTION == nil then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: dedicated 1v1 menu callbacks unavailable")
        return
    end

    mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, renderMenu)
    mod:AddCallback(ModCallbacks.MC_MENU_INPUT_ACTION, onMenuInput)
    if localBridge == nil then
        Isaac.DebugString("[Isaac1v1P2P] ERROR: in-game menu local bridge unavailable")
    end
    Isaac.DebugString("[Isaac1v1P2P] Dedicated 1v1 menu initialized host=\"ISAAC_1V1\"")
end

return menu
