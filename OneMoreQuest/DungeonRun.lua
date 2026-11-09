-- One More Quest: Dungeon Run (decision 476)
-- The Group Check of a dungeon has a "Dungeon Run" button. It plans one run that collects every dungeon quest of that
-- dungeon for my faction that I have not done and do not carry yet, with every pre-quest before it: pick up, do the
-- objectives, turn in, until the dungeon quest is in my log. A dungeon quest counts when it is in the log, a pre-quest
-- when it is turned in; the bar counts all of them ("Dungeon Run: 1/13"). The last stop is the last quest; the run
-- does not lead to the dungeon.
--   Chains: from Data/QuestPlaces.lua (preQuestGroup: all of them, preQuestSingle: one of them), backwards from the
--   dungeon quest. The level does not matter (the run plans what I can take some day); faction, race, class and
--   excluding quests do. Elite pre-quests stay in (Skip takes them out).
--   Quests the data does not know (the new Forever dungeons, a few classic givers without a place): the chain start of
--   OMQ.QuestStarts (Data/DungeonGuide.lua, Data/ForeverDungeons.lua) is a stop, then "follow the quest in your log"
--   until the dungeon quest is there (the small arrow uses the game's map point of the next step when it has one).
--   Quests that start inside the dungeon or from an item are no stops; the preview names them.
--   Order: the nearest stop whose pre-quests are done first, then QuestRun's improvement (with the order rules).
-- In a group every dad gets his own route: the button sends DN s to the others, each one is asked and plans his own
-- run from his own log; the dads send their counts (DN c) and the bar shows how many of them are done.
--   DN|proto|s|dungeon key|guid|name   start your own Dungeon Run for this dungeon
--   DN|proto|c|dungeon key|guid|done|all|ended
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local D = {}
OMQ.DungeonRun = D

D.MAX_DEPTH = 25

local function R() return OMQ.QuestRun end
local function NQ() return OMQ.NextQuest end
local function data(id) return OMQ.QuestPlaces and OMQ.QuestPlaces[id] end
local function has(flags, b) return flags ~= nil and math.floor(flags / b) % 2 == 1 end
local function contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end
local function ever(id) return NQ().EverDone(id) end

-- a place of the data for the planner (any continent: the run takes every quest, D2)
local function placeOf(spot)
    local w = NQ().World(spot)
    if not w then return nil end
    return { a = w[1], b = w[2], inst = w[3], map = spot[1], w = spot[4] or 1 }
end
local function bestPlace(spots, from)
    local best, bd
    for _, s in ipairs(spots or {}) do
        local p = placeOf(s)
        if p then
            local dd = from and R().Dist(from, p) or 0
            if not bd or dd < bd then best, bd = p, dd end
        end
    end
    return best
end
-- the objective place: the one with the most spawns, of those the nearest to the giver
local function objPlace(spots, from)
    local list = {}
    for _, s in ipairs(spots or {}) do list[#list + 1] = s end
    if #list == 0 then return nil end
    table.sort(list, function(x, y) return (x[4] or 1) > (y[4] or 1) end)
    local top = list[1][4] or 1
    local good = {}
    for _, s in ipairs(list) do if (s[4] or 1) * 2.5 >= top then good[#good + 1] = s end end
    return bestPlace(good, from)
end

-- may I take this quest some day? faction, race, class, no excluding quest done (not the level, D2)
function D.ForMe(id, who, log)
    local d = data(id)
    if not d then return true end
    if d[4] and who.fac and d[4] ~= who.fac then return false end
    if d[5] and who.race and not contains(d[5], who.race) then return false end
    if d[6] and who.class and not contains(d[6], who.class) then return false end
    for _, p in ipairs(d[12] or {}) do if ever(p) or (log and log[p]) then return false end end
    return true
end

----------------------------------------------------------------------
-- The chain of one quest
----------------------------------------------------------------------
-- ctx = { pos, log, who, quests = { [id] = entry }, order = { id }, stops = {} }
-- entry = { id, goal = "pick" | "turnin", pick, obj, turnin, needs = { id }, dungeon = dungeon quest id it serves }
-- returns true when the quest is reachable (done already, in the log, or with its stops planned)
local resolve
local function needsOf(ctx, d, visiting, depth)
    local needs = {}
    for _, p in ipairs(d[10] or {}) do                       -- all of them
        if not ever(p) then
            if not resolve(ctx, p, "turnin", visiting, depth + 1) then return nil end
            if ctx.quests[p] then needs[#needs + 1] = p end
        end
    end
    if d[11] and #d[11] > 0 then                             -- one of them
        local ok = false
        for _, p in ipairs(d[11]) do if ever(p) then ok = true; break end end
        if not ok then
            for _, p in ipairs(d[11]) do if ctx.log[p] and resolve(ctx, p, "turnin", visiting, depth + 1) then ok = true; needs[#needs + 1] = p; break end end
        end
        if not ok then
            for _, p in ipairs(d[11]) do if ctx.quests[p] then ok = true; needs[#needs + 1] = p; break end end
        end
        if not ok then
            for _, p in ipairs(d[11]) do
                if resolve(ctx, p, "turnin", visiting, depth + 1) then ok = true; if ctx.quests[p] then needs[#needs + 1] = p end; break end
            end
        end
        if not ok then return nil end
    end
    return needs
end

function resolve(ctx, id, goal, visiting, depth)
    if ctx.quests[id] then return true end
    if ever(id) then return true end
    if goal == "pick" and ctx.log[id] then return true end
    if depth > D.MAX_DEPTH or visiting[id] then return false end
    local d = data(id)
    if not d then return false end
    if not D.ForMe(id, ctx.who, ctx.log) then return false end
    local inLog = ctx.log[id] and true or false
    if not inLog and (has(d[13], 4) or not d[7]) then return false end    -- from an item or no known giver
    if goal == "turnin" and has(d[13], 8) and not NQ().IsComplete(id) then return false end   -- objectives in a dungeon
    visiting[id] = true
    local needs = {}
    if not inLog then
        needs = needsOf(ctx, d, visiting, depth)
        if not needs then visiting[id] = nil; return false end
    end
    visiting[id] = nil
    local e = { id = id, goal = goal, needs = needs }
    local from = ctx.pos
    if not inLog then e.pick = bestPlace(d[7], from); from = e.pick or from end
    if goal == "turnin" then
        if not NQ().IsComplete(id) and d[9] then e.obj = objPlace(d[9], from); from = e.obj or from end
        e.turnin = bestPlace(d[8], from) or e.pick or from
        if not (e.obj or e.turnin) then return false end
    elseif not e.pick then
        return false
    end
    ctx.quests[id] = e
    ctx.order[#ctx.order + 1] = id
    return true
end
D._resolve = resolve

-- the stops of an entry
local function addStops(ctx, e)
    local function stop(kind, place)
        if not place then return end
        local s = { qid = e.id, kind = kind, place = place, goal = e.goal }
        if (kind == "p" or kind == "w") and e.needs and #e.needs > 0 then s.needs = e.needs end
        ctx.stops[#ctx.stops + 1] = s
    end
    if e.follow then stop("w", e.follow); return end
    stop("p", e.pick)
    stop("o", e.obj)
    stop("t", e.turnin)
end

-- the chain start of a quest the data does not know (or knows without a giver place)
local function starts(q)
    local S = OMQ.QuestStarts or {}
    local st = S[q.id]
    if not st then for _, a in ipairs(q.alt or {}) do if S[a] then st = S[a]; break end end end
    if not st then return nil end
    return { root = st[1], rootName = st[2], giver = st[3], map = st[5], x = st[6], y = st[7], kind = st[8] }
end

local function inLogAny(log, q)
    if log[q.id] then return true end
    for _, a in ipairs(q.alt or {}) do if log[a] then return true end end
    return false
end
local function doneAny(q)
    if ever(q.id) then return true end
    for _, a in ipairs(q.alt or {}) do if ever(a) then return true end end
    return false
end

-- the run for a dungeon: { stops, quests = { entry }, length, info = { inside, item, unknown, notForMe, done, inLog }, kind, dungeon }
function D.Build(key, pos, log, who, skip)
    local dg = OMQ.DungeonByKey and OMQ:DungeonByKey(key)
    if not dg then return nil end
    who = who or NQ().Me()
    skip = skip or {}
    local faction = (who.fac == "A" and "Alliance") or (who.fac == "H" and "Horde") or nil
    local ctx = { pos = pos, log = log or {}, who = who, quests = {}, order = {}, stops = {} }
    local info = { inside = {}, item = {}, unknown = {}, notForMe = {}, done = 0, inLog = 0, skipped = {} }
    local dqs = {}
    for _, q in ipairs(OMQ:DungeonQuests(dg, faction)) do
        if doneAny(q) then info.done = info.done + 1
        elseif inLogAny(ctx.log, q) then info.inLog = info.inLog + 1
        elseif skip[q.id] then info.skipped[#info.skipped + 1] = q.id
        else
            local d = data(q.id)
            local before = #ctx.order
            if d and d[7] and not has(d[13], 4) then
                if not D.ForMe(q.id, who, ctx.log) then info.notForMe[#info.notForMe + 1] = q.id
                elseif resolve(ctx, q.id, "pick", {}, 0) then dqs[#dqs + 1] = q.id
                else info.unknown[#info.unknown + 1] = q.id end
            else
                local st = starts(q)
                if not st then
                    if d and has(d[13], 4) then info.item[#info.item + 1] = q.id else info.unknown[#info.unknown + 1] = q.id end
                elseif st.kind == "inside" then info.inside[#info.inside + 1] = q.id
                elseif st.kind == "item" or not (st.map and st.map ~= 0) then info.item[#info.item + 1] = q.id
                else
                    local giver = placeOf({ st.map, st.x, st.y, 1 })
                    if not giver then
                        info.unknown[#info.unknown + 1] = q.id
                    elseif st.root == q.id then
                        ctx.quests[q.id] = { id = q.id, goal = "pick", pick = giver, needs = {} }
                        ctx.order[#ctx.order + 1] = q.id
                        dqs[#dqs + 1] = q.id
                    else
                        -- the known chain start, then follow the quest in the log until the dungeon quest is there
                        local needs = {}
                        local rootOk = ever(st.root)
                        if not rootOk and data(st.root) and resolve(ctx, st.root, "turnin", {}, 0) then rootOk = true end
                        if not rootOk and ctx.log[st.root] then rootOk = true end
                        if not rootOk then
                            ctx.quests[st.root] = { id = st.root, goal = "pick", pick = giver, needs = {} }
                            ctx.order[#ctx.order + 1] = st.root
                            rootOk = true
                        end
                        if ctx.quests[st.root] then needs[1] = st.root end
                        local root = ctx.quests[st.root]
                        local at = (root and (root.turnin or root.pick)) or giver
                        ctx.quests[q.id] = { id = q.id, goal = "pick", follow = at, needs = needs }
                        ctx.order[#ctx.order + 1] = q.id
                        dqs[#dqs + 1] = q.id
                    end
                end
            end
            for i = before + 1, #ctx.order do
                local e = ctx.quests[ctx.order[i]]
                if e and not e.dungeon then e.dungeon = q.id end
            end
        end
    end
    for _, id in ipairs(ctx.order) do addStops(ctx, ctx.quests[id]) end
    local stops = D.Order(pos, ctx.stops)
    local list = {}
    for _, id in ipairs(ctx.order) do list[#list + 1] = ctx.quests[id] end
    return { stops = stops, quests = list, length = R().PathCost(pos, stops), info = info, kind = "dungeon",
             dungeon = key, dungeonQuests = dqs, n = #list }
end

-- the first order: always the nearest stop that may come now, then the improvement
function D.Order(pos, stops)
    local left, out = {}, {}
    for _, s in ipairs(stops) do left[#left + 1] = s end
    local total = {}
    for _, s in ipairs(stops) do total[s.qid] = (total[s.qid] or 0) + 1 end
    local seen = {}
    local function may(s)
        for _, n in ipairs(s.needs or {}) do if total[n] and (seen[n] or 0) < total[n] then return false end end
        -- the quest's own stops in their order: p, o, t
        for _, x in ipairs(left) do
            if x ~= s and x.qid == s.qid then
                local rank = { p = 1, w = 1, o = 2, t = 3 }
                if rank[x.kind] < rank[s.kind] then return false end
            end
        end
        return true
    end
    local cur = pos
    while #left > 0 do
        local bi, bd
        for i, s in ipairs(left) do
            if may(s) then
                local dd = R().Dist(cur, s.place)
                if not bd or dd < bd then bi, bd = i, dd end
            end
        end
        if not bi then for i = 1, #left do out[#out + 1] = left[i] end break end   -- a loop in the data: keep the rest
        local s = table.remove(left, bi)
        out[#out + 1] = s
        seen[s.qid] = (seen[s.qid] or 0) + 1
        cur = s.place
    end
    return R().Improve(pos, out)
end

----------------------------------------------------------------------
-- Preparing and starting
----------------------------------------------------------------------
local prep = nil      -- { key, pos, log, titles, plan, skip }
function D:Prep() return prep end

function D:Prepare(key)
    if not OMQ.QuestPlaces then OMQ:Print("Dungeon Run: no quest data"); return nil end
    local pos = NQ().MyPos()
    if not pos then OMQ:Print("Dungeon Run: no position here"); return nil end
    local log, titles = R().MyLog()
    prep = { key = key, pos = pos, log = log, titles = titles, skip = {} }
    prep.plan = D.Build(key, pos, log, nil, prep.skip)
    return prep
end

-- the preview: leave out a dungeon quest and all pre-quests only it needs
function D:SkipPlanned(qid)
    if not prep then return nil end
    local dq = qid
    for _, e in ipairs(prep.plan and prep.plan.quests or {}) do if e.id == qid and e.dungeon then dq = e.dungeon end end
    prep.skip[dq] = true
    prep.plan = D.Build(prep.key, prep.pos, prep.log, nil, prep.skip)
    return prep.plan
end

-- the dungeon quests of the plan with their pre-quests, for the preview rows
function D.Rows(plan)
    local rows, by = {}, {}
    for _, dq in ipairs(plan and plan.dungeonQuests or {}) do
        local r = { qid = dq, pre = {}, elite = R().IsElite(dq), follow = false }
        rows[#rows + 1] = r
        by[dq] = r
    end
    for _, e in ipairs(plan and plan.quests or {}) do
        local r = by[e.dungeon or e.id]
        if r then
            if e.id ~= r.qid then r.pre[#r.pre + 1] = e.id; if R().IsElite(e.id) then r.elite = true end
            elseif e.follow then r.follow = true end
        end
    end
    -- the order of the way: by the first stop of each row
    local first = {}
    for i, s in ipairs(plan and plan.stops or {}) do
        local e
        for _, x in ipairs(plan.quests) do if x.id == s.qid then e = x end end
        local k = e and (e.dungeon or e.id)
        if k and not first[k] then first[k] = i end
    end
    table.sort(rows, function(a, b) return (first[a.qid] or 1e9) < (first[b.qid] or 1e9) end)
    return rows
end

function D:Start(plan)
    plan = plan or (prep and prep.plan)
    if not plan then return false end
    local ok = R():Start(plan)
    if ok then
        prep = nil
        D.SendCount()
    end
    return ok
end

----------------------------------------------------------------------
-- The group: everybody his own route (D7)
----------------------------------------------------------------------
D.group = {}          -- guid -> { name, key, done, all, ended }
local function myGuid() local m = OMQ:GetSelf(); return m and m.guid end

function D.SendCount()
    local run = R():Run()
    if not (run and run.kind == "dungeon") then return end
    local done, all = R():Counts()
    local g = myGuid()
    if not g then return end
    local last = D._sent
    local text = run.dungeon .. ":" .. done .. "/" .. all
    if last == text then return end
    D._sent = text
    local m = OMQ:GetSelf()
    D.group[g] = { name = m and m.name or "me", key = run.dungeon, done = done, all = all }
    if GetNumGroupMembers and GetNumGroupMembers() > 1 then OMQ:Send("DN", "c", run.dungeon, g, tostring(done), tostring(all), "") end
end

-- the dads of the same Dungeon Run and how many of them are done (me included)
function D.GroupCounts()
    local run = R():Run()
    if not (run and run.kind == "dungeon") then return 0, 0 end
    local n, fin = 0, 0
    for guid, x in pairs(D.group) do
        local present = guid == myGuid() or (OMQ.users and OMQ.users[guid] and (not OMQ.IsOnline or OMQ:IsOnline(OMQ.users[guid])))
        if present and x.key == run.dungeon then
            n = n + 1
            if x.ended or (x.all > 0 and x.done >= x.all) then fin = fin + 1 end
        end
    end
    return fin, n
end

-- the button: my own run, and in a group the others are asked to start theirs
function D:StartForGroup(key)
    local m = OMQ:GetSelf()
    if GetNumGroupMembers and GetNumGroupMembers() > 1 and m then
        OMQ:Send("DN", "s", key, m.guid or "?", m.name or "?")
    end
end

local function askStart(key, name)
    local dg = OMQ.DungeonByKey and OMQ:DungeonByKey(key)
    if not dg then return end
    local pop = "OMQ_DUNGEON_RUN_ASK"
    local function go()
        if OMQ.QuestRunUI and OMQ.QuestRunUI.OpenDungeon then OMQ.QuestRunUI:OpenDungeon(key) end
    end
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs[pop] = {
            text = (name or "A dad") .. " starts a Dungeon Run for " .. dg.name .. ". Plan your own way to its quests?",
            button1 = YES or "Yes", button2 = NO or "No", OnAccept = go,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show(pop)
    else
        go()
    end
end
D._askStart = askStart

OMQ:RegisterMessage("DN", function(f)
    local op = f[1]
    if op == "s" then
        local key, guid, name = f[2], f[3], f[4]
        if guid == myGuid() then return end
        if OMQ.db and OMQ.db.guide and OMQ.db.guide.receive == false then return end
        if OMQ.Unlock and not OMQ.Unlock:Has("dungeon") then return end
        D.group[guid] = { name = name, key = key, done = 0, all = 0 }
        askStart(key, name)
    elseif op == "c" then
        local key, guid = f[2], f[3]
        if not guid or guid == myGuid() then return end
        local prev = D.group[guid] or {}
        D.group[guid] = { name = prev.name, key = key, done = tonumber(f[4]) or 0, all = tonumber(f[5]) or 0, ended = f[6] == "1" }
        OMQ:Fire("QUEST_RUN_CHANGED")
    end
end)

OMQ:On("QUEST_RUN_CHANGED", function() pcall(D.SendCount) end)
OMQ:On("QUEST_RUN_DONE", function(_, _, r)
    if r and r.kind == "dungeon" and GetNumGroupMembers and GetNumGroupMembers() > 1 and myGuid() then
        local done = 0
        for _, q in pairs(r.quests) do if q.done then done = done + 1 end end
        OMQ:Send("DN", "c", r.dungeon, myGuid(), tostring(done), tostring(done), "1")
    end
    D._sent = nil
end)
OMQ:On("QUEST_RUN_END", function() D._sent = nil end)

OMQ:RegisterCommand("drun", function(arg)
    local key = arg and arg:match("^%s*(%S+)")
    if not (key and OMQ:DungeonByKey(key)) then OMQ:Print("Dungeon Run: /omq drun <dungeon key>, or the button in the Group Check"); return end
    if OMQ.QuestRunUI and OMQ.QuestRunUI.OpenDungeon then OMQ.QuestRunUI:OpenDungeon(key) end
end, "Dungeon Run: /omq drun <dungeon key> - every dungeon quest with its pre-quests on one way")
