-- Keeps the hunt button's macro in sync with the mobs the player has
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
local model = { quests = {}, activeQuests = 0, ordered = {} } -- last view model
local views = {} -- extra views refreshed after every rebuild (e.g. the hunt list window)

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

-- Lookup of targets that are still needed and their kind:
-- active[questId][name] = "kill" | "talk" | "turnin".
local function ActiveMobs(quests)
    local active = {}
    for _, quest in ipairs(quests) do
        local kinds = {}
        for _, group in ipairs(quest.groups) do
            for _, name in ipairs(group.mobNames) do
                kinds[name] = kinds[name] or group.kind
            end
        end
        active[quest.id] = kinds
    end
    return active
end

-- Checked entries that are still huntable, in priority order.
local function ActiveEntries(active, questieReady)
    local entries = {}
    for storeIndex, entry in ipairs(SQG.HuntSelection:GetOrdered()) do
        local kind = active[entry.questId] and active[entry.questId][entry.name]
        if kind or not questieReady then
            entries[#entries + 1] = {
                storeIndex = storeIndex,
                questId = entry.questId,
                name = entry.name,
                kind = kind or "kill",
            }
        end
    end
    return entries
end

--- View model for the menu and tooltip. Each mob gets a state:
--- "used" (in the macro), "overflow" (checked, but the 255-char macro is full) or "off".
local function BuildModel(quests, entries, used)
    local inMacro, seen, counted = {}, {}, 0
    for _, entry in ipairs(entries) do
        if not seen[entry.name] then
            seen[entry.name] = true
            counted = counted + 1
            inMacro[entry.name] = counted <= used
        end
    end

    local titles = {}
    for _, quest in ipairs(quests) do
        titles[quest.id] = quest.title
    end

    -- mobStates[questId][name] = "used" | "overflow" for checked mobs, so views
    -- can look up a mob's live state without walking the quest tree.
    local result = { quests = {}, activeQuests = 0, ordered = {}, mobStates = {}, usedCount = 0, overflowCount = 0 }
    for position, entry in ipairs(entries) do
        local state = inMacro[entry.name] and "used" or "overflow"
        result.ordered[position] = {
            storeIndex = entry.storeIndex,
            questId = entry.questId,
            name = entry.name,
            questTitle = titles[entry.questId] or SQG.QuestProvider:GetQuestTitle(entry.questId) or "",
            state = state,
            kind = entry.kind,
        }
        result.mobStates[entry.questId] = result.mobStates[entry.questId] or {}
        result.mobStates[entry.questId][entry.name] = state
        if state == "used" then
            result.usedCount = result.usedCount + 1
        else
            result.overflowCount = result.overflowCount + 1
        end
    end
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
                mobs[#mobs + 1] = { name = name, included = included, state = state, kind = group.kind }
            end
            entry.groups[#entry.groups + 1] = { label = group.label, kind = group.kind, mobs = mobs }
        end
        if entry.state ~= "none" then
            result.activeQuests = result.activeQuests + 1
        end
        result.quests[#result.quests + 1] = entry
    end
    -- The top-priority target decides the button's icon.
    result.topKind = entries[1] and entries[1].kind or nil
    return result
end

-- Talk / turn-in NPCs are only targeted: with no mobs listed the macro just
-- targets; with mobs too, attack and cast keep their [harm] guards so a
-- friendly NPC is never attacked.
local function MacroOptions(entries)
    local hasMob, hasNpc = false, false
    for _, entry in ipairs(entries) do
        if entry.kind == "kill" then
            hasMob = true
        else
            hasNpc = true
        end
    end
    if hasNpc and not hasMob then
        return { retarget = true }
    end
    local settings = SQG.db.hunt
    return {
        spell = ResolveSpellName(SQG:GetHuntSpell()),
        autoAttack = settings.autoAttack,
        keepConditions = hasNpc,
    }
end

function HuntController:Rebuild()
    if InCombatLockdown() then
        pendingRebuild = true
        return
    end
    pendingRebuild = false

    local provider = SQG.QuestProvider
    local quests = provider:GetHuntableQuests()
    local questieReady = provider:IsReady()
    local active = ActiveMobs(quests)

    SQG.HuntSelection:MigrateLegacy(quests)
    if questieReady then
        -- Drop checked mobs whose quest left the log or objective is done.
        SQG.HuntSelection:Prune(function(questId, name)
            return (active[questId] and active[questId][name]) ~= nil
        end)
    end

    local entries = ActiveEntries(active, questieReady)
    local orderedNames = {}
    for _, entry in ipairs(entries) do
        orderedNames[#orderedNames + 1] = entry.name
    end

    local macrotext, used = SQG.HuntMacroBuilder.Build(orderedNames, MacroOptions(entries))
    if used < #orderedNames then
        SQG:Debug("Macro full: using %d of %d mob names", used, #orderedNames)
    end

    -- A hand-edited macro (options page) replaces the generated one; the
    -- generated text is still kept in the model so the editor can show it.
    local custom = SQG.charDb.customMacro
    model = BuildModel(quests, entries, used)
    model.macro = { generated = macrotext, custom = custom, active = custom or macrotext }
    macrotext = model.macro.active
    SQG.HuntButton:SetHunt(macrotext, model)
    for _, view in ipairs(views) do
        view:Refresh(model)
    end
    SQG:Debug("Hunt macro (%d chars):\n%s", #macrotext, macrotext)
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

--- Checks or unchecks several mobs of one quest with a single rebuild.
function HuntController:SetMobs(questId, names, include)
    for _, name in ipairs(names) do
        SQG.HuntSelection:SetIncluded(questId, name, include)
    end
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

function HuntController:MoveMob(fromStoreIndex, toStoreIndex)
    SQG.HuntSelection:Move(fromStoreIndex, toStoreIndex)
    AfterSelectionChange()
end

function HuntController:RemoveMob(storeIndex)
    SQG.HuntSelection:RemoveAt(storeIndex)
    AfterSelectionChange()
end

--- Registers a view with a :Refresh(model) method.
function HuntController:AddView(view)
    views[#views + 1] = view
end

--- Saves a hand-edited macro (nil or blank goes back to the generated one).
function HuntController:SetCustomMacro(text)
    if text and strtrim(text) == "" then
        text = nil
    end
    SQG.charDb.customMacro = text
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

--- The last built model, without rebuilding. Selection changes rebuild
--- synchronously (out of combat), so an open menu can read live states here.
function HuntController:CurrentModel()
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
        getCurrentModel = function() return HuntController:CurrentModel() end,
        onMobToggled = function(questId, name) HuntController:ToggleMob(questId, name) end,
        onQuestToggled = function(questId) HuntController:ToggleQuest(questId) end,
        onClearAll = function() HuntController:ClearAll() end,
        onEditOrder = function() SQG.HuntListWindow:Toggle() end,
        onPickMobs = function(questId) SQG.HuntMobPicker:Open(questId) end,
        onOpenOptions = function() SQG.OptionsPanel:Open() end,
    })

    SQG.MacroEditor:Bind({
        getCurrentModel = function() return HuntController:CurrentModel() end,
        onSave = function(text) HuntController:SetCustomMacro(text) end,
        onReset = function() HuntController:SetCustomMacro(nil) end,
    })
    self:AddView(SQG.MacroEditor)

    SQG.HuntMobPicker:Create({
        getModel = function() return HuntController:GetModel() end,
        onMobToggled = function(questId, name) HuntController:ToggleMob(questId, name) end,
        onSetMobs = function(questId, names, include) HuntController:SetMobs(questId, names, include) end,
    })
    self:AddView(SQG.HuntMobPicker)

    SQG.HuntListWindow:Create({
        getModel = function() return HuntController:GetModel() end,
        onMove = function(from, to) HuntController:MoveMob(from, to) end,
        onRemove = function(index) HuntController:RemoveMob(index) end,
    })
    self:AddView(SQG.HuntListWindow)

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
