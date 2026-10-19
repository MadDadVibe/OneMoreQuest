-- One More Quest: /omq mailprobe (Bet Check, build step 1, decisions 161 to 173)
-- Finds out what WoW Forever lets an addon do at the mailbox, before the bets are built:
--   /omq mailprobe                     report: functions, names, inbox, nearest learned mailbox, slash commands
--   /omq mailprobe send <First Last> [copper]
--                                      with the mailbox open: sends a test mail (default 1 copper) at once
--   /omq mailprobe auto <First Last> [copper]
--                                      arms a test: the next time a mailbox opens (your click), the mail goes
--                                      out by itself, like the bet payments will
--   /omq mailprobe take                with the mailbox open: takes the money of the first mail that has some
--   /omq mailprobe log                 the events seen since the last test
-- Only these commands send or take anything; the plain report changes nothing.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.MailProbe = P

local EVENTS = { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "MAIL_INBOX_UPDATE",
                 "MAIL_SEND_INFO_UPDATE", "UI_ERROR_MESSAGE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }
local MAX_LOG = 60

local log = {}
local mailOpen = false
local armed = nil            -- { name, copper }

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
local function note(t)
    log[#log + 1] = string.format("%7.1f %s", GetTime(), t)
    if #log > MAX_LOG then table.remove(log, 1) end
end

-- "First Last" of a unit, as the mail needs it (decision 165); the UI keeps using the first name
function P.FullName(unit)
    local first, second = UnitName(unit)
    if isSecret(first) or isSecret(second) or not first then return nil end
    if type(second) == "string" and second ~= "" then return first .. " " .. second end
    return first
end

----------------------------------------------------------------------
-- Report
----------------------------------------------------------------------
function P.Report()
    local out = {}
    local function add(t) out[#out + 1] = t end
    local function try(label, fn)
        local res = { pcall(fn) }
        if not res[1] then add(label .. ": ERROR " .. show(res[2])); return end
        local parts = {}
        for i = 2, #res do parts[#parts + 1] = show(res[i]) end
        add(label .. ": " .. (#parts > 0 and table.concat(parts, " | ") or "(no result)"))
    end
    add("One More Quest " .. OMQ.version .. " mail probe, mailbox open: " .. tostring(mailOpen))
    local names = { "SendMail", "SetSendMailMoney", "GetSendMailMoney", "GetSendMailPrice", "ClearSendMail", "CloseMail",
        "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxText", "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem",
        "CheckInbox", "DeleteInboxItem", "InboxItemCanDelete", "C_Mail.HasInboxMoney", "C_Mail.IsCommandPending",
        "C_Mail.CanCheckInbox", "C_PlayerInteractionManager.IsInteractingWithNpcOfType", "InteractUnit", "UnitFullName",
        "GetNormalizedRealmName", "SecureCmdList", "SendMailNameEditBox", "MailFrame" }
    local missing = {}
    for _, n in ipairs(names) do if not exists(n) then missing[#missing + 1] = n end end
    add(#missing == 0 and "functions: all present" or ("functions MISSING: " .. table.concat(missing, ", ")))

    add("-- names (the mail needs first and last name)")
    try("UnitName(player)", function() return UnitName("player") end)
    try("UnitFullName(player)", function() return UnitFullName("player") end)
    try("realm", function() return GetNormalizedRealmName and GetNormalizedRealmName(), GetRealmName and GetRealmName() end)
    add("full name for mail: " .. show(P.FullName("player")))
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists and UnitExists(u) then
            local guid = UnitGUID(u)
            local dad = guid and OMQ.users and OMQ.users[guid] and "dad" or "no addon"
            add(string.format("%s: UnitName %s / %s, full name '%s' (%s)", u, show((UnitName(u))), show(select(2, UnitName(u))),
                show(P.FullName(u)), dad))
        end
    end

    add("-- inbox")
    if mailOpen and GetInboxNumItems then
        try("GetInboxNumItems (shown, total)", GetInboxNumItems)
        local n = GetInboxNumItems() or 0
        for i = 1, math.min(n, 10) do
            try("mail " .. i .. " (icon, stationery, sender, subject, money, COD, days, items, read, returned, text, canReply, GM)",
                function() return GetInboxHeaderInfo(i) end)
        end
    else
        add("open a mailbox and run /omq mailprobe again to see the inbox")
    end
    try("send price of a mail", function() return GetSendMailPrice and GetSendMailPrice() end)
    try("money", GetMoney)

    add("-- the nearest learned mailbox (guidance places)")
    local best
    if OMQ.Places and UnitPosition then
        local a, b, _, inst = UnitPosition("player")
        if type(a) == "number" and not isSecret(a) then
            for _, p in ipairs(OMQ.Places:All("mailbox")) do
                if p.inst == inst then
                    local d = math.sqrt((p.a - a) ^ 2 + (p.b - b) ^ 2)
                    if not best or d < best.d then best = { d = d, name = p.name } end
                end
            end
        end
    end
    add(best and string.format("nearest learned mailbox: %.1f yards", best.d) or "no mailbox learned on this map yet (open one once)")

    add("-- can a click on an addon card open a mailbox? (slash commands with 'interact')")
    local found = {}
    for _, list in ipairs({ SecureCmdList or {}, SlashCmdList or {} }) do
        for k in pairs(list) do
            if type(k) == "string" and k:upper():find("INTERACT") then found[#found + 1] = k end
        end
    end
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^SLASH_") and type(v) == "string" and v:lower():find("interact") then
            found[#found + 1] = k .. "=" .. v
        end
    end
    table.sort(found)
    add(#found > 0 and ("found: " .. table.concat(found, ", ")) or "no interact slash command found")
    try("CVar SoftTargetInteract", function() return GetCVar and GetCVar("SoftTargetInteract") end)
    try("binding of INTERACTTARGET", function() return GetBindingKey and GetBindingKey("INTERACTTARGET") end)

    add("-- test state")
    add(armed and ("armed: the next mailbox sends " .. armed.copper .. " copper to '" .. armed.name .. "'") or "nothing armed")
    add("-- recent events")
    for _, l in ipairs(log) do add(l) end
    return out
end

local function showReport(out)
    out[#out + 1] = "-- end. Please send this whole report (Ctrl+A, Ctrl+C in the window)."
    if OMQDB then OMQDB.mailReport = table.concat(out, "\n") end
    local ok = pcall(OMQ.ShowReport, OMQ, out)
    if not ok then for _, l in ipairs(out) do print(l) end end
end

----------------------------------------------------------------------
-- Tests that send or take something (only on command)
----------------------------------------------------------------------
function P.Send(name, copper)
    if not mailOpen then OMQ:Print("mail probe: open a mailbox first"); return false end
    if not name or name == "" then OMQ:Print("mail probe: give the full name, e.g. /omq mailprobe send Laser Karle"); return false end
    copper = math.max(0, math.floor(tonumber(copper) or 1))
    note(string.format("SEND try: %d copper to '%s'", copper, name))
    local okM, errM = true, nil
    if copper > 0 and SetSendMailMoney then okM, errM = pcall(SetSendMailMoney, copper) end
    note("SetSendMailMoney: " .. (okM and ("ok, returned " .. show(errM)) or ("ERROR " .. show(errM))))
    local okS, errS = pcall(SendMail, name, "One More Quest test", "This is a test of the One More Quest mail probe.")
    note("SendMail: " .. (okS and "called" or ("ERROR " .. show(errS))))
    return okS
end

function P.Take()
    if not mailOpen then OMQ:Print("mail probe: open a mailbox first"); return end
    local n = GetInboxNumItems and GetInboxNumItems() or 0
    for i = 1, n do
        local ok, _, _, sender, subject, money = pcall(GetInboxHeaderInfo, i)
        if ok and type(money) == "number" and not isSecret(money) and money > 0 then
            note(string.format("TAKE try: mail %d from '%s' ('%s'), %d copper", i, show(sender), show(subject), money))
            local okT, err = pcall(TakeInboxMoney, i)
            note("TakeInboxMoney: " .. (okT and "called" or ("ERROR " .. show(err))))
            return
        end
    end
    note("TAKE: no mail with money in the inbox")
    OMQ:Print("mail probe: no mail with money in the inbox")
end

local frame = CreateFrame("Frame")
for _, e in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
frame:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "MAIL_SHOW" then mailOpen = true
    elseif event == "MAIL_CLOSED" then mailOpen = false end
    if event ~= "MAIL_INBOX_UPDATE" and event ~= "MAIL_SEND_INFO_UPDATE" then
        note(event .. (a1 ~= nil and (" " .. show(a1)) or "") .. (a2 ~= nil and (" " .. show(a2)) or ""))
    end
    if event == "MAIL_SHOW" and armed then
        local a = armed
        armed = nil
        -- give the mailbox a moment to be ready, then send without any further click
        local function go()
            P.Send(a.name, a.copper)
            if C_Timer and C_Timer.After then C_Timer.After(3, function() showReport(P.Report()) end) end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.5, go) else go() end
    end
end)

function P.IsOpen() return mailOpen end
function P.Armed() return armed end

OMQ:RegisterCommand("mailprobe", function(arg)
    local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    -- the name may contain a space: the copper amount is the last word if it is a number
    local name, copper = rest, nil
    local n1, c1 = rest:match("^(.-)%s+(%d+)$")
    if n1 then name, copper = n1, c1 end
    if cmd == "send" then
        P.Send(name, copper)
        if C_Timer and C_Timer.After then C_Timer.After(3, function() showReport(P.Report()) end) end
    elseif cmd == "auto" then
        if name == "" then OMQ:Print("mail probe: /omq mailprobe auto First Last [copper]"); return end
        armed = { name = name, copper = math.max(0, math.floor(tonumber(copper) or 1)) }
        log = {}
        OMQ:Print(string.format("mail probe armed: the next mailbox you open sends %d copper to '%s' by itself", armed.copper, armed.name))
    elseif cmd == "take" then
        P.Take()
        if C_Timer and C_Timer.After then C_Timer.After(2, function() showReport(P.Report()) end) end
    elseif cmd == "log" then
        showReport(P.Report())
    else
        showReport(P.Report())
    end
end, "mail probe for Bet Check: /omq mailprobe | send First Last [copper] | auto First Last [copper] | take | log")
