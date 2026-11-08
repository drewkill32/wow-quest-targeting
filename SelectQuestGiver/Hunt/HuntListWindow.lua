-- "Hunt priority" window: the checked mobs in macro order. Reorder by
-- dragging a row, or with the up/down arrows; X unchecks the mob.
--
-- A view: renders HuntController's model in :Refresh(model) and reports user
-- actions through callbacks; it never changes state itself.
local _, SQG = ...

local HuntListWindow = {}
SQG.HuntListWindow = HuntListWindow

local WINDOW_NAME = "SelectQuestGiverHuntListWindow"
-- Roughly the size of the spellbook frame.
local WIDTH = 720
local ROW_HEIGHT = 30
local VISIBLE_ROWS = 14
local PADDING = 12
local ICON_SIZE = 22
local QUEST_WIDTH = 240

local window, scrollFrame, content, emptyText, dropLine, dragGhost
local rows = {}
local callbacks = {}
local entries = {} -- model.ordered: { { storeIndex, questId, name, questTitle, state } }

local drag = nil -- { from = position } while a row is being dragged

---------------------------------------------------------------------------
-- Dragging
---------------------------------------------------------------------------
-- Position (1..#entries + 1) the cursor is over, as an insertion slot.
local function SlotUnderCursor()
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / content:GetEffectiveScale()
    local offset = content:GetTop() - cursorY
    local slot = math.floor(offset / ROW_HEIGHT + 0.5) + 1
    return math.max(1, math.min(slot, #entries + 1))
end

local function UpdateDrag()
    if not drag then
        return
    end
    local slot = SlotUnderCursor()
    drag.slot = slot
    dropLine:ClearAllPoints()
    dropLine:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(slot - 1) * ROW_HEIGHT + 1)
    dropLine:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(slot - 1) * ROW_HEIGHT + 1)
    dropLine:Show()

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    dragGhost:ClearAllPoints()
    dragGhost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale)
end

local function StartDrag(row)
    drag = { from = row.position, slot = row.position }
    dragGhost:SetText(entries[row.position].name)
    dragGhost:Show()
    row:SetAlpha(0.4)
    window:SetScript("OnUpdate", UpdateDrag)
end

local function StopDrag(row)
    if not drag then
        return
    end
    window:SetScript("OnUpdate", nil)
    dropLine:Hide()
    dragGhost:Hide()
    row:SetAlpha(1)

    local from, slot = drag.from, drag.slot
    drag = nil
    -- Inserting at slot N after removing `from` shifts later slots up by one.
    local to = (slot > from) and (slot - 1) or slot
    if to ~= from then
        callbacks.onMove(entries[from].storeIndex, entries[to].storeIndex)
    end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function IconButton(parent, texture, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b:SetNormalTexture(texture .. "-Up")
    b:SetPushedTexture(texture .. "-Down")
    b:SetDisabledTexture(texture .. "-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function() onClick(parent) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function MoveBy(row, delta)
    local to = row.position + delta
    if entries[to] then
        callbacks.onMove(entries[row.position].storeIndex, entries[to].storeIndex)
    end
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    row:RegisterForDrag("LeftButton")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.04)
    end

    row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.number:SetPoint("LEFT", 4, 0)
    row.number:SetWidth(26)
    row.number:SetJustifyH("RIGHT")

    row.grip = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.grip:SetPoint("LEFT", row.number, "RIGHT", 6, 0)
    row.grip:SetText(":::")

    row.remove = IconButton(row, "Interface\\Buttons\\UI-MinusButton", "Remove from hunt",
        function(r) callbacks.onRemove(entries[r.position].storeIndex) end)
    row.remove:SetPoint("RIGHT", -4, 0)
    row.down = IconButton(row, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown", "Move down",
        function(r) MoveBy(r, 1) end)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.up = IconButton(row, "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp", "Move up",
        function(r) MoveBy(r, -1) end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)

    row.quest = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.quest:SetTextColor(0.65, 0.65, 0.65)
    row.quest:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
    row.quest:SetWidth(QUEST_WIDTH)
    row.quest:SetJustifyH("RIGHT")
    row.quest:SetWordWrap(false)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    row.name:SetPoint("LEFT", row.grip, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.quest, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnDragStart", StartDrag)
    row:SetScript("OnDragStop", StopDrag)
    row:SetScript("OnEnter", function(self)
        local entry = entries[self.position]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(entry.name)
        GameTooltip:AddLine(entry.questTitle, 1, 0.82, 0)
        if entry.state == "overflow" then
            GameTooltip:AddLine("Not in the macro: it is full (255 characters). Move this mob up to include it.", 1, 0.53, 0, true)
        end
        GameTooltip:AddLine("Drag to reorder. Higher rows are targeted first.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function RenderRows()
    for position, entry in ipairs(entries) do
        local row = rows[position] or CreateRow(position)
        rows[position] = row
        row.position = position
        row.number:SetText(position .. ".")
        row.name:SetText(entry.name)
        if entry.state == "overflow" then
            row.name:SetTextColor(1, 0.53, 0)
        else
            row.name:SetTextColor(1, 1, 1)
        end
        row.quest:SetText(entry.questTitle)
        row.up:SetEnabled(position > 1)
        row.down:SetEnabled(position < #entries)
        row:Show()
    end
    for position = #entries + 1, #rows do
        rows[position]:Hide()
    end
    content:SetHeight(math.max(1, #entries * ROW_HEIGHT))
    emptyText:SetShown(#entries == 0)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function CreateWindow()
    window = CreateFrame("Frame", WINDOW_NAME, UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(WIDTH, VISIBLE_ROWS * ROW_HEIGHT + 80)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    tinsert(UISpecialFrames, WINDOW_NAME) -- close with Escape

    local title = window.TitleText or window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not window.TitleText then
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("Hunt priority")

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetTextColor(0.75, 0.75, 0.75)
    hint:SetPoint("TOPLEFT", PADDING + 4, -34)
    hint:SetText("Top is targeted first. Drag rows or use the arrows.")

    scrollFrame = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", PADDING, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", -PADDING - 22, PADDING)

    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(WIDTH - 2 * PADDING - 26, 1)
    scrollFrame:SetScrollChild(content)

    emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    emptyText:SetTextColor(0.6, 0.6, 0.6)
    emptyText:SetPoint("TOP", scrollFrame, "TOP", 0, -20)
    emptyText:SetWidth(WIDTH - 60)
    emptyText:SetText("No mobs checked.\nRight-click the hunt button to pick some.")

    dropLine = content:CreateTexture(nil, "OVERLAY")
    dropLine:SetColorTexture(1, 0.82, 0, 0.9)
    dropLine:SetHeight(2)
    dropLine:Hide()

    dragGhost = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    dragGhost:SetTextColor(1, 0.82, 0)
    dragGhost:Hide()

    window:SetScript("OnShow", function()
        HuntListWindow:Refresh(callbacks.getModel())
    end)
    window:SetScript("OnHide", function()
        if drag then
            StopDrag(rows[drag.from])
        end
    end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
---@param controllerCallbacks { getModel: fun(), onMove: fun(fromStoreIndex, toStoreIndex), onRemove: fun(storeIndex) }
function HuntListWindow:Create(controllerCallbacks)
    callbacks = controllerCallbacks
    CreateWindow()
end

function HuntListWindow:Refresh(model)
    entries = model.ordered or {}
    if window and window:IsShown() and not drag then
        RenderRows()
    end
end

function HuntListWindow:Toggle()
    window:SetShown(not window:IsShown())
end
