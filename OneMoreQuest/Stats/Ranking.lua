-- One More Quest: Ranking and statistic definitions
-- Every client ranks locally from the values it received (design principle).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local R = {}
OMQ.Ranking = R

----------------------------------------------------------------------
-- Formatting
----------------------------------------------------------------------
local function compact(v)
    local a = math.abs(v)
    if a >= 1000000 then return string.format("%.1fm", v / 1000000) end
    if a >= 10000 then return string.format("%.1fk", v / 1000) end
    if a >= 1000 then return string.format("%.1fk", v / 1000) end
    return string.format("%d", math.floor(v + 0.5))
end

-- Money as gold, silver and copper (the two largest units that fit a cell):
-- "126g 41s", "36s 93c", "12c".
local function gold(copper)
    copper = math.floor(copper + 0.5)
    local g = math.floor(copper / 10000)
    local sv = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return string.format("%dg %ds", g, sv) end
    if sv > 0 then return string.format("%ds %dc", sv, c) end
    return string.format("%dc", c)
end

local function percent(v) return string.format("%d%%", math.floor(v + 0.5)) end

R.formats = {
    compact = compact,
    gold = gold,
    percent = percent,
    goldsigned = function(v)
        if v == 0 then return "0" end
        return (v > 0 and "+" or "-") .. gold(math.abs(v))
    end,
    int = function(v) return string.format("%d", math.floor(v + 0.5)) end,
    plus2 = function(v) return string.format("%+.2f", v) end,
    dec2 = function(v) return string.format("%.2f", v) end,
    duration = function(v)
        local m = math.floor(v / 60)
        local h = math.floor(m / 60)
        local d = math.floor(h / 24)
        if d > 0 then return string.format("%dd %dh", d, h % 24) end
        if h > 0 then return string.format("%dh %dm", h, m % 60) end
        return string.format("%dm", m)
    end,
}

----------------------------------------------------------------------
-- One list of statistics for the session tooltip and the lifetime window
-- (decision 120). session / life = where the row exists; label2 = other wording
-- in the lifetime window; approx = always shown with "~". best = "high": the biggest
-- value takes place 1, "low": the smallest.
----------------------------------------------------------------------
local ALL = {
    { heading = "Time and gold" },
    { key = "ptime",   label = "Time in session",    label2 = "Time in sessions", best = "high", fmt = "duration", session = true, life = true },
    { key = "gold",    label = "Gold gained",        label2 = "Gold earned",      best = "high", fmt = "gold", session = true, life = true },
    { key = "curgold", label = "Current gold",       best = "high", fmt = "gold", session = true },
    { key = "yards",   label = "Yards walked",       best = "high", fmt = "compact", session = true, life = true },
    { key = "yfollow", label = "Yards on follow",    best = "high", fmt = "compact", session = true, life = true },
    { heading = "Experience" },
    { key = "lvlp",    label = "Level progress",     best = "high", fmt = "plus2", session = true },
    { key = "lvl",     label = "Current level",      best = "high", fmt = "dec2", session = true },
    { key = "nextlvl", label = "Next level up",      best = "low",  fmt = "duration", session = true },
    { key = "xp",      label = "XP gained",          best = "high", fmt = "compact", session = true, life = true },
    { key = "xph",     label = "XP gained per hour", best = "high", fmt = "compact", session = true, life = true },
    { key = "xpkill",  label = "XP from kills",      best = "high", fmt = "compact", session = true, life = true },
    { key = "xpquest", label = "XP from quests",     best = "high", fmt = "compact", session = true, life = true },
    { key = "xpdisc",  label = "XP from discovery",  best = "high", fmt = "compact", session = true, life = true },
    { key = "quests",  label = "Quests completed",   best = "high", fmt = "int", session = true, life = true },
    { key = "kb",      label = "Killing blows",      best = "high", fmt = "int", session = true, life = true },
    { key = "fights",  label = "Fights initiated",   best = "high", fmt = "int", session = true, life = true },
    { key = "dmg",     label = "Damage percentage",  best = "high", fmt = "percent", session = true },
    { key = "food",    label = "Food buff uptime",   best = "high", fmt = "percent", session = true, life = true },
    { heading = "Money talks" },
    { key = "aucp",    label = "Auctions posted",    best = "high", fmt = "int", session = true, life = true },
    { key = "aucb",    label = "Auctions bought",    best = "high", fmt = "int", session = true, life = true },
    { key = "greed",   label = "Greed rolls",        best = "high", fmt = "int", session = true, life = true },
    { key = "need",    label = "Need rolls",         best = "high", fmt = "int", session = true, life = true },
    { key = "gamble",  label = "Gamble balance",     best = "high", fmt = "goldsigned", session = true, life = true },
    { key = "betswon", label = "Bets won",           best = "high", fmt = "int", session = true, life = true },
    { heading = "Legendary stuff" },
    { key = "deaths",  label = "Deaths",             best = "low",  fmt = "int", session = true, life = true },
    { key = "falld",   label = "Deaths from falling", best = "low", fmt = "int", session = true, life = true },
    { key = "drownd",  label = "Deaths from drowning", best = "low", fmt = "int", session = true, life = true },
    { key = "lava",    label = "Deaths from lava",   best = "low",  fmt = "int", session = true, life = true },
    { key = "fallx",   label = "Fall damage taken",  best = "low",  fmt = "compact", session = true, life = true },
    { key = "near",    label = "Near deaths (<20%)", best = "low",  fmt = "int", session = true, life = true },
    { heading = "Records" },
    { key = "hit",     label = "Biggest damage hit", best = "high", fmt = "compact", session = true, life = true },
    { key = "heal",    label = "Biggest heal",       best = "high", fmt = "compact", session = true, life = true, approx = true },
    { key = "bestxph", label = "Best session XP per hour", best = "high", fmt = "compact", life = true },
    { key = "longest", label = "Longest session",    best = "high", fmt = "duration", life = true },
    { key = "bestgold", label = "Most gold per session", best = "high", fmt = "gold", life = true },
    { key = "mostdeaths", label = "Most deaths per session", best = "low", fmt = "int", life = true },
}

local function build(where)
    local list, pending = {}, nil
    for _, d in ipairs(ALL) do
        if d.heading then
            pending = d
        elseif d[where] then
            if pending then list[#list + 1] = pending; pending = nil end
            local copy = {}
            for k, v in pairs(d) do copy[k] = v end
            if where == "life" and d.label2 then copy.label = d.label2 end
            list[#list + 1] = copy
        end
    end
    return list
end

R.sessionStats = build("session")
R.lifetimeStats = build("life")

----------------------------------------------------------------------
-- Ranking. entries = { { id = guid, value = number or nil }, ... }
-- Returns map id -> place (1..n). Ties share the better place (decision 58);
-- entries without data are ranked last and get place = nil.
----------------------------------------------------------------------
function R.Rank(entries, best)
    local withData = {}
    for _, e in ipairs(entries) do
        if type(e.value) == "number" then withData[#withData + 1] = e end
    end
    table.sort(withData, function(a, b)
        if a.value == b.value then return tostring(a.id) < tostring(b.id) end
        if best == "low" then return a.value < b.value end
        return a.value > b.value
    end)
    local places = {}
    local lastValue, lastPlace
    for i, e in ipairs(withData) do
        if lastValue ~= nil and e.value == lastValue then
            places[e.id] = lastPlace
        else
            places[e.id] = i
            lastPlace = i
        end
        lastValue = e.value
    end
    return places
end

-- Formatted value for one cell, or "no data".
function R.Format(def, value, approx)
    if type(value) ~= "number" then return "no data" end
    local text = R.formats[def.fmt](value)
    if approx then text = "~" .. text end
    return text
end
