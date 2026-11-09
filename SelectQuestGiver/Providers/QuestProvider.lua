-- What the hunt feature asks about quests: combines the quest log
-- (QuestLogReader) with the QuestieDB addon's data (QuestTargetResolver).
-- QuestieDB is a required dependency; nothing here needs Questie itself.
local _, SQG = ...

local QuestProvider = {}
SQG.QuestProvider = QuestProvider

-- QuestieDB contract version this addon was written against.
local QUESTIEDB_CONTRACT = 4

local resolver -- created on first use, once QuestieDB has loaded
local warned = false

local function Database()
    local db = _G.LibQuestieDB
    if not db or not db.Quest or not db.Npc or not db.Item then
        return nil
    end
    if db.RequireContract then
        local ok, message = db.RequireContract(QUESTIEDB_CONTRACT)
        if not ok then
            if not warned then
                warned = true
                SQG:Print(message)
            end
            return nil
        end
    end
    return db
end

local function Resolver()
    if not resolver then
        local db = Database()
        if db then
            local letter = UnitFactionGroup("player") == "Horde" and "H" or "A"
            resolver = SQG.QuestTargetResolver.New(db, letter)
        end
    end
    return resolver
end

function QuestProvider:IsAvailable()
    return Resolver() ~= nil
end

function QuestProvider:IsReady()
    return SQG.QuestLogReader:IsReady()
end

function QuestProvider:GetQuestTitle(questId)
    local db = Database()
    return db and db.Quest.name(questId)
end

--- Quests in the log with something to target (mobs, talk or turn-in NPCs),
--- sorted by level:
--- { { id, title, level, groups = { { label, kind, mobNames } } }, ... }
function QuestProvider:GetHuntableQuests()
    local quests = {}
    local targets = Resolver()
    if not targets then
        return quests
    end
    for _, entry in ipairs(SQG.QuestLogReader:GetEntries()) do
        local groups = targets:Resolve(entry)
        if #groups > 0 then
            quests[#quests + 1] = { id = entry.id, title = entry.title, level = entry.level or 0, groups = groups }
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
