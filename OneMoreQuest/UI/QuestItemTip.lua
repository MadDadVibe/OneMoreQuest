-- One More Quest: the quest of a quest item in its tooltip (decision 654). Hovering an item (bags and everywhere else
-- the game shows an item tooltip) that belongs to a quest adds a block of lines: for each quest the level in front of
-- the name, coloured like the quest log does (grey, green, yellow, orange, red), the quest's zone and its state:
-- in my log with the progress of this item's objective, ready to turn in, not accepted (from level N when too low),
-- or turned in already. Which quests: Data/QuestItems.lua (quest -> items, QuestieDB), Data/QuestDrops.lua (items that
-- start a quest), and every quest of my log whose objective names the item (the client's words, so German and English
-- both work and quests the data does not know are found too). Quests of the other faction, another race or class
-- are left out. Names and zones come from the game (localised), the English data name only as a fallback.
-- In-log quests first, then not accepted, then turned in; at most MAX quests, "... and N more".
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local T = {}
OMQ.QuestItemTip = T
T.MAX = 4

local HEAD = { 0.89, 0.71, 0.29 }
local ZONE = { 0.62, 0.62, 0.62 }
-- Enum.RelativeContentDifficulty: Trivial 0, Easy 1, Fair 2, Difficult 3, Impossible 4
T.COLORS = {
    [0] = { 0.62, 0.62, 0.62 },   -- grey
    [1] = { 0.25, 0.75, 0.25 },   -- green
    [2] = { 1.00, 0.82, 0.00 },   -- yellow
    [3] = { 1.00, 0.50, 0.25 },   -- orange
    [4] = { 1.00, 0.10, 0.10 },   -- red
}
local STATE = {
    done = { 0.25, 0.75, 0.25 }, log = { 1, 0.82, 0 }, new = { 1, 1, 1 }, low = { 1, 0.5, 0.25 }, turned = { 0.62, 0.62, 0.62 },
}

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function str(v) return type(v) == "string" and v ~= "" and not isSecret(v) and v or nil end
local function num(v) return type(v) == "number" and not isSecret(v) and v or nil end
local function myLevel() return UnitLevel and num((UnitLevel("player"))) or 1 end
local function places(id) return OMQ.QuestPlaces and OMQ.QuestPlaces[id] end

----------------------------------------------------------------------
-- item -> quests from the data (built once)
----------------------------------------------------------------------
local index
function T.Index()
    if index then return index end
    index = {}
    local function add(item, q)
        if type(item) ~= "number" then return end
        local l = index[item]
        if not l then l = {}; index[item] = l end
        for _, x in ipairs(l) do if x == q then return end end
        l[#l + 1] = q
    end
    for q, items in pairs(OMQ.QuestItems or {}) do
        for _, it in ipairs(items) do add(it, q) end
    end
    for q, d in pairs(OMQ.QuestDrops or {}) do add(d[1], q) end
    return index
end
function T._reset() index = nil; T._log = nil end

----------------------------------------------------------------------
-- my quest log (kept until the log changes)
----------------------------------------------------------------------
local function shownLevel(info)
    return num(info.difficultyLevel) and info.difficultyLevel > 0 and info.difficultyLevel
        or num(info.level) and info.level > 0 and info.level or nil
end
local function complete(id, info)
    if info and info.isComplete ~= nil and not isSecret(info.isComplete) then
        return info.isComplete == true or info.isComplete == 1
    end
    local CQ = C_QuestLog
    for _, f in ipairs({ "IsComplete", "ReadyForTurnIn" }) do
        if CQ and CQ[f] then
            local ok, r = pcall(CQ[f], id)
            if ok and r and not isSecret(r) then return true end
        end
    end
    return false
end
function T.Log()
    if T._log then return T._log end
    local out = { byId = {}, list = {} }
    local CQ = C_QuestLog
    if CQ and CQ.GetNumQuestLogEntries and CQ.GetInfo then
        local ok, n = pcall(CQ.GetNumQuestLogEntries)
        n = ok and num(n) or 0
        local zone
        for i = 1, n do
            local okI, info = pcall(CQ.GetInfo, i)
            if okI and type(info) == "table" then
                if info.isHeader then
                    zone = str(info.title)
                else
                    local id = num(info.questID)
                    if id and id > 0 and not info.isHidden then
                        local objs = {}
                        if CQ.GetQuestObjectives then
                            local okO, l = pcall(CQ.GetQuestObjectives, id)
                            if okO and type(l) == "table" then
                                for _, o in ipairs(l) do
                                    if type(o) == "table" then
                                        objs[#objs + 1] = { text = str(o.text), have = num(o.numFulfilled),
                                                            need = num(o.numRequired), finished = o.finished == true,
                                                            kind = str(o.type) }
                                    end
                                end
                            end
                        end
                        local e = { id = id, title = str(info.title), level = shownLevel(info), zone = zone,
                                    done = complete(id, info), objs = objs }
                        out.byId[id] = e
                        out.list[#out.list + 1] = e
                    end
                end
            end
        end
    end
    T._log = out
    return out
end

----------------------------------------------------------------------
-- the parts of one line
----------------------------------------------------------------------
local function everDone(id)
    local NQ = OMQ.NextQuest
    if NQ and NQ.EverDone then local ok, r = pcall(NQ.EverDone, id); return ok and r or false end
    return false
end
local function contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end
-- quests of the other faction, race or class are not mine
function T.ForMe(id)
    local d = places(id)
    if not d then return true end
    local NQ = OMQ.NextQuest
    local me = NQ and NQ.Me and NQ.Me() or {}
    if d[4] and me.fac and d[4] ~= me.fac then return false end
    if d[5] and me.race and not contains(d[5], me.race) then return false end
    if d[6] and me.class and not contains(d[6], me.class) then return false end
    return true
end

local loading = {}
function T.Title(id, entry)
    local t = entry and entry.title
    if not t and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, r = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok then t = str(r) end
    end
    if not t then
        -- the game fetches the localised name; the next hover shows it
        if not loading[id] and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
            loading[id] = true
            pcall(C_QuestLog.RequestLoadQuestByID, id)
        end
        local d = places(id)
        t = d and d[1]
    end
    return t or ("Quest " .. id)
end

function T.Level(id, entry)
    local l = entry and entry.level
    if not l then local d = places(id); l = d and num(d[3]) and d[3] > 0 and d[3] or nil end
    return l
end

-- the quest log's colour: the game's difficulty for this quest, else my level against the quest level
function T.Difficulty(id, level)
    local OQ = OMQ.OldQuests
    local d = OQ and OQ.GameDifficulty and OQ.GameDifficulty(id)
    if d and T.COLORS[d] then return d end
    if not level then return nil end
    local me = myLevel()
    local diff = level - me
    if diff >= 5 then return 4 end
    if diff >= 3 then return 3 end
    if diff >= -2 then return 2 end
    local grey = OQ and OQ.GreyBelow and OQ.GreyBelow(me) or (me - 5 - math.floor(me / 10))
    if level < grey then return 0 end
    return 1
end

local function mapName(spots)
    local s = type(spots) == "table" and spots[1]
    local m = s and s[1]
    if not m or not (C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, m)
    return ok and type(info) == "table" and str(info.name) or nil
end
function T.Zone(id, entry)
    if entry and entry.zone then return entry.zone end
    local d = places(id)
    if not d then return nil end
    return mapName(d[7]) or mapName(d[8]) or mapName(d[9])
end

-- the objective of a log quest that names this item (plain text search in the client's words)
local function objectiveFor(entry, name)
    if not (entry and name) then return nil end
    for _, o in ipairs(entry.objs) do
        if o.text and (not o.kind or o.kind == "item") and o.text:find(name, 1, true) then return o end
    end
end

-- state text, colour and sort rank (1 log, 2 not accepted, 3 turned in)
function T.State(id, entry, itemName)
    if entry then
        if entry.done then return "complete - turn in", STATE.done, 1 end
        local o = objectiveFor(entry, itemName)
        if o and o.have and o.need and o.need > 1 then
            return ("in log, %d/%d"):format(o.have, o.need), o.finished and STATE.done or STATE.log, 1
        end
        if o and o.finished then return "in log, item done", STATE.done, 1 end
        local n, f = #entry.objs, 0
        for _, x in ipairs(entry.objs) do if x.finished then f = f + 1 end end
        if n > 1 then return ("in log, %d/%d objectives"):format(f, n), STATE.log, 1 end
        return "in log", STATE.log, 1
    end
    if everDone(id) then return "turned in", STATE.turned, 3 end
    local d = places(id)
    local req = d and num(d[2])
    if req and req > myLevel() then return ("not accepted - from level %d"):format(req), STATE.low, 2 end
    return "not accepted", STATE.new, 2
end

----------------------------------------------------------------------
-- the tooltip
----------------------------------------------------------------------
local function itemName(id, link)
    local n
    if C_Item and C_Item.GetItemNameByID then
        local ok, v = pcall(C_Item.GetItemNameByID, id); if ok then n = str(v) end
    end
    if not n and GetItemInfo then
        local ok, v = pcall(GetItemInfo, link or id); if ok then n = str(v) end
    end
    return n
end
local function idOfLink(link)
    local s = str(link)
    return s and tonumber(s:match("item:(%d+)")) or nil
end

-- the quests of this item, sorted: { id, title, level, diff, zone, state, stateColor, rank }
function T.Quests(itemId, link)
    if not itemId then return {} end
    local log = T.Log()
    local name = itemName(itemId, link)
    local seen, out = {}, {}
    local function add(q)
        if seen[q] then return end
        seen[q] = true
        local e = log.byId[q]
        if not e and not T.ForMe(q) then return end
        local level = T.Level(q, e)
        local st, col, rank = T.State(q, e, name)
        out[#out + 1] = { id = q, title = T.Title(q, e), level = level, diff = T.Difficulty(q, level),
                          zone = T.Zone(q, e), state = st, stateColor = col, rank = rank }
    end
    for _, q in ipairs(T.Index()[itemId] or {}) do add(q) end
    if name then
        for _, e in ipairs(log.list) do
            if objectiveFor(e, name) then add(e.id) end
        end
    end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return a.id < b.id
    end)
    return out
end

function T.Enabled()
    return not (OMQ.db and OMQ.db.options and OMQ.db.options.questItemTip == false)
end

local HEADER = "One More Quest - quest"
function T.OnItem(tt, data)
    if not T.Enabled() or not tt or not tt.AddLine then return end
    local link = data and data.hyperlink
    if not link and tt.GetItem then
        local ok, _, l = pcall(tt.GetItem, tt); if ok then link = l end
    end
    local id = data and num(data.id) or idOfLink(link)
    if not id then return end
    -- the game builds some tooltips twice: not a second block
    local name = tt.GetName and tt:GetName()
    local n = tt.NumLines and tt:NumLines() or 0
    for i = 1, n do
        local fs = name and _G[name .. "TextLeft" .. i]
        local s = fs and fs.GetText and fs:GetText()
        if type(s) == "string" and not isSecret(s) and s:find(HEADER, 1, true) then return end
    end
    local list = T.Quests(id, link)
    T.last = { item = id, quests = list }
    if #list == 0 then return end
    tt:AddLine(HEADER .. (#list > 1 and "s" or "") .. ":", HEAD[1], HEAD[2], HEAD[3])
    for i, q in ipairs(list) do
        if i > T.MAX then
            tt:AddLine(("  ... and %d more"):format(#list - T.MAX), ZONE[1], ZONE[2], ZONE[3])
            break
        end
        local c = T.COLORS[q.diff or 2] or T.COLORS[2]
        local left = (q.level and ("[" .. q.level .. "] ") or "") .. q.title
        if tt.AddDoubleLine then
            tt:AddDoubleLine("  " .. left, q.state, c[1], c[2], c[3], q.stateColor[1], q.stateColor[2], q.stateColor[3])
        else
            tt:AddLine("  " .. left .. " - " .. q.state, c[1], c[2], c[3])
        end
        if q.zone then tt:AddLine("    " .. q.zone, ZONE[1], ZONE[2], ZONE[3]) end
    end
    if tt.Show then tt:Show() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED",
                     "PLAYER_LEVEL_UP" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function() T._log = nil end)

OMQ:RegisterCommand("qitem", function()
    local l = T.last
    if not l then OMQ:Print("no item hovered yet"); return end
    OMQ:Print(("item %d: %d quest(s)"):format(l.item, #l.quests))
    for _, q in ipairs(l.quests) do
        OMQ:Print(("  %d [%s] %s - %s - %s (difficulty %s)"):format(q.id, tostring(q.level or "?"), q.title,
            q.zone or "no zone", q.state, tostring(q.diff)))
    end
end, "qitem - the quests found for the last hovered item", true)

OMQ:On("READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
        and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            local ok, err = pcall(T.OnItem, tt, data)
            if not ok then OMQ:Error("quest item tooltip", err) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local ok, err = pcall(T.OnItem, tt, nil)
            if not ok then OMQ:Error("quest item tooltip", err) end
        end)
    end
end)
