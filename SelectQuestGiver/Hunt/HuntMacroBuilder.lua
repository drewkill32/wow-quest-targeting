-- Pure macro-text builder for the hunt button. No WoW API calls, so it can be
-- unit tested outside the game (see tests/test_hunt_macro_builder.lua).
--
-- A single macro is capped at 255 characters, so the lines are split across a
-- chain of macros: each one ends with "/click <next chain button>", and the
-- attack/cast lines always come last. One press runs the whole chain.
local _, SQG = ...

local HuntMacroBuilder = {}
SQG.HuntMacroBuilder = HuntMacroBuilder

HuntMacroBuilder.MAX_LENGTH = 255

local function Trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

local function TargetLines(mobNames)
    local lines, seen = {}, {}
    for _, name in ipairs(mobNames or {}) do
        name = Trim(name)
        if name ~= "" and not seen[name] then
            seen[name] = true
            lines[#lines + 1] = "/targetexact [noexists] " .. name
        end
    end
    return lines
end

local function TailLines(options)
    local tail = {}
    if options.autoAttack then
        tail[#tail + 1] = "/startattack [harm,nodead]"
    end
    local spell = Trim(options.spell)
    if spell ~= "" then
        tail[#tail + 1] = "/cast [harm,nodead] " .. spell
    end
    return tail
end

-- Greedily packs `lines` into macros of at most MAX_LENGTH characters.
-- Every macro except the last ends with "/click <chainNames[i]>".
-- Returns nil if more than 1 + #chainNames macros would be needed.
local function Pack(lines, chainNames)
    local maxLength = HuntMacroBuilder.MAX_LENGTH
    local macros, current = {}, {}

    local function CurrentLength(extraLine)
        local text = table.concat(current, "\n")
        if extraLine then
            text = (#current > 0) and (text .. "\n" .. extraLine) or extraLine
        end
        return #text
    end

    for _, line in ipairs(lines) do
        local nextClick = chainNames[#macros + 1]
        local reserve = nextClick and (#"\n/click " + #nextClick) or 0
        if #current > 0 and CurrentLength(line) + reserve > maxLength then
            if not nextClick then
                return nil
            end
            current[#current + 1] = "/click " .. nextClick
            macros[#macros + 1] = table.concat(current, "\n")
            current = {}
        end
        if #line > maxLength then
            return nil
        end
        current[#current + 1] = line
    end
    macros[#macros + 1] = table.concat(current, "\n")
    return macros
end

--- Builds the chain of macro texts.
---@param mobNames string[] names to try, in priority order
---@param options { spell: string?, autoAttack: boolean?, chainNames: string[]? }
---   chainNames: global names of the extra buttons, in order (may be empty)
---@return string[] macros  macros[1] goes on the main button, macros[i+1] on chainNames[i]
---@return number namesUsed  how many (deduplicated) names fit
function HuntMacroBuilder.Build(mobNames, options)
    options = options or {}
    local chainNames = options.chainNames or {}
    local targets = TargetLines(mobNames)
    local tail = TailLines(options)

    -- Use as many names as fit; drop from the end if the chain runs out.
    for count = #targets, 0, -1 do
        local lines = { "/cleartarget [dead]" }
        for i = 1, count do
            lines[#lines + 1] = targets[i]
        end
        for _, line in ipairs(tail) do
            lines[#lines + 1] = line
        end
        local macros = Pack(lines, chainNames)
        if macros then
            return macros, count
        end
    end
    return { "/cleartarget [dead]" }, 0
end
