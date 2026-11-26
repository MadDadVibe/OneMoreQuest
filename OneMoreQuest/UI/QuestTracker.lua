-- One More Quest: group quest tracker, the card on screen (section 21, mockup on the canvas
-- "One More Quest – Group Quest Tracker"). Plain frame without protected calls, so it works in combat.
-- Right click closes it until the next progress; the mouse over it keeps it open (decisions 157, 158).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local W, PAD, LABEL_MIN, COL_W, ROW_H, GAP = 380, 12, 120, 56, 26, 4
local GOLD = { 0.89, 0.71, 0.29 }
local TAN = { 0.72, 0.63, 0.42 }
local GREEN = { 0.49, 0.78, 0.44 }
local STAMP_SIZE = 190

local U = {}
OMQ.QTrackFrame = U

local runEdges = {}
local topEdge                      -- the gold line on top; blue with the rest of the frame during a Dungeon Run (476)
local BLUE = { 0.30, 0.62, 1.00 }
-- a quest that is not part of the running run (MadDadVibe 2026-11-26): grey frame and head, silver name
U.EXTRA_FRAME = { 0.55, 0.57, 0.60 }
U.EXTRA_HEAD = { 0.62, 0.64, 0.68 }
U.EXTRA_TITLE = { 0.80, 0.82, 0.86 }
U.EXTRA_TEXT = "EXTRA QUEST - NOT IN RUN"
U.NEXT_TEXT = "Next in run: "
local frame, header, title, level, opens, opensHover, prevBtn, navText, nextBtn, stampFrame, stampTex, stampAnim, dim
local texts, texs, tUsed, xUsed = {}, {}, 0, 0
local moveMode = false
local lastStamp

local function classColor(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- background of the card (decision 207): "none" (default, the text gets a shadow so it reads on
-- the game world), "light" (more see-through) or "full" (the old dark card)
U.BACKGROUNDS = { "none", "light", "full" }
U.BG_LABEL = { none = "None", light = "Light", full = "Full" }
local bgTex, borderTex
function U:Background()
    local v = OMQ.db and OMQ.db.options and OMQ.db.options.qtrackBg
    for _, b in ipairs(U.BACKGROUNDS) do if b == v then return v end end
    return "none"
end
local function shade(fs)
    if not fs then return end
    if U:Background() == "full" then
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.6) end
    else
        if fs.SetShadowOffset then fs:SetShadowOffset(1.5, -1.5) end
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
    end
end
U._shade = shade
function U:_BgTextures() return bgTex, borderTex end
local function applyBackground()
    if not bgTex then return end
    local b = U:Background()
    if b == "none" then
        bgTex:Hide(); borderTex:Hide()
    elseif b == "light" then
        bgTex:Show(); borderTex:Show()
        bgTex:SetColorTexture(0.08, 0.086, 0.114, 0.45)
        borderTex:SetColorTexture(0.23, 0.2, 0.13, 0.45)
    else
        bgTex:Show(); borderTex:Show()
        bgTex:SetColorTexture(0.08, 0.086, 0.114, 0.97)
        borderTex:SetColorTexture(0.23, 0.2, 0.13, 1)
    end
    if dim then dim:SetAlpha(b == "none" and 0 or (b == "light" and 0.5 or 1)) end
    for _, fs in ipairs({ header, title, level, navText, opens }) do shade(fs) end
    for _, fs in ipairs(texts) do shade(fs) end
end
function U:SetBackground(b)
    OMQ.db.options.qtrackBg = b
    applyBackground()
end
function U:CycleBackground()
    local cur = self:Background()
    for i, b in ipairs(U.BACKGROUNDS) do
        if b == cur then self:SetBackground(U.BACKGROUNDS[i % #U.BACKGROUNDS + 1]); return end
    end
end

local function newText(font)
    tUsed = tUsed + 1
    local fs = texts[tUsed]
    if not fs then fs = frame:CreateFontString(nil, "OVERLAY", font); texts[tUsed] = fs end
    fs:SetFontObject(font)
    shade(fs)
    fs:ClearAllPoints()
    -- a recycled string keeps the width and alignment of its last use (a 150 px left-aligned
    -- objective label reused as a number cell drew the number half a column to the left):
    -- every string starts unbounded and centred again
    fs:SetWidth(0)
    fs:SetJustifyH("CENTER")
    fs:Show()
    return fs
end

local function newTex()
    xUsed = xUsed + 1
    local t = texs[xUsed]
    if not t then t = frame:CreateTexture(nil, "BACKGROUND", nil, 1); texs[xUsed] = t end
    t:ClearAllPoints()
    t:Show()
    return t
end

----------------------------------------------------------------------
-- Position (move mode like the arrow and the alerts)
----------------------------------------------------------------------
local DEFAULT_POINT = { "LEFT", "LEFT", 0, 165 }        -- default layout (decision 190)

local function store()
    OMQ.db.qtrack = OMQ.db.qtrack or {}
    return OMQ.db.qtrack
end

local function applyPosition()
    local p = store().point or DEFAULT_POINT
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function savePosition()
    local point, _, rel, x, y = frame:GetPoint()
    if point then store().point = { point, rel or point, x or 0, y or 0 } end
end

function U:ResetPosition()
    store().point = nil
    if frame then applyPosition() end
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------
local function navButton(dir)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(22, 22)
    local up = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
    local down = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down"
    b:SetNormalTexture(up)
    b:SetPushedTexture(down)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() OMQ.QTrack:Next(dir) end)
    return b
end

local function build()
    frame = CreateFrame("Frame", "OneMoreQuestQuestTracker", UIParent)
    -- a size from the start (fix 624): the run's bar and arrow hang on the card's place, and a card that was never
    -- shown (a reload outside the Area Run's zone) had no size, so the game drew neither of them
    frame:SetSize(W, 72)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if moveMode then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
    frame:SetScript("OnMouseUp", function(_, button)
        if moveMode then return end
        -- the Grind Run in the tracker's place: left click pauses, right click ends (decision 518)
        if OMQ.GrindUI and OMQ.Grind and OMQ.Grind:Active() then OMQ.GrindUI:TrackerClick(button); return end
        if button == "RightButton" then OMQ.QTrack:Close() end
    end)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    borderTex = border
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.23, 0.2, 0.13, 1)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgTex = bg
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.086, 0.114, 0.97)
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(3)
    edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    topEdge = edge
    -- while a Quest Run goes the card has a gold frame all around (decision 465)
    runEdges = {}
    for _, side in ipairs({ "LEFT", "RIGHT", "BOTTOM" }) do
        local e = frame:CreateTexture(nil, "BORDER")
        if side == "BOTTOM" then e:SetPoint("BOTTOMLEFT"); e:SetPoint("BOTTOMRIGHT"); e:SetHeight(3)
        else e:SetPoint("TOP" .. side); e:SetPoint("BOTTOM" .. side); e:SetWidth(3) end
        e:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        e:Hide()
        runEdges[#runEdges + 1] = e
    end

    header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", PAD, -10)
    header:SetText("GROUP QUEST")
    header:SetTextColor(TAN[1], TAN[2], TAN[3])
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -24)
    title:SetJustifyH("LEFT")
    if title.SetWordWrap then title:SetWordWrap(false) end
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    level = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    level:SetPoint("LEFT", title, "RIGHT", 6, 0)
    level:SetTextColor(0.66, 0.69, 0.73)
    -- what the quest opens (decision 656): green "opens N" behind the level, the hover lists the follow-ups
    opens = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    opens:SetPoint("LEFT", level, "RIGHT", 6, 0)
    opens:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    opensHover = CreateFrame("Frame", nil, frame)
    opensHover:SetPoint("TOPLEFT", title, "TOPLEFT", -2, 3)
    opensHover:SetPoint("BOTTOMRIGHT", opens, "BOTTOMRIGHT", 2, -3)
    if opensHover.EnableMouse then opensHover:EnableMouse(true) end
    if opensHover.SetMouseClickEnabled then pcall(opensHover.SetMouseClickEnabled, opensHover, false) end  -- clicks go to the card
    opensHover:SetScript("OnEnter", function(self) U.OpensTip(self) end)
    opensHover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    opensHover:Hide()

    nextBtn = navButton(1)
    nextBtn:SetPoint("TOPRIGHT", -8, -14)
    navText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    navText:SetPoint("RIGHT", nextBtn, "LEFT", -2, 0)
    navText:SetTextColor(0.66, 0.69, 0.73)
    prevBtn = navButton(-1)
    prevBtn:SetPoint("RIGHT", navText, "LEFT", -2, 0)
    applyBackground()

    -- the stamp sits above everything on its own frame
    stampFrame = CreateFrame("Frame", nil, frame)
    stampFrame:SetAllPoints()
    stampFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    dim = stampFrame:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0.047, 0.05, 0.07, 0.45)
    applyBackground()
    stampTex = stampFrame:CreateTexture(nil, "OVERLAY")
    stampTex:SetSize(STAMP_SIZE, STAMP_SIZE)
    stampTex:SetPoint("CENTER")
    -- lands like a rubber stamp: from 1.6 times the size down to its size in 0.15 s
    pcall(function()
        stampAnim = stampTex:CreateAnimationGroup()
        local s = stampAnim:CreateAnimation("Scale")
        if s.SetScaleFrom then s:SetScaleFrom(1.6, 1.6); s:SetScaleTo(1, 1)
        else s:SetFromScale(1.6, 1.6); s:SetToScale(1, 1) end
        s:SetDuration(0.15)
        local a = stampAnim:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.1)
    end)
    stampFrame:Hide()

    -- the mouse over the card keeps it open (polled, so the buttons on it do not break it)
    local acc = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        local over = false
        if self.IsMouseOver then local ok, v = pcall(self.IsMouseOver, self); over = ok and v and true or false end
        if not over and OMQ.QuestItem and OMQ.QuestItem:IsMouseOver() then over = true end   -- its item button (354)
        OMQ.QTrack:SetHover(over)
        acc = acc + (elapsed or 0)
        if acc >= 0.25 then acc = 0; U:Render() end          -- the light on a changed cell fades
    end)
    applyPosition()
    frame:Hide()
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------
local DEMO = {
    title = "Quest Tracker", level = nil, showNav = false, stamp = false,
    cols = {}, rows = { { text = "Move mode: drag me to a new position", cells = {} } },
}

-- during a Quest Run or a Dungeon Run the card stays on the screen the whole time (481): without a quest
-- card of the group it shows the run's current stop, so the run bar and the arrow have their place
-- the Chain Run (595): its card shows the step, what to do there and the steps of the other dads
function U.ChainView()
    local C = OMQ.ChainRun
    if moveMode or not (C and C:Active()) then return nil end
    local ok, t = pcall(C.Target, C)
    if not ok then t = nil end
    local rows = { { text = t and t.what or "all steps done", cells = {} } }
    if t and t.enemy then rows[#rows + 1] = { text = "|cffff8a6aenemy zone - watch out|r", cells = {} } end
    local others = C:Others()
    if #others > 0 then
        local parts = {}
        for _, o in ipairs(others) do parts[#parts + 1] = string.format("%s %d/%d", o.name, o.done, o.n) end
        rows[#rows + 1] = { text = "Dads: " .. table.concat(parts, ", "), cells = {} }
    end
    local title = t and t.title or ""
    return { run = "CHAIN RUN", title = title, level = t and string.format("%d/%d", t.step, t.n) or nil,
             showNav = false, stamp = false, cols = {}, rows = rows }
end

function U.RunView()
    local cv = U.ChainView()
    if cv then return cv end
    local R = OMQ.QuestRun
    if moveMode or not (R and R:Active()) then return nil end
    local r = R:Run()
    local ok, t = pcall(R.Target, R)
    if not ok then t = nil end
    local what = t and t.what or "all stops done"
    return { run = (r and r.kind == "dungeon") and "DUNGEON RUN" or (r and r.kind == "area") and "AREA RUN" or "QUEST RUN",
             qid = t and t.qid, title = t and t.title or "", showNav = false, stamp = false, cols = {},
             rows = { { text = what, cells = {} } } }
end

-- the Area Run card (decision 615): first the quest I am working on (my newest progress, until its objectives
-- are fulfilled), else the next step of the run: its objectives as the group card, or what to pick up or to
-- turn in there. Turn-ins at the same giver one after the other are listed together. The stamp still comes.
U.TURNIN_YD = 30
function U.TurnIns(r)
    local s1 = r and r.stops and r.stops[1]
    if not (s1 and s1.kind == "t" and s1.place) then return {} end
    local out = { s1.qid }
    for k = 2, #r.stops do
        local s = r.stops[k]
        if s.kind ~= "t" or not s.place or s.place.inst ~= s1.place.inst then break end
        if OMQ.QTrack and OMQ.QTrack.Trackable(s.qid) then break end     -- its objectives are still open (619)
        local d = math.sqrt((s.place.a - s1.place.a) ^ 2 + (s.place.b - s1.place.b) ^ 2)
        if d > U.TURNIN_YD then break end
        out[#out + 1] = s.qid
    end
    return out
end

-- more quests to do at the same place (decision 632): their objectives come under the card's own, each quest with
-- its name as a gold head row; at most TOGETHER_MAX more quests on the card (the arrow's "+ N" counts them all)
U.TOGETHER_MAX = 5
function U.AddTogether(v, qid, t)
    local R, Q = OMQ.QuestRun, OMQ.QTrack
    v.more = 0
    if not (t and R.Together) then return v, false end
    local ok, list = pcall(R.Together, R, t)
    if not ok or type(list) ~= "table" then return v, qid == t.qid end
    local others, mainHere = {}, qid == t.qid
    if t.qid ~= qid then others[1] = t.qid end
    for _, id in ipairs(list) do
        if id == qid then mainHere = true elseif id ~= t.qid then others[#others + 1] = id end
    end
    if not mainHere then return v, false end     -- the quest I work on is elsewhere: the caller adds the step under it
    for _, id in ipairs(others) do
        if v.more >= U.TOGETHER_MAX then break end
        local w = Q.Trackable(id) and Q:View(id)
        if w and #w.rows > 0 then
            v.more = v.more + 1
            v.rows[#v.rows + 1] = { text = (w.title or R.Title(id)) .. U.OpensText(id), head = true, cells = {} }
            for _, r in ipairs(w.rows) do v.rows[#v.rows + 1] = r end
        end
    end
    return v, true
end

-- the run's step under the card of a quest I work on elsewhere (MadDadVibe 2026-11-18): the step's name as a gold
-- head row, then its rows (objectives with the dads' columns, or what to pick up / turn in)
function U.AddStep(v, step)
    if not (v and step) then return v end
    v.rows[#v.rows + 1] = { text = (step.title or "") .. (step.multi and "" or U.OpensText(step.qid)), head = true, step = true, cells = {} }
    for _, r in ipairs(step.rows or {}) do v.rows[#v.rows + 1] = r end
    v.more = (v.more or 0) + 1 + (step.more or 0)
    v.stepAdded = true
    return v
end

-- " (opens N)" in green behind a quest's name on the Area Run card (decision 656), "" when it opens nothing
U.OPENS_COLOR = "|cff7dc770"
function U.OpensText(qid)
    local A = OMQ.AreaRun
    local n = qid and A and A.Opens and A.Opens(qid) or 0
    if n <= 0 then return "" end
    return " " .. U.OPENS_COLOR .. "(opens " .. n .. ")|r"
end
-- the level of a quest from the data, for the pick up and turn-in steps that have no quest log entry yet
function U.DataLevel(qid)
    local d = qid and OMQ.QuestPlaces and OMQ.QuestPlaces[qid]
    return d and type(d[3]) == "number" and d[3] > 0 and d[3] or nil
end

function U.AreaView()
    local v = U.AreaCard()
    -- the card's own quest: what turning it in opens (decision 656)
    if v and v.qid and not v.multi then
        local A = OMQ.AreaRun
        local n = A and A.Opens and A.Opens(v.qid) or 0
        if n > 0 then v.opens, v.opensQid = n, v.qid end
    end
    return v
end

-- the Area Run's step: its objectives as the group card with the quests at the same place (632), else the step text
function U.AreaCardOf(v)
    if not v then return nil end
    v.run, v.showNav = "AREA RUN", false
    return v
end
function U.AreaStep(r, t, allowed)
    local R, Q = OMQ.QuestRun, OMQ.QTrack
    if allowed and t and t.kind == "o" and not t.buy and Q.Trackable(t.qid) then
        local v = U.AreaCardOf(Q:View(t.qid))
        if v then return (U.AddTogether(v, t.qid, t)) end
    end
    local view = { run = "AREA RUN", qid = t and t.qid, title = t and t.title or "", showNav = false, stamp = false,
                   cols = {}, rows = { { text = t and t.what or "all stops done", cells = {} } } }
    if t and t.qid then view.level = U.DataLevel(t.qid) end                 -- the level on p/t steps too (656)
    if t and t.kind == "t" then
        local list = U.TurnIns(r)
        if #list > 1 then
            view.title = string.format("Turn in %d quests", #list)
            view.multi, view.level = true, nil
            view.rows = {}
            for _, id in ipairs(list) do
                local nxt = R.FollowUpIn(r, id)
                view.rows[#view.rows + 1] = { text = R.Title(id) .. U.OpensText(id) .. (nxt and (", then pick up " .. R.Title(nxt)) or ""), cells = {} }
            end
        end
    end
    return view
end

function U.AreaCard()
    local R = OMQ.QuestRun
    if moveMode or not (R and R:Active()) then return nil end
    if OMQ.ChainRun and OMQ.ChainRun:Active() then return nil end
    local r = R:Run()
    if not (r and r.kind == "area") then return nil end
    local Q = OMQ.QTrack
    local allowed = Q:Allowed()
    local function card(v)
        if not v then return nil end
        v.run, v.showNav = "AREA RUN", false
        return v
    end
    if allowed and Q:Stamp() and Q:Shown() then
        local v = card(Q:View())
        if v then return v end
    end
    local ok, t = pcall(R.Target, R)
    if not ok then t = nil end
    local function stepView() return U.AreaStep(r, t, allowed) end
    -- the quest I am working on comes first; is it not part of the step, the step stays on the card under it
    local work = allowed and Q:Working() or nil
    if work and work ~= (t and t.qid) then
        local v = card(Q:View(work))
        if v then
            local _, here = U.AddTogether(v, work, t)
            if not here and t then U.AddStep(v, stepView()) end
            return v
        end
    end
    return stepView()
end

-- outside the zone of the running Area Run (decision 623): no card at all, only the run's bar and arrow stay
function U.AreaAway()
    local R, A = OMQ.QuestRun, OMQ.AreaRun
    if moveMode or not (R and A and A.MyZone and R:Active()) then return false end
    if OMQ.ChainRun and OMQ.ChainRun:Active() then return false end
    local r = R:Run()
    if not (r and r.kind == "area" and r.zone) then return false end
    local ok, here = pcall(A.MyZone)
    return ok and here ~= nil and here ~= r.zone or false
end

-- the colour of the running run's frame: purple Chain Run, blue Dungeon Run, green Area Run, else gold
function U.RunColor()
    if OMQ.ChainRun and OMQ.ChainRun:Active() then return OMQ.ChainRunUI and OMQ.ChainRunUI.PURPLE or { 0.66, 0.33, 0.94 } end
    local r = OMQ.QuestRun and OMQ.QuestRun:Active() and OMQ.QuestRun:Run()
    if r and r.kind == "dungeon" then return BLUE end
    if r and r.kind == "area" then return OMQ.QuestRunUI and OMQ.QuestRunUI.AREA or { 0.33, 0.84, 0.40 } end
    return GOLD
end

-- is the quest part of the running run (MadDadVibe 2026-11-26)? The Chain Run: one of its steps' quests; the other
-- runs: a quest of the run that was not dropped. nil when no run goes (then nothing is an extra quest).
function U.InRun(qid)
    if not qid then return nil end
    local C = OMQ.ChainRun
    if C and C:Active() then
        local chain = C:Chain()
        if not chain then return nil end
        for _, st in ipairs(chain.steps or {}) do
            for _, v in pairs(type(st.quests) == "table" and st.quests or {}) do     -- a list or { [faction] = list }
                if v == qid then return true end
                if type(v) == "table" then for _, id in ipairs(v) do if id == qid then return true end end end
            end
        end
        return false
    end
    local R = OMQ.QuestRun
    if not (R and R:Active()) then return nil end
    local r = R:Run()
    local q = r and r.quests and r.quests[qid]
    return (q ~= nil and not q.dropped) and true or false
end

-- a card of a quest that is no part of the running run: grey, and the run's next step under it
function U.IsExtra(view)
    if moveMode or not view or view.multi or not view.qid then return false end
    return U.InRun(view.qid) == false
end

-- the run's next step for the card of an extra quest: { title, qid, multi, rows }, nil when nothing is left
function U.RunStep()
    local C = OMQ.ChainRun
    if C and C:Active() then
        local cv = U.ChainView()
        if not cv then return nil end
        return { title = cv.title, multi = true, rows = cv.rows }
    end
    local R = OMQ.QuestRun
    if not (R and R:Active()) then return nil end
    local r = R:Run()
    local ok, t = pcall(R.Target, R)
    if not ok or not t then return nil end
    if r and r.kind == "area" then return U.AreaStep(r, t, OMQ.QTrack:Allowed()) end
    return { qid = t.qid, title = t.title, multi = true, rows = { { text = t.what or "", cells = {} } } }
end

function U:Render()
    if not frame then return end
    local Q = OMQ.QTrack
    -- a Grind Run takes the whole card (decision 518): the quest tracker is not needed while it goes
    local grind = not moveMode and OMQ.GrindUI and OMQ.GrindUI.TrackerView() or nil
    local view = moveMode and DEMO or grind or U.AreaView() or (Q:Shown() and Q:View()) or U.RunView()
    if view and not grind and U.AreaAway() then view = nil end
    local extra = not grind and U.IsExtra(view) or false
    if extra and not view.stepAdded then U.AddStep(view, U.RunStep()) end
    U.extra = extra
    if not view then
        frame:Hide()
        lastStamp = nil
        U.runGrind = false
        Q:SetHover(false)                -- a hidden card cannot hold the mouse
        return
    end
    tUsed, xUsed = 0, 0
    for _, fs in ipairs(texts) do fs:Hide() end
    for _, t in ipairs(texs) do t:Hide() end

    U.headerText = extra and U.EXTRA_TEXT or view.run or "GROUP QUEST"
    header:SetText(U.headerText)
    local hc = extra and U.EXTRA_HEAD or TAN
    header:SetTextColor(hc[1], hc[2], hc[3])
    local tc = (view.run == "CHAIN RUN") and (OMQ.ChainRunUI and OMQ.ChainRunUI.TEXT) or GOLD   -- purple title (595)
    if extra then tc = U.EXTRA_TITLE end
    title:SetTextColor(tc[1], tc[2], tc[3])
    title:SetText(view.title or "")
    level:SetText(view.level and ("[" .. view.level .. "]") or "")
    opens:SetText(view.opens and ("opens " .. view.opens) or "")
    U.opensQid = view.opens and view.opensQid or nil
    if U.opensQid then opensHover:Show() else opensHover:Hide() end
    local cols = moveMode and {} or view.cols
    local ncols = #cols
    local labelW = W - PAD * 2 - ncols * (COL_W + GAP)
    if labelW < LABEL_MIN then labelW = LABEL_MIN end
    local width = PAD * 2 + labelW + ncols * (COL_W + GAP)
    -- the quest level right behind the name, not at the far right where the arrows of several
    -- cards cover it (decision 206): the name gets only as wide as it is, at most the room left
    local room = width - PAD * 2 - (view.showNav and 90 or 30)
    local function textW(fs)
        local v = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
        if type(v) ~= "number" then v = fs:GetStringWidth() end
        return type(v) == "number" and v or nil
    end
    local levelW = view.level and ((textW(level) or 24) + 6) or 0
    if view.opens then levelW = levelW + (textW(opens) or 48) + 6 end
    local nameW = textW(title) or room
    title:SetWidth(math.max(20, math.min(nameW + 2, room - levelW)))
    if view.showNav then
        navText:SetText(view.nav); navText:Show(); prevBtn:Show(); nextBtn:Show()
    else
        navText:Hide(); prevBtn:Hide(); nextBtn:Hide()
    end

    local y = -46
    -- column heads: the dads in class colours
    for j, c in ipairs(cols) do
        local fs = newText("GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + labelW + GAP + (j - 1) * (COL_W + GAP), y)
        fs:SetWidth(COL_W)
        fs:SetJustifyH("CENTER")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        fs:SetText(c.name or "?")
        fs:SetTextColor(classColor(c.class))
    end
    if ncols > 0 then y = y - 16 end
    for _, r in ipairs(view.rows) do
        local label = newText("GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y - 6)
        label:SetWidth((r.head or (#r.cells == 0 and ncols > 0)) and (width - PAD * 2) or labelW)
        label:SetJustifyH("LEFT")
        if label.SetWordWrap then label:SetWordWrap(false) end
        label:SetText((extra and r.step) and (U.NEXT_TEXT .. (r.text or "")) or (r.text or ""))
        -- on a see-through card the objective is pure white, like the names (decision 210)
        if extra and r.step then local c = U.RunColor(); label:SetTextColor(c[1], c[2], c[3])  -- the run's step under an extra quest
        elseif r.head then label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])          -- another quest at this place (632)
        elseif U:Background() == "full" then label:SetTextColor(0.79, 0.8, 0.84) else label:SetTextColor(1, 1, 1) end
        for j, cell in ipairs(r.cells) do
            local x = PAD + labelW + GAP + (j - 1) * (COL_W + GAP)
            local box = newTex()
            box:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
            box:SetSize(COL_W, ROW_H - 2)
            if cell.lit then box:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.32)
            elseif cell.isSelf then box:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.10)
            else box:SetColorTexture(1, 1, 1, 0.04) end
            local fs = newText("GameFontHighlightSmall")
            fs:SetPoint("CENTER", frame, "TOPLEFT", x + COL_W / 2, y - (ROW_H - 2) / 2)
            fs:SetText(cell.text or "")
            if cell.state == "done" then fs:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
            elseif cell.state == "none" or cell.state == "wait" then fs:SetTextColor(0.36, 0.38, 0.42)
            else fs:SetTextColor(0.93, 0.92, 0.89) end
        end
        y = y - ROW_H
    end
    frame:SetSize(width, -y + 10)
    local chain = not moveMode and not grind and OMQ.ChainRun and OMQ.ChainRun:Active() or false
    local running = (grind ~= nil) or chain or (OMQ.QuestRun and OMQ.QuestRun:Active() and not moveMode)
    for _, e in ipairs(runEdges) do if running then e:Show() else e:Hide() end end
    U.runFrame = running and true or false
    -- the Dungeon Run's frame is blue instead of gold (476)
    local r = running and not grind and OMQ.QuestRun:Run()
    local blue = r and r.kind == "dungeon" or false
    local area = r and r.kind == "area" or false          -- the Area Run's frame is green (491)
    if chain then r, blue, area = nil, false, false end
    local col = grind and OMQ.GrindUI.RED or chain and (OMQ.ChainRunUI and OMQ.ChainRunUI.PURPLE or { 0.66, 0.33, 0.94 }) or blue and BLUE or area and (OMQ.QuestRunUI and OMQ.QuestRunUI.AREA or { 0.33, 0.84, 0.40 }) or GOLD
    if extra and running then col = U.EXTRA_FRAME end
    U.frameColor = col
    U.runGrind = grind ~= nil
    for _, e in ipairs(runEdges) do e:SetColorTexture(col[1], col[2], col[3], 1) end
    if topEdge then topEdge:SetColorTexture(col[1], col[2], col[3], 1) end
    U.runBlue = blue
    U.runChain = chain
    U.runArea = area

    if view.stamp then
        stampFrame:Show()
        if lastStamp ~= view.qid then
            lastStamp = view.qid
            local k = view.stampKind or OMQ.QTrack.STAMPS[1]          -- the same stamp for every dad (decision 160)
            stampTex:SetTexture(k.file)
            stampTex:SetVertexColor(k.color[1], k.color[2], k.color[3], 1)
            U.stampKey = k.key
            if stampAnim then pcall(stampAnim.Play, stampAnim) end
        end
    else
        stampFrame:Hide()
        lastStamp = nil
    end
    frame:Show()
end

-- the hover over the name (decision 656): the quests turning it in opens, the chain one step behind them
function U.OpensTip(owner)
    local A, qid = OMQ.AreaRun, U.opensQid
    if not (GameTooltip and A and A.OpensLines and qid) then return false end
    local ok, lines, more = pcall(A.OpensLines, qid)
    if not ok or type(lines) ~= "table" or #lines == 0 then return false end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local n = 0
    for _, l in ipairs(lines) do if l.depth == 1 then n = n + 1 end end
    GameTooltip:AddLine(string.format("Turning it in opens %d quest%s", n, n == 1 and "" or "s"), GOLD[1], GOLD[2], GOLD[3])
    for _, l in ipairs(lines) do
        local left = (l.depth > 1 and "    then " or "") .. l.text
        if l.note then left = left .. (l.noteKind == "run" and "  |cff7dc770(" or "  |cffff9933(") .. l.note .. ")|r" end
        local c = l.depth > 1 and 0.75 or 1
        GameTooltip:AddDoubleLine(left, l.zone or "", c, c, c, 0.66, 0.69, 0.73)
    end
    if (more or 0) > 0 then GameTooltip:AddLine(string.format("... and %d more", more), 0.66, 0.69, 0.73) end
    GameTooltip:Show()
    U.tipLines = lines
    return true
end

function U:IsShown() return frame and frame:IsShown() or false end
function U:Frame() return frame end

OMQ:On("READY", function() build(); U:Render() end)
OMQ:On("QTRACK_CHANGED", function() U:Render() end)
OMQ:On("SETTINGS_CHANGED", function() U:Render() end)
OMQ:On("QUEST_RUN_CHANGED", function() U:Render() end)
OMQ:On("GRIND_CHANGED", function() U:Render() end)
OMQ:On("CHAIN_RUN_CHANGED", function() U:Render() end)
OMQ:On("MOVE_MODE", function(on)
    moveMode = on and true or false
    if not frame then return end
    if not moveMode then savePosition() end
    U:Render()
end)
