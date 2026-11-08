-- Adapter that knows how to read Questie's minimap pins.
-- Questie pins are Buttons named "QuestieFrame<N>"; minimap ones have
-- `miniMapIcon = true` and carry the NPC/object name in `data.Name`.
local _, SQG = ...

local QuestiePinProvider = { name = "Questie" }

-- Questie marks object-based pins in several fields depending on pin kind.
local function IsObjectPin(data)
    return data.Type == "object"
        or data.spawnType == "object"
        or data.StarterType == "Object"
        or data.StarterType == "itemFromObject"
        or data.FinisherType == "Object"
end

function QuestiePinProvider:IsAvailable()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return isLoaded("Questie") and true or false
end

function QuestiePinProvider:ResolveUnitName(frame)
    if not frame or not frame.miniMapIcon then
        return nil
    end

    local frameName = frame.GetName and frame:GetName()
    if not frameName or not frameName:match("^QuestieFrame%d+$") then
        return nil
    end

    local data = frame.data
    if type(data) ~= "table" or type(data.Name) ~= "string" or data.Name == "" then
        return nil
    end

    if IsObjectPin(data) then
        return nil
    end

    return data.Name
end

-- Questie's MapIconTooltip renders into GameTooltip, sets `ShownAsMapIcon`
-- and remembers the hovered pin in `_owner`.
function QuestiePinProvider:GetTooltipPin(tooltip)
    if tooltip.ShownAsMapIcon then
        return tooltip._owner
    end
end

SQG:RegisterProvider(QuestiePinProvider)
