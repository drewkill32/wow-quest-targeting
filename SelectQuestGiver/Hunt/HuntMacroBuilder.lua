-- Pure macro-text builder for the hunt button. No WoW API calls, so it can be
-- unit tested outside the game (see tests/test_hunt_macro_builder.lua).
--
-- WoW Forever caps a button macro at 255 characters, and a macro can't /click
-- another button that runs a macro (11.0 rule), so everything must fit in one
-- macro. To fit as many mobs as possible:
--   1. Every mob starts with the short form   "/tar [noexists] Name"
--      and we take as many mobs (in priority order) as fit.
--   2. If dropping the attack/cast conditions ("/startattack", "/cast Spell"
--      instead of "... [harm,nodead] ...") fits more mobs, do that. The
--      leading "/cleartarget [dead]" already drops dead targets.
--   3. Leftover room upgrades mobs, top priority first, to the exact form
--      "/targetexact [noexists] Name" (only matches that exact name; /tar
--      can also match a different mob whose name starts the same way).
local _, SQG = ...

local HuntMacroBuilder = {}
SQG.HuntMacroBuilder = HuntMacroBuilder

HuntMacroBuilder.MAX_LENGTH = 255

local HEAD = "/cleartarget [dead]"
local EXACT_PREFIX = "/targetexact [noexists] "
local SHORT_PREFIX = "/tar [noexists] "
local UPGRADE_COST = #EXACT_PREFIX - #SHORT_PREFIX

local function Trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

local function UniqueNames(mobNames)
    local names, seen = {}, {}
    for _, name in ipairs(mobNames or {}) do
        name = Trim(name)
        if name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

local function TailLines(options, compact)
    local condition = compact and "" or " [harm,nodead]"
    local tail = {}
    if options.autoAttack then
        tail[#tail + 1] = "/startattack" .. condition
    end
    local spell = Trim(options.spell)
    if spell ~= "" then
        tail[#tail + 1] = "/cast" .. condition .. " " .. spell
    end
    return tail
end

-- Characters a list of lines takes, counting the "\n" between them.
local function LinesLength(lines)
    local total = 0
    for _, line in ipairs(lines) do
        total = total + #line
    end
    return total + math.max(0, #lines - 1)
end

-- How many names fit in the short form with this tail; returns count and the
-- budget left over.
local function FitShort(names, tail)
    local fixed = { HEAD }
    for _, line in ipairs(tail) do
        fixed[#fixed + 1] = line
    end
    local budget = HuntMacroBuilder.MAX_LENGTH - LinesLength(fixed)
    local used = 0
    for _, name in ipairs(names) do
        local cost = 1 + #SHORT_PREFIX + #name -- each line also adds a "\n"
        if cost > budget then
            break
        end
        budget = budget - cost
        used = used + 1
    end
    return used, budget
end

--- Builds the macro text.
---@param mobNames string[] names to try, in priority order
---@param options { spell: string?, autoAttack: boolean? }
---@return string macrotext
---@return number namesUsed  how many (deduplicated) names fit
---@return boolean[] exact   exact[i] is true when name i uses /targetexact
function HuntMacroBuilder.Build(mobNames, options)
    options = options or {}
    local names = UniqueNames(mobNames)

    -- 1 + 2. Most names in the short form; compact tail only if it fits more.
    local tail = TailLines(options, false)
    local used, budget = FitShort(names, tail)
    local compactTail = TailLines(options, true)
    local compactUsed, compactBudget = FitShort(names, compactTail)
    if compactUsed > used then
        tail, used, budget = compactTail, compactUsed, compactBudget
    end

    -- 3. Upgrade to the exact form, highest priority first, while room remains.
    local exact = {}
    for i = 1, used do
        if UPGRADE_COST <= budget then
            exact[i] = true
            budget = budget - UPGRADE_COST
        else
            exact[i] = false
        end
    end

    local lines = { HEAD }
    for i = 1, used do
        lines[#lines + 1] = (exact[i] and EXACT_PREFIX or SHORT_PREFIX) .. names[i]
    end
    for _, line in ipairs(tail) do
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n"), used, exact
end
