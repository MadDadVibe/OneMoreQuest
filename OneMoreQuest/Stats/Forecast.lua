-- One More Quest: forecast of the time until level 60 (decision 644)
-- Two forecasts from the character's own level splits (OMQDB.tally[guid].levels, active seconds
-- without AFK), each as played time and as real days at the character's pace so far:
--  own pace: XP per hour of the last 5 finished levels (newer weigh more), carried to the higher
--            levels with the kill XP of a same-level mob (45 + 5 x level), summed up to level 60.
--  reference: a table of hours per level range (6/14/22/28/36/44 h, 150 h to 60; an estimate,
--            Blizzard's measured 20.5 h to level 20 fits it), spread over the levels of a range by
--            the XP they need. The player's time so far against the table's time to the same
--            level gives a factor for the rest of the table (rule of three).
-- Real days = forecast played time / (active seconds per real day since the record began).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local F = {}
OMQ.Forecast = F

local MAX_LEVEL = 60
local LAST_LEVELS = 5          -- finished levels for the own pace
local MIN_LEVELS = 3           -- fewer: the session's XP per hour instead
local MIN_SECS = 1800          -- active seconds before the reference factor means anything
local DAY = 86400

-- XP from level L to L + 1 (Classic table); the game's own value replaces it once seen
F.XP_NEED = {
    400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
    8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
    25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
    95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
    153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

-- reference hours per range: 1-10, 10-20, ..., 50-60
F.REF_HOURS = { 6, 14, 22, 28, 36, 44 }

local function need(b, L)
    local seen = b and b.xpMax and b.xpMax[L]
    if type(seen) == "number" and seen > 0 then return seen end
    return F.XP_NEED[L] or F.XP_NEED[#F.XP_NEED]
end

-- relative XP per hour on level L (kill XP of a same-level mob)
local function grow(L) return 45 + 5 * L end
F.Grow = grow

-- reference seconds for level L to L + 1
local refCache
local function refSecs(L)
    if not refCache then
        refCache = {}
        for r = 1, #F.REF_HOURS do
            local lo, hi = (r - 1) * 10, r * 10 - 1
            if lo < 1 then lo = 1 end
            local sum = 0
            for L2 = lo, hi do sum = sum + F.XP_NEED[L2] end
            for L2 = lo, hi do refCache[L2] = F.REF_HOURS[r] * 3600 * F.XP_NEED[L2] / sum end
        end
    end
    return refCache[L] or 0
end

-- reference seconds from level 1 to the level value x (41.3 = level 41, 30 % through it)
function F.RefTo(x)
    if x >= MAX_LEVEL then x = MAX_LEVEL end
    local s, whole = 0, math.floor(x)
    for L = 1, whole - 1 do s = s + refSecs(L) end
    if whole < MAX_LEVEL and whole >= 1 then s = s + (x - whole) * refSecs(whole) end
    return s
end

-- finished levels with their active seconds: { { lvl = L, secs = s }, ... } oldest first
function F.Finished(b)
    local out = {}
    if not (b and type(b.levels) == "table") then return out end
    local startLvl = b.since and b.since.lvl or 1
    for L = 1, MAX_LEVEL - 1 do
        local a, z = b.levels[L], b.levels[L + 1]
        local s0 = a and a.secs
        if not s0 and L == 1 and startLvl == 1 then s0 = 0 end   -- the record began at level 1, 0 XP
        if type(s0) == "number" and z and type(z.secs) == "number" and z.secs > s0 then
            out[#out + 1] = { lvl = L, secs = z.secs - s0 }
        end
    end
    return out
end

-- the own pace: XP per hour divided by grow(level); nil without enough data
function F.Pace(b, sessionXph, level)
    local done = F.Finished(b)
    if #done >= MIN_LEVELS then
        local sw, sn = 0, 0
        local first = math.max(1, #done - LAST_LEVELS + 1)
        for i = first, #done do
            local d = done[i]
            local w = i - first + 1
            sn = sn + w * (need(b, d.lvl) / (d.secs / 3600)) / grow(d.lvl)
            sw = sw + w
        end
        if sw > 0 and sn > 0 then return sn / sw end
    end
    if type(sessionXph) == "number" and sessionXph > 0 and level then return sessionXph / grow(level) end
    return nil
end

-- active seconds per real day since the record began; nil without data
function F.DayPace(b, now)
    if not (b and type(b.secs) == "number" and b.secs > 0 and b.since and b.since.t) then return nil end
    local days = math.max((now - b.since.t) / DAY, 1)
    return b.secs / days
end

-- all four values: own played seconds, reference played seconds, own and reference real seconds
function F.Compute(b, level, xp, xpMax, sessionXph, now)
    local r = {}
    if not level or level >= MAX_LEVEL then return r end
    xpMax = (xpMax and xpMax > 0) and xpMax or need(b, level)
    local frac = math.min(math.max((xp or 0) / xpMax, 0), 1)
    local pace = F.Pace(b, sessionXph, level)
    if pace then
        local s = (xpMax - (xp or 0)) / (pace * grow(level)) * 3600
        for L = level + 1, MAX_LEVEL - 1 do s = s + need(b, L) / (pace * grow(L)) * 3600 end
        r.own = s
    end
    if b and type(b.secs) == "number" and b.secs >= MIN_SECS then
        local startLvl = b.since and b.since.lvl or 1
        local cur = level + frac
        local refDone = F.RefTo(cur) - F.RefTo(startLvl)
        if refDone > 0 then
            r.factor = b.secs / refDone
            r.ref = (F.RefTo(MAX_LEVEL) - F.RefTo(cur)) * r.factor
        end
    end
    local dp = F.DayPace(b, now or time())
    if dp and dp > 0 then
        if r.own then r.ownDays = r.own / dp * DAY end
        if r.ref then r.refDays = r.ref / dp * DAY end
    end
    return r
end

-- the game's XP for the current level, kept so the forecast uses it later
function F.Remember(b, level, xpMax)
    if not (b and level and type(xpMax) == "number" and xpMax > 0) then return end
    if issecretvalue and issecretvalue(xpMax) then return end
    b.xpMax = b.xpMax or {}
    b.xpMax[level] = xpMax
end

-- values for the session tooltip (Measure:GetValues)
function F.Fill(v, level, xp, xpMax)
    local T = OMQ.Tally
    local b = T and T.Book and T.Book()
    if not b then return end
    F.Remember(b, level, xpMax)
    local r = F.Compute(b, level, xp, xpMax, v.xph, time())
    v.lvl60, v.lvl60r, v.lvl60d, v.lvl60dr = r.own, r.ref, r.ownDays, r.refDays
end

function F.Print()
    local T = OMQ.Tally
    local b = T and T.Book and T.Book()
    if not b then OMQ:Print("no records for this character"); return end
    local level = UnitLevel("player") or 1
    local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 1
    local v = OMQ.Measure and OMQ.Measure:GetValues() or {}
    local r = F.Compute(b, level, xp, xpMax, v.xph, time())
    local done = F.Finished(b)
    local h = function(s) return s and string.format("%.1f h", s / 3600) or "-" end
    local d = function(s) return s and string.format("%.1f days", s / DAY) or "-" end
    OMQ:Print(string.format("Level 60: own pace %s (%s), reference %s (%s)", h(r.own), d(r.ownDays), h(r.ref), d(r.refDays)))
    OMQ:Print(string.format("finished levels %d, record since level %s, played %s, %s per real day, factor vs reference %s",
        #done, tostring(b.since and b.since.lvl), h(b.secs), h(F.DayPace(b, time())), r.factor and string.format("%.2f", r.factor) or "-"))
end

OMQ:RegisterCommand("lvl60", function() F.Print() end, "forecast of the time until level 60 (own pace and reference)")
