-- One More Quest: my characters on the XP bar (decision 548)
-- Hovering the experience bar (or the reputation bar, which takes its place at the level cap) opens a small
-- table next to the bar with every character of this account from level 2 on: name in class color, level,
-- gold and where the character was last. The character I play is marked; the last row is the gold total.
-- Each character writes its own row when it logs in and whenever level, gold or zone change, so a character
-- shows up after it was logged in once with this version. Rows are kept per GUID in OMQDB.alts (account-wide,
-- all realms); the realm is only named when it is not the one I play on. /omq chars forget <name> removes a
-- deleted character. Placement: above the bar, or below it when the bar sits in the upper half of the screen
-- (Dad UI puts it at the top). Zone names are stored as the client shows them (German or English).
-- Decision 763: four time columns from /omq played (Stats/Tally.lua): Played (the game's /played, asked once per
-- session a few seconds after login with the game's chat line held back, and noted from every /played answer),
-- AFK and City (OMQ's tally of that character) and Effective = Played - AFK - City. The played time of the
-- character I play runs on live; the others show the value from their last logout.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local A = {}
OMQ.Alts = A
A.MIN_LEVEL = 2
A.ROW_H = 16
A.PAD = 10
A.GAP = 14

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function text(v) return type(v) == "string" and not secret(v) and v ~= "" and v or nil end

function A.Store()
    if type(OMQDB) ~= "table" then return nil end
    OMQDB.alts = OMQDB.alts or {}
    return OMQDB.alts
end

local function num0(v) return type(v) == "number" and not secret(v) and v or 0 end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

-- my faction ("Alliance"/"Horde"): the game's answer, else from my race (fix 686: a character's row stayed without one)
A.RACE_FACTION = { Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance", Draenei = "Alliance",
                   Orc = "Horde", Scourge = "Horde", Undead = "Horde", Tauren = "Horde", Troll = "Horde", BloodElf = "Horde" }
function A.Faction()
    local f = text(call(UnitFactionGroup, "player"))
    if f == "Alliance" or f == "Horde" then return f end
    local _, race = call(UnitRace, "player")
    race = text(race)
    return race and A.RACE_FACTION[race] or nil
end

-- my Enchanting skill (a number; 0 when only the Disenchant spell tells), false when the professions are listed and
-- Enchanting is not among them and Disenchant is not known, nil when the game does not tell (decision 675, fix 676:
-- an empty or missing profession list at login or logout never clears a stored skill)
function A.Enchanting()
    local M = OMQ.Alerts
    local lines = M and M.ProfessionLines and M.ProfessionLines()
    for _, l in ipairs(lines or {}) do
        if l.key == "Enchanting" then return type(l.rank) == "number" and not secret(l.rank) and l.rank or 0 end
    end
    local DS = OMQ.DESell
    if DS and DS.KnowsSpell and DS.KnowsSpell() then return 0 end
    if type(lines) == "table" and #lines > 0 then return false end
    return nil
end

-- writes the row of the character I play; level from PLAYER_LEVEL_UP (UnitLevel can lag one event).
-- src: the event. Gold is only taken while the game knows it (fix 587): at PLAYER_LOGOUT and before the first
-- PLAYER_ENTERING_WORLD GetMoney can say 0, which wrote over the gold of every character that logged out.
-- A 0 is only believed from PLAYER_MONEY (gold really spent) or when the row has no gold yet.
A.moneyKnown = false
function A.Save(level, src)
    local store = A.Store()
    if not store then return nil end
    local guid = UnitGUID("player")
    if not guid or secret(guid) then return nil end
    local e = store[guid] or {}
    local first, second = call(UnitName, "player")
    first, second = text(first), text(second)
    if first then e.name = second and (first .. " " .. second) or first end
    local _, class = call(UnitClass, "player")
    e.class = text(class) or e.class
    e.realm = text(call(GetRealmName)) or e.realm
    -- faction and Enchanting skill (decision 675: who disenchants for the account; mail stays inside realm and faction)
    e.faction = A.Faction() or e.faction
    if src ~= "PLAYER_LOGOUT" then
        local ench = A.Enchanting()
        -- 0 = only the spell tells: a skill read before stays
        if ench == 0 and type(e.ench) == "number" then ench = e.ench end
        if ench ~= nil then e.ench = ench or nil end
    end
    local lvl = level or call(UnitLevel, "player")
    if type(lvl) == "number" and not secret(lvl) and lvl > 0 then e.level = lvl end
    if src == "PLAYER_ENTERING_WORLD" or src == "PLAYER_MONEY" then A.moneyKnown = true end
    if A.moneyKnown and src ~= "PLAYER_LOGOUT" then
        local money = call(GetMoney)
        if type(money) == "number" and not secret(money)
           and (money > 0 or src == "PLAYER_MONEY" or type(e.money) ~= "number") then e.money = money end
    end
    local zone = text(call(GetRealZoneText)) or text(call(GetZoneText))
    if zone then
        e.zone = zone
        local sub = text(call(GetSubZoneText))
        e.sub = (sub and sub ~= zone) and sub or nil
    end
    -- the played time runs on while I play (decision 763); only counted from an answer of this session
    if A.playedAt and type(e.played) == "number" then
        local now = time()
        if now > A.playedAt then e.played = e.played + (now - A.playedAt) end
        A.playedAt = now
    end
    e.seen = time()
    store[guid] = e
    if A.frame and A.frame:IsShown() and A.bar then A.Fill() end
    return e
end

-- the rows to show: level 2 and up, highest level first, then by name
function A.List()
    local out = {}
    for guid, e in pairs(A.Store() or {}) do
        if type(e) == "table" and type(e.level) == "number" and e.level >= A.MIN_LEVEL and e.name then
            out[#out + 1] = { guid = guid, name = e.name, class = e.class, realm = e.realm, level = e.level,
                              money = e.money, zone = e.zone, sub = e.sub, played = e.played }
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.guid < b.guid
    end)
    return out
end

local ICON = { g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
               c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" }
function A.Money(copper)
    if type(copper) ~= "number" then return "|cff808080?|r" end
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local t = {}
    if g > 0 then t[#t + 1] = g .. ICON.g end
    if g > 0 or s > 0 then t[#t + 1] = string.format(g > 0 and "%02d" or "%d", s) .. ICON.s end
    t[#t + 1] = string.format((g > 0 or s > 0) and "%02d" or "%d", c) .. ICON.c
    return table.concat(t, " ")
end

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.colorStr then return c.colorStr end
    if c and type(c.r) == "number" then
        return string.format("ff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
    end
    return "ffffffff"
end

----------------------------------------------------------------------
-- Played time (decision 763)
----------------------------------------------------------------------
A.PLAYED_DELAY = 8      -- seconds after login before the quiet /played request
A.UNMUTE_AFTER = 10     -- the chat windows get the /played line back after this at the latest
A.playedAt = nil        -- time() of the last /played answer this session (the live part counts from there)

-- every /played answer (mine, the player's, another addon's) is noted for the character I play
function A.OnPlayed(total)
    if type(total) ~= "number" or secret(total) or total < 0 then return end
    local store = A.Store()
    local guid = UnitGUID("player")
    if not store or not guid or secret(guid) then return end
    local e = store[guid] or {}
    store[guid] = e
    e.played = math.floor(total)
    A.playedAt = time()
    if A.frame and A.frame:IsShown() and A.bar then A.Fill() end
end

-- the chat windows that would print the game's /played line
local function chatFrames()
    local out = {}
    for i = 1, (type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if type(cf) == "table" and type(cf.IsEventRegistered) == "function" and call(cf.IsEventRegistered, cf, "TIME_PLAYED_MSG") then
            out[#out + 1] = cf
        end
    end
    return out
end

function A.Unmute()
    local list = A.muted
    A.muted = nil
    for _, cf in ipairs(list or {}) do pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG") end
end

-- asks the game once per session for the played time without the chat line (no automatic chat output, decision 390)
function A.AskPlayed()
    if A.asked or type(RequestTimePlayed) ~= "function" then return end
    A.asked = true
    local list = chatFrames()
    for _, cf in ipairs(list) do pcall(cf.UnregisterEvent, cf, "TIME_PLAYED_MSG") end
    A.muted = list
    if not pcall(RequestTimePlayed) then A.Unmute(); return end
    if C_Timer and C_Timer.After then C_Timer.After(A.UNMUTE_AFTER, A.Unmute) end
end

-- "?" in grey when unknown
local function dur(secs)
    local T = OMQ.Tally
    if type(secs) ~= "number" or not (T and T.Dur) then return "|cff808080?|r" end
    return T.Dur(secs)
end

-- played, AFK, city, effective seconds of one character; played (and effective) nil when not known yet,
-- AFK and city nil when the character has no tally
function A.Times(e)
    local T = OMQ.Tally
    local b = T and T.BookOf and T.BookOf(e.guid)
    local total = type(e.played) == "number" and e.played or nil
    if total and e.guid == UnitGUID("player") and A.playedAt then total = total + math.max(0, time() - A.playedAt) end
    if not b then return total, nil, nil, nil end
    if not total then return nil, num0(b.afk), T.CitySecs(b), nil end
    local afk, city, eff = T.PlayedSplit(total, b)
    return total, afk, city, eff
end

-- the cells of the table: header, one row per character, total; { cells = {texts}, me = bool }
-- a fifth column "Cooldowns" (profession cooldowns, decision 662) only when a character has one
function A.Rows()
    local list = A.List()
    local myGuid = UnitGUID("player")
    local myRealm = text(call(GetRealmName))
    local PCD = OMQ.ProfCD
    local cdText, anyCd = {}, false
    if PCD and PCD.AltText then
        for _, e in ipairs(list) do
            local ok, t = pcall(PCD.AltText, e.guid)
            if ok and t then cdText[e.guid] = t; anyCd = true end
        end
    end
    local head = { "|cffffd100Character|r", "|cffffd100Level|r", "|cffffd100Gold|r", "|cffffd100Played|r", "|cffffd100AFK|r",
                   "|cffffd100City|r", "|cffffd100Effective|r", "|cffffd100Location|r" }
    if anyCd then head[9] = "|cffffd100Cooldowns|r" end
    local rows = { { cells = head, head = true } }
    local total = 0
    local sum, known = { 0, 0, 0, 0 }, { false, false, false, false }
    for _, e in ipairs(list) do
        local name = "|c" .. classHex(e.class) .. e.name .. "|r"
        if e.realm and myRealm and e.realm ~= myRealm then name = name .. " |cff808080(" .. e.realm .. ")|r" end
        local where = e.zone and (e.sub and (e.zone .. " - " .. e.sub) or e.zone) or "|cff808080?|r"
        local t = { A.Times(e) }
        for i = 1, 4 do
            if type(t[i]) == "number" then sum[i] = sum[i] + t[i]; known[i] = true end
        end
        local cells = { name, tostring(e.level), A.Money(e.money), dur(t[1]), dur(t[2]), dur(t[3]), dur(t[4]), where }
        if anyCd then cells[9] = cdText[e.guid] or "" end
        rows[#rows + 1] = { cells = cells, me = (e.guid == myGuid) }
        if type(e.money) == "number" then total = total + e.money end
    end
    local tot = { "|cffffd100Total|r", "", A.Money(total) }
    for i = 1, 4 do tot[3 + i] = known[i] and dur(sum[i]) or "" end
    tot[8] = ""
    if anyCd then tot[9] = "" end
    rows[#rows + 1] = { cells = tot, total = true }
    return rows, #list
end

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

function A.Build()
    if A.frame then return A.frame end
    local f = CreateFrame("Frame", "OneMoreQuestAltsTip", UIParent, BACKDROP)
    f:SetFrameStrata("TOOLTIP")
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(.05, .05, .06, .92)
        f:SetBackdropBorderColor(.42, .35, .18, 1)
    end
    f.mark = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    if f.mark.SetColorTexture then f.mark:SetColorTexture(1, .82, 0, .15) end
    f.cells = {}
    f:Hide()
    A.frame = f
    return f
end

local function cell(f, r, c)
    f.cells[r] = f.cells[r] or {}
    local fs = f.cells[r][c]
    if not fs then
        fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.cells[r][c] = fs
    end
    return fs
end

-- fills and sizes the table; returns the frame
function A.Fill()
    local f = A.Build()
    local rows = A.Rows()
    local cols = #rows[1].cells
    local widths = {}
    for c = 1, cols do widths[c] = 0 end
    for r, row in ipairs(rows) do
        for c = 1, cols do
            local fs = cell(f, r, c)
            fs:SetText(row.cells[c])
            fs:Show()
            local w = fs.GetStringWidth and fs:GetStringWidth()
            if type(w) ~= "number" then w = 40 end
            if w > widths[c] then widths[c] = w end
        end
    end
    -- rows left over from a longer list
    for r = 1, #f.cells do
        for c, fs in pairs(f.cells[r]) do
            if r > #rows or c > cols then fs:Hide() end
        end
    end
    local x = { A.PAD }
    for c = 2, cols do x[c] = x[c - 1] + widths[c - 1] + A.GAP end
    if f.mark.Hide then f.mark:Hide() end
    for r, row in ipairs(rows) do
        -- the total row sits a little lower, below a gap
        local y = -A.PAD - (r - 1) * A.ROW_H - (row.total and 4 or 0)
        for c = 1, cols do
            local fs = f.cells[r][c]
            fs:ClearAllPoints()
            -- level, gold and the times right aligned, name, place and cooldowns left aligned
            if c >= 2 and c <= 7 then
                fs:SetPoint("TOPRIGHT", f, "TOPLEFT", x[c] + widths[c], y)
            else
                fs:SetPoint("TOPLEFT", f, "TOPLEFT", x[c], y)
            end
        end
        if row.me then
            f.mark:ClearAllPoints()
            f.mark:SetPoint("TOPLEFT", f, "TOPLEFT", 4, y + 2)
            f.mark:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, y + 2)
            f.mark:SetHeight(A.ROW_H)
            f.mark:Show()
        end
    end
    f.rows = rows
    f:SetSize(x[cols] + widths[cols] + A.PAD, A.PAD * 2 + #rows * A.ROW_H + 4)
    return f
end

-- above the bar, or below it when the bar sits in the upper half of the screen; centered on the mouse
function A.Below(bar)
    local _, cy = call(bar.GetCenter, bar)
    local h = call(UIParent.GetHeight, UIParent)
    if type(cy) ~= "number" or type(h) ~= "number" or h <= 0 then return false end
    local bs = call(bar.GetEffectiveScale, bar) or 1
    local us = call(UIParent.GetEffectiveScale, UIParent) or 1
    return cy * bs > (h * us) / 2
end

function A.Place(f, bar)
    f:ClearAllPoints()
    local dx = 0
    local cx = call(bar.GetCenter, bar)
    local mx = call(GetCursorPosition)
    if type(cx) == "number" and type(mx) == "number" then
        local bs = call(bar.GetEffectiveScale, bar) or 1
        local us = call(UIParent.GetEffectiveScale, UIParent) or 1
        if bs > 0 and us > 0 then dx = (mx / us) - cx * bs / us end
    end
    if A.Below(bar) then
        f:SetPoint("TOP", bar, "BOTTOM", dx, -6)
        f.below = true
    else
        f:SetPoint("BOTTOM", bar, "TOP", dx, 6)
        f.below = false
    end
end

function A.Show(bar)
    if not bar then return end
    A.Save()
    local f = A.Fill()
    A.bar = bar
    A.Place(f, bar)
    f:Show()
end

function A.Hide()
    A.bar = nil
    if A.frame then A.frame:Hide() end
end

----------------------------------------------------------------------
-- Hooks on the bars (HookScript only: the game's own XP / reputation tooltip stays as it is)
----------------------------------------------------------------------
local hooked = {}
A.hooked = hooked

local function hook(frame, bar)
    if type(frame) ~= "table" or hooked[frame] or type(frame.HookScript) ~= "function" then return end
    hooked[frame] = true
    frame:HookScript("OnEnter", function() A.Show(bar or frame) end)
    frame:HookScript("OnLeave", function() A.Hide() end)
end

function A.Hook()
    local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    local idx = { (enum and enum.Experience) or 4, (enum and enum.Reputation) or 1 }
    for _, n in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local c = _G[n]
        local bars = c and c.bars
        if type(bars) == "table" then
            for _, i in ipairs(idx) do
                local b = bars[i]
                if b then
                    hook(b)
                    -- the rested tick on the XP bar has its own OnEnter: hovering it keeps the table open
                    if type(b.ExhaustionTick) == "table" then hook(b.ExhaustionTick, b) end
                end
            end
        end
    end
    -- older clients: the classic bars
    for _, n in ipairs({ "MainMenuExpBar", "ReputationWatchBar" }) do hook(_G[n]) end
end

----------------------------------------------------------------------
-- /omq chars, /omq chars forget <name>
----------------------------------------------------------------------
function A.Forget(name)
    name = (name or ""):match("^%s*(.-)%s*$"):lower()
    if name == "" then return 0 end
    local store = A.Store() or {}
    local me = UnitGUID("player")
    local n, skipped = 0, false
    for guid, e in pairs(store) do
        local full = type(e) == "table" and type(e.name) == "string" and e.name:lower()
        if full and (full == name or full:match("^(%S+)") == name) then
            if guid == me then skipped = true else store[guid] = nil; n = n + 1 end
        end
    end
    return n, skipped
end

OMQ:RegisterCommand("chars", function(arg)
    arg = arg or ""
    local cmd, rest = arg:match("^%s*(%S*)%s*(.-)%s*$")
    if (cmd or ""):lower() == "forget" then
        if rest == "" then OMQ:Print("/omq chars forget <name>"); return end
        local n, skipped = A.Forget(rest)
        if skipped then OMQ:Print("that is the character you are playing, it stays in the list.") end
        if n > 0 then OMQ:Print("removed " .. n .. " character(s) named " .. rest .. ".")
        elseif not skipped then OMQ:Print("no character named " .. rest .. ".") end
        return
    end
    A.Save()
    local list = A.List()
    OMQ:Print(#list .. " character(s) from level " .. A.MIN_LEVEL .. " (hover the XP bar for the table):")
    for _, e in ipairs(list) do
        print("  " .. e.name .. (e.realm and (" (" .. e.realm .. ")") or "") .. " - " .. e.level .. " - " .. A.Money(e.money)
              .. " - " .. (e.zone and (e.sub and (e.zone .. " - " .. e.sub) or e.zone) or "?"))
    end
end, "my characters (level, gold, place); forget <name> removes one")

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("PLAYER_MONEY")
ev:RegisterEvent("ZONE_CHANGED")
ev:RegisterEvent("ZONE_CHANGED_INDOORS")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("TIME_PLAYED_MSG")
pcall(ev.RegisterEvent, ev, "SKILL_LINES_CHANGED")
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "TIME_PLAYED_MSG" then
        A.OnPlayed(a1)
        -- the chat windows get the line back once our quiet answer is in
        if A.muted and C_Timer and C_Timer.After then C_Timer.After(1, A.Unmute) end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        A.Hook()
        if not A.asked and C_Timer and C_Timer.After then C_Timer.After(A.PLAYED_DELAY, A.AskPlayed) end
    end
    if event == "PLAYER_LEVEL_UP" then A.Save(type(a1) == "number" and not secret(a1) and a1 or nil, event)
    else A.Save(nil, event) end
end)
OMQ:On("READY", function() A.Hook(); A.Save() end)
