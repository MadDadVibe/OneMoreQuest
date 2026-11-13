-- One More Quest: ways over the land instead of straight lines (decision 469)
-- Data/PathGraph.lua holds a coarse walking network of each continent: one anchor per terrain tile (533 yards) and
-- group of walkable ground, with the walk to the anchors of the next tiles, made from the game's walkable terrain
-- (mountains, cliffs, lakes and the sea are walked around, passes and bridges are used). A way goes from a place
-- straight to the nearest anchors, over the anchors, and straight from the last anchors to the target.
-- Flights: the flight masters this character knows on this continent (learned at the flight map, fix 470) join
-- the network; a flight costs its time (OMQ.Taxi:Time) plus FLIGHT_EXTRA seconds, so a
-- flight is only taken when it is at least that much quicker than walking. Costs are in yards on foot
-- (seconds x SPEED), so a planner that adds yards keeps working.
--   P.Cost(p, q)  the cost of the way, nil when the network cannot tell (no data, other continent)
--   P.Way(p, q)   the way for an arrow (Quest Run's small arrow, the main arrow of Guide.lua): { cost, straight, a, b (the point to head for now), via, flight }
-- Fine steering (decision 472): near me the arrow's heading is checked on the 8-yard raster of Data/PathRaster.lua
-- and steered around walls, cliffs and water the coarse network does not see.
-- Routes (decision 585): the whole walk to the arrow's target is searched once on that raster and kept; the arrow
-- follows it (the network and the fine look above are what the arrow uses until the route is found).
-- /omq path [on|off|fine on|fine off|diag|probe|log]   (fine off: neither fine steering nor routes)
-- Middle click on an arrow: way over the land <-> straight line (decision 505)
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.Path = P

local TILE = 1600 / 3
local ORIGIN = 32 * TILE
P.SPEED = 7                 -- yards per second on foot
P.FLIGHT_EXTRA = 60         -- seconds a flight must save (getting on, the ticket)
P.DIRECT = 150              -- closer than this: straight
P.NEAR = 5                  -- anchors tried around a place
P.NEAR_MAX = 1200           -- yards to an anchor at most
P.BOUND = 3000              -- yards searched for the planner
P.WAY_KEEP = 4                -- targets whose search back is kept
P.WAY_BOUND = 40000         -- yards searched back from the arrow's target
P.SLACK, P.SLACK_YD = 1.12, 25   -- a part of the way this close to the straight line is walked straight
P.ISLAND, P.ISLAND_YD = 1.5, 600 -- target in ground the network does not join (an island): boat, a guess
P.JOIN_MOVE = 8             -- the anchors the arrow may join are found again after this many yards (485)
P.JOIN_KEEP, P.JOIN_KEEP_YD = 1.03, 20   -- the last join is kept while it costs no more than this (477)
P.PASSED = 15               -- a way point this close counts as reached: the arrow heads for the next one
P.CUT, P.CUT_YD = 1.12, 25  -- a way point behind me is skipped when the walk on from it is about this straight
P.CARROT = 40               -- the arrow heads for a point this far ahead on the way: it glides round corners (477)
P.CARROT_FINE = 30          -- the same on a fine way round a wall

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not isSecret(v) end
local function straight(a1, b1, a2, b2) return math.sqrt((a1 - a2) ^ 2 + (b1 - b2) ^ 2) end

function P.Enabled()
    if not OMQ.PathGraph then return false end
    return not (OMQDB and OMQDB.pathOff)
end

-- the arrows (decision 505): a middle click on an arrow switches them between the way over the land and the
-- straight line; Quest Run's order of stops keeps using the ways
function P.ArrowStraight() return (OMQDB and OMQDB.pathArrowStraight) and true or false end
function P.ArrowWays() return P.Enabled() and not P.ArrowStraight() end
function P.ToggleArrow()
    if not OMQDB then return P.ArrowWays() end
    if P.ArrowWays() then
        OMQDB.pathArrowStraight = true
    else
        OMQDB.pathArrowStraight = nil
        OMQDB.pathOff = nil
    end
    P._ResetWay()
    return P.ArrowWays()
end

----------------------------------------------------------------------
-- The network of a continent
----------------------------------------------------------------------
local graphs = {}
local function tileKey(a, b)
    return math.floor((ORIGIN - a) / TILE) * 128 + math.floor((ORIGIN - b) / TILE)
end
P.TileKey = tileKey

function P.Graph(inst)
    local g = graphs[inst]
    if g ~= nil then return g or nil end
    local d = OMQ.PathGraph and OMQ.PathGraph[inst]
    if type(d) ~= "table" or type(d.n) ~= "table" then graphs[inst] = false; return nil end
    g = { x = {}, y = {}, e = d.e or {}, tiles = {}, n = math.floor(#d.n / 2) }
    for i = 1, g.n do
        local a, b = d.n[2 * i - 1], d.n[2 * i]
        g.x[i], g.y[i] = a, b
        local k = tileKey(a, b)
        local t = g.tiles[k]
        if not t then t = {}; g.tiles[k] = t end
        t[#t + 1] = i
    end
    graphs[inst] = g
    return g
end

-- the anchors a place walks to straight: those of its own tile (the walks inside a tile are short), else the
-- nearest of the next tiles, else of the tiles after them: { {i, yards}, ... } nearest first
function P.Near(g, a, b)
    local k0 = tileKey(a, b)
    local list = {}
    for ring = 0, 2 do
        for dr = -ring, ring do
            for dc = -ring, ring do
                if math.abs(dr) == ring or math.abs(dc) == ring then
                    for _, i in ipairs(g.tiles[k0 + dr * 128 + dc] or {}) do
                        local d = straight(a, b, g.x[i], g.y[i])
                        if d <= P.NEAR_MAX then list[#list + 1] = { i, d } end
                    end
                end
            end
        end
        if #list > 0 then break end
    end
    table.sort(list, function(x, y) return x[2] < y[2] end)
    for i = #list, P.NEAR + 1, -1 do list[i] = nil end
    return list
end

----------------------------------------------------------------------
-- Known flight masters
----------------------------------------------------------------------
local taxiCache = {}
P.taxiVersion = 0

function P.FlightYards(from, to)
    local yd = straight(from.a, from.b, to.a, to.b)
    local s = OMQ.Taxi and OMQ.Taxi.Time and OMQ.Taxi:Time(from.id, to.id, yd)
    if not num(s) then return nil end
    return (s + P.FLIGHT_EXTRA) * P.SPEED
end

-- The flight masters a character knows (fix 470): the Forever client reports every flight master of the faction as
-- discovered in C_TaxiMap.GetTaxiNodesForMap, so OMQ learns them where the game is sure, at the flight master: when
-- the flight map opens, the nodes it shows as current or reachable are known (C_TaxiMap.GetAllTaxiNodes, else the
-- old TaxiNodeGetType slots). Kept per character in OMQDB.pathTaxi[guid] = { [node id] = true }; a node once known
-- stays known. Until a flight map was opened, the planner uses no flights.
local function myGuid() local m = OMQ.GetSelf and OMQ:GetSelf(); return m and m.guid end
function P.Known()
    local g = myGuid()
    if not (OMQDB and g) then return nil end
    OMQDB.pathTaxi = OMQDB.pathTaxi or {}
    local k = OMQDB.pathTaxi[g]
    if not k then k = {}; OMQDB.pathTaxi[g] = k end
    return k
end

local KNOWN_STATE = { [0] = true, [1] = true }      -- Enum.FlightPathState Current, Reachable
function P.LearnTaxis()
    local known = P.Known()
    if not known then return 0 end
    local added = 0
    local function add(id)
        if num(id) and not known[id] then known[id] = true; added = added + 1 end
    end
    local mapID = OMQ.Taxi and OMQ.Taxi._TaxiMap and OMQ.Taxi._TaxiMap()
    local list
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and num(mapID) then
        local ok, l = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
        if ok and type(l) == "table" then list = l end
    end
    if list then
        for _, n in ipairs(list) do
            if type(n) == "table" and KNOWN_STATE[n.state] then add(n.nodeID) end
        end
    elseif NumTaxiNodes and TaxiNodeGetType and TaxiNodeName and OMQ.taxiNodeIds then
        local fac = UnitFactionGroup and UnitFactionGroup("player")
        local byName = fac and OMQ.taxiNodeIds[fac] or {}
        for i = 1, (NumTaxiNodes() or 0) do
            local t = TaxiNodeGetType(i)
            if t == "CURRENT" or t == "REACHABLE" then
                local nm = TaxiNodeName(i)
                add(type(nm) == "string" and byName[nm:match("^([^,]+)") or nm])
            end
        end
    end
    if added > 0 then taxiCache = {}; P.taxiVersion = P.taxiVersion + 1 end
    return added
end

-- { {id, a, b, name}, ... } of the flight masters I know on that continent
function P.Taxis(inst)
    local c = taxiCache[inst]
    local now = GetTime()
    if c and now - c.at < 30 then return c.list end
    local list, sig = {}, {}
    local data = OMQ.PathTaxi or {}
    local known = P.Known() or {}
    local ids = {}
    for id in pairs(known) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local d = data[id]
        if d and d[1] == inst and not tostring(d[4]):find("^zz") then
            list[#list + 1] = { id = id, a = d[2], b = d[3], name = d[4] }
            sig[#sig + 1] = id
        end
    end
    for _, t in ipairs(list) do
        t.fly = {}
        for k, u in ipairs(list) do
            if u ~= t then
                local y = P.FlightYards(t, u)
                if y then t.fly[#t.fly + 1] = { k, y } end
            end
        end
    end
    table.sort(sig)
    local s = table.concat(sig, ",")
    if not c or c.sig ~= s then P.taxiVersion = P.taxiVersion + 1 end
    taxiCache[inst] = { at = now, list = list, sig = s }
    return list
end
function P._ResetTaxis() taxiCache = {}; P.taxiVersion = P.taxiVersion + 1 end


----------------------------------------------------------------------
-- Search: the cheapest cost from a place to every anchor (Dijkstra, bounded)
----------------------------------------------------------------------
-- a small binary heap of {cost, node}
local function push(h, c, i)
    local n = #h + 1
    h[n] = { c, i }
    while n > 1 do
        local p = math.floor(n / 2)
        if h[p][1] <= c then break end
        h[p], h[n] = h[n], h[p]
        n = p
    end
end
local function pop(h)
    local top = h[1]
    local n = #h
    h[1] = h[n]; h[n] = nil; n = n - 1
    local i = 1
    while true do
        local l, r, m = 2 * i, 2 * i + 1, i
        if l <= n and h[l][1] < h[m][1] then m = l end
        if r <= n and h[r][1] < h[m][1] then m = r end
        if m == i then break end
        h[i], h[m] = h[m], h[i]
        i = m
    end
    return top
end

P.stats = { searches = 0 }

-- node ids: anchors 1..g.n, flight masters g.n + k
function P.Search(p, bound)
    local g = P.Graph(p.inst)
    if not g then return nil end
    P.stats.searches = P.stats.searches + 1
    local taxis = P.Taxis(p.inst)
    local tnear = {}            -- anchor -> { k, yards } flight masters next to it
    for k, t in ipairs(taxis) do
        if not t.near then t.near = P.Near(g, t.a, t.b) end
        for _, x in ipairs(t.near) do
            local l = tnear[x[1]]
            if not l then l = {}; tnear[x[1]] = l end
            l[#l + 1] = { k, x[2] }
        end
    end
    local dist, prev, flew, heap = {}, {}, {}, {}
    local function reach(i, c, from)
        if c <= bound and (dist[i] == nil or c < dist[i]) then
            dist[i] = c; prev[i] = from; push(heap, c, i)
            flew[i] = from < 0 or (from > 0 and flew[from]) or false
        end
    end
    for _, x in ipairs(P.Near(g, p.a, p.b)) do reach(x[1], x[2], 0) end
    for k, t in ipairs(taxis) do
        local d = straight(p.a, p.b, t.a, t.b)
        if d <= P.NEAR_MAX then reach(g.n + k, d, 0) end
    end
    while #heap > 0 do
        local top = pop(heap)
        local c, i = top[1], top[2]
        if c <= dist[i] then
            if i <= g.n then
                local row = g.e[i]
                if row then
                    for j = 1, #row - 1, 2 do reach(row[j], c + row[j + 1], i) end
                end
                for _, x in ipairs(tnear[i] or {}) do reach(g.n + x[1], c + x[2], i) end
            else
                local t = taxis[i - g.n]
                for _, x in ipairs(t.near) do reach(x[1], c + x[2], i) end
                for _, f in ipairs(t.fly) do reach(g.n + f[1], c + f[2], -i) end   -- negative: flown from i
            end
        end
    end
    return { dist = dist, prev = prev, flew = flew, g = g, taxis = taxis, from = p }
end

-- the end of a search at q: the cost and the anchor (or flight master) it comes from
local function finish(s, q)
    local g = s.g
    local best, last = nil, nil
    if not g then return nil end
    for _, x in ipairs(P.Near(g, q.a, q.b)) do
        local d = s.dist[x[1]]
        if d and (best == nil or d + x[2] < best) then best, last = d + x[2], x[1] end
    end
    for k, t in ipairs(s.taxis) do
        local d = s.dist[g.n + k]
        local r = straight(q.a, q.b, t.a, t.b)
        if d and r <= P.NEAR_MAX and (best == nil or d + r < best) then best, last = d + r, g.n + k end
    end
    return best, last, last and s.flew[last] or false
end

----------------------------------------------------------------------
-- Costs for the planner
----------------------------------------------------------------------
local memo = setmetatable({}, { __mode = "k" })
P._memo = memo

function P.Cost(p, q)
    if not (P.Enabled() and p and q and num(p.a) and num(q.a)) then return nil end
    if p.inst ~= q.inst then return nil end
    local s = straight(p.a, p.b, q.a, q.b)
    if s <= P.DIRECT then return s end
    if not P.Graph(p.inst) then return nil end
    P.Taxis(p.inst)
    local m = memo[p]
    if not m or m.v ~= P.taxiVersion then
        m = { v = P.taxiVersion, s = P.Search(p, P.BOUND), q = setmetatable({}, { __mode = "k" }) }
        memo[p] = m
    end
    local c = m.q[q]
    if c then return c end
    if not m.s then return nil end
    local found, _, flew = finish(m.s, q)
    c = found
    if not c then
        -- beyond the searched yards: a little longer than straight; ground the network does not join: a boat
        local far = s > P.BOUND * 0.8
        c = far and s * 1.25 or (s * P.ISLAND + P.ISLAND_YD)
    end
    if c < s and not flew then c = s end     -- on foot never shorter than straight; a flight can be
    m.q[q] = c
    return c
end

----------------------------------------------------------------------
-- The way for an arrow: one search back from the target (kept while the target stays), so every step of the
-- player only looks at the anchors around him
----------------------------------------------------------------------
local function reverse(g)
    if g.r then return g.r end
    local r = {}
    for i = 1, g.n do
        local row = g.e[i]
        if row then
            for j = 1, #row - 1, 2 do
                local t = r[row[j]]
                if not t then t = {}; r[row[j]] = t end
                t[#t + 1] = i; t[#t + 1] = row[j + 1]
            end
        end
    end
    g.r = r
    return r
end

-- the cheapest cost from every anchor (and flight master) to q; next[i] = the node after i (0: q, negative: fly there)
function P.SearchTo(q, bound)
    local g = P.Graph(q.inst)
    if not g then return nil end
    P.stats.searches = P.stats.searches + 1
    local r = reverse(g)
    local taxis = P.Taxis(q.inst)
    local tnear = {}
    for k, t in ipairs(taxis) do
        if not t.near then t.near = P.Near(g, t.a, t.b) end
        for _, x in ipairs(t.near) do
            local l = tnear[x[1]]
            if not l then l = {}; tnear[x[1]] = l end
            l[#l + 1] = { k, x[2] }
        end
    end
    local flyIn = {}            -- k -> { {from k, yards}, ... }
    for k, t in ipairs(taxis) do
        for _, f in ipairs(t.fly or {}) do
            local l = flyIn[f[1]]
            if not l then l = {}; flyIn[f[1]] = l end
            l[#l + 1] = { k, f[2] }
        end
    end
    local dist, nxt, flew, heap = {}, {}, {}, {}
    local function reach(i, c, to)
        if c <= bound and (dist[i] == nil or c < dist[i]) then
            dist[i] = c; nxt[i] = to; push(heap, c, i)
            flew[i] = to < 0 or (to > 0 and flew[to]) or false
        end
    end
    for _, x in ipairs(P.Near(g, q.a, q.b)) do reach(x[1], x[2], 0) end
    for k, t in ipairs(taxis) do
        local d = straight(q.a, q.b, t.a, t.b)
        if d <= P.NEAR_MAX then reach(g.n + k, d, 0) end
    end
    while #heap > 0 do
        local top = pop(heap)
        local c, i = top[1], top[2]
        if c <= dist[i] then
            if i <= g.n then
                local row = r[i]
                if row then
                    for j = 1, #row - 1, 2 do reach(row[j], c + row[j + 1], i) end
                end
                for _, x in ipairs(tnear[i] or {}) do reach(g.n + x[1], c + x[2], i) end
            else
                local k = i - g.n
                for _, x in ipairs(taxis[k].near) do reach(x[1], c + x[2], i) end
                for _, f in ipairs(flyIn[k] or {}) do reach(g.n + f[1], c + f[2], -i) end   -- fly from there to i
            end
        end
    end
    return { dist = dist, nxt = nxt, flew = flew, g = g, taxis = taxis, to = q }
end

-- the anchors the arrow may join (fix 485): ALL anchors of my tile. P.Near keeps only the 5 nearest: when the
-- cheapest join was the 6th nearest, a step that brought another anchor nearer dropped it, the way jumped up by
-- hundreds of yards for a few steps and the arrow turned back. The list is found again after JOIN_MOVE yards, the
-- yards to the anchors every time. Without anchors in my tile: P.Near as before.
function P.JoinNear(g, p, c)
    local ids
    if c and c.jl and c.jinst == p.inst and straight(c.ja, c.jb, p.a, p.b) < P.JOIN_MOVE then
        ids = c.jl
    else
        ids = {}
        for _, i in ipairs(g.tiles[tileKey(p.a, p.b)] or {}) do
            if straight(p.a, p.b, g.x[i], g.y[i]) <= P.NEAR_MAX then ids[#ids + 1] = i end
        end
        if #ids == 0 then
            for _, x in ipairs(P.Near(g, p.a, p.b)) do ids[#ids + 1] = x[1] end
        end
        if c then c.jl, c.ja, c.jb, c.jinst = ids, p.a, p.b, p.inst end
    end
    local list = {}
    for k, i in ipairs(ids) do list[k] = { i, straight(p.a, p.b, g.x[i], g.y[i]) } end
    return list
end

local wayCache = {}
local function coarseWay(p, q)
    if not (P.Enabled() and p and q and num(p.a) and num(q.a)) or p.inst ~= q.inst then return nil end
    local s = straight(p.a, p.b, q.a, q.b)
    local plain = { cost = s, straight = s, a = q.a, b = q.b, via = false }
    if s <= P.DIRECT or not P.Graph(p.inst) then return plain end
    P.Taxis(p.inst)
    -- the searches of the last few targets (the small Quest Run arrow and the main arrow each have one), found by
    -- the target's place: a target table made anew every time (a pin) finds its search again
    local c = nil
    for _, x in ipairs(wayCache) do
        if x.v == P.taxiVersion and x.inst == q.inst and math.abs(x.qa - q.a) < 5 and math.abs(x.qb - q.b) < 5 then c = x; break end
    end
    if not c then
        c = { qa = q.a, qb = q.b, inst = q.inst, v = P.taxiVersion, s = P.SearchTo(q, P.WAY_BOUND) }
        table.insert(wayCache, 1, c)
        wayCache[P.WAY_KEEP + 1] = nil
    end
    local srch = c.s
    if not srch then return plain end
    local g = srch.g
    -- where I join the way
    local best, first = nil, nil
    local keep = nil                                -- the way I joined last time, if it is still near me
    for _, x in ipairs(P.JoinNear(g, p, c)) do
        local d = srch.dist[x[1]]
        if d and (best == nil or d + x[2] < best) then best, first = d + x[2], x[1] end
        if d and x[1] == c.join then keep = d + x[2] end
    end
    for k, t in ipairs(srch.taxis) do
        local d = srch.dist[g.n + k]
        local r = straight(p.a, p.b, t.a, t.b)
        if d and r <= P.NEAR_MAX and (best == nil or d + r < best) then best, first = d + r, g.n + k end
        if d and r <= P.NEAR_MAX and g.n + k == c.join then keep = d + r end
    end
    if not best then return plain end
    -- two joins that cost about the same: keep the last one, else the arrow flips between them step by step (477)
    if keep and first ~= c.join and keep <= best * P.JOIN_KEEP + P.JOIN_KEEP_YD then best, first = keep, c.join end
    c.join = first
    local flew = srch.flew[first]
    if not flew and best <= s * P.SLACK + P.SLACK_YD then return { cost = math.max(best, s), straight = s, a = q.a, b = q.b, via = false } end
    local function xy(n)
        if n <= g.n then return g.x[n], g.y[n] end
        local t = srch.taxis[n - g.n]
        return t.a, t.b
    end
    -- head for the farthest node the way reaches almost straight; never past a flight master I fly from
    local way = { cost = flew and best or math.max(best, s), straight = s, via = true, srch = srch, first = first, best = best }
    local pick, n, steps = nil, first, 0
    while n and n > 0 and steps < 2000 do
        steps = steps + 1
        local a, b = xy(n)
        local done = best - srch.dist[n]           -- the cost from me to this node along the way
        local lim = straight(p.a, p.b, a, b) * P.SLACK + P.SLACK_YD
        if n == c.pick then lim = lim * P.JOIN_KEEP + P.JOIN_KEEP_YD end   -- the last pick is kept a little longer (477)
        if done <= lim then pick = n end
        local nx = srch.nxt[n]
        if nx and nx < 0 then
            if not pick or pick == n then
                pick = n
                way.flight = srch.taxis[n - g.n] and srch.taxis[n - g.n].name
            end
            break
        end
        n = nx
    end
    -- a way point I am at or just walked past (the arrow would turn round): head for the one after it (fix 474)
    pick = pick or first
    c.pick = pick
    -- also one close behind me: going there means turning back on the way to the one after it (477)
    local hn = pick                                 -- the node I head for, nil for the target itself
    local skipped = nil                             -- the last node skipped
    for _ = 1, 3 do
        if way.flight or not hn then break end
        local a, b = xy(hn)
        local nx = srch.nxt[hn]
        if nx == 0 then nx = nil end                -- 0: from there straight to the target
        if nx and nx < 0 then break end
        local na, nb
        if nx then na, nb = xy(nx) else na, nb = q.a, q.b end
        local d = straight(p.a, p.b, a, b)
        -- behind me, and the walk from it to the next one is about straight: I can cut across
        -- (past it: ahead of it toward the next one, and not farther to the side than ahead, nor than CARROT)
        local seg0 = straight(a, b, na, nb)
        local behind = false
        if seg0 > 0.01 then
            local ua, ub = (na - a) / seg0, (nb - b) / seg0
            local along = (p.a - a) * ua + (p.b - b) * ub
            local side = math.abs((p.a - a) * ub - (p.b - b) * ua)
            behind = along > 0 and side <= math.max(along, P.CARROT)
        end
        if behind and nx then
            local seg = straight(a, b, na, nb)
            behind = srch.dist[hn] - srch.dist[nx] <= seg * P.CUT + P.CUT_YD
        end
        if not (d < P.PASSED or behind) then break end
        skipped = hn
        hn = nx
    end
    if hn then way.a, way.b = xy(hn) else way.a, way.b = q.a, q.b end
    -- the stretch of the way the gliding point runs on (decision 477): from the node skipped last to the one I head
    -- for, else from the one I head for to the one after it; none at a flight
    -- (only a stretch walked about straight: a winding walk between two anchors is no line to glide on)
    local function cost(n) if n then return srch.dist[n] end return 0 end
    local function straightOn(n1, n2, a1, b1, a2, b2)
        return cost(n1) - cost(n2) <= straight(a1, b1, a2, b2) * P.CUT + P.CUT_YD
    end
    if not way.flight then
        if skipped then
            local a1, b1 = xy(skipped)
            if straightOn(skipped, hn, a1, b1, way.a, way.b) then
                way.ga, way.gb, way.na, way.nb = a1, b1, way.a, way.b
            end
        elseif hn then
            local nx = srch.nxt[hn]
            if nx == 0 then nx = nil end
            if not (nx and nx < 0) then
                local a2, b2
                if nx then a2, b2 = xy(nx) else a2, b2 = q.a, q.b end
                if straightOn(hn, nx, way.a, way.b, a2, b2) then
                    way.ga, way.gb, way.na, way.nb = way.a, way.b, a2, b2
                end
            end
        end
    end
    return way
end
----------------------------------------------------------------------
-- Fine steering on the 8-yard raster (decision 472)
----------------------------------------------------------------------
-- Data/PathRaster.lua holds the walkable ground in cells of 8.33 yards: per cell which of its 8 neighbours it walks
-- to. The point an arrow heads for (the next point of the way, or the target) is checked in the raster: when the
-- line to it crosses a wall, a cliff or a lake, a small search finds the way around in the cells near me and the
-- arrow heads for the farthest cell of that way I can walk to straight. Only the first floor of a cell is known, so
-- where my cell has more floors (a bridge, a house, a cave, a city under the ground) the arrow stays as it was.
local CELL = TILE / 64
P.CELL = CELL
P.LOOK = 250                    -- yards ahead the fine way is searched
P.FINE_NODES = 4000             -- cells a fine search looks at at most
P.FINE_MARGIN = 24              -- cells around me and the point the search may use
P.FINE_GOAL = 3                 -- cells from a point that is not walkable ground that count as there
P.FINE_KEEP = 64                -- unpacked tiles kept (a route search crosses many, 585)
P.FINE_MOVE, P.FINE_AGE = 5, 2  -- the fine way is found again after these yards moved or seconds
P.FINE_HOLD = 4                 -- seconds a way round is kept against a clear line while I am on it (477)
P.FINE_NEAR = 10                -- or at once this close to the point it heads for
P.SWIM = 1.5                    -- a swum cell costs this much more
P.EDGE = 0.7                    -- a cell next to a wall costs this much more: ways keep off walls, corners get round
P.FINE_SLACK_YD = 15            -- a way round this little longer (x SLACK) is not steered
local DR = { -1, 1, 0, 0, -1, -1, 1, 1 }    -- N, S, W, E, NW, NE, SW, SE
local DC = { 0, 0, -1, 1, -1, 1, -1, 1 }
local BIT = { 1, 2, 4, 8, 16, 32, 64, 128 }
local DIR = {}                              -- (dr + 1) * 3 + dc + 2 -> direction
for d = 1, 8 do DIR[(DR[d] + 1) * 3 + DC[d] + 2] = d end
local SQ2 = math.sqrt(2)
local SWUM, FLOORS = 256, 512
local B64 = {}
do
    local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do B64[abc:byte(i)] = i - 1 end
end
local function walks(v, d) return math.floor(v / BIT[d]) % 2 == 1 end
local function rc(a, b) return math.floor((ORIGIN - a) / CELL), math.floor((ORIGIN - b) / CELL) end
local function center(r, c) return ORIGIN - (r + 0.5) * CELL, ORIGIN - (c + 0.5) * CELL end
P.RC, P.Center = rc, center

local rasterTiles, rasterOrder = {}, {}
local function unpackTile(str)
    local t, n = {}, 0
    for k = 1, #str - 2, 3 do
        local x, y, z = str:byte(k, k + 2)
        local v = B64[x] * 64 + B64[y]
        for _ = 0, B64[z] do n = n + 1; t[n] = v end
    end
    return t
end
-- the 4096 cells of a tile (rows from the north), nil without data
function P.RasterTile(inst, key)
    local id = inst * 16384 + key
    local t = rasterTiles[id]
    if t ~= nil then return t or nil end
    local r = OMQ.PathRaster and OMQ.PathRaster[inst]
    local str = r and r[key]
    t = str and unpackTile(str) or false
    rasterTiles[id] = t
    rasterOrder[#rasterOrder + 1] = id
    if #rasterOrder > P.FINE_KEEP then rasterTiles[table.remove(rasterOrder, 1)] = nil end
    return t or nil
end
-- a cell's value: its walk bits, + 256 swum, + 512 more floors; 0 for no walkable ground or no data
function P.CellAt(inst, r, c)
    local t = P.RasterTile(inst, math.floor(r / 64) * 128 + math.floor(c / 64))
    return t and t[(r % 64) * 64 + c % 64 + 1] or 0
end
local cellAt = P.CellAt

-- can I walk straight from cell (r0, c0) to cell (r1, c1)? (the cells of the line, step by step)
-- strict (585): a diagonal step also needs ground in both cells beside it (the data lets a walk cut the corner of a
-- rock; a player walking the straight line then brushes it)
function P.Sight(inst, r0, c0, r1, c1, strict)
    local dx, dy = math.abs(c1 - c0), math.abs(r1 - r0)
    local sc, sr = c1 > c0 and 1 or -1, r1 > r0 and 1 or -1
    local err = dx - dy
    local r, c = r0, c0
    local v = cellAt(inst, r, c)
    while r ~= r1 or c ~= c1 do
        local e2, mr, mc = 2 * err, 0, 0
        if e2 > -dy then err = err - dy; mc = sc end
        if e2 < dx then err = err + dx; mr = sr end
        if not walks(v, DIR[(mr + 1) * 3 + mc + 2]) then return false end
        if strict and mr ~= 0 and mc ~= 0 and (cellAt(inst, r + mr, c) == 0 or cellAt(inst, r, c + mc) == 0) then return false end
        r, c = r + mr, c + mc
        v = cellAt(inst, r, c)
    end
    return true
end

-- the cheapest walk from cell (r0, c0) to (r1, c1) in a box around both (A*, bounded): the cells { {r, c}, ... }
-- from me on, its yards, and whether it reached the point (else it ends at the cell closest to it)
function P.FineSearch(inst, r0, c0, r1, c1)
    local m = P.FINE_MARGIN
    local rmin, rmax = math.min(r0, r1) - m, math.max(r0, r1) + m
    local cmin, cmax = math.min(c0, c1) - m, math.max(c0, c1) + m
    local W = cmax - cmin + 1
    local open = cellAt(inst, r1, c1) ~= 0
    local function h(r, c)
        local a, b = math.abs(r - r1), math.abs(c - c1)
        if a > b then return a + (SQ2 - 1) * b end
        return b + (SQ2 - 1) * a
    end
    local s = (r0 - rmin) * W + (c0 - cmin)
    local g, prev, done = { [s] = 0 }, {}, {}
    local heap = {}
    push(heap, h(r0, c0), s)
    local count, found, closest, closestH = 0, nil, s, h(r0, c0)
    while heap[1] and count < P.FINE_NODES do
        local i = pop(heap)[2]
        if not done[i] then
            done[i] = true
            count = count + 1
            local r, c = rmin + math.floor(i / W), cmin + i % W
            local hi = h(r, c)
            if hi < closestH then closest, closestH = i, hi end
            if (r == r1 and c == c1) or (not open and math.max(math.abs(r - r1), math.abs(c - c1)) <= P.FINE_GOAL) then
                found = i
                break
            end
            local v, gi = cellAt(inst, r, c), g[i]
            for d = 1, 8 do
                if walks(v, d) then
                    local nr, nc = r + DR[d], c + DC[d]
                    if nr >= rmin and nr <= rmax and nc >= cmin and nc <= cmax then
                        local j = (nr - rmin) * W + (nc - cmin)
                        if not done[j] then
                            local step = d > 4 and SQ2 or 1
                            local nv = cellAt(inst, nr, nc)
                            if nv % FLOORS >= SWUM then step = step * P.SWIM end
                            if nv % SWUM ~= 255 then step = step + P.EDGE end   -- next to a wall: keep off it (477)
                            local ng = gi + step
                            if g[j] == nil or ng < g[j] then
                                g[j], prev[j] = ng, i
                                push(heap, ng + h(nr, nc), j)
                            end
                        end
                    end
                end
            end
        end
    end
    P.stats.fine = (P.stats.fine or 0) + 1
    P.stats.fineCells = count
    local last = found or closest
    if last == s then return nil end
    local back, i = {}, last
    while i do
        back[#back + 1] = { rmin + math.floor(i / W), cmin + i % W }
        i = prev[i]
    end
    local path = {}
    for k = #back, 1, -1 do path[#path + 1] = back[k] end
    return path, g[last] * CELL, found ~= nil
end

-- the point to head for from (pa, pb) toward (ha, hb): { a, b, clear (the line is walkable), yards, reached }, nil
-- when the raster cannot tell
function P.Fine(inst, pa, pb, ha, hb)
    if not (OMQ.PathRaster and OMQ.PathRaster[inst]) then return nil end
    local d = straight(pa, pb, ha, hb)
    local ta, tb = ha, hb
    if d > P.LOOK then
        local f = P.LOOK / d
        ta, tb = pa + (ha - pa) * f, pb + (hb - pb) * f
    end
    local r0, c0 = rc(pa, pb)
    local r1, c1 = rc(ta, tb)
    local v0 = cellAt(inst, r0, c0)
    if v0 == 0 or v0 >= FLOORS then return nil end
    if (r0 == r1 and c0 == c1) or P.Sight(inst, r0, c0, r1, c1) then return { a = ha, b = hb, clear = true } end
    local path, yards, reached = P.FineSearch(inst, r0, c0, r1, c1)
    if not path then return nil end
    -- a tree, a rock, a fence: a way round that is hardly longer; the gliding point keeps the arrow almost straight
    -- (477; before, the arrow then pointed straight through the corner)
    local minor = reached and yards <= straight(pa, pb, ta, tb) * P.SLACK + P.FINE_SLACK_YD
    -- the farthest cell of the way I walk to straight
    local pick = path[2] or path[1]
    for k = 3, #path do
        if not P.Sight(inst, r0, c0, path[k][1], path[k][2]) then break end
        pick = path[k]
    end
    local a, b = center(pick[1], pick[2])
    -- right at the corner: head for the way past it, not for the cell I stand on (fix 474)
    if straight(pa, pb, a, b) < P.FINE_NEAR then
        for k = 2, #path do
            local ka, kb = center(path[k][1], path[k][2])
            a, b = ka, kb
            if straight(pa, pb, ka, kb) >= P.FINE_NEAR then break end
        end
    end
    return { a = a, b = b, clear = false, yards = yards, reached = reached and d <= P.LOOK, path = path, minor = minor }
end

-- a wide line of sight between two places (477): three lines, the middle one and one on each side a third of a
-- cell off, so that a straight walk does not clip the corner of a wall
function P.SightWide(inst, pa, pb, qa, qb, wide, strict)
    local d = straight(pa, pb, qa, qb)
    if d < 0.01 then return true end
    wide = wide or 0.35
    local ua, ub = -(qb - pb) / d * CELL * wide, (qa - pa) / d * CELL * wide
    for _, o in ipairs({ 0, 1, -1 }) do
        local r0, c0 = rc(pa + ua * o, pb + ub * o)
        local r1, c1 = rc(qa + ua * o, qb + ub * o)
        if o ~= 0 and cellAt(inst, r0, c0) == 0 then r0, c0 = rc(pa, pb) end   -- I stand right at a wall
        if not P.Sight(inst, r0, c0, r1, c1, strict) then return false end
    end
    return true
end

-- am I on (within 2 cells of) a fine way, before its last cell?
function P.OnPath(pa, pb, path)
    local r0, c0 = rc(pa, pb)
    for k = 1, #path - 1 do
        if math.max(math.abs(path[k][1] - r0), math.abs(path[k][2] - c0)) <= 2 then return true end
    end
    return false
end

-- the gliding point (decision 477): the point CARROT_FINE yards ahead of me on the fine way, as far as I see it
function P.FineCarrot(inst, pa, pb, path)
    if not path or #path < 2 then return nil end
    local r0, c0 = rc(pa, pb)
    local bi, bd = 1, nil
    for k = 1, #path do
        local dr, dc = path[k][1] - r0, path[k][2] - c0
        local d = dr * dr + dc * dc
        if not bd or d < bd then bi, bd = k, d end
    end
    -- the way from me: me, then the cell centres after the nearest cell
    local pts = { { pa, pb } }
    for k = bi + 1, #path do
        local a, b = center(path[k][1], path[k][2])
        pts[#pts + 1] = { a, b }
    end
    if #pts < 2 then return nil end
    local function along(len)
        for k = 2, #pts do
            local x, y = pts[k - 1], pts[k]
            local s = straight(x[1], x[2], y[1], y[2])
            if s >= len then
                local f = s > 0 and len / s or 0
                return x[1] + (y[1] - x[1]) * f, x[2] + (y[2] - x[2]) * f
            end
            len = len - s
        end
        return pts[#pts][1], pts[#pts][2]
    end
    local len = P.CARROT_FINE
    while len >= CELL do
        local a, b = along(len)
        if P.SightWide(inst, pa, pb, a, b) then return a, b end
        len = len - CELL / 2
    end
    return pts[2][1], pts[2][2]
end

-- the gliding point on the network's way: near the way point the arrow already turns toward the one after it
function P.Carrot(p, w)
    if not (w.na and w.ga) then return w end
    local seg = straight(w.ga, w.gb, w.na, w.nb)
    if seg < 1 then return w end
    local ua, ub = (w.na - w.ga) / seg, (w.nb - w.gb) / seg
    local along = (p.a - w.ga) * ua + (p.b - w.gb) * ub
    local L = P.CARROT
    -- as far along the stretch as I am short of CARROT yards from its start, plus how far along it I am already:
    -- the point leaves the start gently and then stays CARROT yards ahead of me (all of it changes smoothly)
    -- (along counts fully up to CARROT yards to the side of the stretch, not at all from twice that)
    local side = math.abs((p.a - w.ga) * ub - (p.b - w.gb) * ua)
    local near = math.max(0, math.min(1, (2 * L - side) / L))
    -- (fix 585: before, the lead was L minus my yards from the start, so 40 yd along the stretch it was gone and the
    -- point lay beside me: the arrow pointed sideways or back. Now the lead stays L while I am on the stretch.)
    local lead = math.max(0, L - straight(p.a, p.b, w.ga, w.gb))
    if along > 0 then lead = math.max(lead, L * near) end
    local t = math.max(0, along) * near + lead
    if t <= 0 then return w end                      -- still far before the stretch
    t = math.min(t, seg)
    w.a, w.b, w.glide = w.ga + ua * t, w.gb + ub * t, true
    return w
end

-- the arrow's heading of a way, steered on the raster; found again after FINE_MOVE yards or FINE_AGE seconds
local fineCache = {}
local function steer(p, w, ka, kb)
    local ha, hb = w.a, w.b
    ka, kb = ka or ha, kb or hb                     -- the cache key: the way point, not the gliding point (477)
    local t = GetTime and GetTime() or 0
    local c = nil
    for _, x in ipairs(fineCache) do
        if x.inst == p.inst and math.abs(x.ha - ka) < 5 and math.abs(x.hb - kb) < 5 then c = x; break end
    end
    -- found again when I walked on or waited, and at once when I reach the point it heads for or walk past it
    -- (it would turn round, fix 474)
    local stale = not c or t - c.t > P.FINE_AGE or t < c.t or straight(c.pa, c.pb, p.a, p.b) > P.FINE_MOVE
    if not stale and c.f and not c.f.clear then
        local f = c.f
        stale = t - c.t > 0.25 and (straight(p.a, p.b, f.a, f.b) < P.FINE_NEAR
            or (f.a - p.a) * (f.a - c.pa) + (f.b - p.b) * (f.b - c.pb) <= 0)
    end
    if stale then
        local ok, f = pcall(P.Fine, p.inst, p.a, p.b, ha, hb)
        if not c then
            c = { inst = p.inst, ha = ka, hb = kb }
            table.insert(fineCache, 1, c)
            fineCache[P.WAY_KEEP + 1] = nil
        end
        f = ok and f or false
        -- a fine way round something, then a clear line: keep the way round a little longer while I am still on it
        -- (at the edge of a wall the line flips between clear and not, the arrow with it, 477)
        local old = c.f
        -- (also when the raster cannot tell for a moment: my cell has more floors or no ground, fix 485)
        if (not f or f.clear) and old and not old.clear and old.path and t - (c.found or 0) < P.FINE_HOLD
            and P.OnPath(p.a, p.b, old.path) then
            f = old
        elseif f and not f.clear then
            c.found = t
        end
        c.pa, c.pb, c.t, c.f = p.a, p.b, t, f
    end
    local f = c.f
    if not f or f.clear then return w end
    if not w.via and f.reached then w.cost = math.max(w.cost, f.yards) end
    w.a, w.b, w.via, w.fine = f.a, f.b, true, true
    local ok, a, b = pcall(P.FineCarrot, p.inst, p.a, p.b, f.path)
    if ok and a then w.a, w.b = a, b end
    return w
end

----------------------------------------------------------------------
-- Routes on the raster (decision 585)
----------------------------------------------------------------------
-- The whole walk from me to the target is searched once on the 8-yard raster (A*, a little greedy so that it looks
-- at few cells) and then KEPT: the arrow follows it, a point CARROT_ROUTE yards ahead on it. Before, the way was
-- found again every step from the coarse network (anchors on the tile borders) and a fine look 250 yards ahead,
-- and the two disagreed at cliffs, tile borders and towns with more floors: the arrow swung to and fro or led into
-- a dead end. The search runs in small slices (ROUTE_MS per frame), so nothing stutters; until it is done (mostly
-- well under a second) the arrow uses the old way. A new search starts only when I leave the route by ROUTE_OFF
-- yards or the target moves. Far targets: the route goes to a point about ROUTE_LEG yards along the coarse network
-- and the next part is searched before I get there. A flight: the route goes to the flight master.
P.ROUTES = true
P.ROUTE_W = 1.4                 -- greed of the search (1: the shortest walk, more: fewer cells looked at)
P.ROUTE_NODES = 120000          -- cells a search looks at at most
P.ROUTE_MS = 3                  -- milliseconds of search per slice
P.ROUTE_SLICE = 400             -- cells per slice without a clock
P.ROUTE_FIRST_MS, P.ROUTE_FIRST_SLICE = 8, 2000   -- the first slice of a search, right when it starts
P.ROUTE_OFF = 4                 -- cells (about 33 yd) off the route: search again
P.ROUTE_FAR = 1500              -- yards: farther targets get a part of the way (a leg) at a time
P.ROUTE_LEG = 1200              -- yards along the coarse network a leg goes
P.ROUTE_RENEW = 300             -- yards before the end of a leg the next one is searched
P.ROUTE_STALL, P.ROUTE_STALL_YD = 3, 10   -- seconds within these yards (stuck or pacing) on the route: searched once again from here
P.ROUTE_RETRY = 8               -- seconds before a failed search is tried again (or 50 yd moved)
P.ROUTE_GOAL = 3                -- cells round a target that is not walkable ground that count as there
P.ROUTE_NEAR_YD = 40            -- a search that ends this close to its goal is good enough
P.ROUTE_WIDE = 0.6               -- the line to that point keeps this many cells off walls on both sides
P.CARROT_ROUTE = 35             -- the arrow heads for a point this far ahead on the route

local function clockMs() return debugprofilestop and debugprofilestop() or nil end
local function cellId(r, c) return r * 16384 + c end

-- a new search from p to the goal (ga, gb): the state of an A* that runs in slices
local function newSearch(inst, pa, pb, ga, gb)
    local r0, c0 = rc(pa, pb)
    local r1, c1 = rc(ga, gb)
    local function h(r, c)
        local a, b = math.abs(r - r1), math.abs(c - c1)
        if a > b then return (a + (SQ2 - 1) * b) * P.ROUTE_W end
        return (b + (SQ2 - 1) * a) * P.ROUTE_W
    end
    local s = cellId(r0, c0)
    local st = { inst = inst, r0 = r0, c0 = c0, r1 = r1, c1 = c1, h = h, g = { [s] = 0 }, prev = {}, done = {},
        heap = {}, count = 0, closest = s, closestH = h(r0, c0), open = cellAt(inst, r1, c1) ~= 0, start = s,
        ga = ga, gb = gb, pa = pa, pb = pb }
    push(st.heap, h(r0, c0), s)
    return st
end

-- run a search for a while: true when it has ended (found or given up)
local function stepSearch(st, budgetMs, slice)
    if st.ended then return true end
    local inst, heap, g, prev, done, h = st.inst, st.heap, st.g, st.prev, st.done, st.h
    local r1, c1, open = st.r1, st.c1, st.open
    local t0 = clockMs()
    local n = 0
    while heap[1] do
        if st.count >= P.ROUTE_NODES then break end
        n = n + 1
        if n % 100 == 0 then
            if t0 then
                if clockMs() - t0 >= (budgetMs or P.ROUTE_MS) then return false end
            elseif n >= (slice or P.ROUTE_SLICE) then
                return false
            end
        end
        local i = pop(heap)[2]
        if not done[i] then
            done[i] = true
            st.count = st.count + 1
            local r = math.floor(i / 16384)
            local c = i - r * 16384
            local hi = h(r, c)
            if hi < st.closestH then st.closest, st.closestH = i, hi end
            if (r == r1 and c == c1) or (not open and math.max(math.abs(r - r1), math.abs(c - c1)) <= P.ROUTE_GOAL) then
                st.found = i
                break
            end
            local v, gi = cellAt(inst, r, c), g[i]
            -- the walks of the first floor (the ground itself) also in a cell with more floors (a bridge, a roof, a
            -- cave above); a cell without data (only where I stand): to any neighbour with ground
            local free = v == 0
            for d = 1, 8 do
                local nr, nc = r + DR[d], c + DC[d]
                local nv = cellAt(inst, nr, nc)
                -- (a diagonal step only with ground on both sides: no corner of a rock cut, see P.Sight strict)
                if nv ~= 0 and (free or walks(v, d))
                    and (d <= 4 or (cellAt(inst, nr, c) ~= 0 and cellAt(inst, r, nc) ~= 0)) then
                    local j = cellId(nr, nc)
                    if not done[j] then
                        local step = d > 4 and SQ2 or 1
                        if nv % FLOORS >= SWUM then step = step * P.SWIM end
                        if nv % SWUM ~= 255 and nv < FLOORS then step = step + P.EDGE end
                        local ng = gi + step
                        if g[j] == nil or ng < g[j] then
                            g[j], prev[j] = ng, i
                            push(heap, ng + h(nr, nc), j)
                        end
                    end
                end
            end
        end
    end
    st.ended = true
    P.stats.routes = (P.stats.routes or 0) + 1
    P.stats.routeCells = st.count
    return true
end
P._NewSearch, P._StepSearch = newSearch, stepSearch

-- the route a finished search found: { cells = { {r, c}, ... }, cum = yards along it, ... }, nil when it failed
local function routeOf(st)
    local last = st.found
    if not last then
        -- not reached: good enough when it ended close to the goal (a target in a house the raster does not know)
        local r = math.floor(st.closest / 16384)
        local ca, cb = center(r, st.closest - r * 16384)
        if straight(ca, cb, st.ga, st.gb) <= P.ROUTE_NEAR_YD then last = st.closest end
    end
    if not last then return nil end
    local back, i = {}, last
    while i do
        local r = math.floor(i / 16384)
        back[#back + 1] = { r, i - r * 16384 }
        i = st.prev[i]
    end
    local cells, cum = {}, {}
    for k = #back, 1, -1 do cells[#cells + 1] = back[k] end
    cum[1] = 0
    for k = 2, #cells do
        local dr, dc = math.abs(cells[k][1] - cells[k - 1][1]), math.abs(cells[k][2] - cells[k - 1][2])
        cum[k] = cum[k - 1] + ((dr + dc == 2) and SQ2 or 1) * CELL
    end
    return { cells = cells, cum = cum, k = 1, ga = st.ga, gb = st.gb }
end
P._RouteOf = routeOf

-- where I am on the route: the index of the nearest cell near the last one, and whether I left it
local function progress(rt, pa, pb)
    local r0, c0 = rc(pa, pb)
    local cells = rt.cells
    local lo, hi = math.max(1, rt.k - 10), math.min(#cells, rt.k + 120)
    local bk, bd = rt.k, nil
    for k = lo, hi do
        local dr, dc = cells[k][1] - r0, cells[k][2] - c0
        local d = dr * dr + dc * dc
        if not bd or d < bd or (d == bd and k > bk) then bk, bd = k, d end
    end
    rt.k = bk
    return bk, math.sqrt(bd or 0) > P.ROUTE_OFF
end

-- the point to head for: CARROT_ROUTE yards ahead of my place on the route, as far as I see it
local function routeCarrot(inst, rt, pa, pb)
    local cells, cum, k = rt.cells, rt.cum, rt.k
    local function at(len)
        local want = cum[k] + len
        for j = k + 1, #cells do
            if cum[j] >= want then return center(cells[j][1], cells[j][2]) end
        end
        return nil
    end
    local len = P.CARROT_ROUTE
    while len >= CELL do
        local a, b = at(len)
        if not a then
            -- the end of the route is closer than that: its goal, when I see it
            if P.SightWide(inst, pa, pb, rt.ga, rt.gb, P.ROUTE_WIDE, true) then return rt.ga, rt.gb end
        elseif P.SightWide(inst, pa, pb, a, b, P.ROUTE_WIDE, true) then
            return a, b
        end
        len = len - CELL / 2
    end
    -- right at a corner: the farthest of the next cells my own cell sees, else back onto the route's cell next to me
    local r0, c0 = rc(pa, pb)
    for j = math.min(#cells, k + 8), k + 1, -1 do
        if P.Sight(inst, r0, c0, cells[j][1], cells[j][2], true) then return center(cells[j][1], cells[j][2]) end
    end
    if r0 ~= cells[k][1] or c0 ~= cells[k][2] then return center(cells[k][1], cells[k][2]) end
    local j = math.min(#cells, k + 1)
    return center(cells[j][1], cells[j][2])
end

-- the goal of a new route from p for target q, with the coarse way w: { a, b, tail (yards from the goal on to the
-- target), leg, flight }
local function goalOf(p, q, w)
    if w and w.flight then
        local fy = straight(p.a, p.b, w.a, w.b)
        return { a = w.a, b = w.b, tail = math.max(0, (w.cost or 0) - fy), flight = w.flight }
    end
    local s = straight(p.a, p.b, q.a, q.b)
    if s > P.ROUTE_FAR and w and w.srch and w.first and w.best then
        local srch, g = w.srch, w.srch.g
        local n, steps = w.first, 0
        while n and n > 0 and steps < 2000 do
            steps = steps + 1
            local nx = srch.nxt[n]
            if w.best - srch.dist[n] >= P.ROUTE_LEG or not nx or nx <= 0 then break end
            n = nx
        end
        if n and n > 0 and srch.dist[n] and srch.dist[n] > P.ROUTE_RENEW then
            local a, b
            if n <= g.n then a, b = g.x[n], g.y[n] else local t = srch.taxis[n - g.n]; a, b = t.a, t.b end
            return { a = a, b = b, tail = srch.dist[n], leg = true }
        end
    end
    return { a = q.a, b = q.b, tail = 0 }
end
P._GoalOf = goalOf

local routes = {}               -- the routes of the last few targets, found by the target's place
local pending = {}              -- searches still running: stepped by the driver below
P._routes = routes

local function routeFor(q)
    for _, x in ipairs(routes) do
        if x.inst == q.inst and math.abs(x.qa - q.a) < 5 and math.abs(x.qb - q.b) < 5 then return x end
    end
    local x = { qa = q.a, qb = q.b, inst = q.inst }
    table.insert(routes, 1, x)
    local old = routes[P.WAY_KEEP + 1]
    routes[P.WAY_KEEP + 1] = nil
    if old then old.search = nil end
    return x
end

local function startSearch(x, p, q, w)
    local goal = goalOf(p, q, w)
    local st = newSearch(p.inst, p.a, p.b, goal.a, goal.b)
    st.goal = goal
    x.search = st
    x.tries = { a = p.a, b = p.b, t = GetTime and GetTime() or 0 }
    pending[#pending + 1] = x
    -- a short search (most are: a few hundred cells) ends right here, so the arrow goes from route to route without
    -- showing the old way (and its other yards) in between
    stepSearch(st, P.ROUTE_FIRST_MS, P.ROUTE_FIRST_SLICE)
end

-- a search has ended: its route replaces the old one, or the target gets no route for a while
local function adopt(x)
    local st = x.search
    x.search = nil
    local rt = routeOf(st)
    if not rt then x.failed = true; return end
    x.failed = nil
    rt.tail, rt.leg, rt.flight = st.goal.tail, st.goal.leg, st.goal.flight
    x.cur = rt
end

-- the way for an arrow along the kept route, nil while there is none (the arrow then uses the old way)
function P.RouteWay(p, q, w)
    if not (P.ROUTES and OMQ.PathRaster and OMQ.PathRaster[p.inst]) then return nil end
    local x = routeFor(q)
    if x.search and stepSearch(x.search, 1) then adopt(x) end
    local now = GetTime and GetTime() or 0
    local rt = x.cur
    if rt then
        local k, off = progress(rt, p.a, p.b)
        if off then
            x.cur, rt = nil, nil
        elseif rt.leg and not x.search and rt.cum[#rt.cells] - rt.cum[k] < P.ROUTE_RENEW then
            startSearch(x, p, q, w)             -- the next leg, while I walk on this one
        elseif not x.sa or straight(x.sa, x.sb, p.a, p.b) > P.ROUTE_STALL_YD or now < x.st then
            x.sa, x.sb, x.st, x.stalled = p.a, p.b, now, nil
        elseif now - x.st > P.ROUTE_STALL and not x.stalled and not x.search then
            -- I stand still next to the route (a wall the route slipped past, a ledge): once a route from right here
            x.stalled = true
            startSearch(x, p, q, w)
        end
    end
    if not rt then
        if not x.search then
            local tr = x.tries
            local again = not x.failed or not tr or now - tr.t > P.ROUTE_RETRY or now < tr.t
                or straight(tr.a, tr.b, p.a, p.b) > 50
            if again then startSearch(x, p, q, w) end
            if x.search and x.search.ended then adopt(x) end
            rt = x.cur
            if rt then progress(rt, p.a, p.b) end
        end
        if not rt then return nil end
    end
    local a, b = routeCarrot(p.inst, rt, p.a, p.b)
    local k = rt.k
    local mine = straight(p.a, p.b, center(rt.cells[k][1], rt.cells[k][2]))
    local s = straight(p.a, p.b, q.a, q.b)
    local left = rt.cum[#rt.cells] - rt.cum[k] + mine
    if not rt.flight and not rt.leg then left = left + straight(rt.ga, rt.gb, q.a, q.b) end
    local cost = left + (rt.tail or 0)
    if not rt.flight then cost = math.max(cost, s) end
    return { cost = cost, straight = s, a = a, b = b, via = true, route = true, flight = rt.flight }
end

-- the driver: running searches get a slice every frame, so a route is ready soon also when the arrows ask seldom
local driver = CreateFrame("Frame")
if driver.SetScript then
    driver:SetScript("OnUpdate", function()
        local k = 1
        while pending[k] do
            local x = pending[k]
            if not x.search then
                table.remove(pending, k)
            else
                local ok, ended = pcall(stepSearch, x.search, P.ROUTE_MS)
                if not ok then x.search, x.failed = nil, true; table.remove(pending, k)
                elseif ended then adopt(x); table.remove(pending, k)
                else k = k + 1 end
                break                           -- one search per frame
            end
        end
    end)
end
P._Drive = function()
    for _ = 1, 100000 do
        local x = pending[1]
        if not x then return end
        if x.search and stepSearch(x.search, 1000) then adopt(x) end
        if not x.search then table.remove(pending, 1) end
    end
end

function P.Way(p, q)
    local w = coarseWay(p, q)
    if w and not (OMQDB and OMQDB.pathFineOff) and num(p.a) and num(q.a) and p.inst == q.inst then
        local ok, r = pcall(P.RouteWay, p, q, w)
        if ok and r then return r end
    end
    -- the gliding point first, then the fine way to it: a wall between me and the gliding point is walked round
    local ka, kb = w and w.a, w and w.b
    if w and w.via then P.Carrot(p, w) end
    if w and OMQ.PathRaster and not (OMQDB and OMQDB.pathFineOff) then steer(p, w, ka, kb) end
    return w
end
function P._ResetWay()
    wayCache, fineCache = {}, {}
    for k in pairs(routes) do routes[k] = nil end
    for k in pairs(pending) do pending[k] = nil end
end
function P._Reset()
    for k in pairs(routes) do routes[k] = nil end
    for k in pairs(pending) do pending[k] = nil end
    graphs, taxiCache, wayCache, fineCache = {}, {}, {}, {}
    rasterTiles, rasterOrder = {}, {}
    for k in pairs(memo) do memo[k] = nil end
    P.taxiVersion = P.taxiVersion + 1
end

----------------------------------------------------------------------
-- /omq path
----------------------------------------------------------------------
local function myPos() return OMQ.NextQuest and OMQ.NextQuest.MyPos and OMQ.NextQuest.MyPos() end

function P.Diag()
    local out = { "Ways over the land - diagnostics" }
    out[#out + 1] = "ways: " .. (P.Enabled() and "on" or "off (straight lines)")
    out[#out + 1] = "arrows: " .. (P.ArrowWays() and "way over the land" or "straight line") .. " (middle click on an arrow switches)"
    local pos = myPos()
    if not pos then out[#out + 1] = "position: none"; return out end
    local g = P.Graph(pos.inst)
    out[#out + 1] = string.format("position: %.0f, %.0f, continent %s", pos.a, pos.b, tostring(pos.inst))
    local v = OMQ.PathRaster and OMQ.PathRaster[pos.inst] and P.CellAt(pos.inst, P.RC(pos.a, pos.b))
    out[#out + 1] = "fine steering: " .. ((OMQDB and OMQDB.pathFineOff) and "off" or not v and "no raster here"
        or v == 0 and "my cell is not walkable ground in the raster" or v >= 512 and "my cell has more floors - not steered here"
        or string.format("on (my cell walks %d ways%s)", (function() local n = 0; for d = 0, 7 do if math.floor(v / 2 ^ d) % 2 == 1 then n = n + 1 end end; return n end)(), v % 512 >= 256 and ", swum" or ""))
    if not g then out[#out + 1] = "no walking network for this continent"; return out end
    local near = P.Near(g, pos.a, pos.b)
    out[#out + 1] = string.format("network: %d anchors, %d near me (nearest %s yd)", g.n, #near,
        near[1] and string.format("%.0f", near[1][2]) or "-")
    local taxis = P.Taxis(pos.inst)
    local names = {}
    for _, t in ipairs(taxis) do names[#names + 1] = t.name end
    out[#out + 1] = string.format("flight masters I know here: %d%s", #taxis, #names > 0 and (" (" .. table.concat(names, "; ") .. ")")
        or " - talk to a flight master once, then OMQ knows which ones you have")
    local t = OMQ.QuestRun and OMQ.QuestRun.Target and OMQ.QuestRun:Target()
    if t and t.place then
        local w = P.Way(pos, t.place)
        if w then
            out[#out + 1] = string.format("Quest Run stop: straight %.0f yd, way %.0f yd%s%s", w.straight, w.cost,
                w.via and string.format(", heading for %.0f yd ahead", straight(pos.a, pos.b, w.a, w.b)) or ", straight",
                w.flight and (", fly from " .. w.flight) or "")
        end
    end
    local rt = routes[1] and routes[1].cur
    if rt then
        out[#out + 1] = string.format("route of the last arrow target: %.0f yd, %d%% walked%s%s", rt.cum[#rt.cells],
            math.floor(100 * rt.cum[rt.k] / math.max(1, rt.cum[#rt.cells])), rt.leg and ", a leg (the next is searched on the way)" or "",
            rt.flight and (", to the flight master " .. rt.flight) or "")
    elseif routes[1] and routes[1].search then
        out[#out + 1] = "route of the last arrow target: searching"
    end
    out[#out + 1] = "searches so far: " .. P.stats.searches .. ", fine searches: " .. (P.stats.fine or 0)
        .. ", routes: " .. (P.stats.routes or 0) .. (P.stats.routeCells and (" (last " .. P.stats.routeCells .. " cells)") or "")
    if OMQ.PathLog and OMQ.PathLog.Summary then out[#out + 1] = OMQ.PathLog:Summary() end
    return out
end

-- what the game's own way points say (the retail navigation API is in the Forever client)
function P.Probe()
    local out = { "Game way points - probe" }
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    out[#out + 1] = "map: " .. tostring(map)
    if C_Navigation and C_Navigation.GetNextWaypointForMap and num(map) then
        local ok, x, y, text = pcall(C_Navigation.GetNextWaypointForMap, map)
        out[#out + 1] = "C_Navigation.GetNextWaypointForMap: " .. (ok and (tostring(x) .. ", " .. tostring(y) .. ", " .. tostring(text)) or "error")
    else
        out[#out + 1] = "C_Navigation.GetNextWaypointForMap: missing"
    end
    local t = OMQ.QuestRun and OMQ.QuestRun.Target and OMQ.QuestRun:Target()
    if t and C_QuestLog and C_QuestLog.GetNextWaypoint then
        local ok, m, x, y = pcall(C_QuestLog.GetNextWaypoint, t.qid)
        out[#out + 1] = "C_QuestLog.GetNextWaypoint(" .. tostring(t.qid) .. "): " .. (ok and (tostring(m) .. ", " .. tostring(x) .. ", " .. tostring(y)) or "error")
    end
    return out
end

local function show(lines)
    if OMQ.ShowReport then OMQ:ShowReport(lines) else for _, l in ipairs(lines) do print(l) end end
end

local taxiFrame = CreateFrame("Frame")
pcall(taxiFrame.RegisterEvent, taxiFrame, "TAXIMAP_OPENED")
taxiFrame:SetScript("OnEvent", function() pcall(P.LearnTaxis) end)

OMQ:RegisterCommand("path", function(arg)
    arg = (arg or ""):lower()
    if arg == "off" then
        if OMQDB then OMQDB.pathOff = true end
        P._ResetWay()
        OMQ:Print("ways over the land: off - Quest Run uses straight lines")
    elseif arg == "on" then
        if OMQDB then OMQDB.pathOff = nil end
        P._ResetWay()
        OMQ:Print("ways over the land: on")
    elseif arg == "fine off" or arg == "fine on" then
        if OMQDB then OMQDB.pathFineOff = arg == "fine off" or nil end
        P._ResetWay()
        OMQ:Print("fine steering near you: " .. (arg == "fine off" and "off" or "on"))
    elseif arg == "probe" then
        show(P.Probe())
    elseif arg == "log" then
        OMQ:Print(OMQ.PathLog and OMQ.PathLog:Summary() or "no recording")
    else
        show(P.Diag())
    end
end, "ways over the land: /omq path [on|off|fine on|fine off|probe|log]")
