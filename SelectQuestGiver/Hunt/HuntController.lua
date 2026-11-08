-- Keeps the hunt button's macro chain in sync with the mobs the player has
-- checked (across any number of quests) and with the quest log.
-- Secure attributes can't change in combat, so changes made in combat are
-- queued and applied as soon as combat ends.
local _, SQG = ...

local HuntController = {}
SQG.HuntController = HuntController

local REBUILD_DELAY = 0.3 -- QUEST_LOG_UPDATE fires in bursts; coalesce them

local events = CreateFrame("Frame")
local pendingRebuild = false -- a rebuild is waiting for combat to end
local rebuildScheduled = false
local model = { quests = {}, activeQuests = 0 } -- last view model for menu/tooltip

-- The options accept a spell name or a spell ID, but macro /cast only
-- understands names, so turn an ID into the spell's name.
local function ResolveSpellName(spell)
    local spellId = tonumber(spell)
    if not spellId then
        return spell
    end
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellId)
    elseif GetSpellInfo then
        name = GetSpellInfo(spellId)
    end
    if not name then
        SQG:Print("Unknown spell ID %d - the hunt button won't cast.", spellId)
    end
    return name or ""
end

local function AllMobNames(quest)
    local names = {}
    for _, group in ipairs(quest.groups) do
        for _, name in ipairs(group.mobNames) do
            names[#names + 1] = name
        end
    end
    return names
end

-- Checked mob names in menu order (quests by level, then objective order).
local function CollectCheckedNames(quests)
    local names = {}
    for _, quest in ipairs(quests) do
        for _, name in ipairs(AllMobNames(quest)) do
            if SQG.HuntSelection:IsIncluded(quest.id, name) then
                names[#names + 1] = name
            end
        end
    end
    return names
end

--- View model for the menu and tooltip. Each mob gets a state:
--- "used" (in the macro), "overflow" (checked, but the chain is full) or "off".
local function BuildModel(quests, checkedNames, used)
    local inMacro = {}
    for i = 1, used do
        inMacro[checkedNames[i]] = true
    end

    local result = { quests = {}, activeQuests = 0 }
    for _, quest in ipairs(quests) do
        local allNames = AllMobNames(quest)
        local entry = {
            id = quest.id,
            title = quest.title,
            level = quest.level,
            state = SQG.HuntSelection:GetQuestState(quest.id, allNames),
            groups = {},
        }
        for _, group in ipairs(quest.groups) do
            local mobs = {}
            for _, name in ipairs(group.mobNames) do
                local included = SQG.HuntSelection:IsIncluded(quest.id, name)
                local state = "off"
                if included then
                    state = inMacro[name] and "used" or "overflow"
                end
                mobs[#mobs + 1] = { name = name, included = included, state = state }
            end
            entry.groups[#entry.groups + 1] = { label = group.label, mobs = mobs }
        end
        if entry.state ~= "none" then
            result.activeQuests = result.activeQuests + 1
        end
        result.quests[#result.quests + 1] = entry
    end
    return result
end

function HuntController:Rebuild()
    if InCombatLockdown() then
        pendingRebuild = true
        return
    end
    pendingRebuild = false

    local provider = SQG.QuestProvider
    SQG.HuntSelection:MigrateLegacy(function(questId) return provider:GetMobNames(questId) end)
    -- Forget checked mobs of quests that left the log (no-op until Questie is ready).
    SQG.HuntSelection:Prune(function(questId) return provider:IsInLog(questId) end)

    local quests = provider:GetHuntableQuests()
    local checkedNames = CollectCheckedNames(quests)

    local settings = SQG.db.hunt
    local macros, used = SQG.HuntMacroBuilder.Build(checkedNames, {
        spell = ResolveSpellName(settings.spell),
        autoAttack = settings.autoAttack,
        chainNames = SQG.HuntButton:GetChainNames(),
    })
    if used < #checkedNames then
        SQG:Debug("Macro chain full: using %d of %d mob names", used, #checkedNames)
    end

    model = BuildModel(quests, checkedNames, used)
    SQG.HuntButton:SetHunt(macros, model)
    for index, text in ipairs(macros) do
        SQG:Debug("Hunt macro %d/%d:\n%s", index, #macros, text)
    end
end

function HuntController:ScheduleRebuild()
    if rebuildScheduled then
        return
    end
    rebuildScheduled = true
    C_Timer.After(REBUILD_DELAY, function()
        rebuildScheduled = false
        HuntController:Rebuild()
    end)
end

-- Selection changes: saved immediately, applied now or after combat.
local function AfterSelectionChange()
    HuntController:Rebuild()
    if InCombatLockdown() then
        SQG:Print("Hunt mobs will update after combat.")
    end
end

function HuntController:ToggleMob(questId, name)
    SQG.HuntSelection:ToggleMob(questId, name)
    AfterSelectionChange()
end

function HuntController:ToggleQuest(questId)
    for _, quest in ipairs(model.quests) do
        if quest.id == questId then
            local names = {}
            for _, group in ipairs(quest.groups) do
                for _, mob in ipairs(group.mobs) do
                    names[#names + 1] = mob.name
                end
            end
            SQG.HuntSelection:ToggleQuest(questId, names)
        end
    end
    AfterSelectionChange()
end

function HuntController:ClearAll()
    SQG.HuntSelection:ClearAll()
    AfterSelectionChange()
end

--- Fresh view model for the menu (it only opens out of combat, so the
--- rebuild applies immediately).
function HuntController:GetModel()
    self:Rebuild()
    return model
end

-- Questie reads the quest log in the background for a few seconds after
-- login/reload, often after the last QUEST_LOG_UPDATE. Poll until its cache
-- has quests so the button's label and macro are right without user input.
local READY_POLL_INTERVAL = 2
local READY_POLL_LIMIT = 30 -- tries (one minute)

local function WaitForQuestie(triesLeft)
    if SQG.QuestProvider:IsReady() then
        HuntController:Rebuild()
        return
    end
    if triesLeft > 0 then
        C_Timer.After(READY_POLL_INTERVAL, function() WaitForQuestie(triesLeft - 1) end)
    end
end

function HuntController:Start()
    if not SQG.QuestProvider:IsAvailable() then
        SQG:Print("Questie not found - the hunt button has no quests to pick from.")
    end

    SQG.HuntButton:Create({
        getModel = function() return HuntController:GetModel() end,
        onMobToggled = function(questId, name) HuntController:ToggleMob(questId, name) end,
        onQuestToggled = function(questId) HuntController:ToggleQuest(questId) end,
        onClearAll = function() HuntController:ClearAll() end,
    })

    SQG:OnSettingsChanged(function()
        if not SQG.HuntButton:ApplySettings() then
            pendingRebuild = true
        end
        HuntController:Rebuild()
    end)

    events:RegisterEvent("QUEST_LOG_UPDATE")
    events:RegisterEvent("QUEST_REMOVED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingRebuild then
                SQG.HuntButton:ApplySettings()
                HuntController:Rebuild()
            end
        else
            HuntController:ScheduleRebuild()
        end
    end)

    self:Rebuild()
    WaitForQuestie(READY_POLL_LIMIT)
end
