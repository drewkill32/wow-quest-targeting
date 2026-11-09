-- The on-screen hunt button: a movable SecureActionButton that runs the
-- macro built by HuntController. Left-click / keybind runs the macro,
-- right-click opens HuntMenu, drag picks up the action bar macro and
-- Shift+drag moves the button (when unlocked).
local _, SQG = ...

local HuntButton = {}
SQG.HuntButton = HuntButton

local BUTTON_NAME = "SelectQuestGiverHuntButton"
local SIZE = 40

local button, icon, label
local callbacks = {} -- from the controller: onOpenMenu(owner), onPickupMacro()
local model = { quests = {}, activeQuests = 0 } -- view model from HuntController

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function SavePosition()
    local point, _, relativePoint, x, y = button:GetPoint(1)
    SQG.db.hunt.position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function RestorePosition()
    local pos = SQG.db.hunt.position
    button:ClearAllPoints()
    if pos then
        button:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end
end

---------------------------------------------------------------------------
-- Scripts
---------------------------------------------------------------------------
local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Quest Hunt")
    SQG.HuntStyle.AddTargetLines(GameTooltip, model)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click / keybind: target (& attack mobs)", 0.43, 0.43, 0.43)
    GameTooltip:AddLine("Right-click: choose targets", 0.43, 0.43, 0.43)
    GameTooltip:AddLine("Drag: put the macro on an action bar", 0.43, 0.43, 0.43)
    if not SQG.db.hunt.locked then
        GameTooltip:AddLine("Shift-drag: move", 0.43, 0.43, 0.43)
    end
    GameTooltip:Show()
end

local function UpdateIcon()
    icon:SetTexture(SQG.HuntStyle.ActionIcon(model.topKind))
end

-- Text under the button: the one active quest, a count, or a hint.
local function SummaryText()
    if model.activeQuests == 0 then
        return "|cff888888Right-click to pick targets|r"
    end
    if model.activeQuests == 1 then
        for _, quest in ipairs(model.quests) do
            if quest.state ~= "none" then
                return quest.title
            end
        end
    end
    return string.format("%d quests", model.activeQuests)
end

-- Debug trace of each press: whether it runs, and what it targeted.
local function PreClick(self, mouseButton, down)
    SQG:Debug("Hunt click: %s %s, target before: %s", mouseButton, down and "down" or "up",
        UnitName("target") or "none")
end

local function PostClick(self, mouseButton, down)
    SQG:Debug("Hunt click done: target after: %s (macro %d chars)", UnitName("target") or "none",
        #(self:GetAttribute("*macrotext1") or ""))
    if mouseButton == "RightButton" and not down and not InCombatLockdown() then
        callbacks.onOpenMenu(button)
    end
end

local function OnDragStart(self)
    if InCombatLockdown() then
        return
    end
    if IsShiftKeyDown() then
        if not SQG.db.hunt.locked then
            self:StartMoving()
        end
    elseif callbacks.onPickupMacro then
        callbacks.onPickupMacro()
    end
end

local function OnDragStop(self)
    self:StopMovingOrSizing()
    SavePosition()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function HuntButton:Create(controllerCallbacks)
    callbacks = controllerCallbacks

    button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
    button:SetSize(SIZE, SIZE)
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp")
    -- "*" prefix = applies with any modifier held (Ctrl/Shift/Alt).
    button:SetAttribute("*type1", "macro")

    icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetPoint("CENTER")
    border:SetSize(SIZE * 1.65, SIZE * 1.65)

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", button, "BOTTOM", 0, -4)
    label:SetWidth(160)
    label:SetWordWrap(true)

    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("PreClick", PreClick)
    button:SetScript("PostClick", PostClick)
    button:SetScript("OnDragStart", OnDragStart)
    button:SetScript("OnDragStop", OnDragStop)

    RestorePosition()
    self:ApplySettings()
end

--- Applies show/scale/icon settings. Out of combat only (secure frame).
function HuntButton:ApplySettings()
    if InCombatLockdown() then
        return false
    end
    local settings = SQG.db.hunt
    button:SetScale(settings.scale)
    RestorePosition() -- each profile has its own position
    UpdateIcon()
    button:SetShown(settings.show)
    return true
end

--- Sets the macro and the view model. Out of combat only.
function HuntButton:SetHunt(macrotext, viewModel)
    if InCombatLockdown() then
        return false
    end
    button:SetAttribute("*macrotext1", macrotext)
    model = viewModel
    label:SetText(SummaryText())
    UpdateIcon()
    if GameTooltip:GetOwner() == button then
        ShowTooltip(button)
    end
    return true
end
