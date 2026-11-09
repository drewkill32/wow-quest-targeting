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
--   noDead          add "nodead" to the target conditions
--                   ("/tar [noexists,nodead] Name", "/tar [nodead] Name" when
--                   retargeting). Costs 7-9 characters per name.
--   rightClickMenu  start with MENU_LINES so a right-click on an action bar
--                   copy of the macro opens the hunt menu ("/sqg menu" only
--                   acts on right-clicks) and then stops before targeting.
local _, SQG = ...

local HuntMacroBuilder = {}
SQG.HuntMacroBuilder = HuntMacroBuilder

HuntMacroBuilder.MAX_LENGTH = 255

local HEAD = "/cleartarget [dead]"
local EXACT_COMMAND = "/targetexact "
local SHORT_COMMAND = "/tar "
-- Right-click on an action bar macro: open the menu, then stop.
HuntMacroBuilder.MENU_LINES = { "/sqg menu", "/stopmacro [btn:2]" }
local UPGRADE_COST = #EXACT_COMMAND - #SHORT_COMMAND -- same whatever the conditions

-- Exact and short target-line prefixes for the options, e.g.
-- "/targetexact [noexists] " and "/tar [noexists] ".
local function TargetPrefixes(options)
    local conditions = {}
    if not options.retarget then
        conditions[#conditions + 1] = "noexists"
    end
    if options.noDead then
        conditions[#conditions + 1] = "nodead"
    end
    local condition = #conditions > 0 and ("[" .. table.concat(conditions, ",") .. "] ") or ""
    return EXACT_COMMAND .. condition, SHORT_COMMAND .. condition
end

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

local function Append(lines, more)
    for _, line in ipairs(more) do
        lines[#lines + 1] = line
    end
    return lines
end

-- How many names fit in the short form between the lead and tail lines;
-- returns count and the budget left over.
local function FitShort(names, lead, shortPrefix, tail)
    local fixed = Append({}, lead)
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
---@param options { spell: string?, autoAttack: boolean?, keepConditions: boolean?, retarget: boolean?, noDead: boolean?, rightClickMenu: boolean? }
---@return string macrotext
---@return number namesUsed  how many (deduplicated) names fit
---@return boolean[] exact   exact[i] is true when name i uses /targetexact
function HuntMacroBuilder.Build(mobNames, options)
    options = options or {}
    local names = UniqueNames(mobNames)

    -- 1 + 2. Most names in the short form; compact tail only if it fits more.
    local retarget = options.retarget
    local lead = options.rightClickMenu and Append({}, HuntMacroBuilder.MENU_LINES) or {}
    if not retarget then
        lead[#lead + 1] = HEAD
    end
    local exactPrefix, shortPrefix = TargetPrefixes(options)
    local tail = retarget and {} or TailLines(options, false)
    local used, budget = FitShort(names, lead, shortPrefix, tail)
    if not options.keepConditions and not retarget then
        local compactTail = TailLines(options, true)
        local compactUsed, compactBudget = FitShort(names, lead, shortPrefix, compactTail)
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
    local lines = Append({}, lead)
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

--- Adds MENU_LINES to the top of a hand-written macro when they aren't there
--- yet and still fit; otherwise returns it unchanged.
function HuntMacroBuilder.WithRightClickMenu(text)
    local menu = table.concat(HuntMacroBuilder.MENU_LINES, "\n")
    if text:sub(1, #menu) == menu or #menu + 1 + #text > HuntMacroBuilder.MAX_LENGTH then
        return text
    end
    return menu .. "\n" .. text
end
