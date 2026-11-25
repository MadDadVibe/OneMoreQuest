-- One More Quest: removed quests and holiday/world event quests (decision 708)
--   OMQ.QuestHidden(id) is true for a quest that is gone from the game (Data/QuestStatus.lua, OMQ.QuestRemoved) and
--   for a holiday or world event quest (OMQ.QuestEvent) while its event does not run. Whether an event runs comes
--   from the game calendar (C_Calendar, holidays of today): by the holiday's event ID or, for both client languages,
--   by words in its title. "seasonal" = a holiday quest we could not place: shown during any holiday but the
--   Darkmoon Faire. The quest givers on the world map use it (MadDadVibe: event quests only while the event runs).
--   /omq events lists today's holidays and which OMQ events count as running.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local E = {}
OMQ.QuestEvents = E

E.CACHE = 600            -- seconds a calendar look is kept
-- event key -> { holiday event IDs, title words (English and German, lower case) }
E.EVENTS = {
    winterveil = { ids = { 141 }, words = { "winter veil", "winterhauch" } },
    hallowsend = { ids = { 324 }, words = { "hallow", "schlotternächte", "schlotternaechte" } },
    lunar      = { ids = { 327 }, words = { "lunar festival", "mondfest" } },
    love       = { ids = { 335, 423 }, words = { "love is in the air", "liebe liegt in der luft" } },
    harvest    = { ids = { 321 }, words = { "harvest festival", "erntedank" } },
    childrens  = { ids = { 201 }, words = { "children's week", "kinderwoche" } },
    midsummer  = { ids = { 341 }, words = { "midsummer", "sonnenwende" } },
    dmf        = { ids = { 374, 375, 376, 479 }, words = { "darkmoon", "dunkelmond" } },
    scourge    = { ids = {}, words = { "scourge invasion", "invasion der geißel", "invasion der geissel" } },
    aq         = { ids = {}, words = { "ahn'qiraj" } },
}

local isSecret = function(v) return issecretvalue and issecretvalue(v) end
local function now() return GetTime and GetTime() or 0 end
local cache, cacheAt, opened = nil, -1e9, false

-- the event key of one calendar holiday, or nil
function E.KeyOf(id, title)
    local t = (type(title) == "string" and not isSecret(title)) and title:lower() or ""
    for key, ev in pairs(E.EVENTS) do
        for _, x in ipairs(ev.ids) do if id == x then return key end end
        for _, w in ipairs(ev.words) do
            if t ~= "" and t:find(w, 1, true) then return key end
        end
    end
    return nil
end

-- today's holidays: { { id, title, key } }
function E.Today()
    local out = {}
    local C = C_Calendar
    if not (C and C.GetNumDayEvents and C.GetDayEvent) then return out end
    if not opened and C.OpenCalendar then opened = true; pcall(C.OpenCalendar) end
    local today = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if type(today) ~= "table" or not today.monthDay then return out end
    -- the day events are asked relative to the month the calendar shows (the calendar window may show another one)
    local offset = 0
    if C.GetMonthInfo then
        local ok, mi = pcall(C.GetMonthInfo, 0)
        if ok and type(mi) == "table" and mi.month and mi.year and today.month and today.year then
            offset = (today.year - mi.year) * 12 + (today.month - mi.month)
        end
    end
    local ok, n = pcall(C.GetNumDayEvents, offset, today.monthDay)
    if not ok or type(n) ~= "number" then return out end
    for i = 1, n do
        local ok2, ev = pcall(C.GetDayEvent, offset, today.monthDay, i)
        if ok2 and type(ev) == "table" and ev.calendarType == "HOLIDAY" then
            out[#out + 1] = { id = ev.eventID, title = ev.title, key = E.KeyOf(ev.eventID, ev.title) }
        end
    end
    return out
end

-- { [event key] = true } for the events running now, "any" = a holiday other than the Darkmoon Faire
function E.Active(force)
    if cache and not force and now() - cacheAt < E.CACHE then return cache end
    local act = {}
    for _, h in ipairs(E.Today()) do
        if h.key then act[h.key] = true end
        if h.key ~= "dmf" then act.any = true end
    end
    cache, cacheAt = act, now()
    return act
end
function E.Forget() cache = nil end

-- is this quest to be left out now: removed, or its event does not run
function E.Hidden(id)
    if OMQ.QuestRemoved and OMQ.QuestRemoved[id] then return true end
    local key = OMQ.QuestEvent and OMQ.QuestEvent[id]
    if not key then return false end
    local act = E.Active()
    if key == "seasonal" then return not act.any end
    return not act[key]
end
OMQ.QuestHidden = E.Hidden

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "CALENDAR_UPDATE_EVENT_LIST")
f:SetScript("OnEvent", function()
    E.Forget()
    if OMQ.QuestGiverMap and OMQ.QuestGiverMap.MarkDirty then OMQ.QuestGiverMap.MarkDirty() end
end)

OMQ:RegisterCommand("events", function()
    local out = { "Holidays today (game calendar):" }
    local list = E.Today()
    for _, h in ipairs(list) do
        out[#out + 1] = string.format("  %s (%s) -> %s", tostring(h.title), tostring(h.id), h.key or "not an OMQ event")
    end
    if #list == 0 then out[#out + 1] = "  none (or the calendar has not loaded yet)" end
    local keys = {}
    for k in pairs(E.Active(true)) do keys[#keys + 1] = k end
    table.sort(keys)
    out[#out + 1] = "Event quests shown for: " .. (#keys > 0 and table.concat(keys, ", ") or "nothing")
    OMQ:ShowReport(out)
end, "holidays of today and which event quests OMQ shows: /omq events")
