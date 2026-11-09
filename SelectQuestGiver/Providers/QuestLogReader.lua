-- Reads the player's quest log through the game API (modern C_QuestLog with
-- a fallback to the classic functions). No quest database involved.
--
-- Entries: { id, title, level, isComplete, objectives = { { text, type, finished } } }
local _, SQG = ...

local QuestLogReader = {}
SQG.QuestLogReader = QuestLogReader

local function NumEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        return C_QuestLog.GetNumQuestLogEntries() or 0
    end
    return GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
end

-- { id, title, level, isHeader, isComplete } for a log row.
local function RowInfo(logIndex)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(logIndex)
        if not info then
            return nil
        end
        local complete = not info.isHeader and C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
        return { id = info.questID, title = info.title, level = info.level, isHeader = info.isHeader,
            isComplete = complete and true or false }
    end
    local title, level, _, isHeader, _, isComplete, _, questId = GetQuestLogTitle(logIndex)
    if not title then
        return nil
    end
    return { id = questId, title = title, level = level, isHeader = isHeader, isComplete = isComplete == 1 }
end

local function Objectives(questId, logIndex)
    local objectives = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questId) or {}) do
            objectives[#objectives + 1] = { text = objective.text, type = objective.type, finished = objective.finished }
        end
        return objectives
    end
    for i = 1, GetNumQuestLeaderBoards(logIndex) or 0 do
        local text, objectiveType, finished = GetQuestLogLeaderBoard(i, logIndex)
        objectives[#objectives + 1] = { text = text, type = objectiveType, finished = finished }
    end
    return objectives
end

--- Quests in the log (headers skipped).
function QuestLogReader:GetEntries()
    local entries = {}
    for logIndex = 1, NumEntries() do
        local row = RowInfo(logIndex)
        if row and not row.isHeader and row.id and row.id > 0 then
            row.objectives = Objectives(row.id, logIndex)
            -- Quests with nothing left to do count as ready to turn in.
            local allDone = true
            for _, objective in ipairs(row.objectives) do
                allDone = allDone and objective.finished
            end
            row.isComplete = row.isComplete or allDone
            entries[#entries + 1] = row
        end
    end
    return entries
end

--- true once the game has quest log data (it's empty for a moment after
--- login), so callers don't drop a saved selection too early.
function QuestLogReader:IsReady()
    return NumEntries() > 0
end
