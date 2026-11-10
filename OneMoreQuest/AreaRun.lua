-- One More Quest: Area Run (decision 491)
-- The Area Run icon of the check bar opens a window with the zones: I pick one (my zone first) and OMQ plans one way
-- through every quest of that zone I can do: the quests of my log that belong to the zone, every quest whose giver
-- stands in the zone, and the follow-ups that open on the way. A quest counts when it is turned in; the bar shows
-- "Area Run: 4/23". The tracker card has a green frame.
--   Which quests: giver in the zone (or in my log with giver, objectives or turn-in in the zone), my faction, race and
--   class, never done, at most LEVEL_ABOVE levels above me, NOT grey (a grey pre-quest stays when a quest of the zone
--   needs it), never repeatable, from a profession, reputation or in a dungeon; from an item only when a named mob
--   of the zone drops it (decision 508: the pick up stop is at the mob). Elite quests stay in, also alone. Quests of a higher level join the run when I level up.
--   Quests that start outside the zone are no stops. A quest outside whose follow-ups (or objectives) are in the zone
--   is a hint: as soon as I am in the same zone or city as its giver, a card names it with the number of quests it
--   opens in the run's zone; "Add" puts it (and what it opens) into the run and the main arrow to its giver.
--   Turn-ins outside the zone (a capital city) come at the end, unless a follow-up needs them earlier.
--   The quest log: never more quests picked up than there is room; the next pick up waits for a turn-in.
--   Order: always the nearest stop that may come now, then a quick improvement (reversing parts, moving single
--   stops), counted on the ways over the land of Path.lua.
-- In a group the dad who starts plans the route from his log and sends it to the others (as the Quest Run, the RN
-- messages carry the kind "area" and the zone); a quest some dad does not carry gets a pick up stop.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local A = {}
OMQ.AreaRun = A

A.LEVEL_ABOVE = 2
A.MAX_DEPTH = 12
A.HINT_TICK = 2           -- seconds between the hint checks
A.HINT_SHOW = 25          -- seconds a hint card stays
A.BUDGET = 120            -- milliseconds the improvement may take at most

local function R() return OMQ.QuestRun end
local function NQ() return OMQ.NextQuest end
local function data(id) return OMQ.QuestPlaces and OMQ.QuestPlaces[id] end
local function has(flags, b) return flags ~= nil and math.floor(flags / b) % 2 == 1 end
local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function number(v) return type(v) == "number" and not isSecret(v) end
local function contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end
local function ever(id) return NQ().EverDone(id) end

----------------------------------------------------------------------
-- Zones
----------------------------------------------------------------------
local zoneSet
local function zones()
    if not zoneSet then
        zoneSet = {}
        for _, z in ipairs(OMQ.QuestZones or {}) do zoneSet[z[1]] = z end
    end
    return zoneSet
end
A.CITY = { [1453] = "Stormwind City", [1454] = "Orgrimmar", [1455] = "Ironforge", [1456] = "Thunder Bluff",
           [1457] = "Darnassus", [1458] = "Undercity" }

local function mapInfo(map)
    if not (map and C_Map and C_Map.GetMapInfo) then return nil end
    local ok, i = pcall(C_Map.GetMapInfo, map)
    if ok and type(i) == "table" then return i end
    return nil
end

-- the zone (or capital city) a map belongs to: the map itself or the first parent that is one
function A.ZoneOf(map)
    local z = zones()
    local m, guard = map, 0
    while m and guard < 6 do
        if z[m] or A.CITY[m] then return m end
        local i = mapInfo(m)
        local p = i and i.parentMapID
        if not number(p) or p == 0 or p == m then break end
        m, guard = p, guard + 1
    end
    return map
end

function A.MyZone()
    local pos = NQ().MyPos()
    return pos and pos.map and A.ZoneOf(pos.map) or nil
end

function A.ZoneName(zone)
    local i = mapInfo(zone)
    if i and type(i.name) == "string" and i.name ~= "" and not isSecret(i.name) then return i.name end
    local z = zones()[zone]
    return (z and z[5]) or A.CITY[zone] or ("zone " .. tostring(zone))
end

local function inZone(spots, zone)
    for _, s in ipairs(spots or {}) do if s[1] == zone then return true end end
    return false
end
A.InZone = inZone

-- where a quest starts: its giver, else the named mob that drops it (decision 508)
local function starts(id, d) return (d and d[7]) or NQ().Starts(id, true) end
-- does a quest belong to the zone? giver, objectives or turn-in there
local function touches(d, zone) return inZone(d[7], zone) or inZone(d[9], zone) or inZone(d[8], zone) end

----------------------------------------------------------------------
-- Places
----------------------------------------------------------------------
local function placeOf(spot)
    local w = NQ().World(spot)
    if not w then return nil end
    return { a = w[1], b = w[2], inst = w[3], map = spot[1], w = spot[4] or 1 }
end
-- the spots in the zone when there are any
local function local_(spots, zone)
    local inside = {}
    for _, s in ipairs(spots or {}) do if s[1] == zone then inside[#inside + 1] = s end end
    if #inside > 0 then return inside end
    return spots or {}
end
local function bestPlace(spots, from, zone)
    local best, bd
    for _, s in ipairs(local_(spots, zone)) do
        local p = placeOf(s)
        if p then
            local dd = from and R().Dist(from, p) or 0
            if not bd or dd < bd then best, bd = p, dd end
        end
    end
    return best
end
local function objPlace(spots, from, zone)
    local list = {}
    for _, s in ipairs(local_(spots, zone)) do list[#list + 1] = s end
    if #list == 0 then return nil end
    table.sort(list, function(x, y) return (x[4] or 1) > (y[4] or 1) end)
    local top = list[1][4] or 1
    local good = {}
    for _, s in ipairs(list) do if (s[4] or 1) * 2.5 >= top then good[#good + 1] = s end end
    return bestPlace(good, from, zone)
end
-- the game's own point of a log quest on the zone's map (quests the data does not know)
local function zonePoint(qid, zone)
    if not (zone and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return nil end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, zone)
    if not ok or type(list) ~= "table" then return nil end
    for _, q in ipairs(list) do
        if type(q) == "table" and q.questID == qid and number(q.x) and number(q.y) then
            return placeOf({ zone, q.x * 100, q.y * 100, 1 })
        end
    end
end

----------------------------------------------------------------------
-- Quests
----------------------------------------------------------------------
-- may I take this quest some day? faction, race, class, no excluding quest done (not the level)
function A.ForMe(id, who, log)
    local d = data(id)
    if not d then return true end
    if d[4] and who.fac and d[4] ~= who.fac then return false end
    if d[5] and who.race and not contains(d[5], who.race) then return false end
    if d[6] and who.class and not contains(d[6], who.class) then return false end
    for _, p in ipairs(d[12] or {}) do if ever(p) or (log and log[p]) then return false end end
    return true
end
local function excluded(d, id)
    if has(d[13], 1) or has(d[13], 2) then return true end
    if d[7] then return has(d[13], 4) end
    return not (id and NQ().Drop(id))              -- from an item: only a named mob's drop (508)
end

-- ctx = { zone, pos, log, who, allow, quests = { [id] = entry }, order = { id }, fail = { [id] = blocker | false },
--         later = { [id] = true } }
-- entry = { id, goal = "turnin", pick, obj, turnin, follow, needs = { id }, late = turn-in outside the zone }
local resolve
local function needsOf(ctx, d, visiting, depth)
    local needs = {}
    for _, p in ipairs(d[10] or {}) do                       -- all of them
        if not ever(p) then
            if not resolve(ctx, p, visiting, depth + 1) then return nil, ctx.fail[p] end
            if ctx.quests[p] then needs[#needs + 1] = p end
        end
    end
    if d[11] and #d[11] > 0 then                             -- one of them
        for _, p in ipairs(d[11]) do if ever(p) then return needs end end
        for _, p in ipairs(d[11]) do if ctx.quests[p] then needs[#needs + 1] = p; return needs end end
        local blocker
        for _, p in ipairs(d[11]) do
            if resolve(ctx, p, visiting, depth + 1) then
                if ctx.quests[p] then needs[#needs + 1] = p end
                return needs
            end
            blocker = blocker or ctx.fail[p]
        end
        return nil, blocker
    end
    return needs
end

local function fail(ctx, id, blocker)
    ctx.fail[id] = blocker or false
    return false
end

function resolve(ctx, id, visiting, depth)
    if ctx.quests[id] then return true end
    if ctx.fail[id] ~= nil then return false end
    if ever(id) then return true end
    if ctx.skip[id] then return fail(ctx, id) end                                  -- skipped: what needs it goes too
    if depth > A.MAX_DEPTH or visiting[id] then return false end
    local d = data(id)
    local inLog = ctx.log[id] and true or false
    if not d then return fail(ctx, id) end
    if not inLog then
        if not A.ForMe(id, ctx.who, ctx.log) or excluded(d, id) then return fail(ctx, id) end
        if (d[2] or 0) > ctx.who.level then ctx.later[id] = true; return fail(ctx, id) end
        if not inZone(starts(id, d), ctx.zone) and not ctx.allow[id] then return fail(ctx, id, id) end   -- starts outside the zone
    end
    if has(d[13], 8) and not NQ().IsComplete(id) then return fail(ctx, id) end     -- objectives in a dungeon
    local needs = {}
    if not inLog then
        visiting[id] = true
        local blocker
        needs, blocker = needsOf(ctx, d, visiting, depth)
        visiting[id] = nil
        if not needs then return fail(ctx, id, blocker) end
    end
    local e = { id = id, goal = "turnin", needs = needs }
    local from = ctx.pos
    if not inLog then e.pick = bestPlace(starts(id, d), from, ctx.zone); from = e.pick or from end
    if not NQ().IsComplete(id) and d[9] then e.obj = objPlace(d[9], from, ctx.zone); from = e.obj or from end
    e.turnin = bestPlace(d[8], from, ctx.zone)
    if not e.turnin then
        if inLog then e.follow = e.obj or zonePoint(id, ctx.zone) or ctx.pos; e.obj = nil
        else return fail(ctx, id) end
    end
    if e.turnin and e.turnin.map ~= ctx.zone then e.late = true end
    ctx.quests[id] = e
    ctx.order[#ctx.order + 1] = id
    return true
end
A._resolve = resolve

-- the stops of an entry
local function addStops(ctx, e)
    local function stop(kind, place)
        if not place then return end
        local s = { qid = e.id, kind = kind, place = place, goal = "turnin" }
        if kind == "p" and e.needs and #e.needs > 0 then s.needs = e.needs end
        if kind == "t" and e.late then s.late = true end
        ctx.stops[#ctx.stops + 1] = s
    end
    stop("p", e.pick)
    if e.follow then
        local s = { qid = e.id, kind = "w", place = e.follow, goal = "turnin" }
        ctx.stops[#ctx.stops + 1] = s
        return
    end
    stop("o", e.obj)
    stop("t", e.turnin)
end

----------------------------------------------------------------------
-- Order: never more quests than the log holds
----------------------------------------------------------------------
-- free = room in the log now; a pick up takes a place, a turn-in gives one back
function A.Valid(stops, free)
    if not R()._valid(stops) then return false end
    local rest = false                   -- the pick ups outside the zone I chose come first (decision 510)
    for _, s in ipairs(stops) do
        if s.early then if rest then return false end else rest = true end
    end
    if not free then return true end
    local n = free
    for _, s in ipairs(stops) do
        if s.kind == "p" then n = n - 1; if n < 0 then return false end
        elseif s.kind == "t" then n = n + 1 end
    end
    return true
end

local function clock() return debugprofilestop and debugprofilestop() or nil end

-- a pick up outside the zone of a quest I chose to add ("Pick up first", the hint card) comes before the zone
function A.MarkEarly(stops, zone, allow)
    for _, s in ipairs(stops or {}) do
        s.early = (s.kind == "p" and allow and allow[s.qid] and s.place and s.place.map and s.place.map ~= zone) and true or nil
    end
    return stops
end

-- the first order: the pick ups I chose outside the zone first, then the nearest stop that may come now (turn-ins
-- outside the zone last), then the improvement
function A.Order(pos, stops, free)
    local left, out = {}, {}
    for _, s in ipairs(stops) do left[#left + 1] = s end
    local total, seen = {}, {}
    for _, s in ipairs(stops) do total[s.qid] = (total[s.qid] or 0) + 1 end
    local rank = { p = 1, w = 2, o = 2, t = 3 }
    local room = free or math.huge
    local open = {}            -- qid -> { [rank] = stops of that rank still left }
    for _, s in ipairs(stops) do
        local o = open[s.qid]
        if not o then o = { 0, 0, 0 }; open[s.qid] = o end
        o[rank[s.kind]] = o[rank[s.kind]] + 1
    end
    local function may(s)
        for _, n in ipairs(s.needs or {}) do if total[n] and (seen[n] or 0) < total[n] then return false end end
        local o, r = open[s.qid], rank[s.kind]
        for k = 1, r - 1 do if o[k] > 0 then return false end end      -- the quest's own stops in their order: p, o, t
        if s.kind == "p" and room <= 0 then return false end
        return true
    end
    local cur = pos
    local memo = {}
    local function d(p, q)
        local m = memo[p]
        if not m then m = {}; memo[p] = m end
        local v = m[q]
        if not v then v = R().Dist(p, q); m[q] = v end
        return v
    end
    while #left > 0 do
        local bi, bd, li, ld, ei, ed
        for i, s in ipairs(left) do
            if may(s) then
                local dd = d(cur, s.place)
                if s.early then
                    if not ed or dd < ed then ei, ed = i, dd end
                elseif s.late then
                    if not ld or dd < ld then li, ld = i, dd end
                elseif not bd or dd < bd then bi, bd = i, dd end
            end
        end
        bi = ei or bi or li
        if not bi then for i = 1, #left do out[#out + 1] = left[i] end break end   -- a loop in the data: keep the rest
        local s = table.remove(left, bi)
        out[#out + 1] = s
        seen[s.qid] = (seen[s.qid] or 0) + 1
        local o = open[s.qid]; o[rank[s.kind]] = o[rank[s.kind]] - 1
        if s.kind == "p" then room = room - 1 elseif s.kind == "t" then room = room + 1 end
        cur = s.place
    end
    return A.Improve(pos, out, free, 3)
end

-- reversing parts and moving single stops while the way gets shorter; the change is measured on the stops it
-- touches only, within a time budget (long runs)
function A.Improve(pos, stops, free, passes)
    local n = #stops
    if n < 3 then return stops end
    local memo = {}
    local function d(p, q)
        if not (p and q) then return 0 end
        local m = memo[p]
        if not m then m = {}; memo[p] = m end
        local v = m[q]
        if not v then v = R().Dist(p, q); m[q] = v end
        return v
    end
    local function at(list, i) if i == 0 then return pos end local s = list[i]; return s and s.place end
    local function cost(list)
        local c, prev = 0, pos
        for _, s in ipairs(list) do c = c + d(prev, s.place); prev = s.place end
        return c
    end
    local best = cost(stops)
    local t0 = clock()
    local function late() return t0 and clock() - t0 > A.BUDGET end
    for _ = 1, passes or 2 do
        local better = false
        for i = 1, n - 1 do
            if late() then return stops end
            for j = i + 1, n do
                local a, b, c, e = at(stops, i - 1), at(stops, i), at(stops, j), at(stops, j + 1)
                local delta = d(a, c) - d(a, b) + (e and (d(b, e) - d(c, e)) or 0)
                if delta < -1 then
                    local t = {}
                    for k = 1, i - 1 do t[#t + 1] = stops[k] end
                    for k = j, i, -1 do t[#t + 1] = stops[k] end
                    for k = j + 1, n do t[#t + 1] = stops[k] end
                    local cc = cost(t)
                    if cc < best - 0.5 and A.Valid(t, free) then stops, best, better = t, cc, true end
                end
            end
        end
        for i = 1, n do
            if late() then return stops end
            local x = stops[i].place
            local p, q = at(stops, i - 1), at(stops, i + 1)
            local gain = d(p, x) + (q and (d(x, q) - d(p, q)) or 0)
            for j = 0, n do
                if j ~= i and j ~= i - 1 then
                    local a, b = at(stops, j), at(stops, j + 1)
                    local add = d(a, x) + (b and (d(x, b) - d(a, b)) or 0)
                    if add - gain < -1 then
                        local t = {}
                        for k = 1, n do if k ~= i then t[#t + 1] = stops[k] end end
                        table.insert(t, j < i and j + 1 or j, stops[i])
                        local cc = cost(t)
                        if cc < best - 0.5 and A.Valid(t, free) then stops, best, better = t, cc, true; break end
                    end
                end
            end
        end
        if not better then break end
    end
    return stops
end

-- the open stops of a running Area Run sorted again (QuestRun's clock calls it)
function A.Resort(pos, stops)
    local free = R().FreeSlots((R().MyLog()))
    local r = R():Run()
    if r and r.kind == "area" then A.MarkEarly(stops, r.zone, r.allow) end
    return A.Improve(pos, stops, free, 1)
end

----------------------------------------------------------------------
-- The plan of a zone
----------------------------------------------------------------------
-- a quest outside the zone I can take now on the way to blocker (its own pre-quests may be outside too)
local function takeable(ctx, id, depth)
    depth = depth or 0
    if depth > 5 then return nil end
    local d = data(id)
    if not d or ever(id) or ctx.log[id] then return nil end
    if NQ().CanTake(id, ctx.who, ctx.log) then return id end
    for _, p in ipairs(d[10] or {}) do
        if not ever(p) then local t = takeable(ctx, p, depth + 1); if t then return t end end
    end
    for _, p in ipairs(d[11] or {}) do
        local t = takeable(ctx, p, depth + 1)
        if t then return t end
    end
    return nil
end

-- the same quest at several givers (exclusive, e.g. The Ashenvale Hunt in Orgrimmar, Thunder Bluff and the Crossroads):
-- one hint, at the giver nearest to me; none when one of them is in the run, in my log or done (decision 510)
local function sameQuest(id)
    local d = data(id)
    local out = { id }
    for _, x in ipairs(d and d[12] or {}) do
        local dx = data(x)
        if dx and dx[1] == d[1] then out[#out + 1] = x end
    end
    return out
end
-- opens = { [outside quest] = { [zone quest] = true } } -> hints sorted: most quests opened, then the nearest giver
function A.Hints(opens, ctx, pos)
    local taken = {}
    for id in pairs(ctx.quests) do taken[id] = true end
    for id in pairs(ctx.log) do taken[id] = true end
    for id in pairs(ctx.allow or {}) do taken[id] = true end
    local groups, seen = {}, {}
    local ids = {}
    for id in pairs(opens) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if not seen[id] then
            local same = sameQuest(id)
            local blocked, set, best, bd, bmap = false, {}, nil, nil, nil
            for _, x in ipairs(same) do
                seen[x] = true
                if taken[x] or ever(x) then blocked = true end
                for q in pairs(opens[x] or {}) do set[q] = true end
            end
            for _, x in ipairs(same) do
                if (opens[x] or x == id) and not blocked then
                    local dx = data(x)
                    for _, g in ipairs(dx and dx[7] or {}) do
                        local p = placeOf(g)
                        if p then
                            local dd = pos and R().Dist(pos, p) or 0
                            if not bd or dd < bd then best, bd, bmap = { id = x, place = p }, dd, g[1] end
                        end
                    end
                end
            end
            if best then
                local itself = false
                for _, x in ipairs(same) do if set[x] then set[x] = nil; itself = true end end
                if itself then set[best.id] = true end
                local list = {}
                for q in pairs(set) do list[#list + 1] = q end
                table.sort(list)
                local n = #list
                groups[#groups + 1] = { id = best.id, map = bmap, place = best.place, opens = n, list = list,
                                        title = data(best.id)[1], dist = bd or 0 }
            end
        end
    end
    table.sort(groups, function(x, y)
        if x.opens ~= y.opens then return x.opens > y.opens end
        if math.abs(x.dist - y.dist) > 1 then return x.dist < y.dist end
        return x.id < y.id
    end)
    return groups
end

-- { stops, quests = { entry }, length, info, hints, kind = "area", zone, n }
-- info = { grey, later, unknown, inLog, new, free, logFull, skipped = { id } }
-- hint = { id, map, place, opens = number of quests of the zone it opens, list = { those quests }, title, dist }
function A.Build(zone, pos, log, who, skip, allow, members, noOrder)
    who = who or NQ().Me()
    skip, allow, log = skip or {}, allow or {}, log or {}
    local ctx = { zone = zone, pos = pos, log = log, who = who, allow = allow, skip = skip, quests = {}, order = {}, stops = {},
                  fail = {}, later = {} }
    local info = { grey = 0, later = 0, unknown = 0, inLog = 0, new = 0, skipped = {} }
    local blocked = {}           -- outside quest -> { zone quest = true }
    local function want(id)
        if skip[id] then info.skipped[#info.skipped + 1] = id; return end
        if resolve(ctx, id, {}, 0) then return true end
        local b = ctx.fail[id]
        if b then blocked[b] = blocked[b] or {}; blocked[b][id] = true end
    end
    -- the quests of my log that belong to the zone
    local ids = {}
    for id in pairs(log) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local d = data(id)
        if d then
            if touches(d, zone) then want(id) end
        elseif not skip[id] then
            local p = zonePoint(id, zone)
            if p then
                ctx.quests[id] = { id = id, goal = "turnin", needs = {}, follow = p }
                ctx.order[#ctx.order + 1] = id
            end
        end
    end
    -- every quest whose giver stands in the zone
    local grey = NQ().GreyBelow(who.level)
    local news = {}
    for id, d in pairs(OMQ.QuestPlaces or {}) do
        if inZone(starts(id, d), zone) and not log[id] then news[#news + 1] = id end
    end
    table.sort(news)
    for _, id in ipairs(news) do
        local d = data(id)
        if not ever(id) and not excluded(d, id) and not has(d[13], 8) and A.ForMe(id, who, log) then
            local ql = d[3] or 0
            if ql > 0 and ql < grey then info.grey = info.grey + 1
            elseif ql > who.level + A.LEVEL_ABOVE or (d[2] or 0) > who.level then info.later = info.later + 1
            else want(id) end
        end
    end
    -- quests from outside that I chose to add (the hint card)
    local allowed = {}
    for id in pairs(allow) do allowed[#allowed + 1] = id end
    table.sort(allowed)
    for _, id in ipairs(allowed) do if not log[id] then want(id) end end
    -- hints: quests outside the zone that open quests of the zone, or whose objectives are in the zone
    local opens = {}             -- outside quest -> { zone quest = true }
    local function hint(outside, set)
        local id = takeable(ctx, outside)
        if id and not skip[id] and not allow[id] then
            opens[id] = opens[id] or {}
            for q in pairs(set) do opens[id][q] = true end
        end
    end
    for b, set in pairs(blocked) do hint(b, set) end
    for id, d in pairs(OMQ.QuestPlaces or {}) do
        if d[7] and not inZone(d[7], zone) and (inZone(d[9], zone) or inZone(d[8], zone)) and not log[id] and not ctx.quests[id] then
            local ql = d[3] or 0
            if not (ql > 0 and ql < grey) and NQ().CanTake(id, who, log) then hint(id, { [id] = true }) end   -- the quest itself counts
        end
    end
    local hints = A.Hints(opens, ctx, pos)
    for id in pairs(ctx.later) do if not ctx.quests[id] then info.later = info.later + 1 end end
    -- in a group: a quest of my log some dad does not carry gets a pick up stop at its giver
    for _, u in ipairs(members or {}) do
        if u.quests then
            for _, id in ipairs(ctx.order) do
                local e = ctx.quests[id]
                local d = data(id)
                if e and not e.pick and not e.follow and not u.quests[id] and d and starts(id, d) then
                    e.pick = bestPlace(starts(id, d), ctx.pos, zone)
                end
            end
        end
    end
    for _, id in ipairs(ctx.order) do
        local e = ctx.quests[id]
        if e.pick then info.new = info.new + 1 else info.inLog = info.inLog + 1 end
        addStops(ctx, e)
    end
    local free = R().FreeSlots(log)
    info.free = free
    info.logFull = info.new > free
    A.MarkEarly(ctx.stops, zone, allow)
    local stops = noOrder and ctx.stops or A.Order(pos, ctx.stops, free)   -- a refresh sorts in the run
    local list = {}
    for _, id in ipairs(ctx.order) do list[#list + 1] = ctx.quests[id] end
    return { stops = stops, quests = list, length = noOrder and 0 or R().PathCost(pos, stops), info = info, hints = hints,
             kind = "area", zone = zone, n = #list }
end

----------------------------------------------------------------------
-- The zones for the window
----------------------------------------------------------------------
-- how many quests a zone has for me now (a quick count without the chains): giver in the zone, not done, for me,
-- the level fits and not grey
function A.Count(zone, who, log)
    who = who or NQ().Me()
    log = log or (R().MyLog())
    local grey = NQ().GreyBelow(who.level)
    local n = 0
    for id, d in pairs(OMQ.QuestPlaces or {}) do
        if inZone(starts(id, d), zone) then
            if log[id] then n = n + 1
            elseif not ever(id) and not excluded(d, id) and not has(d[13], 8) and A.ForMe(id, who, log) then
                local ql = d[3] or 0
                if not (ql > 0 and ql < grey) and ql <= who.level + A.LEVEL_ABOVE and (d[2] or 0) <= who.level then n = n + 1 end
            end
        end
    end
    return n
end

-- { { zone, name, min, max, count, here } }: my zone first, then the zones of my faction that fit my level;
-- all = every zone of my faction
function A.ZoneList(all)
    local who = NQ().Me()
    local log = R().MyLog()
    local here = A.MyZone()
    local out, seen = {}, {}
    local function add(zone, min, max)
        if seen[zone] then return end
        seen[zone] = true
        out[#out + 1] = { zone = zone, name = A.ZoneName(zone), min = min, max = max, count = A.Count(zone, who, log), here = zone == here }
    end
    if here then
        local z = zones()[here]
        add(here, z and z[2], z and z[3])
    end
    local rest = {}
    for _, z in ipairs(NQ().Zones(who.fac)) do
        if all or (z[2] <= who.level + A.LEVEL_ABOVE and z[3] >= who.level - 2) then rest[#rest + 1] = z end
    end
    table.sort(rest, function(x, y) if x[2] ~= y[2] then return x[2] < y[2] end return x[1] < y[1] end)
    for _, z in ipairs(rest) do add(z[1], z[2], z[3]) end
    return out
end

----------------------------------------------------------------------
-- Preparing and starting
----------------------------------------------------------------------
local prep = nil      -- { zone, pos, log, titles, plan, skip, allow, members }
function A:Prep() return prep end

local function members()
    local m = NQ().Members()
    return m
end

function A:Prepare(zone)
    if not OMQ.QuestPlaces then OMQ:Print("Area Run: no quest data"); return nil end
    local pos = NQ().MyPos()
    if not pos then OMQ:Print("Area Run: no position here"); return nil end
    local log, titles = R().MyLog()
    prep = { zone = zone, pos = pos, log = log, titles = titles, skip = {}, allow = {}, members = members() }
    prep.plan = A.Build(zone, pos, log, nil, prep.skip, prep.allow, prep.members)
    return prep
end

-- the preview: leave out a quest and every quest that needs it
function A:SkipPlanned(qid)
    if not prep then return nil end
    prep.skip[qid] = true
    prep.plan = A.Build(prep.zone, prep.pos, prep.log, nil, prep.skip, prep.allow, prep.members)
    return prep.plan
end

-- the preview's "Pick up first": a quest outside the zone joins the plan, its pick up comes first (decision 510)
function A:AllowPlanned(qid)
    if not prep then return nil end
    prep.allow[qid] = true
    prep.skip[qid] = nil
    prep.plan = A.Build(prep.zone, prep.pos, prep.log, nil, prep.skip, prep.allow, prep.members)
    return prep.plan
end

-- the preview rows: one per quest, in the order of the way
function A.Rows(plan)
    local rows, first = {}, {}
    for i, s in ipairs(plan and plan.stops or {}) do if not first[s.qid] then first[s.qid] = i end end
    for _, e in ipairs(plan and plan.quests or {}) do
        local what
        if e.follow then what = "in your log - the game's map point"
        elseif e.pick and plan.zone and e.pick.map and e.pick.map ~= plan.zone then
            what = "pick it up first in " .. A.ZoneName(e.pick.map)
        elseif e.pick and #e.needs > 0 then what = "follow-up of " .. R().Title(e.needs[#e.needs])
        elseif e.pick then what = "pick it up"
        elseif e.obj then what = "in your log"
        else what = "in your log - turn it in" end
        if e.late then what = what .. ", turn-in outside the zone" end
        rows[#rows + 1] = { qid = e.id, what = what, elite = R().IsElite(e.id), new = e.pick ~= nil, first = first[e.id] or 1e9 }
    end
    table.sort(rows, function(a, b) return a.first < b.first end)
    return rows
end

function A:Start(plan)
    plan = plan or (prep and prep.plan)
    if not plan then return false end
    plan.members = prep and prep.members or {}
    plan.allow = prep and prep.allow or {}
    local ok = R():Start(plan)
    if ok then
        prep = nil
        A.hints = plan.hints or {}
        A.dismissed, A.shownIn = {}, {}
    end
    return ok
end

----------------------------------------------------------------------
-- While the run goes: new quests (level up, quests picked up outside the plan) and the hints
----------------------------------------------------------------------
A.hints, A.dismissed, A.shownIn = {}, {}, {}

local function areaRun()
    local r = R():Run()
    if r and r.kind == "area" and (not r.group or R():IsLeader()) then return r end
    return nil
end

-- plans the zone again from where I stand and adds what is new to the run (nothing that is in it goes)
function A.Refresh()
    local r = areaRun()
    if not r then return 0 end
    local pos = NQ().MyPos()
    if not pos then return 0 end
    local log = R().MyLog()
    local skip = {}
    for id in pairs(r.skip or {}) do skip[id] = true end
    local plan = A.Build(r.zone, pos, log, nil, skip, r.allow or {}, r.members, true)
    A.hints = plan.hints or {}
    local add = {}
    for _, e in ipairs(plan.quests) do
        local q = r.quests[e.id]
        if not q then add[e.id] = true end
    end
    local stops = {}
    for _, s in ipairs(plan.stops) do
        if add[s.qid] then
            local needs
            for _, n in ipairs(s.needs or {}) do if add[n] then needs = needs or {}; needs[#needs + 1] = n end end
            stops[#stops + 1] = { qid = s.qid, kind = s.kind, place = s.place, goal = "turnin", needs = needs, late = s.late }
        end
    end
    if #stops == 0 then return 0 end
    return R():AddStops(stops)
end

-- the hint card's "Add": the quest and what it opens join the run, the main arrow goes to its giver
function A.TakeHint(h)
    local r = areaRun()
    if not (r and h) then return false end
    r.allow = r.allow or {}
    r.allow[h.id] = true
    A.dismissed[h.id] = true
    A.Refresh()
    if OMQ.Guide and h.place then
        OMQ.Guide:StartAt("Area Run: " .. R().Title(h.id), h.place.a, h.place.b, h.place.inst, "run", nil,
            { name = "pick up the quest", radius = R().PICK_RADIUS, qid = h.id })
    end
    return true
end
function A.DismissHint(h) if h then A.dismissed[h.id] = true end end

-- the hint for the zone I am in now: the one that opens the most quests (nil when none, or shown in this visit)
function A.HintHere(pos)
    local r = R():Run()
    if not (r and r.kind == "area") then return nil end
    pos = pos or NQ().MyPos()
    if not (pos and pos.map) then return nil end
    local here = A.ZoneOf(pos.map)
    if here == r.zone then return nil end
    local log
    for _, h in ipairs(A.hints or {}) do
        if not A.dismissed[h.id] and (h.map == here or h.map == pos.map) and not ever(h.id) then
            log = log or R().MyLog()
            if not log[h.id] then return h end
        end
    end
    return nil
end

local lastZone
function A.CheckHints()
    local r = R():Run()
    if not (r and r.kind == "area") then lastZone = nil; return nil end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return nil end
    if UnitOnTaxi and UnitOnTaxi("player") then return nil end
    local pos = NQ().MyPos()
    local here = pos and pos.map and A.ZoneOf(pos.map)
    if here ~= lastZone then lastZone = here; A.shownIn = {} end          -- a new visit: hints may show again
    local h = A.HintHere(pos)
    if not h or A.shownIn[h.id] then return nil end
    A.shownIn[h.id] = true
    if OMQ.AreaRunUI and OMQ.AreaRunUI.ShowHint then OMQ.AreaRunUI:ShowHint(h) end
    return h
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local pending
local function later(secs)
    if pending then return end
    pending = true
    C_Timer.After(secs or 2, function()
        pending = nil
        local ok, err = pcall(A.Refresh)
        if not ok then OMQ:Error("arearun", err) end
    end)
end
A._later = later

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "QUEST_ACCEPTED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
    if not areaRun() then return end
    later(event == "PLAYER_LEVEL_UP" and 3 or 2)
end)

OMQ:On("READY", function()
    C_Timer.After(5, function() if areaRun() then later(1) end end)     -- the hints of a restored run
    C_Timer.NewTicker(A.HINT_TICK, function()
        local ok, err = pcall(A.CheckHints)
        if not ok then OMQ:Error("arearun", err) end
    end)
end)

OMQ:RegisterCommand("arun", function(arg)
    arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "off" or arg == "end" then
        local r = R():Run()
        if r and r.kind == "area" then R():End(); OMQ:Print("Area Run ended") else OMQ:Print("Area Run: no run active") end
        return
    end
    if arg == "diag" then
        local out = { "Area Run - diagnostics" }
        local zone = A.MyZone()
        out[#out + 1] = "zone: " .. (zone and (A.ZoneName(zone) .. " (" .. zone .. ")") or "none")
        local r = R():Run()
        if r and r.kind == "area" then
            local d, all = R():Counts()
            out[#out + 1] = string.format("run: %s, %d/%d done, %d stops open, %d hints", A.ZoneName(r.zone), d, all, #r.stops, #(A.hints or {}))
            for _, h in ipairs(A.hints or {}) do
                out[#out + 1] = string.format("  hint: %s in %s, opens %d", R().Title(h.id), A.ZoneName(h.map), h.opens)
            end
        end
        if OMQ.ShowReport then OMQ:ShowReport(out) else for _, l in ipairs(out) do print(l) end end
        return
    end
    local zone = tonumber(arg)
    if not zone and arg ~= "" then
        for _, z in ipairs(OMQ.QuestZones or {}) do
            if z[5]:lower() == arg or A.ZoneName(z[1]):lower() == arg then zone = z[1] end
        end
    end
    if OMQ.AreaRunUI then OMQ.AreaRunUI:Open(zone) end
end, "Area Run: /omq arun [zone|off|diag] - one way through every quest of a zone")
