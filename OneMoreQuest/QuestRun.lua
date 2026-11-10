-- One More Quest: Quest Run (decision 465)
-- A dad (alone or in a group) picks how many quests he wants to do now: 1, 3, 5 or 7. OMQ looks at his quest
-- log and at the quests he could pick up nearby and plans the shortest way: first the quest giver of a new
-- quest, then the place of its objectives. A quest counts as done when its objectives are fulfilled; turning it
-- in is not part of the run. A small second arrow above the quest tracker leads from stop to stop.
--   Candidates: quests of my log with open objectives and known places (Data/QuestPlaces.lua; for quests the data
--   does not know the client's own point on my map, C_QuestLog.GetQuestsOnMap), plus new quests I can take
--   (NextQuest.CanTake, at most LEVEL_ABOVE levels above me, never from a profession or reputation, repeatable or
--   in a dungeon; from an item only when a named mob drops it, decision 508: the pick up stop is the mob's place
--   and stays until the quest is accepted), at most as many new ones as my quest log has room for. Elite (group) quests
--   only in a group. Only places on my continent; another zone costs ZONE_PENALTY yards.
--   Plan: start with the cheapest quest, then always add the quest that makes the way the least longer (the
--   giver before the objectives), then improve the order (reversing parts, moving single stops) while it gets
--   shorter. Distances are the ways over the land of Path.lua (469: around mountains, lakes and cliffs, flights
--   I know), straight lines only where the walking network has no data. Only the way counts.
--   While the run goes, the rest of the stops is sorted again from where I stand whenever a stop is done.
-- In a group only quests every dad with the addon has (or every one of them can take) are used. The dad who
-- starts plans the route and sends it to the others; the others report when they picked up a quest or fulfilled
-- its objectives; a stop is done when every dad is done with it. (quest IDs in base 36)
--   RN|proto|s|run|leader|quests         a new run: the stops follow
--   RN|proto|p|run|i|kind|qid|a|b|inst|map|new   stop i (kind p = pick up, o = objectives)
--   RN|proto|o|run|done|order|dropped    the state: quests done, the open stops in their order, quests left out
--   RN|proto|c|run|guid|qid|state        a dad reports: p = picked up, d = objectives fulfilled
--   RN|proto|x|run|qid                   a dad asks the leader to skip that quest
--   RN|proto|e|run                       the leader ended the run
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local R = {}
OMQ.QuestRun = R

R.SIZES = { 1, 3, 5, 7 }
R.ZONE_PENALTY, R.FAR = 300, 1e6
R.NEW_SOLO, R.NEW_GROUP = 40, 20      -- the nearest new quests looked at (in a group they must fit in one message)
R.SPOTS = 4                           -- objective places tried per quest (the ones with the most spawns)
R.OBJ_RADIUS, R.PICK_RADIUS = 40, 12  -- "you are there"
R.LEVEL_ABOVE = 2
R.SPEED = 7                           -- yards per second on foot, for the minutes in the preview
R.LOG_MAX = 20
R.TICK = 0.5

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return GetTime() end
local function data(id) return OMQ.QuestPlaces and OMQ.QuestPlaces[id] end
local function has(flags, b) return flags ~= nil and math.floor(flags / b) % 2 == 1 end
local function NQ() return OMQ.NextQuest end
local function number(v) return type(v) == "number" and not isSecret(v) end

----------------------------------------------------------------------
-- Places and distances
----------------------------------------------------------------------
-- a place: { a, b, inst, map } in world yards
local function placeOf(spot)
    local w = NQ().World(spot)
    if not w then return nil end
    return { a = w[1], b = w[2], inst = w[3], map = spot[1], w = spot[4] or 1 }
end
function R.Dist(p, q)
    if not (p and q) then return 0 end
    if p.inst ~= q.inst then return R.FAR end
    -- the way over the land when the walking network knows it (469), else straight + zone penalty
    local path = OMQ.Path
    if path and path.Enabled() then
        local c = path.Cost(p, q)
        if c then return c end
    end
    local d = math.sqrt((p.a - q.a) ^ 2 + (p.b - q.b) ^ 2)
    if p.map and q.map and p.map ~= q.map then d = d + R.ZONE_PENALTY end
    return d
end
local dist = R.Dist

-- the objective places of a quest: the ones with the most spawns first
local function objPlaces(spots)
    local list = {}
    for _, s in ipairs(spots or {}) do list[#list + 1] = s end
    table.sort(list, function(x, y) return (x[4] or 1) > (y[4] or 1) end)
    local out, top = {}, list[1] and (list[1][4] or 1) or 1
    for _, s in ipairs(list) do
        if #out >= R.SPOTS then break end
        if (s[4] or 1) * 2.5 >= top then
            local p = placeOf(s)
            if p then out[#out + 1] = p end
        end
    end
    return out
end

-- the objective places of a new quest near me; a drop quest without objective places (bring the item) is done
-- where its mob is (decision 508)
local function newSpots(id, d, pos, pick)
    local out = {}
    if d[9] then
        for _, p in ipairs(objPlaces(d[9])) do if dist(pos, p) < R.FAR then out[#out + 1] = p end end
    elseif pick and NQ().Drop(id) then out[1] = pick end
    return out
end

-- the client's own point of a quest on my map (quests the data does not know)
local function mapPoint(qid, pos)
    if not (pos and pos.map and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return nil end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, pos.map)
    if not ok or type(list) ~= "table" then return nil end
    for _, q in ipairs(list) do
        if type(q) == "table" and q.questID == qid and number(q.x) and number(q.y) then
            return placeOf({ pos.map, q.x * 100, q.y * 100, 1 })
        end
    end
end

----------------------------------------------------------------------
-- Quests
----------------------------------------------------------------------
local function myLog()
    if OMQ.QuestSync and OMQ.QuestSync.ReadLog then return OMQ.QuestSync:ReadLog() end
    return {}, {}
end
R.MyLog = myLog
local function complete(id) return NQ().IsComplete(id) end

function R.IsElite(id)
    local CQ = C_QuestLog
    if not (CQ and CQ.GetQuestTagInfo) then return false end
    local ok, info = pcall(CQ.GetQuestTagInfo, id)
    if not ok or type(info) ~= "table" then return false end
    if info.isElite == true then return true end
    return info.tagID == 1 or info.tagID == 81 or info.tagID == 62     -- group, dungeon, raid
end

function R.FreeSlots(log)
    local n = 0
    for _ in pairs(log or {}) do n = n + 1 end
    local max = R.LOG_MAX
    local CQ = C_QuestLog
    if CQ and CQ.GetMaxNumQuestsCanAccept then
        local ok, m = pcall(CQ.GetMaxNumQuestsCanAccept)
        if ok and number(m) and m > 0 then max = m end
    end
    return math.max(0, max - n)
end

local titleAsked = {}
function R.Title(id, titles)
    local t = titles and titles[id]
    if not t and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, r = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and type(r) == "string" and r ~= "" and not isSecret(r) then t = r end
        if not t and not titleAsked[id] and C_QuestLog.RequestLoadQuestByID then
            titleAsked[id] = true
            pcall(C_QuestLog.RequestLoadQuestByID, id)
        end
    end
    local d = data(id)
    return t or (d and d[1]) or ("Quest " .. id)
end

-- the first open objective in the words of the client
function R.OpenObjective(id)
    local CQ = C_QuestLog
    if not (CQ and CQ.GetQuestObjectives) then return nil end
    local ok, list = pcall(CQ.GetQuestObjectives, id)
    if not ok or type(list) ~= "table" then return nil end
    for _, o in ipairs(list) do
        if type(o) == "table" and not o.finished and type(o.text) == "string" and o.text ~= "" and not isSecret(o.text) then
            return o.text
        end
    end
end

-- The candidates. opts: { log, titles, members, doneBy = guid -> set, availBy = guid -> set, solo }
-- returns the list { id, new, pick = place, spots = { place } } and the room for new quests
function R.Pool(pos, opts)
    opts = opts or {}
    local log = opts.log or {}
    local members = opts.members or {}
    local solo = #members == 0
    local out = {}
    local skip = opts.skip or {}
    -- quests of my log (in a group: the ones every dad has)
    local ids = {}
    if solo then for id in pairs(log) do ids[#ids + 1] = id end
    else ids = NQ().Common(log, members) end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local d = data(id)
        local doneAll = complete(id)
        for _, u in ipairs(members) do
            local set = opts.doneBy and opts.doneBy[u.guid]
            if not (set and set[id]) then doneAll = false end
        end
        if not skip[id] and not doneAll and not (d and has(d[13], 8)) and not (solo and R.IsElite(id)) then
            local spots
            if d and d[9] then spots = objPlaces(d[9]) end
            if not spots or #spots == 0 then
                local p = mapPoint(id, pos)
                spots = p and { p } or {}
            end
            local near = {}
            for _, p in ipairs(spots) do if dist(pos, p) < R.FAR then near[#near + 1] = p end end
            if #near > 0 and (d and d[9] or not d) then out[#out + 1] = { id = id, spots = near } end
        end
    end
    -- new quests I could pick up
    local free = R.FreeSlots(log)
    if free > 0 and OMQ.QuestPlaces then
        local level = UnitLevel and tonumber((UnitLevel("player"))) or 1
        local news = {}
        for id, d in pairs(OMQ.QuestPlaces) do
            local starts = not skip[id] and NQ().Starts(id, true)
            if starts and (d[9] or not d[7]) and (d[3] or 0) <= level + R.LEVEL_ABOVE and NQ().CanTake(id, nil, log, nil, true) then
                local ok = true
                for _, u in ipairs(members) do
                    local set = opts.availBy and opts.availBy[u.guid]
                    if not (set and set[id]) then ok = false; break end
                end
                if ok and solo and R.IsElite(id) then ok = false end
                if ok then
                    local best, bd
                    for _, s in ipairs(starts) do
                        local p = placeOf(s)
                        local dd = p and dist(pos, p)
                        if dd and dd < R.FAR and (not bd or dd < bd) then best, bd = p, dd end
                    end
                    if best then news[#news + 1] = { id = id, new = true, pick = best, d = bd } end
                end
            end
        end
        table.sort(news, function(x, y) if x.d ~= y.d then return x.d < y.d end return x.id < y.id end)
        local max = solo and R.NEW_SOLO or R.NEW_GROUP
        for i = 1, math.min(#news, max) do
            local e = news[i]
            e.spots = newSpots(e.id, data(e.id), pos, e.pick)
            if #e.spots > 0 then out[#out + 1] = e end
        end
    end
    -- follow-up quests (decision 466): behind a quest of the pool (alone also behind a new one) or behind a quest of
    -- my log whose objectives are fulfilled already (a "door": it does not count, only its follow-up does)
    local roots = {}
    for _, e in ipairs(out) do if solo or not e.new then roots[#roots + 1] = { id = e.id, door = false } end end
    for _, id in ipairs(ids) do
        local doneAll = complete(id)
        for _, u in ipairs(members) do
            local set = opts.doneBy and opts.doneBy[u.guid]
            if not (set and set[id]) then doneAll = false end
        end
        if doneAll then roots[#roots + 1] = { id = id, door = true } end
    end
    for _, f in ipairs(R.Follows(pos, roots, log, opts, solo)) do out[#out + 1] = f end
    return out, free
end

-- the follow-up quests of a quest: the quests that name it as a pre-quest (built once per quest data)
local followsOf, followsData = {}, nil
function R.FollowsOf(id)
    if followsData ~= OMQ.QuestPlaces then
        followsData, followsOf = OMQ.QuestPlaces, {}
        for qid, d in pairs(OMQ.QuestPlaces or {}) do
            for _, list in ipairs({ d[10] or {}, d[11] or {} }) do
                for _, p in ipairs(list) do
                    followsOf[p] = followsOf[p] or {}
                    table.insert(followsOf[p], qid)
                end
            end
        end
        for _, l in pairs(followsOf) do table.sort(l) end
    end
    return followsOf[id] or {}
end

local function nearestPlace(spots, pos)
    local best, bd
    for _, s in ipairs(spots or {}) do
        local p = placeOf(s)
        local dd = p and dist(pos, p)
        if dd and dd < R.FAR and (not bd or dd < bd) then best, bd = p, dd end
    end
    return best
end

-- the follow-ups behind roots { id, door }, up to CHAIN_DEPTH quests deep: { id, new, follow, parent, door, turnin, pick, spots }
R.CHAIN_DEPTH = 3
function R.Follows(pos, roots, log, opts, solo)
    local out, seen = {}, {}
    local level = UnitLevel and tonumber((UnitLevel("player"))) or 1
    local queue = {}
    for _, r in ipairs(roots) do queue[#queue + 1] = { id = r.id, door = r.door, depth = 0, chain = { [r.id] = true } }; seen[r.id] = true end
    local qi = 1
    while queue[qi] do
        local a = queue[qi]; qi = qi + 1
        local da = data(a.id)
        local turnin = da and da[8] and nearestPlace(da[8], pos)
        if turnin and a.depth < R.CHAIN_DEPTH then
            for _, b in ipairs(R.FollowsOf(a.id)) do
                local d = data(b)
                local starts = d and NQ().Starts(b, true)
                if not seen[b] and not log[b] and not (opts.skip and opts.skip[b]) and starts and (d[9] or not d[7])
                   and (d[3] or 0) <= level + R.LEVEL_ABOVE and NQ().CanTake(b, nil, log, a.chain, true)
                   and not (solo and R.IsElite(b)) then
                    local ok = true
                    for _, u in ipairs(opts.members or {}) do
                        local set = opts.laterBy and opts.laterBy[u.guid]
                        if not (set and set[b]) then ok = false; break end
                    end
                    local pick = ok and nearestPlace(starts, pos)
                    if pick then
                        local spots = newSpots(b, d, pos, pick)
                        if #spots > 0 then
                            seen[b] = true
                            out[#out + 1] = { id = b, new = true, follow = true, parent = a.id, door = a.door,
                                              turnin = turnin, pick = pick, spots = spots }
                            local chain = {}
                            for k in pairs(a.chain) do chain[k] = true end
                            chain[b] = true
                            queue[#queue + 1] = { id = b, door = false, depth = a.depth + 1, chain = chain }
                        end
                    end
                end
            end
        end
    end
    return out
end

-- the follow-ups a group run asks the others about: behind the quests every dad has
function R.ChainIds(pos, log, members)
    local roots = {}
    for _, id in ipairs(NQ().Common(log, members)) do roots[#roots + 1] = { id = id, door = false } end
    local out = {}
    for _, f in ipairs(R.Follows(pos, roots, log, { members = {} }, false)) do out[#out + 1] = f.id end
    return out
end

-- the nearest new quests that a group run asks the others about (before the pool)
function R.NewNear(pos, log, max)
    local opts = { log = log, members = {} }
    local list = {}
    local level = UnitLevel and tonumber((UnitLevel("player"))) or 1
    for id, d in pairs(OMQ.QuestPlaces or {}) do
        local starts = NQ().Starts(id, true)
        if starts and (d[9] or not d[7]) and (d[3] or 0) <= level + R.LEVEL_ABOVE and NQ().CanTake(id, nil, log, nil, true) then
            local bd
            for _, s in ipairs(starts) do
                local p = placeOf(s)
                local dd = p and dist(pos, p)
                if dd and dd < R.FAR and (not bd or dd < bd) then bd = dd end
            end
            if bd then list[#list + 1] = { id = id, d = bd } end
        end
    end
    table.sort(list, function(x, y) if x.d ~= y.d then return x.d < y.d end return x.id < y.id end)
    local out = {}
    for i = 1, math.min(#list, max or R.NEW_GROUP) do out[i] = list[i].id end
    return out, opts
end

----------------------------------------------------------------------
-- The planner (pure: places in, stops out)
----------------------------------------------------------------------
-- a stop: { qid, kind = "p" (pick up) | "o" (objectives), place }
local function pathCost(pos, stops)
    local c, prev = 0, pos
    for _, s in ipairs(stops) do c = c + dist(prev, s.place); prev = s.place end
    return c
end
R.PathCost = pathCost

-- every pick up before the objectives of its quest, a turn-in after its objectives, the pick up of a follow-up
-- after the turn-in of its pre-quest (s.after)
-- Dungeon Run (476): a stop with needs = { qid } comes after every stop of those quests (their whole chain step),
-- a "w" stop (follow the quest in the log) is a pick up
local function valid(stops)
    local seenObj, seenT = {}, {}
    local total, seen, anyNeeds = nil, nil, false
    for _, s in ipairs(stops) do if s.needs then anyNeeds = true; break end end
    if anyNeeds then
        total, seen = {}, {}
        for _, s in ipairs(stops) do total[s.qid] = (total[s.qid] or 0) + 1 end
    end
    for _, s in ipairs(stops) do
        local q = s.qid
        if s.needs then
            for _, n in ipairs(s.needs) do
                if total[n] and (seen[n] or 0) < total[n] then return false end
            end
        end
        if seen then seen[q] = (seen[q] or 0) + 1 end
        if s.kind == "o" or s.kind == "w" then             -- "w" (follow the log) comes after its pick up like objectives
            if seenT[q] then return false end
            seenObj[q] = true
        elseif s.kind == "t" then
            seenT[q] = true
        else
            if seenObj[q] or seenT[q] then return false end
            if s.after and not seenT[s.after] then return false end
        end
    end
    return true
end
R._valid = valid

-- better order: reverse parts and move single stops while the way gets shorter
function R.Improve(pos, stops, maxIter)
    local n = #stops
    if n < 2 then return stops end
    -- the ways between the same two places are asked once (long Dungeon Runs, 476)
    local memo = setmetatable({}, { __mode = "k" })
    local function d2(p, q)
        if not (p and q) then return 0 end
        local m = memo[p]
        if not m then m = {}; memo[p] = m end
        local v = m[q]
        if not v then v = dist(p, q); m[q] = v end
        return v
    end
    local function pathCost(from, list)
        local c, prev = 0, from
        for _, s in ipairs(list) do c = c + d2(prev, s.place); prev = s.place end
        return c
    end
    local best = pathCost(pos, stops)
    maxIter = maxIter or (n > 40 and 2 or n > 16 and 4 or 60)
    for _ = 1, maxIter do
        local better = false
        for i = 1, n - 1 do
            for j = i + 1, n do
                local t = {}
                for k = 1, i - 1 do t[#t + 1] = stops[k] end
                for k = j, i, -1 do t[#t + 1] = stops[k] end
                for k = j + 1, n do t[#t + 1] = stops[k] end
                local c = pathCost(pos, t)
                if c < best - 0.01 and valid(t) then stops, best, better = t, c, true end
            end
        end
        for i = 1, n do
            for j = 1, n do
                if i ~= j then
                    local t = {}
                    for k = 1, n do if k ~= i then t[#t + 1] = stops[k] end end
                    table.insert(t, j, stops[i])
                    local c = pathCost(pos, t)
                    if c < best - 0.01 and valid(t) then stops, best, better = t, c, true end
                end
            end
        end
        if not better then break end
    end
    return stops
end

-- the cheapest way to add a follow-up: the turn-in of its pre-quest (unless planned already), then its pick up,
-- then its objectives. Returns the added yards and the new list of stops.
local function insertAt(list, i, x)
    local t = {}
    for k = 1, i do t[k] = list[k] end
    t[#t + 1] = x
    for k = i + 1, #list do t[#t + 1] = list[k] end
    return t
end
function R.TryFollow(pos, stops, e, sp)
    local base = pathCost(pos, stops)
    local tAt
    for idx, s in ipairs(stops) do if s.kind == "t" and s.qid == e.parent then tAt = idx end end
    local P = { qid = e.id, kind = "p", place = e.pick, after = e.parent }
    local O = { qid = e.id, kind = "o", place = sp }
    local m = #stops
    local bestC, bestArr
    local function consider(arr)
        if valid(arr) then
            local c = pathCost(pos, arr) - base
            if not bestC or c < bestC - 0.01 then bestC, bestArr = c, arr end
        end
    end
    if tAt then
        for j = tAt, m do
            local a1 = insertAt(stops, j, P)
            for k = j + 1, m + 1 do consider(insertAt(a1, k, O)) end
        end
    else
        local T = { qid = e.parent, kind = "t", place = e.turnin }
        for i = 0, m do
            local a0 = insertAt(stops, i, T)
            for j = i + 1, m + 1 do
                local a1 = insertAt(a0, j, P)
                for k = j + 1, m + 2 do consider(insertAt(a1, k, O)) end
            end
        end
    end
    return bestC, bestArr
end

-- choose n quests of the pool and their order. Returns { stops, quests = { entry }, length }
function R.Plan(pos, pool, n, free)
    local stops, chosen, used = {}, {}, {}
    local newCount = 0
    free = free or math.huge
    for _ = 1, n do
        local best
        for _, e in ipairs(pool) do
            if e.follow then
                if not used[e.id] and (e.door or used[e.parent]) then
                    for _, sp in ipairs(e.spots) do
                        local c, arr = R.TryFollow(pos, stops, e, sp)
                        if c and (not best or c < best.c - 0.01) then best = { c = c, e = e, arr = arr } end
                    end
                end
            elseif not used[e.id] and (not e.new or newCount < free) then
                for _, sp in ipairs(e.spots) do
                    local m = #stops
                    local function at(i) if i == 0 then return pos end return stops[i] and stops[i].place end
                    local function seg(i, x)      -- yards added by x between stop i and stop i + 1
                        local nxt = at(i + 1)
                        if not nxt then return dist(at(i), x) end
                        return dist(at(i), x) + dist(x, nxt) - dist(at(i), nxt)
                    end
                    for i = 0, m do
                        if not e.new then
                            local c = seg(i, sp)
                            if not best or c < best.c - 0.01 then best = { c = c, e = e, sp = sp, i = i } end
                        else
                            for j = i, m do
                                local c
                                if j == i then
                                    local nxt = at(i + 1)
                                    c = dist(at(i), e.pick) + dist(e.pick, sp) + (nxt and (dist(sp, nxt) - dist(at(i), nxt)) or 0)
                                else
                                    c = seg(i, e.pick) + seg(j, sp)
                                end
                                if not best or c < best.c - 0.01 then best = { c = c, e = e, sp = sp, i = i, j = j } end
                            end
                        end
                    end
                end
            end
        end
        if not best then break end
        local e = best.e
        used[e.id] = true
        chosen[#chosen + 1] = e
        local o = { qid = e.id, kind = "o", place = best.sp }
        if best.arr then
            stops = best.arr                      -- a follow-up: turn-in, pick up and objectives already placed
        elseif e.new then
            newCount = newCount + 1
            table.insert(stops, best.j + 1, o)
            table.insert(stops, best.i + 1, { qid = e.id, kind = "p", place = e.pick })
        else
            table.insert(stops, best.i + 1, o)
        end
    end
    stops = R.Improve(pos, stops)
    return { stops = stops, quests = chosen, length = pathCost(pos, stops) }
end

-- how many quests fit at most, for the buttons
function R.Fit(pool, free)
    local logN, newN, folN = 0, 0, 0
    for _, e in ipairs(pool) do
        if e.follow then folN = folN + 1 elseif e.new then newN = newN + 1 else logN = logN + 1 end
    end
    return logN + math.min(newN, free or newN) + folN
end

----------------------------------------------------------------------
-- Preparing a run (the window asks, the vote starts one at once)
----------------------------------------------------------------------
local prep = nil      -- { pos, log, titles, members, doneBy, availBy, pool, free, ready, skip }
local run = nil       -- the running run
R._state = function() return prep, run end

local function members()
    local m = NQ().Members()
    return m
end

local function finishPrep(st, after)
    local doneBy, availBy, laterBy = {}, {}, {}
    for _, u in ipairs(st.members) do
        local r = st.replies and st.replies[u.guid]
        if r then doneBy[u.guid] = r.done; availBy[u.guid] = r.avail; laterBy[u.guid] = r.later end
    end
    st.doneBy, st.availBy, st.laterBy = doneBy, availBy, laterBy
    st.pool, st.free = R.Pool(st.pos, st)
    st.ready = true
    OMQ:Fire("QUEST_RUN_PREP")
    if after then after(st) end
end

-- prepares the candidates; after(st) runs when they are known (at once alone, after the answers in a group)
function R:Prepare(after)
    if not OMQ.QuestPlaces then OMQ:Print("Quest Run: no quest data"); return nil end
    local pos = NQ().MyPos()
    if not pos then OMQ:Print("Quest Run: no position here"); return nil end
    local log, titles = myLog()
    local st = { pos = pos, log = log, titles = titles, members = members(), replies = {}, skip = {} }
    prep = st
    if #st.members == 0 then finishPrep(st, after); return st end
    local ids = R.NewNear(pos, log, R.NEW_GROUP)
    NQ().Ask(st, ids, function(s) if prep == s then finishPrep(s, after) end end, R.ChainIds(pos, log, st.members))
    OMQ:Fire("QUEST_RUN_PREP")
    return st
end

function R:Prep() return prep end

-- the plan for n quests of the prepared pool
function R:PlanFor(n)
    if not (prep and prep.ready) then return nil end
    local plan = R.Plan(prep.pos, prep.pool, n, prep.free)
    plan.n = n
    prep.plan = plan
    return plan
end

-- the preview: leave out a quest and take the next best instead
function R:SkipPlanned(qid)
    if not (prep and prep.ready and prep.plan) then return nil end
    prep.skip[qid] = true
    local pool = {}
    for _, e in ipairs(prep.pool) do if not prep.skip[e.id] then pool[#pool + 1] = e end end
    local plan = R.Plan(prep.pos, pool, prep.plan.n, prep.free)
    plan.n = prep.plan.n
    prep.plan = plan
    return plan
end

----------------------------------------------------------------------
-- The running run
----------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    n = math.floor(n)
    if n == 0 then return "0" end
    local t = ""
    while n > 0 do local r = n % 36; t = DIGITS:sub(r + 1, r + 1) .. t; n = math.floor(n / 36) end
    return t
end
local function list36(t) local o = {} for _, v in ipairs(t) do o[#o + 1] = b36(v) end return table.concat(o, ",") end
local function parse36(text)
    local o = {}
    for w in tostring(text or ""):gmatch("[%w]+") do local n = tonumber(w, 36); if n then o[#o + 1] = n end end
    return o
end

local function me() return OMQ:GetSelf() end
local function myGuid() local m = me(); return m and m.guid end
function R:Active() return run ~= nil end
function R:Run() return run end
function R:IsLeader() return run ~= nil and run.leader == myGuid() end

local function save()
    if not OMQ.db then return end
    local g = myGuid()
    if not g then return end
    OMQ.db.questRun = OMQ.db.questRun or {}
    if not run then OMQ.db.questRun[g] = nil; return end
    local s = { id = run.id, leader = run.leader, started = run.started, total = run.total, group = run.group,
                quests = {}, stops = {}, kind = run.kind, dungeon = run.dungeon, info = run.info, zone = run.zone, allow = run.allow }
    for qid, q in pairs(run.quests) do s.quests[#s.quests + 1] = { qid, q.new and 1 or 0, q.done and 1 or 0, q.picked and 1 or 0, q.dropped and 1 or 0, q.follow or 0, q.goal } end
    for _, st in ipairs(run.stops) do s.stops[#s.stops + 1] = { st.qid, st.kind, st.place.a, st.place.b, st.place.inst, st.place.map, st.i, st.after, st.goal, st.needs } end
    OMQ.db.questRun[g] = s
end

-- the quest tracker keeps the cards of the open quests of the run, the next stop's quest in front
local function pin()
    if not (OMQ.QTrack and OMQ.QTrack.Pin) then return end
    local set = {}
    if run then
        for qid, q in pairs(run.quests) do if not q.done and not q.dropped then set[qid] = true end end
        for _, s in ipairs(run.stops) do if s.kind == "t" then set[s.qid] = true end end   -- still to turn in (466)
    end
    OMQ.QTrack:Pin(set, run and run.stops[1] and run.stops[1].qid or nil)
end
local function fire() pin(); OMQ:Fire("QUEST_RUN_CHANGED"); save() end
local closeRun

-- counts for the bar: done and all quests of the run (left out ones do not count)
function R:Counts()
    if not run then return 0, 0 end
    local done, all = 0, 0
    for _, q in pairs(run.quests) do
        if not q.dropped then all = all + 1; if q.done then done = done + 1 end end
    end
    return done, all
end

function R:Current() return run and run.stops[1] or nil end

local function newRun(id, leader)
    return { id = id, leader = leader, started = time and time() or 0, quests = {}, stops = {}, all = {},
             reports = {}, total = 0, group = false, nextI = 1, doors = {} }
end

local function addStop(r, s)
    s.i = s.i or r.nextI
    r.nextI = math.max(r.nextI, s.i + 1)
    r.all[s.i] = s
    r.stops[#r.stops + 1] = s
    if s.kind == "t" then                         -- a turn-in: a quest of the run, or a door that does not count (466)
        if s.goal then                            -- Dungeon Run (476): the pre-quest counts when turned in
            local q = r.quests[s.qid]
            if not q then q = { qid = s.qid, new = false, done = false }; r.quests[s.qid] = q end
            q.goal = s.goal
        elseif not r.quests[s.qid] then r.doors[s.qid] = true end
        return
    end
    local q = r.quests[s.qid]
    if not q then q = { qid = s.qid, new = false, done = false }; r.quests[s.qid] = q end
    if s.goal then q.goal = s.goal end
    if s.kind == "p" or s.kind == "w" then q.new = true; q.follow = s.after end
end

local function sendStop(s)
    OMQ:Send("RN", "p", run.id, tostring(s.i), s.kind, b36(s.qid), string.format("%.1f", s.place.a), string.format("%.1f", s.place.b),
        tostring(s.place.inst or 0), tostring(s.place.map or 0), s.after and b36(s.after) or "")
end

local function sendState()
    if not (run and run.group and R:IsLeader()) then return end
    local done, dropped, order = {}, {}, {}
    for qid, q in pairs(run.quests) do
        if q.done then done[#done + 1] = qid end
        if q.dropped then dropped[#dropped + 1] = qid end
    end
    table.sort(done); table.sort(dropped)
    for _, s in ipairs(run.stops) do order[#order + 1] = s.i end
    OMQ:Send("RN", "o", run.id, list36(done), list36(order), list36(dropped))
end

-- starts the prepared plan (the window's Start button or the vote)
function R:Start(plan)
    plan = plan or (prep and prep.plan)
    if not (plan and #plan.stops > 0) then
        OMQ:Print((plan and plan.kind == "dungeon") and "Dungeon Run: no quest to collect" or (plan and plan.kind == "area") and "Area Run: no quest in this zone" or "Quest Run: no quest fits here")
        return false
    end
    if run then closeRun("replaced") end      -- one run at a time (476)
    local g = myGuid() or "?"
    run = newRun(tostring(math.random(100000, 999999)), g)
    run.pool = prep and prep.pool or {}
    run.free = prep and prep.free
    run.skip = prep and prep.skip or {}
    run.members = prep and prep.members or {}
    run.group = #run.members > 0
    if plan.kind == "dungeon" then             -- Dungeon Run (476): every dad has his own route, no leader
        run.kind, run.dungeon, run.info = "dungeon", plan.dungeon, plan.info
        run.members, run.group, run.pool = {}, false, {}
    elseif plan.kind == "area" then            -- Area Run (491): one route, in a group from the dad who starts
        run.kind, run.zone, run.info, run.allow = "area", plan.zone, plan.info, plan.allow or {}
        run.members, run.pool = plan.members or {}, {}
        run.group = #run.members > 0
    end
    for _, s in ipairs(plan.stops) do addStop(run, { qid = s.qid, kind = s.kind, place = s.place, after = s.after, goal = s.goal, needs = s.needs, late = s.late }) end
    run.total = 0
    for _ in pairs(run.quests) do run.total = run.total + 1 end
    run.startedAt = now()
    prep = nil
    if run.group then
        OMQ:Send("RN", "s", run.id, g, tostring(run.total), run.kind or "", tostring(run.zone or ""))
        for _, s in ipairs(run.stops) do sendStop(s) end
        sendState()
    end
    R:Tick()
    fire()
    return true
end

-- the next best quest instead of this one (the Skip button); in a group only the leader changes the plan
function R:Skip(qid)
    if not run then return false end
    if run.group and not R:IsLeader() then
        OMQ:Send("RN", "x", run.id, b36(qid))
        return true
    end
    local q = run.quests[qid]
    if not q or q.done then return false end
    if run.kind == "dungeon" or run.kind == "area" then   -- Dungeon Run (476), Area Run (491): the quest and what waits for it go
        R.DropWithDependents(run, qid)
        local pos = NQ().MyPos()
        if pos then run.stops = R.Resort(pos, run.stops, 3) end
        sendState()
        fire()
        return true
    end
    -- the quest and its follow-ups in the run go (decision 466), each one replaced
    local gone, n = { [qid] = true }, 1
    local more = true
    while more do
        more = false
        for id, x in pairs(run.quests) do
            if x.follow and gone[x.follow] and not gone[id] and not x.done and not x.dropped then gone[id] = true; n = n + 1; more = true end
        end
    end
    for id in pairs(gone) do
        run.skip[id] = true
        run.quests[id].dropped = true
        for k = #run.stops, 1, -1 do
            local st = run.stops[k]
            if st.qid == id and st.kind ~= "t" then table.remove(run.stops, k) end
        end
    end
    R.DropTurnins(run)
    -- the next best quest from where I stand
    local pos = NQ().MyPos()
    local used = {}
    for id in pairs(run.quests) do used[id] = true end
    local pool = {}
    for _, e in ipairs(run.pool or {}) do if not used[e.id] and not run.skip[e.id] then pool[#pool + 1] = e end end
    local log = myLog()
    local news = 0
    for _, x in pairs(run.quests) do if x.new and not x.picked and not x.done and not x.dropped then news = news + 1 end end
    local free = math.max(0, R.FreeSlots(log) - news)
    local extra = pos and R.Plan(pos, pool, n, free)
    local got = extra and #extra.quests or 0
    if got > 0 then
        for _, s in ipairs(extra.stops) do
            local dup = false
            if s.kind == "t" then for _, x in ipairs(run.stops) do if x.kind == "t" and x.qid == s.qid then dup = true end end end
            if not dup then
                addStop(run, { qid = s.qid, kind = s.kind, place = s.place, after = s.after })
                if run.group then sendStop(run.stops[#run.stops]) end
            end
        end
        run.quests[extra.quests[1].id].replaces = qid
        run.total = run.total + got
    end
    if got < n then
        OMQ:Print("Quest Run: no other quest fits - " .. (n - got == 1 and "one quest" or ((n - got) .. " quests")) .. " less")
    end
    if pos then run.stops = R.Improve(pos, run.stops) end
    sendState()
    fire()
    return true
end

-- Dungeon Run (476): a quest goes, and every quest whose stops need it (and theirs)
function R.DropWithDependents(r, qid)
    local gone, more = { [qid] = true }, true
    while more do
        more = false
        for _, st in ipairs(r.stops) do
            if not gone[st.qid] and st.needs then
                for _, n in ipairs(st.needs) do
                    if gone[n] then gone[st.qid] = true; more = true; break end
                end
            end
        end
    end
    for id in pairs(gone) do
        local x = r.quests[id]
        if x and not x.done then x.dropped = true end
        if r.skip then r.skip[id] = true end
    end
    for k = #r.stops, 1, -1 do
        local x = r.quests[r.stops[k].qid]
        if gone[r.stops[k].qid] and not (x and x.done) then table.remove(r.stops, k) end
    end
    R.DropTurnins(r)
    return gone
end

-- a turn-in stays only while a follow-up of the run still waits for it (decision 466)
function R.DropTurnins(r)
    for k = #r.stops, 1, -1 do
        local st = r.stops[k]
        if st.kind == "t" then
            local q = r.quests[st.qid]
            local needed = q ~= nil and q.goal == "turnin" and not q.done and not q.dropped      -- a pre-quest of a Dungeon Run (476)
            for _, x in ipairs(r.stops) do if x.kind == "p" and x.after == st.qid then needed = true end end
            if not needed then table.remove(r.stops, k) end
        end
    end
end

-- the open stops sorted again from where I stand (the Area Run keeps the room in the quest log, 490)
function R.Resort(pos, stops, iter)
    if run and run.kind == "area" and OMQ.AreaRun then return OMQ.AreaRun.Resort(pos, stops) end
    if not iter and run and run.kind == "dungeon" then iter = #stops > 40 and 1 or 2 end
    return R.Improve(pos, stops, iter)
end

-- Area Run (491): quests that came up during the run (a level up, a hint taken) join it
function R:AddStops(stops)
    if not run or (run.group and not R:IsLeader()) then return 0 end
    local before = {}
    for qid in pairs(run.quests) do before[qid] = true end
    for _, s in ipairs(stops) do
        addStop(run, { qid = s.qid, kind = s.kind, place = s.place, after = s.after, goal = s.goal, needs = s.needs, late = s.late })
        if run.group then sendStop(run.stops[#run.stops]) end
    end
    local n = 0
    for qid in pairs(run.quests) do if not before[qid] then n = n + 1 end end
    run.total = run.total + n
    local pos = NQ().MyPos()
    if pos then run.stops = R.Resort(pos, run.stops) end
    sendState()
    fire()
    return n
end

local function everDone(id)
    local CQ = C_QuestLog
    if CQ and CQ.IsQuestFlaggedCompleted then
        local ok, v = pcall(CQ.IsQuestFlaggedCompleted, id)
        if ok and v == true then return true end
    end
    return false
end

function closeRun(reason)
    if not run then return end
    local wasGroupLeader = run.group and R:IsLeader()
    local r = run
    run = nil
    if OMQ.Guide and OMQ.Guide:Kind() == "run" then OMQ.Guide:Clear() end
    if wasGroupLeader then OMQ:Send("RN", "e", r.id) end
    OMQ:Fire("QUEST_RUN_END", reason, r)
    fire()
end

-- ends the run here (right click on the small arrow, after the question)
function R:End() closeRun("ended") end

local function finish()
    if not run then return end
    local secs = now() - (run.startedAt or now())
    if run.restored and time and run.started then secs = time() - run.started end
    local done = R:Counts()
    local r = run
    run = nil
    if OMQ.Guide and OMQ.Guide:Kind() == "run" then OMQ.Guide:Clear() end
    OMQ:Fire("QUEST_RUN_DONE", done, secs, r)
    fire()
end
R._finish = finish

-- the dads of the run who are still here (one who left the group or went offline no longer holds a stop)
local function present()
    local out = {}
    for _, u in ipairs(run.members or {}) do
        local x = OMQ.users and OMQ.users[u.guid]
        if x and (not OMQ.IsOnline or OMQ:IsOnline(x)) then out[#out + 1] = u end
    end
    return out
end

-- is the quest done (objectives fulfilled) for every dad of the run?
local function doneForAll(qid)
    if not complete(qid) then
        local log = myLog()
        if log[qid] then return false end
        local q = run.quests[qid]
        if not (q and q.wasComplete) then return false end      -- turned in after its objectives were fulfilled
    end
    if not run.group then return true end
    for _, u in ipairs(present()) do
        local rep = run.reports[u.guid]
        if not (rep and (rep[qid] == "d" or rep[qid] == "t")) then return false end
    end
    return true
end
-- turned in (decision 466): gone from the log after its objectives were fulfilled, or done before
local function turnedIn(qid)
    local log = myLog()
    if log[qid] then return false end
    local q = run.quests[qid]
    return (q and q.wasComplete) or (run.wasComplete and run.wasComplete[qid]) or everDone(qid)
end
local function turnedInByAll(qid)
    if not turnedIn(qid) then return false end
    if not run.group then return true end
    for _, u in ipairs(present()) do
        local rep = run.reports[u.guid]
        if not (rep and rep[qid] == "t") then return false end
    end
    return true
end
local function pickedByAll(qid)
    local log = myLog()
    if not log[qid] and not complete(qid) then return false end
    if not run.group then return true end
    for _, u in ipairs(present()) do
        local rep = run.reports[u.guid]
        if not (rep and (rep[qid] == "p" or rep[qid] == "d" or rep[qid] == "t")) then return false end
    end
    return true
end

local function report(qid, state)
    run.sent = run.sent or {}                -- qid -> state sent in this run
    if run.sent[qid] == state then return end
    run.sent[qid] = state
    OMQ:Send("RN", "c", run.id, myGuid() or "?", b36(qid), state)
end

-- the clock: checks the stops, sorts the rest again, ends the run
function R:Tick()
    if not run then return end
    local log = myLog()
    local changed = false
    run.wasComplete = run.wasComplete or {}
    for qid in pairs(run.doors) do if complete(qid) then run.wasComplete[qid] = true end end
    for qid, q in pairs(run.quests) do
        if complete(qid) then q.wasComplete = true end
        if log[qid] then q.inLog = true end
        -- what the others need to know from me
        if run.group and not R:IsLeader() then
            if turnedIn(qid) then report(qid, "t")
            elseif complete(qid) or (q.wasComplete and not log[qid]) then report(qid, "d")
            elseif log[qid] then report(qid, "p") end
        end
    end
    if run.group and not R:IsLeader() then
        for qid in pairs(run.doors) do if turnedIn(qid) then report(qid, "t") end end
    end
    if run.group and not R:IsLeader() then return end        -- the leader decides
    local function removeStops(qid, kinds)
        for k = #run.stops, 1, -1 do
            local s = run.stops[k]
            if s.qid == qid and (not kinds or kinds[s.kind]) then table.remove(run.stops, k) end
        end
    end
    for qid, q in pairs(run.quests) do
        if not q.done and not q.dropped and q.goal then
            -- Dungeon Run (476): a dungeon quest counts when it is in the log, a pre-quest when it is turned in
            local inLog = log[qid] and true or false
            local ever = everDone(qid)
            local grp = run.group                       -- Area Run in a group (491): every dad of the run
            if q.goal == "pick" then
                if inLog or complete(qid) or ever then
                    q.done, q.picked = true, true
                    removeStops(qid)
                    changed = true
                    if OMQ.Sound then OMQ.Sound:Play("update") end
                end
            else
                if q.new and not q.picked and (inLog or complete(qid) or ever) and (not grp or pickedByAll(qid)) then
                    q.picked = true; removeStops(qid, { p = true }); changed = true
                end
                if not q.objDone and (complete(qid) or ever) and (not grp or doneForAll(qid)) then
                    q.objDone = true; removeStops(qid, { o = true }); changed = true
                end
                if (ever or (not inLog and q.wasComplete)) and (not grp or turnedInByAll(qid)) then
                    q.done = true
                    removeStops(qid)
                    for _, x in ipairs(run.stops) do if x.after == qid then x.after = nil end end
                    changed = true
                    if OMQ.Sound then OMQ.Sound:Play("update") end
                elseif q.inLog and not inLog and not q.wasComplete and not ever then
                    R.DropWithDependents(run, qid)            -- abandoned: it and what waits for it go
                    changed = true
                end
            end
        elseif not q.done and not q.dropped then
            if q.new and not q.picked and pickedByAll(qid) then
                q.picked = true
                for k = #run.stops, 1, -1 do
                    local s = run.stops[k]
                    if s.qid == qid and s.kind == "p" then table.remove(run.stops, k) end
                end
                changed = true
            end
            if (not q.new or q.picked) and doneForAll(qid) then
                q.done = true
                for k = #run.stops, 1, -1 do                     -- its turn-in stays for a follow-up (466)
                    local s = run.stops[k]
                    if s.qid == qid and s.kind ~= "t" then table.remove(run.stops, k) end
                end
                changed = true
                if OMQ.Sound then OMQ.Sound:Play("update") end
            elseif q.inLog and not log[qid] and not q.wasComplete then
                q.dropped = true                                   -- abandoned: left out, one quest less
                for k = #run.stops, 1, -1 do if run.stops[k].qid == qid then table.remove(run.stops, k) end end
                -- its follow-ups (and theirs) cannot come any more
                local gone, more = { [qid] = true }, true
                while more do
                    more = false
                    for id, x in pairs(run.quests) do
                        if x.follow and gone[x.follow] and not gone[id] and not x.done and not x.picked and not x.dropped then
                            gone[id], more, x.dropped = true, true, true
                            for k = #run.stops, 1, -1 do if run.stops[k].qid == id then table.remove(run.stops, k) end end
                        end
                    end
                end
                R.DropTurnins(run)
                changed = true
            end
        end
    end
    -- turn-ins (decision 466): done when every dad turned the quest in
    for k = #run.stops, 1, -1 do
        local s = run.stops[k]
        if s.kind == "t" and turnedInByAll(s.qid) then
            table.remove(run.stops, k); changed = true
            for _, x in ipairs(run.stops) do if x.kind == "p" and x.after == s.qid then x.after = nil end end
        end
    end
    local done, all = R:Counts()
    if all == 0 then
        if changed or #run.stops == 0 then
            OMQ:Print("Quest Run: no quest left in the run")
            closeRun("empty")
        end
        return
    end
    if done >= all then sendState(); finish(); return end
    if changed then
        local pos = NQ().MyPos()
        if pos then run.stops = R.Resort(pos, run.stops) end
        sendState()
        fire()
    end
end

-- a pick up of a quest a named mob drops (decision 508): what to do there, else nil
function R.Hunt(qid)
    if data(qid) and data(qid)[7] then return nil end
    if myLog()[qid] then return nil end
    return NQ().DropWhat(qid)
end

-- what the small arrow shows: { qid, kind, title, what, distance, heading, there, place }
function R:Target()
    if not run then return nil end
    local s = run.stops[1]
    if not s then return nil end
    local pos = NQ().MyPos()
    if s.kind == "w" then return R.FollowTarget(s, pos) end
    local view = { qid = s.qid, kind = s.kind, place = s.place, title = R.Title(s.qid) }
    local hunt = s.kind == "p" and R.Hunt(s.qid)
    local near = s.kind ~= "o" and not hunt              -- a named mob walks around: the wide radius (508)
    if pos and pos.inst == s.place.inst then
        view.straight = math.sqrt((s.place.a - pos.a) ^ 2 + (s.place.b - pos.b) ^ 2)
        view.distance = view.straight
        local ha, hb = s.place.a, s.place.b
        -- the way over the land (469): the arrow heads for the next point of the way, the yards are the way's
        local way = OMQ.Path and OMQ.Path.ArrowWays() and OMQ.Path.Way(pos, s.place)
        if way and way.via then
            view.distance, view.via, view.flight = way.cost, true, way.flight
            ha, hb = way.a, way.b
        end
        if OMQ.Arrow then view.heading = OMQ.Arrow.Heading(ha - pos.a, hb - pos.b) end
        local calm = OMQ.Arrow and OMQ.Arrow.CALM or 25
        view.near = view.straight <= calm and view.distance <= calm + 10 or nil       -- decision 477
    end
    local inside = false
    if s.kind == "o" and C_Minimap and C_Minimap.IsInsideQuestBlob then
        local ok, v = pcall(C_Minimap.IsInsideQuestBlob, s.qid)
        inside = ok and v == true and not isSecret(v)
    end
    local radius = near and R.PICK_RADIUS or R.OBJ_RADIUS
    view.there = inside or (view.straight ~= nil and view.straight <= radius)
    if s.kind == "p" then
        view.what = "pick up the quest"
        local q = run.quests[s.qid]
        if q and q.follow then view.what = "pick up the follow-up of " .. R.Title(q.follow) end
        if hunt then view.what, view.hunt = hunt, true end
    elseif s.kind == "t" then
        local nxt = R.FollowUpIn(run, s.qid)
        view.what = "turn in" .. (nxt and (", then pick up " .. R.Title(nxt)) or "")
        if not nxt and run.kind == "dungeon" then view.what = "turn in the pre-quest" end
    else view.what = R.OpenObjective(s.qid) or "objectives" end
    return view
end

-- Dungeon Run (476): the steps between a known chain start and the dungeon quest are not in the data. The small
-- arrow points at the game's own map point of a quest I picked up during the run that the data does not know
-- (the next step of the chain), else it only says to follow the quest in the log.
function R.FollowTarget(s, pos)
    local view = { qid = s.qid, kind = "w", title = R.Title(s.qid), what = "follow the quest in your log" }
    if not pos then return view end
    local known = run and run.quests or {}
    local log = myLog()
    local best, bd
    if log[s.qid] then                                  -- the quest itself is in the log: the game's own point of it
        local p = mapPoint(s.qid, pos)
        if p then
            bd = math.sqrt((p.a - pos.a) ^ 2 + (p.b - pos.b) ^ 2)
            view.place, view.straight, view.distance = p, bd, bd
            view.what = NQ().IsComplete(s.qid) and "turn it in" or (R.OpenObjective(s.qid) or "follow the quest in your log")
            if OMQ.Arrow then view.heading = OMQ.Arrow.Heading(p.a - pos.a, p.b - pos.b) end
            view.there = bd <= R.OBJ_RADIUS
            return view
        end
        view.what = NQ().IsComplete(s.qid) and "turn it in - follow the quest in your log" or view.what
        return view
    end
    for id in pairs(log) do
        if not known[id] and not data(id) then
            local p = mapPoint(id, pos)
            local dd = p and math.sqrt((p.a - pos.a) ^ 2 + (p.b - pos.b) ^ 2)
            if dd and (not bd or dd < bd) then best, bd, view.via_qid = p, dd, id end
        end
    end
    if best then
        view.place, view.straight, view.distance = best, bd, bd
        view.what = "follow " .. R.Title(view.via_qid)
        if OMQ.Arrow then view.heading = OMQ.Arrow.Heading(best.a - pos.a, best.b - pos.b) end
        view.there = bd <= R.OBJ_RADIUS
    end
    return view
end

-- left click on the small arrow: the main arrow goes to the same place (anything else replaces it again)
function R:MainArrow()
    local t = self:Target()
    if not (t and OMQ.Guide and t.place) then return false end
    OMQ.Guide:StartAt("Quest Run: " .. t.title, t.place.a, t.place.b, t.place.inst, "run", nil,
        { name = t.what, radius = (t.kind ~= "o" and not t.hunt) and R.PICK_RADIUS or R.OBJ_RADIUS, qid = t.qid, area = t.kind == "o" })
    return true
end

-- the follow-up of the run that waits behind turning in qid (466)
function R.FollowUpIn(r, qid)
    for _, x in ipairs(r and r.stops or {}) do if x.kind == "p" and x.after == qid then return x.qid end end
    return nil
end

-- the quests of the run in their order, for the list (open ones first by their next stop, then done ones);
-- a turn-in stop is no row of its own: the follow-up's row says to turn in first
function R:List()
    if not run then return {} end
    local out, seen = {}, {}
    if run.kind == "dungeon" or run.kind == "area" then   -- Dungeon Run (476), Area Run (491): one row per quest
        local WHAT = { p = "pick up", o = "objectives", t = "turn in", w = "follow the quest in your log" }
        for _, s in ipairs(run.stops) do
            local q = run.quests[s.qid]
            if q and not seen[s.qid] and not q.done and not q.dropped then
                seen[s.qid] = true
                local what = WHAT[s.kind] or "objectives"
                if s.kind == "p" then what = R.Hunt(s.qid) or what end        -- named mob drop (508)
                out[#out + 1] = { qid = s.qid, title = R.Title(s.qid), what = what, kind = s.kind,
                                  dungeonQuest = q.goal == "pick", current = #out == 0 }
            end
        end
        for qid, q in pairs(run.quests) do
            if not seen[qid] and q.done then out[#out + 1] = { qid = qid, done = true, title = R.Title(qid), dungeonQuest = q.goal == "pick" } end
        end
        return out
    end
    for _, s in ipairs(run.stops) do
        local q = run.quests[s.qid]
        if s.kind ~= "t" and q and not seen[s.qid] then
            seen[s.qid] = true
            local what = (s.kind == "p") and "pick up" or "objectives"
            if s.kind == "p" and q.follow then
                local waiting = false
                for _, x in ipairs(run.stops) do if x.kind == "t" and x.qid == q.follow then waiting = true end end
                what = waiting and ("turn in " .. R.Title(q.follow) .. " first, then pick up") or "pick up the follow-up"
            end
            if s.kind == "p" and R.Hunt(s.qid) and not (q.follow and what ~= "pick up the follow-up") then what = R.Hunt(s.qid) end
            out[#out + 1] = { qid = s.qid, new = q.new and not q.picked, follow = q.follow, title = R.Title(s.qid),
                              what = what, current = #out == 0 }
        end
    end
    for qid, q in pairs(run.quests) do
        if not seen[qid] and q.done then out[#out + 1] = { qid = qid, done = true, title = R.Title(qid) } end
    end
    return out
end

----------------------------------------------------------------------
-- Messages
----------------------------------------------------------------------
OMQ:RegisterMessage("RN", function(f)
    local op = f[1]
    local mine = myGuid()
    if op == "s" then
        if f[3] == mine then return end
        if OMQ.db and OMQ.db.guide and OMQ.db.guide.receive == false then return end
        run = newRun(f[2], f[3])
        run.group = true
        run.total = tonumber(f[4]) or 0
        if f[5] == "area" then run.kind, run.zone = "area", tonumber(f[6]) end      -- Area Run (491)
        run.startedAt = now()
        prep = nil
        fire()
    elseif not run or f[2] ~= run.id then
        return
    elseif op == "p" then
        if R:IsLeader() then return end
        local i, qid = tonumber(f[3]), tonumber(f[5], 36)
        local a, b = tonumber(f[6]), tonumber(f[7])
        if not (i and qid and a and b) or run.all[i] then return end
        local kind = (f[4] == "p" or f[4] == "t") and f[4] or "o"
        local after = f[10] and f[10] ~= "" and tonumber(f[10], 36) or nil
        addStop(run, { i = i, qid = qid, kind = kind, after = after, goal = run.kind == "area" and "turnin" or nil,
                       place = { a = a, b = b, inst = tonumber(f[8]) or 0, map = tonumber(f[9]) } })
        fire()
    elseif op == "o" then
        if R:IsLeader() then return end
        local done, order, dropped = parse36(f[3]), parse36(f[4]), parse36(f[5])
        for _, qid in ipairs(done) do if run.quests[qid] then run.quests[qid].done = true end end
        for _, qid in ipairs(dropped) do if run.quests[qid] then run.quests[qid].dropped = true end end
        local stops = {}
        for _, i in ipairs(order) do if run.all[i] then stops[#stops + 1] = run.all[i] end end
        run.stops = stops
        for qid, q in pairs(run.quests) do
            if q.new then
                local open = false
                for _, s in ipairs(stops) do if s.qid == qid and s.kind == "p" then open = true end end
                if not open then q.picked = true end
            end
        end
        local d, all = R:Counts()
        if all > 0 and d >= all then finish() return end
        fire()
    elseif op == "c" then
        if not R:IsLeader() then return end
        local guid, qid = f[3], tonumber(f[4], 36)
        if not (guid and qid) then return end
        run.reports[guid] = run.reports[guid] or {}
        run.reports[guid][qid] = f[5]
        R:Tick()
    elseif op == "x" then
        if R:IsLeader() then local qid = tonumber(f[3], 36); if qid then R:Skip(qid) end end
    elseif op == "e" then
        if R:IsLeader() then return end
        closeRun("leader")
    end
end)

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
-- the vote (decision 465): "One more quest!" wins, the starter of the vote starts a run with one quest for everybody
function R:QuickOne()
    return self:Prepare(function(st)
        local plan = R.Plan(st.pos, st.pool, 1, st.free)
        if not plan.quests[1] then
            OMQ:Print("Quest Run: no quest found" .. (#st.members > 0 and " that every dad has or can take" or ""))
            return
        end
        R:Start(plan)
    end)
end

local function restore()
    local g = myGuid()
    local s = g and OMQ.db and OMQ.db.questRun and OMQ.db.questRun[g]
    if type(s) ~= "table" or type(s.stops) ~= "table" then return end
    run = newRun(s.id or "0", s.leader or g)
    run.group, run.restored, run.started = s.group and true or false, true, s.started
    run.total = s.total or 0
    run.startedAt = now() - math.max(0, (time and s.started) and (time() - s.started) or 0)
    for _, q in ipairs(s.quests or {}) do
        run.quests[q[1]] = { qid = q[1], new = q[2] == 1, done = q[3] == 1, picked = q[4] == 1, dropped = q[5] == 1,
                             inLog = q[2] ~= 1 or q[4] == 1, wasComplete = q[3] == 1,      -- a new quest not picked up is not in the log
                             follow = (q[6] and q[6] ~= 0) and q[6] or nil, goal = q[7] }
    end
    run.kind, run.dungeon, run.info, run.zone, run.allow = s.kind, s.dungeon, s.info, s.zone, s.allow
    for _, st in ipairs(s.stops) do
        addStop(run, { qid = st[1], kind = st[2], place = { a = st[3], b = st[4], inst = st[5], map = st[6] }, i = st[7], after = st[8],
                       goal = st[9], needs = st[10] })
    end
    run.members = members()
    run.pool, run.skip = {}, {}
    if run.group and run.leader ~= g then run.group = true end
    fire()
end

R._restore = restore

OMQ:On("READY", function()
    pcall(restore)
    C_Timer.NewTicker(R.TICK, function()
        local ok, err = pcall(R.Tick, R)
        if not ok then OMQ:Error("questrun", err) end
    end)
end)

OMQ:RegisterCommand("run", function(arg)
    arg = (arg or ""):lower()
    local n = tonumber(arg)
    if arg == "off" or arg == "end" or arg == "stop" then
        if run then R:End(); OMQ:Print("Quest Run ended") else OMQ:Print("Quest Run: no run active") end
        return
    end
    if arg == "diag" then
        local out = { "Quest Run - diagnostics" }
        local pos = NQ().MyPos()
        out[#out + 1] = "position: " .. (pos and string.format("%.0f, %.0f, continent %s, map %s", pos.a, pos.b, tostring(pos.inst), tostring(pos.map)) or "none")
        if pos then
            local log, titles = myLog()
            local pool, free = R.Pool(pos, { log = log, titles = titles, members = {} })
            local logN, newN = 0, 0
            for _, e in ipairs(pool) do if e.new then newN = newN + 1 else logN = logN + 1 end end
            out[#out + 1] = string.format("quests of my log that fit: %d, new quests nearby: %d, room in the log: %d", logN, newN, free)
        end
        if run then
            local d, all = R:Counts()
            out[#out + 1] = string.format("run: %d/%d done, %d stops open, %s", d, all, #run.stops, run.group and "group" or "alone")
        end
        if OMQ.ShowReport then OMQ:ShowReport(out) else for _, l in ipairs(out) do print(l) end end
        return
    end
    if n and n >= 1 and n <= 7 then
        R:Prepare(function() local plan = R:PlanFor(n); if plan then R:Start(plan) end end)
        return
    end
    if OMQ.QuestRunUI then OMQ.QuestRunUI:Open() end
end, "quest run: /omq run [1-7|off|diag]")
