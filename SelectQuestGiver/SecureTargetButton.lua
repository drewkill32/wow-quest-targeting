-- The one secure button that actually performs the targeting.
-- Targeting is protected, so it can only happen from a click on a
-- SecureActionButton. We lay this button over the hovered pin so the
-- player's Ctrl+click lands on it.
local _, SQG = ...

local SecureTargetButton = {}
SQG.SecureTargetButton = SecureTargetButton

local button      -- the secure Button frame
local attachedPin -- the pin frame we're currently covering
local targetName  -- the NPC name the macro will target

local function CallPinScript(pin, scriptName)
    local script = pin and pin:GetScript(scriptName)
    if script then
        script(pin)
    end
end

local function OnEnter()
    -- Mouse focus moved from the pin to us; re-show the pin's tooltip.
    CallPinScript(attachedPin, "OnEnter")
end

local function OnLeave()
    CallPinScript(attachedPin, "OnLeave")
    SecureTargetButton:Detach()
end

-- The button is registered for both press and release, so one physical
-- click produces two PostClicks. Report the result only once per click.
local REPORT_DEBOUNCE = 0.5
local lastReportTime = 0

local function PreClick(self, mouseButton, down)
    SQG:Debug("PreClick button=%s down=%s useKeyDown=%s type=%s macrotext=%s",
        tostring(mouseButton), tostring(down),
        tostring(GetCVarBool("ActionButtonUseKeyDown")),
        tostring(SecureButton_GetModifiedAttribute(self, "type", mouseButton)),
        tostring(SecureButton_GetModifiedAttribute(self, "macrotext", mouseButton)))
end

local function PostClick(_, _, down)
    local expectedName = targetName
    SQG:Debug("PostClick down=%s target=%s", tostring(down), tostring(UnitName("target")))
    if not expectedName then
        return
    end
    -- Give the target change a frame to apply before checking it.
    C_Timer.After(0.1, function()
        if UnitName("target") == expectedName then
            SQG:Debug("Targeted %s", expectedName)
            return
        end
        local now = GetTime()
        if now - lastReportTime > REPORT_DEBOUNCE then
            lastReportTime = now
            SQG:Print("Could not target %s.", expectedName)
        end
    end)
end

function SecureTargetButton:Create()
    if button then
        return
    end
    button = CreateFrame("Button", "SelectQuestGiverTargetButton", UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    button:EnableMouse(true)
    -- Questie pins use fixed frame levels that can sit very high, so copying
    -- the pin's strata/level doesn't reliably put us on top. The TOOLTIP
    -- strata is above everything on the minimap; the button is invisible,
    -- pin-sized and only shown while Ctrl-hovering, so nothing else is blocked.
    button:SetFrameStrata("TOOLTIP")
    button:SetFrameLevel(10000)
    -- Unprefixed attribute names on purpose: with Ctrl held the secure
    -- template looks up "ctrl-type1", "*type1", "ctrl-type*", "*type*",
    -- then "type". It never checks "type1", so that name would be ignored.
    button:SetAttribute("type", "macro")
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", OnLeave)
    button:SetScript("PreClick", PreClick)
    button:SetScript("PostClick", PostClick)
    button:Hide()
end

function SecureTargetButton:IsAttachedTo(pin, unitName)
    return button:IsShown() and attachedPin == pin and targetName == unitName
end

function SecureTargetButton:AttachTo(pin, unitName)
    if InCombatLockdown() or self:IsAttachedTo(pin, unitName) then
        return
    end

    attachedPin = pin
    targetName = unitName

    button:SetAttribute("macrotext", "/targetexact " .. unitName)
    button:ClearAllPoints()
    button:SetAllPoints(pin)
    button:Show()

    SQG:Debug("Ready to target %s (pin %s/%d)", unitName, pin:GetFrameStrata(), pin:GetFrameLevel())
    C_Timer.After(0.1, function()
        local focus = GetMouseFoci and GetMouseFoci()[1]
        SQG:Debug("Under mouse: %s", focus and (focus:GetName() or "<unnamed>") or "nothing")
    end)
end

function SecureTargetButton:Detach()
    if not button or not button:IsShown() or InCombatLockdown() then
        return
    end
    button:Hide()
    button:ClearAllPoints()
    attachedPin = nil
    targetName = nil
end

function SecureTargetButton:GetAttachedPin()
    return attachedPin
end
