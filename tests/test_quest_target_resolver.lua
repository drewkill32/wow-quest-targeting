-- Run: luajit tests/test_quest_target_resolver.lua   (from the repo root)
local SQG = {}
assert(loadfile("SelectQuestGiver/Providers/QuestTargetResolver.lua"))("SelectQuestGiver", SQG)
local Resolver = SQG.QuestTargetResolver

local failures = 0
local function check(name, cond)
    print((cond and "ok   " or "FAIL ") .. name)
    if not cond then failures = failures + 1 end
end

-- Fake QuestieDB with the fields the resolver reads.
local npcs = {
    [1] = { name = "Kobold Vermin" },
    [2] = { name = "Grizzled Bear" },
    [3] = { name = "Young Bear" },
    [4] = { name = "Marshal Dughan", friendly = "A", flags = 2 },
    [5] = { name = "Innkeeper Farley", friendly = "AH", flags = 3 },
    [6] = { name = "Goretusk" },
    [7] = { name = "Vendor Joe", friendly = "AH", flags = 128 },
    [8] = { name = "Dummy Credit" },
    [9] = { name = "Totem Target A" },
    [10] = { name = "Totem Target B" },
    [11] = { name = "Zhevra Runner", friendly = "AH" }, -- neutral beast: no NPC flags
}
local items = {
    [100] = { name = "Grizzled Bear Heart", drops = { 2, 3, 7 } },
    [101] = { name = "Goretusk Liver", drops = { 6 } },
    [102] = { name = "Zhevra Hooves", drops = { 11 } },
}
local quests = {
    [10] = { objectives = { { { 1 } }, nil, { { 100 } } } },
    [11] = { objectives = { { { 4, "Speak with Marshal Dughan" } } } },
    [12] = { objectives = {}, finishedBy = { { 5, 4 } } },
    [13] = { objectives = { nil, nil, { { 101 }, { 100 } } } },
    [14] = { objectives = { [5] = { { { 9, 10 }, 8, "Totems tested" } } } },
    [16] = { objectives = { { { 11 } }, nil, { { 102 } } } },
}
local db = {
    Quest = {
        objectives = function(id) return quests[id] and quests[id].objectives end,
        finishedBy = function(id) return quests[id] and quests[id].finishedBy end,
    },
    Npc = {
        name = function(id) return npcs[id] and npcs[id].name end,
        friendlyToFaction = function(id) return npcs[id] and npcs[id].friendly end,
        npcFlags = function(id) return npcs[id] and npcs[id].flags end,
    },
    Item = {
        name = function(id) return items[id] and items[id].name end,
        npcDrops = function(id) return items[id] and items[id].drops end,
    },
}
local resolver = Resolver.New(db, "A")

local function Names(group)
    return table.concat(group.mobNames, ",")
end

check("label strips trailing counter", Resolver.ObjectiveLabel("Kobold Vermin slain: 3/10") == "Kobold Vermin slain")
check("label strips leading counter", Resolver.ObjectiveLabel("0/6 Skittering Blood") == "Skittering Blood")

do
    local groups = resolver:Resolve({ id = 10, objectives = {
        { text = "Kobold Vermin slain: 0/10", type = "monster", finished = false },
        { text = "Grizzled Bear Heart: 1/5", type = "item", finished = false },
    } })
    check("kill + item: two groups", #groups == 2)
    check("kill objective -> mob", groups[1].kind == "kill" and Names(groups[1]) == "Kobold Vermin")
    check("item objective -> hostile droppers, vendor skipped", Names(groups[2]) == "Grizzled Bear,Young Bear"
        and groups[2].label == "Grizzled Bear Heart")
end

do
    local groups = resolver:Resolve({ id = 10, objectives = {
        { text = "Kobold Vermin slain: 10/10", type = "monster", finished = true },
        { text = "Grizzled Bear Heart: 1/5", type = "item", finished = false },
    } })
    check("finished objective dropped", #groups == 1 and groups[1].label == "Grizzled Bear Heart")
end

do
    local groups = resolver:Resolve({ id = 11, objectives = {
        { text = "Speak with Marshal Dughan", type = "monster", finished = false },
    } })
    check("friendly creature -> talk", #groups == 1 and groups[1].kind == "talk" and Names(groups[1]) == "Marshal Dughan")
end

do
    local groups = resolver:Resolve({ id = 12, isComplete = true, objectives = {} })
    check("complete -> turn-in NPCs", #groups == 1 and groups[1].kind == "turnin"
        and Names(groups[1]) == "Innkeeper Farley,Marshal Dughan")
end

do
    -- Log order differs from the database order: matched by name.
    local groups = resolver:Resolve({ id = 13, objectives = {
        { text = "Grizzled Bear Heart: 0/5", type = "item", finished = false },
        { text = "Goretusk Liver: 0/8", type = "item", finished = false },
    } })
    check("items matched by name", groups[1].label == "Grizzled Bear Heart" and Names(groups[1]) == "Grizzled Bear,Young Bear"
        and Names(groups[2]) == "Goretusk")
end

do
    -- Unknown text falls back to database order.
    local groups = resolver:Resolve({ id = 13, objectives = {
        { text = "Something: 0/8", type = "item", finished = false },
    } })
    check("fallback to order", #groups == 1 and Names(groups[1]) == "Goretusk")
end

do
    local groups = resolver:Resolve({ id = 14, objectives = {
        { text = "Totems tested: 0/2", type = "monster", finished = false },
    } })
    check("kill credit -> all credited mobs", #groups == 1 and Names(groups[1]) == "Totem Target A,Totem Target B")
end

do
    local groups = resolver:Resolve({ id = 10, objectives = {
        { text = "Use the thing", type = "event", finished = false },
    } })
    check("event objective has no targets", #groups == 0)
end

do
    -- Talk groups sort before kill groups.
    quests[15] = { objectives = { { { 1 }, { 4 } } } }
    local groups = resolver:Resolve({ id = 15, objectives = {
        { text = "Kobold Vermin slain: 0/1", type = "monster", finished = false },
        { text = "Marshal Dughan", type = "monster", finished = false },
    } })
    check("talk first", groups[1].kind == "talk" and groups[2].kind == "kill")
end

do
    -- Neutral beasts are "AH" but have no NPC flags: still kill targets.
    local groups = resolver:Resolve({ id = 16, objectives = {
        { text = "Zhevra Hooves: 0/4", type = "item", finished = false },
    } })
    check("neutral beast drops item", #groups == 1 and groups[1].kind == "kill" and Names(groups[1]) == "Zhevra Runner")
    groups = resolver:Resolve({ id = 16, objectives = {
        { text = "Zhevra Runner slain: 0/4", type = "monster", finished = false },
    } })
    check("neutral beast kill objective is kill", #groups == 1 and groups[1].kind == "kill")
end

if failures > 0 then
    print(failures .. " test(s) failed")
    os.exit(1)
end
print("all tests passed")
