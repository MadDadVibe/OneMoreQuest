-- One More Quest: Grind Run (decision 518)
--   Pick a zone (or "here"): OMQ lists up to 3 spots for the level (the group's lowest level), -2 to +2, normal mobs
--   only, from Data/GrindSpots.lua (densest circles, respawn times); spots that dads have measured come first, then
--   the dads' own spots ("here", shared in the group). The big arrow leads to the spot; there (50 yards) a card asks
--   30 or 60 minutes. While the run goes the quest tracker's place shows the run (UI/Grind.lua): time remaining,
--   kills, XP per hour; left click pauses (until the next left click, kills in a pause do not count), right click
--   ends it after a question. Only XP of kills counts (quest turn-ins are taken off). The end: kill XP, level
--   percent, XP per hour, the worth of the loot (auction price minus 5 %, or the vendor price when higher; grey and
--   bound items vendor, quest items nothing) and the gold looted; the spot's leaderboard (top 5 XP per hour,
--   level = level at the start) takes a run of 25 minutes or more with 70 % of the time within 150 yards.
--   Group: the starter starts it for every dad within 100 yards of the spot; each gets his own summary plus a line
--   for the group. Own spots, deletions and the leaderboards travel in the group (messages GS, GD, GB, GR).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local G = {}
OMQ.Grind = G

G.BELOW, G.ABOVE = 2, 2       -- mob levels around mine
G.SPOTS = 3                   -- spots of the data per zone
G.APART = 120                 -- yards between two listed spots
G.ARRIVE = 50                 -- yards: "you are there"
G.JOIN = 100                  -- yards: a dad of the group takes part in the starter's run
G.INSIDE = 150                -- yards: on the spot
G.BOARD_MIN = 25 * 60         -- seconds a run needs for the leaderboard
G.BOARD_SHARE = 0.7           -- of the time on the spot
G.BOARD_KEEP = 10
G.BOARD_SHOW = 5
G.SETTLE = 2                  -- seconds: an XP change and a quest turn-in belong together
G.AH_CUT = 0.95
G.MINUTES = { 30, 60 }

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not isSecret(v) end
local function str(v) return type(v) == "string" and not isSecret(v) and v ~= "" end
local function call(f, ...)
    if not f then return nil end
    local ok, a, b, c, d = pcall(f, ...)
    if ok then return a, b, c, d end
    return nil
end
local function now() return GetTime() end
local function clock() return time() end
local function myGuid() local me = OMQ:GetSelf(); return me and me.guid end
local function myName() local me = OMQ:GetSelf(); return me and me.name or "?" end
local function fire() OMQ:Fire("GRIND_CHANGED") end

----------------------------------------------------------------------
-- Saved data: OMQDB.grind = { spots = { key = spot }, gone = { key = true }, boards = { key = { entry } },
--   runs = { guid = run }, hist = { guid = { result } } }
----------------------------------------------------------------------
local function db()
    OMQDB = OMQDB or {}
    local g = OMQDB.grind or {}
    OMQDB.grind = g
    g.spots = g.spots or {}
    g.gone = g.gone or {}
    g.boards = g.boards or {}
    g.runs = g.runs or {}
    g.hist = g.hist or {}
    return g
end
G.DB = db

----------------------------------------------------------------------
-- Places
----------------------------------------------------------------------
local worlds = {}
-- world position { a, b, inst } of a place on a map (map %, as the data writes it)
function G.World(map, x, y)
    local k = string.format("%s:%.1f:%.1f", tostring(map), x or 0, y or 0)
    local w = worlds[k]
    if w == nil then
        w = false
        if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and map and x and y then
            local ok, inst, vec = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
            if ok and vec then
                local a, b
                if vec.GetXY then a, b = vec:GetXY() else a, b = vec.x, vec.y end
                if num(a) and num(b) then w = { a = a, b = b, inst = inst } end
            end
        end
        worlds[k] = w
    end
    return w or nil
end

function G.MyPos()
    local a, b, _, inst = call(UnitPosition, "player")
    if not (num(a) and num(b)) then return nil end
    local map = C_Map and call(C_Map.GetBestMapForUnit, "player")
    return { a = a, b = b, inst = inst, map = num(map) and map or nil }
end

-- yards between me and a spot, nil when unknown or on another continent
function G.Dist(spot, pos)
    pos = pos or G.MyPos()
    local w = spot and G.World(spot.map, spot.x, spot.y)
    if not (pos and w) then return nil end
    if pos.inst and w.inst and pos.inst ~= w.inst then return nil end
    return math.sqrt((pos.a - w.a) ^ 2 + (pos.b - w.b) ^ 2)
end

local zoneSet
local function zones()
    if not zoneSet then
        zoneSet = {}
        for i, z in ipairs(OMQ.QuestZones or {}) do zoneSet[z[1]] = { z = z, i = i } end
    end
    return zoneSet
end
local function mapInfo(map)
    if not (map and C_Map and C_Map.GetMapInfo) then return nil end
    local i = call(C_Map.GetMapInfo, map)
    return type(i) == "table" and i or nil
end
-- the zone a map belongs to (the map itself or the first parent that is a zone of the data)
function G.ZoneOf(map)
    local m, guard = map, 0
    while m and guard < 6 do
        if zones()[m] or (OMQ.GrindSpots and OMQ.GrindSpots[m]) then return m end
        local i = mapInfo(m)
        local p = i and i.parentMapID
        if not num(p) or p == 0 or p == m then break end
        m, guard = p, guard + 1
    end
    return map
end
function G.ZoneName(zone)
    local i = mapInfo(zone)
    if i and str(i.name) then return i.name end
    local z = zones()[zone]
    return z and z.z[5] or ("zone " .. tostring(zone))
end
function G.MyZone()
    local pos = G.MyPos()
    return pos and pos.map and G.ZoneOf(pos.map) or nil
end

----------------------------------------------------------------------
-- Spots
----------------------------------------------------------------------
function G.MobName(id) return (OMQ.GrindMobs and OMQ.GrindMobs[id]) or ("Mob " .. tostring(id)) end

local function dataSpot(zone, d)
    local key = string.format("%d:%d:%d", zone, math.floor(d[1] * 10 + 0.5), math.floor(d[2] * 10 + 0.5))
    local names = {}
    for i = 1, math.min(#d[7], 4), 2 do names[#names + 1] = G.MobName(d[7][i]) end
    return { key = key, map = zone, zone = zone, x = d[1], y = d[2], lo = d[3], hi = d[4], n = d[5], kph = d[6],
             mobs = d[7], name = table.concat(names, ", ") }
end

-- every spot by its key: one of the data or one of the dads
function G.Spot(key)
    if type(key) ~= "string" then return nil end
    local s = db().spots[key]
    if s then return s end
    local zone = tonumber(key:match("^(%d+):"))
    for _, d in ipairs(zone and OMQ.GrindSpots and OMQ.GrindSpots[zone] or {}) do
        local sp = dataSpot(zone, d)
        if sp.key == key then return sp end
    end
    return nil
end

-- the best run of a spot (its leaderboard's first entry)
function G.Board(key) return db().boards[key] or {} end
function G.Best(key) return G.Board(key)[1] end

-- the level the spots are for: mine, in a group the lowest of the dads
function G.Level()
    local lvl = num(UnitLevel and UnitLevel("player")) and UnitLevel("player") or 1
    for guid, u in pairs(OMQ.users or {}) do
        if guid ~= myGuid() and OMQ:IsOnline(u) and num(u.level) and u.level > 0 and u.level < lvl then lvl = u.level end
    end
    return lvl
end

-- the spots of a zone for a level: up to 3 of the data (measured ones first, then by the kills the respawn allows,
-- never two close together), then the dads' own spots of the zone
function G.Spots(zone, level)
    level = level or G.Level()
    local cands = {}
    for _, d in ipairs(OMQ.GrindSpots and OMQ.GrindSpots[zone] or {}) do
        if d[3] >= level - G.BELOW and d[4] <= level + G.ABOVE then cands[#cands + 1] = dataSpot(zone, d) end
    end
    local function measured(s) local b = G.Best(s.key); return b and b.k or nil end
    table.sort(cands, function(p, q)
        local a, b = measured(p), measured(q)
        if a and b and a ~= b then return a > b end
        if a and not b then return true end
        if b and not a then return false end
        if p.kph ~= q.kph then return p.kph > q.kph end
        return p.key < q.key
    end)
    local out = {}
    for _, s in ipairs(cands) do
        local free = true
        for _, o in ipairs(out) do
            local w1, w2 = G.World(s.map, s.x, s.y), G.World(o.map, o.x, o.y)
            local d = (w1 and w2) and math.sqrt((w1.a - w2.a) ^ 2 + (w1.b - w2.b) ^ 2)
                or math.sqrt((s.x - o.x) ^ 2 + (s.y - o.y) ^ 2) * 30
            if d < G.APART then free = false; break end
        end
        if free then out[#out + 1] = s end
        if #out >= G.SPOTS then break end
    end
    local own = {}
    for key, s in pairs(db().spots) do
        if s.zone == zone and not db().gone[key] then own[#own + 1] = s end
    end
    table.sort(own, function(p, q)
        local a, b = measured(p) or -1, measured(q) or -1
        if a ~= b then return a > b end
        return p.key < q.key
    end)
    for _, s in ipairs(own) do out[#out + 1] = s end
    return out
end

-- the zones with a spot for the level: mine first, then by the zones' levels
function G.ZoneList(level)
    level = level or G.Level()
    local here = G.MyZone()
    local seen, out = {}, {}
    local function add(zone)
        if seen[zone] then return end
        seen[zone] = true
        local list = G.Spots(zone, level)
        if #list > 0 or zone == here then
            local z = zones()[zone]
            out[#out + 1] = { zone = zone, name = G.ZoneName(zone), count = #list, here = zone == here,
                              order = z and z.i or 999, min = z and z.z[2], max = z and z.z[3] }
        end
    end
    for zone in pairs(OMQ.GrindSpots or {}) do add(zone) end
    for _, s in pairs(db().spots) do if s.zone and not db().gone[s.key] then add(s.zone) end end
    table.sort(out, function(p, q)
        if p.here ~= q.here then return p.here end
        if (p.min or 99) ~= (q.min or 99) then return (p.min or 99) < (q.min or 99) end
        return p.order < q.order
    end)
    if here and out[1] and out[1].zone == here and out[1].count == 0 then table.remove(out, 1) end
    return out
end

----------------------------------------------------------------------
-- Own spots ("here")
----------------------------------------------------------------------
local function b36(n)
    n = math.floor(n)
    local digits, s = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    repeat local r = n % 36; s = digits:sub(r + 1, r + 1) .. s; n = math.floor(n / 36) until n == 0
    return s
end

function G:Here()
    local pos = G.MyPos()
    if not (pos and pos.map) then OMQ:Print("Grind Run: no position here"); return nil end
    local v = C_Map and call(C_Map.GetPlayerMapPosition, pos.map, "player")
    local x, y
    if v then
        if v.GetXY then x, y = v:GetXY() else x, y = v.x, v.y end
    end
    if not (num(x) and num(y)) then OMQ:Print("Grind Run: no position here"); return nil end
    local zone = G.ZoneOf(pos.map)
    local sub = GetSubZoneText and call(GetSubZoneText)
    local name = G.ZoneName(zone) .. (str(sub) and (" - " .. sub) or "")
    local guid = myGuid() or "?"
    local key = "h" .. b36(clock()) .. guid:sub(-4)
    local spot = { key = key, map = pos.map, zone = zone, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10,
                   name = name, by = myName(), byGuid = guid, own = true, day = date and date("%Y-%m-%d") or "" }
    db().spots[key] = spot
    G.SendSpot(spot)
    fire()
    return spot
end

function G:Delete(key)
    local s = db().spots[key]
    if not s or s.byGuid ~= myGuid() then return false end
    db().spots[key] = nil
    db().gone[key] = true
    OMQ:Send("GD", key, s.byGuid)
    fire()
    return true
end

----------------------------------------------------------------------
-- Going there
----------------------------------------------------------------------
G.target = nil
G.early = {}                  -- group results that came before my own run ended
function G:Go(spot)
    if not spot then return false end
    G.target = spot
    local w = G.World(spot.map, spot.x, spot.y)
    if w and OMQ.Guide then OMQ.Guide:StartAt("Grind Run", w.a, w.b, w.inst, "grind", nil, { name = spot.name, radius = G.ARRIVE }) end
    G.Check()
    return true
end

-- the arrow's goal reached: the card asks for the minutes
function G.Check()
    local t = G.target
    if not t or G:Active() then return end
    local d = G.Dist(t)
    if d and d <= G.ARRIVE then
        G.target = nil
        if OMQ.GrindUI then OMQ.GrindUI:Arrive(t) end
    end
end

----------------------------------------------------------------------
-- The run
----------------------------------------------------------------------
local function guid() return myGuid() or "?" end
function G:Run() return db().runs[guid()] end
function G:Active() return G:Run() ~= nil end

function G.Used(r)
    r = r or G:Run()
    if not r then return 0 end
    local paused = r.paused and (clock() - r.paused) or 0
    return math.max(0, clock() - r.t0 - (r.pauseSum or 0) - paused)
end
function G.Remaining(r)
    r = r or G:Run()
    if not r then return 0 end
    return math.max(0, r.dur - G.Used(r))
end
function G.XPH(r)
    r = r or G:Run()
    if not r then return 0 end
    return (r.xp or 0) / math.max(G.Used(r), 60) * 3600
end

local function xpNow()
    local cur, max, lvl = call(UnitXP, "player"), call(UnitXPMax, "player"), call(UnitLevel, "player")
    if not (num(cur) and num(max) and num(lvl)) then return nil end
    return cur, math.max(max, 1), lvl
end
local function money()
    local m = call(GetMoney)
    return num(m) and m or nil
end

local function spotCopy(s)
    return { key = s.key, map = s.map, zone = s.zone, x = s.x, y = s.y, name = s.name, by = s.by, byGuid = s.byGuid }
end

-- opts: { id = the group run's id, starter = name } (a run the starter began for the group)
function G:Start(spot, minutes, opts)
    if not spot or G:Active() then return false end
    opts = opts or {}
    minutes = (minutes == 60) and 60 or 30
    local cur, max, lvl = xpNow()
    local r = { id = opts.id or (b36(clock()) .. guid():sub(-4)), spot = spotCopy(spot), dur = minutes * 60, mins = minutes,
                t0 = clock(), pauseSum = 0, xp = 0, pct = 0, kills = 0, gold = 0, items = {}, samples = 0, inside = 0,
                lvl0 = lvl or 1, xpLast = cur, maxLast = max, lvlLast = lvl, moneyLast = money(),
                group = opts.id ~= nil or (OMQ:GetChannel() ~= nil), starter = opts.starter }
    db().runs[guid()] = r
    G.target = nil
    G.pending, G.quests, G.moneyPend = {}, {}, nil
    if OMQ.Guide and OMQ.Guide.Kind and OMQ.Guide:Kind() == "grind" then OMQ.Guide:Clear() end
    if not opts.id and OMQ:GetChannel() then
        OMQ:Send("GR", "s", r.id, spot.key, tostring(spot.map), string.format("%.1f", spot.x), string.format("%.1f", spot.y),
                 tostring(minutes), spot.name or "", myName(), tostring(spot.zone or ""))
    end
    if OMQ.GrindUI then OMQ.GrindUI:HideArrive() end
    OMQ:Fire("QTRACK_CHANGED")
    fire()
    return true
end

function G:TogglePause()
    local r = G:Run()
    if not r then return nil end
    if r.paused then
        r.pauseSum = (r.pauseSum or 0) + (clock() - r.paused)
        r.paused = nil
        -- what came in the pause stays out: start counting from here
        r.xpLast, r.maxLast, r.lvlLast = xpNow()
        r.moneyLast = money()
    else
        r.paused = clock()
    end
    fire()
    return r.paused ~= nil
end
function G:Paused() local r = G:Run(); return r and r.paused ~= nil or false end

-- XP: every change is kept a moment, quest turn-ins next to it are taken off; the rest is kill XP
G.pending, G.quests = {}, {}
function G.OnXP()
    local r = G:Run()
    if not r then return end
    local cur, max, lvl = xpNow()
    if not cur then return end
    local delta, pct = 0, 0
    if r.lvlLast and r.xpLast and r.maxLast then
        if lvl > r.lvlLast then
            delta = (r.maxLast - r.xpLast) + cur
            pct = (r.maxLast - r.xpLast) / r.maxLast + cur / max
        elseif cur > r.xpLast then
            delta = cur - r.xpLast
            pct = delta / max
        end
    end
    r.xpLast, r.maxLast, r.lvlLast = cur, max, lvl
    if delta > 0 and not r.paused then
        G.pending[#G.pending + 1] = { t = now(), x = delta, p = pct }
    end
end
function G.OnQuest(_, xp)
    if not G:Active() then return end
    G.quests[#G.quests + 1] = { t = now(), x = num(xp) and xp or 0 }
end
function G.Settle(all)
    local r = G:Run()
    local keep = {}
    for _, e in ipairs(G.pending) do
        if all or now() - e.t >= G.SETTLE then
            local x = e.x
            for _, q in ipairs(G.quests) do
                if q.x > 0 and math.abs(q.t - e.t) <= G.SETTLE then
                    local take = math.min(q.x, x)
                    q.x, x = q.x - take, x - take
                end
            end
            if r and x > 0 then
                r.xp = r.xp + x
                r.pct = r.pct + e.p * x / e.x
            end
        else
            keep[#keep + 1] = e
        end
    end
    G.pending = keep
    local qs = {}
    for _, q in ipairs(G.quests) do if now() - q.t < G.SETTLE * 3 then qs[#qs + 1] = q end end
    G.quests = qs
end

-- a kill: the game's "dies, you gain ... experience" line (not in a pause, not a quest turn-in)
G.kills = {}
function G.OnKillXP()
    local r = G:Run()
    if not r or r.paused then return end
    G.kills[#G.kills + 1] = now()
end
local function settleKills(all)
    local r = G:Run()
    local keep = {}
    for _, t in ipairs(G.kills) do
        if all or now() - t >= G.SETTLE then
            local quest = false
            for _, q in ipairs(G.quests) do if math.abs(q.t - t) <= G.SETTLE then quest = true end end
            if r and not quest then r.kills = r.kills + 1 end
        else
            keep[#keep + 1] = t
        end
    end
    G.kills = keep
end

-- loot
local function toPattern(fmt)
    if not str(fmt) then return nil end
    local p = fmt:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
    p = p:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
    return "^" .. p
end
local pats
function G.OnLoot(msg)
    local r = G:Run()
    if not r or r.paused or not str(msg) then return end
    if not pats then
        pats = {}
        for _, f in ipairs({ LOOT_ITEM_SELF_MULTIPLE or "", LOOT_ITEM_SELF or "" }) do
            local p = toPattern(f)
            if p then pats[#pats + 1] = p end
        end
    end
    for _, p in ipairs(pats) do
        local link, n = msg:match(p)
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            if id then r.items[id] = (r.items[id] or 0) + (tonumber(n) or 1) end
            return
        end
    end
end

-- gold: a rise of my money while the loot window is open, or next to the game's "You loot ..." line
local lootOpen, moneyAt = false, nil
function G.OnMoney()
    local r = G:Run()
    local m = money()
    if not (r and m) then return end
    local d = m - (r.moneyLast or m)
    r.moneyLast = m
    if d <= 0 or r.paused then return end
    if lootOpen or (moneyAt and now() - moneyAt <= G.SETTLE) then
        r.gold = r.gold + d
        moneyAt = nil
    else
        G.moneyPend = { t = now(), d = d }
    end
end
function G.OnMoneyMsg()
    local r = G:Run()
    if not r then return end
    local p = G.moneyPend
    if p and now() - p.t <= G.SETTLE and not r.paused then
        r.gold = r.gold + p.d
        G.moneyPend = nil
    else
        moneyAt = now()
    end
end
function G.SetLootOpen(v) lootOpen = v and true or false end

-- worth of an item: auction price minus the cut, or the vendor price when that is higher; grey and bound items
-- the vendor price; quest items nothing
function G.ItemValue(id)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not info then return 0 end
    local ok, _, _, quality, _, _, _, _, _, _, _, sell, classID, _, bind = pcall(info, id)
    if not ok then return 0 end
    if classID == 12 then return 0 end
    local vendor = (OMQ.Prices and OMQ.Prices.Vendor and OMQ.Prices.Vendor(id)) or (num(sell) and sell) or 0
    if quality == 0 or bind == 1 then return vendor end
    local ah = OMQ.Prices and OMQ.Prices.Auction and OMQ.Prices.Auction(id)
    if num(ah) and ah > 0 then return math.max(math.floor(ah * G.AH_CUT), vendor) end
    return vendor
end
function G.Worth(items)
    local sum = 0
    for id, n in pairs(items or {}) do sum = sum + G.ItemValue(id) * n end
    return sum
end

function G.Tick()
    local r = G:Run()
    if not r then G.Check(); return end
    G.Settle(); settleKills()
    if not r.paused then
        r.samples = r.samples + 1
        local d = G.Dist(r.spot)
        if d and d <= G.INSIDE then r.inside = r.inside + 1 end
    end
    if G.Remaining(r) <= 0 then G:Finish("time") end
end

----------------------------------------------------------------------
-- The end
----------------------------------------------------------------------
local function boardAdd(key, e)
    local b = db().boards[key] or {}
    db().boards[key] = b
    for _, o in ipairs(b) do if o.id == e.id and o.g == e.g then return nil end end
    b[#b + 1] = e
    table.sort(b, function(p, q) if p.x ~= q.x then return p.x > q.x end return (p.d or "") < (q.d or "") end)
    while #b > G.BOARD_KEEP do table.remove(b) end
    for i, o in ipairs(b) do if o == e then return i end end
    return nil
end
G.BoardAdd = boardAdd

function G.Qualifies(secs, inside, samples)
    return secs >= G.BOARD_MIN and samples > 0 and inside / samples >= G.BOARD_SHARE
end

function G:Finish(reason)
    local r = G:Run()
    if not r then return nil end
    if r.paused then r.pauseSum = r.pauseSum + (clock() - r.paused); r.paused = nil end
    G.Settle(true); settleKills(true)
    local secs = G.Used(r)
    local profit = G.Worth(r.items)
    local cur, max, lvl = xpNow()
    local res = { id = r.id, key = r.spot.key, name = r.spot.name, zone = r.spot.zone, mins = r.mins, secs = secs,
                  kills = r.kills, xp = r.xp, pct = r.pct * 100, xph = r.xp / math.max(secs, 60) * 3600,
                  profit = profit, gold = r.gold, gph = (profit + r.gold) / math.max(secs, 60) * 3600,
                  kph = r.kills / math.max(secs, 60) * 3600,
                  lvl0 = r.lvl0, lvl1 = lvl or r.lvl0, nowPct = cur and (cur / max * 100) or 0,
                  early = reason ~= "time", day = date and date("%Y-%m-%d") or "", group = G.early[r.id] or {} }
    G.early[r.id] = nil
    res.ok = G.Qualifies(secs, r.inside, r.samples)
    local hist = db().hist[guid()] or {}
    db().hist[guid()] = hist
    local best
    for _, h in ipairs(hist) do if not best or h.xph > best then best = h.xph end end
    res.best = best
    if OMQ.DungeonXP and OMQ.DungeonXP.OutsideRate then res.out = (OMQ.DungeonXP.OutsideRate()) end
    table.insert(hist, 1, { xph = res.xph, key = res.key, day = res.day, secs = secs })
    while #hist > 20 do table.remove(hist) end
    if res.ok then
        local e = { id = r.id, g = guid(), n = myName(), l = r.lvl0, d = res.day, x = math.floor(res.xph), m = math.floor(res.gph),
                    k = math.floor(res.kph) }
        res.place = boardAdd(r.spot.key, e)
        OMQ:Send("GB", r.spot.key, e.id, e.g, e.n, tostring(e.l), e.d, tostring(e.x), tostring(e.m), tostring(e.k))
    end
    if r.group then
        OMQ:Send("GR", "e", r.id, guid(), myName(), tostring(math.floor(r.xp)), tostring(profit + r.gold), tostring(r.kills))
    end
    db().runs[guid()] = nil
    G.last = res
    OMQ:Fire("QTRACK_CHANGED")
    fire()
    OMQ:Fire("GRIND_DONE", res)
    return res
end

function G:Cancel() return G:Finish("cancel") end

----------------------------------------------------------------------
-- Messages in the group
----------------------------------------------------------------------
function G.SendSpot(s)
    OMQ:SendBulk("GS", s.key, tostring(s.map), string.format("%.1f", s.x), string.format("%.1f", s.y), s.name or "",
                 s.by or "", s.byGuid or "", tostring(s.zone or s.map), s.day or "")
end
local function sendBoard(key, e)
    OMQ:SendBulk("GB", key, e.id or "", e.g or "", e.n or "", tostring(e.l or 0), e.d or "", tostring(e.x or 0),
                 tostring(e.m or 0), tostring(e.k or 0))
end
-- a dad joins: he gets my spots, what was deleted and the leaderboards
function G.Sync()
    local g = db()
    local n = 0
    for key in pairs(g.gone) do OMQ:SendBulk("GD", key, ""); n = n + 1 end
    for _, s in pairs(g.spots) do G.SendSpot(s); n = n + 1 end
    for key, b in pairs(g.boards) do
        for i = 1, math.min(#b, G.BOARD_SHOW) do sendBoard(key, b[i]); n = n + 1 end
    end
    return n
end

OMQ:RegisterMessage("GS", function(f)
    local key, map, x, y = f[1], tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
    if not (str(key) and map and x and y) or db().gone[key] or db().spots[key] then return end
    db().spots[key] = { key = key, map = map, x = x, y = y, name = f[5] ~= "" and f[5] or "Spot", by = f[6], byGuid = f[7],
                        zone = tonumber(f[8]) or map, day = f[9] }
    fire()
end)
OMQ:RegisterMessage("GD", function(f)
    local key = f[1]
    if not str(key) then return end
    local s = db().spots[key]
    if s and f[2] ~= "" and s.byGuid ~= f[2] then return end      -- only the dad who made it deletes it
    db().spots[key] = nil
    db().gone[key] = true
    fire()
end)
OMQ:RegisterMessage("GB", function(f)
    local key = f[1]
    local e = { id = f[2], g = f[3], n = f[4], l = tonumber(f[5]) or 0, d = f[6], x = tonumber(f[7]) or 0,
                m = tonumber(f[8]) or 0, k = tonumber(f[9]) or 0 }
    if not (str(key) and str(e.id) and str(e.g)) then return end
    boardAdd(key, e)
    fire()
end)
OMQ:RegisterMessage("GR", function(f, sender)
    local op = f[1]
    if op == "s" then
        if G:Active() then return end
        local spot = { key = f[3], map = tonumber(f[4]), x = tonumber(f[5]), y = tonumber(f[6]), name = f[8], zone = tonumber(f[11]) }
        if not (str(spot.key) and spot.map and spot.x and spot.y) then return end
        spot.zone = spot.zone or spot.map
        local d = G.Dist(spot)
        if not d or d > G.JOIN then return end          -- not there at the start: not in this run
        G:Start(spot, tonumber(f[7]), { id = f[2], starter = f[9] })
    elseif op == "e" then
        if f[3] == myGuid() then return end
        local res = G.last
        local list
        if res and res.id == f[2] then list = res.group
        else                                    -- his run ended before mine: kept for my summary
            G.early[f[2]] = G.early[f[2]] or {}
            list = G.early[f[2]]
        end
        for _, m in ipairs(list) do if m.g == f[3] then return end end
        list[#list + 1] = { g = f[3], n = f[4], xp = tonumber(f[5]) or 0, copper = tonumber(f[6]) or 0, kills = tonumber(f[7]) or 0 }
        if list == (res and res.group) then OMQ:Fire("GRIND_GROUP", res) end
    end
end)

----------------------------------------------------------------------
-- Events, restore, command
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_XP_UPDATE", "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY",
                     "PLAYER_MONEY", "LOOT_OPENED", "LOOT_CLOSED" }) do frame:RegisterEvent(e) end
local HANDLERS = {
    PLAYER_XP_UPDATE = function() G.OnXP() end,
    QUEST_TURNED_IN = function(_, xp) G.OnQuest(nil, xp) end,
    CHAT_MSG_COMBAT_XP_GAIN = function() G.OnKillXP() end,
    CHAT_MSG_LOOT = function(msg) G.OnLoot(msg) end,
    CHAT_MSG_MONEY = function() G.OnMoneyMsg() end,
    PLAYER_MONEY = function() G.OnMoney() end,
    LOOT_OPENED = function() G.SetLootOpen(true) end,
    LOOT_CLOSED = function() G.SetLootOpen(false) end,
}
frame:SetScript("OnEvent", function(_, event, ...)
    local fn = HANDLERS[event]
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then OMQ:Error("grind " .. event, err) end
end)

OMQ:On("READY", function()
    local r = G:Run()
    if r then
        -- after a reload or a new login the clock went on; XP and money count from here
        r.xpLast, r.maxLast, r.lvlLast = xpNow()
        r.moneyLast = money()
        OMQ:Fire("QTRACK_CHANGED")
    end
    C_Timer.NewTicker(1, function()
        local ok, err = pcall(G.Tick)
        if not ok then OMQ:Error("grind tick", err) end
    end)
end)
OMQ:On("USER_JOINED", function() G.Sync() end)

OMQ:RegisterCommand("grind", function(arg)
    arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "here" then
        local s = G:Here()
        if s and OMQ.GrindUI then OMQ.GrindUI:Arrive(s) end
        return
    end
    if arg == "off" or arg == "end" then
        if G:Active() then G:Finish("cancel") else OMQ:Print("Grind Run: no run active") end
        return
    end
    if arg == "pause" then
        if G:Active() then G:TogglePause() else OMQ:Print("Grind Run: no run active") end
        return
    end
    if arg == "diag" then
        local out = { "Grind Run - diagnostics" }
        local zone = G.MyZone()
        out[#out + 1] = string.format("zone: %s, level for spots: %d", zone and (G.ZoneName(zone) .. " (" .. zone .. ")") or "none", G.Level())
        for _, s in ipairs(zone and G.Spots(zone) or {}) do
            local d = G.Dist(s)
            out[#out + 1] = string.format("  %s  %s  %s yd", s.key, s.name or "?", d and tostring(math.floor(d)) or "?")
        end
        local r = G:Run()
        if r then
            out[#out + 1] = string.format("run %s: %d s used, %d s left, %d kills, %d XP, %d copper, %d/%d s on the spot%s",
                r.spot.name or "?", G.Used(r), G.Remaining(r), r.kills, r.xp, r.gold, r.inside, r.samples, r.paused and ", paused" or "")
        end
        if OMQ.ShowReport then OMQ:ShowReport(out) else for _, l in ipairs(out) do print(l) end end
        return
    end
    if OMQ.GrindUI then OMQ.GrindUI:Open() end
end, "Grind Run: /omq grind [here|pause|off|diag]")
