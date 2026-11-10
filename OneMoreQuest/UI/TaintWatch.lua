-- One More Quest: action bar watch (decision 507)
-- In a fight the game's action buttons fail with "SetCooldown ... Secret values are only allowed during untainted
-- execution" once addon code has left its mark (taint) on them; only a /reload cleans them. Addons cannot read the
-- game's taint.log, so OMQ looks for itself:
-- * the game's taint log (CVar taintLog) is switched on at login for every dad (option taintLog, /omq taint log off);
-- * a trail keeps the last calls of addon code that can touch the bars (cursor pickups, placing, equipping, macros,
--   CVars, trainer buys), with the addon file and line that made them (hooksecurefunc only, nothing is replaced),
--   plus the bar events ACTIONBAR_SHOWGRID / ACTIONBAR_SLOT_CHANGED;
-- * every few seconds, after each bar event, after a blocked action and after the game's own bar error it reads
--   with issecurevariable which fields of the action buttons and bars carry an addon's taint (reading changes nothing);
-- * the first finding of a session (and every new addon after it) goes into the error log as kind "taint" with the
--   trail, so the error collection brings it to the collector; the game's bar error is kept there as kind "game".
-- /omq taint: the findings and the trail; "log on|off"; "scan".
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local W = {}
OMQ.TaintWatch = W

W.TRAIL = 25            -- calls kept in the trail
W.SHOW_TRAIL = 12       -- calls sent with a finding
W.EVERY = 5             -- seconds between two scans
W.MAX_FIELDS = 8        -- tainted fields named in a finding
W.MAX_FINDINGS = 10     -- findings kept in OMQDB.taintWatch

local trail = {}
local findings = {}
local seen = {}         -- addon -> true: already reported this session
local scanQueued = false

local function now() return GetTime and GetTime() or 0 end
local function stamp() return date and date("%Y-%m-%d %H:%M:%S") or "?" end
local function locked() return InCombatLockdown and InCombatLockdown() and true or false end

----------------------------------------------------------------------
-- The trail: who called what
----------------------------------------------------------------------
-- the first addon line of a stack that is not this file: "RXPGuides/functions.lua:5220"
function W.Caller(stack)
    for line in tostring(stack or ""):gmatch("[^\n]+") do
        local path, ln = line:match("AddOns[/\\]([^%]:]+%.lua)%]?:(%d+)")
        if path and not path:find("^Blizzard_") and not path:find("TaintWatch%.lua$") then
            return (path:gsub("\\", "/")) .. ":" .. ln
        end
    end
    return nil
end

function W.Add(what, who)
    what = tostring(what)
    local last = trail[#trail]
    if last and last.what == what and last.who == who then
        -- the same call again (a CVar set many times): one line with a count, so it does not push the rest out
        last.t, last.at, last.n, last.combat = now(), stamp(), (last.n or 1) + 1, locked()
        return
    end
    trail[#trail + 1] = { t = now(), at = stamp(), what = what, who = who, combat = locked() }
    while #trail > W.TRAIL do table.remove(trail, 1) end
end

function W.Trail() return trail end

-- calls of addon code only: a click of the player runs Blizzard code and has no addon line in its stack
local function hookCall(name, fn)
    return function()
        local stack = debugstack and debugstack(2, 12, 0) or ""
        local who = W.Caller(stack)
        if who then W.Add(name, who) end
    end
end

W.APIS = {
    { nil, "PickupSpell" }, { "C_Spell", "PickupSpell" }, { nil, "PickupAction" }, { nil, "PlaceAction" },
    { nil, "PickupMacro" }, { nil, "PickupItem" }, { "C_Item", "PickupItem" }, { nil, "PickupInventoryItem" },
    { nil, "PickupContainerItem" }, { "C_Container", "PickupContainerItem" }, { nil, "PickupMerchantItem" },
    { nil, "PickupPetAction" }, { nil, "PickupCompanion" }, { nil, "ClearCursor" },
    { nil, "EquipItemByName" }, { "C_Item", "EquipItemByName" }, { nil, "EquipCursorItem" },
    { nil, "UseContainerItem" }, { "C_Container", "UseContainerItem" },
    { nil, "CreateMacro" }, { nil, "EditMacro" }, { nil, "DeleteMacro" },
    { nil, "SetCVar" }, { "C_CVar", "SetCVar" }, { nil, "BuyTrainerService" },
    { "C_ClickBindings", "SetProfileByInfo" }, { nil, "ChangeActionBarPage" }, { nil, "SetActionBarToggles" },
}

function W.HookAll()
    if not hooksecurefunc then return 0 end
    local n = 0
    for _, a in ipairs(W.APIS) do
        local tbl, key = a[1] and _G[a[1]], a[2]
        local label = a[1] and (a[1] .. "." .. key) or key
        if a[1] == nil and type(_G[key]) == "function" then
            if pcall(hooksecurefunc, key, hookCall(label)) then n = n + 1 end
        elseif type(tbl) == "table" and type(tbl[key]) == "function" then
            if pcall(hooksecurefunc, tbl, key, hookCall(label)) then n = n + 1 end
        end
    end
    W.hooked = n
    return n
end

----------------------------------------------------------------------
-- The scan: which bar fields carry an addon's taint
----------------------------------------------------------------------
W.BARS = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
    "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar" }
W.BUTTONS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
W.BUTTON_FIELDS = { "action", "spellID", "cooldown", "chargeCooldown", "lossOfControlCooldown", "enableLOCCooldown",
    "bar", "index", "flyoutID", "isFlyoutAction" }
W.BAR_FIELDS = { "numButtonsShowable", "actionButtons", "shownButtonContainers", "noSpacers", "isShowingGrid" }
W.GLOBALS = { "ActionButton_UpdateCooldown", "ActionButton_ApplyCooldown", "ActionBarButtonEventsFrame" }
W.GAMEPAD = "GamepadMainActionBarFrame"

local function taintOf(tbl, key)
    if not issecurevariable then return nil end
    local ok, secure, addon
    if tbl == nil then ok, secure, addon = pcall(issecurevariable, key)
    else ok, secure, addon = pcall(issecurevariable, tbl, key) end
    if ok and secure == false then return addon or "?" end
    return nil
end

local function collectButtons()
    local list, seenB = {}, {}
    local function add(b, name)
        if type(b) == "table" and not seenB[b] then seenB[b] = true; list[#list + 1] = { b, name } end
    end
    for _, pre in ipairs(W.BUTTONS) do
        for i = 1, 12 do add(_G[pre .. i], pre .. i) end
    end
    for _, bn in ipairs(W.BARS) do
        local bar = _G[bn]
        if type(bar) == "table" and type(bar.actionButtons) == "table" then
            for i, b in pairs(bar.actionButtons) do add(b, (b.GetName and b:GetName()) or (bn .. "#" .. tostring(i))) end
        end
    end
    -- the gamepad bars: their buttons hang below the frame
    local root = _G[W.GAMEPAD]
    local function walk(f, depth)
        if depth > 4 or type(f) ~= "table" or not f.GetChildren then return end
        local ok, kids = pcall(function() return { f:GetChildren() } end)
        if not ok then return end
        for _, c in ipairs(kids) do
            if rawget(c, "action") ~= nil or rawget(c, "cooldown") ~= nil then
                add(c, (c.GetName and c:GetName()) or ("Gamepad#" .. tostring(#list + 1)))
            end
            walk(c, depth + 1)
        end
    end
    walk(root, 0)
    return list
end
W._collectButtons = collectButtons

-- { { name = "MultiBarBottomLeftButton2.action", addon = "OneMoreQuest" }, ... }, buttons looked at
function W.Scan()
    local out = {}
    local buttons = collectButtons()
    for _, e in ipairs(buttons) do
        local b, name = e[1], e[2]
        for _, k in ipairs(W.BUTTON_FIELDS) do
            local a = taintOf(b, k)
            if a then out[#out + 1] = { name = name .. "." .. k, addon = a } end
        end
    end
    for _, bn in ipairs(W.BARS) do
        local bar = _G[bn]
        if type(bar) == "table" then
            for _, k in ipairs(W.BAR_FIELDS) do
                local a = taintOf(bar, k)
                if a then out[#out + 1] = { name = bn .. "." .. k, addon = a } end
            end
        end
    end
    for _, g in ipairs(W.GLOBALS) do
        local a = taintOf(nil, g)
        if a then out[#out + 1] = { name = g, addon = a } end
    end
    return out, #buttons
end

-- the trail as short lines, newest last: "-12s RXPGuides/functions.lua:5220 C_Container.PickupContainerItem"
function W.TrailLines(n, at)
    local lines = {}
    at = at or now()
    for i = math.max(1, #trail - (n or W.SHOW_TRAIL) + 1), #trail do
        local e = trail[i]
        lines[#lines + 1] = string.format("-%ds %s %s%s%s", math.floor(at - e.t + 0.5), e.who or "game", e.what,
            (e.n and e.n > 1) and (" x" .. e.n) or "", e.combat and " (combat)" or "")
    end
    return lines
end

-- one finding per addon and session; returns the new finding or nil
function W.Check(reason)
    local found = W.Scan()
    if #found == 0 then return nil end
    local by, order = {}, {}
    for _, f in ipairs(found) do
        if not by[f.addon] then by[f.addon] = {}; order[#order + 1] = f.addon end
        table.insert(by[f.addon], f.name)
    end
    local new = nil
    for _, addon in ipairs(order) do
        if not seen[addon] then
            seen[addon] = true
            local names = by[addon]
            local shown = {}
            for i = 1, math.min(#names, W.MAX_FIELDS) do shown[i] = names[i] end
            local f = {
                at = stamp(), addon = addon, reason = tostring(reason or "scan"), count = #names,
                fields = shown, trail = W.TrailLines(W.SHOW_TRAIL), version = OMQ.version, combat = locked(),
            }
            findings[#findings + 1] = f
            while #findings > W.MAX_FINDINGS do table.remove(findings, 1) end
            if OMQ.db then OMQ.db.taintWatch = findings end
            if OMQ.Errors and OMQ.Errors.Record then
                local msg = string.format("bars tainted by %s (%d fields, %s): %s", addon, #names, f.reason,
                    table.concat(shown, ", "))
                pcall(OMQ.Errors.Record, "taint", msg, table.concat(f.trail, "\n"))
            end
            new = new or f
        end
    end
    return new
end

function W.Findings() return findings end

local function soon(reason)
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.2, function()
        scanQueued = false
        pcall(W.Check, reason)
    end)
end
W.Soon = soon

-- the game's own bar error (it names no addon, so the normal error log leaves it out)
function W.IsBarError(msg)
    local m = tostring(msg or "")
    return m:find("untainted execution", 1, true) ~= nil and
        (m:find("ActionButton", 1, true) ~= nil or m:find("SetCooldown", 1, true) ~= nil)
end

----------------------------------------------------------------------
-- The game's taint log
----------------------------------------------------------------------
function W.Wanted() return not (OMQ.db and OMQ.db.options and OMQ.db.options.taintLog == false) end

function W.ApplyLog()
    if not W.Wanted() or locked() then return false end
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not (get and set) then return false end
    local ok, v = pcall(get, "taintLog")
    if not ok or v == nil then return false end
    if tostring(v) ~= "0" then return false end      -- on already (1 or 2): leave it
    return (pcall(set, "taintLog", "1"))
end

function W.SetLog(on)
    OMQ.db.options.taintLog = on and true or false
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if set then pcall(set, "taintLog", on and "1" or "0") end
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
W.HookAll()

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "ACTIONBAR_SLOT_CHANGED", "ADDON_ACTION_BLOCKED",
                     "ADDON_ACTION_FORBIDDEN", "PLAYER_LOGIN" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        pcall(W.ApplyLog)
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(W.EVERY, function() pcall(W.Check, "scan") end) end
        return
    end
    if event == "ACTIONBAR_SLOT_CHANGED" then W.Add("ACTIONBAR_SLOT_CHANGED " .. tostring(arg1))
    elseif event == "ACTIONBAR_SHOWGRID" or event == "ACTIONBAR_HIDEGRID" then W.Add(event)
    else W.Add(event .. " " .. tostring(arg1)) end
    soon(event)
end)

OMQ:On("DB_READY", function()
    local old = type(OMQ.db.taintWatch) == "table" and OMQ.db.taintWatch or {}
    for _, f in ipairs(findings) do old[#old + 1] = f end
    while #old > W.MAX_FINDINGS do table.remove(old, 1) end
    findings = old
    OMQ.db.taintWatch = findings
end)

OMQ:RegisterCommand("taint", function(arg)
    local cmd, value = (arg or ""):match("^(%S*)%s*(.-)$")
    if cmd == "log" then
        W.SetLog(not (value == "off" or value == "0"))
        OMQ:Print("game taint log " .. (W.Wanted() and "on (Logs\\taint.log after a /reload)" or "off"))
        return
    end
    if cmd == "scan" then
        local found, n = W.Scan()
        OMQ:Print(string.format("bar watch: %d buttons looked at, %d tainted fields", n, #found))
        for i = 1, math.min(#found, 10) do print("  " .. found[i].name .. " <- " .. found[i].addon) end
        return
    end
    OMQ:Print(string.format("bar watch: %d findings, taint log %s, %d calls hooked", #findings,
        tostring(((C_CVar and C_CVar.GetCVar) or GetCVar)("taintLog")), W.hooked or 0))
    for i = math.max(1, #findings - 2), #findings do
        local f = findings[i]
        print(string.format("  %s %s (%s, %d fields): %s", f.at, f.addon, f.reason, f.count, table.concat(f.fields, ", ")))
    end
    print("  trail:")
    for _, l in ipairs(W.TrailLines(W.SHOW_TRAIL)) do print("    " .. l) end
end, "action bar watch: findings and trail; 'scan'; 'log on|off'")
