-- One More Quest: /omq qtrack (decision 149, build step 1 of the group quest tracker)
-- Read-only. Finds out what WoW Forever tells an addon about quest objectives, so the tracker can be
-- built on what really works:
--   /omq qtrack              report now: functions, every quest in the log with its objectives
--   /omq qtrack watch [sec]  records quest events and every change of the objective counts for
--                            a while (default 180 s, also in combat), then shows the report
--   /omq qtrack stop         ends the recording early
-- The last report is also kept in the saved variables (OMQDB.qtrackReport).
-- Never registers the combat log (section 13.7).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.QTrackProbe = P

local WATCH_DEFAULT, WATCH_MAX = 180, 900
local MAX_LINES = 400
local EVENTS = { "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED",
                 "QUEST_REMOVED", "QUEST_TURNED_IN", "UI_INFO_MESSAGE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function show(v)
    if v == nil then return "nil" end
    if isSecret(v) then return "SECRET" end
    return (tostring(v):gsub("[%c|]", " "))
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
local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end

----------------------------------------------------------------------
-- Reading the quest log
----------------------------------------------------------------------
local function quests()
    local out = {}
    local CQ = C_QuestLog
    if not (CQ and CQ.GetNumQuestLogEntries and CQ.GetInfo) then return out end
    local ok, n = pcall(CQ.GetNumQuestLogEntries)
    if not ok or type(n) ~= "number" or isSecret(n) then return out end
    for i = 1, n do
        local okI, info = pcall(CQ.GetInfo, i)
        if okI and type(info) == "table" and not info.isHeader and type(info.questID) == "number"
            and not isSecret(info.questID) and info.questID > 0 then
            out[#out + 1] = info
        end
    end
    return out
end
P.Quests = quests

local function objectives(id)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil, "GetQuestObjectives missing" end
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
    if not ok then return nil, "error " .. show(list) end
    if type(list) ~= "table" then return nil, "returned " .. show(list) end
    return list
end

-- The counts of a quest as one short text ("3/10,1/6+" where + = finished), "secret" or nil.
function P.Signature(id)
    local list = objectives(id)
    if not list then return nil end
    local parts = {}
    for i, o in ipairs(list) do
        if type(o) ~= "table" then return nil end
        local n, m, f = o.numFulfilled, o.numRequired, o.finished
        if isSecret(n) or isSecret(m) or isSecret(f) then return "secret" end
        parts[i] = tostring(n) .. "/" .. tostring(m) .. (f and "+" or "")
    end
    return table.concat(parts, ",")
end

local function call(fn, ...)
    if not fn then return "missing" end
    local ok, v = pcall(fn, ...)
    if not ok then return "error " .. show(v) end
    return show(v)
end

----------------------------------------------------------------------
-- /omq qtrack: report now
----------------------------------------------------------------------
function P.Report()
    local out = {}
    local function add(t) out[#out + 1] = t end
    add("One More Quest " .. OMQ.version .. " quest tracker probe (read-only), in combat: " .. tostring(inCombat()))
    local Q = OMQ.QTrack
    if Q then
        add(string.format("tracker: option %s, master group %s, visible %s, shown %s, cards %d, stamp %s",
            tostring(not (OMQ.db and OMQ.db.options.qtrack == false)), tostring(OMQ:Master("group")),
            tostring(Q:IsVisible()), tostring(Q:Shown()), #Q:Cards(), tostring(Q:Stamp() ~= nil)))
    end
    local names = { "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives",
        "C_QuestLog.IsComplete", "C_QuestLog.ReadyForTurnIn", "C_QuestLog.GetTitleForQuestID",
        "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.IsOnQuest", "C_QuestLog.GetQuestDifficultyLevel",
        "GetQuestLogLeaderBoard", "GetNumQuestLeaderBoards", "GetQuestObjectiveInfo", "issecretvalue" }
    local missing = {}
    for _, n in ipairs(names) do if not exists(n) then missing[#missing + 1] = n end end
    add(#missing == 0 and "functions: all present" or ("functions MISSING: " .. table.concat(missing, ", ")))
    local list = quests()
    add("quests in the log: " .. #list)
    local CQ = C_QuestLog or {}
    for _, info in ipairs(list) do
        local id = info.questID
        add(string.format("quest %d '%s' level %s | info.isComplete %s | IsComplete %s | ReadyForTurnIn %s | title by id '%s'",
            id, show(info.title), show(info.level), show(info.isComplete), call(CQ.IsComplete, id),
            call(CQ.ReadyForTurnIn, id), call(CQ.GetTitleForQuestID, id)))
        local objs, why = objectives(id)
        if not objs then
            add("  objectives: " .. tostring(why))
        elseif #objs == 0 then
            add("  objectives: none")
        else
            for i, o in ipairs(objs) do
                add(string.format("  %d: type %s | %s/%s | finished %s | '%s'", i, show(o.type),
                    show(o.numFulfilled), show(o.numRequired), show(o.finished), show(o.text)))
            end
        end
        if GetQuestObjectiveInfo then
            local ok, text, typ, done, n, m = pcall(GetQuestObjectiveInfo, id, 1, false)
            if ok then add(string.format("  GetQuestObjectiveInfo(1): '%s' %s %s %s/%s", show(text), show(typ), show(done), show(n), show(m))) end
        end
    end
    -- a quest that is surely not in the log: does the game still give its title?
    add("title of a quest not in the log (5761 Slaying the Beast): '" .. call(CQ.GetTitleForQuestID, 5761) .. "'")
    add("title of a quest not in the log (168 Collecting Memories): '" .. call(CQ.GetTitleForQuestID, 168) .. "'")
    return out
end

----------------------------------------------------------------------
-- /omq qtrack watch: record events and changes of the counts
----------------------------------------------------------------------
local watch                 -- { untilAt, lines, counts, last = { id -> signature }, changes }
local frame = CreateFrame("Frame")

local function addLine(t)
    if not watch then return end
    if #watch.lines < MAX_LINES then
        watch.lines[#watch.lines + 1] = string.format("%7.1f %s %s", GetTime() - watch.startAt, inCombat() and "[combat]" or "        ", t)
    end
end

local function compare(reason)
    if not watch then return end
    local seen = {}
    for _, info in ipairs(quests()) do
        local id = info.questID
        seen[id] = true
        local sig = P.Signature(id)
        local old = watch.last[id]
        if old == nil then
            watch.last[id] = sig or "nil"
            if watch.ready then addLine(string.format("NEW quest %d '%s': %s (after %s)", id, show(info.title), show(sig), reason)) end
        elseif old ~= (sig or "nil") then
            watch.changes = watch.changes + 1
            if sig == "secret" then watch.secret = watch.secret + 1 end
            addLine(string.format("CHANGE quest %d '%s': %s -> %s (after %s)", id, show(info.title), old, show(sig), reason))
            watch.last[id] = sig or "nil"
        end
    end
    for id in pairs(watch.last) do
        if not seen[id] then addLine(string.format("GONE quest %d (after %s)", id, reason)); watch.last[id] = nil end
    end
end

local function finish()
    if not watch then return end
    for _, e in ipairs(EVENTS) do pcall(frame.UnregisterEvent, frame, e) end
    local w = watch
    watch = nil
    local out = { string.format("One More Quest %s quest tracker watch: %d s, %d changes of the counts (%d secret)",
        OMQ.version, math.floor(GetTime() - w.startAt + 0.5), w.changes, w.secret) }
    local ev = {}
    for e, n in pairs(w.counts) do ev[#ev + 1] = e .. " " .. n end
    table.sort(ev)
    out[#out + 1] = "events: " .. (#ev > 0 and table.concat(ev, ", ") or "none")
    out[#out + 1] = "-- timeline (seconds since start)"
    for _, l in ipairs(w.lines) do out[#out + 1] = l end
    out[#out + 1] = "-- state at the end"
    for _, l in ipairs(P.Report()) do out[#out + 1] = l end
    out[#out + 1] = "-- end. Please send this whole report (Ctrl+A, Ctrl+C in the window)."
    if OMQDB then OMQDB.qtrackReport = table.concat(out, "\n") end
    OMQ:Print("quest tracker watch finished: " .. w.changes .. " changes recorded")
    local ok = pcall(OMQ.ShowReport, OMQ, out)
    if not ok then for _, l in ipairs(out) do print(l) end end
end
P.Finish = finish

frame:SetScript("OnEvent", function(_, event, a1, a2)
    if not watch then return end
    local ok, err = pcall(function()
        watch.counts[event] = (watch.counts[event] or 0) + 1
        if event == "UI_INFO_MESSAGE" then
            addLine("UI_INFO_MESSAGE '" .. show(a2) .. "'")      -- the text is the second argument
        elseif event == "PLAYER_REGEN_DISABLED" then
            addLine("combat starts")
        elseif event == "PLAYER_REGEN_ENABLED" then
            addLine("combat ends")
        elseif event == "UNIT_QUEST_LOG_CHANGED" and a1 ~= "player" then
            return
        elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
            addLine(event .. " " .. show(a1))
        end
        compare(event)
        if GetTime() >= watch.untilAt then finish() end
    end)
    if not ok then OMQ:Error("qtrack " .. event, err) end
end)

function P.Start(seconds)
    if watch then OMQ:Print("quest tracker watch is already running (/omq qtrack stop ends it)"); return false end
    seconds = math.max(10, math.min(WATCH_MAX, tonumber(seconds) or WATCH_DEFAULT))
    watch = { startAt = GetTime(), untilAt = GetTime() + seconds, lines = {}, counts = {}, last = {},
              changes = 0, secret = 0 }
    compare("start")              -- the first snapshot never counts as a change
    watch.ready = true
    for _, e in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
    if C_Timer and C_Timer.After then C_Timer.After(seconds + 0.5, function() if watch then finish() end end) end
    OMQ:Print(string.format("quest tracker watch runs %d s: kill quest mobs, loot quest items, also in combat. /omq qtrack stop ends it.", seconds))
    return true
end

function P.IsWatching() return watch ~= nil end

OMQ:RegisterCommand("qtrack", function(arg)
    local cmd, value = (arg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "watch" then
        P.Start(value)
    elseif cmd == "position" then
        if OMQ.QTrackFrame then OMQ.QTrackFrame:ResetPosition() end
        OMQ:Print("quest tracker position reset")
    elseif cmd == "bg" then
        local f = OMQ.QTrackFrame
        if f then
            if value ~= "" then f:SetBackground(value:lower()) else f:CycleBackground() end
            OMQ:Print("quest tracker background: " .. f:Background())
        end
    elseif cmd == "demo" then
        if OMQ.QTrack then OMQ.QTrack:Demo(value == "stamp") end
    elseif cmd == "stop" then
        if watch then finish() else OMQ:Print("no quest tracker watch running") end
    else
        local out = P.Report()
        out[#out + 1] = "-- /omq qtrack watch [seconds] records quest progress over time. Please send this whole report."
        if OMQDB then OMQDB.qtrackReport = table.concat(out, "\n") end
        local ok = pcall(OMQ.ShowReport, OMQ, out)
        if not ok then for _, l in ipairs(out) do print(l) end end
    end
end, "group quest tracker: /omq qtrack (report) | watch [seconds] | stop | demo [stamp] | position | bg [none|light|full]")
