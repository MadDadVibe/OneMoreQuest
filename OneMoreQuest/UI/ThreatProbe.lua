-- One More Quest: /omq threat (decision 333, step 1 of the threat meter: look at the data first)
-- Asks the game for the threat of the player, the pet, the party and their pets on the current target and
-- prints one line per unit, so we can see on WoW Forever what really arrives and what is "secret".
--   /omq threat        one report for the current target
--   /omq threat live   one compact report every second until you type it again (pull tests)
-- Per line: tank flag, status 0-3, scaled % (0-100, 100 = this unit is the target), raw % (relative to the
-- tank; it can be above 100 before the pull: melee pulls at 110, ranged at 130) and the threat value.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local T = {}
OMQ.ThreatProbe = T

T.UNITS = { "player", "pet", "party1", "party2", "party3", "party4",
            "partypet1", "partypet2", "partypet3", "partypet4" }
local MOB = "target"

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
-- a value as text: "secret", "-" for nil, else the number rounded
local function fmt(v)
    if v == nil then return "-" end
    if isSecret(v) then return "secret" end
    if type(v) == "number" then return string.format("%.0f", v) end
    return tostring(v)
end
T.Fmt = fmt

-- one unit against the mob: a table of what the game answered (nothing invented)
function T.Read(unit, mob)
    local r = { unit = unit }
    if not (UnitExists and UnitExists(unit)) then return nil end
    local okN, name = pcall(UnitName, unit)
    r.name = okN and name or "?"
    if isSecret(r.name) then r.name = "secret" end
    if not UnitDetailedThreatSituation then r.err = "UnitDetailedThreatSituation missing"; return r end
    local ok, tank, status, scaled, raw, value = pcall(UnitDetailedThreatSituation, unit, mob)
    if not ok then r.err = tostring(tank); return r end
    r.tank, r.status, r.scaled, r.raw, r.value = tank, status, scaled, raw, value
    r.none = (status == nil and scaled == nil and raw == nil and value == nil)
    return r
end

function T.Line(r)
    if r.err then return string.format("%-9s %s: error %s", r.unit, r.name, r.err) end
    if r.none then return string.format("%-9s %s: no threat", r.unit, r.name) end
    local tank = isSecret(r.tank) and "secret" or (r.tank and "TANK" or "-")
    local over = ""
    if not isSecret(r.raw) and type(r.raw) == "number" and r.raw > 100 and not r.tank then over = "  (over the tank)" end
    return string.format("%-9s %s: %s  status %s  scaled %s  raw %s  value %s%s",
        r.unit, r.name, tank, fmt(r.status), fmt(r.scaled), fmt(r.raw), fmt(r.value), over)
end

local function targetLine()
    if not (UnitExists and UnitExists(MOB)) then return nil end
    local okN, name = pcall(UnitName, MOB)
    local okC, class = pcall(UnitClassification, MOB)
    local okL, lvl = pcall(UnitLevel, MOB)
    local okA, attack = pcall(UnitCanAttack, "player", MOB)
    return string.format("target: %s  %s  level %s  attackable %s",
        okN and fmt(name) or "?", okC and fmt(class) or "?", okL and fmt(lvl) or "?", okA and tostring(attack) or "?")
end

-- the lines of one report (a list of strings)
function T.Report()
    local out = {}
    local tl = targetLine()
    if not tl then out[1] = "threat: no target"; return out end
    out[1] = tl
    if OMQ.ThreatMeter then
        local role, mt = OMQ.ThreatMeter.MyGroupRole()
        out[#out + 1] = string.format("my group role: %s%s  tank mode: %s", tostring(role or "none"), mt and " + main tank" or "",
            OMQ.ThreatMeter.TankMode() and "on" or "off")
    end
    local any = false
    for _, u in ipairs(T.UNITS) do
        local r = T.Read(u, MOB)
        if r then any = true; out[#out + 1] = T.Line(r) end
    end
    if not any then out[#out + 1] = "no unit answered" end
    return out
end

T.live = false
local function tick()
    if not T.live then return end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        local tl = targetLine()
        if tl then
            local parts = {}
            for _, u in ipairs(T.UNITS) do
                local r = T.Read(u, MOB)
                if r and not r.err and not r.none then
                    parts[#parts + 1] = string.format("%s %s/%s%s", r.name, fmt(r.scaled), fmt(r.raw), r.tank == true and "T" or "")
                end
            end
            OMQ:Print("threat " .. (#parts > 0 and table.concat(parts, "  ") or "nothing readable"))
        end
    end
    C_Timer.After(1, tick)
end

OMQ:RegisterCommand("threat", function(arg)
    arg = (arg or ""):lower():gsub("%s+", "")
    if arg == "reset" then
        if OMQ.ThreatMeter then OMQ.ThreatMeter.ResetPosition() end
        OMQ:Print("threat meter: position reset")
        return
    end
    if arg == "live" then
        T.live = not T.live
        OMQ:Print("threat live " .. (T.live and "on (every second, in combat)" or "off"))
        if T.live then C_Timer.After(0, tick) end
        return
    end
    for _, l in ipairs(T.Report()) do print(l) end
end, "threat: /omq threat (report) | live (every second) | reset (meter position)")
