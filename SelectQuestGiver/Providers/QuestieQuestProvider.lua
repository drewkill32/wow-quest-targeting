-- Adapter that reads Questie's quest data to find the hostile mobs still
-- needed for quests in the player's log.
--
-- Sources (read-only):
--   QuestLogCache.questLog_DO_NOT_MODIFY[questId] = { title, objectives[i].finished, ... }
--   QuestieDB.GetQuest(questId).Objectives[i].spawnList[id] = { Name, Hostile, ... }
--   QuestieDB.GetQuest(questId).ObjectiveData[i] = { Type, Id, IdList }  (fallback)
local _, SQG = ...

local QuestieQuestProvider = { name = "Questie" }
SQG.QuestProvider = QuestieQuestProvider

local function ImportModule(name)
    if not QuestieLoader or not QuestieLoader.ImportModule then
        return nil
    end
    local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    return ok and module or nil
end

function QuestieQuestProvider:IsAvailable()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return isLoaded("Questie") and ImportModule("QuestLogCache") ~= nil and ImportModule("QuestieDB") ~= nil
end

---------------------------------------------------------------------------
-- Name collection
---------------------------------------------------------------------------
local function AddName(names, seen, name)
    if type(name) == "string" and name ~= "" and not seen[name] then
        seen[name] = true
        names[#names + 1] = name
    end
end

-- Preferred: Questie's resolved spawn list (already has the Hostile flag,
-- and includes mobs that drop quest items).
local function CollectFromSpawnList(objective, names, seen)
    local spawnList = objective and objective.spawnList
    if type(spawnList) ~= "table" or not next(spawnList) then
        return false
    end
    for _, spawn in pairs(spawnList) do
        if spawn.Hostile then
            AddName(names, seen, spawn.Name)
        end
    end
    return true
end

-- Fallback when Questie hasn't resolved the spawn list yet: look the
-- monsters up straight from the database.
local function CollectFromObjectiveData(QuestieDB, data, names, seen)
    if type(data) ~= "table" then
        return
    end
    local function AddNpc(npcId)
        AddName(names, seen, QuestieDB.QueryNPCSingle(npcId, "name"))
    end

    if data.Type == "monster" then
        AddNpc(data.Id)
    elseif data.Type == "killcredit" and data.IdList then
        for _, npcId in ipairs(data.IdList) do
            AddNpc(npcId)
        end
    elseif data.Type == "item" then
        local item = QuestieDB:GetItem(data.Id)
        for _, source in pairs(item and item.Sources or {}) do
            if source.Type == "monster" and not source.Vendor then
                AddNpc(source.Id)
            end
        end
    end
end

local function ObjectiveLabel(logObjective, index)
    local text = logObjective.text or ("Objective " .. index)
    -- Strip the progress counter, wherever the client puts it:
    -- "0/6 Skittering Blood" or "Skittering Blood: 0/6" -> "Skittering Blood"
    text = text:gsub("^%s*%d+%s*/%s*%d+%s*", "")
    text = text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    return text
end

--- Incomplete objectives of a quest with the hostile mobs for each:
--- { { label = "Grizzled Bear Heart", mobNames = { ... } }, ... }
--- A mob appears only under the first objective that needs it.
function QuestieQuestProvider:GetObjectiveGroups(questId)
    local groups, seen = {}, {}
    local QuestLogCache, QuestieDB = ImportModule("QuestLogCache"), ImportModule("QuestieDB")
    local logEntry = questId and QuestLogCache and QuestLogCache.questLog_DO_NOT_MODIFY[questId]
    local quest = logEntry and QuestieDB.GetQuest(questId)
    if not quest then
        return groups
    end

    for index, logObjective in ipairs(logEntry.objectives or {}) do
        if not logObjective.finished then
            local names = {}
            local objective = quest.Objectives and quest.Objectives[index]
            if not CollectFromSpawnList(objective, names, seen) then
                CollectFromObjectiveData(QuestieDB, quest.ObjectiveData and quest.ObjectiveData[index], names, seen)
            end
            if #names > 0 then
                groups[#groups + 1] = { label = ObjectiveLabel(logObjective, index), mobNames = names }
            end
        end
    end
    return groups
end

--- Mob names still needed for a quest, in objective order, deduplicated.
function QuestieQuestProvider:GetMobNames(questId)
    local names = {}
    for _, group in ipairs(self:GetObjectiveGroups(questId)) do
        for _, name in ipairs(group.mobNames) do
            names[#names + 1] = name
        end
    end
    return names
end

--- true once Questie's quest log cache has been filled.
function QuestieQuestProvider:IsReady()
    local QuestLogCache = ImportModule("QuestLogCache")
    return QuestLogCache ~= nil and QuestLogCache.GetQuestCount() > 0
end

--- true/false once Questie has read the quest log; nil while it hasn't yet
--- (right after login), so callers don't drop a saved selection too early.
function QuestieQuestProvider:IsInLog(questId)
    local QuestLogCache = ImportModule("QuestLogCache")
    if not questId or not QuestLogCache or QuestLogCache.GetQuestCount() == 0 then
        return nil
    end
    return QuestLogCache.questLog_DO_NOT_MODIFY[questId] ~= nil
end

function QuestieQuestProvider:GetQuestTitle(questId)
    local QuestLogCache = ImportModule("QuestLogCache")
    local entry = QuestLogCache and QuestLogCache.questLog_DO_NOT_MODIFY[questId]
    return entry and entry.title
end

--- Quests in the log that still have hostile mobs to hunt, sorted by level:
--- { { id, title, level, groups = GetObjectiveGroups(id) }, ... }
function QuestieQuestProvider:GetHuntableQuests()
    local quests = {}
    local QuestLogCache, QuestieDB = ImportModule("QuestLogCache"), ImportModule("QuestieDB")
    if not QuestLogCache or not QuestieDB then
        return quests
    end

    for questId, entry in pairs(QuestLogCache.questLog_DO_NOT_MODIFY) do
        local groups = self:GetObjectiveGroups(questId)
        if #groups > 0 then
            local quest = QuestieDB.GetQuest(questId)
            quests[#quests + 1] = {
                id = questId,
                title = entry.title,
                level = quest and quest.level or 0,
                groups = groups,
            }
        end
    end

    table.sort(quests, function(a, b)
        if a.level ~= b.level then
            return a.level < b.level
        end
        return (a.title or "") < (b.title or "")
    end)
    return quests
end
