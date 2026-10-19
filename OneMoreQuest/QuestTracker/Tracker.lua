-- One More Quest: group quest tracker, logic (section 21, decisions 149 to 158)
-- The tracker appears on every dad's screen as soon as any dad makes quest progress, shows the
-- progress of every dad in the group, and hides 60 s after the last progress of any dad. One card
-- per quest, newest in front. When every dad who has a quest has all its objectives fulfilled, the
-- One More Quest stamp lands on the card; 5 s later the card goes.
--   QP|proto|guid|questID|counts     own progress (opens the tracker everywhere)
--   QR|proto|guid|questID|counts     own counts as an answer when a card opens (opens nothing)
--   QG|proto|guid|questID            the quest left my log (turned in or abandoned)
-- counts = "n/m" per objective, separated by ",", "+" at the end when the objective is finished.
-- Own progress is always sent, whatever the option or the master switch says (decision 156).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local T = {}
OMQ.QTrack = T

local HIDE_AFTER = 60            -- decision 154
local STAMP_SECONDS = 5
local SEND_DELAY = 0.5           -- updates of one quest within this time go out as one message (R5)
local STAMP_CHECK = 1.5          -- wait this long for the answers before judging "everybody is done"
local READ_DELAY = 0.2           -- the quest log settles after the event
local MAX_OBJ = 8
local MAX_COLS = 5
local FLASH_SECONDS = 1.3
T.HIDE_AFTER, T.STAMP_SECONDS = HIDE_AFTER, STAMP_SECONDS

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function now() return GetTime() end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local mine = {}              -- questID -> { counts = {{n,m,f}...}, title, level, texts = {} }
local primed = false         -- the first reading after login or reload never counts as progress
local others = {}            -- questID -> guid -> counts
local leftQuest = {}         -- questID -> guid -> true (that dad turned in or abandoned it)
local cards = {}             -- questIDs, newest progress first
local idx = 1
local visible = false
local lastProgress = -math.huge
local cardAt = {}             -- questID -> last progress of any dad on that card (decision 178)
local stamp = nil            -- { qid, untilAt, startedAt }
local judgeAt = {}           -- questID -> time to check "everybody is done"
local flash = nil            -- { qid, guid, at }
local sendAt = {}            -- questID -> time to send QP
local answered = {}          -- questID -> true: we sent our QR for the open card
local hovering = false
local readAt = nil

----------------------------------------------------------------------
-- Counts
----------------------------------------------------------------------
function T.Encode(counts)
    local parts = {}
    for i = 1, math.min(#counts, MAX_OBJ) do
        local c = counts[i]
        parts[i] = string.format("%d/%d%s", c.n, c.m, c.f and "+" or "")
    end
    return table.concat(parts, ",")
end

function T.Decode(text)
    if type(text) ~= "string" then return nil end
    local out = {}
    for n, m, f in text:gmatch("(%d+)/(%d+)(%+?)") do
        out[#out + 1] = { n = tonumber(n), m = tonumber(m), f = f == "+" }
        if #out >= MAX_OBJ then break end
    end
    return out
end

local function objDone(c) return c and (c.f or (c.m > 0 and c.n >= c.m)) end

function T.Complete(counts)
    if type(counts) ~= "table" or #counts == 0 then return false end
    for _, c in ipairs(counts) do if not objDone(c) then return false end end
    return true
end

-- "Prachtkrallenpelz: 7/10" -> "Prachtkrallenpelz", "0/1 Use the emote" -> "Use the emote"
function T.Label(text)
    if type(text) ~= "string" or isSecret(text) then return nil end
    local a = text:match("^(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
    if a and a ~= "" then return a end
    local b = text:match("^%s*%d+%s*/%s*%d+%s+(.+)$")
    if b and b ~= "" then return b end
    return text
end

----------------------------------------------------------------------
-- Reading the own quest log
----------------------------------------------------------------------
local function readLog()
    local out = {}
    local CQ = C_QuestLog
    if not (CQ and CQ.GetNumQuestLogEntries and CQ.GetInfo and CQ.GetQuestObjectives) then return nil end
    local ok, num = pcall(CQ.GetNumQuestLogEntries)
    if not ok or type(num) ~= "number" or isSecret(num) then return nil end
    for i = 1, num do
        local okI, info = pcall(CQ.GetInfo, i)
        local id = okI and type(info) == "table" and not info.isHeader and info.questID
        if type(id) == "number" and not isSecret(id) and id > 0 then
            local okO, objs = pcall(CQ.GetQuestObjectives, id)
            local counts, texts, readable = {}, {}, true
            if okO and type(objs) == "table" then
                for j, o in ipairs(objs) do
                    if j > MAX_OBJ then break end
                    local n, m, f = o.numFulfilled, o.numRequired, o.finished
                    if isSecret(n) or isSecret(m) or isSecret(f) or type(n) ~= "number" or type(m) ~= "number" then
                        readable = false
                        break
                    end
                    counts[j] = { n = n, m = m, f = f and true or false }
                    texts[j] = T.Label(o.text)
                end
            end
            if readable then
                out[id] = { counts = counts, texts = texts,
                            title = not isSecret(info.title) and info.title or nil, level = info.level }
            elseif mine[id] then
                out[id] = mine[id]          -- unreadable right now (R4): keep the last known state
            end
        end
    end
    return out
end

local function progressed(old, new)
    if not (old and new) or #old.counts ~= #new.counts then return false end
    for i, c in ipairs(new.counts) do
        local o = old.counts[i]
        if c.n > o.n or (c.f and not o.f) then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Who is shown
----------------------------------------------------------------------
-- me first, then the online dads in group order, at most 5 (R8)
function T:Columns()
    local me = OMQ:GetSelf()
    local cols = {}
    if me then cols[1] = { guid = me.guid, name = me.name, class = me.class, isSelf = true } end
    local list = {}
    for guid, u in pairs(OMQ.users or {}) do
        if (not me or guid ~= me.guid) and OMQ:IsOnline(u) then
            list[#list + 1] = { guid = guid, name = u.name, class = u.class, pos = OMQ:GroupPosition(guid) or 9 }
        end
    end
    table.sort(list, function(a, b)
        if a.pos ~= b.pos then return a.pos < b.pos end
        return (a.name or "") < (b.name or "")
    end)
    for _, c in ipairs(list) do
        if #cols >= MAX_COLS then break end
        cols[#cols + 1] = c
    end
    return cols
end

-- counts of a dad for a quest; nil = unknown; false = he does not have it
function T:CountsOf(qid, guid)
    local me = OMQ:GetSelf()
    if me and guid == me.guid then return mine[qid] and mine[qid].counts or false end
    if leftQuest[qid] and leftQuest[qid][guid] then return false end
    local c = others[qid] and others[qid][guid]
    if c then return c end
    local u = OMQ.users and OMQ.users[guid]
    if u and u.quests then return u.quests[qid] and nil or false end     -- quest list from quest sync
    return nil
end

-- every online dad who has the quest has all objectives fulfilled (decision 151)
function T:EverybodyDone(qid)
    local any = false
    for _, col in ipairs(self:Columns()) do
        local c = self:CountsOf(qid, col.guid)
        if c == nil then return false end                -- he may have it, no numbers yet
        if c then
            if not T.Complete(c) then return false end
            any = true
        end
    end
    return any
end

----------------------------------------------------------------------
-- Cards and visibility
----------------------------------------------------------------------
local function fire() OMQ:Fire("QTRACK_CHANGED") end

local function cardIndex(qid)
    for i, q in ipairs(cards) do if q == qid then return i end end
end

local function toFront(qid)
    local i = cardIndex(qid)
    if i then table.remove(cards, i) end
    table.insert(cards, 1, qid)
    idx = 1
    return i == nil
end

function T:Hide()
    visible, cards, idx, stamp = false, {}, 1, nil
    cardAt = {}
    answered, judgeAt = {}, {}
    fire()
end

local function sendCounts(kind, qid)
    local me = OMQ:GetSelf()
    local m = mine[qid]
    if not (me and m and OMQ:GetChannel()) then return end
    OMQ:Send(kind, me.guid, tostring(qid), T.Encode(m.counts))
end

-- progress of any dad (own or received): the card comes to the front, the 60 s start again
local function progress(qid, guid)
    local isNew = toFront(qid)
    lastProgress = now()
    cardAt[qid] = now()
    visible = true
    flash = { qid = qid, guid = guid, at = now() }
    if OMQ.Sound and T:Shown() then OMQ.Sound:Play("update") end
    judgeAt[qid] = now() + STAMP_CHECK
    local me = OMQ:GetSelf()
    -- the card just opened here: answer once with my own numbers (R7)
    if (isNew or not answered[qid]) and me and guid ~= me.guid and mine[qid] then
        answered[qid] = true
        sendCounts("QR", qid)
    end
    fire()
end

local function ownProgress(qid)
    if not sendAt[qid] then sendAt[qid] = now() + SEND_DELAY end
    local me = OMQ:GetSelf()
    if me then progress(qid, me.guid) end
    -- the others hear of it SEND_DELAY later: judge at the same moment as they do, so the stamp is in sync
    judgeAt[qid] = sendAt[qid] + STAMP_CHECK
end

local function questGone(qid)
    local me = OMQ:GetSelf()
    if me and OMQ:GetChannel() then OMQ:Send("QG", me.guid, tostring(qid)) end
    sendAt[qid] = nil
    local i = cardIndex(qid)
    if i and not (stamp and stamp.qid == qid) then
        table.remove(cards, i)                       -- R16: the card of a quest that left my log goes
        if idx > #cards then idx = 1 end
        if #cards == 0 then T:Hide() return end
    end
    fire()
end

function T:Read()
    local new = readLog()
    if not new then return end
    local hits, gone = {}, {}
    if primed then
        for qid, q in pairs(new) do
            if progressed(mine[qid], q) then hits[#hits + 1] = qid end
        end
        for qid in pairs(mine) do if not new[qid] then gone[#gone + 1] = qid end end
    end
    mine, primed = new, true
    table.sort(hits)
    for _, qid in ipairs(gone) do questGone(qid) end
    for _, qid in ipairs(hits) do ownProgress(qid) end
    if #hits == 0 and #gone == 0 and visible then fire() end
end

----------------------------------------------------------------------
-- Messages
----------------------------------------------------------------------
local function sender(f)
    local guid, qid = f[1], tonumber(f[2])
    local me = OMQ:GetSelf()
    if not (guid and qid) or (me and guid == me.guid) then return nil end
    local u = OMQ.users and OMQ.users[guid]
    if not (u and OMQ:IsOnline(u)) then return nil end      -- only dads in my group (R6)
    return guid, qid
end

local function store(qid, guid, text)
    local counts = T.Decode(text)
    if not counts then return false end
    others[qid] = others[qid] or {}
    others[qid][guid] = counts
    if leftQuest[qid] then leftQuest[qid][guid] = nil end
    return true
end

OMQ:RegisterMessage("QP", function(f)
    local guid, qid = sender(f)
    if not guid or not store(qid, guid, f[3]) then return end
    progress(qid, guid)
end)

OMQ:RegisterMessage("QR", function(f)
    local guid, qid = sender(f)
    if not guid or not store(qid, guid, f[3]) then return end
    if visible and cardIndex(qid) then judgeAt[qid] = judgeAt[qid] or (now() + 0.2) end
    fire()
end)

OMQ:RegisterMessage("QG", function(f)
    local guid, qid = sender(f)
    if not guid then return end
    if others[qid] then others[qid][guid] = nil end
    leftQuest[qid] = leftQuest[qid] or {}
    leftQuest[qid][guid] = true
    fire()
end)

----------------------------------------------------------------------
-- Clock
----------------------------------------------------------------------
function T:Update()
    local t = now()
    if readAt and t >= readAt then readAt = nil; self:Read() end
    for qid, at in pairs(sendAt) do
        if t >= at then sendAt[qid] = nil; sendCounts("QP", qid) end
    end
    if stamp then
        if t >= stamp.untilAt then
            local qid = stamp.qid
            stamp = nil
            local i = cardIndex(qid)
            if i then table.remove(cards, i) end
            judgeAt[qid], cardAt[qid] = nil, nil
            if #cards == 0 then self:Hide() return end
            idx = 1                                      -- the newest other card; the 60 s go on (R18)
            fire()
        end
        return                                           -- nothing else happens during the stamp (R19)
    end
    if not visible then return end
    for qid, at in pairs(judgeAt) do
        if t >= at then
            judgeAt[qid] = nil
            if cardIndex(qid) and self:EverybodyDone(qid) then
                toFront(qid)
                stamp = { qid = qid, startedAt = t, untilAt = t + STAMP_SECONDS }
                if OMQ.Sound and self:Shown() then OMQ.Sound:Play("done") end
                fire()
                return
            end
        end
    end
    -- every card goes 60 s after its own last progress; hovering keeps all of them (decisions 158 and 178)
    if not hovering then
        local removed = false
        for i = #cards, 1, -1 do
            local qid = cards[i]
            if t >= (cardAt[qid] or lastProgress) + HIDE_AFTER then
                table.remove(cards, i)
                cardAt[qid], judgeAt[qid], answered[qid] = nil, nil, nil
                if i < idx then idx = idx - 1 end
                removed = true
            end
        end
        if #cards == 0 then self:Hide() return end
        if removed then
            if idx > #cards then idx = 1 end
            fire()
        end
    end
end

----------------------------------------------------------------------
-- View for the frame
----------------------------------------------------------------------
local titleAsked = {}
local function titleOf(qid)
    local m = mine[qid]
    if m and m.title then return m.title, m.level end
    local CQ = C_QuestLog
    if CQ and CQ.GetTitleForQuestID then
        local ok, t = pcall(CQ.GetTitleForQuestID, qid)
        if ok and type(t) == "string" and not isSecret(t) and t ~= "" then return t end
    end
    if not titleAsked[qid] and CQ and CQ.RequestLoadQuestByID then         -- the title comes later (probe)
        titleAsked[qid] = true
        pcall(CQ.RequestLoadQuestByID, qid)
    end
    return "Quest " .. qid
end

-- Four stamps in the colours of the item qualities (decision 160). Every dad sees the same one: it is
-- picked from the quest ID, scrambled so that quests in a row get different stamps.
T.STAMPS = {
    { key = "uncommon",  file = "Interface\\AddOns\\OneMoreQuest\\Media\\Stamp_Uncommon",  color = { 0.12, 1.00, 0.00 } },
    { key = "rare",      file = "Interface\\AddOns\\OneMoreQuest\\Media\\Stamp_Rare",      color = { 0.19, 0.55, 1.00 } },
    { key = "epic",      file = "Interface\\AddOns\\OneMoreQuest\\Media\\Stamp_Epic",      color = { 0.64, 0.21, 0.93 } },
    { key = "legendary", file = "Interface\\AddOns\\OneMoreQuest\\Media\\Stamp_Legendary", color = { 1.00, 0.50, 0.00 } },
}
function T.StampFor(qid)
    local h = (tonumber(qid) or 0) * 2654435761 % 4294967296      -- Knuth's multiplicative hash
    return T.STAMPS[math.floor(h * #T.STAMPS / 4294967296) + 1]       -- the top bits mix best
end

function T:IsVisible() return visible end
function T:Shown()
    return visible and OMQ:Master("group") and not (OMQ.db and OMQ.db.options and OMQ.db.options.qtrack == false)
end
function T:Cards() return cards end
function T:Index() return idx end
function T:Stamp() return stamp end
function T:SetHover(on) hovering = on and true or false end
function T:HideAt() return lastProgress + HIDE_AFTER end          -- the last card goes then
function T:CardHideAt(qid) return cardAt[qid] and (cardAt[qid] + HIDE_AFTER) or nil end

function T:Next(step)
    if stamp or #cards < 2 then return end
    idx = ((idx - 1 + (step or 1)) % #cards) + 1         -- switching does not restart the 60 s (R15)
    fire()
end

-- right click: closed on this client until the next progress of any dad (decision 157)
function T:Close()
    self:Hide()
end

function T:View()
    local qid = stamp and stamp.qid or cards[idx]
    if not qid then return nil end
    local title, level = titleOf(qid)
    local cols = self:Columns()
    local m = mine[qid]
    local nrows = 0
    for _, col in ipairs(cols) do
        local c = self:CountsOf(qid, col.guid)
        if c and #c > nrows then nrows = #c end
    end
    local fresh = flash and flash.qid == qid and (now() - flash.at) < FLASH_SECONDS
    local rows = {}
    for i = 1, nrows do
        local row = { text = (m and m.texts[i]) or ("Objective " .. i), cells = {} }
        for j, col in ipairs(cols) do
            local c = self:CountsOf(qid, col.guid)
            local cell
            if c == false then cell = { text = "-", state = "none" }
            elseif c == nil then cell = { text = "...", state = "wait" }
            elseif c[i] then
                local done = objDone(c[i])
                cell = { text = c[i].n .. "/" .. c[i].m, state = done and "done" or "open" }
            else cell = { text = "", state = "none" } end
            cell.lit = fresh and flash.guid == col.guid or false
            cell.isSelf = col.isSelf
            row.cells[j] = cell
        end
        rows[i] = row
    end
    return { qid = qid, title = title, level = level, cols = cols, rows = rows,
             nav = idx .. " / " .. #cards, showNav = not stamp and #cards > 1, stamp = stamp ~= nil,
             stampKind = stamp and T.StampFor(qid) or nil }
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    pcall(frame.RegisterEvent, frame, e)
end
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
    readAt = readAt or (now() + READ_DELAY)
end)

OMQ:On("READY", function()
    pcall(T.Read, T)                                     -- the first reading: no progress
    C_Timer.NewTicker(0.1, function()
        local ok, err = pcall(T.Update, T)
        if not ok then OMQ:Error("qtrack", err) end
    end)
end)

-- a dad leaves the group: his column goes (the next view is built without him)
OMQ:On("ROSTER_CHANGED", function() if visible then fire() end end)

-- test and demo helpers
T._progress = progress
function T:Mine() return mine end
function T:Demo(withStamp)
    local me = OMQ:GetSelf()
    local qid
    for id in pairs(mine) do if not qid or id < qid then qid = id end end
    if not (me and qid) then OMQ:Print("demo: you need a quest in your log"); return end
    progress(qid, me.guid)
    if withStamp then stamp = { qid = qid, startedAt = now(), untilAt = now() + STAMP_SECONDS }; fire() end
end
