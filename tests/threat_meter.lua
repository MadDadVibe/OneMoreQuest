-- Run from the repository root: lua5.1 tests/threat_meter.lua
local function equal(actual, expected, what)
    assert(actual == expected, what .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local grouped, instance, unlocked = false, nil, false
local attackable, dead = true, {}
local units = { player = "Hunter", pet = "Cat", target = "Boar", party1 = "Ally" }
local combat, threat, reads, lookups = {}, {}, {}, {}
local secret = {}
issecretvalue = function(value) return value == secret end
IsInGroup = function() return grouped end
IsInInstance = function() return instance ~= nil, instance end
UnitExists = function(unit) lookups[unit] = true; return units[unit] ~= nil end
UnitName = function(unit) return units[unit] end
UnitAffectingCombat = function(unit) return combat[unit] == true end
UnitCanAttack = function() return attackable end
UnitIsDead = function(unit) return dead[unit] == true end
UnitClass = function() return "Hunter", "HUNTER" end
GetTime = function() return 100 end
local function readThreat(unit, target)
    reads[unit] = true
    local value = threat[target] and threat[target][unit]
    if value == "error" then error("threat API error") end
    if value then return value[1], value[2], value[3], value[4], value[5] end
end
UnitDetailedThreatSituation = readThreat

local frames, methods = {}, {}
local function frame(_, name, parent)
    local f = setmetatable({ name = name, parent = parent, shown = true, scripts = {}, events = {} }, { __index = methods })
    frames[#frames + 1] = f
    return f
end
for _, name in ipairs({ "SetHeight", "SetWidth", "SetPoint", "SetAllPoints", "SetFrameStrata", "SetClampedToScreen",
    "SetMovable", "RegisterForDrag", "EnableMouse", "ClearAllPoints", "SetColorTexture", "SetTextColor",
    "SetJustifyH", "SetAlpha" }) do methods[name] = function() end end
function methods:SetText(value) self.text = value end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:CreateTexture() return frame(nil, nil, self) end
function methods:CreateFontString() return frame(nil, nil, self) end
CreateFrame = frame
UIParent = { shown = true }
local function visibleText(text)
    for _, f in ipairs(frames) do
        local p = f
        while p and p.shown do p = p.parent end
        if not p and f.text and f.text:find(text, 1, true) then return true end
    end
    return false
end

local OMQ = { db = { options = {} }, Alerts = { ruleOrder = {} }, On = function() end, RegisterCommand = function() end,
    Unlock = { Has = function() return unlocked end } }
_G.OneMoreQuest = OMQ
for _, path in ipairs({ "UI/ThreatProbe.lua", "UI/ThreatMeter.lua", "Settings.lua" }) do
    assert(loadfile("OneMoreQuest/" .. path))("OneMoreQuest", OMQ)
end
local M = OMQ.ThreatMeter
local options = OMQ.db.options
local setting
for _, section in ipairs(OMQ.Settings:Sections()) do
    for _, item in ipairs(section.items) do if item.label == "Threat meter" then setting = item end end
end
assert(setting, "Threat meter setting must be visible before the first dungeon")
equal(setting.options[4], "Solo + group", "solo option")
equal(M.Mode(), "group", "fresh installs preserve existing default")
options.threat = false
equal(M.Mode(), "never", "legacy disabled toggle still applies")
for i, mode in ipairs({ "group", "dungeon", "never", "always" }) do
    setting.set(i)
    equal(M.Mode(), mode, "setting persists " .. mode)
    equal(setting.get(), i, "setting displays " .. mode)
    equal(options.threat, nil, "setting clears legacy flag")
end

-- The pet can open combat before the player. Even with party units in the mock, solo reads only local units.
threat.target = { pet = { true, 3, 100 }, party1 = { false, 1, 90 } }
combat.pet = true
reads, lookups = {}, {}
local state, rows = M.Compute()
equal(state, "rows", "solo mode bypasses the first-dungeon unlock")
equal(#rows, 2, "solo player and pet rows")
equal(rows[1].unit, "pet", "pet opens the pull")
equal(rows[1].tank, true, "pet holds verified aggro")
equal(rows[2].unit, "player", "player appears with pet threat")
equal(rows[2].pct, 0, "explicitly no threat can display zero")
equal(reads.party1 or lookups.party1, nil, "solo mode does not query party units")
equal(M.Refresh(), "rows", "rows render")
assert(visibleText("Aggro"), "verified aggro must be visible")

threat.target.player, threat.target.pet = { true, 3, 100 }, { false, 1, 65 }
state, rows = M.Compute()
equal(rows[1].unit, "player", "player overtakes pet")
equal(rows[1].tank, true, "player now holds aggro")
equal(rows[2].tank, false, "pet loses aggro")
threat.target.player, threat.target.pet = { false, 1, 100 }, { secret, 1, 65 }
M.Refresh()
assert(visibleText("100%") and not visibleText("Aggro"), "percentages and hidden flags do not prove aggro")
threat.target.player, threat.target.pet = { true }, { false, 0, 0 }
state, rows = M.Compute()
local player = rows[1].unit == "player" and rows[1] or rows[2]
local pet = rows[1].unit == "pet" and rows[1] or rows[2]
equal(player.tank, true, "readable tank flag alone still shows aggro")
equal(player.pct, nil, "tank flag alone does not invent percent")
equal(pet.pct, 0, "explicit zero is preserved")
M.Refresh()
assert(visibleText("Aggro") and visibleText("-"), "known aggro with unknown percentage renders as Aggro and a dash")

threat.target.pet = { true, 3, 100 }
for _, restricted in ipairs({ { false, 1, secret }, { false, 1 }, "error" }) do
    threat.target.player = restricted
    state, rows = M.Compute()
    equal(state, "rows", "pet remains visible with restricted player threat")
    equal(rows[2].unit, "player", "player row remains visible")
    equal(rows[2].pct, nil, "restricted player threat does not become zero")
end
threat.target = { player = { secret, secret, secret }, pet = "error" }
M.Refresh()
assert(visibleText("Threat unavailable"), "pet combat with unavailable threat shows the correct hint")
assert(not visibleText("Aggro"), "the hint hides previously visible aggro rows")
UnitDetailedThreatSituation = nil
M.Refresh()
assert(visibleText("Threat unavailable"), "missing threat API is distinguishable from zero threat")
UnitDetailedThreatSituation = readThreat

threat.target, units.target = {}, "Wolf"
for _, f in ipairs(frames) do
    if f.events.PLAYER_TARGET_CHANGED then f.scripts.OnEvent(f, "PLAYER_TARGET_CHANGED") end
end
assert(visibleText("No threat"), "switching target clears threat from the old target")
assert(not visibleText("Threat unavailable"), "readable no-data response differs from restricted threat")

threat.target = { player = { true, 3, 100 }, pet = { false, 1, 60 }, party1 = { false, 1, 72 } }
dead.pet, reads = true, {}
state, rows = M.Compute()
equal(#rows, 1, "solo with a dead pet shows only the player")
equal(reads.pet, nil, "no threat API call for a dead pet")
dead.pet = false
units.pet, reads = nil, {}
state, rows = M.Compute()
equal(#rows, 1, "solo without pet shows only the player")
equal(reads.pet, nil, "no threat API call for absent pet")
combat.player = true
attackable, reads = false, {}
equal(M.Compute(), "notarget", "friendly target is rejected in combat")
equal(next(reads), nil, "friendly target does not query threat")
attackable, dead.target = true, true
equal(M.Compute(), "notarget", "dead target is rejected in combat")
equal(next(reads), nil, "dead target does not query threat")
dead.target = false

setting.set(1)
equal(M.Compute(), "hidden", "old group mode stays hidden solo")
grouped = true
equal(M.Compute(), "hidden", "old group mode still observes first-dungeon unlock")
unlocked = true
state, rows = M.Compute()
equal(rows[2].unit, "party1", "group mode still includes and ranks party members")
threat.target.player = "error"
state, rows = M.Compute()
equal(rows[2].unit, "player", "group mode still shows the local player beside party threat")
equal(rows[2].pct, nil, "unavailable group threat does not become zero")
setting.set(2)
equal(M.Compute(), "hidden", "dungeon mode stays hidden outside an instance")
instance = "party"
equal(M.Compute(), "rows", "dungeon mode still runs in a party instance")
setting.set(3)
equal(M.Compute(), "hidden", "Never stays hidden even inside a dungeon")

print("Threat meter regression checks passed")
