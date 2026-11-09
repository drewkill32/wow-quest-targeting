-- "Profile" section of the options page: shows the active profile and lets
-- the player switch, create, copy, delete or reset profiles.
-- All profile logic lives in Core/ProfileStore; this only presents it.
local _, SQG = ...

local ProfilesSection = {}
SQG.ProfilesSection = ProfilesSection

local CONFIRM_POPUP = "SELECTQUESTGIVER_CONFIRM"
local WHITE = "|cffffffff"

local activeText

StaticPopupDialogs[CONFIRM_POPUP] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, onAccept) onAccept() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Confirm(text, onAccept)
    StaticPopup_Show(CONFIRM_POPUP, text, nil, onAccept)
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Profile names other than the active one.
local function OtherProfiles()
    local names = {}
    for _, name in ipairs(SQG:GetProfileNames()) do
        if name ~= SQG:GetProfileName() then
            names[#names + 1] = name
        end
    end
    return names
end

-- Opens a menu listing `names`; picking one calls onPick(name).
local function PickMenu(owner, title, names, onPick)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        if #names == 0 then
            root:CreateTitle("|cff9d9d9dNo other profiles|r")
        end
        for _, name in ipairs(names) do
            root:CreateButton(name, function() onPick(name) end)
        end
    end)
end

local function SwitchMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Use profile")
        for _, name in ipairs(SQG:GetProfileNames()) do
            root:CreateRadio(name,
                function() return name == SQG:GetProfileName() end,
                function() SQG:UseProfile(name) end)
        end
    end)
end

function ProfilesSection:Refresh()
    if activeText then
        activeText:SetText("Active profile: " .. WHITE .. SQG:GetProfileName() .. "|r")
    end
end

--- Builds the section under `anchor`; returns the bottom-most widget.
function ProfilesSection:Create(parent, anchor)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    header:SetText("Profile")

    activeText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    activeText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)

    local switch = Button(parent, "Switch...", 100, function(self) SwitchMenu(self) end)
    switch:SetPoint("LEFT", activeText, "RIGHT", 12, 0)

    -- New profile: type a name, Create switches to it.
    local nameBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", activeText, "BOTTOMLEFT", 6, -14)
    nameBox:SetSize(200, 22)
    nameBox:SetAutoFocus(false)
    local create = Button(parent, "New profile", 110, function()
        local name = strtrim(nameBox:GetText() or "")
        if name == "" then
            return
        end
        nameBox:SetText("")
        nameBox:ClearFocus()
        SQG:UseProfile(name) -- an existing name just switches to it
    end)
    create:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    nameBox:SetScript("OnEnterPressed", function() create:Click() end)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local copy = Button(parent, "Copy from...", 110, function(self)
        PickMenu(self, "Copy settings from", OtherProfiles(), function(name)
            Confirm(string.format("Overwrite profile \"%s\" with the settings from \"%s\"?",
                SQG:GetProfileName(), name), function() SQG:CopyProfile(name) end)
        end)
    end)
    copy:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -10)

    local delete = Button(parent, "Delete...", 110, function(self)
        PickMenu(self, "Delete profile", OtherProfiles(), function(name)
            Confirm(string.format("Delete profile \"%s\"? This can't be undone.", name),
                function() SQG:DeleteProfile(name) end)
        end)
    end)
    delete:SetPoint("LEFT", copy, "RIGHT", 8, 0)

    local reset = Button(parent, "Reset profile", 110, function()
        Confirm(string.format("Reset profile \"%s\" to default settings?", SQG:GetProfileName()),
            function() SQG:ResetProfile() end)
    end)
    reset:SetPoint("LEFT", delete, "RIGHT", 8, 0)

    local note = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", copy, "BOTTOMLEFT", 0, -8)
    note:SetWidth(560)
    note:SetJustifyH("LEFT")
    note:SetText("Profiles hold every setting on this page, including the spell and button position. " ..
        "Checked targets and a custom macro always stay with the character.")

    parent:HookScript("OnShow", function() ProfilesSection:Refresh() end)
    SQG:OnProfileChanged(function() ProfilesSection:Refresh() end)
    return note
end
