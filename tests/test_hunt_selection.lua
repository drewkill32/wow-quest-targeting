-- Run: luajit tests/test_hunt_selection.lua   (from the repo root)
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local SQG = { charDb = { huntOrder = {} } }
assert(loadfile("SelectQuestGiver/Hunt/HuntSelection.lua"))("SelectQuestGiver", SQG)
local S = SQG.HuntSelection

local failures = 0
local function check(name, cond)
    print((cond and "ok   " or "FAIL ") .. name)
    if not cond then failures = failures + 1 end
end

local function Names()
    local out = {}
    for _, e in ipairs(S:GetOrdered()) do out[#out + 1] = e.name end
    return table.concat(out, ",")
end

local bears = { "Giant Grizzled Bear", "Elmpaw", "Old Vicejaw" }

check("new quests start unchecked", not S:IsIncluded(100, "Elmpaw") and S:GetQuestState(100, bears) == "none")
S:ToggleMob(100, "Elmpaw")
check("toggle mob checks it", S:IsIncluded(100, "Elmpaw") and S:GetQuestState(100, bears) == "some")
check("same name in other quest unaffected", not S:IsIncluded(200, "Elmpaw"))
S:ToggleQuest(100, bears)
check("quest toggle from some -> all, new ones appended", Names() == "Elmpaw,Giant Grizzled Bear,Old Vicejaw")
S:ToggleQuest(100, bears)
check("quest toggle from all -> none", S:GetQuestState(100, bears) == "none" and #S:GetOrdered() == 0)

S:ToggleQuest(100, bears) -- Giant, Elmpaw, Old
S:Move(3, 1)
check("move last to first", Names() == "Old Vicejaw,Giant Grizzled Bear,Elmpaw")
S:Move(1, 3)
check("move first to last", Names() == "Giant Grizzled Bear,Elmpaw,Old Vicejaw")
S:Move(2, 99)
check("move clamps to end", Names() == "Giant Grizzled Bear,Old Vicejaw,Elmpaw")
S:RemoveAt(1)
check("remove at", Names() == "Old Vicejaw,Elmpaw")

S:SetIncluded(300, "Moss Stalker", true)
S:Prune(function(questId, name)
    if name == "Elmpaw" then return false end   -- objective finished
    if questId == 300 then return nil end       -- unknown, keep
    return true
end)
check("prune removes inactive, keeps unknown", Names() == "Old Vicejaw,Moss Stalker")

S:ClearAll()
check("clear all", #S:GetOrdered() == 0)

-- v1 migration: one quest, some mobs unchecked
SQG.charDb.huntQuestId = 500
SQG.charDb.huntExcluded = { ["500"] = { Elmpaw = true } }
local quests = { { id = 500, groups = { { mobNames = bears } } } }
S:MigrateLegacy({})
check("migration waits for quests", SQG.charDb.huntQuestId == 500)
S:MigrateLegacy(quests)
check("v1 migration keeps non-excluded mobs in order", Names() == "Giant Grizzled Bear,Old Vicejaw")
check("v1 migration clears legacy fields", SQG.charDb.huntQuestId == nil and SQG.charDb.huntExcluded == nil)

-- v2 migration: per-quest sets, ordered by quest list order
S:ClearAll()
SQG.charDb.huntIncluded = { ["600"] = { B = true }, ["500"] = { Elmpaw = true } }
S:MigrateLegacy({
    { id = 500, groups = { { mobNames = bears } } },
    { id = 600, groups = { { mobNames = { "A", "B" } } } },
})
check("v2 migration follows quest order", Names() == "Elmpaw,B" and SQG.charDb.huntIncluded == nil)

if failures > 0 then os.exit(1) end
print("all tests passed")
