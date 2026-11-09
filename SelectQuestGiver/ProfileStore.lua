-- Settings profiles, the way most addons do them (AceDB style), without
-- WoW API calls so it can be unit tested (tests/test_profile_store.lua).
--
-- Saved layout (account-wide SavedVariables table `root`):
--   root.profiles[profileName]  = settings table
--   root.profileKeys[charKey]   = profileName the character uses
--
-- A character with no profile yet gets its own, named after it
-- ("Name - Realm"), seeded from the "Default" profile when one exists.
local _, SQG = ...

local ProfileStore = {}
ProfileStore.__index = ProfileStore
SQG.ProfileStore = ProfileStore

ProfileStore.DEFAULT_NAME = "Default"

-- Settings that lived at the top level of the saved table before profiles.
local LEGACY_KEYS = { "enabled", "tooltipHint", "debug", "hunt" }

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in pairs(value) do
        copy[key] = DeepCopy(inner)
    end
    return copy
end
ProfileStore.DeepCopy = DeepCopy

--- Fills missing keys of `target` from `defaults` (recursively).
local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end
ProfileStore.ApplyDefaults = ApplyDefaults

-- Moves pre-profile settings into a "Default" profile (once).
local function MigrateLegacy(root)
    local legacy, found = {}, false
    for _, key in ipairs(LEGACY_KEYS) do
        if root[key] ~= nil then
            legacy[key] = root[key]
            root[key] = nil
            found = true
        end
    end
    if found and not root.profiles[ProfileStore.DEFAULT_NAME] then
        root.profiles[ProfileStore.DEFAULT_NAME] = legacy
    end
end

---@param root table      account-wide saved table
---@param charKey string  "Name - Realm"
---@param defaults table  default settings for a profile
function ProfileStore.New(root, charKey, defaults)
    root.profiles = root.profiles or {}
    root.profileKeys = root.profileKeys or {}
    MigrateLegacy(root)

    local store = setmetatable({ root = root, charKey = charKey, defaults = defaults }, ProfileStore)
    if not root.profileKeys[charKey] then
        store:Use(charKey, root.profiles[ProfileStore.DEFAULT_NAME])
    end
    store:Current() -- make sure it exists with defaults
    return store
end

function ProfileStore:CurrentName()
    return self.root.profileKeys[self.charKey]
end

--- The active profile's settings table (created and defaulted on demand).
function ProfileStore:Current()
    local name = self:CurrentName()
    local profiles = self.root.profiles
    profiles[name] = ApplyDefaults(profiles[name] or {}, self.defaults)
    return profiles[name]
end

--- Profile names, sorted.
function ProfileStore:List()
    local names = {}
    for name in pairs(self.root.profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function ProfileStore:Exists(name)
    return self.root.profiles[name] ~= nil
end

--- Switches this character to `name`, creating it if needed (as a copy of
--- `seed` when given, otherwise with default settings).
function ProfileStore:Use(name, seed)
    if not self.root.profiles[name] then
        self.root.profiles[name] = DeepCopy(seed or {})
    end
    self.root.profileKeys[self.charKey] = name
    return self:Current()
end

--- Overwrites the active profile with a copy of another one.
function ProfileStore:CopyFrom(name)
    local source = self.root.profiles[name]
    if not source or name == self:CurrentName() then
        return false
    end
    self.root.profiles[self:CurrentName()] = DeepCopy(source)
    self:Current()
    return true
end

--- Deletes a profile other than the active one. Characters that used it fall
--- back to their own profile next time they log in.
function ProfileStore:Delete(name)
    if name == self:CurrentName() or not self.root.profiles[name] then
        return false
    end
    self.root.profiles[name] = nil
    for charKey, profileName in pairs(self.root.profileKeys) do
        if profileName == name then
            self.root.profileKeys[charKey] = nil
        end
    end
    return true
end

--- Puts the active profile back to default settings.
function ProfileStore:Reset()
    self.root.profiles[self:CurrentName()] = {}
    return self:Current()
end
