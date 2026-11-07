-- One More Quest: /omq questarea (read-only probe, decisions 440 and 449)
-- Finds out what WoW Forever tells an addon about the quest areas it highlights on the map:
--   - which functions exist (quest places on a map, next waypoint, the inside test of the minimap)
--   - the quest places on my current map (C_QuestLog.GetQuestsOnMap)
--   - per quest of my log: on this map?, next waypoint, waypoint text, inside its area now
--     (C_Minimap.IsInsideQuestBlob, the test the game's own quest item glow uses)
--   /omq questarea watch [sec]  writes every PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED of the game into the chat
--                              ("entered" / "left" with the quest), and every change the inside test shows
--                              once a second, for a while (default 300 s); /omq questarea stop ends it early
-- v1.3.45 tried an own invisible QuestPOIFrame (DrawBlob, UpdateMouseOverTooltip): it never answered in the game.
-- Nothing is changed in the game. The last report is kept in the saved variables (OMQDB.questareaReport, the
-- watch lines in OMQDB.questareaWatch).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.QuestAreaProbe = P

P.MAX_QUESTS, P.MAX_MAP = 15, 10

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function show(v)
    if v == nil then return "nil" end
    if isSecret(v) then return "SECRET" end
    if type(v) == "number" then
        if v == math.floor(v) then return tostring(v) end
        return string.format("%.3f", v)
    end
    return (tostring(v):gsub("[%c|]", " "))
end
local function num(v) return type(v) == "number" and not isSecret(v) end
local function xyOf(v)
    if type(v) ~= "table" then return nil end
    if v.GetXY then local ok, x, y = pcall(v.GetXY, v); if ok then return x, y end end
    return v.x, v.y
end
local function exists(path)
    local t = _G
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return false end
        t = t[part]
        if t == nil then return false end
    end
    return true
end
local function keys(t)
    local list = {}
    for k, v in pairs(t) do list[#list + 1] = tostring(k) .. "=" .. (type(v) == "table" and "{..}" or show(v)) end
    table.sort(list)
    return table.concat(list, " ")
end

P.NAMES = {
    "C_QuestLog.GetQuestsOnMap", "C_QuestLog.GetNextWaypoint", "C_QuestLog.GetNextWaypointForMap",
    "C_QuestLog.GetNextWaypointText", "C_QuestLog.IsOnMap", "C_QuestLog.GetQuestAdditionalHighlights",
    "C_QuestLog.GetMapForQuestPOIs", "C_QuestLog.SetMapForQuestPOIs", "C_SuperTrack.GetSuperTrackedQuestID",
    "C_Minimap.IsInsideQuestBlob", "C_Map.GetWorldPosFromMapPos", "C_Map.GetPlayerMapPosition",
}

-- yards between me and a map point (x, y from 0 to 1)
local function yards(map, x, y)
    if not (UnitPosition and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local a, b, _, inst = UnitPosition("player")
    if not (num(a) and num(b)) then return nil end
    local ok, cont, vec = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok then return nil end
    local wa, wb = xyOf(vec)
    if not (num(wa) and num(wb)) then return nil end
    if inst and cont and cont ~= inst then return "other continent" end
    return math.floor(math.sqrt((wa - a) ^ 2 + (wb - b) ^ 2) + 0.5)
end

function P.Run()
    local out = {}
    local function add(t) out[#out + 1] = t end
    add("One More Quest " .. tostring(OMQ.version) .. " quest area probe")

    add("-- which functions exist")
    local missing = {}
    for _, n in ipairs(P.NAMES) do if not exists(n) then missing[#missing + 1] = n end end
    add(#missing == 0 and "all present" or ("MISSING: " .. table.concat(missing, ", ")))
    if GetCVar then
        local ok, v = pcall(GetCVar, "questPOI")
        add("map option questPOI (quest objectives on the map): " .. (ok and show(v) or "ERROR"))
    end

    add("-- me")
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local px, py
    if map and C_Map.GetPlayerMapPosition then
        local ok, v = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if ok then px, py = xyOf(v) end
    end
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    add(string.format("map %s %s, position %s, %s", show(map), info and show(info.name) or "", show(px), show(py)))
    if not (num(px) and num(py)) then px, py = nil, nil end
    local tracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    add("super tracked quest: " .. show(tracked))

    add("-- quest places on this map (GetQuestsOnMap)")
    local onMap = {}
    if map and C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, map)
        if not ok then add("ERROR " .. show(list))
        elseif type(list) ~= "table" or #list == 0 then add("none")
        else
            add(#list .. " places")
            for i, q in ipairs(list) do
                if type(q) == "table" then
                    if q.questID then onMap[q.questID] = q end
                    if i <= P.MAX_MAP then
                        local d = (map and num(q.x) and num(q.y)) and yards(map, q.x, q.y)
                        add("  " .. keys(q) .. (d and ("  -> " .. show(d) .. " yd") or ""))
                    end
                end
            end
        end
    else
        add("none (no map or no function)")
    end

    add("-- my quests")
    local ids = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local q = C_QuestLog.GetInfo(i)
            if q and not q.isHeader and q.questID and #ids < P.MAX_QUESTS then ids[#ids + 1] = { id = q.questID, title = q.title } end
        end
    end
    if #ids == 0 then add("no quests in the log") end
    for _, q in ipairs(ids) do
        local parts = { "quest " .. q.id .. " '" .. show(q.title) .. "'" }
        if C_QuestLog.IsOnMap then
            local ok, a, b = pcall(C_QuestLog.IsOnMap, q.id)
            parts[#parts + 1] = ok and ("on map " .. show(a) .. " local " .. show(b)) or "IsOnMap ERROR"
        end
        if C_QuestLog.GetNextWaypoint then
            local ok, m, x, y = pcall(C_QuestLog.GetNextWaypoint, q.id)
            if ok and m then
                local d = num(x) and num(y) and yards(m, x, y)
                parts[#parts + 1] = string.format("waypoint map %s %s, %s%s", show(m), show(x), show(y), d and (" (" .. show(d) .. " yd)") or "")
            else parts[#parts + 1] = ok and "no waypoint" or "waypoint ERROR" end
        end
        if C_QuestLog.GetNextWaypointText then
            local ok, t = pcall(C_QuestLog.GetNextWaypointText, q.id)
            if ok and t and t ~= "" then parts[#parts + 1] = "text '" .. show(t) .. "'" end
        end
        if onMap[q.id] then parts[#parts + 1] = "place on this map" end
        add(table.concat(parts, " | "))
    end

    add("-- inside test (C_Minimap.IsInsideQuestBlob)")
    if not (C_Minimap and C_Minimap.IsInsideQuestBlob) then
        add("missing")
    else
        local inside = {}
        for _, q in ipairs(ids) do
            local ok, r = pcall(C_Minimap.IsInsideQuestBlob, q.id)
            if not ok then inside[#inside + 1] = q.id .. " ERROR " .. show(r)
            elseif r and not isSecret(r) then inside[#inside + 1] = q.id .. " '" .. show(q.title) .. "'"
            elseif isSecret(r) then inside[#inside + 1] = q.id .. " SECRET" end
        end
        add(#inside == 0 and "inside no area" or ("inside: " .. table.concat(inside, ", ")))
    end
    add("(run it standing inside a quest area; /omq questarea watch reports entering and leaving)")

    OMQDB = OMQDB or {}
    OMQDB.questareaReport = out
    if OMQ.ShowReport then OMQ:ShowReport(out) else for _, l in ipairs(out) do print(l) end end
    return out
end

----------------------------------------------------------------------
-- Watch: the game's event and the inside test once a second
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
local watchUntil, state, log, ticker = nil, {}, nil, nil

local function title(id)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and type(t) == "string" and not isSecret(t) then return t end
    end
    return "quest " .. tostring(id)
end
local function note(text)
    local line = string.format("%.1f %s", GetTime(), text)
    if log then log[#log + 1] = line end
    OMQ:Print("quest area: " .. text)
end
function P.IsWatching() return watchUntil ~= nil end

function P.Poll()
    if not watchUntil then return end
    if GetTime() >= watchUntil then P.Stop(); return end
    if not (C_Minimap and C_Minimap.IsInsideQuestBlob and C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local q = C_QuestLog.GetInfo(i)
        if q and not q.isHeader and q.questID then
            local ok, r = pcall(C_Minimap.IsInsideQuestBlob, q.questID)
            if ok and not isSecret(r) then
                r = r and true or false
                if state[q.questID] ~= nil and state[q.questID] ~= r then
                    note((r and "test says inside " or "test says outside ") .. title(q.questID) .. " (" .. q.questID .. ")")
                end
                state[q.questID] = r
            end
        end
    end
end

frame:SetScript("OnEvent", function(_, event, qid, inside)
    if event ~= "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED" or not watchUntil then return end
    if isSecret(qid) or isSecret(inside) then note("event with secret values"); return end
    note((inside and "EVENT entered " or "EVENT left ") .. title(qid) .. " (" .. tostring(qid) .. ")")
end)

function P.Watch(seconds)
    seconds = math.max(10, math.min(tonumber(seconds) or 300, 1800))
    watchUntil, state, log = GetTime() + seconds, {}, {}
    OMQDB = OMQDB or {}
    OMQDB.questareaWatch = log
    pcall(frame.RegisterEvent, frame, "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED")
    if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, P.Poll) end
    P.Poll()
    OMQ:Print("quest area watch for " .. seconds .. " s: walk into and out of a quest area (/omq questarea stop ends it)")
end

function P.Stop()
    if not watchUntil then return end
    watchUntil = nil
    pcall(frame.UnregisterEvent, frame, "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED")
    if ticker and ticker.Cancel then ticker:Cancel() end
    ticker = nil
    OMQ:Print("quest area watch ended, " .. (log and #log or 0) .. " lines kept")
end

OMQ:RegisterCommand("questarea", function(arg)
    local cmd, rest = (arg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "watch" then return P.Watch(rest) end
    if cmd == "stop" then return P.Stop() end
    P.Run()
end, "read-only report: what the client tells about the quest areas on the map; watch [sec] reports entering and leaving")
