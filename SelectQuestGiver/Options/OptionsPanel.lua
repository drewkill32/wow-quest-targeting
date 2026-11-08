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
    label:SetText("Spell to cast on hostile targets (empty = just target):")

    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -6)
    box:SetSize(220, 22)
    box:SetAutoFocus(false)

    local status = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("LEFT", box, "RIGHT", 10, 0)

    local function Save(self)
        local spell = strtrim(self:GetText() or "")
        SQG.db.hunt.spell = spell
        if spell == "" or IsKnownSpell(spell) then
            status:SetText("")
        else
            status:SetText("|cffff8800Unknown spell - check spelling|r")
        end
        SQG:NotifySettingsChanged()
    end

    box:SetScript("OnShow", function(self)
        self:SetText(SQG.db.hunt.spell or "")
        status:SetText("")
    end)
    box:SetScript("OnEnterPressed", function(self)
        Save(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", Save)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(SQG.db.hunt.spell or "")
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

local function ScaleSlider(parent, anchor)
    local slider = CreateFrame("Slider", "SelectQuestGiverScaleSlider", parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -28)
    slider:SetWidth(220)
    slider:SetMinMaxValues(0.5, 2)
    slider:SetValueStep(0.05)
    slider:SetObeyStepOnDrag(true)
    local low = _G[slider:GetName() .. "Low"]
    local high = _G[slider:GetName() .. "High"]
    local text = _G[slider:GetName() .. "Text"]
    if low then low:SetText("50%") end
    if high then high:SetText("200%") end

    local function UpdateText(value)
        if text then
            text:SetText(string.format("Button scale: %d%%", value * 100 + 0.5))
        end
    end
    slider:SetScript("OnShow", function(self)
        self:SetValue(SQG.db.hunt.scale)
        UpdateText(SQG.db.hunt.scale)
    end)
    slider:SetScript("OnValueChanged", function(_, value, userInput)
        UpdateText(value)
        if userInput then
            SQG.db.hunt.scale = value
            SQG:NotifySettingsChanged()
        end
    end)
    return slider
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function BuildPanel()
    local panel = CreateFrame("Frame")
    panel.name = TITLE

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", LEFT, -16)
    title:SetText(TITLE)

    local db = SQG.db

    -- Minimap ---------------------------------------------------------------
    local minimapHeader = Header(panel, "Minimap pins", title)
    local enabled = Checkbox(panel, "Ctrl+click Questie minimap pins to target the NPC", nil, minimapHeader,
        function() return db.enabled end, function(v) db.enabled = v end)
    local hint = Checkbox(panel, "Show \"Ctrl-click to target\" in pin tooltips", nil, enabled,
        function() return db.tooltipHint end, function(v) db.tooltipHint = v end)

    -- Hunt button -----------------------------------------------------------
    local huntHeader = Header(panel, "Quest hunt button", hint)
    local huntNote = Note(panel,
        "Right-click the button to choose a quest. Each click (or keybind press) targets the nearest " ..
        "living mob you still need for that quest, then attacks it. Settings changed in combat apply when combat ends.",
        huntHeader)
    local show = Checkbox(panel, "Show hunt button", nil, huntNote,
        function() return db.hunt.show end, function(v) db.hunt.show = v end)
    local lock = Checkbox(panel, "Lock position", "When unlocked, Shift+drag the button to move it.", show,
        function() return db.hunt.locked end, function(v) db.hunt.locked = v end)
    local attack = Checkbox(panel, "Start auto-attack on hostile targets", nil, lock,
        function() return db.hunt.autoAttack end, function(v) db.hunt.autoAttack = v end)
    local spellBox = SpellBox(panel, attack)
    local slider = ScaleSlider(panel, spellBox)

    Note(panel, "Keybind: Options -> Keybindings -> Select Quest Giver -> \"Hunt quest mob\".",
        slider, -28)

    return panel
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
