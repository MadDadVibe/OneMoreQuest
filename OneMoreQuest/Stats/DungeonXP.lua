-- One More Quest: XP of a dungeon visit against XP outside (decision 493)
-- Inside a dungeon (or raid) OMQ counts the XP and the time of the visit. When I come out alive (ported or
-- walked out; a ghost on the corpse run is still inside the visit) after at least 5 minutes with some XP,
-- a card shows the dungeon's XP, its XP per hour and the XP per hour outside. Back in the same dungeon within
-- 15 minutes, the same visit goes on (the time outside does not count for it).
-- Outside OMQ counts XP and play time in 5 minute blocks; the comparison uses the last 3 hours of play time
-- outside (AFK does not count). Under 20 minutes outside: "not enough data yet". Only XP gained INSIDE counts
-- for the dungeon: dungeon quests turned in outside count as XP outside.
-- Saved per character in OMQDB.dungeonXP[guid] = { cur = visit or nil, runs = { last 20, newest last },
-- blocks = { { s = seconds, x = xp }, ... } }. /omq dxp lists the last 10 visits.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local D = {}
OMQ.DungeonXP = D

D.MIN_SECS = 5 * 60          -- shorter visits get no card
D.CONTINUE = 15 * 60         -- back in the same dungeon within this time: the same visit
D.WINDOW = 3 * 3600          -- the outside comparison: this much play time outside
D.MIN_OUT = 20 * 60          -- less outside play time: no comparison yet
D.BLOCK = 5 * 60             -- seconds in one outside block
D.KEEP_RUNS = 20
D.TICK = 5

local function call(f, ...)
    if not f then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    return unpack(r, 2)
end
local function plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local function num(v) return type(v) == "number" and plain(v) end

local function store()
    local guid = call(UnitGUID, "player")
    if not (plain(guid) and OMQDB) then return nil end
    OMQDB.dungeonXP = OMQDB.dungeonXP or {}
    local st = OMQDB.dungeonXP[guid]
    if not st then st = { runs = {}, blocks = {} }; OMQDB.dungeonXP[guid] = st end
    st.runs = st.runs or {}
    st.blocks = st.blocks or {}
    return st
end
D.Store = store

-- inside a dungeon or raid: true, instance id, name
function D.Where()
    local name, kind, _, _, _, _, _, instId = call(GetInstanceInfo)
    if (kind == "party" or kind == "raid") and num(instId) then
        return true, instId, plain(name) and type(name) == "string" and name or "Dungeon"
    end
    return false
end

local function dead() return call(UnitIsDeadOrGhost, "player") and true or false end
local function afk() return call(UnitIsAFK, "player") and true or false end
local function maxLevel()
    local m = call(GetMaxPlayerLevel)
    return num(m) and m or 60
end

----------------------------------------------------------------------
-- XP differences
----------------------------------------------------------------------
local lastLevel, lastXP, lastMax
local function snapshot()
    lastLevel, lastXP, lastMax = call(UnitLevel, "player"), call(UnitXP, "player"), call(UnitXPMax, "player")
end

-- the XP gained since the last call (a level up: the rest of the old level plus the new one)
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

----------------------------------------------------------------------
-- Outside blocks
----------------------------------------------------------------------
local function outBlock(st)
    local b = st.blocks[#st.blocks]
    if not b or (b.s or 0) >= D.BLOCK then
        b = { s = 0, x = 0 }
        st.blocks[#st.blocks + 1] = b
        -- keep just enough blocks for the window
        local total = 0
        for i = #st.blocks, 1, -1 do
            total = total + (st.blocks[i].s or 0)
            if total > D.WINDOW + D.BLOCK then
                for _ = 1, i - 1 do table.remove(st.blocks, 1) end
                break
            end
        end
    end
    return b
end

-- XP per hour outside over the last window of play time: xph, seconds counted (nil: not enough data)
function D.OutsideRate(st)
    st = st or store()
    if not st then return nil, 0 end
    local secs, xp = 0, 0
    for i = #st.blocks, 1, -1 do
        local b = st.blocks[i]
        local s = b.s or 0
        if secs + s > D.WINDOW then
            local part = (D.WINDOW - secs) / math.max(s, 1)
            xp = xp + (b.x or 0) * part
            secs = D.WINDOW
            break
        end
        secs, xp = secs + s, xp + (b.x or 0)
    end
    if secs < D.MIN_OUT then return nil, secs end
    return xp / secs * 3600, secs
end

----------------------------------------------------------------------
-- The visit
----------------------------------------------------------------------
-- a finished (or paused) visit as a row of runs
local function result(v, st)
    local out = D.OutsideRate(st)
    local xph = v.xp / math.max(v.s, 60) * 3600
    return { id = v.id, nm = v.nm, t = v.t, s = v.s, xp = v.xp, xph = xph, out = out, l = v.l }
end

local function saveRun(st, v)
    local r = result(v, st)
    local runs = st.runs
    local last = runs[#runs]
    if last and last.t == v.t and last.id == v.id then runs[#runs] = r else runs[#runs + 1] = r end
    while #runs > D.KEEP_RUNS do table.remove(runs, 1) end
    return r
end

local function enter(st, id, name)
    local v = st.cur
    local now = time()
    if v and v.id == id and v.left and now - v.left <= D.CONTINUE then
        v.left = nil
        v.seen = now
        return v
    end
    local level = call(UnitLevel, "player")
    v = { id = id, nm = name, t = now, s = 0, xp = 0, seen = now, l = num(level) and level or nil }
    st.cur = v
    return v
end

-- out of the dungeon and alive: the card (once per leaving)
local function leave(st, v)
    v.left = time()
    v.seen = v.left
    if v.s < D.MIN_SECS or v.xp <= 0 then return end
    local r = saveRun(st, v)
    OMQ:Fire("DUNGEON_XP_DONE", r)
end

-- every few seconds: counts the time and the XP where I am; noticed leaving
function D.Tick(secs)
    local st = store()
    if not st then return end
    secs = secs or D.TICK
    local g = gained()
    local inside, id, name = D.Where()
    local level = call(UnitLevel, "player")
    local capped = num(level) and level >= maxLevel()
    local v = st.cur
    -- a visit not seen for a long time (logged out inside): kept in the list, no card
    if v and not v.left and time() - (v.seen or 0) > D.CONTINUE then
        if v.s >= D.MIN_SECS and v.xp > 0 then saveRun(st, v) end
        st.cur, v = nil, nil
    end
    if inside then
        if v and not v.left and v.id ~= id then leave(st, v) end
        if not v or v.id ~= id or v.left then v = enter(st, id, name) end
        v.s = v.s + secs
        v.xp = v.xp + g
        v.seen = time()
        return
    end
    if v and not v.left then
        if dead() then
            -- the corpse run belongs to the visit
            v.s = v.s + secs
            v.xp = v.xp + g
            v.seen = time()
            return
        end
        leave(st, v)
    end
    if v and v.left and time() - v.left > D.CONTINUE then st.cur = nil end
    if capped or afk() then return end
    local b = outBlock(st)
    b.s = b.s + secs
    b.x = b.x + g
end

-- XP right away (the kill that ends the visit counts before a port out)
function D.OnXP()
    local st = store()
    if not st then return end
    local g = gained()
    if g <= 0 then return end
    local v = st.cur
    if v and not v.left then v.xp = v.xp + g
    elseif not D.Where() then local b = outBlock(st); b.x = b.x + g end
end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------
function D.Num(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

function D.Time(secs)
    secs = math.max(0, math.floor((secs or 0) + 0.5))
    local h, m = math.floor(secs / 3600), math.floor(secs / 60) % 60
    if h > 0 then return string.format("%d:%02d h", h, m) end
    return string.format("%d min", m)
end

-- the two lines of a run: "18,400 XP in 52 min - 21,200 XP/h", "Outside: 14,800 XP/h - dungeon +43 %"
function D.Lines(r)
    local a = string.format("%s XP in %s - %s XP/h", D.Num(r.xp), D.Time(r.s), D.Num(r.xph))
    local b
    if r.out and r.out > 0 then
        local pct = math.floor((r.xph / r.out - 1) * 100 + 0.5)
        b = string.format("Outside: %s XP/h - dungeon %s%d %%", D.Num(r.out), pct >= 0 and "+" or "", pct)
        return a, b, pct
    end
    return a, "Outside: not enough data yet", nil
end

OMQ:RegisterCommand("dxp", function(arg)
    if arg == "test" then
        local out = D.OutsideRate()
        OMQ:Fire("DUNGEON_XP_DONE", { nm = "Wailing Caverns", s = 3130, xp = 18400, xph = 18400 / 3130 * 3600,
            out = out or 14800, t = time() })
        return
    end
    local st = store()
    if not st then return end
    local out, secs = D.OutsideRate(st)
    OMQ:Print(string.format("dungeon XP: outside %s (%s played outside counted)",
        out and (D.Num(out) .. " XP/h") or "not enough data yet", D.Time(secs)))
    local runs = st.runs
    if #runs == 0 then print("  no dungeon visit yet"); return end
    for i = #runs, math.max(1, #runs - 9), -1 do
        local r = runs[i]
        local a, b = D.Lines(r)
        print(string.format("  %s %s: %s; %s", date and date("%d.%m. %H:%M", r.t) or "", r.nm or "?", a, b))
    end
end, "dungeon XP: your last 10 dungeon visits, their XP per hour against XP per hour outside ('test': a sample card)")

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:SetScript("OnEvent", function(_, event)
    if not D.ready then return end
    local ok, err
    if event == "PLAYER_XP_UPDATE" then ok, err = pcall(D.OnXP)
    else ok, err = pcall(D.Tick, 0) end
    if not ok then OMQ:Error("dungeonxp", err) end
end)

OMQ:On("READY", function()
    snapshot()
    D.ready = true
    C_Timer.NewTicker(D.TICK, function()
        local ok, err = pcall(D.Tick, D.TICK)
        if not ok then OMQ:Error("dungeonxp", err) end
    end)
end)
