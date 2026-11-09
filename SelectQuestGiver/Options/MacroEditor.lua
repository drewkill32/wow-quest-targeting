-- "Hunt macro" section of the options page: shows the macro the hunt button
-- runs and lets the player replace it with their own text.
--
-- A view like the hunt windows: HuntController binds callbacks and calls
-- :Refresh(model) after every rebuild; the editor never changes state itself.
-- model.macro = { generated = string, custom = string?, active = string }
local _, SQG = ...

local MacroEditor = {}
SQG.MacroEditor = MacroEditor

local MAX_LENGTH = 255 -- WoW Forever's hard macro limit
local WIDTH = 560
local HEIGHT = 150

local callbacks = {}
local box, status, counter, saveButton, resetButton

local GREY = "|cff9d9d9d"
local ORANGE = "|cffff8800"

local function CurrentMacro()
    local model = callbacks.getCurrentModel and callbacks.getCurrentModel()
    return model and model.macro or { generated = "", active = "" }
end

-- Status line, counter and button states for the text in the box.
local function UpdateControls()
    local macro = CurrentMacro()
    local text = box:GetText() or ""
    local edited = text ~= macro.active

    counter:SetText(string.format("%s%d / %d|r", #text >= MAX_LENGTH and ORANGE or GREY, #text, MAX_LENGTH))
    if macro.custom then
        status:SetText(ORANGE .. "Custom macro in use.|r " .. GREY ..
            "Checked targets and the spell/auto-attack settings are ignored until you reset.|r")
    else
        status:SetText(GREY .. "Generated from your checked targets. Edit and save to use your own macro instead.|r")
    end
    saveButton:SetEnabled(edited and strtrim(text) ~= "")
    resetButton:SetEnabled(macro.custom ~= nil or edited)
end

-- Shows the active macro unless the player is in the middle of editing.
local function ShowActive(force)
    if not box then
        return
    end
    if force or not box:HasFocus() then
        box:SetText(CurrentMacro().active or "")
    end
    UpdateControls()
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
---@param controllerCallbacks { getCurrentModel: fun(), onSave: fun(text), onReset: fun() }
function MacroEditor:Bind(controllerCallbacks)
    callbacks = controllerCallbacks
end

--- Builds the section under `anchor` on the options page; returns the
--- bottom-most widget to anchor what follows.
function MacroEditor:Create(parent, anchor)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -28)
    header:SetText("Hunt macro")

    status = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    status:SetWidth(WIDTH)
    status:SetJustifyH("LEFT")

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -8)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(WIDTH - 40)
    box:SetMaxLetters(MAX_LENGTH)
    box:SetScript("OnTextChanged", UpdateControls)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ShowActive(true) -- discard unsaved edits
    end)
    box:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
        ScrollingEdit_OnCursorChanged(self, 0, y, 0, cursorHeight)
    end)
    box:SetScript("OnUpdate", function(self, elapsed)
        ScrollingEdit_OnUpdate(self, elapsed, scroll)
    end)
    scroll:SetScrollChild(box)
    -- Clicking anywhere in the frame focuses the text.
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function() box:SetFocus() end)

    saveButton = Button(parent, "Save custom macro", 150, function()
        box:ClearFocus()
        callbacks.onSave(box:GetText())
    end)
    saveButton:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -6)

    resetButton = Button(parent, "Reset to generated", 150, function()
        box:ClearFocus()
        callbacks.onReset()
        ShowActive(true)
    end)
    resetButton:SetPoint("LEFT", saveButton, "RIGHT", 8, 0)

    counter = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    counter:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -4, -10)

    local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", saveButton, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(WIDTH)
    hint:SetJustifyH("LEFT")
    hint:SetText("Escape discards unsaved edits. Changes made in combat apply when combat ends.")

    parent:HookScript("OnShow", function() ShowActive(true) end)
    return hint
end

--- View refresh after every rebuild.
function MacroEditor:Refresh()
    ShowActive(false)
end
