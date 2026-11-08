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
-- /omq path [on|off|fine on|fine off|diag|probe|log]
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

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not isSecret(v) end
local function straight(a1, b1, a2, b2) return math.sqrt((a1 - a2) ^ 2 + (b1 - b2) ^ 2) end

function P.Enabled()
    if not OMQ.PathGraph then return false end
    return not (OMQDB and OMQDB.pathOff)
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
    for _, x in ipairs(P.Near(g, p.a, p.b)) do
        local d = srch.dist[x[1]]
        if d and (best == nil or d + x[2] < best) then best, first = d + x[2], x[1] end
    end
    for k, t in ipairs(srch.taxis) do
        local d = srch.dist[g.n + k]
        local r = straight(p.a, p.b, t.a, t.b)
        if d and r <= P.NEAR_MAX and (best == nil or d + r < best) then best, first = d + r, g.n + k end
    end
    if not best then return plain end
    local flew = srch.flew[first]
    if not flew and best <= s * P.SLACK + P.SLACK_YD then return { cost = math.max(best, s), straight = s, a = q.a, b = q.b, via = false } end
    local function xy(n)
        if n <= g.n then return g.x[n], g.y[n] end
        local t = srch.taxis[n - g.n]
        return t.a, t.b
    end
    -- head for the farthest node the way reaches almost straight; never past a flight master I fly from
    local way = { cost = flew and best or math.max(best, s), straight = s, via = true }
    local pick, n, steps = nil, first, 0
    while n and n > 0 and steps < 2000 do
        steps = steps + 1
        local a, b = xy(n)
        local done = best - srch.dist[n]           -- the cost from me to this node along the way
        if done <= straight(p.a, p.b, a, b) * P.SLACK + P.SLACK_YD then pick = n end
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
    way.a, way.b = xy(pick or first)
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
P.FINE_KEEP = 16                -- unpacked tiles kept
P.FINE_MOVE, P.FINE_AGE = 5, 2  -- the fine way is found again after these yards moved or seconds
P.SWIM = 1.5                    -- a swum cell costs this much more
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
function P.Sight(inst, r0, c0, r1, c1)
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
                            if cellAt(inst, nr, nc) % FLOORS >= SWUM then step = step * P.SWIM end
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
    -- a tree, a rock, a fence: a way round that is hardly longer is walked by eye, the arrow stays
    if reached and yards <= straight(pa, pb, ta, tb) * P.SLACK + P.FINE_SLACK_YD then return { a = ha, b = hb, clear = true } end
    -- the farthest cell of the way I walk to straight
    local pick = path[2] or path[1]
    for k = 3, #path do
        if not P.Sight(inst, r0, c0, path[k][1], path[k][2]) then break end
        pick = path[k]
    end
    local a, b = center(pick[1], pick[2])
    return { a = a, b = b, clear = false, yards = yards, reached = reached and d <= P.LOOK }
end

-- the arrow's heading of a way, steered on the raster; found again after FINE_MOVE yards or FINE_AGE seconds
local fineCache = {}
local function steer(p, w)
    local ha, hb = w.a, w.b
    local t = GetTime and GetTime() or 0
    local c = nil
    for _, x in ipairs(fineCache) do
        if x.inst == p.inst and math.abs(x.ha - ha) < 5 and math.abs(x.hb - hb) < 5 then c = x; break end
    end
    if not c or t - c.t > P.FINE_AGE or t < c.t or straight(c.pa, c.pb, p.a, p.b) > P.FINE_MOVE then
        local ok, f = pcall(P.Fine, p.inst, p.a, p.b, ha, hb)
        if not c then
            c = { inst = p.inst, ha = ha, hb = hb }
            table.insert(fineCache, 1, c)
            fineCache[P.WAY_KEEP + 1] = nil
        end
        c.pa, c.pb, c.t, c.f = p.a, p.b, t, ok and f or false
    end
    local f = c.f
    if not f or f.clear then return w end
    if not w.via and f.reached then w.cost = math.max(w.cost, f.yards) end
    w.a, w.b, w.via, w.fine = f.a, f.b, true, true
    return w
end

function P.Way(p, q)
    local w = coarseWay(p, q)
    if w and OMQ.PathRaster and not (OMQDB and OMQDB.pathFineOff) then steer(p, w) end
    return w
end
function P._ResetWay() wayCache, fineCache = {}, {} end
function P._Reset()
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
    out[#out + 1] = "searches so far: " .. P.stats.searches .. ", fine searches: " .. (P.stats.fine or 0)
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
