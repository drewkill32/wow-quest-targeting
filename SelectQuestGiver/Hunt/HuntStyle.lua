-- Shared look for hunt views, so the menu, mob picker, priority window and
-- button tooltip mark the same states the same way.
--
-- A mob that is checked but didn't fit in the 255-character macro is shown
-- greyed out with a red X icon after its name. (WoW font strings can't do
-- strikethrough, so grey + icon is the clearest "not active" cue.)
local _, SQG = ...

local HuntStyle = {}
SQG.HuntStyle = HuntStyle

HuntStyle.OVERFLOW_ICON = "Interface\\RaidFrame\\ReadyCheck-NotReady"
HuntStyle.OVERFLOW_RGB = { 0.5, 0.5, 0.5 }
local GREY = "|cff808080"

-- Ability-style icons (the same set the macro icon picker uses) for
-- friendly-NPC targets. "kill" targets have none in lists and use the spell
-- icon on the button.
HuntStyle.KIND_ICONS = {
    turnin = "Interface\\Icons\\INV_Scroll_03",              -- quest scroll
    talk = "Interface\\Icons\\Ability_Warrior_BattleShout",  -- speaking face
}

HuntStyle.DEFAULT_ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"

local function SpellIcon(spell)
    if not spell or spell == "" then
        return nil
    end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spell)
    end
    return GetSpellTexture and GetSpellTexture(spell)
end

--- Icon for what a press does: the turn-in / talk icon when the top-priority
--- target is an NPC, otherwise the spell's icon (or the default). Shared by
--- the hunt button and the action bar macro. Returns a path or file ID.
function HuntStyle.ActionIcon(topKind)
    return HuntStyle.KIND_ICONS[topKind] or SpellIcon(SQG:GetHuntSpell()) or HuntStyle.DEFAULT_ICON
end

--- Inline icon for a target kind ("" for kill targets), cropped like an
--- action button so the icon's border doesn't show next to text.
function HuntStyle.KindIcon(kind, size)
    local texture = HuntStyle.KIND_ICONS[kind]
    if not texture then
        return ""
    end
    size = size or 0
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", texture, size, size)
end

--- Inline texture escape for the overflow icon (size 0 = font height).
function HuntStyle.OverflowIcon(size)
    return string.format("|T%s:%d|t", HuntStyle.OVERFLOW_ICON, size or 0)
end

--- Target name as shown in lists: prefixed with its kind's icon (talk /
--- turn-in), greyed out with the overflow icon when it didn't fit.
function HuntStyle.MobText(name, overflowed, kind, iconSize)
    local prefix = HuntStyle.KindIcon(kind, iconSize)
    if overflowed then
        return prefix .. GREY .. name .. "|r " .. HuntStyle.OverflowIcon(iconSize)
    end
    return prefix .. name
end

--- Short note explaining the icon, e.g. for summary lines and tooltips.
function HuntStyle.OverflowNote(count, iconSize)
    local noun = count == 1 and "mob doesn't" or "mobs don't"
    return string.format("%s %s%d checked %s fit in the macro|r",
        HuntStyle.OverflowIcon(iconSize), GREY, count, noun)
end

--- Tooltip lines listing the checked targets per quest (hunt button and
--- minimap button).
function HuntStyle.AddTargetLines(tooltip, model)
    if model.macro and model.macro.custom then
        tooltip:AddLine("Custom macro in use (set in Options)", 1, 0.53, 0)
    end
    if (model.activeQuests or 0) == 0 then
        tooltip:AddLine("Nothing checked", 0.6, 0.6, 0.6)
    end
    for _, quest in ipairs(model.quests or {}) do
        if quest.state ~= "none" then
            tooltip:AddLine(quest.title, 1, 0.82, 0)
            for _, group in ipairs(quest.groups) do
                for _, mob in ipairs(group.mobs) do
                    if mob.state ~= "off" then
                        tooltip:AddLine("  " .. HuntStyle.MobText(mob.name, mob.state == "overflow", mob.kind), 1, 1, 1)
                    end
                end
            end
        end
    end
end
