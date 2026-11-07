-- One More Quest: /omq questarea (read-only probe, decision 440)
-- Finds out what WoW Forever tells an addon about the quest areas it highlights on the map, before the
-- tracker is built on them:
--   - which functions exist (quest places on a map, next waypoint, the map's quest area frame)
--   - the quest places on my current map (C_QuestLog.GetQuestsOnMap)
--   - per quest of my log: on this map?, next waypoint, waypoint text, distance from me in yards
--   - the area test: an own invisible QuestPOIFrame draws the area of one quest and is asked whether my
--     position lies inside (UpdateMouseOverTooltip), plus a coarse grid over the map (how much of it is area)
-- Nothing is changed in the game. Not in combat (the area test makes a frame). The last report is kept in
-- the saved variables (OMQDB.questareaReport).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.QuestAreaProbe = P

P.MAX_QUESTS, P.MAX_MAP, P.GRID = 15, 10, 20

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
    "QuestPOIGetIconInfo", "GetQuestPOILeaderBoard", "C_Map.GetWorldPosFromMapPos", "C_Map.GetPlayerMapPosition",
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

-- the invisible area frame (made once)
local area
local function areaFrame(add)
    if area ~= nil then return area or nil end
    area = false
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, UIParent)
    if not ok or not f then add("area frame: cannot be made (" .. show(f) .. ")"); return nil end
    if f.SetSize then pcall(f.SetSize, f, 512, 512) end
    if f.SetPoint then pcall(f.SetPoint, f, "CENTER") end
    if f.SetAlpha then pcall(f.SetAlpha, f, 0) end
    if f.EnableMouse then pcall(f.EnableMouse, f, false) end
    area = f
    return f
end

-- is the map point inside the drawn area? returns the quest ID the frame names and its tooltip count
local function hit(f, x, y)
    local ok, qid, n = pcall(f.UpdateMouseOverTooltip, f, x, y)
    if not ok then return nil, nil, qid end
    return qid, n
end

function P.Reset() area = nil end

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

    add("-- area test (an invisible quest area frame)")
    if InCombatLockdown and InCombatLockdown() then
        add("not in combat - run it again after the fight")
    elseif not map then
        add("no map")
    else
        local f = areaFrame(add)
        if f then
            local need = { "SetMapID", "DrawNone", "DrawBlob", "UpdateMouseOverTooltip", "GetTooltipIndex" }
            local lack = {}
            for _, m in ipairs(need) do if type(f[m]) ~= "function" then lack[#lack + 1] = m end end
            add(#lack == 0 and "frame has every method" or ("frame lacks: " .. table.concat(lack, ", ")))
            if #lack == 0 then
                pcall(f.Show, f)
                local okm, em = pcall(f.SetMapID, f, map)
                if not okm then add("SetMapID ERROR " .. show(em)) end
                for _, q in ipairs(ids) do
                    pcall(f.DrawNone, f)
                    local okd, ed = pcall(f.DrawBlob, f, q.id, true)
                    if not okd then add("quest " .. q.id .. ": DrawBlob ERROR " .. show(ed))
                    else
                        local here = "?"
                        if px then
                            local qid, n, err = hit(f, px, py)
                            here = err and ("ERROR " .. show(err)) or (qid and ("inside (quest " .. show(qid) .. ", " .. show(n) .. " tooltips)") or "outside")
                        end
                        local cells, minx, maxx, miny, maxy, sx, sy = 0, 1, 0, 1, 0, 0, 0
                        for gx = 0, P.GRID do
                            for gy = 0, P.GRID do
                                local x, y = gx / P.GRID, gy / P.GRID
                                local qid = hit(f, x, y)
                                if qid == q.id then
                                    cells = cells + 1; sx, sy = sx + x, sy + y
                                    minx, maxx = math.min(minx, x), math.max(maxx, x)
                                    miny, maxy = math.min(miny, y), math.max(maxy, y)
                                end
                            end
                        end
                        local grid = cells == 0 and "no grid point inside"
                            or string.format("%d grid points inside, box %.2f-%.2f / %.2f-%.2f, middle %.2f, %.2f", cells, minx, maxx, miny, maxy, sx / cells, sy / cells)
                        add("quest " .. q.id .. ": me " .. here .. " | " .. grid)
                    end
                end
                pcall(f.DrawNone, f)
                pcall(f.Hide, f)
            end
        end
    end
    add("(run it where a quest area shows on your map, best standing inside one)")

    OMQDB = OMQDB or {}
    OMQDB.questareaReport = out
    if OMQ.ShowReport then OMQ:ShowReport(out) else for _, l in ipairs(out) do print(l) end end
    return out
end

OMQ:RegisterCommand("questarea", function() P.Run() end, "read-only report: what the client tells about the quest areas on the map")
