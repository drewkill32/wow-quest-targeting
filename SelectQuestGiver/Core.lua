-- Core: addon namespace, settings, logging and the pin-provider registry.
local ADDON_NAME, SQG = ...

SQG.name = ADDON_NAME

local DEFAULTS = {
    enabled = true,     -- Ctrl+click minimap pins
    tooltipHint = true, -- "Ctrl-click to target" line in pin tooltips
    debug = false,
    hunt = {
        show = true,
        locked = false,
        scale = 1,
        spell = "",
        autoAttack = true,
    },
}

local CHAR_DEFAULTS = {
    huntPosition = nil,
    huntIncluded = {},
}

-- Keybinding labels (Options -> Keybindings).
_G["BINDING_NAME_CLICK SelectQuestGiverHuntButton:LeftButton"] = "Hunt quest mob"

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
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

function SQG:LoadSettings()
    SelectQuestGiverDB = ApplyDefaults(SelectQuestGiverDB or {}, DEFAULTS)
    SelectQuestGiverCharDB = ApplyDefaults(SelectQuestGiverCharDB or {}, CHAR_DEFAULTS)
    self.db = SelectQuestGiverDB
    self.charDb = SelectQuestGiverCharDB
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

---------------------------------------------------------------------------
-- Pin providers
-- A provider is a table with:
--   provider.name                       string
--   provider:IsAvailable()              -> boolean (its map addon is loaded)
--   provider:ResolveUnitName(frame)     -> string|nil  NPC name if `frame` is
--                                          one of its minimap pins for an NPC
--   provider:GetTooltipPin(tooltip)     -> frame|nil   the pin a tooltip is
--                                          currently showing, if it's theirs
---------------------------------------------------------------------------
SQG.providers = {}

function SQG:RegisterProvider(provider)
    table.insert(self.providers, provider)
end

--- Returns the NPC name for a hovered frame, asking each available provider.
function SQG:ResolveUnitName(frame)
    for _, provider in ipairs(self.providers) do
        if provider:IsAvailable() then
            local unitName = provider:ResolveUnitName(frame)
            if unitName then
                return unitName, provider
            end
        end
    end
end

--- Returns the NPC name for the pin a tooltip is showing, if any.
function SQG:ResolveTooltipUnitName(tooltip)
    for _, provider in ipairs(self.providers) do
        if provider:IsAvailable() then
            local pin = provider:GetTooltipPin(tooltip)
            local unitName = pin and provider:ResolveUnitName(pin)
            if unitName then
                return unitName, provider
            end
        end
    end
end
