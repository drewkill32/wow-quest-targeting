-- Settings page under Options -> AddOns -> Select Quest Giver.
-- It only reads/writes SQG.db and calls SQG:NotifySettingsChanged(); the
-- modules that care react through SQG:OnSettingsChanged().
local ADDON_NAME, SQG = ...

local OptionsPanel = {}
SQG.OptionsPanel = OptionsPanel

local TITLE = "Select Quest Giver"
local LEFT = 16
local category

---------------------------------------------------------------------------
-- Small widget factories
---------------------------------------------------------------------------
local function Header(parent, text, anchor, offsetY)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -20)
    fs:SetText(text)
    return fs
end

local function Note(parent, text, anchor, offsetY)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -8)
    fs:SetWidth(560)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

-- get(): boolean, set(value)
local function Checkbox(parent, text, tooltip, anchor, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    local label = cb.Text or cb.text or cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:ClearAllPoints()
    label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    label:SetText(text)
    cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        SQG:NotifySettingsChanged()
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
    end
    return cb
end

local function IsKnownSpell(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        return C_Spell.GetSpellInfo(spell) ~= nil
    end
    return GetSpellInfo and GetSpellInfo(spell) ~= nil
end

local function SpellNameFromId(spellId)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellId)
    end
    return GetSpellInfo and (GetSpellInfo(spellId))
end

-- Accepts a spell link ("|Hspell:20271|h[Judgement]|h") or plain text.
local function SpellNameFromLink(link)
    local spellId = tonumber(link:match("|Hspell:(%d+)"))
    local name = spellId and SpellNameFromId(spellId)
    return name or link:match("%[(.-)%]") or link
end

local function SpellBox(parent, anchor)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -14)
    label:SetText("Spell to cast on hostile targets, for this character (empty = just target):")

    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -6)
    box:SetSize(220, 22)
    box:SetAutoFocus(false)

    local status = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("LEFT", box, "RIGHT", 10, 0)

    local function Save(self)
        local spell = strtrim(self:GetText() or "")
        SQG:SetHuntSpell(spell)
        if spell == "" or IsKnownSpell(spell) then
            status:SetText("")
        else
            status:SetText("|cffff8800Unknown spell - check spelling|r")
        end
        SQG:NotifySettingsChanged()
    end

    box:SetScript("OnShow", function(self)
        self:SetText(SQG:GetHuntSpell())
        status:SetText("")
    end)
    box:SetScript("OnEnterPressed", function(self)
        Save(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", Save)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(SQG:GetHuntSpell())
        self:ClearFocus()
    end)

    local function SetSpell(name)
        box:SetText(name)
        Save(box)
    end

    -- Shift-click in the spellbook: Blizzard sends the spell link to
    -- ChatEdit_InsertLink, so grab it while this box has focus.
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if box:HasFocus() and type(link) == "string" then
            SetSpell(SpellNameFromLink(link))
        end
    end)

    -- Drag a spell from the spellbook onto the box.
    local function OnReceiveDrag()
        local kind, _, _, spellId = GetCursorInfo()
        if kind == "spell" and spellId then
            local name = SpellNameFromId(spellId)
            if name then
                SetSpell(name)
            end
            ClearCursor()
        end
    end
    box:SetScript("OnReceiveDrag", OnReceiveDrag)
    box:HookScript("OnMouseDown", OnReceiveDrag) -- click-drop while carrying a spell

    local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -4)
    hint:SetText("Type a name or ID, drag a spell here, or click the box and Shift-click a spell in your spellbook.")

    return hint
end

-- Labelled slider bound to a setting.
---@param spec { name: string, min: number, max: number, step: number, lowText: string, highText: string,
---              label: fun(value): string, get: fun(): number, set: fun(value) }
local function Slider(parent, anchor, spec)
    local slider = CreateFrame("Slider", spec.name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -28)
    slider:SetWidth(220)
    slider:SetMinMaxValues(spec.min, spec.max)
    slider:SetValueStep(spec.step)
    slider:SetObeyStepOnDrag(true)
    local low = _G[spec.name .. "Low"]
    local high = _G[spec.name .. "High"]
    local text = _G[spec.name .. "Text"]
    if low then low:SetText(spec.lowText) end
    if high then high:SetText(spec.highText) end

    local function UpdateText(value)
        if text then
            text:SetText(spec.label(value))
        end
    end
    slider:SetScript("OnShow", function(self)
        self:SetValue(spec.get())
        UpdateText(spec.get())
    end)
    slider:SetScript("OnValueChanged", function(_, value, userInput)
        UpdateText(value)
        if userInput then
            spec.set(value)
            SQG:NotifySettingsChanged()
        end
    end)
    return slider
end

local function ScaleSlider(parent, anchor)
    return Slider(parent, anchor, {
        name = "SelectQuestGiverScaleSlider", min = 0.5, max = 2, step = 0.05, lowText = "50%", highText = "200%",
        label = function(value) return string.format("Button scale: %d%%", value * 100 + 0.5) end,
        get = function() return SQG.db.hunt.scale end,
        set = function(value) SQG.db.hunt.scale = value end,
    })
end

local function MenuHeightSlider(parent, anchor)
    return Slider(parent, anchor, {
        name = "SelectQuestGiverMenuHeightSlider", min = 200, max = 1000, step = 50, lowText = "200", highText = "1000",
        label = function(value) return string.format("Hunt menu max height: %d (scrolls past this)", value + 0.5) end,
        get = function() return SQG.db.hunt.menuHeight end,
        set = function(value) SQG.db.hunt.menuHeight = value end,
    })
end

-- Button that puts the self-updating "SQG Hunt" macro on the cursor.
local function ActionBarMacro(parent, anchor, menuCheckbox)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    local menu = menuCheckbox(button)
    button:SetSize(200, 22)
    button:SetText("Put macro on cursor")
    button:SetScript("OnClick", function() SQG.HuntMacroSync:Pickup() end)

    local note = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", menu, "BOTTOMLEFT", 0, -6)
    note:SetWidth(560)
    note:SetJustifyH("LEFT")
    note:SetText(string.format("Creates the character macro \"%s\" (or picks it up) so you can drop it on " ..
        "any action bar. It updates itself as your targets change. You can also drag the hunt button, " ..
        "or type /sqg macro. The right-click menu adds two lines to the macro, which leaves room for " ..
        "about one mob fewer.", SQG.HuntMacroSync.NAME))
    return note
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local CONTENT_WIDTH = 600
local CONTENT_HEIGHT = 1330

-- The page is taller than the settings canvas, so widgets live on a
-- scrolling content frame.
local function ScrollingContent(panel)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, CONTENT_HEIGHT)
    scroll:SetScrollChild(content)
    -- After a profile switch/copy/reset, re-show the widgets so each one
    -- re-reads its value (they all load in OnShow).
    SQG:OnProfileChanged(function()
        if content:IsVisible() then
            content:Hide()
            content:Show()
        end
    end)
    return content
end

local function BuildPanel()
    local outer = CreateFrame("Frame")
    outer.name = TITLE
    local panel = ScrollingContent(outer)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", LEFT, -16)
    title:SetText(TITLE)

    -- Profile ---------------------------------------------------------------
    local profiles = SQG.ProfilesSection:Create(panel, title)

    -- Minimap ---------------------------------------------------------------
    local minimapHeader = Header(panel, "Minimap", profiles, -28)
    local minimapButton = Checkbox(panel, "Show minimap button", "Click it to choose hunt targets.", minimapHeader,
        function() return not SQG.db.minimap.hide end, function(v) SQG.db.minimap.hide = not v end)

    -- Hunt button -----------------------------------------------------------
    local huntHeader = Header(panel, "Quest hunt button", minimapButton)
    local huntNote = Note(panel,
        "Right-click the button to check the mobs to hunt (from any quests). Each click (or keybind press) " ..
        "targets the first nearby mob in priority order, then attacks it. Change the order with " ..
        "\"Edit priority order...\" in that menu or /sqg list. Changes made in combat apply when combat ends.",
        huntHeader)
    local show = Checkbox(panel, "Show hunt button", nil, huntNote,
        function() return SQG.db.hunt.show end, function(v) SQG.db.hunt.show = v end)
    local lock = Checkbox(panel, "Lock position", "When unlocked, Shift+drag the button to move it.", show,
        function() return SQG.db.hunt.locked end, function(v) SQG.db.hunt.locked = v end)
    local attack = Checkbox(panel, "Start auto-attack on hostile targets", nil, lock,
        function() return SQG.db.hunt.autoAttack end, function(v) SQG.db.hunt.autoAttack = v end)
    local noDead = Checkbox(panel, "Add [nodead] to target lines",
        "Each target line becomes \"/tar [noexists,nodead] Name\". Uses 7 more characters per mob, " ..
        "so fewer mobs fit in the macro.", attack,
        function() return SQG.db.hunt.targetNoDead end, function(v) SQG.db.hunt.targetNoDead = v end)
    local spellBox = SpellBox(panel, noDead)
    local slider = ScaleSlider(panel, spellBox)
    local menuHeight = MenuHeightSlider(panel, slider)
    local keybind = Note(panel, "Keybind: Options -> Keybindings -> Select Quest Giver -> \"Hunt quest mob\".",
        menuHeight, -28)

    local barMacro = ActionBarMacro(panel, keybind, function(anchor)
        return Checkbox(panel, "Right-click the action bar macro to open the hunt menu", nil, anchor,
            function() return SQG.db.hunt.barMacroMenu end, function(v) SQG.db.hunt.barMacroMenu = v end)
    end)

    -- Hunt macro --------------------------------------------------------------
    SQG.MacroEditor:Create(panel, barMacro)

    return outer
end

function OptionsPanel:Register()
    local panel = BuildPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        category = panel
    end
end

function OptionsPanel:Open()
    if Settings and Settings.OpenToCategory and category and category.GetID then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(category)
        InterfaceOptionsFrame_OpenToCategory(category) -- twice: old Blizzard bug
    end
end
