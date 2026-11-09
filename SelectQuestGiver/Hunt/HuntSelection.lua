-- The mobs the player has checked for hunting, as one ordered priority list
-- across all quests. Order = macro order: the first nearby mob in the list wins.
--
-- Stored per character: SelectQuestGiverCharDB.huntOrder = { { questId, name }, ... }
-- Newly checked mobs go to the bottom.
local _, SQG = ...

local HuntSelection = {}
SQG.HuntSelection = HuntSelection

local function List()
    return SQG.charDb.huntOrder
end

local function IndexOf(questId, name)
    for index, entry in ipairs(List()) do
        if entry.questId == questId and entry.name == name then
            return index
        end
    end
end

function HuntSelection:IsIncluded(questId, name)
    return IndexOf(questId, name) ~= nil
end

function HuntSelection:SetIncluded(questId, name, included)
    local index = IndexOf(questId, name)
    if included and not index then
        table.insert(List(), { questId = questId, name = name })
    elseif not included and index then
        table.remove(List(), index)
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
    wipe(List())
end

--- The ordered entries (read-only; use Move/RemoveAt to change).
function HuntSelection:GetOrdered()
    return List()
end

--- Moves the entry at `from` so it ends up at position `to`.
function HuntSelection:Move(from, to)
    local list = List()
    if from == to or not list[from] then
        return
    end
    to = math.max(1, math.min(to, #list))
    local entry = table.remove(list, from)
    table.insert(list, to, entry)
end

function HuntSelection:RemoveAt(index)
    table.remove(List(), index)
end

--- Drops entries that are no longer huntable.
---@param isActive fun(questId: number, name: string): boolean|nil
---   false = remove (quest gone or objective finished), nil = unknown, keep
function HuntSelection:Prune(isActive)
    local list = List()
    for index = #list, 1, -1 do
        local entry = list[index]
        if isActive(entry.questId, entry.name) == false then
            table.remove(list, index)
        end
    end
end

--- Converts older saved formats into the ordered list:
---   v1: huntQuestId + huntExcluded[questId][name]  (one quest, unchecked mobs)
---   v2: huntIncluded[questId][name]                (checked mobs, no order)
--- Needs current mob names, so it waits until Questie has the quest log.
---@param quests table[]  huntable quests in menu order: { id, groups = { { mobNames } } }
function HuntSelection:MigrateLegacy(quests)
    local charDb = SQG.charDb
    if not charDb.huntQuestId and not charDb.huntIncluded then
        return
    end
    if #quests == 0 then
        return -- not ready yet (or nothing to hunt); try again later
    end

    local legacyQuest = charDb.huntQuestId
    local excluded = charDb.huntExcluded and charDb.huntExcluded[tostring(legacyQuest)] or {}
    local included = charDb.huntIncluded or {}

    for _, quest in ipairs(quests) do
        local set = included[tostring(quest.id)] or {}
        for _, group in ipairs(quest.groups) do
            for _, name in ipairs(group.mobNames) do
                local fromV1 = quest.id == legacyQuest and not excluded[name]
                if fromV1 or set[name] then
                    self:SetIncluded(quest.id, name, true)
                end
            end
        end
    end
    charDb.huntQuestId, charDb.huntExcluded, charDb.huntIncluded = nil, nil, nil
end
