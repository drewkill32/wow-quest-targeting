-- Run: luajit tests/test_hunt_selection.lua   (from the repo root)
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local SQG = { charDb = { huntIncluded = {} } }
assert(loadfile("SelectQuestGiver/Hunt/HuntSelection.lua"))("SelectQuestGiver", SQG)
local S = SQG.HuntSelection

local failures = 0
local function check(name, cond)
    print((cond and "ok   " or "FAIL ") .. name)
    if not cond then failures = failures + 1 end
end

local bears = { "Giant Grizzled Bear", "Elmpaw", "Old Vicejaw" }

check("new quests start unchecked", not S:IsIncluded(100, "Elmpaw") and S:GetQuestState(100, bears) == "none")
S:ToggleMob(100, "Elmpaw")
check("toggle mob checks it", S:IsIncluded(100, "Elmpaw") and S:GetQuestState(100, bears) == "some")
check("same name in other quest unaffected", not S:IsIncluded(200, "Elmpaw"))
S:ToggleQuest(100, bears)
check("quest toggle from some -> all", S:GetQuestState(100, bears) == "all")
S:ToggleQuest(100, bears)
check("quest toggle from all -> none", S:GetQuestState(100, bears) == "none")
check("empty quest set removed", SQG.charDb.huntIncluded["100"] == nil)

S:ToggleMob(300, "X")
S:ToggleMob(400, "Y")
S:Prune(function(id) if id == 300 then return false end return nil end)
check("prune drops quests not in log, keeps unknown", SQG.charDb.huntIncluded["300"] == nil and S:IsIncluded(400, "Y"))

S:ClearAll()
check("clear all", next(SQG.charDb.huntIncluded) == nil)

SQG.charDb.huntQuestId = 500
SQG.charDb.huntExcluded = { ["500"] = { Elmpaw = true } }
S:MigrateLegacy(function() return {} end)
check("migration waits for mob names", SQG.charDb.huntQuestId == 500)
S:MigrateLegacy(function() return bears end)
check("migration checks non-excluded mobs",
    S:IsIncluded(500, "Giant Grizzled Bear") and S:IsIncluded(500, "Old Vicejaw") and not S:IsIncluded(500, "Elmpaw"))
check("migration clears legacy fields", SQG.charDb.huntQuestId == nil and SQG.charDb.huntExcluded == nil)

if failures > 0 then os.exit(1) end
print("all tests passed")
