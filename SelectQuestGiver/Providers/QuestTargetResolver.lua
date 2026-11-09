-- Works out what to target for one quest in the log, using the QuestieDB
-- addon's data. Pure: no WoW API calls, and the database is passed in, so it
-- can be unit tested (tests/test_quest_target_resolver.lua).
--
-- Input (from QuestLogReader):
--   entry = { id, title, level, isComplete, objectives = { { text, type, finished }, ... } }
-- Database (LibQuestieDB, or a fake in tests):
--   db.Quest.objectives(id)  = { [1] creatures {npcId, text?}, [2] objects, [3] items {itemId, text?},
--                                [4] reputation, [5] kill credit {npcIds, rootNpcId, text?}, ... }
--   db.Quest.finishedBy(id)  = { [1] npcIds, [2] objectIds }
--   db.Npc.name(id), db.Npc.friendlyToFaction(id) -> "A" | "H" | "AH" | nil
--   db.Item.name(id), db.Item.npcDrops(id) -> npcIds
--
-- Target kinds:
--   "kill"   hostile mob (or a mob dropping a quest item): target, attack, cast
--   "talk"   friendly NPC an objective asks you to speak with: target only
--   "turnin" NPC the completed quest is handed in to: target only
local _, SQG = ...

local QuestTargetResolver = {}
QuestTargetResolver.__index = QuestTargetResolver
SQG.QuestTargetResolver = QuestTargetResolver

local KIND_ORDER = { turnin = 1, talk = 2, kill = 3 }

-- QuestieDB objective slots.
local CREATURES, ITEMS, KILL_CREDIT = 1, 3, 5

---@param db table          LibQuestieDB (needs Quest, Npc, Item)
---@param factionLetter string  "A" or "H": the player's faction
function QuestTargetResolver.New(db, factionLetter)
    return setmetatable({ db = db, faction = factionLetter }, QuestTargetResolver)
end

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
local function Trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

--- Objective text without its progress counter, wherever the client puts it:
--- "0/6 Skittering Blood" or "Skittering Blood: 0/6" -> "Skittering Blood".
function QuestTargetResolver.ObjectiveLabel(text)
    text = text or ""
    text = text:gsub("^%s*%d+%s*/%s*%d+%s*", "")
    text = text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    return Trim(text)
end

-- "Kobold Vermin slain" -> "Kobold Vermin"
local function WithoutSlain(label)
    return (label:gsub("%s+slain$", ""))
end

-- Non-empty strings among the arguments (objective texts are often nil).
local function Names(...)
    local names = {}
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if type(name) == "string" and name ~= "" then
            names[#names + 1] = name
        end
    end
    return names
end

local function Same(a, b)
    return a and b and a:lower() == b:lower()
end

---------------------------------------------------------------------------
-- Database objectives -> candidates that log objectives are matched against
---------------------------------------------------------------------------
-- Each candidate: { names = { matchable texts }, targets = { { npcId, kind } } }
function QuestTargetResolver:IsFriendly(npcId)
    local factions = self.db.Npc.friendlyToFaction(npcId)
    return type(factions) == "string" and factions:find(self.faction, 1, true) ~= nil
end

function QuestTargetResolver:CreatureCandidate(objective)
    local npcId, text = objective[1], objective[2]
    local kind = self:IsFriendly(npcId) and "talk" or "kill"
    return { names = Names(text, self.db.Npc.name(npcId)), targets = { { npcId, kind } } }
end

function QuestTargetResolver:KillCreditCandidate(objective)
    local npcIds, rootId, text = objective[1], objective[2], objective[3]
    local targets = {}
    for _, npcId in ipairs(npcIds or {}) do
        targets[#targets + 1] = { npcId, self:IsFriendly(npcId) and "talk" or "kill" }
    end
    return { names = Names(text, rootId and self.db.Npc.name(rootId)), targets = targets }
end

-- Mobs that drop the item; friendly NPCs (vendors, quest givers) are skipped.
function QuestTargetResolver:ItemCandidate(objective)
    local itemId, text = objective[1], objective[2]
    local targets = {}
    for _, npcId in ipairs(self.db.Item.npcDrops(itemId) or {}) do
        if not self:IsFriendly(npcId) then
            targets[#targets + 1] = { npcId, "kill" }
        end
    end
    return { names = Names(text, self.db.Item.name(itemId)), targets = targets }
end

-- Candidates per log objective type ("monster" covers creatures and kill
-- credit, both of which the quest log reports as monsters).
function QuestTargetResolver:Candidates(questId)
    local objectives = self.db.Quest.objectives(questId) or {}
    local byType = { monster = {}, item = {} }
    for _, objective in ipairs(objectives[CREATURES] or {}) do
        table.insert(byType.monster, self:CreatureCandidate(objective))
    end
    for _, objective in ipairs(objectives[KILL_CREDIT] or {}) do
        table.insert(byType.monster, self:KillCreditCandidate(objective))
    end
    for _, objective in ipairs(objectives[ITEMS] or {}) do
        table.insert(byType.item, self:ItemCandidate(objective))
    end
    return byType
end

-- Picks the candidate for a log objective: by name first, otherwise the
-- first one of that type not used yet (the log keeps the database order).
local function Match(candidates, label, used)
    local wanted = { label, WithoutSlain(label) }
    for _, candidate in ipairs(candidates) do
        if not used[candidate] then
            for _, name in ipairs(candidate.names) do
                if Same(name, wanted[1]) or Same(name, wanted[2]) then
                    return candidate
                end
            end
        end
    end
    for _, candidate in ipairs(candidates) do
        if not used[candidate] then
            return candidate
        end
    end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- Collects names per kind, skipping names an earlier objective already has.
local function NewGroupBuilder(npcName)
    local seen = {}
    return function(targets)
        local names = { kill = {}, talk = {} }
        for _, target in ipairs(targets) do
            local name = npcName(target[1])
            if type(name) == "string" and name ~= "" and not seen[name] then
                seen[name] = true
                table.insert(names[target[2]], name)
            end
        end
        return names
    end
end

--- NPCs the quest is turned in to (objects can't be targeted, so skipped).
function QuestTargetResolver:TurnInNames(questId)
    local finishedBy = self.db.Quest.finishedBy(questId) or {}
    local names, seen = {}, {}
    for _, npcId in ipairs(finishedBy[1] or {}) do
        local name = self.db.Npc.name(npcId)
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
function QuestTargetResolver:Resolve(entry)
    local groups = {}
    if entry.isComplete then
        local names = self:TurnInNames(entry.id)
        if #names > 0 then
            groups[1] = { label = "Turn in to", kind = "turnin", mobNames = names }
        end
        return groups
    end

    local candidates = self:Candidates(entry.id)
    local used = {}
    local build = NewGroupBuilder(self.db.Npc.name)
    for index, objective in ipairs(entry.objectives or {}) do
        local pool = candidates[objective.type]
        local label = QuestTargetResolver.ObjectiveLabel(objective.text)
        local candidate = pool and Match(pool, label, used)
        if candidate then
            used[candidate] = true
        end
        if candidate and not objective.finished then
            local names = build(candidate.targets)
            if label == "" then
                label = "Objective " .. index
            end
            for _, kind in ipairs({ "talk", "kill" }) do
                if #names[kind] > 0 then
                    groups[#groups + 1] = { label = label, kind = kind, mobNames = names[kind], order = #groups }
                end
            end
        end
    end
    -- Talk targets first, otherwise objective order (stable).
    table.sort(groups, function(a, b)
        if a.kind ~= b.kind then
            return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
        end
        return a.order < b.order
    end)
    return groups
end
