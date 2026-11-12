-- One More Quest: my characters on the XP bar (decision 548)
-- Hovering the experience bar (or the reputation bar, which takes its place at the level cap) opens a small
-- table next to the bar with every character of this account from level 2 on: name in class color, level,
-- gold and where the character was last. The character I play is marked; the last row is the gold total.
-- Each character writes its own row when it logs in and whenever level, gold or zone change, so a character
-- shows up after it was logged in once with this version. Rows are kept per GUID in OMQDB.alts (account-wide,
-- all realms); the realm is only named when it is not the one I play on. /omq chars forget <name> removes a
-- deleted character. Placement: above the bar, or below it when the bar sits in the upper half of the screen
-- (Dad UI puts it at the top). Zone names are stored as the client shows them (German or English).
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

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

-- writes the row of the character I play; level from PLAYER_LEVEL_UP (UnitLevel can lag one event)
function A.Save(level)
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
    local lvl = level or call(UnitLevel, "player")
    if type(lvl) == "number" and not secret(lvl) and lvl > 0 then e.level = lvl end
    local money = call(GetMoney)
    if type(money) == "number" and not secret(money) then e.money = money end
    local zone = text(call(GetRealZoneText)) or text(call(GetZoneText))
    if zone then
        e.zone = zone
        local sub = text(call(GetSubZoneText))
        e.sub = (sub and sub ~= zone) and sub or nil
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
                              money = e.money, zone = e.zone, sub = e.sub }
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

-- the cells of the table: header, one row per character, total; { cells = {4 texts}, me = bool }
function A.Rows()
    local list = A.List()
    local myGuid = UnitGUID("player")
    local myRealm = text(call(GetRealmName))
    local rows = { { cells = { "|cffffd100Character|r", "|cffffd100Level|r", "|cffffd100Gold|r", "|cffffd100Location|r" }, head = true } }
    local total = 0
    for _, e in ipairs(list) do
        local name = "|c" .. classHex(e.class) .. e.name .. "|r"
        if e.realm and myRealm and e.realm ~= myRealm then name = name .. " |cff808080(" .. e.realm .. ")|r" end
        local where = e.zone and (e.sub and (e.zone .. " - " .. e.sub) or e.zone) or "|cff808080?|r"
        rows[#rows + 1] = { cells = { name, tostring(e.level), A.Money(e.money), where }, me = (e.guid == myGuid) }
        if type(e.money) == "number" then total = total + e.money end
    end
    rows[#rows + 1] = { cells = { "|cffffd100Total|r", "", A.Money(total), "" }, total = true }
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
    local widths = { 0, 0, 0, 0 }
    for r, row in ipairs(rows) do
        for c = 1, 4 do
            local fs = cell(f, r, c)
            fs:SetText(row.cells[c])
            fs:Show()
            local w = fs.GetStringWidth and fs:GetStringWidth()
            if type(w) ~= "number" then w = 40 end
            if w > widths[c] then widths[c] = w end
        end
    end
    -- rows left over from a longer list
    for r = #rows + 1, #f.cells do for c = 1, 4 do f.cells[r][c]:Hide() end end
    local x = { A.PAD }
    for c = 2, 4 do x[c] = x[c - 1] + widths[c - 1] + A.GAP end
    if f.mark.Hide then f.mark:Hide() end
    for r, row in ipairs(rows) do
        -- the total row sits a little lower, below a gap
        local y = -A.PAD - (r - 1) * A.ROW_H - (row.total and 4 or 0)
        for c = 1, 4 do
            local fs = f.cells[r][c]
            fs:ClearAllPoints()
            -- level and gold right aligned, name and place left aligned
            if c == 2 or c == 3 then
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
    f:SetSize(x[4] + widths[4] + A.PAD, A.PAD * 2 + #rows * A.ROW_H + 4)
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
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "PLAYER_ENTERING_WORLD" then A.Hook() end
    if event == "PLAYER_LEVEL_UP" then A.Save(type(a1) == "number" and not secret(a1) and a1 or nil)
    else A.Save() end
end)
OMQ:On("READY", function() A.Hook(); A.Save() end)
