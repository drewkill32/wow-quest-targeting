-- "Choose mobs" dialog: every mob for one quest, grouped by objective, with a
-- checkbox each and a search box. Opened from "More mobs..." in the hunt menu
-- for quests with more mobs than the menu shows.
--
-- A view: renders HuntController's model in :Refresh(model) and reports
-- clicks through callbacks; checkbox states are read live from HuntSelection.
local _, SQG = ...

local HuntMobPicker = {}
SQG.HuntMobPicker = HuntMobPicker

local WINDOW_NAME = "SelectQuestGiverMobPicker"
local WIDTH = 460
local HEIGHT = 560
local ROW_HEIGHT = 26
local PADDING = 12

local window, title, searchBox, scrollFrame, content, emptyText, countText
local rows = {}
local callbacks = {}
local questId = nil
local quest = nil -- this quest's entry in model.quests
local filter = ""

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Matches(name)
    return filter == "" or name:lower():find(filter, 1, true) ~= nil
end

-- Flat list of rows to show: objective headers followed by their mobs.
local function VisibleItems()
    local items = {}
    if not quest then
        return items
    end
    for _, group in ipairs(quest.groups) do
        local mobs = {}
        for _, mob in ipairs(group.mobs) do
            if Matches(mob.name) then
                mobs[#mobs + 1] = mob
            end
        end
        if #mobs > 0 then
            items[#items + 1] = { header = group.label }
            for _, mob in ipairs(mobs) do
                items[#items + 1] = { mob = mob }
            end
        end
    end
    return items
end

local function CheckedCount()
    local checked, total = 0, 0
    for _, group in ipairs(quest and quest.groups or {}) do
        for _, mob in ipairs(group.mobs) do
            total = total + 1
            if SQG.HuntSelection:IsIncluded(questId, mob.name) then
                checked = checked + 1
            end
        end
    end
    return checked, total
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function CreateRow(index)
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)

    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.header:SetPoint("LEFT", 4, -2)
    row.header:SetTextColor(0.62, 0.62, 0.62)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    row.check:SetPoint("LEFT", 16, 0)
    row.check:SetScript("OnClick", function()
        callbacks.onMobToggled(questId, row.mobName)
    end)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    return row
end

local function Render()
    local items = VisibleItems()
    for index, item in ipairs(items) do
        local row = rows[index] or CreateRow(index)
        rows[index] = row
        if item.header then
            row.header:SetText(item.header)
            row.header:Show()
            row.check:Hide()
            row.name:Hide()
        else
            local mob = item.mob
            row.mobName = mob.name
            row.header:Hide()
            row.check:Show()
            row.check:SetChecked(SQG.HuntSelection:IsIncluded(questId, mob.name))
            row.name:SetText(mob.name .. (mob.state == "overflow" and " |cffff8800(macro full)|r" or ""))
            row.name:Show()
        end
        row:Show()
    end
    for index = #items + 1, #rows do
        rows[index]:Hide()
    end
    content:SetHeight(math.max(1, #items * ROW_HEIGHT))
    emptyText:SetShown(#items == 0)

    local checked, total = CheckedCount()
    countText:SetText(string.format("%d of %d checked", checked, total))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- Check/uncheck every mob currently shown (respects the search filter).
local function SetAll(include)
    local names = {}
    for _, item in ipairs(VisibleItems()) do
        if item.mob then
            names[#names + 1] = item.mob.name
        end
    end
    callbacks.onSetMobs(questId, names, include)
end

local function SmallButton(text, onClick)
    local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    b:SetSize(90, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function CreateWindow()
    window = CreateFrame("Frame", WINDOW_NAME, UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER", 200, 0)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    tinsert(UISpecialFrames, WINDOW_NAME) -- close with Escape

    title = window.TitleText or window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not window.TitleText then
        title:SetPoint("TOP", 0, -5)
    end

    searchBox = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    searchBox:SetPoint("TOPLEFT", PADDING + 8, -32)
    searchBox:SetSize(WIDTH - 2 * PADDING - 16, 24)
    searchBox:SetAutoFocus(false)
    searchBox:HookScript("OnTextChanged", function(self)
        filter = strtrim(self:GetText() or ""):lower()
        Render()
    end)

    local checkAll = SmallButton("Check all", function() SetAll(true) end)
    checkAll:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -6, -6)
    local checkNone = SmallButton("None", function() SetAll(false) end)
    checkNone:SetPoint("LEFT", checkAll, "RIGHT", 6, 0)

    countText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countText:SetPoint("RIGHT", window, "RIGHT", -PADDING - 8, 0)
    countText:SetPoint("TOP", checkAll, "TOP", 0, -5)

    scrollFrame = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", checkAll, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -PADDING - 22, PADDING)

    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(WIDTH - 2 * PADDING - 34, 1)
    scrollFrame:SetScrollChild(content)

    emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetTextColor(0.6, 0.6, 0.6)
    emptyText:SetPoint("TOP", scrollFrame, "TOP", 0, -20)
    emptyText:SetText("No mobs match.")
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
---@param controllerCallbacks { getModel: fun(), onMobToggled: fun(questId, name), onSetMobs: fun(questId, names, include) }
function HuntMobPicker:Create(controllerCallbacks)
    callbacks = controllerCallbacks
    CreateWindow()
end

--- Opens the dialog for one quest.
function HuntMobPicker:Open(id)
    questId = id
    filter = ""
    searchBox:SetText("")
    window:Show()
    self:Refresh(callbacks.getModel())
end

function HuntMobPicker:Refresh(model)
    if not window or not window:IsShown() then
        return
    end
    quest = nil
    for _, entry in ipairs(model.quests or {}) do
        if entry.id == questId then
            quest = entry
        end
    end
    if not quest then
        window:Hide() -- quest finished or left the log
        return
    end
    title:SetText(string.format("Choose mobs: %s", quest.title or ""))
    Render()
end
