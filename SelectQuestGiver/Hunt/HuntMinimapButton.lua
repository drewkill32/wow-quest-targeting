-- Minimap button (LibDataBroker launcher shown by LibDBIcon, so minimap
-- addons can collect it). Clicking it opens the same hunt menu as the hunt
-- button. Its position and visibility live in the profile (SQG.db.minimap).
--
-- A view: HuntController calls :Refresh(model) after every rebuild, which
-- keeps the icon and tooltip in step with the hunt button.
local _, SQG = ...

local HuntMinimapButton = {}
SQG.HuntMinimapButton = HuntMinimapButton

local NAME = "SelectQuestGiver"

local callbacks = {}
local model = { quests = {}, activeQuests = 0 }
local dataObject
local icons -- LibDBIcon

local function ShowTooltip(tooltip)
    tooltip:AddLine("Select Quest Giver")
    SQG.HuntStyle.AddTargetLines(tooltip, model)
    tooltip:AddLine(" ")
    tooltip:AddLine("Click: choose targets", 0.43, 0.43, 0.43)
    tooltip:AddLine("Drag: move around the minimap", 0.43, 0.43, 0.43)
end

local function ApplySettings()
    if icons then
        icons:Refresh(NAME, SQG.db.minimap) -- shows/hides and re-reads the position
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
---@param controllerCallbacks { onOpenMenu: fun(owner) }
function HuntMinimapButton:Create(controllerCallbacks)
    callbacks = controllerCallbacks
    local broker = LibStub and LibStub("LibDataBroker-1.1", true)
    icons = LibStub and LibStub("LibDBIcon-1.0", true)
    if not broker or not icons then
        return
    end
    dataObject = broker:NewDataObject(NAME, {
        type = "launcher",
        label = "Select Quest Giver",
        icon = SQG.HuntStyle.ActionIcon(nil),
        OnClick = function(frame) callbacks.onOpenMenu(frame) end,
        OnTooltipShow = ShowTooltip,
    })
    icons:Register(NAME, dataObject, SQG.db.minimap)
    SQG:OnSettingsChanged(ApplySettings) -- also runs after a profile switch
end

--- View refresh after every rebuild.
function HuntMinimapButton:Refresh(newModel)
    model = newModel
    if dataObject then
        dataObject.icon = SQG.HuntStyle.ActionIcon(model.topKind)
    end
end
