-- Keeps a regular character macro ("SQG Hunt") in step with the hunt macro,
-- so the player can put it on any action bar like their own macros.
--
-- A view like the hunt windows: HuntController calls :Refresh(model) after
-- every rebuild (always out of combat, which EditMacro needs too).
-- The macro is only created when the player asks for it (dragging the hunt
-- button or the options button); if they delete it, it stays deleted.
--
-- Right-click on the action bar copy (option "barMacroMenu"): the macro starts with
-- HuntMacroBuilder.MENU_LINES. "/sqg menu" calls :OnMenuCommand, which opens
-- the menu only for a right-click, and "/stopmacro [btn:2]" then stops the
-- macro before it targets anything.
local _, SQG = ...

local HuntMacroSync = {}
SQG.HuntMacroSync = HuntMacroSync

HuntMacroSync.NAME = "SQG Hunt" -- macro names are capped at 16 characters

local callbacks = {}
local model -- last model from the controller
local ready = false -- macros aren't readable until the world has loaded
local existed -- whether the macro existed at the last check

local events = CreateFrame("Frame")

local function MacroIndex()
    if not ready then
        return 0
    end
    return GetMacroIndexByName(HuntMacroSync.NAME) or 0
end

-- EditMacro / CreateMacro take a file ID or an icon name; our kind icons
-- are paths.
local function IconValue(texture)
    if type(texture) == "string" and GetFileIDFromPath then
        return GetFileIDFromPath(texture) or texture
    end
    return texture
end

local function MenuEnabled()
    return SQG.db.hunt.barMacroMenu
end

-- Text for the action bar copy: the active macro, plus the right-click
-- lines when that option is on (a custom macro gets them when they fit).
local function BarText()
    local text = model and model.macro and model.macro.active or ""
    if not MenuEnabled() then
        return text
    end
    return SQG.HuntMacroBuilder.WithRightClickMenu(text)
end

local function BarIcon()
    return IconValue(SQG.HuntStyle.ActionIcon(model and model.topKind))
end

local function Write(index)
    local _, icon, body = GetMacroInfo(index)
    local text, newIcon = BarText(), BarIcon()
    if body ~= text or icon ~= newIcon then
        EditMacro(index, HuntMacroSync.NAME, newIcon, text)
        SQG:Debug("Updated action bar macro \"%s\"", HuntMacroSync.NAME)
    end
end

-- Creating or deleting the macro changes whether the generated macro needs
-- the right-click lines, so the controller rebuilds.
local function CheckExistence()
    local exists = MacroIndex() > 0
    if exists ~= existed then
        existed = exists
        if callbacks.onAvailabilityChanged then
            callbacks.onAvailabilityChanged()
        end
    end
end

local function Create()
    local _, numCharacter = GetNumMacros()
    local max = MAX_CHARACTER_MACROS or 18
    if numCharacter >= max then
        SQG:Print("Your character macros are full (%d/%d). Delete one to add \"%s\".", numCharacter, max,
            HuntMacroSync.NAME)
        return 0
    end
    local index = CreateMacro(HuntMacroSync.NAME, BarIcon(), BarText(), true)
    if index and index > 0 then
        SQG:Print("Created character macro \"%s\" - it updates itself as your targets change.", HuntMacroSync.NAME)
    end
    return index or 0
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
---@param controllerCallbacks { onAvailabilityChanged: fun(), onOpenMenu: fun(owner) }
function HuntMacroSync:Bind(controllerCallbacks)
    callbacks = controllerCallbacks
end

--- True when the action bar macro exists.
function HuntMacroSync:IsActive()
    return MacroIndex() > 0
end

--- True when the generated macro should start with the right-click lines:
--- the action bar macro exists and the option is on. The lines cost room,
--- so they're left out otherwise.
function HuntMacroSync:WantsRightClickMenu()
    return MenuEnabled() and self:IsActive()
end

--- View refresh after every rebuild.
function HuntMacroSync:Refresh(newModel)
    model = newModel
    if InCombatLockdown() then
        return
    end
    local index = MacroIndex()
    if index > 0 then
        Write(index)
    end
end

--- Puts the macro on the cursor (creating it first if needed), ready to
--- drop on an action bar.
function HuntMacroSync:Pickup()
    if InCombatLockdown() then
        SQG:Print("Can't pick up macros in combat.")
        return
    end
    if not ready then
        return
    end
    local index = MacroIndex()
    if index == 0 then
        index = Create()
        if index == 0 then
            return
        end
        CheckExistence() -- rebuilds with the right-click lines
    end
    PickupMacro(index)
end

-- True only when the macro was run by a right-click. Checked two ways
-- because keybinds and left-clicks run the same line and must do nothing.
local function IsRightClick()
    if GetMouseButtonClicked and GetMouseButtonClicked() == "RightButton" then
        return true
    end
    return SecureCmdOptionParse ~= nil and SecureCmdOptionParse("[btn:2] yes") == "yes"
end

--- "/sqg menu": runs on every press of the action bar macro, but only a
--- right-click opens the menu.
function HuntMacroSync:OnMenuCommand()
    if not IsRightClick() or InCombatLockdown() then
        return
    end
    local owner
    if GetMouseFoci then
        owner = GetMouseFoci()[1]
    elseif GetMouseFocus then
        owner = GetMouseFocus()
    end
    if not owner or owner == WorldFrame then
        owner = UIParent
    end
    callbacks.onOpenMenu(owner)
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_MACROS")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        ready = true
    end
    if ready and not InCombatLockdown() then
        CheckExistence()
    end
end)
