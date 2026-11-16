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
-- The arrow's way (decision 609, before: 472 and 585): Data/PathRaster.lua holds the ground in cells of 8 yards with
-- all its floors (bridges, tunnels, ramps, safe falls). From the arrow's target the walk to it is searched back
-- over these once and kept; the arrow follows it from wherever I stand. The network above gives the planner its
-- costs, the flights, the corridor of that search, and the arrow's way until the search has reached me.
-- /omq path [on|off|fine on|fine off|diag|probe|log|rec|mark <words>]   (fine off: only the network's way)
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
    if not flew and best <= s * P.SLACK + P.SLACK_YD then
        -- (the search and where I join it go along: a far target's leg is found from them, 609)
        return { cost = math.max(best, s), straight = s, a = q.a, b = q.b, via = false, srch = srch, first = first, best = best }
    end
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
-- The ground in cells of 8 yards, with all its floors (decision 609)
----------------------------------------------------------------------
-- Data/PathRaster.lua holds the walkable ground in cells of 8.33 yards. A NODE is a floor of a cell: floor 0 is the
-- ground itself, the others are bridges, tunnels, ramps, the storeys of a house (OMQ.PathFloors). Walks between
-- nodes go both ways; a safe fall (a drop) goes one way. Before (decisions 472 and 585) only floor 0 was known:
-- no way led over a bridge or through a tunnel, and the top and the foot of a cliff were the same place.
-- The game does not tell my height (UnitPosition gives 0), so the floor I am on is followed from cell to cell
-- (P.Stand): the floors I can have walked or dropped to from where I was.
local CELL = TILE / 64
P.CELL = CELL
P.FINE_KEEP = 96                -- unpacked tiles kept
P.SWIM = 1.5                    -- a swum cell costs this much more
P.EDGE = 0.4                    -- a ground cell next to a wall costs this much more: ways keep off walls
P.DROP = 0.5                    -- a safe fall costs this many cells more than the step
local DR = { -1, 1, 0, 0, -1, -1, 1, 1 }    -- N, S, W, E, NW, NE, SW, SE
local DC = { 0, 0, -1, 1, -1, 1, -1, 1 }
local BIT = { 1, 2, 4, 8, 16, 32, 64, 128 }
local OPP = { 2, 1, 4, 3, 8, 7, 6, 5 }
local DIR = {}                              -- (dr + 1) * 3 + dc + 2 -> direction
for d = 1, 8 do DIR[(DR[d] + 1) * 3 + DC[d] + 2] = d end
local SQ2 = math.sqrt(2)
local SWUM, MORE = 256, 512
local floor = math.floor
local B64 = {}
do
    local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do B64[abc:byte(i)] = i - 1 end
end
local function walks(v, d) return floor(v / BIT[d]) % 2 == 1 end
local function rc(a, b) return floor((ORIGIN - a) / CELL), floor((ORIGIN - b) / CELL) end
local function center(r, c) return ORIGIN - (r + 0.5) * CELL, ORIGIN - (c + 0.5) * CELL end
P.RC, P.Center = rc, center
-- a node: (row * 16384 + column) * 8 + floor
local function nodeOf(r, c, k) return (r * 16384 + c) * 8 + k end
local function nodeRC(n)
    local k = n % 8
    local cc = (n - k) / 8
    local c = cc % 16384
    return (cc - c) / 16384, c, k
end
P.Node, P.NodeRC = nodeOf, nodeRC

local rasterTiles, rasterRecs, rasterOrder = {}, {}, {}
local function unpackTile(str)
    local t, n = {}, 0
    for k = 1, #str - 2, 3 do
        local x, y, z = str:byte(k, k + 2)
        local v = B64[x] * 64 + B64[y]
        for _ = 0, B64[z] do n = n + 1; t[n] = v end
    end
    return t
end
-- the records of a tile: [cell * 8 + floor] = { swum, nw (number of walks), walk codes ..., drop codes ... }
-- (a code: direction * 7 + floor, direction 0 to 7 = N ... SE, 8 = the same cell)
local function unpackRecs(str)
    local recs, k, n = {}, 1, #str
    while k + 4 <= n do
        local a, b, c, x, y = str:byte(k, k + 4)
        local h = B64[a] * 4096 + B64[b] * 64 + B64[c]
        local nw, nd = B64[x], B64[y]
        local rec = { swum = floor(h / 4) % 2 == 1, nw = nw }
        for i = 1, nw + nd do rec[i] = B64[str:byte(k + 4 + i)] end
        recs[floor(h / 8)] = rec
        k = k + 5 + nw + nd
    end
    return recs
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
    local f = OMQ.PathFloors and OMQ.PathFloors[inst]
    rasterRecs[id] = t and f and f[key] and unpackRecs(f[key]) or false
    rasterOrder[#rasterOrder + 1] = id
    if #rasterOrder > P.FINE_KEEP then
        local old = table.remove(rasterOrder, 1)
        rasterTiles[old], rasterRecs[old] = nil, nil
    end
    return t or nil
end
-- a cell's value: the walks of its floor 0 to floor 0 of the neighbours, + 256 swum, + 512 it has records; 0: nothing
function P.CellAt(inst, r, c)
    local t = P.RasterTile(inst, floor(r / 64) * 128 + floor(c / 64))
    return t and t[(r % 64) * 64 + c % 64 + 1] or 0
end
local cellAt = P.CellAt
-- the record of floor k of a cell (only cells whose value has 512)
local function recAt(inst, r, c, k)
    local key = floor(r / 64) * 128 + floor(c / 64)
    local id = inst * 16384 + key
    local recs = rasterRecs[id]
    if recs == nil then P.RasterTile(inst, key); recs = rasterRecs[id] end
    return recs and recs[((r % 64) * 64 + c % 64) * 8 + k] or nil
end
P.RecAt = recAt

-- is floor k of a cell a node?
local function exists(inst, r, c, k)
    local v = cellAt(inst, r, c)
    if v == 0 then return false end
    if k == 0 and v % MORE ~= 0 then return true end
    return v >= MORE and recAt(inst, r, c, k) ~= nil
end
-- the nodes of a cell: { node, ... }
function P.Floors(inst, r, c)
    local v = cellAt(inst, r, c)
    local out = {}
    if v == 0 then return out end
    if v < MORE then out[1] = nodeOf(r, c, 0); return out end
    for k = 0, 6 do
        if (k == 0 and v % MORE ~= 0) or recAt(inst, r, c, k) then out[#out + 1] = nodeOf(r, c, k) end
    end
    return out
end
-- the node I walk to from node n in direction d (1 to 8), nil when there is none; with more than one, the floor
-- `prefer` when it is among them, else the lowest
local function stepWalk(inst, n, d, prefer)
    local r, c, k = nodeRC(n)
    local v = cellAt(inst, r, c)
    local best = nil
    if k == 0 and walks(v, d) then
        if not prefer or prefer == 0 then return nodeOf(r + DR[d], c + DC[d], 0) end
        best = 0
    end
    if v >= MORE then
        local rec = recAt(inst, r, c, k)
        if rec then
            for i = 1, rec.nw do
                local code = rec[i]
                local f = code % 7
                if (code - f) / 7 == d - 1 then
                    if f == prefer then return nodeOf(r + DR[d], c + DC[d], f) end
                    if not best or f < best then best = f end
                end
            end
        end
    end
    return best and nodeOf(r + DR[d], c + DC[d], best) or nil
end
P.StepWalk = stepWalk
-- every node I get to from node n in cell (r1, c1), the next cell or my own: walked, or dropped (a safe fall)
local function stepsInto(inst, n, r1, c1, out)
    local r, c, k = nodeRC(n)
    local dr, dc = r1 - r, c1 - c
    local d = DIR[(dr + 1) * 3 + dc + 2]
    local v = cellAt(inst, r, c)
    if d then
        if k == 0 and walks(v, d) then out[nodeOf(r1, c1, 0)] = true end
        if v >= MORE then
            local rec = recAt(inst, r, c, k)
            if rec then
                for i = 1, rec.nw do
                    local code = rec[i]
                    local f = code % 7
                    if (code - f) / 7 == d - 1 then out[nodeOf(r1, c1, f)] = true end
                end
            end
        end
    end
    -- drops: the records of the floors of that cell name the floors falling onto them
    if (d or (dr == 0 and dc == 0)) and cellAt(inst, r1, c1) >= MORE then
        local back = (dr == 0 and dc == 0) and 8 or (OPP[d] - 1)
        local want = back * 7 + k
        for f = 0, 6 do
            local rec = recAt(inst, r1, c1, f)
            if rec then
                for i = rec.nw + 1, #rec do
                    if rec[i] == want then out[nodeOf(r1, c1, f)] = true; break end
                end
            end
        end
    end
    return out
end
P.StepsInto = stepsInto

----------------------------------------------------------------------
-- The floor I stand on, followed from cell to cell
----------------------------------------------------------------------
P.SNAP = 2                      -- cells around a place without ground that are searched for the nearest ground
local me = {}                   -- inst, r, c, set = { [node] = true }, n (how many)
local function count(set) local n = 0; for _ in pairs(set) do n = n + 1 end return n end
-- the nodes at a place whose own cell is no ground: those of the nearest cells around it
local function snap(inst, r, c)
    local set = {}
    for ring = 0, P.SNAP do
        for dr = -ring, ring do
            for dc = -ring, ring do
                if math.max(math.abs(dr), math.abs(dc)) == ring then
                    for _, n in ipairs(P.Floors(inst, r + dr, c + dc)) do set[n] = true end
                end
            end
        end
        if next(set) then break end
    end
    return set
end
-- where the player at p may stand: { [node] = true } (several while the game cannot tell: under or on a bridge)
function P.Stand(p)
    local r, c = rc(p.a, p.b)
    if me.inst == p.inst and me.r == r and me.c == c and me.set then return me.set end
    local set = nil
    if me.inst == p.inst and me.set and me.onGround and math.max(math.abs(me.r - r), math.abs(me.c - c)) <= 3 then
        -- step by step along the line from the old cell to the new one
        set = me.set
        local cr, cc = me.r, me.c
        while (cr ~= r or cc ~= c) and set do
            local nr = cr + (r > cr and 1 or r < cr and -1 or 0)
            local nc = cc + (c > cc and 1 or c < cc and -1 or 0)
            local nxt = {}
            -- (also from the floors of my cell I fall onto when I walk off a rock or a ledge)
            local from = {}
            for n in pairs(set) do from[n] = true; stepsInto(p.inst, n, cr, cc, from) end
            for n in pairs(from) do stepsInto(p.inst, n, nr, nc, nxt) end
            if not next(nxt) and nr ~= cr and nc ~= cc then
                -- a diagonal the ground does not walk: round the corner, one way or the other
                for _, via in ipairs({ { nr, cc }, { cr, nc } }) do
                    local mid = {}
                    for n in pairs(from) do stepsInto(p.inst, n, via[1], via[2], mid) end
                    for n in pairs(mid) do stepsInto(p.inst, n, nr, nc, nxt) end
                end
            end
            set = next(nxt) and nxt or nil
            cr, cc = nr, nc
        end
    end
    local onGround = true
    if not set then
        -- a new place (login, a flight, a hearthstone), or a step the data does not know: every floor of the cell
        set = {}
        for _, n in ipairs(P.Floors(p.inst, r, c)) do set[n] = true end
        if not next(set) then set = snap(p.inst, r, c); onGround = false end
    end
    me.inst, me.r, me.c, me.set, me.onGround = p.inst, r, c, set, onGround
    return set
end
function P._ResetStand() me = {} end

-- I run but do not get anywhere (a wall, the foot of a cliff; I slide along it a little): the floor the arrow took
-- me to be on is not mine.
-- That floor is dropped from the set; was it the only one, the other floors of my cell take its place.
P.PUSH_S, P.PUSH_YD = 3, 10        -- running for these seconds within these yards: pushing against something
local push = {}
function P.Pushing(p, now)
    local speed = GetUnitSpeed and GetUnitSpeed("player")
    if not num(speed) or speed <= 0 or not push.t or now < push.t or push.inst ~= p.inst
        or straight(push.a, push.b, p.a, p.b) > P.PUSH_YD then
        push.t, push.a, push.b, push.inst = now, p.a, p.b, p.inst
        return false
    end
    return now - push.t >= P.PUSH_S
end
function P.Doubt(n)
    if not (me.set and me.set[n]) then return false end
    local set = {}
    for m in pairs(me.set) do if m ~= n then set[m] = true end end
    if not next(set) then
        -- the only floor I took myself to be on: I lost my floor on the way - any other floor of this cell
        for _, m in ipairs(P.Floors(me.inst, me.r, me.c)) do if m ~= n then set[m] = true end end
    end
    if not next(set) then return false end
    me.set = set
    push.t = nil
    return true
end

-- every node I get to from node n going in direction d (1 to 8): walked, fallen onto the next cell (a safe fall),
-- or fallen off a rock or ledge within my cell and then walked or fallen on
local function advance(inst, n, d, out)
    local r, c = nodeRC(n)
    local nr, nc = r + DR[d], c + DC[d]
    stepsInto(inst, n, nr, nc, out)
    if cellAt(inst, r, c) >= MORE then
        for m in pairs(stepsInto(inst, n, r, c, {})) do stepsInto(inst, m, nr, nc, out) end
    end
    return out
end
P.Advance = advance

----------------------------------------------------------------------
-- Line of sight on the nodes
----------------------------------------------------------------------
-- do I walk straight from the nodes of `from` at (pa, pb) to (qa, qb)? Every cell the line crosses, in its order,
-- each a walk (or a safe fall) from a node before; where several floors can be stepped onto, all of them are
-- followed. Where the line passes the corner of a cell, the cells on both sides of the corner must be walked to as
-- well (no corner of a rock is cut). With a search st: only over nodes it has finished, and none of them farther
-- from the target than `glim` (a ledge that leads back is no way on).
-- Gives the nodes the line can end on { [node] = true }, nil when it is blocked.
local CORNER = 0.15             -- cells: a line passing a corner this close counts as through it
local function sightLine(inst, from, pa, pb, qa, qb, st, glim)
    local x0, y0 = (ORIGIN - pa) / CELL, (ORIGIN - pb) / CELL
    local x1, y1 = (ORIGIN - qa) / CELL, (ORIGIN - qb) / CELL
    local r, c, r1, c1 = floor(x0), floor(y0), floor(x1), floor(y1)
    local dx, dy = x1 - x0, y1 - y0
    local sr, sc = dx > 0 and 1 or -1, dy > 0 and 1 or -1
    local tdx = dx ~= 0 and math.abs(1 / dx) or math.huge
    local tdy = dy ~= 0 and math.abs(1 / dy) or math.huge
    local tx = dx ~= 0 and (sr > 0 and (r + 1 - x0) or (x0 - r)) * tdx or math.huge
    local ty = dy ~= 0 and (sc > 0 and (c + 1 - y0) or (y0 - c)) * tdy or math.huge
    local eps = CORNER / math.max(math.abs(dx), math.abs(dy), 0.001)
    local cur = from
    for _ = 1, 400 do
        if r == r1 and c == c1 then return cur end
        local mr, mc = 0, 0
        if r ~= r1 and c ~= c1 and math.abs(tx - ty) < eps then
            mr, mc = sr, sc
            tx, ty = tx + tdx, ty + tdy
        elseif (tx < ty and r ~= r1) or c == c1 then
            mr = sr; tx = tx + tdx
        else
            mc = sc; ty = ty + tdy
        end
        local d = DIR[(mr + 1) * 3 + mc + 2]
        local nxt = {}
        for n in pairs(cur) do
            if mr == 0 or mc == 0 or (next(advance(inst, n, DIR[(mr + 1) * 3 + 2], {})) and next(advance(inst, n, DIR[3 + mc + 2], {}))) then
                advance(inst, n, d, nxt)
            end
        end
        if st then
            for n in pairs(nxt) do
                if not (st.closed[n] and st.g[n] <= glim) then nxt[n] = nil end
            end
        end
        if not next(nxt) then return nil end
        r, c, cur = r + mr, c + mc, nxt
    end
    return nil
end
P.SightLine = sightLine
P.SIGHT_WIDE = 0.4              -- the line keeps this many cells off walls on both sides
-- a wide line of sight from node n0 at (pa, pb) to node n1 at (qa, qb): the line itself must end on n1, and a line
-- on each side of it must be walkable too (ending on n1 or right next to it), so the walk does not brush a wall
function P.Sees(inst, n0, pa, pb, n1, qa, qb, st)
    local glim = st and (st.g[n0] or 0) + 1.5
    local from = { [n0] = true }
    local mid = sightLine(inst, from, pa, pb, qa, qb, st, glim)
    if not (mid and mid[n1]) then return false end
    local d = straight(pa, pb, qa, qb)
    if d < CELL then return true end
    local ua, ub = -(qb - pb) / d * CELL * P.SIGHT_WIDE, (qa - pa) / d * CELL * P.SIGHT_WIDE
    local r0, c0 = rc(pa, pb)
    local r1, c1 = rc(qa, qb)
    for o = -1, 1, 2 do
        local sa, sb = pa + ua * o, pb + ub * o
        local sr, sc = rc(sa, sb)
        local start = from
        if sr ~= r0 or sc ~= c0 then
            local dd = DIR[(sr - r0 + 1) * 3 + (sc - c0) + 2]
            start = dd and advance(inst, n0, dd, {})
            if not (start and next(start)) then start, sa, sb = from, pa, pb end      -- I stand right at a wall
        end
        local ea, eb = qa + ua * o, qb + ub * o
        local er, ec = rc(ea, eb)
        local ends = sightLine(inst, start, sa, sb, ea, eb, st, glim)
        if not ends then return false end
        if not ends[n1] then
            local dd = DIR[(r1 - er + 1) * 3 + (c1 - ec) + 2]
            local ok = false
            if dd then
                for n in pairs(ends) do
                    if advance(inst, n, dd, {})[n1] then ok = true; break end
                end
            end
            if not ok then return false end
        end
    end
    return true
end

----------------------------------------------------------------------
-- The way to a target: one search back from it, kept (decision 609)
----------------------------------------------------------------------
-- From the target the cheapest walk TO it is searched over the nodes, outward, toward me (A*); every node the
-- search has finished knows its yards to the target and the next node on the way there. The arrow follows these
-- from whatever node I stand on: there is no single route to fall off. When I leave the searched ground the same
-- search simply goes on toward my new place. The search stays in a corridor around the coarse network's way (wider
-- when it finds nothing); far targets get the way to a point about ROUTE_LEG yards along the network first.
-- It runs in small slices (ROUTE_MS per frame); until it has reached me the arrow uses the network's way.
P.ROUTES = true
P.ROUTE_NODES = 150000          -- nodes a search finishes at most
P.ROUTE_MS = 3                  -- milliseconds of search per frame
P.ROUTE_SLICE = 400             -- nodes per slice without a clock
P.ROUTE_FIRST_MS, P.ROUTE_FIRST_SLICE = 8, 3000   -- the first slice of a search, right when it starts
P.ROUTE_FAR = 2600              -- yards: farther targets get a part of the way (a leg) at a time
P.ROUTE_LEG = 2000              -- yards along the coarse network a leg goes
P.ROUTE_RENEW = 500             -- yards before the end of a leg the next one is searched
P.ROUTE_RETRY, P.ROUTE_RETRY_YD = 15, 60    -- a failed search is tried again after these seconds (doubled each time) and yards moved
P.ROUTE_GOAL = 3                -- cells round a target that is no ground that count as there
P.ROUTE_BLOCK = 16              -- cells: the corridor is made of blocks of this size
P.ROUTE_WIDTH = 3               -- blocks on each side of the network's way the search may use; then 3 times that
P.ROUTE_MARGIN = 6              -- cells the search goes on past me, so a few steps aside stay on searched ground
P.LOOK = 40                     -- nodes ahead on the way the arrow may head for (when it sees them)
P.CARROT_MOVE, P.CARROT_AGE = 2, 0.3   -- the arrow's point is found again after these yards moved or seconds

local function clockMs() return debugprofilestop and debugprofilestop() or nil end

-- a heap of nodes by key, in two arrays
local function hpush(hk, hv, key, val)
    local n = #hk + 1
    while n > 1 do
        local p = floor(n / 2)
        if hk[p] <= key then break end
        hk[n], hv[n] = hk[p], hv[p]
        n = p
    end
    hk[n], hv[n] = key, val
end
local function hpop(hk, hv)
    local n = #hk
    local key, val = hk[1], hv[1]
    local lk, lv = hk[n], hv[n]
    hk[n], hv[n] = nil, nil
    n = n - 1
    if n > 0 then
        local i = 1
        while true do
            local l = 2 * i
            if l > n then break end
            if l < n and hk[l + 1] < hk[l] then l = l + 1 end
            if hk[l] >= lk then break end
            hk[i], hv[i] = hk[l], hv[l]
            i = l
        end
        hk[i], hv[i] = lk, lv
    end
    return key, val
end

local function blockOf(r, c) return floor(r / P.ROUTE_BLOCK) * 4096 + floor(c / P.ROUTE_BLOCK) end
-- the blocks within `width` blocks of the line of points { {a, b}, ... }
local function corridor(pts, width)
    local set = {}
    local function mark(a, b)
        local r, c = rc(a, b)
        local br, bc = floor(r / P.ROUTE_BLOCK), floor(c / P.ROUTE_BLOCK)
        for dr = -width, width do
            for dc = -width, width do set[(br + dr) * 4096 + bc + dc] = true end
        end
    end
    local step = P.ROUTE_BLOCK * CELL * 0.75
    for i = 1, #pts do
        local x = pts[i]
        mark(x[1], x[2])
        local y = pts[i + 1]
        if y then
            local d = straight(x[1], x[2], y[1], y[2])
            for k = 1, floor(d / step) do
                local f = k * step / d
                mark(x[1] + (y[1] - x[1]) * f, x[2] + (y[2] - x[2]) * f)
            end
        end
    end
    return set
end
P._Corridor = corridor

-- a new search back from the goal (ga, gb): its state
local function newSearch(inst, ga, gb, blocks)
    local st = { inst = inst, ga = ga, gb = gb, g = {}, par = {}, closed = {}, hk = {}, hv = {}, count = 0,
        blocks = blocks, hr = 0, hc = 0, sources = 0 }
    local r1, c1 = rc(ga, gb)
    local at = P.Floors(inst, r1, c1)
    if #at > 0 then
        for _, n in ipairs(at) do st.g[n] = 0; st.sources = st.sources + 1 end
        st.exact = true                              -- the target's own cell: the arrow ends on the target itself
    else
        -- a target that is no ground (in a house the data does not know, on a rock): the ground around it
        for ring = 1, P.ROUTE_GOAL do
            for dr = -ring, ring do
                for dc = -ring, ring do
                    if math.max(math.abs(dr), math.abs(dc)) == ring then
                        for _, n in ipairs(P.Floors(inst, r1 + dr, c1 + dc)) do
                            st.g[n] = math.sqrt(dr * dr + dc * dc); st.sources = st.sources + 1
                        end
                    end
                end
            end
        end
    end
    st.fresh = true
    return st
end

-- point the search at cell (r, c): the keys of the open nodes are made anew (the yards found so far stay true)
local function aim(st, r, c)
    st.hr, st.hc = r, c
    local g, closed = st.g, st.closed
    local list = {}
    if st.fresh then
        for n in pairs(g) do list[#list + 1] = n end
        st.fresh = nil
    else
        local hv, seen = st.hv, {}
        for i = 1, #hv do
            local n = hv[i]
            if not closed[n] and not seen[n] then seen[n] = true; list[#list + 1] = n end
        end
    end
    local hk, hv = {}, {}
    st.hk, st.hv = hk, hv
    for i = 1, #list do
        local n = list[i]
        local nr, nc = nodeRC(n)
        local a, b = math.abs(nr - r), math.abs(nc - c)
        hpush(hk, hv, g[n] + (a > b and a + (SQ2 - 1) * b or b + (SQ2 - 1) * a), n)
    end
    st.ended, st.stopAt = nil, nil
end

-- the node of the set the search has finished with the fewest yards to the target, nil when none yet
local function reached(st, set)
    local best, bg = nil, nil
    for n in pairs(set) do
        if st.closed[n] and (not bg or st.g[n] < bg) then best, bg = n, st.g[n] end
    end
    return best
end

-- run a search for a while toward the nodes of `set`: true when it has ended (they are reached, or it gave up)
local function stepSearch(st, set, budgetMs, slice)
    if st.ended then return true end
    local inst, g, par, closed, hk, hv, blocks = st.inst, st.g, st.par, st.closed, st.hk, st.hv, st.blocks
    local hr, hc = st.hr, st.hc
    local t0 = clockMs()
    local steps = 0
    local SWIM, EDGE, DROP, BLOCK = P.SWIM, P.EDGE, P.DROP, P.ROUTE_BLOCK
    while hk[1] do
        if st.stopAt and hk[1] > st.stopAt then break end
        if st.count >= P.ROUTE_NODES then st.full = true; break end
        steps = steps + 1
        if steps % 64 == 0 then
            if t0 then
                if clockMs() - t0 >= (budgetMs or P.ROUTE_MS) then return false end
            elseif steps >= (slice or P.ROUTE_SLICE) then
                return false
            end
        end
        local key, n = hpop(hk, hv)
        if not closed[n] then
            closed[n] = true
            st.count = st.count + 1
            -- I am reached: a little farther still (the ground beside me), then the search rests
            if not st.stopAt and set[n] then st.stopAt = key + P.ROUTE_MARGIN end
            local k = n % 8
            local cc = (n - k) / 8
            local c = cc % 16384
            local r = (cc - c) / 16384
            local v, gi = cellAt(inst, r, c), g[n]
            local rec = v >= MORE and recAt(inst, r, c, k) or nil
            local last = rec and #rec or 0
            -- the nodes that walk (or fall) to this one: its walks (they go both ways), the drops onto it
            for i = (k == 0 and -7 or 1), last do
                local d, f, drop, ok = nil, 0, false, true
                if i <= 0 then
                    d = i + 8
                    ok = walks(v, d)
                else
                    local code = rec[i]
                    f = code % 7
                    d = (code - f) / 7 + 1
                    drop = i > rec.nw
                end
                if ok then
                    local nr, nc = r, c
                    if d <= 8 then nr, nc = r + DR[d], c + DC[d] end
                    local u = (nr * 16384 + nc) * 8 + f
                    if not closed[u] and (not blocks or blocks[floor(nr / BLOCK) * 4096 + floor(nc / BLOCK)]) then
                        local stepc = (d > 4 and d <= 8) and SQ2 or 1
                        if d > 8 then stepc = 0 end
                        if drop then stepc = stepc + DROP end
                        local uv = cellAt(inst, nr, nc)
                        if f == 0 then
                            if uv % MORE >= SWUM then stepc = stepc * SWIM
                            elseif uv % SWUM ~= 255 and uv < MORE then stepc = stepc + EDGE end
                        else
                            local ur = recAt(inst, nr, nc, f)
                            if ur and ur.swum then stepc = stepc * SWIM end
                        end
                        local ng = gi + stepc
                        local og = g[u]
                        if og == nil or ng < og then
                            g[u], par[u] = ng, n
                            local a, b = nr - hr, nc - hc
                            if a < 0 then a = -a end
                            if b < 0 then b = -b end
                            hpush(hk, hv, ng + (a > b and a + (SQ2 - 1) * b or b + (SQ2 - 1) * a), u)
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
P._NewSearch, P._StepSearch, P._Aim, P._Reached = newSearch, stepSearch, aim, reached

-- the goal of a search from p for target q, with the coarse way w: { a, b, tail (yards from the goal on to the
-- target), leg, flight, pts (the line the corridor follows) }
local function goalOf(p, q, w)
    local pts = { { p.a, p.b } }
    if w and w.flight then
        local fy = straight(p.a, p.b, w.a, w.b)
        pts[2] = { w.a, w.b }
        return { a = w.a, b = w.b, tail = math.max(0, (w.cost or 0) - fy), flight = w.flight, pts = pts }
    end
    local s = straight(p.a, p.b, q.a, q.b)
    if w and w.srch and w.first and w.best then
        local srch, g = w.srch, w.srch.g
        local n, steps = w.first, 0
        local far = s > P.ROUTE_FAR
        while n and n > 0 and steps < 2000 do
            steps = steps + 1
            local a, b
            if n <= g.n then a, b = g.x[n], g.y[n] else local t = srch.taxis[n - g.n]; a, b = t.a, t.b end
            local nx = srch.nxt[n]
            if nx and nx < 0 then break end             -- never past a flight
            pts[#pts + 1] = { a, b }
            if far and w.best - srch.dist[n] >= P.ROUTE_LEG and srch.dist[n] > P.ROUTE_RENEW and n <= g.n then
                return { a = a, b = b, tail = srch.dist[n], leg = true, pts = pts }
            end
            if not nx or nx <= 0 then break end
            n = nx
        end
    end
    pts[#pts + 1] = { q.a, q.b }
    return { a = q.a, b = q.b, tail = 0, pts = pts }
end
P._GoalOf = goalOf

local routes = {}               -- the searches of the last few targets, found by the target's place
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
    if old then old.st, old.nx = nil, nil end
    return x
end

local function queue(x)
    for _, y in ipairs(pending) do if y == x then return end end
    pending[#pending + 1] = x
end

-- start a search for target record x from p; wide: 1 (the corridor), 2 (three times as wide), 3 (anywhere)
local function startSearch(x, p, q, w, wide, slot)
    local goal = goalOf(p, q, w)
    local blocks = nil
    if wide < 3 then blocks = corridor(goal.pts, P.ROUTE_WIDTH * (wide == 2 and 3 or 1)) end
    local st = newSearch(p.inst, goal.a, goal.b, blocks)
    st.goal, st.wide = goal, wide
    st.pa, st.pb = p.a, p.b
    local r, c = rc(p.a, p.b)
    aim(st, r, c)
    st.set = P.Stand(p)
    x[slot or "st"] = st
    queue(x)
    -- a short search (most are) ends right here
    stepSearch(st, st.set, P.ROUTE_FIRST_MS, P.ROUTE_FIRST_SLICE)
    return st
end

-- the point the arrow heads for from node n at p: the farthest node ahead on the way that I see
local function carrot(st, inst, n, pa, pb)
    local chain, m = { n }, 1
    local par = st.par
    while m < P.LOOK do
        local nx = par[chain[m]]
        if not nx then break end
        m = m + 1
        chain[m] = nx
    end
    local atGoal = par[chain[m]] == nil             -- the way ends within what I look at
    local j = m
    while j >= 2 do
        local r, c = nodeRC(chain[j])
        local a, b = center(r, c)
        if j == m and atGoal and st.exact then a, b = st.ga, st.gb end
        if P.Sees(inst, n, pa, pb, chain[j], a, b, st) then return a, b end
        j = (j > 12) and floor(j * 0.8) or j - 1
    end
    -- right at a corner: the next node of the way that is not my own cell (a fall within it) nor right under my feet
    local r0, c0 = rc(pa, pb)
    for i = 2, m do
        local r, c = nodeRC(chain[i])
        local a, b = center(r, c)
        if i == m and atGoal and st.exact then a, b = st.ga, st.gb end
        local mine = r == r0 and c == c0
        if i == m or (not mine and straight(pa, pb, a, b) >= CELL * 0.6) then return a, b end
    end
    return st.ga, st.gb
end

-- the way for an arrow along the kept search, nil while there is none (the arrow then uses the network's way)
function P.RouteWay(p, q, w)
    if not (P.ROUTES and OMQ.PathRaster and OMQ.PathRaster[p.inst]) then return nil end
    local x = routeFor(q)
    local now = GetTime and GetTime() or 0
    local set = P.Stand(p)
    if not next(set) then return nil end            -- no ground known anywhere near me
    if x.last and x.last.way.node and P.Pushing(p, now) and P.Doubt(x.last.way.node) then
        set = me.set
        x.carrot = nil
    end
    local r0, c0 = rc(p.a, p.b)
    -- a pending search that has reached me takes over
    local nx = x.nx
    if nx then
        nx.set = set
        if reached(nx, set) then x.st, x.nx = nx, nil
        elseif nx.ended then x.nx, x.nxFailed = nil, now end
    end
    local st = x.st
    if st and st.blocks and not st.blocks[blockOf(r0, c0)] then st = nil; x.st = nil end     -- I left the corridor
    local n = st and reached(st, set)
    if st and not n then
        st.set = set
        if st.ended and not st.full and (st.hr ~= r0 or st.hc ~= c0 or st.stopAt) and st.hk[1] then
            -- I walked off the searched ground: the same search goes on toward me
            aim(st, r0, c0)
            queue(x)
            stepSearch(st, set, P.ROUTE_FIRST_MS, P.ROUTE_FIRST_SLICE)
        elseif not st.ended then
            if st.hr ~= r0 or st.hc ~= c0 then
                if math.max(math.abs(st.hr - r0), math.abs(st.hc - c0)) > 6 then aim(st, r0, c0) end
            end
            stepSearch(st, set, 1, 200)
        end
        n = reached(st, set)
        if not n and st.ended then
            -- nothing in this corridor (or too far): wider, then anywhere, then give up for a while
            local wide = (st.full or st.sources == 0) and 4 or st.wide + 1
            x.st, st = nil, nil
            if wide <= 3 then
                st = startSearch(x, p, q, w, wide)
                n = reached(st, set)
            else
                -- (each time in a row it waits twice as long, up to 2 minutes: a way the data does not have - an
                -- elevator, a boat - is not searched for over and over)
                x.fails = math.min((x.fails or 0) + 1, 4)
                x.failed = { a = p.a, b = p.b, t = now, wait = P.ROUTE_RETRY * 2 ^ (x.fails - 1) }
            end
        end
    end
    if not st then
        local f = x.failed
        if f and not (now < f.t) and (now - f.t < f.wait or straight(f.a, f.b, p.a, p.b) < P.ROUTE_RETRY_YD) then
            return nil
        end
        x.failed = nil
        if not x.st then
            st = startSearch(x, p, q, w, 1)
            n = reached(st, set)
        end
    end
    if not (st and n) then
        -- still searching: the last point for a moment, so the arrow does not jump to the network's way and back
        local l = x.last
        if l and now - l.t < 1.5 and now >= l.t then return l.way end
        return nil
    end
    x.fails = nil
    -- the next leg, while I walk on this one
    local left = st.g[n] * CELL
    if st.goal.leg and not x.nx and left < P.ROUTE_RENEW
        and not (x.nxFailed and now >= x.nxFailed and now - x.nxFailed < P.ROUTE_RETRY) then
        startSearch(x, p, q, w, 1, "nx")
    end
    -- the arrow's point (found again only after a few steps: the search for it looks along many cells)
    local cr = x.carrot
    if not (cr and cr.st == st and cr.n == n and now - cr.t < P.CARROT_AGE and now >= cr.t
        and straight(cr.pa, cr.pb, p.a, p.b) < P.CARROT_MOVE) then
        local a, b = carrot(st, p.inst, n, p.a, p.b)
        cr = { st = st, n = n, t = now, pa = p.a, pb = p.b, a = a, b = b }
        x.carrot = cr
    end
    local s = straight(p.a, p.b, q.a, q.b)
    local cost = left + (st.goal.tail or 0)
    if not st.goal.flight and not st.goal.leg and not st.exact then cost = cost + straight(st.ga, st.gb, q.a, q.b) end
    if not st.goal.flight then cost = math.max(cost, s) end
    local way = { cost = cost, straight = s, a = cr.a, b = cr.b, via = true, route = true, flight = st.goal.flight,
        leg = st.goal.leg or nil, node = n, floors = count(set) }
    x.last = { t = now, way = way }
    return way
end

-- the driver: running searches get a slice every frame, so a way is ready soon also when the arrows ask seldom
local function drive(budget)
    local k = 1
    while pending[k] do
        local x = pending[k]
        local busy = false
        for _, slot in ipairs({ "st", "nx" }) do
            local st = x[slot]
            if st and not st.ended and st.set and not busy then
                busy = true
                local ok, ended = pcall(stepSearch, st, st.set, budget)
                if not ok then st.ended, st.full = true, true end
            end
        end
        if not busy then table.remove(pending, k) else return true end      -- one search per frame
    end
    return false
end
local driver = CreateFrame("Frame")
if driver.SetScript then
    driver:SetScript("OnUpdate", function() drive(P.ROUTE_MS) end)
end
P._DriveOnce = drive
P._Drive = function()
    for _ = 1, 100000 do
        if not drive(1000) then return end
    end
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

function P.Way(p, q)
    local w = coarseWay(p, q)
    local out = w
    if w and not (OMQDB and OMQDB.pathFineOff) and num(p.a) and num(q.a) and p.inst == q.inst then
        local ok, r = pcall(P.RouteWay, p, q, w)
        if ok and r then out = r
        elseif not ok then P.stats.routeError = tostring(r) end
    end
    -- without a route (still searching, no data, no way found): the network's way with its gliding point
    if out == w and w and w.via then P.Carrot(p, w) end
    if out and P.Record then pcall(P.Record, p, q, out) end
    return out
end
function P._ResetWay()
    wayCache = {}
    for k in pairs(routes) do routes[k] = nil end
    for k in pairs(pending) do pending[k] = nil end
end
function P._Reset()
    for k in pairs(routes) do routes[k] = nil end
    for k in pairs(pending) do pending[k] = nil end
    graphs, taxiCache, wayCache = {}, {}, {}
    rasterTiles, rasterRecs, rasterOrder = {}, {}, {}
    me = {}
    for k in pairs(memo) do memo[k] = nil end
    P.taxiVersion = P.taxiVersion + 1
end

----------------------------------------------------------------------
-- The arrow's log (decision 609): what the arrow did in the last minutes, to look at a bad way afterwards
----------------------------------------------------------------------
-- Every REC_EVERY seconds per arrow target one line goes into OMQDB.pathRec.list (a ring of REC_KEEP lines):
--   time | continent | my place | the target | the point the arrow heads for | yards | kind | floors I may be on
-- kind: R a searched way, L a leg of a far way, F to a flight master, N the network's way, S straight.
-- /omq path mark [words] keeps the last MARK_LINES lines with a note in OMQDB.pathMarks (at most MARK_KEEP).
-- Nothing is sent anywhere.
P.REC_EVERY, P.REC_KEEP = 2, 600
P.MARK_LINES, P.MARK_KEEP = 150, 20
local recLast = {}
local function stamp() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end
function P.Record(p, q, w)
    if not OMQDB or OMQDB.pathRecOff then return end
    local now = GetTime and GetTime() or 0
    local key = floor(q.a / 5) * 100000 + floor(q.b / 5)
    local l = recLast[key]
    if l and now >= l and now - l < P.REC_EVERY then return end
    if not l then
        local n = 0
        for _ in pairs(recLast) do n = n + 1 end
        if n > 20 then recLast = {} end
    end
    recLast[key] = now
    local s = OMQDB.pathRec
    if type(s) ~= "table" or type(s.list) ~= "table" then s = { list = {}, at = 0 }; OMQDB.pathRec = s end
    local kind = w.route and (w.flight and "F" or w.leg and "L" or "R") or (w.via and "N" or "S")
    s.at = (s.at or 0) % P.REC_KEEP + 1
    s.list[s.at] = string.format("%d|%d|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%s|%d", stamp(), p.inst, p.a, p.b, q.a, q.b,
        w.a or q.a, w.b or q.b, w.cost or 0, kind, w.floors or 0)
end
-- the lines of the log, oldest first
function P.RecLines(max)
    local s = OMQDB and OMQDB.pathRec
    local out = {}
    if type(s) ~= "table" or type(s.list) ~= "table" then return out end
    local n = #s.list
    for i = 1, n do
        local line = s.list[(s.at + i - 1) % n + 1]
        if line then out[#out + 1] = line end
    end
    if max and #out > max then
        local cut = {}
        for i = #out - max + 1, #out do cut[#cut + 1] = out[i] end
        out = cut
    end
    return out
end
function P.Mark(note)
    if not OMQDB then return nil end
    OMQDB.pathMarks = OMQDB.pathMarks or {}
    local marks = OMQDB.pathMarks
    local pos = OMQ.NextQuest and OMQ.NextQuest.MyPos and OMQ.NextQuest.MyPos()
    local m = { t = stamp(), note = note ~= "" and note or nil, version = OMQ.version, lines = P.RecLines(P.MARK_LINES) }
    if pos and num(pos.a) and num(pos.b) then m.inst, m.a, m.b = pos.inst, floor(pos.a + 0.5), floor(pos.b + 0.5) end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if num(map) then m.map = map end
    marks[#marks + 1] = m
    while #marks > P.MARK_KEEP do table.remove(marks, 1) end
    return m, #marks
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
    local stand = v and P.Stand(pos) or {}
    local floors = {}
    for n in pairs(stand) do floors[#floors + 1] = n % 8 end
    table.sort(floors)
    out[#out + 1] = "ground near me: " .. ((OMQDB and OMQDB.pathFineOff) and "off (only the network's way)" or not v and "no data here"
        or #floors == 0 and "no walkable ground known around me"
        or string.format("%s, I may be on floor %s%s", v == 0 and "my cell is no ground, the nearest is used" or
            (v >= 512 and "my cell has more floors or a drop" or "plain ground"), table.concat(floors, " or "), v % 512 >= 256 and ", swum" or ""))
    if not g then
        out[#out + 1] = "no walking network for this continent"
    else
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
    end
    local x = routes[1]
    local st = x and x.st
    if st then
        local n = P._Reached(st, stand)
        out[#out + 1] = string.format("way of the last arrow target: %s, %d cells searched%s%s%s",
            n and string.format("%.0f yd left", st.g[n] * P.CELL) or (st.ended and "has not reached me" or "searching"), st.count,
            st.wide == 2 and ", wide corridor" or st.wide == 3 and ", searched anywhere" or "",
            st.goal.leg and ", a leg (the next is searched on the way)" or "",
            st.goal.flight and (", to the flight master " .. st.goal.flight) or "")
    elseif x and x.failed then
        out[#out + 1] = "way of the last arrow target: none found - the arrow uses the network's way"
    end
    out[#out + 1] = "network searches so far: " .. P.stats.searches .. ", way searches: " .. (P.stats.routes or 0)
        .. (P.stats.routeCells and (" (last " .. P.stats.routeCells .. " cells)") or "")
        .. (P.stats.routeError and (", last error: " .. P.stats.routeError) or "")
    out[#out + 1] = string.format("arrow log: %d lines, %d marks (/omq path mark <words> keeps the last minutes)", #P.RecLines(),
        OMQDB and OMQDB.pathMarks and #OMQDB.pathMarks or 0)
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
    local raw = arg or ""
    arg = raw:lower()
    if arg == "mark" or arg:find("^mark ") then
        local m, n = P.Mark(strtrim and strtrim(raw:sub(6)) or raw:sub(6))
        if m then
            OMQ:Print(string.format("way marked (%d lines of the arrow's log kept, mark %d of %d)", #m.lines, n, P.MARK_KEEP))
        end
    elseif arg == "rec" then
        local lines = P.RecLines(15)
        table.insert(lines, 1, "The arrow's log - last lines (time | continent | me | target | heading for | yards | kind | floors)")
        show(lines)
    elseif arg == "off" then
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
        OMQ:Print("ways over the ground near you: " .. (arg == "fine off" and "off (only the network's way)" or "on"))
    elseif arg == "probe" then
        show(P.Probe())
    elseif arg == "log" then
        OMQ:Print(OMQ.PathLog and OMQ.PathLog:Summary() or "no recording")
    else
        show(P.Diag())
    end
end, "ways over the land: /omq path [on|off|fine on|fine off|probe|log|rec|mark <words>]")
