-- One More Quest: Grind Run, the screen parts (decision 518)
--   The window (the Grind Run icon of the check bar): "Here" (grind where I stand) and the zones with a spot for
--   my level; a zone shows its spots with the mobs' 3D models, names, levels, how many and the best run there
--   (the mouse: the spot's leaderboard); "Go" starts the big arrow. A dad's own spot can be deleted by him (right
--   click on the row). The arrival card: 30 or 60 minutes. The run itself takes the quest tracker's place (red
--   frame, UI/QuestTracker.lua asks TrackerView): time remaining, kills, XP per hour; left click pauses and goes on,
--   right click ends it after a question. The summary card stays until it is closed; "One more?" asks the minutes
--   for the same spot again.
-- Plain frames without protected calls.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local UI = {}
OMQ.GrindUI = UI

UI.RED = { 0.86, 0.26, 0.22 }
local RED = UI.RED
local TAN = { 0.72, 0.63, 0.42 }
local GOLD = { 0.89, 0.71, 0.29 }
local W, ROWS, ROW_H, SPOT_H = 400, 10, 30, 62

local win, title, sub, foot, rows, backBtn
local arrive, summary
local mode = "zones"         -- zones | spots
local zoneShown
UI._view = {}

local function G() return OMQ.Grind end
local function button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 90, h or 22)
    b:SetText(text)
    return b
end
local function frameBox(f, col)
    local border = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(col[1], col[2], col[3], 1)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.086, 0.114, 0.97)
end
local function confirm(key, text, go)
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs[key] = { text = text, button1 = YES or "Yes", button2 = NO or "No", OnAccept = go,
                                    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
        StaticPopup_Show(key)
        return
    end
    go()
end
UI._confirm = confirm

-- numbers and money
function UI.Num(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
function UI.Money(c)
    c = math.floor(c or 0)
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return string.format("%dg %ds", g, s) end
    if s > 0 then return string.format("%ds %dc", s, k) end
    return string.format("%dc", k)
end
function UI.Clock(secs)
    secs = math.max(0, math.floor(secs or 0))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local function model(parent)
    local m = CreateFrame("PlayerModel", nil, parent)
    m:SetSize(SPOT_H - 6, SPOT_H - 6)
    return m
end
local function setModel(m, id)
    if not m then return end
    if not id then m:Hide(); return end
    pcall(m.ClearModel, m)
    pcall(m.SetCreature, m, id)
    pcall(m.SetPortraitZoom, m, 0.6)
    m:Show()
end

local function buildWindow()
    win = CreateFrame("Frame", "OneMoreQuestGrindWindow", UIParent)
    win:SetSize(W, 120)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frameBox(win, RED)
    title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(RED[1], RED[2], RED[3])
    sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", 14, -36)
    sub:SetWidth(W - 28)
    sub:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() UI:Close() end)
    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(W - 28, ROW_H)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(RED[1], RED[2], RED[3], 0.12)
        r.hl:Hide()
        r.m1, r.m2 = model(r), model(r)
        r.m1:SetPoint("LEFT", 0, 0)
        r.m2:SetPoint("LEFT", r.m1, "RIGHT", 2, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetJustifyH("LEFT")
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.what = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.what:SetJustifyH("LEFT")
        r.btn = button(r, "Go", 64, 20)
        r.btn:SetPoint("RIGHT", 0, 0)
        r.btn:SetScript("OnClick", function(self) UI:RowClick(self:GetParent()) end)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, b) if b == "RightButton" then UI:RowRight(self) else UI:RowClick(self) end end)
        r:SetScript("OnEnter", function(self) self.hl:Show(); UI:RowTip(self) end)
        r:SetScript("OnLeave", function(self) self.hl:Hide(); if GameTooltip then GameTooltip:Hide() end end)
        r:Hide()
        rows[i] = r
    end
    foot = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetJustifyH("LEFT")
    foot:SetWidth(W - 28)
    backBtn = button(win, "Back", 96, 24)
    backBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    backBtn:SetScript("OnClick", function() UI:Back() end)
    win:Hide()
end

local function layoutRow(r, i, h, withModels)
    r:ClearAllPoints()
    r:SetSize(W - 28, h)
    r:SetPoint("TOPLEFT", 14, -60 - (i - 1) * h)
    local left = withModels and (2 * (SPOT_H - 6) + 8) or 0
    r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", left, withModels and -8 or -2); r.name:SetWidth(W - 110 - left)
    r.what:ClearAllPoints(); r.what:SetPoint("TOPLEFT", left + (withModels and 0 or 14), withModels and -24 or -16)
    r.what:SetWidth(W - 110 - left)
    if not withModels then r.m1:Hide(); r.m2:Hide() end
end

-- the text under a spot: levels, how many mobs, how far, who made it, the best run
function UI.SpotWhat(s, pos)
    local parts = {}
    if s.lo then parts[#parts + 1] = string.format("level %d-%d", s.lo, s.hi) end
    if s.n then parts[#parts + 1] = string.format("%d mobs", s.n) end
    if s.by then parts[#parts + 1] = "by " .. s.by end
    local d = G().Dist(s, pos)
    if d then parts[#parts + 1] = string.format("%d yd", math.floor(d / 10 + 0.5) * 10) end
    local b = G().Best(s.key)
    local line = table.concat(parts, " - ")
    if b then line = line .. string.format("\n|cffe0b04cbest: %s XP/h (%s, level %d)|r", UI.Num(b.x), b.n or "?", b.l or 0) end
    return line
end

function UI:Render()
    if not win then return end
    local view = { mode = mode, rows = {} }
    UI._view = view
    for _, r in ipairs(rows) do r:Hide(); r.zone, r.spot, r.here = nil, nil, nil end
    foot:Hide(); backBtn:Hide()
    local height
    local level = G().Level()
    if mode == "zones" then
        title:SetText("Grind Run")
        sub:SetText(string.format("Where? Spots for level %d (mobs %d-%d).", level, level - G().BELOW, level + G().ABOVE))
        local r = rows[1]
        layoutRow(r, 1, ROW_H, false)
        r.here = true
        r.name:SetText("Here"); r.name:SetTextColor(RED[1], RED[2], RED[3])
        r.what:SetText("Grind where you stand")
        r.btn:SetText("Here"); r.btn:Show(); r:Show()
        view.rows[1] = { here = true }
        local list = G().ZoneList(level)
        view.zones = list
        local n = math.min(#list, ROWS - 1)
        for i = 1, n do
            local z, row = list[i], rows[i + 1]
            layoutRow(row, i + 1, ROW_H, false)
            row.zone = z.zone
            row.name:SetText(z.name .. (z.here and "  |cff7fc76f(you are here)|r" or ""))
            row.name:SetTextColor(RED[1], RED[2], RED[3])
            row.what:SetText(z.count == 1 and "1 spot" or (z.count .. " spots"))
            row.btn:SetText("Spots"); row.btn:Show(); row:Show()
            view.rows[i + 1] = { zone = z.zone, name = z.name, count = z.count, here = z.here }
        end
        height = 60 + (n + 1) * ROW_H + 16
    else
        title:SetText("Grind Run: " .. G().ZoneName(zoneShown))
        local list = G().Spots(zoneShown, level)
        view.spots = list
        sub:SetText(#list == 0 and "No spot here for your level." or "Pick a spot - the arrow leads you there.")
        local pos = G().MyPos()
        local n = math.min(#list, math.floor(ROWS / 2))
        for i = 1, n do
            local s, r = list[i], rows[i]
            layoutRow(r, i, SPOT_H, true)
            r.spot = s
            setModel(r.m1, s.mobs and s.mobs[1])
            setModel(r.m2, s.mobs and s.mobs[3])
            r.name:SetText(s.name or "?"); r.name:SetTextColor(RED[1], RED[2], RED[3])
            local what = UI.SpotWhat(s, pos)
            r.what:SetText(what)
            r.btn:SetText("Go"); r.btn:Show(); r:Show()
            view.rows[i] = { key = s.key, name = s.name, what = what, own = s.byGuid ~= nil and s.byGuid == (OMQ:GetSelf() or {}).guid }
        end
        foot:ClearAllPoints(); foot:SetPoint("TOPLEFT", 14, -66 - n * SPOT_H)
        foot:SetText("Mouse over a spot: its leaderboard. Right click on your own spot: delete it.")
        foot:Show()
        backBtn:Show()
        height = 60 + n * SPOT_H + 30 + 44
    end
    win:SetSize(W, height)
end

function UI:RowClick(r)
    if not r then return end
    if r.here then
        local s = G():Here()
        if s then self:Close(); self:Arrive(s) end
    elseif r.zone then
        zoneShown = r.zone; mode = "spots"; self:Render()
    elseif r.spot then
        G():Go(r.spot)
        self:Close()
    end
end
function UI:RowRight(r)
    local s = r and r.spot
    local me = OMQ:GetSelf()
    if not (s and s.byGuid and me and s.byGuid == me.guid) then return end
    confirm("OMQ_GRIND_DELETE", "Delete your grind spot \"" .. (s.name or "?") .. "\" for every dad?", function()
        G():Delete(s.key); UI:Render()
    end)
end
-- the leaderboard of a spot
function UI.BoardLines(key)
    local out = {}
    for i, e in ipairs(G().Board(key)) do
        if i > G().BOARD_SHOW then break end
        out[#out + 1] = string.format("%d. %s (level %d) - %s XP/h - %s/h - %s", i, e.n or "?", e.l or 0, UI.Num(e.x), UI.Money(e.m), e.d or "")
    end
    return out
end
function UI:RowTip(r)
    local s = r and r.spot
    if not (s and GameTooltip) then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetText(s.name or "?")
    for i = 1, #(s.mobs or {}), 2 do
        GameTooltip:AddLine(string.format("%s x%d", G().MobName(s.mobs[i]), s.mobs[i + 1] or 0), 1, 1, 1)
    end
    if s.kph then GameTooltip:AddLine(string.format("The respawn allows about %d kills per hour", s.kph), 0.8, 0.8, 0.8) end
    local lines = UI.BoardLines(s.key)
    GameTooltip:AddLine(#lines > 0 and "Leaderboard:" or "No run of 25 minutes here yet", GOLD[1], GOLD[2], GOLD[3])
    for _, l in ipairs(lines) do GameTooltip:AddLine(l, 1, 1, 1) end
    GameTooltip:Show()
    UI._tip = lines
end
function UI:Back() if mode == "spots" then mode = "zones"; self:Render() else self:Close() end end
function UI:Mode() return mode end
function UI:IsOpen() return win and win:IsShown() or false end
function UI:Close() if win then win:Hide() end end
function UI:Open(zone)
    if not win then buildWindow() end
    if zone then zoneShown, mode = zone, "spots" else mode = "zones" end
    win:Show()
    self:Render()
end
function UI:Toggle() if self:IsOpen() then self:Close() else self:Open() end end

----------------------------------------------------------------------
-- The arrival card: 30 or 60 minutes
----------------------------------------------------------------------
local function buildArrive()
    arrive = CreateFrame("Frame", "OneMoreQuestGrindArrive", UIParent)
    arrive:SetSize(320, 112)
    arrive:SetPoint("TOP", UIParent, "TOP", 0, -190)
    arrive:SetFrameStrata("DIALOG")
    arrive:EnableMouse(true)
    frameBox(arrive, RED)
    local head = arrive:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head:SetPoint("TOP", 0, -10)
    head:SetText("GRIND RUN")
    head:SetTextColor(TAN[1], TAN[2], TAN[3])
    arrive.title = arrive:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    arrive.title:SetPoint("TOP", 0, -26)
    arrive.title:SetWidth(300)
    arrive.title:SetTextColor(RED[1], RED[2], RED[3])
    arrive.text = arrive:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    arrive.text:SetPoint("TOP", 0, -50)
    arrive.text:SetText("You are there. How long?")
    arrive.b30 = button(arrive, "30 min", 110, 24)
    arrive.b30:SetPoint("BOTTOMLEFT", 24, 10)
    arrive.b30:SetScript("OnClick", function() UI:Choose(30) end)
    arrive.b60 = button(arrive, "60 min", 110, 24)
    arrive.b60:SetPoint("BOTTOMRIGHT", -24, 10)
    arrive.b60:SetScript("OnClick", function() UI:Choose(60) end)
    arrive:SetScript("OnMouseUp", function(_, b) if b == "RightButton" then UI:HideArrive() end end)
    arrive:Hide()
end
function UI:Arrive(spot)
    if not spot then return end
    if not arrive then buildArrive() end
    UI._arrive = spot
    arrive.title:SetText(spot.name or "Grind spot")
    arrive:Show()
    if OMQ.Sound then OMQ.Sound:Play("update") end
end
function UI:Choose(minutes)
    local s = UI._arrive
    UI:HideArrive()
    if s then G():Start(s, minutes) end
end
function UI:HideArrive() if arrive then arrive:Hide() end end
function UI:ArriveShown() return arrive and arrive:IsShown() or false end

----------------------------------------------------------------------
-- The run in the tracker's place
----------------------------------------------------------------------
function UI.TrackerView()
    local r = G():Run()
    if not r then return nil end
    local paused = r.paused ~= nil
    return { run = paused and "GRIND RUN - PAUSED" or "GRIND RUN", grind = true, title = r.spot.name or "Grind spot",
             showNav = false, stamp = false, cols = {},
             rows = { { text = "Time remaining: " .. UI.Clock(G().Remaining(r)), cells = {} },
                      { text = "Kills: " .. r.kills, cells = {} },
                      { text = "XP/hour: " .. UI.Num(G().XPH(r)), cells = {} },
                      { text = paused and "Left click: go on" or "Left click: pause - right click: end", cells = {} } } }
end
function UI:TrackerClick(b)
    if not G():Active() then return false end
    if b == "RightButton" then
        confirm("OMQ_GRIND_END", "End the Grind Run now?", function() G():Cancel() end)
    else
        G():TogglePause()
        OMQ:Fire("QTRACK_CHANGED")
    end
    return true
end

----------------------------------------------------------------------
-- The summary card
----------------------------------------------------------------------
local function buildSummary()
    summary = CreateFrame("Frame", "OneMoreQuestGrindSummary", UIParent)
    summary:SetSize(380, 200)
    summary:SetPoint("TOP", UIParent, "TOP", 0, -150)
    summary:SetFrameStrata("DIALOG")
    summary:EnableMouse(true)
    frameBox(summary, RED)
    local head = summary:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head:SetPoint("TOP", 0, -10)
    head:SetText("GRIND RUN")
    head:SetTextColor(TAN[1], TAN[2], TAN[3])
    summary.title = summary:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    summary.title:SetPoint("TOP", 0, -26)
    summary.title:SetWidth(360)
    summary.title:SetTextColor(RED[1], RED[2], RED[3])
    summary.text = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary.text:SetPoint("TOPLEFT", 16, -52)
    summary.text:SetWidth(348)
    summary.text:SetJustifyH("LEFT")
    summary.again = button(summary, "One more?", 120, 24)
    summary.again:SetPoint("BOTTOMLEFT", 24, 10)
    summary.again:SetScript("OnClick", function() UI:Again() end)
    summary.close = button(summary, "Close", 120, 24)
    summary.close:SetPoint("BOTTOMRIGHT", -24, 10)
    summary.close:SetScript("OnClick", function() UI:HideSummary() end)
    summary:SetScript("OnMouseUp", function(_, b) if b == "RightButton" then UI:HideSummary() end end)
    summary:Hide()
end

function UI.SummaryLines(res)
    local lines = {}
    local lvl = res.lvl1 > res.lvl0 and string.format("%d -> %d, now %d %%", res.lvl0, res.lvl1, math.floor(res.nowPct))
        or string.format("level %d, now %d %%", res.lvl1, math.floor(res.nowPct))
    lines[#lines + 1] = string.format("XP from kills: %s  (+%d %% - %s)", UI.Num(res.xp), math.floor(res.pct + 0.5), lvl)
    local xph = string.format("XP per hour: %s", UI.Num(res.xph))
    if res.out then xph = xph .. string.format("  |cff9a9a9a(questing: %s)|r", UI.Num(res.out)) end
    lines[#lines + 1] = xph
    lines[#lines + 1] = string.format("Kills: %d in %s%s", res.kills, UI.Clock(res.secs), res.early and " (ended early)" or "")
    lines[#lines + 1] = string.format("Loot worth: %s  -  gold looted: %s", UI.Money(res.profit), UI.Money(res.gold))
    if res.best then
        lines[#lines + 1] = res.xph > res.best and "|cff66dd66Your best Grind Run so far!|r"
            or string.format("Your best Grind Run: %s XP/h", UI.Num(res.best))
    end
    if res.place then
        lines[#lines + 1] = string.format("|cffe0b04cPlace %d on the leaderboard of this spot|r", res.place)
    elseif not res.ok then
        lines[#lines + 1] = "|cff9a9a9aNot on the leaderboard (25 minutes on the spot needed)|r"
    end
    for _, l in ipairs(UI.BoardLines(res.key)) do lines[#lines + 1] = "  " .. l end
    if res.group and #res.group > 0 then
        local xp, copper = res.xp, res.profit + res.gold
        for _, m in ipairs(res.group) do xp, copper = xp + m.xp, copper + m.copper end
        lines[#lines + 1] = string.format("Group: %d dads - %s XP - %s", #res.group + 1, UI.Num(xp), UI.Money(copper))
    end
    return lines
end

function UI:ShowSummary(res)
    if not res then return end
    if not summary then buildSummary() end
    UI._res = res
    summary.title:SetText(res.name or "Grind spot")
    local lines = UI.SummaryLines(res)
    UI._lines = lines
    summary.text:SetText(table.concat(lines, "\n"))
    summary:SetSize(380, 52 + #lines * 15 + 50)
    summary:Show()
    if OMQ.Sound then OMQ.Sound:Play("update") end
end
function UI:HideSummary() if summary then summary:Hide() end end
function UI:SummaryShown() return summary and summary:IsShown() or false end
function UI:Again()
    local res = UI._res
    UI:HideSummary()
    local s = res and G().Spot(res.key)
    if s then UI:Arrive(s) end
end

OMQ:On("GRIND_DONE", function(res) UI:ShowSummary(res) end)
OMQ:On("GRIND_GROUP", function(res) if UI._res == res and UI:SummaryShown() then UI:ShowSummary(res) end end)
OMQ:On("GRIND_CHANGED", function() if UI:IsOpen() then UI:Render() end end)
