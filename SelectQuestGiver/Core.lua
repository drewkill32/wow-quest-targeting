-- Core: addon namespace, settings and logging.
local ADDON_NAME, SQG = ...

SQG.name = ADDON_NAME

-- Settings kept in the active profile (see ProfileStore).
local PROFILE_DEFAULTS = {
    debug = false,
    minimap = { hide = false }, -- LibDBIcon: hide, minimapPos, lock
    hunt = {
        show = true,
        locked = false,
        scale = 1,
        autoAttack = true,
        spell = "",       -- spell the hunt macro casts ("" = just target)
        position = nil,   -- saved button position
        barMacroMenu = true, -- right-click on the action bar macro opens the menu
    },
}

-- Per-character state that depends on the character's quest log, so it
-- never belongs in a shareable profile.
local CHAR_DEFAULTS = {
    huntOrder = {},
    customMacro = nil, -- hand-edited hunt macro; replaces the generated one while set
}

-- Keybinding labels (Options -> Keybindings).
_G["BINDING_NAME_CLICK SelectQuestGiverHuntButton:LeftButton"] = "Hunt quest mob"

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local store -- ProfileStore for this character

local function CharacterKey()
    return string.format("%s - %s", UnitName("player") or "Unknown", GetRealmName() or "")
end

-- v1.2 kept the spell and button position per character outside profiles;
-- move them into this character's profile (once).
local function MigrateCharacterSettings(charDb, profile)
    if charDb.huntSpell ~= nil then
        if profile.hunt.spell == "" then
            profile.hunt.spell = charDb.huntSpell
        end
        charDb.huntSpell = nil
    end
    if charDb.huntPosition ~= nil then
        profile.hunt.position = profile.hunt.position or charDb.huntPosition
        charDb.huntPosition = nil
    end
end

function SQG:LoadSettings()
    SelectQuestGiverDB = SelectQuestGiverDB or {}
    SelectQuestGiverCharDB = SQG.ProfileStore.ApplyDefaults(SelectQuestGiverCharDB or {}, CHAR_DEFAULTS)
    self.charDb = SelectQuestGiverCharDB
    store = SQG.ProfileStore.New(SelectQuestGiverDB, CharacterKey(), PROFILE_DEFAULTS)
    self.db = store:Current()
    MigrateCharacterSettings(self.charDb, self.db)
end

--- The hunt macro's spell ("" = just target).
function SQG:GetHuntSpell()
    return self.db.hunt.spell or ""
end

function SQG:SetHuntSpell(spell)
    self.db.hunt.spell = spell
end

---------------------------------------------------------------------------
-- Profiles: every change swaps SQG.db and notifies settings listeners, so
-- modules always read the active profile through SQG.db.
---------------------------------------------------------------------------
local profileListeners = {}

--- Called after the active profile changes (switch, copy or reset), after
--- the settings listeners, e.g. so the options page re-reads its widgets.
function SQG:OnProfileChanged(listener)
    profileListeners[#profileListeners + 1] = listener
end

local function ProfileChanged()
    SQG.db = store:Current()
    SQG:NotifySettingsChanged()
    for _, listener in ipairs(profileListeners) do
        listener(SQG.db)
    end
end

function SQG:GetProfileName()
    return store:CurrentName()
end

function SQG:GetProfileNames()
    return store:List()
end

function SQG:ProfileExists(name)
    return store:Exists(name)
end

--- Switches to a profile, creating it (with defaults) if it's new.
function SQG:UseProfile(name)
    store:Use(name)
    ProfileChanged()
end

function SQG:CopyProfile(name)
    if store:CopyFrom(name) then
        ProfileChanged()
    end
end

function SQG:DeleteProfile(name)
    return store:Delete(name)
end

function SQG:ResetProfile()
    store:Reset()
    ProfileChanged()
end

-- Settings-changed observers: the options panel notifies, modules listen.
local settingsListeners = {}

function SQG:OnSettingsChanged(listener)
    settingsListeners[#settingsListeners + 1] = listener
end

function SQG:NotifySettingsChanged()
    for _, listener in ipairs(settingsListeners) do
        listener(self.db)
    end
end

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------
local PREFIX = "|cff33ff99SelectQuestGiver|r: "

function SQG:Print(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. string.format(fmt, ...))
end

function SQG:Debug(fmt, ...)
    if self.db and self.db.debug then
        self:Print("|cff888888" .. fmt .. "|r", ...)
    end
end
