-- Watches the mouse while Ctrl is held and tells SecureTargetButton
-- which pin (if any) it should cover.
local _, SQG = ...

local HoverController = {}
SQG.HoverController = HoverController

local POLL_INTERVAL = 0.05

local watcher = CreateFrame("Frame")
local elapsedSinceCheck = 0

local function GetHoveredFrame()
    if GetMouseFoci then
        return (GetMouseFoci())[1]
    end
    return GetMouseFocus and GetMouseFocus()
end

local function CanAct()
    return SQG.db and SQG.db.enabled and IsControlKeyDown() and not InCombatLockdown()
end

function HoverController:Update()
    local secureButton = SQG.SecureTargetButton

    if not CanAct() then
        secureButton:Detach()
        return
    end

    local hovered = GetHoveredFrame()
    if not hovered or hovered == SelectQuestGiverTargetButton then
        -- Already covering a pin (mouse is on our button) or nothing hovered.
        return
    end

    local unitName = SQG:ResolveUnitName(hovered)
    if unitName then
        secureButton:AttachTo(hovered, unitName)
    else
        secureButton:Detach()
    end
end

local function OnUpdate(_, elapsed)
    elapsedSinceCheck = elapsedSinceCheck + elapsed
    if elapsedSinceCheck < POLL_INTERVAL then
        return
    end
    elapsedSinceCheck = 0
    HoverController:Update()
end

function HoverController:Start()
    watcher:SetScript("OnUpdate", OnUpdate)
end

function HoverController:Stop()
    watcher:SetScript("OnUpdate", nil)
    SQG.SecureTargetButton:Detach()
end
