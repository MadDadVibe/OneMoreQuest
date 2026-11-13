-- One More Quest: Area Run, the screen parts (decision 491)
--   The window (the Area Run icon of the check bar): the zones, mine first, then the ones of my level with how
--   many quests they have for me ("All zones" shows the rest). A click on a zone plans it: the preview lists the
--   quests in the order of the way with Skip, the way in minutes, what is left out (grey, higher level, quests
--   that start outside the zone) and whether the quest log is too small; Start and Back.
--   "Pick up first" (decision 510): up to 4 quests outside the zone that open quests of the zone (most first, the same
--   quest at several givers once, at the nearest), with the place and how many they open; the mouse shows which.
--   "Add" puts it into the plan, its pick up comes first.
--   While an Area Run goes the icon opens the run's list (the Quest Run window, green).
--   The hint card: in the zone or city of a quest giver whose quest opens quests of the run's zone: the quest, how
--   many quests it opens, "Add" (joins the run, the main arrow to the giver) and "No".
-- Plain frames without protected calls.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local UI = {}
OMQ.AreaRunUI = UI

local AREA = { 0.33, 0.84, 0.40 }
local TAN = { 0.72, 0.63, 0.42 }
local GREY = { 0.6, 0.63, 0.68 }
local W, ROWS, ROW_H = 380, 10, 30
local HROWS = 4

local win, title, sub, foot, rows, startBtn, backBtn, allBtn, hintHead, hintRows, moreBtn
local hintCard
local mode = "zones"                  -- zones | preview
local showAll = false
UI._view = {}

local function A() return OMQ.AreaRun end
local function R() return OMQ.QuestRun end
local function enable(b, on)
    if not b then return end
    b.omqEnabled = on and true or false
    if on then if b.Enable then b:Enable() end else if b.Disable then b:Disable() end end
    if b.SetAlpha then b:SetAlpha(on and 1 or 0.4) end
end
local function button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 90, h or 22)
    b:SetText(text)
    b.omqEnabled = true
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
local function tip(b, head, line)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(head)
        if line then GameTooltip:AddLine(line, 0.8, 0.8, 0.8) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local function buildWindow()
    win = CreateFrame("Frame", "OneMoreQuestAreaRunWindow", UIParent)
    win:SetSize(W, 120)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frameBox(win, AREA)
    title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(AREA[1], AREA[2], AREA[3])
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
        r:SetPoint("TOPLEFT", 14, -60 - (i - 1) * ROW_H)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(AREA[1], AREA[2], AREA[3], 0.12)
        r.hl:Hide()
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("TOPLEFT", 0, -2)
        r.name:SetWidth(W - 110)
        r.name:SetJustifyH("LEFT")
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.what = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.what:SetPoint("TOPLEFT", 14, -16)
        r.what:SetWidth(W - 124)
        r.what:SetJustifyH("LEFT")
        if r.what.SetWordWrap then r.what:SetWordWrap(false) end
        r.btn = button(r, "Skip", 64, 20)
        r.btn:SetPoint("RIGHT", 0, 0)
        r.btn:SetScript("OnClick", function(self) UI:RowClick(self:GetParent()) end)
        r:SetScript("OnClick", function(self) if mode == "zones" then UI:RowClick(self) end end)
        r:SetScript("OnEnter", function(self) if mode == "zones" then self.hl:Show() end end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        r:Hide()
        rows[i] = r
    end
    hintHead = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hintHead:SetJustifyH("LEFT")
    hintHead:SetWidth(W - 28)
    hintHead:SetTextColor(TAN[1], TAN[2], TAN[3])
    hintHead:SetText("Pick up first (outside the zone):")
    hintHead:Hide()
    hintRows = {}
    for i = 1, HROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(W - 28, ROW_H)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(TAN[1], TAN[2], TAN[3], 0.12)
        r.hl:Hide()
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("TOPLEFT", 0, -2)
        r.name:SetWidth(W - 110)
        r.name:SetJustifyH("LEFT")
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.what = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.what:SetPoint("TOPLEFT", 14, -16)
        r.what:SetWidth(W - 124)
        r.what:SetJustifyH("LEFT")
        if r.what.SetWordWrap then r.what:SetWordWrap(false) end
        r.btn = button(r, "Add", 64, 20)
        r.btn:SetPoint("RIGHT", 0, 0)
        r.btn:SetScript("OnClick", function(self) UI:HintAdd(self:GetParent()) end)
        r:SetScript("OnEnter", function(self) self.hl:Show(); UI:HintTip(self) end)
        r:SetScript("OnLeave", function(self) self.hl:Hide(); if GameTooltip then GameTooltip:Hide() end end)
        r:Hide()
        hintRows[i] = r
    end
    -- "... and N more quests": the mouse lists the rest (decision 513)
    moreBtn = CreateFrame("Button", nil, win)
    moreBtn:SetSize(W - 28, 16)
    moreBtn.text = moreBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moreBtn.text:SetPoint("LEFT", 0, 0)
    moreBtn.text:SetJustifyH("LEFT")
    moreBtn:SetScript("OnEnter", function(self) UI:MoreTip(self) end)
    moreBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    moreBtn:Hide()
    foot = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetJustifyH("LEFT")
    foot:SetWidth(W - 28)
    startBtn = button(win, "Start", 96, 24)
    startBtn:SetScript("OnClick", function(self) if self.omqEnabled then UI:Primary() end end)
    backBtn = button(win, "Back", 96, 24)
    backBtn:SetScript("OnClick", function() UI:Secondary() end)
    allBtn = button(win, "All zones", 110, 24)
    allBtn:SetScript("OnClick", function() showAll = not showAll; UI:Render() end)
    win:Hide()
end

local function minutes(yards)
    return math.max(1, math.floor(math.min(yards, 9e5) / (R().SPEED or 7) / 60 + 0.5))
end

function UI:Render()
    if not win then return end
    local view = { mode = mode, rows = {} }
    UI._view = view
    for _, r in ipairs(rows) do r:Hide() end
    for _, r in ipairs(hintRows) do r:Hide(); r.hint = nil end
    moreBtn:Hide(); moreBtn.rest = nil
    hintHead:Hide()
    startBtn:Hide(); backBtn:Hide(); allBtn:Hide(); foot:Hide()
    local height
    if mode == "zones" then
        title:SetText("Area Run")
        sub:SetText("Which zone? OMQ plans one way through all its quests.")
        local list = A().ZoneList(showAll)
        view.zones = list
        local n = math.min(#list, ROWS)
        for i = 1, n do
            local z, r = list[i], rows[i]
            r.zone = z.zone
            r.name:SetText(z.name .. (z.here and "  |cff7fc76f(you are here)|r" or ""))
            r.name:SetTextColor(AREA[1], AREA[2], AREA[3])
            local lv = z.min and string.format("level %d-%d - ", z.min, z.max) or ""
            r.what:SetText(lv .. (z.count == 1 and "1 quest for you" or (z.count .. " quests for you")))
            r.btn:SetText("Plan")
            enable(r.btn, z.count > 0)
            r.btn:Show()
            r:Show()
            view.rows[i] = { zone = z.zone, name = z.name, count = z.count, here = z.here }
        end
        allBtn:SetText(showAll and "My level" or "All zones")
        allBtn:ClearAllPoints(); allBtn:SetPoint("BOTTOMRIGHT", -14, 12); allBtn:Show()
        height = 60 + n * ROW_H + 44
    else
        local prep = A():Prep()
        local plan = prep and prep.plan
        if not plan then mode = "zones"; return self:Render() end
        local name = A().ZoneName(prep.zone)
        title:SetText("Area Run: " .. name)
        local rws = A().Rows(plan)
        view.total = #rws
        sub:SetText(#rws == 0 and "No quest of this zone fits you now." or
            string.format("%d quest%s, in the order of the way:", #rws, #rws == 1 and "" or "s"))
        local n = math.min(#rws, ROWS)
        for i = 1, n do
            local o, r = rws[i], rows[i]
            r.qid, r.zone = o.qid, nil
            r.name:SetText(i .. ". " .. R().Title(o.qid, prep.titles) .. (o.elite and "  |cffff8040Elite|r" or ""))
            r.name:SetTextColor(AREA[1], AREA[2], AREA[3])
            r.what:SetText(o.what)
            r.btn:SetText("Skip")
            enable(r.btn, true)
            r.btn:Show()
            r:Show()
            view.rows[i] = { qid = o.qid, what = o.what, elite = o.elite }
        end
        local info = plan.info or {}
        local lines = {}
        if #rws > 0 then
            lines[#lines + 1] = string.format("Way: about %d min on foot", minutes(plan.length)) ..
                (plan.busy and "  |cff9d9d9d(looking for a shorter way...)|r" or "")
        end
        if info.logFull then
            lines[#lines + 1] = string.format("|cffffd040Your quest log has room for %d new quest%s - the next pick-up waits for a turn-in.|r",
                info.free or 0, info.free == 1 and "" or "s")
        end
        if (info.later or 0) > 0 then lines[#lines + 1] = string.format("Higher level: %d quest%s, they join when you level up", info.later, info.later == 1 and "" or "s") end
        if (info.grey or 0) > 0 then lines[#lines + 1] = string.format("Grey, left out: %d", info.grey) end
        local hints = plan.hints or {}
        local hn = math.min(#hints, HROWS)
        if #hints > HROWS then
            local more = #hints - HROWS
            lines[#lines + 1] = string.format("%d more quest%s outside the zone - a card tells you when you are there", more, more == 1 and "" or "s")
        end
        if #(info.skipped or {}) > 0 then lines[#lines + 1] = string.format("Skipped: %d", #info.skipped) end
        view.lines = lines
        view.hints = {}
        local y = -66 - n * ROW_H
        view.more = nil
        if #rws > ROWS then
            local rest = {}
            for i = ROWS + 1, #rws do rest[#rest + 1] = rws[i] end
            moreBtn.rest = rest
            moreBtn.text:SetText(string.format("... and %d more quests |cff9a9a9a(mouse over: the list)|r", #rest))
            moreBtn:ClearAllPoints()
            moreBtn:SetPoint("TOPLEFT", 14, y)
            moreBtn:Show()
            view.more = #rest
            y = y - 18
        end
        if hn > 0 then
            hintHead:ClearAllPoints()
            hintHead:SetPoint("TOPLEFT", 14, y)
            hintHead:Show()
            y = y - 18
            for i = 1, hn do
                local h, r = hints[i], hintRows[i]
                r.hint = h
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 14, y - (i - 1) * ROW_H)
                r.name:SetText(R().Title(h.id, prep.titles))
                r.name:SetTextColor(TAN[1], TAN[2], TAN[3])
                local what = string.format("in %s - opens %d quest%s here", A().ZoneName(h.map), h.opens, h.opens == 1 and "" or "s")
                r.what:SetText(what)
                enable(r.btn, true)
                r.btn:Show()
                r:Show()
                view.hints[i] = { qid = h.id, what = what, opens = h.opens, map = h.map }
            end
            y = y - hn * ROW_H - 6
        end
        foot:ClearAllPoints()
        foot:SetPoint("TOPLEFT", 14, y)
        foot:SetText(table.concat(lines, "\n"))
        foot:Show()
        startBtn:SetText("Start"); enable(startBtn, #rws > 0)
        backBtn:SetText("Back")
        startBtn:ClearAllPoints(); startBtn:SetPoint("BOTTOMRIGHT", -14, 12); startBtn:Show()
        backBtn:ClearAllPoints(); backBtn:SetPoint("RIGHT", startBtn, "LEFT", -8, 0); backBtn:Show()
        height = 60 + n * ROW_H + (view.more and 18 or 0) + (hn > 0 and (18 + hn * ROW_H + 6) or 0) + 18 + #lines * 14 + 44
    end
    win:SetSize(W, height)
end

function UI:RowClick(r)
    if mode == "zones" then
        if r.zone then self:Plan(r.zone) end
    elseif r.qid then
        A():SkipPlanned(r.qid)
        self:Render()
    end
end

-- "Pick up first": Add puts the quest into the plan (its pick up first); the mouse lists what it opens
function UI:HintAdd(r)
    if mode ~= "preview" or not (r and r.hint) then return end
    A():AllowPlanned(r.hint.id)
    self:Render()
end
function UI:HintTip(r)
    local h = r and r.hint
    if not (h and GameTooltip) then return end
    local prep = A():Prep()
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetText(R().Title(h.id, prep and prep.titles))
    GameTooltip:AddLine(string.format("Giver in %s. Opens in %s:", A().ZoneName(h.map), prep and A().ZoneName(prep.zone) or "the zone"), 0.8, 0.8, 0.8)
    for i, q in ipairs(h.list or {}) do
        if i > 10 then GameTooltip:AddLine(string.format("... and %d more", #h.list - 10), 0.6, 0.6, 0.6); break end
        GameTooltip:AddLine("- " .. R().Title(q, prep and prep.titles), 1, 1, 1)
    end
    GameTooltip:Show()
    UI._tip = { qid = h.id, list = h.list }
end

-- the quests after the first ten, in the order of the way (numbers go on from 11)
function UI:MoreTip(f)
    local rest = f and f.rest
    if not (rest and GameTooltip) then return end
    local prep = A():Prep()
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    GameTooltip:SetText(string.format("%d more quests", #rest))
    local shown, lines = {}, {}
    for i, o in ipairs(rest) do
        if i > 30 then
            GameTooltip:AddLine(string.format("... and %d more", #rest - 30), 0.6, 0.6, 0.6)
            break
        end
        local line = (ROWS + i) .. ". " .. R().Title(o.qid, prep and prep.titles) .. (o.elite and "  |cffff8040Elite|r" or "")
        GameTooltip:AddDoubleLine(line, o.what, AREA[1], AREA[2], AREA[3], 0.8, 0.8, 0.8)
        shown[#shown + 1] = o.qid
        lines[#lines + 1] = line
    end
    GameTooltip:Show()
    UI._moreTip, UI._moreLines = shown, lines
end

function UI:Plan(zone)
    if not win then buildWindow() end
    if not A():Prepare(zone) then return false end
    mode = "preview"
    win:Show()
    self:Render()
    return true
end

local function askReplace(go)
    local key = "OMQ_AREA_RUN_REPLACE"
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs[key] = {
            text = "End the running run and start the Area Run?", button1 = YES or "Yes", button2 = NO or "No",
            OnAccept = go, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show(key)
        return
    end
    go()
end

function UI:Primary()
    if mode ~= "preview" then self:Close(); return end
    local prep = A():Prep()
    if not prep then return end
    local function go() if A():Start(prep.plan) then mode = "zones"; UI:Close() end end
    if R():Active() then askReplace(go) else go() end
end
function UI:Secondary()
    if mode == "preview" then mode = "zones"; self:Render() else self:Close() end
end

function UI:IsOpen() return win and win:IsShown() or false end
function UI:Mode() return mode end
function UI:Close() if win then win:Hide() end end

-- the icon: the run's list while an Area Run goes, else the zones (or the plan of one zone)
function UI:Open(zone)
    local r = R():Run()
    if r and r.kind == "area" and not zone then
        if OMQ.QuestRunUI then OMQ.QuestRunUI:Open() end
        return
    end
    if not win then buildWindow() end
    if zone then return self:Plan(zone) end
    mode = "zones"
    win:Show()
    self:Render()
end
function UI:Toggle()
    if self:IsOpen() then self:Close() return end
    if OMQ.QuestRunUI and OMQ.QuestRunUI:IsOpen() and R():Run() and R():Run().kind == "area" then OMQ.QuestRunUI:Close() return end
    self:Open()
end

----------------------------------------------------------------------
-- The hint card
----------------------------------------------------------------------
local hintUntil
local function buildHint()
    hintCard = CreateFrame("Frame", "OneMoreQuestAreaRunHint", UIParent)
    hintCard:SetSize(320, 112)
    hintCard:SetPoint("TOP", UIParent, "TOP", 0, -190)
    hintCard:SetFrameStrata("DIALOG")
    hintCard:EnableMouse(true)
    frameBox(hintCard, AREA)
    local head = hintCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head:SetPoint("TOP", 0, -10)
    head:SetText("AREA RUN")
    head:SetTextColor(TAN[1], TAN[2], TAN[3])
    hintCard.title = hintCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hintCard.title:SetPoint("TOP", 0, -26)
    hintCard.title:SetWidth(300)
    hintCard.title:SetTextColor(AREA[1], AREA[2], AREA[3])
    hintCard.text = hintCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hintCard.text:SetPoint("TOP", 0, -50)
    hintCard.text:SetWidth(300)
    local add = button(hintCard, "Add", 110, 24)
    add:SetPoint("BOTTOMLEFT", 24, 10)
    add:SetScript("OnClick", function() local h = UI._hint; UI:HideHint(); A().TakeHint(h) end)
    tip(add, "Add", "The quest and what it opens join the run - the big arrow leads you to the quest giver")
    local no = button(hintCard, "No", 110, 24)
    no:SetPoint("BOTTOMRIGHT", -24, 10)
    no:SetScript("OnClick", function() A().DismissHint(UI._hint); UI:HideHint() end)
    tip(no, "No", "Not in this run")
    hintCard:SetScript("OnMouseUp", function(_, b) if b == "RightButton" then UI:HideHint() end end)
    hintCard:Hide()
end

function UI:ShowHint(h)
    if not h then return end
    if not hintCard then buildHint() end
    local r = R():Run()
    local zone = r and r.zone and A().ZoneName(r.zone) or "the zone"
    UI._hint = h
    hintCard.title:SetText(R().Title(h.id))
    local text = string.format("Starts here in %s - opens %d quest%s for %s", A().ZoneName(h.map), h.opens, h.opens == 1 and "" or "s", zone)
    hintCard.text:SetText(text)
    UI._hintView = { qid = h.id, text = text }
    hintCard:Show()
    hintUntil = GetTime() + (A().HINT_SHOW or 25)
    if OMQ.Sound then OMQ.Sound:Play("update") end
end
function UI:HideHint() if hintCard then hintCard:Hide() end; hintUntil = nil end
function UI:HintShown() return hintCard and hintCard:IsShown() or false end

OMQ:On("READY", function()
    C_Timer.NewTicker(1, function() if hintUntil and GetTime() >= hintUntil then UI:HideHint() end end)
end)
OMQ:On("QUEST_RUN_END", function() UI:HideHint() end)
-- the better order of the preview is ready (decision 584)
OMQ:On("AREA_RUN_PLAN", function() if win and win:IsShown() and mode == "preview" then UI:Render() end end)
