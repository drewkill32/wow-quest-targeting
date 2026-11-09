-- Wires everything together: events and slash commands.
local ADDON_NAME, SQG = ...

local events = CreateFrame("Frame")

local handlers = {}

function handlers.ADDON_LOADED(loadedName)
    if loadedName ~= ADDON_NAME then
        return
    end
    events:UnregisterEvent("ADDON_LOADED")

    SQG:LoadSettings()

    SQG.HuntController:Start()

    SQG.OptionsPanel:Register()
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

function commands.hunt()
    SQG.db.hunt.show = not SQG.db.hunt.show
    SQG:NotifySettingsChanged()
    SQG:Print("hunt button %s%s", SQG.db.hunt.show and "shown" or "hidden",
        InCombatLockdown() and " (after combat)" or "")
end

function commands.list()
    SQG.HuntListWindow:Toggle()
end

-- Run by the action bar macro on every press; opens the menu on right-click.
function commands.menu()
    SQG.HuntMacroSync:OnMenuCommand()
end

function commands.macro()
    SQG.HuntMacroSync:Pickup()
end

function commands.options()
    SQG.OptionsPanel:Open()
end

function commands.debug()
    SQG.db.debug = not SQG.db.debug
    SQG:Print("debug %s", SQG.db.debug and "on" or "off")
end

function commands.help()
    SQG:Print("/sqg options - settings   /sqg hunt - show/hide hunt button")
    SQG:Print("/sqg list - hunt priority order   /sqg macro - put the hunt macro on your cursor")
    SQG:Print("/sqg debug - debug output")
end

SLASH_SELECTQUESTGIVER1 = "/sqg"
SlashCmdList.SELECTQUESTGIVER = function(msg)
    local command = commands[strtrim(msg or ""):lower()] or commands.help
    command()
end
