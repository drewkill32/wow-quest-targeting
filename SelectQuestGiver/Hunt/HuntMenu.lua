-- Right-click menu of the hunt button: every huntable quest with its
-- objectives and mobs indented underneath, each with a checkbox. Mobs from
-- any number of quests can be checked at once.
--
-- Renders the view model from HuntController:GetModel() and reports clicks
-- through the callbacks; it never changes state itself. Checkbox states are
-- read live from HuntSelection so they update while the menu stays open.
local _, SQG = ...

local HuntMenu = {}
SQG.HuntMenu = HuntMenu

local QUEST_COLOR = "|cffffd100"
local OBJECTIVE_COLOR = "|cff9d9d9d"
local OVERFLOW_SUFFIX = " |cffff8800(chain full)|r"
local INDENT_OBJECTIVE = "      "
local INDENT_MOB = "         "

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
            for _, group in ipairs(quest.groups) do
                root:CreateTitle(INDENT_OBJECTIVE .. OBJECTIVE_COLOR .. group.label .. "|r")
                for _, mob in ipairs(group.mobs) do
                    KeepOpen(root:CreateCheckbox(INDENT_MOB .. MobLabel(mob),
                        function() return IsMobChecked(quest, mob) end,
                        function() callbacks.onMobToggled(quest.id, mob.name) end))
                end
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
            for _, group in ipairs(quest.groups) do
                AddTitle(OBJECTIVE_COLOR .. group.label .. "|r", 16)
                for _, mob in ipairs(group.mobs) do
                    AddCheckbox(MobLabel(mob),
                        function() return IsMobChecked(quest, mob) end,
                        function() callbacks.onMobToggled(quest.id, mob.name) end, 24)
                end
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
---@param callbacks { getModel: fun(), onQuestToggled: fun(questId), onMobToggled: fun(questId, name), onClearAll: fun(), onEditOrder: fun() }
function HuntMenu:Open(owner, callbacks)
    local model = callbacks.getModel()
    if MenuUtil and MenuUtil.CreateContextMenu then
        OpenModern(owner, model, callbacks)
    else
        OpenClassic(owner, model, callbacks)
    end
end
