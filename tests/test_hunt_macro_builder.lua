-- Run: luajit tests/test_hunt_macro_builder.lua   (from the repo root)
local SQG = {}
assert(loadfile("SelectQuestGiver/Hunt/HuntMacroBuilder.lua"))("SelectQuestGiver", SQG)
local Builder = SQG.HuntMacroBuilder
local Build = Builder.Build

local failures = 0
local function check(name, cond)
    print((cond and "ok   " or "FAIL ") .. name)
    if not cond then failures = failures + 1 end
end

local CAST = "/cast [harm,nodead] Judgement"
local ATTACK = "/startattack [harm,nodead]"
local FULL = { spell = "Judgement", autoAttack = true }

local function EndsWith(text, suffix)
    return text:sub(-#suffix) == suffix
end

local function Count(text, pattern)
    local n = 0
    for _ in text:gmatch(pattern) do n = n + 1 end
    return n
end

do
    -- Conditions are only dropped when that fits more names.
    local text = Build({ "A", "B" }, FULL)
    check("short list keeps [harm,nodead]", EndsWith(text, ATTACK .. "\n" .. CAST))
end

do
    local text, used = Build({}, {})
    check("no names -> only cleartarget", text == "/cleartarget [dead]" and used == 0)
end

do
    local text, used, exact = Build({ "Grizzly Bear" }, FULL)
    check("room to spare -> exact form", text == table.concat({
        "/cleartarget [dead]",
        "/targetexact [noexists] Grizzly Bear",
        ATTACK,
        CAST,
    }, "\n") and used == 1 and exact[1] == true)
end

do
    local text = Build({ "Grizzly Bear" }, { spell = "  ", autoAttack = false })
    check("blank spell + no autoattack -> target only",
        text == "/cleartarget [dead]\n/targetexact [noexists] Grizzly Bear")
end

do
    local _, used = Build({ "A", "B", "A", " B ", "" }, {})
    check("dedupes and trims names", used == 2)
end

-- The real list from the hunt priority window.
local REAL = {
    "Krethis Shadowspinner", "Moss Stalker", "Mist Creeper", "Searing Blade Cultist",
    "Searing Blade Enforcer", "Nightlash", "Moonrage Darkrunner",
}

do
    local text, used, exact = Build(REAL, FULL)
    print(("  real list: %d/%d names, %d chars\n%s"):format(used, #REAL, #text, text))
    check("real list: within 255", #text <= Builder.MAX_LENGTH)
    check("real list: more names than all-exact would fit", used >= 5)
    check("real list: compact tail used to fit more", EndsWith(text, "/startattack\n/cast Judgement"))
    check("real list: no /click", not text:find("/click", 1, true))
    -- Exact upgrades go to the top of the list first.
    local sawShort, ordered = false, true
    for i = 1, used do
        if exact[i] == false then sawShort = true elseif sawShort then ordered = false end
    end
    check("real list: exact lines come first (priority order)", ordered)
    check("real list: line kinds match flags",
        Count(text, "/targetexact ") + Count(text, "/tar %[") == used)
end

do
    local names = {}
    for i = 1, 40 do names[i] = "Some Fairly Long Mob Name " .. i end
    local text, used = Build(names, FULL)
    check("long list: within 255", #text <= Builder.MAX_LENGTH)
    check("long list: keeps the first names in order",
        used > 0 and used < 40 and text:find("Name 1\n", 1, true) ~= nil and not text:find("Name " .. (used + 1) .. "\n", 1, true))
    check("long list: cast still last", EndsWith(text, "Judgement"))
end

do
    -- Every size 1..30 stays within the cap and keeps the tail.
    local ok = true
    for n = 1, 30 do
        local names = {}
        for i = 1, n do names[i] = "Mob Number " .. i end
        local text, used = Build(names, FULL)
        if #text > Builder.MAX_LENGTH or not EndsWith(text, "Judgement") or used > n then ok = false end
        local _, usedWithoutTail = Build(names, {})
        if usedWithoutTail < used then ok = false end
    end
    check("sweep 1..30: within cap, tail kept", ok)
end

do
    -- Friendly NPCs mixed in: conditions stay even when dropping them fits more.
    local text = Build(REAL, { spell = "Judgement", autoAttack = true, keepConditions = true })
    check("keepConditions: guarded tail kept", EndsWith(text, ATTACK .. "\n" .. CAST))
    check("keepConditions: within 255", #text <= Builder.MAX_LENGTH)
end

do
    -- Only NPCs: no clear, plain target lines, lowest priority first.
    local text = Build({ "Innkeeper Farley", "Marshal Dughan" }, { retarget = true, spell = "Judgement", autoAttack = true })
    check("retarget: no clear, reversed plain targets, no attack", text == table.concat({
        "/targetexact Marshal Dughan",
        "/targetexact Innkeeper Farley",
    }, "\n"))
    local names = {}
    for i = 1, 30 do names[i] = "Some Long Friendly Npc Name " .. i end
    local long, used = Build(names, { retarget = true })
    check("retarget: long list within 255, top priority last", #long <= Builder.MAX_LENGTH
        and used > 0 and EndsWith(long, "Name 1"))
end

do
    local MENU = "/sqg menu\n/stopmacro [btn:2]\n"
    local text = Build({ "A" }, { rightClickMenu = true, spell = "Judgement", autoAttack = true })
    check("rightClickMenu: menu lines first", text:sub(1, #MENU) == MENU)
    check("rightClickMenu: then the usual macro", text:sub(#MENU + 1) == Build({ "A" }, FULL))
    local npc = Build({ "Innkeeper Farley" }, { rightClickMenu = true, retarget = true })
    check("rightClickMenu + retarget", npc == MENU .. "/targetexact Innkeeper Farley")
    local names = {}
    for i = 1, 40 do names[i] = "Long Mob Name " .. i end
    local plain, plainUsed = Build(names, FULL)
    local withMenu, menuUsed = Build(names, { rightClickMenu = true, spell = "Judgement", autoAttack = true })
    check("rightClickMenu: within 255", #withMenu <= Builder.MAX_LENGTH and #plain <= Builder.MAX_LENGTH)
    check("rightClickMenu: costs room", menuUsed < plainUsed)

    check("WithRightClickMenu adds lines", Builder.WithRightClickMenu("/tar X") == MENU .. "/tar X")
    check("WithRightClickMenu is idempotent", Builder.WithRightClickMenu(MENU .. "/tar X") == MENU .. "/tar X")
    local full = string.rep("x", 250)
    check("WithRightClickMenu leaves a full macro alone", Builder.WithRightClickMenu(full) == full)
end

if failures > 0 then
    print(failures .. " test(s) failed")
    os.exit(1)
end
print("all tests passed")
