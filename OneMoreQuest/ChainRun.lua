-- One More Quest: Chain Run (decision 595). Leads step by step through a quest chain every dad should do
-- (Data/QuestChains.lua: the Cozy Sleeping Bag, the Night Watchman's Torch). Each dad has his own state; in a group
-- the dads tell each other which step they are at (message CN) and the dad who starts offers the chain to the others.
-- Only one run goes at a time: starting a Chain Run ends a Quest/Dungeon/Area Run or a Grind Run and the other way
-- round. The bar, the small arrow and the tracker card are the ones of the Quest Run (UI/QuestRun.lua,
-- UI/QuestTracker.lua) in purple; the window is UI/ChainRun.lua.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local C = {}
OMQ.ChainRun = C

C.PICK_RADIUS = 12        -- "you are there" at a giver in the world
C.SEARCH_RADIUS = 30      -- a search place counts as looked at from here (the dead guard lies near it)
C.TICK = 0.5
C.OTHERS_TTL = 600        -- a dad's step is forgotten after 10 minutes without news

local run                 -- { key, started, startedAt, seen = { [i] = true }, last }
local others = {}         -- [name] = { key, step, n, at }

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return GetTime() end
local function NQ() return OMQ.NextQuest end
local function myGuid() local m = OMQ:GetSelf(); return m and m.guid end

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
function C.Chains() return OMQ.QuestChains or {} end
function C.Get(key)
    for _, c in ipairs(C.Chains()) do if c.key == key then return c end end
    return nil
end
function C.Faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Horde" or f == "Alliance" then return f end
    return "Alliance"
end
-- the value of a per-faction table: { Alliance = .., Horde = .. } or { both = .. }
function C.Pick(t, faction)
    if type(t) ~= "table" then return nil end
    return t[faction or C.Faction()] or t.both
end
function C.Level()
    local l = UnitLevel and UnitLevel("player")
    if type(l) ~= "number" or isSecret(l) then return 0 end
    return l
end

local function everDone(id)
    local CQ = C_QuestLog
    if CQ and CQ.IsQuestFlaggedCompleted then
        local ok, r = pcall(CQ.IsQuestFlaggedCompleted, id)
        return ok and r == true
    end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) and true or false end
    return false
end
local function inLog(id)
    local CQ = C_QuestLog
    if CQ and CQ.GetLogIndexForQuestID then
        local ok, i = pcall(CQ.GetLogIndexForQuestID, id)
        if ok and type(i) == "number" and not isSecret(i) and i > 0 then return true end
    end
    if CQ and CQ.IsOnQuest then
        local ok, r = pcall(CQ.IsOnQuest, id)
        if ok and r == true then return true end
    end
    if CQ and CQ.GetNumQuestLogEntries and CQ.GetInfo and not CQ.GetLogIndexForQuestID then   -- old API: walk the log
        local ok, n = pcall(CQ.GetNumQuestLogEntries)
        for i = 1, (ok and type(n) == "number") and n or 0 do
            local ok2, info = pcall(CQ.GetInfo, i)
            if ok2 and type(info) == "table" and info.questID == id and not info.isHeader then return true end
        end
    end
    return false
end
local function itemCount(id)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, id, true)
        if ok and type(n) == "number" and not isSecret(n) then return n end
    end
    if GetItemCount then
        local ok, n = pcall(GetItemCount, id, true)
        if ok and type(n) == "number" and not isSecret(n) then return n end
    end
    return 0
end
C._everDone, C._inLog, C._itemCount = everDone, inLog, itemCount

-- "done", "log" (picked up, not turned in) or "open"
function C.StepState(step, faction)
    local ids = C.Pick(step.quests, faction) or {}
    for _, id in ipairs(ids) do if everDone(id) then return "done", id end end
    if step.item and itemCount(step.item) > 0 then return "done" end
    for _, id in ipairs(ids) do if inLog(id) then return "log", id end end
    return "open", ids[1]
end

-- how far a chain is: number of done steps, all steps, index of the first open step (nil when all are done)
function C.Progress(chain, faction)
    local done, first = 0, nil
    for i, st in ipairs(chain.steps) do
        if C.StepState(st, faction) == "done" then done = done + 1 elseif not first then first = i end
    end
    return done, #chain.steps, first
end

-- "done", "running", "low" (level too low) or "ready"
function C.Status(chain)
    local done, n = C.Progress(chain)
    if done >= n then return "done" end
    if run and run.key == chain.key then return "running" end
    if C.Level() < (chain.minLevel or 1) then return "low" end
    return "ready"
end

function C.Title(step, faction)
    local _, id = C.StepState(step, faction)
    local t
    if id and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, r = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and type(r) == "string" and r ~= "" and not isSecret(r) then t = r end
    end
    return t or step.title or ("Quest " .. tostring(id))
end

----------------------------------------------------------------------
-- Places
----------------------------------------------------------------------
local placeCache = {}
function C.Place(spot)
    if not spot then return nil end
    local p = placeCache[spot]
    if p ~= nil then return p or nil end
    local w = NQ() and NQ().World(spot)
    p = w and { a = w[1], b = w[2], inst = w[3], map = spot[1] } or false
    placeCache[spot] = p
    return p or nil
end
local function straight(p, pos)
    if not (p and pos) or p.inst ~= pos.inst then return nil end
    return math.sqrt((p.a - pos.a) ^ 2 + (p.b - pos.b) ^ 2)
end

-- the next search place: the nearest one not looked at yet (all looked at: start again)
function C.SearchSpot(step, pos)
    if not run then return nil end
    run.seen = run.seen or {}
    local function nearest()
        local best, bd, bi
        for i, spot in ipairs(step.search) do
            if not run.seen[i] then
                local p = C.Place(spot)
                local d = straight(p, pos) or (1e6 + i)
                if p and (not bd or d < bd) then best, bd, bi = p, d, i end
            end
        end
        return best, bi
    end
    local p, i = nearest()
    if not p then run.seen = {}; p, i = nearest() end
    return p, i
end

----------------------------------------------------------------------
-- The run
----------------------------------------------------------------------
function C:Active() return run ~= nil end
function C:Run() return run end
function C:Chain() return run and C.Get(run.key) or nil end

local function save()
    if not OMQ.db then return end
    local g = myGuid()
    if not g then return end
    OMQ.db.chainRun = OMQ.db.chainRun or {}
    OMQ.db.chainRun[g] = run and { key = run.key, started = run.started, seen = run.seen } or nil
end

local function sendStep()
    if not run then return end
    local chain = C:Chain()
    if not chain then return end
    local done, n = C.Progress(chain)
    OMQ:Send("CN", "s", run.key, tostring(done), tostring(n))
end

local function fire() OMQ:Fire("CHAIN_RUN_CHANGED"); save() end

local function endOthers()
    if OMQ.QuestRun and OMQ.QuestRun:Active() then OMQ.QuestRun:End() end
    if OMQ.Grind and OMQ.Grind:Active() then OMQ.Grind:Finish("cancel") end
end
C._endOthers = endOthers

-- another run is going (the window asks before it ends it, K5)
function C.OtherRun()
    if OMQ.QuestRun and OMQ.QuestRun:Active() then
        local r = OMQ.QuestRun:Run()
        return (r and r.kind == "dungeon") and "Dungeon Run" or (r and r.kind == "area") and "Area Run" or "Quest Run"
    end
    if OMQ.Grind and OMQ.Grind:Active() then return "Grind Run" end
    return nil
end

function C:Start(key, opts)
    local chain = C.Get(key)
    if not chain then OMQ:Print("Chain Run: no such chain"); return false end
    local status = C.Status(chain)
    if status == "done" then OMQ:Print("Chain Run: " .. chain.name .. " is already done"); return false end
    if status == "low" then OMQ:Print("Chain Run: " .. chain.name .. " needs level " .. chain.minLevel); return false end
    endOthers()
    run = { key = key, started = time and time() or 0, startedAt = now(), seen = {} }
    others = {}
    if not (opts and opts.quiet) then OMQ:Send("CN", "o", key) end     -- the other dads get the offer (K6)
    C:Tick()
    sendStep()
    fire()
    return true
end

function C:End(reason)
    if not run then return end
    run = nil
    OMQ:Send("CN", "e")
    fire()
end

local function finish()
    local chain = C:Chain()
    local secs = now() - (run.startedAt or now())
    local n = chain and #chain.steps or 0
    run = nil
    OMQ:Send("CN", "s", chain and chain.key or "", tostring(n), tostring(n))
    fire()
    OMQ:Fire("CHAIN_RUN_DONE", chain, n, secs)
end
C._finish = finish

-- every half second: done steps, looked-at search places, the end
function C:Tick()
    if not run then return end
    local chain = C:Chain()
    if not chain then run = nil; fire(); return end
    local done, n, first = C.Progress(chain)
    if not first then finish(); return end
    local step = chain.steps[first]
    if step.search then
        local pos = NQ() and NQ().MyPos()
        local p, i = C.SearchSpot(step, pos)
        local d = straight(p, pos)
        run.lookedAt = run.lookedAt or {}
        -- a place counts as looked at after I was near it and walked away again without the quest
        local changed = false
        for k in pairs(run.lookedAt) do
            local dk = straight(C.Place(step.search[k]), pos)
            if not dk or dk > C.SEARCH_RADIUS then
                run.lookedAt[k] = nil
                if C.StepState(step) == "open" then run.seen[k] = true; changed = true end
            end
        end
        if i and d and d <= C.SEARCH_RADIUS and C.StepState(step) == "open" then run.lookedAt[i] = true end
        if changed then fire() end
    end
    if run.last ~= done then
        run.last = done
        sendStep()
        fire()
    end
end

-- what the small arrow and the tracker card show: { title, what, place, distance, heading, there, near, step, n,
-- paused, enemy, search }
function C:Target()
    if not run then return nil end
    local chain = C:Chain()
    if not chain then return nil end
    local done, n, first = C.Progress(chain)
    if not first then return nil end
    local step = chain.steps[first]
    local state = C.StepState(step)
    local view = { title = C.Title(step), step = first, n = n, done = done, chain = chain.name }
    local need = step.minLevel or chain.minLevel or 1
    if C.Level() < need then
        view.paused, view.what = need, "next step at level " .. need
        return view
    end
    local pos = NQ() and NQ().MyPos()
    local p
    if step.search then
        p = C.SearchSpot(step, pos)
        view.search = true
        view.what = state == "log" and step.toText or step.fromText
    elseif state == "log" then
        p = C.Place(C.Pick(step.to)); view.what = step.toText
    else
        p = C.Place(C.Pick(step.from)); view.what = step.fromText
    end
    view.place = p
    if step.enemyZone and C.Pick(step.enemyZone) then view.enemy = true end
    local d = straight(p, pos)
    if d then
        view.straight, view.distance = d, d
        local ha, hb = p.a, p.b
        local way = OMQ.Path and OMQ.Path.ArrowWays and OMQ.Path.ArrowWays() and OMQ.Path.Way(pos, p)
        if way and way.via then view.distance, view.via, view.flight = way.cost, true, way.flight; ha, hb = way.a, way.b end
        if OMQ.Arrow and OMQ.Arrow.Heading then view.heading = OMQ.Arrow.Heading(ha - pos.a, hb - pos.b) end
        local calm = OMQ.Arrow and OMQ.Arrow.CALM or 25
        view.near = d <= calm or nil
        view.there = d <= (step.search and C.SEARCH_RADIUS or C.PICK_RADIUS)
    end
    return view
end

-- the bar's numbers: done steps, all steps
function C:ShownCounts()
    local chain = C:Chain()
    if not chain then return 0, 0 end
    local done, n = C.Progress(chain)
    return done, n
end

-- the rows of the bar's tooltip and the list
function C:List()
    local chain = C:Chain()
    local out = {}
    if not chain then return out end
    local _, _, first = C.Progress(chain)
    for i, st in ipairs(chain.steps) do
        out[#out + 1] = { title = C.Title(st), done = C.StepState(st) == "done", current = i == first }
    end
    return out
end

-- left click on the small arrow: the main arrow goes there too
function C:MainArrow()
    local t = self:Target()
    if not (t and t.place and OMQ.Guide) then return false end
    OMQ.Guide:StartAt("Chain Run: " .. t.title, t.place.a, t.place.b, t.place.inst, "run", nil,
        { name = t.what, radius = t.search and C.SEARCH_RADIUS or C.PICK_RADIUS })
    return true
end

-- the dads of the group and their step of my chain (K6)
function C:Others()
    local out = {}
    local t = now()
    for name, o in pairs(others) do
        if run and o.key == run.key and t - o.at <= C.OTHERS_TTL then out[#out + 1] = { name = name, done = o.done, n = o.n } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- a purple dot on the check bar icon: a chain that became ready for me and that I have not looked at yet (K4)
function C.NewForMe()
    local g = myGuid()
    local seen = g and OMQ.db and OMQ.db.chainSeen and OMQ.db.chainSeen[g] or {}
    for _, c in ipairs(C.Chains()) do
        if C.Status(c) == "ready" and not seen[c.key] then return true end
    end
    return false
end
function C.MarkSeen()
    local g = myGuid()
    if not (g and OMQ.db) then return end
    OMQ.db.chainSeen = OMQ.db.chainSeen or {}
    OMQ.db.chainSeen[g] = OMQ.db.chainSeen[g] or {}
    for _, c in ipairs(C.Chains()) do
        if C.Status(c) == "ready" then OMQ.db.chainSeen[g][c.key] = true end
    end
end

----------------------------------------------------------------------
-- Group messages: o = offer (key), s = my step (key, done, all), e = ended
----------------------------------------------------------------------
local function shortName(sender) return (tostring(sender or "?"):match("^[^-]+")) or "?" end

OMQ:RegisterMessage("CN", function(f, sender)
    local op = f[1]
    local me = OMQ:GetSelf()
    local who = shortName(sender)
    if me and who == me.name then return end
    if op == "s" then
        others[who] = { key = f[2], done = tonumber(f[3]) or 0, n = tonumber(f[4]) or 0, at = now() }
        OMQ:Fire("CHAIN_RUN_CHANGED")
    elseif op == "e" then
        others[who] = nil
        OMQ:Fire("CHAIN_RUN_CHANGED")
    elseif op == "o" then
        local chain = C.Get(f[2])
        if not chain or (run and run.key == chain.key) then return end
        if C.Status(chain) ~= "ready" then return end
        OMQ:Fire("CHAIN_RUN_OFFER", who, chain)
    end
end)

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local function restore()
    local g = myGuid()
    local s = g and OMQ.db and OMQ.db.chainRun and OMQ.db.chainRun[g]
    if type(s) ~= "table" or not C.Get(s.key) then return end
    run = { key = s.key, started = s.started, seen = type(s.seen) == "table" and s.seen or {} }
    run.startedAt = now() - math.max(0, (time and s.started) and (time() - s.started) or 0)
    fire()
end
C._restore = restore
C._state = function() return run, others end

OMQ:On("READY", function()
    pcall(restore)
    C_Timer.NewTicker(C.TICK, function()
        local ok, err = pcall(C.Tick, C)
        if not ok then OMQ:Error("chainrun", err) end
    end)
end)

OMQ:RegisterCommand("chain", function(arg)
    arg = (arg or ""):lower()
    if arg == "off" or arg == "end" or arg == "stop" then
        if run then C:End(); OMQ:Print("Chain Run ended") else OMQ:Print("Chain Run: no run active") end
        return
    end
    if arg == "diag" then
        local out = { "Chain Run - diagnostics", "faction: " .. C.Faction() .. ", level " .. C.Level() }
        for _, c in ipairs(C.Chains()) do
            local done, n, first = C.Progress(c)
            out[#out + 1] = string.format("%s: %s, %d/%d steps done%s", c.key, C.Status(c), done, n, first and (", next step " .. first) or "")
            for i, st in ipairs(c.steps) do
                local state, id = C.StepState(st)
                out[#out + 1] = string.format("   %d. %s (%s): %s", i, C.Title(st), tostring(id), state)
            end
        end
        local t = C:Target()
        if t then out[#out + 1] = "target: " .. t.title .. " - " .. tostring(t.what) .. (t.distance and string.format(" - %d yd", math.floor(t.distance + 0.5)) or "") end
        if OMQ.ShowReport then OMQ:ShowReport(out) else for _, l in ipairs(out) do print(l) end end
        return
    end
    if C.Get(arg) then
        if C.OtherRun() and OMQ.ChainRunUI then OMQ.ChainRunUI:AskStart(arg) else C:Start(arg) end
        return
    end
    if OMQ.ChainRunUI then OMQ.ChainRunUI:Toggle() end
end, "chain run: /omq chain [bag|torch|off|diag]")
