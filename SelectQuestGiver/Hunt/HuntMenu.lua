-- Right-click menu of the hunt button: every huntable quest with its
-- objectives and mobs indented underneath, each with a checkbox. Mobs from
-- any number of quests can be checked at once.
--
-- Each quest shows at most MAX_MOBS_PER_QUEST mobs (checked ones always
-- shown first); the rest are reached through "More mobs..." which opens
-- HuntMobPicker.
--
-- Renders the view model from HuntController:GetModel() and reports clicks
-- through the callbacks; it never changes state itself. Checkbox states are
-- read live from HuntSelection so they update while the menu stays open.
local _, SQG = ...

local HuntMenu = {}
SQG.HuntMenu = HuntMenu

local QUEST_COLOR = "|cffffd100"
local OBJECTIVE_COLOR = "|cff9d9d9d"
local OVERFLOW_SUFFIX = " |cffff8800(macro full)|r"
local INDENT_OBJECTIVE = "      "
local INDENT_MOB = "         "
local MAX_MOBS_PER_QUEST = 6

local function QuestLabel(quest)
    return string.format("%s[%d] %s|r", QUEST_COLOR, quest.level or 0, quest.title or ("Quest " .. quest.id))
end

local function MobNames(quest)
    local names = {}
    for _, group in ipairs(quest.groups) do
        for _, mob in ipairs(group.mobs) do
            names[#names + 1] = mob.name
        end
    end
    return names
end

local function IsQuestChecked(quest)
    return SQG.HuntSelection:GetQuestState(quest.id, MobNames(quest)) ~= "none"
end

local function IsMobChecked(quest, mob)
    return SQG.HuntSelection:IsIncluded(quest.id, mob.name)
end

local function MobLabel(mob)
    return mob.name .. (mob.state == "overflow" and OVERFLOW_SUFFIX or "")
end

--- The quest's groups trimmed to MAX_MOBS_PER_QUEST mobs: every checked mob,
--- then unchecked ones in list order to fill up. Returns groups and how many
--- mobs were left out.
local function VisibleGroups(quest)
    local shown, shownCount, total = {}, 0, 0
    for _, group in ipairs(quest.groups) do
        for _, mob in ipairs(group.mobs) do
            total = total + 1
            if IsMobChecked(quest, mob) then
                shown[mob] = true
                shownCount = shownCount + 1
            end
        end
    end
    for _, group in ipairs(quest.groups) do
        for _, mob in ipairs(group.mobs) do
            if shownCount >= MAX_MOBS_PER_QUEST then
                break
            end
            if not shown[mob] then
                shown[mob] = true
                shownCount = shownCount + 1
            end
        end
    end

    local groups = {}
    for _, group in ipairs(quest.groups) do
        local mobs = {}
        for _, mob in ipairs(group.mobs) do
            if shown[mob] then
                mobs[#mobs + 1] = mob
            end
        end
        if #mobs > 0 then
            groups[#groups + 1] = { label = group.label, mobs = mobs }
        end
    end
    return groups, total - shownCount
end

local function MoreLabel(hidden)
    return string.format("More mobs... |cff9d9d9d(%d more)|r", hidden)
end

-- Same setting as the options page checkbox; notifying rebuilds the macro.
local function IsAutoAttackOn()
    return SQG.db.hunt.autoAttack
end

local function ToggleAutoAttack()
    SQG.db.hunt.autoAttack = not SQG.db.hunt.autoAttack
    SQG:NotifySettingsChanged()
end

---------------------------------------------------------------------------
-- Modern Menu API (MenuUtil)
---------------------------------------------------------------------------
local function KeepOpen(element)
    if element and element.SetResponse and MenuResponse then
        element:SetResponse(MenuResponse.Refresh)
    end
    return element
end

local function OpenModern(owner, model, callbacks)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Hunt quest mobs")
        if #model.quests == 0 then
            root:CreateTitle(OBJECTIVE_COLOR .. "No quests with mobs to hunt|r")
        end

        for _, quest in ipairs(model.quests) do
            KeepOpen(root:CreateCheckbox(QuestLabel(quest),
                function() return IsQuestChecked(quest) end,
                function() callbacks.onQuestToggled(quest.id) end))
            local groups, hidden = VisibleGroups(quest)
            for _, group in ipairs(groups) do
                root:CreateTitle(INDENT_OBJECTIVE .. OBJECTIVE_COLOR .. group.label .. "|r")
                for _, mob in ipairs(group.mobs) do
                    KeepOpen(root:CreateCheckbox(INDENT_MOB .. MobLabel(mob),
                        function() return IsMobChecked(quest, mob) end,
                        function() callbacks.onMobToggled(quest.id, mob.name) end))
                end
            end
            if hidden > 0 then
                root:CreateButton(INDENT_MOB .. MoreLabel(hidden), function() callbacks.onPickMobs(quest.id) end)
            end
        end

        root:CreateDivider()
        root:CreateButton("Edit priority order...", callbacks.onEditOrder)
        KeepOpen(root:CreateCheckbox("Start auto-attack", IsAutoAttackOn, ToggleAutoAttack))
        root:CreateButton("Uncheck all", callbacks.onClearAll)
    end)
end

---------------------------------------------------------------------------
-- Fallback: classic UIDropDownMenu
---------------------------------------------------------------------------
local dropDown

local function AddTitle(text, padding)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.isTitle, info.notCheckable = text, true, true
    info.leftPadding = padding
    UIDropDownMenu_AddButton(info)
end

local function AddCheckbox(text, isChecked, onClick, padding)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.isNotRadio, info.keepShownOnClick = true, true
    info.checked = isChecked
    info.func = onClick
    info.leftPadding = padding
    UIDropDownMenu_AddButton(info)
end

local function OpenClassic(owner, model, callbacks)
    if not dropDown then
        dropDown = CreateFrame("Frame", "SelectQuestGiverHuntMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(dropDown, function()
        AddTitle("Hunt quest mobs")
        if #model.quests == 0 then
            AddTitle(OBJECTIVE_COLOR .. "No quests with mobs to hunt|r")
        end
        for _, quest in ipairs(model.quests) do
            AddCheckbox(QuestLabel(quest),
                function() return IsQuestChecked(quest) end,
                function() callbacks.onQuestToggled(quest.id) end)
            local groups, hidden = VisibleGroups(quest)
            for _, group in ipairs(groups) do
                AddTitle(OBJECTIVE_COLOR .. group.label .. "|r", 16)
                for _, mob in ipairs(group.mobs) do
                    AddCheckbox(MobLabel(mob),
                        function() return IsMobChecked(quest, mob) end,
                        function() callbacks.onMobToggled(quest.id, mob.name) end, 24)
                end
            end
            if hidden > 0 then
                local more = UIDropDownMenu_CreateInfo()
                more.text, more.notCheckable, more.leftPadding = MoreLabel(hidden), true, 24
                more.func = function() callbacks.onPickMobs(quest.id) end
                UIDropDownMenu_AddButton(more)
            end
        end
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable, info.func = "Edit priority order...", true, callbacks.onEditOrder
        UIDropDownMenu_AddButton(info)
        AddCheckbox("Start auto-attack", IsAutoAttackOn, ToggleAutoAttack)
        info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable, info.func = "Uncheck all", true, callbacks.onClearAll
        UIDropDownMenu_AddButton(info)
    end, "MENU")
    ToggleDropDownMenu(1, nil, dropDown, owner, 0, 0)
end

--- Opens the menu next to `owner`.
---@param callbacks { getModel: fun(), onQuestToggled: fun(questId), onMobToggled: fun(questId, name), onClearAll: fun(), onEditOrder: fun(), onPickMobs: fun(questId) }
function HuntMenu:Open(owner, callbacks)
    local model = callbacks.getModel()
    if MenuUtil and MenuUtil.CreateContextMenu then
        OpenModern(owner, model, callbacks)
    else
        OpenClassic(owner, model, callbacks)
    end
end
