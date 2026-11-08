-- Which mobs the player has checked in the hunt menu, per quest.
-- Stored per character: SelectQuestGiverCharDB.huntIncluded[questId][name] = true
-- New quests start with nothing checked.
local _, SQG = ...

local HuntSelection = {}
SQG.HuntSelection = HuntSelection

local function Store()
    return SQG.charDb.huntIncluded
end

local function QuestSet(questId, create)
    local key = tostring(questId)
    local store = Store()
    if create and not store[key] then
        store[key] = {}
    end
    return store[key]
end

function HuntSelection:IsIncluded(questId, name)
    local set = QuestSet(questId, false)
    return set ~= nil and set[name] == true
end

function HuntSelection:SetIncluded(questId, name, included)
    local set = QuestSet(questId, true)
    set[name] = included and true or nil
    if not next(set) then
        Store()[tostring(questId)] = nil
    end
end

function HuntSelection:ToggleMob(questId, name)
    self:SetIncluded(questId, name, not self:IsIncluded(questId, name))
end

--- "all", "some" or "none" of `names` are checked for the quest.
function HuntSelection:GetQuestState(questId, names)
    local count = 0
    for _, name in ipairs(names) do
        if self:IsIncluded(questId, name) then
            count = count + 1
        end
    end
    if count == 0 then
        return "none"
    end
    return count == #names and "all" or "some"
end

--- Quest checkbox: checks every mob unless all are already checked.
function HuntSelection:ToggleQuest(questId, names)
    local include = self:GetQuestState(questId, names) ~= "all"
    for _, name in ipairs(names) do
        self:SetIncluded(questId, name, include)
    end
end

function HuntSelection:ClearAll()
    wipe(Store())
end

--- Drops choices for quests no longer in the log.
---@param isInLog fun(questId: number): boolean|nil  nil = unknown, keep it
function HuntSelection:Prune(isInLog)
    for key in pairs(Store()) do
        if isInLog(tonumber(key)) == false then
            Store()[key] = nil
        end
    end
end

--- Converts the old single-quest selection (huntQuestId + huntExcluded) into
--- checked mobs. Needs the quest's current mob names, so it runs once Questie
--- has the quest log.
function HuntSelection:MigrateLegacy(getMobNames)
    local charDb = SQG.charDb
    local questId = charDb.huntQuestId
    if not questId then
        return
    end
    local names = getMobNames(questId)
    if #names == 0 then
        return -- not ready yet (or nothing to hunt); try again later
    end
    local excluded = charDb.huntExcluded and charDb.huntExcluded[tostring(questId)] or {}
    for _, name in ipairs(names) do
        if not excluded[name] then
            self:SetIncluded(questId, name, true)
        end
    end
    charDb.huntQuestId, charDb.huntExcluded = nil, nil
end
