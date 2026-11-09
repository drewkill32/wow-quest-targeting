-- Run: luajit tests/test_profile_store.lua   (from the repo root)
local SQG = {}
assert(loadfile("SelectQuestGiver/ProfileStore.lua"))("SelectQuestGiver", SQG)
local Store = SQG.ProfileStore

local failures = 0
local function check(name, cond)
    print((cond and "ok   " or "FAIL ") .. name)
    if not cond then failures = failures + 1 end
end

local DEFAULTS = { enabled = true, hunt = { scale = 1, spell = "" } }

do
    local root = {}
    local store = Store.New(root, "Thrall - Forever", DEFAULTS)
    check("new character gets its own profile", store:CurrentName() == "Thrall - Forever")
    check("profile has defaults", store:Current().hunt.scale == 1 and store:Current().enabled == true)
end

do
    -- Pre-profile settings become "Default"; characters start from a copy.
    local root = { enabled = false, hunt = { scale = 1.5, autoAttack = false } }
    local store = Store.New(root, "Jaina - Forever", DEFAULTS)
    check("legacy keys moved out of root", root.enabled == nil and root.hunt == nil)
    check("legacy saved as Default", root.profiles.Default.hunt.scale == 1.5)
    check("character seeded from Default", store:Current().hunt.scale == 1.5 and store:Current().enabled == false)
    store:Current().hunt.scale = 2
    check("seed is a copy, not shared", root.profiles.Default.hunt.scale == 1.5)
end

do
    local root = {}
    local a = Store.New(root, "A - R", DEFAULTS)
    a:Current().hunt.spell = "Judgement"
    local b = Store.New(root, "B - R", DEFAULTS)
    check("characters don't share by default", b:Current().hunt.spell == "")
    b:Use("A - R")
    check("switch to another profile shares it", b:Current().hunt.spell == "Judgement")
    b:Use("Shared")
    check("new profile has defaults", b:Current().hunt.spell == "" and b:CurrentName() == "Shared")
    check("copy from", b:CopyFrom("A - R") and b:Current().hunt.spell == "Judgement")
    check("copy is independent", (function()
        b:Current().hunt.spell = "Holy Light"
        return root.profiles["A - R"].hunt.spell == "Judgement"
    end)())
    check("can't delete active", not b:Delete("Shared"))
    check("delete other", b:Delete("B - R") and not b:Exists("B - R"))
    b:Reset()
    check("reset to defaults", b:Current().hunt.spell == "" and b:CurrentName() == "Shared")
    local names = table.concat(b:List(), ",")
    check("list sorted", names == "A - R,Shared")
end

do
    -- A character whose profile was deleted elsewhere gets its own again.
    local root = {}
    Store.New(root, "A - R", DEFAULTS):Use("Gone")
    local other = Store.New(root, "B - R", DEFAULTS)
    other:Delete("Gone")
    local again = Store.New(root, "A - R", DEFAULTS)
    check("deleted profile falls back to own", again:CurrentName() == "A - R")
end

if failures > 0 then
    print(failures .. " test(s) failed")
    os.exit(1)
end
print("all tests passed")
