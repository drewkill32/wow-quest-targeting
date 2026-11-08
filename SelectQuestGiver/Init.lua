-- Wires everything together: events and slash commands.
local ADDON_NAME, SQG = ...

local events = CreateFrame("Frame")

local handlers = {}

local function ApplyMinimapSetting(db)
    if db.enabled then
        SQG.HoverController:Start()
    else
        SQG.HoverController:Stop()
    end
end

function handlers.ADDON_LOADED(loadedName)
    if loadedName ~= ADDON_NAME then
        return
    end
    events:UnregisterEvent("ADDON_LOADED")

    SQG:LoadSettings()

    -- Minimap Ctrl+click targeting
    SQG.SecureTargetButton:Create()
    SQG.TooltipHint:Install()
    ApplyMinimapSetting(SQG.db)
    SQG:OnSettingsChanged(ApplyMinimapSetting)

    -- Quest hunt button
    SQG.HuntController:Start()

    SQG.OptionsPanel:Register()
end

-- Fires just before combat lockdown starts: last chance to hide the
-- secure button so it doesn't block pin clicks during combat.
function handlers.PLAYER_REGEN_DISABLED()
    SQG.SecureTargetButton:Detach()
end

function handlers.MODIFIER_STATE_CHANGED()
    SQG.HoverController:Update()
end

events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)
for event in pairs(handlers) do
    events:RegisterEvent(event)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local commands = {}

function commands.toggle()
    SQG.db.enabled = not SQG.db.enabled
    SQG:NotifySettingsChanged()
    SQG:Print("minimap Ctrl+click %s", SQG.db.enabled and "enabled" or "disabled")
end

function commands.hunt()
    SQG.db.hunt.show = not SQG.db.hunt.show
    SQG:NotifySettingsChanged()
    SQG:Print("hunt button %s%s", SQG.db.hunt.show and "shown" or "hidden",
        InCombatLockdown() and " (after combat)" or "")
end

function commands.options()
    SQG.OptionsPanel:Open()
end

function commands.debug()
    SQG.db.debug = not SQG.db.debug
    SQG:Print("debug %s", SQG.db.debug and "on" or "off")
end

function commands.help()
    SQG:Print("Ctrl+click a Questie minimap pin to target that NPC.")
    SQG:Print("/sqg options - settings   /sqg hunt - show/hide hunt button")
    SQG:Print("/sqg toggle - minimap Ctrl+click on/off   /sqg debug - debug output")
end

SLASH_SELECTQUESTGIVER1 = "/sqg"
SlashCmdList.SELECTQUESTGIVER = function(msg)
    local command = commands[strtrim(msg or ""):lower()] or commands.help
    command()
end
