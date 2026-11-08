-- Adds a "Ctrl-click to target" hint to map pin tooltips for targetable NPCs.
local _, SQG = ...

local TooltipHint = {}
SQG.TooltipHint = TooltipHint

local HINT_TEXT = "Ctrl-click to target"
local HINT_COLOR = { r = 0.43, g = 0.43, b = 0.43 } -- matches Questie's gray hints

local hintAdded = false -- reset whenever the tooltip is cleared
local isAdding = false  -- guards against our own Show() re-entering the hook

local function ShouldShowHint(tooltip)
    if not SQG.db or not SQG.db.enabled or not SQG.db.tooltipHint or InCombatLockdown() then
        return false
    end
    return SQG:ResolveTooltipUnitName(tooltip) ~= nil
end

local function OnTooltipShow(tooltip)
    if isAdding or hintAdded or not ShouldShowHint(tooltip) then
        return
    end
    isAdding = true
    tooltip:AddLine(HINT_TEXT, HINT_COLOR.r, HINT_COLOR.g, HINT_COLOR.b)
    tooltip:Show() -- resize to fit the new line
    hintAdded = true
    isAdding = false
end

function TooltipHint:Install()
    GameTooltip:HookScript("OnTooltipCleared", function()
        hintAdded = false
    end)
    hooksecurefunc(GameTooltip, "Show", OnTooltipShow)
end
