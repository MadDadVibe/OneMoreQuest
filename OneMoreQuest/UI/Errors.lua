-- One More Quest: error log and error collection
-- Every Lua error that touches One More Quest (its text or call stack names the addon), every error the addon caught
-- itself (OMQ:Error) and every blocked action of the addon is kept in OMQDB.errorLog (the same error once, with a count,
-- first and last time and the version; at most MAX_LOG, the stack shortened). Nothing is printed.
-- Collection: on one account "/omq errors collect on" makes it the collector. A collector in the group asks the dads
-- for their errors (XQ, at a group change and every ten minutes); every dad sends the errors the collector has not
-- confirmed yet, a few at a time, in parts over the bulk lane (XP), never in a fight. The collector keeps them per dad in
-- OMQDB.errorsIn (the game writes them into SavedVariables\OneMoreQuest.lua at logout or /reload) and confirms (XA).
-- Only the error text, the stack, the version, the character name and the times travel.
-- /omq errors: my own log; "show <dad>"; "collect on|off"; "sync"; "clear"; "clear collected".
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local E = {}
OMQ.Errors = E

local MAX_LOG = 50          -- my own errors
local MAX_PER_DAD = 100     -- errors kept per dad at the collector
local MAX_MSG = 400         -- characters of the error text
local MAX_STACK = 1000      -- characters of the call stack
local MAX_TRAIL = 2500      -- characters of the stack of a game bar error / bar finding (the trail, decision 527)
local PART = 190            -- characters per message part (the game allows 255 per message)
local PER_PUSH = 5          -- errors sent per round; the next round follows the confirmation
local RESEND_AFTER = 120    -- an unconfirmed error goes out again after this
local ASK_EVERY = 600       -- the collector asks again while grouped
local ASK_GAP = 30          -- never two questions closer than this
local BUFFER_TTL = 300      -- half received errors are dropped after this

local log = {}              -- my own entries, oldest first
local inFlight = {}         -- id -> time sent
local pending = false       -- the collector asked during a fight
local collectorAt = nil     -- when a collector last asked
local lastAsk = -1000
local parts = {}            -- sender .. id -> { n, got, list, at }

local function now() return GetTime and GetTime() or 0 end
local function stamp() return date and date("%Y-%m-%d %H:%M:%S") or "?" end
local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function short(s) return (tostring(s or ""):match("^[^-]+")) or tostring(s or "") end

-- a short stable id for an error: the same text (without memory addresses) gives the same id
function E.Id(kind, msg)
    local s = tostring(kind) .. ":" .. tostring(msg):gsub("0x%x+", ""):gsub(": %x%x%x%x%x%x%x%x+", ""):gsub("%s+$", "")
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

-- the error concerns this addon
function E.Ours(msg, stack)
    local t = tostring(msg or "") .. "\n" .. tostring(stack or "")
    return t:find("OneMoreQuest", 1, true) ~= nil
end

local function trimLog(list, max)
    while #list > max do
        local oldest, at = 1, nil
        for i, e in ipairs(list) do
            if not at or (e.last or "") < at then oldest, at = i, e.last or "" end
        end
        table.remove(list, oldest)
    end
end

-- keep one error; returns the entry
function E.Record(kind, msg, stack)
    msg = tostring(msg or "?"):sub(1, MAX_MSG)
    local cap = (kind == "game" or kind == "taint") and MAX_TRAIL or MAX_STACK
    stack = stack and tostring(stack):sub(1, cap) or nil
    local id = E.Id(kind, msg)
    local t = stamp()
    for _, e in ipairs(log) do
        if e.id == id then
            e.count = (e.count or 1) + 1
            e.last = t
            e.version = OMQ.version
            if stack and stack ~= "" then e.stack = stack end
            E.Soon()
            return e
        end
    end
    local me = OMQ.GetSelf and OMQ:GetSelf()
    local e = { id = id, kind = kind, msg = msg, stack = stack, count = 1, first = t, last = t,
        version = OMQ.version, char = me and me.name or "?" }
    log[#log + 1] = e
    trimLog(log, MAX_LOG)
    if OMQ.db then OMQ.db.errorLog = log end
    E.Soon()
    return e
end

function E.Log() return log end

----------------------------------------------------------------------
-- Catching the errors
----------------------------------------------------------------------
local busy = false
local function grab(msg, stack)
    if busy then return end
    busy = true
    pcall(function()
        if E.Ours(msg, stack) then E.Record("lua", msg, stack)
        elseif OMQ.TaintWatch and OMQ.TaintWatch.IsBarError(msg) then
            -- the game's own bar error names no addon (decision 507): kept as kind "game", then the bar watch looks
            local st = stack
            if OMQ.TaintWatch.ErrorStack then
                local ok, s = pcall(OMQ.TaintWatch.ErrorStack, stack)
                if ok and s then st = s end
            end
            E.Record("game", msg, st)
            OMQ.TaintWatch.Soon("bar error")
        end
    end)
    busy = false
end
E.Grab = grab

-- BugGrabber (BugSack) keeps the error handler for itself; it tells its listeners instead
function E.Hook()
    local bg = _G.BugGrabber
    if type(bg) == "table" and type(bg.RegisterCallback) == "function" then
        local ok = pcall(bg.RegisterCallback, E, "BugGrabber_BugGrabbed", function(_, err)
            if type(err) == "table" then grab(err.message, err.stack) end
        end)
        if ok then E.hooked = "BugGrabber"; return E.hooked end
    end
    if type(geterrorhandler) == "function" and type(seterrorhandler) == "function" then
        local prev = geterrorhandler()
        seterrorhandler(function(msg, ...)
            local stack = debugstack and debugstack(2) or nil
            grab(msg, stack)
            if prev then return prev(msg, ...) end
        end)
        E.hooked = "handler"
    end
    return E.hooked
end

-- the errors the addon catches itself
local baseError = OMQ.Error
function OMQ:Error(where, err)
    baseError(self, where, err)
    if not busy then
        busy = true
        pcall(E.Record, "caught", tostring(where) .. ": " .. tostring(err))
        busy = false
    end
end

-- blocked actions of this addon (UI/Blocked.lua)
function E.Blocked(addon, func)
    if tostring(addon):find("OneMoreQuest", 1, true) then
        return E.Record("blocked", tostring(addon) .. ": " .. tostring(func) .. (inCombat() and " (in combat)" or ""))
    end
end

----------------------------------------------------------------------
-- Text for the messages: no separators, no line breaks
----------------------------------------------------------------------
local function esc(s)
    return (tostring(s or ""):gsub("[%%%^|\n\r]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function unesc(s)
    return (tostring(s or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local FIELDS = { "id", "kind", "count", "first", "last", "version", "char", "msg", "stack" }
function E.Pack(e)
    local out = {}
    for i, k in ipairs(FIELDS) do out[i] = esc(e[k]) end
    return table.concat(out, "^")
end
function E.Unpack(s)
    local e, i = {}, 0
    for f in (s .. "^"):gmatch("([^%^]*)%^") do
        i = i + 1
        if FIELDS[i] then e[FIELDS[i]] = unesc(f) end
    end
    if not e.id or e.id == "" or not e.msg then return nil end
    e.count = tonumber(e.count) or 1
    if e.stack == "" then e.stack = nil end
    return e
end

----------------------------------------------------------------------
-- The dad's side: send what the collector does not have yet
----------------------------------------------------------------------
function E.Unsent()
    local list = {}
    for _, e in ipairs(log) do
        if (e.count or 1) > (e.acked or 0) then
            local t = inFlight[e.id]
            if not t or now() - t > RESEND_AFTER then list[#list + 1] = e end
        end
    end
    table.sort(list, function(a, b) return (a.last or "") > (b.last or "") end)
    return list
end

function E.IsCollector() return OMQ.db and OMQ.db.errorCollect == true or false end

function E.Push()
    if E.IsCollector() or not OMQ:GetChannel() then return 0 end
    if inCombat() then pending = true; return 0 end
    pending = false
    local me = OMQ:GetSelf()
    if not me then return 0 end
    local n = 0
    for _, e in ipairs(E.Unsent()) do
        if n >= PER_PUSH then break end
        local text = E.Pack(e)
        local total = math.ceil(#text / PART)
        for i = 1, total do
            OMQ:SendBulk("XP", me.guid, e.id, i, total, text:sub((i - 1) * PART + 1, i * PART))
        end
        inFlight[e.id] = now()
        n = n + 1
    end
    return n
end

-- a new error while a collector is around: it goes out half a minute later
local soonAt = nil
function E.Soon()
    if not collectorAt or now() - collectorAt > 2 * ASK_EVERY or soonAt then return end
    soonAt = now()
    if C_Timer and C_Timer.After then
        C_Timer.After(30, function() soonAt = nil; E.Push() end)
    end
end

----------------------------------------------------------------------
-- The collector's side
----------------------------------------------------------------------
function E.Ask(force)
    if not E.IsCollector() or not OMQ:GetChannel() then return false end
    if not force and now() - lastAsk < ASK_GAP then return false end
    lastAsk = now()
    return OMQ:Send("XQ", "1")
end

local function store(dad, e)
    local db = OMQ.db
    if not db then return end
    db.errorsIn = type(db.errorsIn) == "table" and db.errorsIn or {}
    local list = db.errorsIn[dad] or {}
    db.errorsIn[dad] = list
    local old = list[e.id]
    if old then
        old.count = math.max(old.count or 1, e.count or 1)
        if (e.last or "") > (old.last or "") then old.last = e.last end
        if (e.first or "") < (old.first or "~") then old.first = e.first end
        old.version, old.stack, old.char = e.version, e.stack or old.stack, e.char
    else
        e.received = stamp()
        list[e.id] = e
        local n, oldest, at = 0, nil, nil
        for id, x in pairs(list) do
            n = n + 1
            if not at or (x.last or "") < at then oldest, at = id, x.last or "" end
        end
        if n > MAX_PER_DAD then list[oldest] = nil end
    end
end

local function onPart(fields, sender)
    if not E.IsCollector() then return end
    local guid, id, i, n, chunk = fields[1], fields[2], tonumber(fields[3]), tonumber(fields[4]), fields[5] or ""
    if not guid or not id or not i or not n or n < 1 or n > 40 or i < 1 or i > n then return end
    local key = tostring(sender) .. ":" .. id
    for k, b in pairs(parts) do
        if now() - b.at > BUFFER_TTL then parts[k] = nil end
    end
    local b = parts[key]
    if not b or b.n ~= n then b = { n = n, got = 0, list = {}, at = now() }; parts[key] = b end
    if not b.list[i] then b.got = b.got + 1 end
    b.list[i] = chunk
    b.at = now()
    if b.got < n then return end
    parts[key] = nil
    local e = E.Unpack(table.concat(b.list))
    if not e or e.id ~= id then return end
    store(short(sender), e)
    OMQ:Send("XA", guid, id, e.count)
end

local function onAsk()
    collectorAt = now()
    E.Push()
end

local function onAck(fields)
    local me = OMQ:GetSelf()
    if not me or fields[1] ~= me.guid then return end
    local id, count = fields[2], tonumber(fields[3]) or 0
    for _, e in ipairs(log) do
        if e.id == id then e.acked = math.max(e.acked or 0, count) end
    end
    inFlight[id] = nil
    for _ in pairs(inFlight) do return end
    E.Push()      -- the round is through: the next few
end

OMQ:RegisterMessage("XQ", onAsk)
OMQ:RegisterMessage("XP", onPart)
OMQ:RegisterMessage("XA", onAck)

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    if pending then E.Push() end
end)

OMQ:On("ROSTER_CHANGED", function() E.Ask() end)
OMQ:On("USER_JOINED", function() E.Ask() end)

OMQ:On("DB_READY", function()
    -- the log of the sessions before comes first; what happened during the load is added behind it
    local old = type(OMQ.db.errorLog) == "table" and OMQ.db.errorLog or {}
    if old ~= log then
        for _, e in ipairs(log) do old[#old + 1] = e end
        log = old
        trimLog(log, MAX_LOG)
    end
    OMQ.db.errorLog = log
end)

OMQ:On("READY", function()
    C_Timer.NewTicker(ASK_EVERY, function() E.Ask(true) end)
end)

E.Hook()

----------------------------------------------------------------------
-- /omq errors
----------------------------------------------------------------------
function E.Collected()
    local out = {}
    local inbox = OMQ.db and type(OMQ.db.errorsIn) == "table" and OMQ.db.errorsIn or {}
    for dad, list in pairs(inbox) do
        local n, total = 0, 0
        for _, e in pairs(list) do n = n + 1; total = total + (e.count or 1) end
        out[#out + 1] = { dad = dad, errors = n, total = total }
    end
    table.sort(out, function(a, b) return a.dad < b.dad end)
    return out
end

local function line(e)
    return string.format("%s x%d [%s] %s%s", e.last or "?", e.count or 1, e.kind or "?", (e.msg or "?"):sub(1, 160),
        e.version and (" v" .. e.version) or "")
end

function E.Report(dad)
    local lines = {}
    if dad and dad ~= "" then
        local inbox = OMQ.db and OMQ.db.errorsIn or {}
        local list = {}
        for name, l in pairs(inbox) do
            if name:lower() == dad:lower() then for _, e in pairs(l) do list[#list + 1] = e end end
        end
        table.sort(list, function(a, b) return (a.last or "") < (b.last or "") end)
        lines[1] = string.format("errors of %s: %d", dad, #list)
        for i = math.max(1, #list - 9), #list do lines[#lines + 1] = line(list[i]) end
    else
        lines[1] = string.format("errors: %d recorded (%s)", #log, tostring(E.hooked or "no hook"))
        for i = math.max(1, #log - 9), #log do lines[#lines + 1] = line(log[i]) end
        if E.IsCollector() then
            local c = E.Collected()
            local names = {}
            for _, x in ipairs(c) do names[#names + 1] = x.dad .. " " .. x.errors end
            lines[#lines + 1] = "collecting: " .. (#names > 0 and table.concat(names, ", ") or "nothing received yet")
                .. " (/omq errors show <name>; saved at logout or /reload)"
        end
    end
    for _, s in ipairs(lines) do OMQ:Print(s) end
    return lines
end

OMQ:RegisterCommand("errors", function(arg)
    local cmd, value = (arg or ""):match("^(%S*)%s*(.-)$")
    if cmd == "collect" then
        OMQ.db.errorCollect = not (value == "off" or value == "0") or nil
        OMQ:Print("errors: collecting from the group " .. (E.IsCollector() and "on" or "off"))
        if E.IsCollector() then E.Ask(true) end
    elseif cmd == "sync" then
        OMQ:Print(E.Ask(true) and "errors: asked the group" or "errors: not collecting or not in a group")
    elseif cmd == "show" then
        E.Report(value)
    elseif cmd == "clear" then
        if value == "collected" then
            OMQ.db.errorsIn = {}
            OMQ:Print("errors: collected errors cleared")
        else
            for i = #log, 1, -1 do log[i] = nil end
            OMQ:Print("errors: log cleared")
        end
    else
        E.Report()
    end
end, "errors of the addon: the log; 'show <dad>'; 'collect on|off'; 'sync'; 'clear [collected]'", true)
