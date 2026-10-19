-- One More Quest: Comm
-- Addon messages over the party channel, and the list of addon users.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local PREFIX = "OMQ"
local OFFLINE_AFTER = 3600      -- decision 57: offline after 1 hour of silence
local HEARTBEAT = 60            -- seconds between HELLO messages while grouped
local MIN_HELLO_GAP = 5         -- never send two HELLOs closer than this
local FIELD_SEP = "|"

OMQ.users = {}                  -- guid -> { guid, name, class, version, lastSeen }
-- a new id for every login or reload: the others see that we lost everything they sent (decision 199)
OMQ.loadId = tostring(math.random(100000, 999999))

----------------------------------------------------------------------
-- Codec (pure functions, no game API; tested outside the game)
----------------------------------------------------------------------
-- Message layout: TYPE|PROTOCOL|field|field|...
-- Fields must not contain the separator; we strip it defensively.
local function clean(s)
    return (tostring(s or ""):gsub("[|\n\r]", ""))
end

function OMQ.Encode(msgType, protocol, ...)
    local parts = { clean(msgType), tostring(protocol) }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = clean((select(i, ...)))
    end
    local text = table.concat(parts, FIELD_SEP)
    if #text > 255 then return nil, "message too long" end
    return text
end

function OMQ.Decode(text)
    if type(text) ~= "string" or text == "" then return nil end
    local fields = {}
    -- keep empty fields: split on the separator manually
    local start = 1
    while true do
        local s, e = text:find(FIELD_SEP, start, true)
        if not s then
            fields[#fields + 1] = text:sub(start)
            break
        end
        fields[#fields + 1] = text:sub(start, s - 1)
        start = e + 1
    end
    if #fields < 2 then return nil end
    local msgType = table.remove(fields, 1)
    local protocol = tonumber(table.remove(fields, 1))
    if not msgType or msgType == "" or not protocol then return nil end
    return msgType, protocol, fields
end

----------------------------------------------------------------------
-- Channel choice. Parties of up to 5 only (decision 37): no raids.
----------------------------------------------------------------------
function OMQ:GetChannel()
    -- dad simulator (Sim/Sim.lua): everything goes to the fake dads, nothing to real players
    if OMQ.Sim and OMQ.Sim.active then return "SIM" end
    if IsInRaid and IsInRaid() then return nil end
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------
-- Send queue (decision 199). The game throttles addon messages; a message it refuses is lost
-- without notice. Messages go out at once while the budget allows, the rest waits in a queue
-- (normal messages first, bulk like the gear after them) and a refused message is tried again.
-- messages at once, messages per second after that (a table, so a test can lift the limit)
OMQ._sendLimits = { burst = 10, rate = 4 }       -- the game's own throttle answers are retried (decision 217)
local MAX_QUEUE = 200
local tokens, refillAt = OMQ._sendLimits.burst, 0
local queue = { normal = {}, bulk = {} }
OMQ._sendQueue = queue

local function refill()
    local now = GetTime()
    local lim = OMQ._sendLimits
    tokens = math.min(lim.burst, tokens + (now - refillAt) * lim.rate)
    refillAt = now
end

-- "ok", "retry" (throttled, try again later) or "drop"
-- what happened to our messages, for /omq comm (decision 217)
OMQ.commStats = { ok = 0, retry = 0, drop = 0, lastCode = nil, received = {}, receivedAt = {} }
local CS = OMQ.commStats
local function rawSend(text, channel)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel)
    if not ok then OMQ:Error("send", res); CS.drop = CS.drop + 1; CS.lastCode = "error"; return "drop" end
    if res == false then CS.retry = CS.retry + 1; CS.lastCode = "false"; return "retry" end
    if type(res) == "number" and res ~= 0 then
        CS.lastCode = res
        local E = Enum and Enum.SendAddonMessageResult
        if E and (res == E.AddonMessageThrottle or res == E.ChannelThrottle) then CS.retry = CS.retry + 1; return "retry" end
        if not E and (res == 3 or res == 8) then CS.retry = CS.retry + 1; return "retry" end
        CS.drop = CS.drop + 1
        return "drop"
    end
    CS.ok = CS.ok + 1
    return "ok"
end

local function flush()
    if #queue.normal == 0 and #queue.bulk == 0 then return end
    local channel = OMQ:GetChannel()
    if not channel or channel == "SIM" then queue.normal, queue.bulk = {}, {}; OMQ._sendQueue = queue; return end
    refill()
    while tokens >= 1 do
        local lane = (#queue.normal > 0) and queue.normal or ((#queue.bulk > 0) and queue.bulk or nil)
        if not lane then break end
        local item = lane[1]
        local r = rawSend(item.text, channel)
        if r == "retry" then
            item.tries = (item.tries or 0) + 1
            if item.tries > 20 then table.remove(lane, 1); CS.drop = CS.drop + 1 end
            tokens = 0
            break
        end
        table.remove(lane, 1)
        tokens = tokens - 1
    end
end
OMQ._flush = flush

-- messages that only need their newest copy: a waiting older one is replaced (decision 217)
local LATEST_ONLY = { H = true, P = true, S = true, S2 = true, Q = true, L = true, L2 = true, TI = true }
local function enqueue(text, bulk, msgType)
    local lane = bulk and queue.bulk or queue.normal
    if msgType and LATEST_ONLY[msgType] then
        for _, item in ipairs(lane) do
            if item.msgType == msgType then item.text = text; item.tries = 0; return end
        end
    end
    if #queue.normal + #queue.bulk >= MAX_QUEUE then
        table.remove(#queue.bulk > 0 and queue.bulk or queue.normal, 1)
        CS.drop = CS.drop + 1
    end
    lane[#lane + 1] = { text = text, msgType = msgType }
end

local function send(self, bulk, msgType, ...)
    local channel = self:GetChannel()
    if not channel then return false end
    local text, err = OMQ.Encode(msgType, OMQ.protocol, ...)
    if not text then self:Error("send " .. msgType, err); return false end
    if channel == "SIM" then OMQ.Sim:Outgoing(text); return true end
    refill()
    -- straight out when nothing waits ahead of it in its lane (normal messages pass the bulk lane)
    local ahead = #queue.normal + (bulk and #queue.bulk or 0)
    if ahead == 0 and tokens >= 1 then
        local r = rawSend(text, channel)
        if r == "ok" then tokens = tokens - 1; return true end
        if r == "drop" then return false end
        tokens = 0
    end
    enqueue(text, bulk, msgType)
    return true
end

function OMQ:Send(msgType, ...) return send(self, false, msgType, ...) end
-- for big, not urgent data (the gear): waits behind everything else
function OMQ:SendBulk(msgType, ...) return send(self, true, msgType, ...) end
function OMQ:QueueLength() return #queue.normal + #queue.bulk end

local lastHello = 0
function OMQ:SendHello(force)
    local now = GetTime()
    if not force and now - lastHello < MIN_HELLO_GAP then return end
    local me = self:GetSelf()
    if not me then return end
    -- the full name (first and last) travels too: only the bet mail uses it (decision 173);
    -- the load id changes with every login or reload (decision 199)
    if self:Send("H", me.guid, me.name, me.version, me.class or "", me.fullName or "", OMQ.loadId) then
        lastHello = now
    end
end

----------------------------------------------------------------------
-- User list
----------------------------------------------------------------------
-- Who is in my group right now: guid -> position (party1 = 1 ... party4 = 4). Cached for a
-- moment; the roster events clear the cache.
local groupSet, groupAt = nil, -1000
local function groupMembers()
    local now = GetTime()
    if groupSet and now - groupAt < 0.25 then return groupSet end
    local set = {}
    if IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists and UnitExists(unit) then
                local g = UnitGUID(unit)
                if g and not (issecretvalue and issecretvalue(g)) then set[g] = i end
            end
        end
    end
    if OMQ.Sim and OMQ.Sim.active then
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        for i, g in ipairs(OMQ.Sim:Guids()) do set[g] = n + i end
    end
    groupSet, groupAt = set, now
    return set
end

-- Position of the player in my group (1 to 4), or nil when he is not in it.
function OMQ:GroupPosition(guid)
    if not guid then return nil end
    return groupMembers()[guid]
end

function OMQ:InGroup(guid)
    if self.assumeInGroup then return true end       -- tests without unit tokens
    return groupMembers()[guid] ~= nil
end

-- Heard from within the last hour (decision 57). The sessions use this to know who was met.
function OMQ:IsRecent(user)
    return user and (GetTime() - user.lastSeen) < OFFLINE_AFTER
end

-- "Online" means: heard from within the last hour AND in my group right now (decision 135).
function OMQ:IsOnline(user)
    return user and (GetTime() - user.lastSeen) < OFFLINE_AFTER and self:InGroup(user.guid) or false
end

function OMQ:TouchUser(guid, name, version, class, fullName)
    local u = self.users[guid]
    local isNew = (u == nil)
    if isNew then
        u = { guid = guid }
        self.users[guid] = u
    end
    u.name = name ~= "" and name or u.name or "?"
    u.version = version ~= "" and version or u.version
    u.class = class ~= "" and class or u.class
    if fullName and fullName ~= "" then u.fullName = fullName end
    u.lastSeen = GetTime()
    return u, isNew
end

-- Sorted list for UIs: the player first, then the others by name.
function OMQ:GetUserList()
    local me = self:GetSelf()
    local list = {}
    if me then
        list[1] = {
            guid = me.guid, name = me.name, class = me.class,
            version = me.version, isSelf = true, online = true,
        }
    end
    local others = {}
    for guid, u in pairs(self.users) do
        if not me or guid ~= me.guid then
            others[#others + 1] = {
                guid = guid, name = u.name, class = u.class, version = u.version,
                online = self:IsOnline(u), lastSeen = u.lastSeen,
            }
        end
    end
    table.sort(others, function(a, b) return (a.name or "") < (b.name or "") end)
    for _, o in ipairs(others) do list[#list + 1] = o end
    return list
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
local function handleHello(fields, sender)
    local guid, name, version, class = fields[1], fields[2], fields[3], fields[4]
    if not guid or guid == "" then return end
    local me = OMQ:GetSelf()
    if me and guid == me.guid then return end        -- our own echo
    local u, isNew = OMQ:TouchUser(guid, name or "", version or "", class or "", fields[5] or "")
    local loadId = fields[6]
    local reloaded = not isNew and loadId and loadId ~= "" and u.loadId and u.loadId ~= loadId
    if loadId and loadId ~= "" then u.loadId = loadId end
    if isNew or reloaded then
        -- a newcomer, or a dad after a reload who lost everything we sent: he gets it all again
        -- Answer once so the newcomer learns about us. No reply to known users,
        -- otherwise two clients would answer each other forever.
        OMQ:SendHello()
        OMQ:Fire("USER_JOINED", guid)
    end
    OMQ:Fire("USER_UPDATED", guid)
end

local messageHandlers = { H = handleHello }

-- Other modules register their message types here.
function OMQ:RegisterMessage(msgType, fn)
    -- two modules with the same type would silently replace each other's handler
    if messageHandlers[msgType] and messageHandlers[msgType] ~= fn then
        OMQ:Error("message type " .. tostring(msgType), "already registered by another module")
    end
    messageHandlers[msgType] = fn
end

local function onAddonMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if sender and channel ~= "SIM" then
        local who = tostring(sender):match("^[^-]+") or tostring(sender)
        CS.received[who] = (CS.received[who] or 0) + 1
        CS.receivedAt[who] = GetTime()
    end
    local msgType, protocol, fields = OMQ.Decode(text)
    if not msgType then return end
    if protocol ~= OMQ.protocol then return end      -- different protocol: ignore
    local fn = messageHandlers[msgType]
    if fn then
        local ok, err = pcall(fn, fields, sender, channel)
        if not ok then OMQ:Error("message " .. msgType, err) end
    end
end

-- a message from a simulated dad (Sim/Sim.lua), handled like one from the party
function OMQ:SimDeliver(text, sender)
    onAddonMessage(PREFIX, text, "SIM", sender)
end

function OMQ:ResetGroupCache() groupSet = nil end

----------------------------------------------------------------------
-- Events and heartbeat
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        onAddonMessage(...)
    else
        -- joined a group, group changed, or loaded: announce ourselves
        groupSet = nil
        OMQ:SendHello()
        OMQ:Fire("ROSTER_CHANGED")
    end
end)

OMQ:On("DB_READY", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
end)

OMQ:On("READY", function()
    C_Timer.NewTicker(0.3, function() local ok, err = pcall(flush); if not ok then OMQ:Error("send queue", err) end end)
    C_Timer.NewTicker(HEARTBEAT, function()
        if OMQ:GetChannel() then OMQ:SendHello(true) end
    end)
end)

OMQ:RegisterCommand("users", function()
    local list = OMQ:GetUserList()
    OMQ:Print("addon users (" .. #list .. "), channel: " .. tostring(OMQ:GetChannel()))
    for _, u in ipairs(list) do
        print(string.format("  %s%s  v%s  %s",
            u.name or "?", u.isSelf and " (you)" or "", tostring(u.version),
            u.online and "online" or "offline"))
    end
end, "list known addon users")

-- /omq comm: is anything going out and coming in? (decision 217) Both dads run it and compare.
OMQ:RegisterCommand("comm", function()
    local me = OMQ:GetSelf()
    OMQ:Print(string.format("comm: version %s, protocol %d, channel %s, load id %s", OMQ.version, OMQ.protocol,
        tostring(OMQ:GetChannel()), tostring(OMQ.loadId)))
    print(string.format("  sent ok %d, throttled and retried %d, dropped %d, last answer of the game %s, waiting %d (normal %d, bulk %d)",
        CS.ok, CS.retry, CS.drop, tostring(CS.lastCode), #queue.normal + #queue.bulk, #queue.normal, #queue.bulk))
    local any = false
    for who, n in pairs(CS.received) do
        any = true
        print(string.format("  received from %s: %d messages, last %.0f s ago", who, n, GetTime() - (CS.receivedAt[who] or 0)))
    end
    if not any then print("  received nothing from anybody yet") end
    for guid, u in pairs(OMQ.users) do
        if not me or guid ~= me.guid then
            print(string.format("  knows %s: version %s, %s, heard %.0f s ago, gear %s, stats %s", u.name or "?", tostring(u.version),
                OMQ:IsOnline(u) and "online" or "not in group", GetTime() - (u.lastSeen or 0), u.gear and "yes" or "no", u.values and "yes" or "no"))
        end
    end
end, "addon messages: sent, throttled, received, known dads")

OMQ:RegisterCommand("hello", function()
    OMQ:SendHello(true)
    OMQ:Print("hello sent on channel " .. tostring(OMQ:GetChannel()))
end, "send a hello to the group")
