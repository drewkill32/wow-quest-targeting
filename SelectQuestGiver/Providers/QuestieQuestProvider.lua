-- Adapter that reads Questie's quest data to find what the player still has
-- to target for quests in their log: hostile mobs, NPCs to talk to and the
-- NPCs completed quests are turned in to.
--
-- Sources (read-only):
--   QuestLogCache.questLog_DO_NOT_MODIFY[questId] = { title, objectives[i].finished, ... }
--   QuestieDB.GetQuest(questId).Objectives[i].spawnList[id] = { Name, Hostile, ... }
--   QuestieDB.GetQuest(questId).ObjectiveData[i] = { Type, Id, IdList }  (fallback)
--   QuestieDB.GetQuest(questId).Finisher.NPC = { npcId, ... }  (turn-in NPCs)
--   QuestieDB.IsComplete(questId) == 1  (ready to turn in)
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
-- Target kinds
--   "kill"   hostile mob (or a mob dropping a quest item): target, attack, cast
--   "talk"   friendly NPC an objective asks you to speak with: target only
--   "turnin" NPC the completed quest is handed in to: target only
---------------------------------------------------------------------------
local KIND_ORDER = { turnin = 1, talk = 2, kill = 3 }

-- Questie's IsFriendlyToPlayer treats "no faction data" as friendly, which
-- would make every hostile mob a talk target, so read the raw field:
-- friendlyToFaction is "A", "H", "AH" or nil (friendly to nobody).
local function IsFriendlyNpc(QuestieDB, npcId)
    local factions = QuestieDB.QueryNPCSingle(npcId, "friendlyToFaction")
    if type(factions) ~= "string" then
        return false
    end
    local letter = UnitFactionGroup("player") == "Horde" and "H" or "A"
    return factions:find(letter, 1, true) ~= nil
end

-- Collects target names for one objective into names[kind], skipping names
-- already used by an earlier objective.
local Collector = {}
Collector.__index = Collector

local function NewCollector(QuestieDB)
    return setmetatable({ db = QuestieDB, seen = {}, names = { kill = {}, talk = {} } }, Collector)
end

function Collector:Add(kind, name)
    if type(name) == "string" and name ~= "" and not self.seen[name] then
        self.seen[name] = true
        local list = self.names[kind]
        list[#list + 1] = name
    end
end

-- A monster objective is "talk" when the NPC is friendly to the player.
function Collector:AddNpc(npcId, name, objectiveType)
    local kind = "kill"
    if objectiveType ~= "item" and npcId and IsFriendlyNpc(self.db, npcId) then
        kind = "talk"
    end
    self:Add(kind, name or (npcId and self.db.QueryNPCSingle(npcId, "name")))
end

-- Preferred: Questie's resolved spawn list (already has the Hostile flag,
-- and includes mobs that drop quest items).
function Collector:FromSpawnList(objective, objectiveType)
    local spawnList = objective and objective.spawnList
    if type(spawnList) ~= "table" or not next(spawnList) then
        return false
    end
    for id, spawn in pairs(spawnList) do
        if spawn.Hostile then
            self:AddNpc(spawn.Id or id, spawn.Name, objectiveType)
        end
    end
    return true
end

-- Fallback when Questie hasn't resolved the spawn list yet: look the
-- monsters up straight from the database.
function Collector:FromObjectiveData(data)
    if type(data) ~= "table" then
        return
    end
    if data.Type == "monster" then
        self:AddNpc(data.Id, nil, data.Type)
    elseif data.Type == "killcredit" and data.IdList then
        for _, npcId in ipairs(data.IdList) do
            self:AddNpc(npcId, nil, data.Type)
        end
    elseif data.Type == "item" then
        local item = self.db:GetItem(data.Id)
        for _, source in pairs(item and item.Sources or {}) do
            if source.Type == "monster" and not source.Vendor then
                self:AddNpc(source.Id, nil, "item")
            end
        end
    end
end

-- Takes the names gathered for one objective, leaving the collector empty.
function Collector:Drain()
    local names = self.names
    self.names = { kill = {}, talk = {} }
    return names
end

local function ObjectiveLabel(logObjective, index)
    local text = logObjective.text or ("Objective " .. index)
    -- Strip the progress counter, wherever the client puts it:
    -- "0/6 Skittering Blood" or "Skittering Blood: 0/6" -> "Skittering Blood"
    text = text:gsub("^%s*%d+%s*/%s*%d+%s*", "")
    text = text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    return text
end

-- NPCs the quest is turned in to (objects can't be targeted, so skipped).
local function TurnInNames(QuestieDB, quest)
    local names, seen = {}, {}
    for _, npcId in ipairs(quest.Finisher and quest.Finisher.NPC or {}) do
        local name = QuestieDB.QueryNPCSingle(npcId, "name")
        if name and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

--- Targets for a quest, grouped by objective:
--- { { label = "Grizzled Bear Heart", kind = "kill", mobNames = { ... } }, ... }
--- A completed quest has a single "turnin" group with its finisher NPCs.
--- A name appears only under the first objective that needs it.
function QuestieQuestProvider:GetObjectiveGroups(questId)
    local groups = {}
    local QuestLogCache, QuestieDB = ImportModule("QuestLogCache"), ImportModule("QuestieDB")
    local logEntry = questId and QuestLogCache and QuestLogCache.questLog_DO_NOT_MODIFY[questId]
    local quest = logEntry and QuestieDB.GetQuest(questId)
    if not quest then
        return groups
    end

    if QuestieDB.IsComplete(questId) == 1 then
        local names = TurnInNames(QuestieDB, quest)
        if #names > 0 then
            groups[1] = { label = "Turn in to", kind = "turnin", mobNames = names }
        end
        return groups
    end

    local collector = NewCollector(QuestieDB)
    for index, logObjective in ipairs(logEntry.objectives or {}) do
        if not logObjective.finished then
            local objective = quest.Objectives and quest.Objectives[index]
            local data = quest.ObjectiveData and quest.ObjectiveData[index]
            local objectiveType = (data and data.Type) or logObjective.type
            if not collector:FromSpawnList(objective, objectiveType) then
                collector:FromObjectiveData(data)
            end
            local names = collector:Drain()
            local label = ObjectiveLabel(logObjective, index)
            for _, kind in ipairs({ "talk", "kill" }) do
                if #names[kind] > 0 then
                    groups[#groups + 1] = { label = label, kind = kind, mobNames = names[kind] }
                end
            end
        end
    end
    table.sort(groups, function(a, b) return KIND_ORDER[a.kind] < KIND_ORDER[b.kind] end)
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

--- Quests in the log with something to target (mobs, talk or turn-in NPCs),
--- sorted by level:
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
