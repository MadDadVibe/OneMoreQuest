-- One More Quest: Quest Run, the screen parts (decision 465)
--   The window: "How many quests?" with 1, 3, 5 and 7 (grey when not that many fit), then the preview: the
--   quests in the order of the way, new ones marked, the way in yards and minutes on foot, a Skip button per
--   quest (the next best quest takes its place), Start and Back. While a run goes the same window lists the
--   quests of the run with Skip and "End run".
--   The bar: a slim bar right above the quest tracker card, "Quest Run: 2/5 done"; a click opens the list.
--   The small arrow: above the bar, about 60 % of the main arrow, the quest and the distance next to it, in
--   the quest area "you are there" and the open objective. Left click puts the main arrow on the same place,
--   right click ends the run after a question.
--   The done card: "Quest Run done", the number of quests and the time, the fanfare, and "One more?", which
--   opens the choice of 1, 3, 5 and 7 again.
-- Plain frames without protected calls, so everything works in combat.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local UI = {}
OMQ.QuestRunUI = UI

local GOLD = { 0.89, 0.71, 0.29 }
local TAN = { 0.72, 0.63, 0.42 }
local GREEN = { 0.49, 0.78, 0.44 }
local BLUE = { 0.30, 0.62, 1.00 }       -- the Dungeon Run (476)
local GREY = { 0.6, 0.63, 0.68 }
local W, ROWS, ROW_H = 360, 10, 30
local TWO_PI = math.pi * 2
local ARROW = 35                     -- the main arrow is 58

local win, title, sub, foot, sizeBtns, rows, startBtn, backBtn, closeBtn
local bar, barText, arrowFrame, arrowTex, arrowDetail, arrowName, arrowDist
local card, cardTitle, cardText, cardMore
local mode = "choose"               -- choose | preview | list | dungeon (the Dungeon Run's preview, 476)
local winBorder, barEdge
local function isDungeon() local r = OMQ.QuestRun and OMQ.QuestRun:Run(); return r ~= nil and r.kind == "dungeon" end
local function D() return OMQ.DungeonRun end
UI._view = {}

local function R() return OMQ.QuestRun end
local function setShown(f, on) if not f then return end; if on then f:Show() else f:Hide() end end
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

local function shadow(fs)
    if fs and fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    if fs and fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local function buildWindow()
    win = CreateFrame("Frame", "OneMoreQuestRunWindow", UIParent)
    win:SetSize(W, 120)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local border = win:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    winBorder = border
    local bg = win:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.086, 0.114, 0.97)
    title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Quest Run")
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", 14, -36)
    sub:SetWidth(W - 28)
    sub:SetJustifyH("LEFT")
    closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() UI:Close() end)

    sizeBtns = {}
    for i, n in ipairs(R().SIZES) do
        local b = button(win, tostring(n), 70, 44)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * 84, -62)
        b.n = n
        b:SetScript("OnClick", function(self) if self.omqEnabled then UI:Choose(self.n) end end)
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.n == 1 and "1 quest" or (self.n .. " quests"))
            if self.why then GameTooltip:AddLine(self.why, 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        sizeBtns[i] = b
    end

    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, win)
        r:SetSize(W - 28, ROW_H)
        r:SetPoint("TOPLEFT", 14, -60 - (i - 1) * ROW_H)
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
        r.skip = button(r, "Skip", 56, 20)
        r.skip:SetPoint("RIGHT", 0, 0)
        r.skip:SetScript("OnClick", function(self) if self.qid then UI:Skip(self.qid) end end)
        r.skip:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Skip")
            GameTooltip:AddLine("Leave this quest out - the next best quest takes its place", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        r.skip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        r:Hide()
        rows[i] = r
    end
    foot = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetJustifyH("LEFT")
    startBtn = button(win, "Start", 96, 24)
    startBtn:SetScript("OnClick", function(self) if self.omqEnabled then UI:Primary() end end)
    backBtn = button(win, "Back", 96, 24)
    backBtn:SetScript("OnClick", function() UI:Secondary() end)
    win:Hide()
end

local function fmtMin(yards)
    local m = math.max(1, math.floor(yards / R().SPEED / 60 + 0.5))
    return m
end

function UI:Render()
    if not win then return end
    local Q = R()
    local view = { mode = mode, rows = {}, sizes = {} }
    UI._view = view
    for _, b in ipairs(sizeBtns) do b:Hide() end
    for _, r in ipairs(rows) do r:Hide() end
    startBtn:Hide(); backBtn:Hide(); foot:Hide()
    local blue = mode == "dungeon" or (mode == "list" and isDungeon())
    local col = blue and BLUE or GOLD
    winBorder:SetColorTexture(col[1], col[2], col[3], 1)
    title:SetTextColor(col[1], col[2], col[3])
    view.blue = blue
    local height
    if mode == "dungeon" then
        height = self:RenderDungeon(view)
    elseif mode == "choose" then
        local prep = Q:Prep()
        title:SetText("Quest Run")
        if not (prep and prep.ready) then
            sub:SetText("Looking at your quests" .. ((prep and #prep.members > 0) and " and asking the dads..." or "..."))
            view.sub = "wait"
        else
            local fit = Q.Fit(prep.pool, prep.free)
            view.fit = fit
            if fit == 0 then
                sub:SetText("No quest fits here: nothing in your quest log and no new quest nearby" ..
                    (#prep.members > 0 and " that every dad has or can take." or "."))
            else
                sub:SetText("How many quests do you want to do now?")
            end
            view.sub = "ask"
        end
        for i, b in ipairs(sizeBtns) do
            local ready = prep and prep.ready
            local on = ready and view.fit and b.n <= view.fit or false
            b.why = (ready and not on) and string.format("only %d quest%s fit%s here", view.fit or 0, view.fit == 1 and "" or "s", view.fit == 1 and "s" or "") or nil
            enable(b, on)
            b:Show()
            view.sizes[i] = on
        end
        height = 120
    elseif mode == "preview" then
        local prep = Q:Prep()
        local plan = prep and prep.plan
        title:SetText("Quest Run: the way")
        if not plan then mode = "choose"; return self:Render() end
        local shown = {}
        local order = {}
        for _, s in ipairs(plan.stops) do
            if s.kind ~= "t" and not shown[s.qid] then       -- a turn-in is no row: the follow-up says it (466)
                shown[s.qid] = true
                local isNew, parent = false, nil
                for _, e in ipairs(plan.quests) do
                    if e.id == s.qid then isNew = e.new and true or false; if e.follow then parent = e.parent end end
                end
                order[#order + 1] = { qid = s.qid, new = isNew, parent = parent }
            end
        end
        local n = #order
        sub:SetText(n < plan.n and string.format("Only %d of %d quests fit here.", n, plan.n) or
            "In this order, the shortest way:")
        for i, o in ipairs(order) do
            local r = rows[i]
            if not r then break end
            local t = Q.Title(o.qid, prep.titles)
            r.name:SetText(i .. ". " .. t .. (o.parent and "  |cff7fc76ffollow-up|r" or o.new and "  |cff7fc76fnew|r" or ""))
            r.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            r.what:SetText(o.parent and ("turn in " .. Q.Title(o.parent, prep.titles) .. " first, then pick it up")
                or o.new and "pick it up first, then the objectives" or (Q.OpenObjective(o.qid) or "objectives"))
            r.skip.qid = o.qid
            r.skip:Show()
            r:SetPoint("TOPLEFT", 14, -60 - (i - 1) * ROW_H)
            r:Show()
            view.rows[i] = { qid = o.qid, new = o.new, parent = o.parent, title = t }
        end
        view.length = plan.length
        foot:ClearAllPoints()
        foot:SetPoint("TOPLEFT", 14, -66 - n * ROW_H)
        foot:SetText(string.format("Way: %d yd, about %d min on foot (straight lines)", math.floor(plan.length + 0.5), fmtMin(plan.length)))
        foot:Show()
        startBtn:SetText("Start"); enable(startBtn, n > 0)
        backBtn:SetText("Back")
        startBtn:ClearAllPoints(); startBtn:SetPoint("BOTTOMRIGHT", -14, 12); startBtn:Show()
        backBtn:ClearAllPoints(); backBtn:SetPoint("RIGHT", startBtn, "LEFT", -8, 0); backBtn:Show()
        height = 60 + n * ROW_H + 64
    else
        local list = Q:List()
        local done, all = Q:Counts()
        title:SetText(blue and ("Dungeon Run: " .. UI.DungeonName(Q:Run().dungeon)) or "Quest Run")
        sub:SetText(string.format("%d of %d quests done", done, all))
        for i, e in ipairs(list) do
            local r = rows[i]
            if not r then break end
            r.name:SetText(e.title)
            if e.done then
                r.name:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
                r.what:SetText("done")
                r.skip:Hide()
            else
                r.name:SetTextColor(col[1], col[2], col[3])
                if blue then
                    local w = e.kind == "o" and (Q.OpenObjective(e.qid) or "objectives") or e.what
                    r.what:SetText((e.current and "next: " or "") .. w .. (e.dungeonQuest and "  |cff9aa0aa(dungeon quest)|r" or ""))
                else
                r.what:SetText((e.current and "next: " or "") .. (e.follow and e.new and e.what or e.new and "pick it up" or (Q.OpenObjective(e.qid) or "objectives")))
                end
                r.skip.qid = e.qid
                r.skip:Show()
            end
            r:SetPoint("TOPLEFT", 14, -60 - (i - 1) * ROW_H)
            r:Show()
            view.rows[i] = { qid = e.qid, done = e.done, current = e.current, title = e.title, what = e.what }
        end
        local n = math.min(#list, ROWS)
        startBtn:SetText("Close"); enable(startBtn, true)
        backBtn:SetText("End run")
        startBtn:ClearAllPoints(); startBtn:SetPoint("BOTTOMRIGHT", -14, 12); startBtn:Show()
        backBtn:ClearAllPoints(); backBtn:SetPoint("RIGHT", startBtn, "LEFT", -8, 0); backBtn:Show()
        height = 60 + n * ROW_H + 44
    end
    win:SetSize(W, height)
end

function UI.DungeonName(key)
    local d = key and OMQ.DungeonByKey and OMQ:DungeonByKey(key)
    return d and d.name or tostring(key or "?")
end

-- the Dungeon Run's preview: the dungeon quests in the order of the way, how many pre-quests each one needs,
-- Skip per dungeon quest (its pre-quests go too), the quests that are no stops, Start
function UI:RenderDungeon(view)
    local Q = R()
    local prep = D() and D():Prep()
    local plan = prep and prep.plan
    title:SetText("Dungeon Run: " .. UI.DungeonName(prep and prep.key))
    if not plan then sub:SetText("No dungeon quest data"); return 80 end
    local rws = D().Rows(plan)
    local n = math.min(#rws, ROWS)
    local total = #plan.quests
    sub:SetText(total == 0 and "Nothing to collect here: you have every dungeon quest you can get or did them already." or
        string.format("%d dungeon quest%s, %d quests in all, in this order:", #rws, #rws == 1 and "" or "s", total))
    view.rows = {}
    for i = 1, n do
        local o = rws[i]
        local r = rows[i]
        local t = Q.Title(o.qid, prep.titles)
        local d = OMQ.QuestPlaces and OMQ.QuestPlaces[o.qid]
        local lvl = d and d[2] or 0
        local me = UnitLevel and tonumber((UnitLevel("player"))) or 1
        r.name:SetText(i .. ". " .. t .. (o.elite and "  |cffff8040Elite|r" or "") ..
            ((lvl > me) and ("  |cff9aa0aafrom level " .. lvl .. "|r") or ""))
        r.name:SetTextColor(BLUE[1], BLUE[2], BLUE[3])
        local what
        if o.follow then what = "chain start known, then follow the quest in your log"
        elseif #o.pre == 0 then what = "pick it up"
        else
            local names = {}
            for k = 1, math.min(#o.pre, 3) do names[#names + 1] = Q.Title(o.pre[k], prep.titles) end
            what = #o.pre .. " pre-quest" .. (#o.pre == 1 and "" or "s") .. ": " .. table.concat(names, ", ") .. (#o.pre > 3 and ", ..." or "")
        end
        r.what:SetText(what)
        r.skip.qid = o.qid
        r.skip:Show()
        r:SetPoint("TOPLEFT", 14, -60 - (i - 1) * ROW_H)
        r:Show()
        view.rows[i] = { qid = o.qid, pre = #o.pre, elite = o.elite, follow = o.follow, title = t }
    end
    -- what is no stop
    local info = plan.info or {}
    local lines = {}
    local function names(list)
        local t = {}
        for _, id in ipairs(list or {}) do t[#t + 1] = Q.Title(id, prep.titles) end
        return table.concat(t, ", ")
    end
    if #(info.inside or {}) > 0 then lines[#lines + 1] = "Starts inside the dungeon: " .. names(info.inside) end
    if #(info.item or {}) > 0 then lines[#lines + 1] = "Starts from an item: " .. names(info.item) end
    if #(info.unknown or {}) > 0 then lines[#lines + 1] = "No known way yet: " .. names(info.unknown) end
    if #(info.skipped or {}) > 0 then lines[#lines + 1] = "Skipped: " .. names(info.skipped) end
    if (info.inLog or 0) > 0 or (info.done or 0) > 0 then
        lines[#lines + 1] = string.format("Already in your log: %d, done before: %d", info.inLog or 0, info.done or 0)
    end
    if #rws > ROWS then lines[#lines + 1] = string.format("... and %d more dungeon quests", #rws - ROWS) end
    if total > 0 then
        table.insert(lines, 1, string.format("Way: %d yd, about %d min on foot", math.floor(math.min(plan.length, 9e5) + 0.5), fmtMin(math.min(plan.length, 9e5))))
    end
    view.lines = lines
    view.total = total
    foot:ClearAllPoints()
    foot:SetPoint("TOPLEFT", 14, -66 - n * ROW_H)
    foot:SetWidth(W - 28)
    foot:SetText(table.concat(lines, "\n"))
    foot:Show()
    startBtn:SetText("Start"); enable(startBtn, total > 0)
    backBtn:SetText("Close")
    startBtn:ClearAllPoints(); startBtn:SetPoint("BOTTOMRIGHT", -14, 12); startBtn:Show()
    backBtn:ClearAllPoints(); backBtn:SetPoint("RIGHT", startBtn, "LEFT", -8, 0); backBtn:Show()
    return 60 + n * ROW_H + 18 + #lines * 14 + 44
end

-- the Group Check's button: the preview of the Dungeon Run for this dungeon
function UI:OpenDungeon(key)
    if not (D() and key) then return end
    if not win then buildWindow() end
    if not D():Prepare(key) then return end
    mode = "dungeon"
    win:Show()
    self:Render()
end

local function askReplace(go)
    local key = "OMQ_DUNGEON_RUN_REPLACE"
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs[key] = {
            text = "End the running Quest Run and start the Dungeon Run?", button1 = YES or "Yes", button2 = NO or "No",
            OnAccept = go, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show(key)
        return
    end
    go()
end

function UI:StartDungeon()
    local prep = D():Prep()
    if not prep then return false end
    local key = prep.key
    local function go()
        if D():Start(prep.plan) then
            D():StartForGroup(key)
            mode = "list"
            UI:Close()
        end
    end
    if R():Active() then askReplace(go) else go() end
    return true
end

function UI:IsOpen() return win and win:IsShown() or false end
function UI:Mode() return mode end

-- the check bar icon: the choice, or the list while a run goes
function UI:Open()
    if not win then buildWindow() end
    if R():Active() then
        mode = "list"
    else
        mode = "choose"
        R():Prepare(function() if mode == "choose" then UI:Render() end end)
    end
    win:Show()
    self:Render()
end
function UI:Toggle()
    if self:IsOpen() then self:Close() else self:Open() end
end
function UI:Close() if win then win:Hide() end end

function UI:Choose(n)
    local plan = R():PlanFor(n)
    if not plan then return end
    mode = "preview"
    self:Render()
end

function UI:Skip(qid)
    if mode == "dungeon" then D():SkipPlanned(qid)
    elseif mode == "preview" then R():SkipPlanned(qid)
    elseif mode == "list" then R():Skip(qid) end
    self:Render()
end

function UI:Primary()
    if mode == "dungeon" then UI:StartDungeon(); return end
    if mode == "preview" then
        if R():Start() then mode = "list"; self:Close() end
    else
        self:Close()
    end
end

local function askEnd()
    local key = "OMQ_QUEST_RUN_END"
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs[key] = {
            text = isDungeon() and "End the Dungeon Run?" or "End the Quest Run?", button1 = YES or "Yes", button2 = NO or "No",
            OnAccept = function() R():End() end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show(key)
        return true
    end
    R():End()
    return false
end
UI.AskEnd = askEnd

function UI:Secondary()
    if mode == "dungeon" then self:Close()
    elseif mode == "preview" then mode = "choose"; self:Render()
    elseif mode == "list" then self:Close(); askEnd() end
end

----------------------------------------------------------------------
-- The bar and the small arrow above the quest tracker
----------------------------------------------------------------------
local shownRot, wantHeading = 0, nil
local function turn(elapsed)
    if not arrowTex then return end
    local target = 0
    if wantHeading then
        local facing = GetPlayerFacing and GetPlayerFacing()
        if type(facing) ~= "number" then return end
        target = (wantHeading - facing) % TWO_PI
    end
    local diff = (target - shownRot + math.pi) % TWO_PI - math.pi
    local k = 1 - math.exp(-(elapsed or 0.016) * 22)
    if math.abs(diff) < 0.002 then shownRot = target else shownRot = (shownRot + diff * k) % TWO_PI end
    arrowTex:SetRotation(shownRot)
    arrowDetail:SetRotation(shownRot)
end

local function anchor()
    local tf = OMQ.QTrackFrame and OMQ.QTrackFrame:Frame()
    bar:ClearAllPoints()
    if tf then bar:SetPoint("BOTTOMLEFT", tf, "TOPLEFT", 0, 4)
    else bar:SetPoint("LEFT", UIParent, "LEFT", 0, 260) end
end

local function applyStyle()
    if not arrowTex then return end
    local st = OMQ.Arrow and OMQ.Arrow.Style and OMQ.Arrow:Style() or 1
    arrowTex:SetTexture("Interface\\AddOns\\OneMoreQuest\\Media\\Arrow" .. st .. "_Tint")
    arrowDetail:SetTexture("Interface\\AddOns\\OneMoreQuest\\Media\\Arrow" .. st .. "_Detail")
end

local function buildBar()
    bar = CreateFrame("Button", "OneMoreQuestRunBar", UIParent)
    bar:SetSize(230, 20)
    bar:SetFrameStrata("MEDIUM")
    bar:EnableMouse(true)
    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local edge = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
    edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    barEdge = edge
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.086, 0.114, 0.92)
    barText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    barText:SetPoint("LEFT", 8, 0)
    barText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    bar:SetScript("OnClick", function(_, button)
        if button == "RightButton" then askEnd() else UI:Toggle() end
    end)
    bar:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(isDungeon() and "Dungeon Run" or "Quest Run")
        for _, e in ipairs(R():List()) do
            if e.done then GameTooltip:AddLine("done: " .. e.title, GREEN[1], GREEN[2], GREEN[3])
            else GameTooltip:AddLine((e.current and "next: " or "") .. e.title, 1, 1, 1) end
        end
        GameTooltip:AddLine("Click: the list with Skip - right click: end the run", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    arrowFrame = CreateFrame("Button", "OneMoreQuestRunArrow", UIParent)
    arrowFrame:SetSize(ARROW + 6, ARROW + 6)
    arrowFrame:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
    arrowFrame:SetFrameStrata("MEDIUM")
    arrowFrame:EnableMouse(true)
    arrowFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    arrowTex = arrowFrame:CreateTexture(nil, "ARTWORK")
    arrowTex:SetSize(ARROW, ARROW)
    arrowTex:SetPoint("CENTER")
    arrowDetail = arrowFrame:CreateTexture(nil, "OVERLAY")
    arrowDetail:SetAllPoints(arrowTex)
    applyStyle()
    arrowName = arrowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrowName:SetPoint("TOPLEFT", arrowFrame, "TOPRIGHT", 4, -4)
    arrowName:SetJustifyH("LEFT")
    arrowDist = arrowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrowDist:SetPoint("TOPLEFT", arrowName, "BOTTOMLEFT", 0, -2)
    arrowDist:SetJustifyH("LEFT")
    for _, fs in ipairs({ arrowName, arrowDist, barText }) do shadow(fs) end
    arrowFrame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then askEnd() else R():MainArrow() end
    end)
    arrowFrame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Quest Run")
        GameTooltip:AddLine("Click: the big arrow to this place too", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right click: end the run", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    arrowFrame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    arrowFrame:SetScript("OnUpdate", function(_, elapsed) turn(elapsed) end)
    anchor()
    bar:Hide(); arrowFrame:Hide()
end

-- the bar, the small arrow and their texts (every 0.1 s and on changes)
function UI:RenderBar()
    if not bar then return end
    local Q = R()
    local st = { shown = false }
    UI._bar = st
    if not Q:Active() then
        bar:Hide(); arrowFrame:Hide()
        return
    end
    anchor()
    local done, all = Q:Counts()
    local blue = isDungeon()
    local col = blue and BLUE or GOLD
    barEdge:SetColorTexture(col[1], col[2], col[3], 1)
    barText:SetTextColor(col[1], col[2], col[3])
    st.blue = blue
    if blue then
        st.text = string.format("Dungeon Run: %d/%d", done, all)
        local fin, n = 0, 0
        if D() then fin, n = D().GroupCounts() end
        if n > 1 then st.text = st.text .. string.format("  -  group: %d/%d done", fin, n) end
    else
        st.text = string.format("Quest Run: %d/%d done", done, all)
    end
    bar:SetWidth(blue and 300 or 230)
    barText:SetText(st.text)
    st.shown = true
    bar:Show()
    local t = Q:Target()
    if not t then arrowFrame:Hide(); return end
    st.title = t.title
    arrowName:SetText(t.title)
    if t.kind == "w" and not t.distance then
        st.dist = t.what
        arrowDist:SetText(t.what)
        wantHeading = nil
        arrowTex:SetVertexColor(GREY[1], GREY[2], GREY[3])
    elseif t.there then
        st.dist = "you are there: " .. t.what
        arrowDist:SetText("|cff7fc76fyou are there:|r " .. t.what)
        wantHeading = nil
        arrowTex:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
    elseif t.distance then
        st.dist = string.format("%d yd - %s", math.floor(t.distance + 0.5), t.what)
        if t.flight then st.dist = string.format("%d yd - fly from %s - %s", math.floor(t.distance + 0.5), t.flight, t.what) end
        arrowDist:SetText(st.dist)
        wantHeading = t.heading
        if blue then arrowTex:SetVertexColor(BLUE[1], BLUE[2], BLUE[3]) else arrowTex:SetVertexColor(1, 0.82, 0.25) end
    else
        st.dist = "other continent - " .. t.what
        arrowDist:SetText(st.dist)
        wantHeading = nil
        arrowTex:SetVertexColor(0.6, 0.63, 0.68)
    end
    arrowFrame:Show()
end

----------------------------------------------------------------------
-- The done card
----------------------------------------------------------------------
local cardUntil
local function buildCard()
    card = CreateFrame("Frame", "OneMoreQuestRunDone", UIParent)
    card:SetSize(300, 116)
    card:SetPoint("TOP", UIParent, "TOP", 0, -150)
    card:SetFrameStrata("DIALOG")
    card:EnableMouse(true)
    local border = card:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    card.border = border
    local bg = card:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.086, 0.114, 0.97)
    local head = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head:SetPoint("TOP", 0, -10)
    head:SetText("QUEST RUN")
    card.head = head
    head:SetTextColor(TAN[1], TAN[2], TAN[3])
    cardTitle = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cardTitle:SetPoint("TOP", 0, -26)
    cardTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    cardText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cardText:SetPoint("TOP", 0, -50)
    cardMore = button(card, "One more?", 120, 24)
    cardMore:SetPoint("BOTTOMLEFT", 24, 12)
    cardMore:SetScript("OnClick", function() UI:HideCard(); UI:Open() end)
    local close = button(card, "Close", 100, 24)
    close:SetPoint("BOTTOMRIGHT", -24, 12)
    close:SetScript("OnClick", function() UI:HideCard() end)
    card:SetScript("OnMouseUp", function(_, b) if b == "RightButton" then UI:HideCard() end end)
    card:Hide()
end

function UI.FormatTime(secs)
    secs = math.max(0, math.floor((secs or 0) + 0.5))
    local h, m, s = math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

function UI:ShowCard(done, secs, r)
    if not card then buildCard() end
    local dungeon = r and r.kind == "dungeon"
    local col = dungeon and BLUE or GOLD
    card.border:SetColorTexture(col[1], col[2], col[3], 1)
    cardTitle:SetTextColor(col[1], col[2], col[3])
    card.head:SetText(dungeon and "DUNGEON RUN" or "QUEST RUN")
    local text = string.format("%d quest%s in %s", done, done == 1 and "" or "s", UI.FormatTime(secs))
    if dungeon then
        cardTitle:SetText("All dungeon quests collected!")
        text = "Ready for " .. UI.DungeonName(r.dungeon) .. " - " .. text
        cardMore:Hide()
    else
        cardTitle:SetText("Quest Run done!")
        cardMore:Show()
    end
    cardText:SetText(text)
    UI._card = { text = text, title = dungeon and "All dungeon quests collected!" or "Quest Run done!", dungeon = dungeon }
    card:Show()
    cardUntil = GetTime() + 30
    if OMQ.Unlock and OMQ.Unlock.Fanfare then pcall(OMQ.Unlock.Fanfare)
    elseif OMQ.Sound then OMQ.Sound:Play("done") end
end
function UI:HideCard() if card then card:Hide() end; cardUntil = nil end
function UI:CardShown() return card and card:IsShown() or false end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
OMQ:On("READY", function()
    buildBar()
    C_Timer.NewTicker(0.1, function()
        local ok, err = pcall(UI.RenderBar, UI)
        if not ok then OMQ:Error("questrun", err) end
        if cardUntil and GetTime() >= cardUntil then UI:HideCard() end
    end)
end)
OMQ:On("QUEST_RUN_CHANGED", function()
    UI:RenderBar()
    if UI:IsOpen() and mode == "list" then
        if R():Active() then UI:Render() else UI:Close() end
    end
end)
OMQ:On("QUEST_RUN_PREP", function() if UI:IsOpen() and mode == "choose" then UI:Render() end end)
OMQ:On("QUEST_RUN_DONE", function(done, secs, r) UI:Close(); UI:ShowCard(done, secs, r) end)
OMQ:On("SETTINGS_CHANGED", function() applyStyle() end)
