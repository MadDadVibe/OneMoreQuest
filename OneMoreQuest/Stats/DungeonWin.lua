-- One More Quest: the dungeon window, its numbers (decision 530)
-- In every 5-player dungeon (not in raids) OMQ keeps a visit: the time inside, the XP from mobs (all XP inside
-- without the XP of quest turn-ins), the coins looted (my share) and which bosses and rares are dead.
-- The clock runs from entering; back in the same dungeon within 15 minutes the same visit goes on (as the dungeon
-- XP card). When every boss is dead the clock stops. UI/DungeonWin.lua draws the window.
-- Which dungeon: the instance id (Data/DungeonWindow.lua), else one learned before, else the English name; wings
-- sharing one instance (Scarlet Monastery, Blackrock Spire, Dire Maul) come from the sub zone, whose name the game
-- gives in the client's language (C_Map.GetAreaInfo). An unknown instance is learned from the first dead boss.
-- Kills inside instances are secret for addons: a boss counts from the encounter end (creature ids of the boss
-- units, else its name), a boss or rare from opening its corpse (GetLootSourceInfo), and from a dad in the group
-- (message DW). Coins: a positive money change while my loot window is open, or within 2 s of a loot money chat
-- event (the text is not read: works on every client language and with secret chat text).
-- Saved: OMQDB.dwin = { pos, min, inst = { [instance id] = key }, names = { [npc] = name }, cur = { [guid] = visit } }
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local W = {}
OMQ.DungeonWin = W

W.CONTINUE = 15 * 60
W.TICK = 1
W.MONEY_GAP = 2

local function call(f, ...)
    if not f then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    return unpack(r, 2)
end
local function plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local function num(v) return type(v) == "number" and plain(v) end
local function str(v) return type(v) == "string" and plain(v) and v ~= "" end
local function data() return OMQ.DungeonWinData or {} end

function W.Saved()
    if not OMQDB then return nil end
    local s = OMQDB.dwin
    if type(s) ~= "table" then s = {}; OMQDB.dwin = s end
    s.inst = s.inst or {}
    s.names = s.names or {}
    s.cur = s.cur or {}
    return s
end

local function me()
    local g = call(UnitGUID, "player")
    return plain(g) and g or nil
end

function W.On() return not (OMQ.db and OMQ.db.options and OMQ.db.options.dungeonWin == false) end

----------------------------------------------------------------------
-- Dungeon data
----------------------------------------------------------------------
local DQ_NAMES
local function nameKey(name)
    if not DQ_NAMES then
        DQ_NAMES = {}
        for _, d in ipairs(OMQ.Dungeons or {}) do
            if d.name and d.key then DQ_NAMES[d.name:lower()] = d.key end
        end
    end
    return str(name) and DQ_NAMES[name:lower()] or nil
end

function W.Title(key)
    for _, d in ipairs(OMQ.Dungeons or {}) do if d.key == key then return d.name end end
    return nil
end

-- the boss entries of a dungeon: { npc, items = { id, ... }, rare = true|nil }, bosses first then rares
function W.Bosses(key)
    local D, rares = data(), {}
    local bosses = {}
    local seen = {}
    for _, b in ipairs((OMQ.DungeonLoot or {})[key] or {}) do
        local npc = b[1]
        if num(npc) and npc > 0 and not seen[npc] then
            seen[npc] = true
            local items = {}
            for i = 2, #b do items[#items + 1] = b[i] end
            local e = { npc = npc, items = items }
            if D.rare and D.rare[npc] then e.rare = true; rares[#rares + 1] = e else bosses[#bosses + 1] = e end
        end
    end
    for _, npc in ipairs(D.extra and D.extra[key] or {}) do
        if not seen[npc] then seen[npc] = true; rares[#rares + 1] = { npc = npc, items = {}, rare = true } end
    end
    return bosses, rares
end

-- which key owns this npc (for learning an unknown instance); keys = only these
local function keyOfNpc(npc, keys)
    local D = data()
    local function owns(k)
        for _, b in ipairs((OMQ.DungeonLoot or {})[k] or {}) do if b[1] == npc then return true end end
        for _, n in ipairs(D.extra and D.extra[k] or {}) do if n == npc then return true end end
        return false
    end
    if keys then
        for _, k in ipairs(keys) do if owns(k) then return k end end
        return nil
    end
    for k in pairs(OMQ.DungeonLoot or {}) do if k ~= "stu" and owns(k) then return k end end
    return nil
end
W.KeyOfNpc = keyOfNpc

function W.Name(npc)
    local s = W.Saved()
    local D = data()
    return (s and s.names[npc]) or (D.names and D.names[npc]) or (D.rare and D.rare[npc]) or nil
end

----------------------------------------------------------------------
-- Where am I
----------------------------------------------------------------------
-- inside a 5-player dungeon: instance id, its name
function W.Where()
    local name, kind, _, _, _, _, _, instId = call(GetInstanceInfo)
    if kind == "party" and num(instId) then return instId, str(name) and name or "Dungeon" end
    return nil
end

local areaNames = {}
local function areaName(id)
    if areaNames[id] == nil then
        local n = C_Map and C_Map.GetAreaInfo and call(C_Map.GetAreaInfo, id)
        areaNames[id] = str(n) and n or false
    end
    return areaNames[id] or nil
end

-- the wing of a shared instance from the sub zone, nil when the sub zone names none
function W.Wing(keys)
    local zones = {}
    for _, f in ipairs({ GetSubZoneText, GetMinimapZoneText }) do
        local z = call(f)
        if str(z) then zones[#zones + 1] = z end
    end
    if #zones == 0 then return nil end
    local wings = data().wings or {}
    for _, k in ipairs(keys) do
        for _, id in ipairs(wings[k] or {}) do
            local n = areaName(id)
            if n then for _, z in ipairs(zones) do if z == n then return k end end end
        end
    end
    return nil
end

-- the keys the instance can be: one key, a list (wings), or nil (unknown)
function W.KeysOf(instId, name)
    local s = W.Saved()
    local v = data().inst and data().inst[instId]
    if type(v) == "table" then return v end
    if v then return { v } end
    if s and s.inst[instId] then return { s.inst[instId] } end
    local k = nameKey(name)
    if k then return { k } end
    return nil
end

----------------------------------------------------------------------
-- The visit
----------------------------------------------------------------------
local function visit()
    local s, g = W.Saved(), me()
    return s and g and s.cur[g] or nil
end
W.Visit = visit

local function newVisit(instId, name, key)
    local s, g = W.Saved(), me()
    if not (s and g) then return nil end
    local v = { id = instId, nm = name, key = key, t = time(), s = 0, xp = 0, qxp = 0, gold = 0, dead = {}, seen = time() }
    s.cur[g] = v
    return v
end

-- the bosses still alive in the visit (0 = all dead: the clock stops)
function W.Left(v)
    v = v or visit()
    if not (v and v.key) then return nil end
    local bosses = W.Bosses(v.key)
    if #bosses == 0 then return nil end
    local n = 0
    for _, b in ipairs(bosses) do if not v.dead[b.npc] then n = n + 1 end end
    return n
end

local lastLevel, lastXP, lastMax
local function snapshot()
    lastLevel, lastXP, lastMax = call(UnitLevel, "player"), call(UnitXP, "player"), call(UnitXPMax, "player")
end
local function gained()
    local level, xp, xpMax = call(UnitLevel, "player"), call(UnitXP, "player"), call(UnitXPMax, "player")
    if not (num(level) and num(xp) and num(xpMax)) then return 0 end
    local g = 0
    if num(lastLevel) and num(lastXP) and num(lastMax) then
        if level > lastLevel then g = math.max(lastMax - lastXP, 0) + xp
        elseif level == lastLevel then g = math.max(xp - lastXP, 0) end
    end
    lastLevel, lastXP, lastMax = level, xp, xpMax
    return g
end

local function changed() OMQ:Fire("DUNGEON_WIN_CHANGED") end

-- every second: the visit follows where I am
function W.Tick(secs)
    secs = secs or W.TICK
    local v = visit()
    local instId, name = W.Where()
    if instId then
        local keys = W.KeysOf(instId, name)
        local key = keys and keys[1]
        if keys and #keys > 1 then
            key = W.Wing(keys) or (v and v.id == instId and v.key) or nil
            if v and v.id == instId and v.key and key and key ~= v.key and not v.left then
                -- another wing of the same instance: a new visit
                v = nil
            end
        end
        if v and v.id == instId and (not v.left or time() - v.left <= W.CONTINUE) and (not v.key or not key or v.key == key) then
            v.left = nil
        else
            v = newVisit(instId, name, key)
            if not v then return end
            v.wings = keys and #keys > 1 and keys or nil
            changed()
        end
        if not v.key and key then v.key = key; changed() end
        v.seen = time()
        if not v.done then v.s = v.s + secs end
        return v
    end
    if v and not v.left then
        if call(UnitIsDeadOrGhost, "player") then
            -- the corpse run belongs to the visit
            if not v.done then v.s = v.s + secs end
            v.seen = time()
            return v
        end
        v.left = time()
        changed()
    end
    return nil
end

function W.Inside()
    local v = visit()
    return v and not v.left and W.Where() == v.id and v or nil
end

-- the XP from mobs: all XP inside without the XP of quest turn-ins
function W.MobXP(v)
    v = v or visit()
    if not v then return 0 end
    return math.max(0, (v.xp or 0) - (v.qxp or 0))
end

function W.OnXP()
    local g = gained()
    local v = W.Inside()
    if v and g > 0 then v.xp = v.xp + g; changed() end
end

function W.OnQuestTurnedIn(_, xp)
    local v = W.Inside()
    if v and num(xp) and xp > 0 then v.qxp = (v.qxp or 0) + xp; changed() end
end

----------------------------------------------------------------------
-- Coins
----------------------------------------------------------------------
local money, lootOpen, lootClosed = nil, false, -100
local pendDelta, pendDeltaAt, pendMsgAt = 0, -100, -100

local function addGold(c)
    local v = W.Inside()
    if v and c > 0 then v.gold = (v.gold or 0) + c; changed() end
end

function W.OnMoney()
    local m = call(GetMoney)
    if not num(m) then return end
    local d = money and (m - money) or 0
    money = m
    if d <= 0 then return end
    local now = GetTime()
    if lootOpen or now - lootClosed <= 1 then addGold(d); return end
    if now - pendMsgAt <= W.MONEY_GAP then pendMsgAt = -100; addGold(d); return end
    pendDelta, pendDeltaAt = d, now
end

function W.OnMoneyMsg()
    local now = GetTime()
    if lootOpen or now - lootClosed <= 1 then return end      -- counted by the loot window already
    if pendDelta > 0 and now - pendDeltaAt <= W.MONEY_GAP then
        addGold(pendDelta)
        pendDelta = 0
        return
    end
    pendMsgAt = now
end

----------------------------------------------------------------------
-- Dead bosses and rares
----------------------------------------------------------------------
-- npc of a creature GUID ("Creature-0-1-2-3-<npc>-<spawn>"), nil for others or secret ones
local function npcOf(guid)
    if not str(guid) then return nil end
    local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(npc) end
    return nil
end
W.NpcOf = npcOf

local function learnKey(v, npc)
    if v.key and not v.wings then return end
    local k = keyOfNpc(npc, v.wings)
    if not k then return end
    v.key = k
    if not v.wings then
        local s = W.Saved()
        if s and not (data().inst and data().inst[v.id]) then s.inst[v.id] = k end
    end
end

-- a boss or rare died in my visit; share = tell the dads
function W.Dead(npc, share, name)
    local v = W.Inside()
    if not (v and num(npc) and npc > 0) then return false end
    if str(name) then local s = W.Saved(); if s then s.names[npc] = name end end
    learnKey(v, npc)
    if not v.key then return false end
    local mine = keyOfNpc(npc, { v.key })
    if not mine or v.dead[npc] then return false end
    v.dead[npc] = time()
    if W.Left(v) == 0 then v.done = true end
    if share and OMQ.GetChannel and OMQ:GetChannel() then OMQ:Send("DW", v.id, npc) end
    changed()
    return true
end

-- encounter names seen this session (the name of an encounter without creature ids)
local function byName(name)
    local v = W.Inside()
    if not (v and v.key and str(name)) then return nil end
    for _, b in ipairs((W.Bosses(v.key))) do
        if W.Name(b.npc) == name then return b.npc end
    end
    return nil
end

function W.OnEncounterEnd(_, name, _, _, success, units)
    if not (num(success) and success == 1) then return end
    local any = false
    if type(units) == "table" then
        for _, u in ipairs(units) do
            local id = type(u) == "table" and u.creatureID
            if num(id) then
                any = true
                W.Dead(id, true, type(u) == "table" and u.creatureName or nil)
            end
        end
    end
    if not any then
        local npc = byName(name)
        if npc then W.Dead(npc, true) end
    end
end

function W.OnLootOpened()
    lootOpen = true
    if not (W.Inside() and GetLootSourceInfo and GetNumLootItems) then return end
    local n = call(GetNumLootItems)
    if not num(n) then return end
    for i = 1, n do
        local npc = npcOf((call(GetLootSourceInfo, i)))
        if npc then W.Dead(npc, true) end
    end
end

function W.OnLootClosed()
    lootOpen = false
    lootClosed = GetTime()
end

OMQ:RegisterMessage("DW", function(f)
    local inst, npc = tonumber(f[1]), tonumber(f[2])
    local v = W.Inside()
    if v and inst == v.id and npc then W.Dead(npc, false) end
end)

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------
function W.Clock(secs)
    secs = math.max(0, math.floor((secs or 0) + 0.5))
    local h, m, sec = math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
    return string.format("%d:%02d", m, sec)
end

function W.Num(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- "58g 80s" (plain text; the window uses coin icons)
function W.Gold(c)
    c = math.floor(c or 0)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return string.format("%dg %ds", g, s) end
    if s > 0 then return string.format("%ds %dc", s, cp) end
    return string.format("%dc", cp)
end

OMQ:RegisterCommand("dwin", function(arg)
    if arg == "reset" then
        local s = W.Saved()
        if s then s.pos = nil; s.min = nil end
        if OMQ.DungeonWinUI then OMQ.DungeonWinUI.Place() end
        OMQ:Print("dungeon window: back in its place")
        return
    end
    if arg == "test" then
        if OMQ.DungeonWinUI then OMQ.DungeonWinUI.Test() end
        return
    end
    local instId, name = W.Where()
    local v = visit()
    OMQ:Print(string.format("dungeon window: instance %s (%s), sub zone '%s'", tostring(instId or "-"), tostring(name or "outside"),
        tostring(call(GetSubZoneText) or "")))
    if not v then print("  no visit"); return end
    local bosses, rares = {}, {}
    if v.key then bosses, rares = W.Bosses(v.key) end
    local dead = 0
    for _ in pairs(v.dead or {}) do dead = dead + 1 end
    print(string.format("  %s key %s: %s, mob XP %s, gold %s, %d bosses + %d rares, %d dead%s%s", v.nm or "?",
        tostring(v.key or "unknown"), W.Clock(v.s), W.Num(W.MobXP(v)), W.Gold(v.gold), #bosses, #rares, dead,
        v.done and ", done" or "", v.left and ", left" or ""))
end, "dungeon window: what it knows about this dungeon ('test': a sample window, 'reset': back to its place)")

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "QUEST_TURNED_IN", "PLAYER_MONEY", "CHAT_MSG_MONEY", "LOOT_OPENED", "LOOT_CLOSED", "ENCOUNTER_END" }) do
    frame:RegisterEvent(e)
end
local HANDLERS = {
    PLAYER_XP_UPDATE = function() W.OnXP() end,
    QUEST_TURNED_IN = function(...) W.OnQuestTurnedIn(...) end,
    PLAYER_MONEY = function() W.OnMoney() end,
    CHAT_MSG_MONEY = function() W.OnMoneyMsg() end,
    LOOT_OPENED = function() W.OnLootOpened() end,
    LOOT_CLOSED = function() W.OnLootClosed() end,
    ENCOUNTER_END = function(...) W.OnEncounterEnd(...) end,
}
frame:SetScript("OnEvent", function(_, event, ...)
    if not W.ready then return end
    local fn = HANDLERS[event] or function() W.Tick(0) end
    local ok, err = pcall(fn, ...)
    if not ok then OMQ:Error("dungeonwin", err) end
end)

OMQ:On("READY", function()
    snapshot()
    money = call(GetMoney)
    if not num(money) then money = nil end
    W.ready = true
    C_Timer.NewTicker(W.TICK, function()
        local ok, err = pcall(W.Tick, W.TICK)
        if not ok then OMQ:Error("dungeonwin", err) end
        OMQ:Fire("DUNGEON_WIN_TICK")
    end)
end)
