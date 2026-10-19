-- One More Quest: /omq diag guide
-- Finds out which position sources this client offers (map pin, corpse, quest
-- waypoints, flight points) and how their coordinates relate to UnitPosition.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function show(v)
    if v == nil then return "nil" end
    if isSecret(v) then return "SECRET" end
    if type(v) == "number" then return string.format("%.4f", v) end
    return tostring(v)
end
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

local function run()
    local out = {}
    local function add(t) out[#out + 1] = t end
    local function try(label, fn)
        local res = { pcall(fn) }
        if not res[1] then add(label .. ": ERROR " .. tostring(res[2])); return end
        local parts = {}
        for i = 2, #res do
            local v = res[i]
            if type(v) == "table" then
                local x, y = xyOf(v)
                if x ~= nil then parts[#parts + 1] = "(" .. show(x) .. ", " .. show(y) .. ")"
                else
                    local keys = {}
                    for k, val in pairs(v) do keys[#keys + 1] = tostring(k) .. "=" .. (type(val) == "table" and "{..}" or show(val)) end
                    table.sort(keys)
                    parts[#parts + 1] = "{" .. table.concat(keys, " ") .. "}"
                end
            else
                parts[#parts + 1] = show(v)
            end
        end
        add(label .. ": " .. (#parts > 0 and table.concat(parts, "  ") or "(no result)"))
    end

    add("One More Quest " .. OMQ.version .. " guide probe")
    add("-- which functions exist")
    local names = {
        "C_Map.GetUserWaypoint", "C_Map.SetUserWaypoint", "C_Map.HasUserWaypoint", "C_Map.ClearUserWaypoint",
        "C_Map.GetUserWaypointPositionForMap", "C_Map.GetWorldPosFromMapPos", "C_Map.GetMapPosFromWorldPos",
        "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo", "C_Map.CanSetUserWaypointOnMap",
        "C_SuperTrack.GetSuperTrackedQuestID", "C_SuperTrack.IsSuperTrackingUserWaypoint", "C_SuperTrack.SetSuperTrackedUserWaypoint",
        "C_DeathInfo.GetCorpseMapPosition", "C_QuestLog.GetNextWaypoint", "C_QuestLog.GetNextWaypointForMap",
        "C_QuestLog.GetQuestsOnMap", "C_TaxiMap.GetAllTaxiNodes", "C_TaxiMap.GetTaxiNodesForMap",
        "C_EncounterJournal.GetDungeonEntrancesForMap", "CreateVector2D", "UnitPosition", "GetPlayerFacing",
    }
    local missing = {}
    for _, n in ipairs(names) do if not exists(n) then missing[#missing + 1] = n end end
    add(#missing == 0 and "all present" or ("MISSING: " .. table.concat(missing, ", ")))

    add("-- player")
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    try("UnitPosition(player) a, b, z, instance", function() return UnitPosition("player") end)
    try("best map", function() return map end)
    try("map info", function()
        local i = C_Map.GetMapInfo(map)
        return i and i.name, i and i.mapType, i and i.parentMapID
    end)
    local px, py
    try("map position", function()
        local v = C_Map.GetPlayerMapPosition(map, "player")
        px, py = xyOf(v)
        return v
    end)
    try("facing", GetPlayerFacing)
    -- the key question: how do map positions relate to UnitPosition?
    if map and CreateVector2D and px and not isSecret(px) then
        try("world pos from map pos (continent, x, y)", function()
            local cont, w = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(px, py))
            local wx, wy = xyOf(w)
            return cont, wx, wy
        end)
        try("UnitPosition again (to compare)", function() return UnitPosition("player") end)
        add("(measured: world x equals the first UnitPosition number, no axis swap)")
    end

    add("-- map pin")
    try("HasUserWaypoint", function() return C_Map.HasUserWaypoint() end)
    try("GetUserWaypoint", function()
        local w = C_Map.GetUserWaypoint()
        if not w then return nil end
        return w.uiMapID, w.position
    end)
    try("pin position on current map", function() return C_Map.GetUserWaypointPositionForMap(map) end)
    try("pin to world pos", function()
        local w = C_Map.GetUserWaypoint()
        if not w then return nil end
        local cont, v = C_Map.GetWorldPosFromMapPos(w.uiMapID, w.position)
        local x, y = xyOf(v)
        return cont, x, y
    end)
    add("(set a pin on your map with ctrl+right-click and run this again)")

    add("-- corpse")
    try("ghost / dead", function() return UnitIsGhost and UnitIsGhost("player"), UnitIsDeadOrGhost("player") end)
    try("corpse on current map", function() return C_DeathInfo.GetCorpseMapPosition(map) end)
    add("(release at a graveyard and run this again to see the corpse position)")

    add("-- quests")
    try("super tracked quest", function() return C_SuperTrack.GetSuperTrackedQuestID() end)
    try("quests on this map", function()
        local q = C_QuestLog.GetQuestsOnMap(map)
        local n = type(q) == "table" and #q or 0
        local first = q and q[1]
        return n, first and first.questID, first and first.x, first and first.y
    end)
    try("next waypoint of the first quests in the log", function()
        local lines = {}
        for i = 1, math.min(5, C_QuestLog.GetNumQuestLogEntries()) do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local m, x, y = C_QuestLog.GetNextWaypoint(info.questID)
                lines[#lines + 1] = info.questID .. ":" .. show(m) .. "," .. show(x) .. "," .. show(y)
            end
        end
        return table.concat(lines, "  ")
    end)

    add("-- flight points")
    try("taxi nodes on this map (count, first)", function()
        local nodes = C_TaxiMap.GetAllTaxiNodes(map)
        local n = type(nodes) == "table" and #nodes or 0
        local f = nodes and nodes[1]
        if not f then return n end
        return n, f.name, f.nodeID, f.state, f.position
    end)

    add("-- dungeon entrances")
    try("entrances on this map", function()
        local e = C_EncounterJournal.GetDungeonEntrancesForMap(map)
        local n = type(e) == "table" and #e or 0
        local f = e and e[1]
        if not f then return n end
        return n, f.name, f.position
    end)

    OMQ:ShowReport(out)
end

OMQ.GuideProbe = run
