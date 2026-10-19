-- One More Quest: "Take the dungeon quest along" (decision 258)
-- When I walk away from a place where a dungeon quest waits for me, a card reminds me, and a click
-- puts the arrow on the quest giver. Idea: nobody forgets a dungeon quest he could have taken.
-- A quest counts when I could take it now: my faction, my level at least the quest's level, the
-- dungeon not grey yet (my level up to its highest), not in my log, not done, and its giver has a
-- place (quests from items or from inside the dungeon have none). For a quest chain the arrow goes to
-- the start of the chain; once that start is done the quest is left out (its next giver is not known).
-- When:
--   any place (city, village, quest hub): I was within NEAR yards of the giver and now am more than
--     LEAVE yards away;
--   a major city: I leave the city map - all waiting quests of that city;
--   a flight master (fixed or learned), closer than FLIGHT yards: in a city all waiting quests of the
--     city, elsewhere those within HUB yards.
-- One card for everything that is waiting, for CARD_SECONDS; hover lists every quest. A quest
-- that was on the card comes back at the earliest after AGAIN seconds.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local DQ = {}
OMQ.DungeonQuestAlert = DQ

DQ.NEAR, DQ.LEAVE, DQ.FLIGHT, DQ.HUB = 80, 160, 10, 300
DQ.CARD_SECONDS, DQ.AGAIN, DQ.SEEN_FOR = 180, 1800, 900

local seen = {}        -- quest id -> time I was near its giver
local warned = {}      -- quest id -> time it was on the card
local pending = {}     -- quest id -> entry, shown since pendingAt
local pendingAt
DQ._seen, DQ._warned, DQ._pending = seen, warned, pending

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return GetTime() end

local function myPos()
    if not UnitPosition then return nil end
    local a, b, _, inst = UnitPosition("player")
    if type(a) ~= "number" or isSecret(a) or isSecret(b) then return nil end
    return a, b, inst
end
local function myMap()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if isSecret(m) then return nil end
    return m
end
local function done(id)
    local CQ = C_QuestLog
    return CQ and CQ.IsQuestFlaggedCompleted and CQ.IsQuestFlaggedCompleted(id) and true or false
end
local function inLog(id)
    local CQ = C_QuestLog
    return CQ and CQ.GetLogIndexForQuestID and CQ.GetLogIndexForQuestID(id) and true or false
end

-- the quest name as this client shows it (German on a German client), else the name from the data
local function title(id, name)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and type(t) == "string" and t ~= "" and not isSecret(t) then return t end
    end
    return name
end

-- the dungeon quests I could take now, each with the world position of its giver
function DQ.Available()
    local out = {}
    local R = OMQ.Ready
    if not (OMQ.Dungeons and R and R.QuestStart and OMQ.Guide and OMQ.Guide.WorldOf) then return out end
    local level = UnitLevel and tonumber((UnitLevel("player"))) or 1
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    for _, d in ipairs(OMQ.Dungeons) do
        if level <= d.max then
            for _, q in ipairs(OMQ:DungeonQuests(d, faction)) do
                local ids = { q.id }
                for _, a in ipairs(q.alt or {}) do ids[#ids + 1] = a end
                local taken = false
                for _, id in ipairs(ids) do if done(id) or inLog(id) then taken = true end end
                if not taken and level >= (q.level or 1) then
                    local st = R.QuestStart(q)
                    if st and st.kind == "npc" and st.map and st.map ~= 0 and not (st.chain and (done(st.root) or inLog(st.root))) then
                        local w = OMQ.Guide.WorldOf({ nil, nil, st.map, st.x, st.y })
                        if w then
                            out[#out + 1] = { id = q.id, name = title(q.id, q.name), dungeon = d, giver = st.giver, map = st.map,
                                              rootName = st.chain and st.rootName or nil, a = w[1], b = w[2], inst = w[3] }
                        end
                    end
                end
            end
        end
    end
    return out
end

local function dist(e, a, b, inst)
    if not a or e.inst ~= inst then return nil end
    return math.sqrt((e.a - a) ^ 2 + (e.b - b) ^ 2)
end

local function add(e, t)
    if warned[e.id] and t - warned[e.id] < DQ.AGAIN then return end
    if not pending[e.id] then pending[e.id] = e end
    pendingAt = t
end

-- the nearest flight master in yards (fixed places of my faction and learned ones)
local function flightDistance(a, b, inst)
    local best
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    fac = (fac == "Alliance" and "A") or (fac == "Horde" and "H") or nil
    for _, p in ipairs(OMQ.fixedPlaces or {}) do
        if p[1] == "flight" and (not fac or p[6] == "AH" or p[6] == fac) then
            local w = OMQ.Guide.WorldOf(p)
            if w and w[3] == inst then
                local d = math.sqrt((w[1] - a) ^ 2 + (w[2] - b) ^ 2)
                if not best or d < best then best = d end
            end
        end
    end
    for _, p in ipairs(OMQ.Places and OMQ.Places:All("flight") or {}) do
        if p.inst == inst and p.a then
            local d = math.sqrt((p.a - a) ^ 2 + (p.b - b) ^ 2)
            if not best or d < best then best = d end
        end
    end
    return best
end

local lastCity, atFlight = nil, false
function DQ.Tick()
    if not M:IsRuleEnabled("dungeonquest") then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    local t = now()
    local a, b, inst = myPos()
    local map = myMap()
    local city = map and OMQ.cityMaps and OMQ.cityMaps[map] and map or nil
    local list = DQ.Available()
    local before = pendingAt
    -- quests that are no longer waiting (taken, done) leave the card
    local still = {}
    for _, e in ipairs(list) do still[e.id] = true end
    for id in pairs(pending) do if not still[id] then pending[id] = nil end end
    -- 1. walked away from a giver I was close to
    for _, e in ipairs(list) do
        local d = dist(e, a, b, inst)
        if d and d <= DQ.NEAR then seen[e.id] = t
        elseif d and d > DQ.LEAVE and seen[e.id] and t - seen[e.id] < DQ.SEEN_FOR then
            seen[e.id] = nil
            add(e, t)
        end
    end
    -- 2. left a major city: everything that waits in it
    if lastCity and city ~= lastCity then
        for _, e in ipairs(list) do if e.map == lastCity then add(e, t) end end
    end
    lastCity = city
    -- 3. at a flight master
    local fd = a and flightDistance(a, b, inst)
    local nowAt = fd ~= nil and fd < DQ.FLIGHT
    if nowAt and not atFlight then
        for _, e in ipairs(list) do
            local d = dist(e, a, b, inst)
            if (city and e.map == city) or (not city and d and d <= DQ.HUB) then add(e, t) end
        end
    end
    atFlight = nowAt
    if pendingAt and t - pendingAt > DQ.CARD_SECONDS then
        for id in pairs(pending) do pending[id] = nil end
        pendingAt = nil
    end
    if pendingAt ~= before and M.Evaluate then M:Evaluate() end
end

-- the waiting quests, nearest giver first
function DQ.Pending()
    local a, b, inst = myPos()
    local list = {}
    for _, e in pairs(pending) do list[#list + 1] = e end
    table.sort(list, function(x, y)
        local dx, dy = dist(x, a, b, inst) or 1e9, dist(y, a, b, inst) or 1e9
        if dx ~= dy then return dx < dy end
        return x.id < y.id
    end)
    return list
end

function DQ.Card()
    local list = DQ.Pending()
    if #list == 0 then return nil end
    local first = list[1]
    local title = #list == 1 and ("Dungeon quest: " .. first.name) or (#list .. " dungeon quests waiting here")
    local sub = (first.rootName and ("Starts with \"" .. first.rootName .. "\" - ") or "") .. first.giver
        .. " (" .. first.dungeon.abbr .. ")" .. (#list > 1 and " - hover for all" or "")
    local tips = { "Dungeon quests you can take before you go:" }
    for _, e in ipairs(list) do
        tips[#tips + 1] = string.format("%s - %s, %s", e.name, e.giver, e.dungeon.name)
    end
    tips[#tips + 1] = "Left click: arrow to " .. first.giver .. ". Right click: not now."
    return {
        key = "dquest", title = title, text = title, sub = sub, tag = "QUEST", tipLines = tips,
        icon = "Interface\\GossipFrame\\AvailableQuestIcon", color = { 0.98, 0.82, 0.25 },
        open = function()
            for _, e in ipairs(list) do warned[e.id] = now() end
            if OMQ.Guide then OMQ.Guide:StartAt(first.giver, first.a, first.b, first.inst) end
        end,
    }
end

M:Register({ id = "dungeonquest", name = "Dungeon quests you could still take when you leave a place", check = function()
    local c = DQ.Card()
    if c then
        for _, e in pairs(pending) do warned[e.id] = warned[e.id] or now() end
        return { c }
    end
end })

local tick = CreateFrame("Frame")
local acc = 0
tick:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 1 then return end
    acc = 0
    pcall(DQ.Tick)
end)

OMQ:RegisterCommand("dquests", function()
    local list = DQ.Available()
    OMQ:Print(#list .. " dungeon quests you could take now:")
    local a, b, inst = myPos()
    for _, e in ipairs(list) do
        local d = dist(e, a, b, inst)
        OMQ:Print(string.format("  %s (%s) - %s%s", e.name, e.dungeon.abbr, e.giver, d and string.format(", %d yd", math.floor(d)) or ""))
    end
end, "dungeon quests you could take now and where")
