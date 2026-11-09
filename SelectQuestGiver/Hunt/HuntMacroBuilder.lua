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
--
-- Options for friendly NPCs (talk / turn-in targets):
--   keepConditions  never drop "[harm,nodead]", so a friendly NPC in the list
--                   is targeted but never attacked or cast at.
--   retarget        always switch to the highest-priority name in range, even
--                   if something else is targeted (used when only NPCs are
--                   listed). A button press can't clear and then target (the
--                   clear uses up the press's target change), so instead of
--                   "/cleartarget" + "[noexists]" it lists plain target lines
--                   lowest priority first: the last name found wins.
local _, SQG = ...

local HuntMacroBuilder = {}
SQG.HuntMacroBuilder = HuntMacroBuilder

HuntMacroBuilder.MAX_LENGTH = 255

local HEAD = "/cleartarget [dead]"
local EXACT_PREFIX = "/targetexact [noexists] "
local SHORT_PREFIX = "/tar [noexists] "
local RETARGET_EXACT_PREFIX = "/targetexact "
local RETARGET_SHORT_PREFIX = "/tar "
local UPGRADE_COST = #EXACT_PREFIX - #SHORT_PREFIX -- same for both forms

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
local function FitShort(names, head, shortPrefix, tail)
    local fixed = { head }
    for _, line in ipairs(tail) do
        fixed[#fixed + 1] = line
    end
    local budget = HuntMacroBuilder.MAX_LENGTH - LinesLength(fixed)
    local used = 0
    for _, name in ipairs(names) do
        local cost = 1 + #shortPrefix + #name -- each line also adds a "\n"
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
---@param options { spell: string?, autoAttack: boolean?, keepConditions: boolean?, retarget: boolean? }
---@return string macrotext
---@return number namesUsed  how many (deduplicated) names fit
---@return boolean[] exact   exact[i] is true when name i uses /targetexact
function HuntMacroBuilder.Build(mobNames, options)
    options = options or {}
    local names = UniqueNames(mobNames)

    -- 1 + 2. Most names in the short form; compact tail only if it fits more.
    local retarget = options.retarget
    local head = not retarget and HEAD or nil
    local exactPrefix = retarget and RETARGET_EXACT_PREFIX or EXACT_PREFIX
    local shortPrefix = retarget and RETARGET_SHORT_PREFIX or SHORT_PREFIX
    local tail = retarget and {} or TailLines(options, false)
    local used, budget = FitShort(names, head, shortPrefix, tail)
    if not options.keepConditions and not retarget then
        local compactTail = TailLines(options, true)
        local compactUsed, compactBudget = FitShort(names, head, shortPrefix, compactTail)
        if compactUsed > used then
            tail, used, budget = compactTail, compactUsed, compactBudget
        end
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

    local targetLines = {}
    for i = 1, used do
        targetLines[i] = (exact[i] and exactPrefix or shortPrefix) .. names[i]
    end
    local lines = { head }
    if retarget then
        -- Lowest priority first, so the highest-priority name found is the
        -- last target set.
        for i = used, 1, -1 do
            lines[#lines + 1] = targetLines[i]
        end
    else
        for i = 1, used do
            lines[#lines + 1] = targetLines[i]
        end
    end
    for _, line in ipairs(tail) do
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n"), used, exact
end
