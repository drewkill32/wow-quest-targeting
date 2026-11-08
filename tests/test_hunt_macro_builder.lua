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

local CHAIN = { "Chain1", "Chain2", "Chain3" }

local function ManyNames(n)
    local names = {}
    for i = 1, n do
        names[i] = "Some Fairly Long Mob Name " .. i
    end
    return names
end

do
    local macros, used = Build({}, {})
    check("no names -> only cleartarget", #macros == 1 and macros[1] == "/cleartarget [dead]" and used == 0)
end

do
    local macros = Build({ "Grizzly Bear" }, { spell = "Judgement", autoAttack = true, chainNames = CHAIN })
    check("short macro stays on one button", #macros == 1 and macros[1] == table.concat({
        "/cleartarget [dead]",
        "/targetexact [noexists] Grizzly Bear",
        "/startattack [harm,nodead]",
        "/cast [harm,nodead] Judgement",
    }, "\n"))
end

do
    local macros = Build({ "Grizzly Bear" }, { spell = "  ", autoAttack = false })
    check("blank spell + no autoattack -> target only",
        macros[1] == "/cleartarget [dead]\n/targetexact [noexists] Grizzly Bear")
end

do
    local _, used = Build({ "A", "B", "A", " B ", "" }, {})
    check("dedupes and trims names", used == 2)
end

do
    local macros, used = Build(ManyNames(40), { spell = "Judgement", autoAttack = true })
    check("no chain: one macro within cap", #macros == 1 and #macros[1] <= Builder.MAX_LENGTH)
    check("no chain: keeps first names", used > 0 and used < 40 and macros[1]:find("Name 1\n", 1, true) ~= nil)
    check("no chain: tail kept", macros[1]:sub(-#"/cast [harm,nodead] Judgement") == "/cast [harm,nodead] Judgement")
end

do
    local macros, used = Build(ManyNames(12), { spell = "Judgement", autoAttack = true, chainNames = CHAIN })
    check("chain: all 12 names fit", used == 12)
    check("chain: uses more than one macro", #macros > 1 and #macros <= 1 + #CHAIN)
    local allOk = true
    for i, text in ipairs(macros) do
        if #text > Builder.MAX_LENGTH then allOk = false end
        local expectedClick = CHAIN[i]
        local endsWithClick = expectedClick and text:sub(-#("/click " .. expectedClick)) == "/click " .. expectedClick
        if i < #macros and not endsWithClick then allOk = false end
        if i == #macros and text:find("/click", 1, true) then allOk = false end
    end
    check("chain: each macro within cap, linked by /click in order", allOk)
    check("chain: cleartarget first", macros[1]:sub(1, #"/cleartarget [dead]") == "/cleartarget [dead]")
    local joined = table.concat(macros, "\n")
    local lastTarget = joined:find("Name 12\n", 1, true)
    local attackAt = joined:find("/startattack [harm,nodead]", 1, true)
    local castAt = joined:find("/cast [harm,nodead] Judgement", 1, true)
    check("chain: attack then cast, after every target line",
        lastTarget and attackAt and castAt and lastTarget < attackAt and attackAt < castAt)
    check("chain: cast is the very last line", macros[#macros]:sub(-#"/cast [harm,nodead] Judgement") == "/cast [harm,nodead] Judgement")
    check("chain: names in order", joined:find("Name 1\n", 1, true) < joined:find("Name 12\n", 1, true))
end

do
    local macros, used = Build(ManyNames(200), { spell = "Judgement", autoAttack = true, chainNames = CHAIN })
    check("chain full: drops overflow names", used > 0 and used < 200)
    check("chain full: never more macros than buttons", #macros <= 1 + #CHAIN)
    check("chain full: tail still last",
        macros[#macros]:sub(-#"/cast [harm,nodead] Judgement") == "/cast [harm,nodead] Judgement")
end

if failures > 0 then
    print(failures .. " test(s) failed")
    os.exit(1)
end
print("all tests passed")
