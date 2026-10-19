-- One More Quest: the guided tour (decision 244, improvement 35; mockup "One More Quest – Guided Tour")
-- On the first use (per account) a welcome card: left click starts the tour, right click hides it.
-- /omq tour starts it any time. Every step darkens the screen around one element, puts a gold
-- ring around it and shows the guide panel: step n / 12, title, one or two sentences, the mouse
-- buttons as gold chips, the progress bar, End tour / Back / Next. An element that is not on the
-- screen gets the panel in the middle without a spotlight. In combat the tour pauses and comes back
-- at the same step afterwards. The overlay never takes the mouse; only the panel does.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local TR = {}
OMQ.Tour = TR

local function minimapButton() return _G.OneMoreQuestMinimapButton end
local function partyFrame()
    for _, n in ipairs({ "CompactPartyFrame", "PartyFrame", "PartyMemberFrame1" }) do
        local f = _G[n]
        if f and f.IsShown and f:IsShown() then return f end
    end
end
local function shown(name) local f = _G[name]; if f and f.IsShown and f:IsShown() then return f end end

-- the steps, as in the mockup; target() returns a frame or nil, prepare/cleanup open and close things
TR.STEPS = {
    { title = "Your home base", target = minimapButton,
      text = "The gold exclamation mark at the minimap belongs to One More Quest. Everything starts here.",
      mouse = { { "Hover", "tonight: the stats of every dad" }, { "Left click", "lifetime stats" }, { "Right click", "options" } } },
    { title = "Tonight in numbers", target = function() return shown("OneMoreQuestTooltip") end,
      text = "Every dad in one column, you first. The small number is the place in that row.",
      mouse = { { "Hover", "the exclamation mark at the minimap" } },
      prepare = function() local b = minimapButton(); if b and OMQ.Tooltip then pcall(OMQ.Tooltip.Show, OMQ.Tooltip, b) end end,
      cleanup = function() if OMQ.Tooltip then pcall(OMQ.Tooltip.Hide, OMQ.Tooltip) end end },
    { title = "Alert cards", target = function() return shown("OneMoreQuestAlerts") end,
      text = "Small helpers that pop up when something needs doing: repair, train, drink, buy a tool, call your pet. Most of them do the job for you.",
      mouse = { { "Left click", "do it (cast, arrow, place, open)" }, { "Right click", "hide it for 5 minutes" } } },
    { title = "Where to go", target = function() return shown("OneMoreQuestGuideBar") end,
      text = "The meeting point is always here. Hover it for trainer, vendor, repair, flight master, mailbox, inn and bank.",
      mouse = { { "Click an icon", "the arrow leads you to the nearest one" }, { "Meeting point", "every dad gets an arrow to you" } },
      prepare = function() if OMQ.GuideBar then OMQ.GuideBar.tourOpen = true end end,
      cleanup = function() if OMQ.GuideBar then OMQ.GuideBar.tourOpen = nil end end },
    { title = "The arrow", target = function() return shown("OneMoreQuestArrow") end,
      text = "Blue: your destination. It also points to a dad who fell behind and says how far away he is.",
      mouse = { { "Left click", "the next place of that kind" }, { "Right click", "stop" } } },
    { title = "The check bar", target = function() return shown("OneMoreQuestCheckBar") end,
      text = "Group Check before a dungeon (gear, bags, drinks, quests, best loot), your Progress Check, bets and the \"one more quest?\" vote.",
      mouse = { { "Hover", "the bar slides open" } },
      prepare = function() if OMQ.CheckBar then OMQ.CheckBar.tourOpen = true end end,
      cleanup = function() if OMQ.CheckBar then OMQ.CheckBar.tourOpen = nil end end },
    { title = "Quests together", target = function() return shown("OneMoreQuestQuestTracker") end,
      text = "Quests you accept are shared with dads up to 5 levels apart. When anyone makes progress, this shows everybody's count.",
      mouse = { { "Arrows", "more than one quest" }, { "Right click", "close until the next progress" } },
      prepare = function()
          if not shown("OneMoreQuestQuestTracker") and OMQ.QTrack and OMQ.QTrack.Demo then pcall(OMQ.QTrack.Demo, OMQ.QTrack) end
      end },
    { title = "Who needs this item?", target = function() return nil end,
      text = "Hold Alt over an item: what each dad wears in that slot, and his score with the new one. Red: he can't wear it.",
      mouse = { { "Alt + hover", "compare with the dads" } } },
    { title = "Your party", target = partyFrame,
      text = "Healers: Shift + left click on a frame is your emergency heal, Shift + right click the comfortable one. Everyone: the \"<\" key follows the nearest dad.",
      mouse = { { "Shift + left", "emergency heal" }, { "Shift + right", "comfortable heal" }, { "< key", "follow" } } },
    { title = "News in the chat", target = function() return shown("ChatFrame1") end,
      text = "Shared quests, flights, bets and finished bets show up here as One More Quest lines.",
      mouse = {} },
    { title = "Bets and the vote", target = function()
          local b = OMQ.CheckBar and OMQ.CheckBar.Button and OMQ.CheckBar:Button("bet")
          return (b and b.IsShown and b:IsShown()) and b or shown("OneMoreQuestCheckBar")
      end,
      text = "The die starts a bet. Bets are evaluated automatically, and debts are paid automatically by mail. The moon starts the vote: one more quest or quit?",
      mouse = { { "Die", "start a bet" }, { "Moon", "one more quest or quit?" } },
      prepare = function() if OMQ.CheckBar then OMQ.CheckBar.tourOpen = true end end,
      cleanup = function() if OMQ.CheckBar then OMQ.CheckBar.tourOpen = nil end end },
    { title = "All in your hands", target = minimapButton,
      text = "Right click the exclamation mark for the quick options, Shift + right click for every setting. Type /omq tour to see this again.",
      mouse = { { "Right click", "quick options" }, { "Shift + right", "all options" } } },
}

local GOLD = { 0.89, 0.71, 0.29 }
local overlay, ring, dims, panel
TR.index, TR.active, TR.paused = 0, false, false

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------
local function fs(parent, font, r, g, b)
    local f = parent:CreateFontString(nil, "OVERLAY", font)
    f:SetJustifyH("LEFT")
    if r then f:SetTextColor(r, g, b) end
    return f
end

local function build()
    overlay = CreateFrame("Frame", "OneMoreQuestTour", UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    if overlay.EnableMouse then overlay:EnableMouse(false) end
    dims = {}
    for i = 1, 4 do
        local t = overlay:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(0.015, 0.02, 0.03, 0.72)
        dims[i] = t
    end
    ring = {}
    for i = 1, 4 do
        local t = overlay:CreateTexture(nil, "BORDER")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        ring[i] = t
    end

    panel = CreateFrame("Frame", "OneMoreQuestTourPanel", overlay, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(380, 220)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(overlay:GetFrameLevel() + 10)
    if panel.EnableMouse then panel:EnableMouse(true) end
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        panel:SetBackdropColor(0.086, 0.094, 0.12, 0.97)
        panel:SetBackdropBorderColor(0.63, 0.5, 0.21, 1)
    end
    panel.step = fs(panel, "GameFontNormalSmall", GOLD[1], GOLD[2], GOLD[3])
    panel.step:SetPoint("TOPLEFT", 18, -14)
    panel.title = fs(panel, "GameFontNormalLarge", 0.95, 0.82, 0.48)
    panel.title:SetPoint("TOPLEFT", 18, -32)
    panel.title:SetWidth(344)
    panel.text = fs(panel, "GameFontHighlight", 0.9, 0.89, 0.86)
    panel.text:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -8)
    panel.text:SetWidth(344)
    if panel.text.SetWordWrap then panel.text:SetWordWrap(true) end
    panel.chips = {}
    for i = 1, 3 do
        local chip = CreateFrame("Frame", nil, panel)
        chip:SetSize(100, 16)
        chip.bg = chip:CreateTexture(nil, "BACKGROUND")
        chip.bg:SetAllPoints()
        chip.bg:SetColorTexture(0.165, 0.14, 0.086, 1)
        chip.key = fs(chip, "GameFontNormalSmall", 0.95, 0.82, 0.48)
        chip.key:SetPoint("CENTER")
        chip.val = fs(panel, "GameFontHighlightSmall", 0.79, 0.8, 0.84)
        chip.val:SetPoint("LEFT", chip, "RIGHT", 8, 0)
        panel.chips[i] = chip
    end
    panel.dots = {}
    for i = 1, #TR.STEPS do
        local d = panel:CreateTexture(nil, "ARTWORK")
        d:SetSize(24, 4)
        panel.dots[i] = d
    end
    local function button(label, w, onClick, primary)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(w, 26)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end
    panel.nextB = button("Next", 90, function() TR:Next() end)
    panel.nextB:SetPoint("BOTTOMRIGHT", -16, 14)
    panel.backB = button("Back", 80, function() TR:Back() end)
    panel.backB:SetPoint("RIGHT", panel.nextB, "LEFT", -8, 0)
    panel.endB = CreateFrame("Button", nil, panel)
    panel.endB:SetSize(80, 26)
    panel.endB:SetPoint("BOTTOMLEFT", 14, 14)
    panel.endB.label = fs(panel.endB, "GameFontDisable")
    panel.endB.label:SetPoint("LEFT")
    panel.endB.label:SetText("End tour")
    panel.endB:SetScript("OnClick", function() TR:Stop() end)
    panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.close:SetPoint("TOPRIGHT", 2, 2)
    panel.close:SetScript("OnClick", function() TR:Stop() end)
    overlay:Hide()
end

-- a frame's box in UIParent coordinates: left, bottom, width, height
local function boxOf(f)
    if not (f and f.GetLeft) then return nil end
    local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    if not (l and b and w and h) or w <= 0 or h <= 0 then return nil end
    local s = (f.GetEffectiveScale and f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return l * s, b * s, w * s, h * s
end
TR._boxOf = boxOf

local function screen() return tonumber((UIParent:GetWidth())) or 1440, tonumber((UIParent:GetHeight())) or 860 end

local function layoutSpotlight(l, b, w, h)
    local W, H = screen()
    local pad = 6
    if not l then
        dims[1]:ClearAllPoints(); dims[1]:SetAllPoints(overlay); dims[1]:Show()
        for i = 2, 4 do dims[i]:Hide() end
        for i = 1, 4 do ring[i]:Hide() end
        return
    end
    local x0, y0, x1, y1 = l - pad, b - pad, l + w + pad, b + h + pad
    -- top, bottom, left, right
    dims[1]:ClearAllPoints(); dims[1]:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0); dims[1]:SetSize(W, math.max(1, H - y1))
    dims[2]:ClearAllPoints(); dims[2]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0); dims[2]:SetSize(W, math.max(1, y0))
    dims[3]:ClearAllPoints(); dims[3]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, y0); dims[3]:SetSize(math.max(1, x0), y1 - y0)
    dims[4]:ClearAllPoints(); dims[4]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", x1, y0); dims[4]:SetSize(math.max(1, W - x1), y1 - y0)
    for i = 1, 4 do dims[i]:Show() end
    local t = 2
    ring[1]:ClearAllPoints(); ring[1]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", x0, y1 - t); ring[1]:SetSize(x1 - x0, t)
    ring[2]:ClearAllPoints(); ring[2]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", x0, y0); ring[2]:SetSize(x1 - x0, t)
    ring[3]:ClearAllPoints(); ring[3]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", x0, y0); ring[3]:SetSize(t, y1 - y0)
    ring[4]:ClearAllPoints(); ring[4]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", x1 - t, y0); ring[4]:SetSize(t, y1 - y0)
    for i = 1, 4 do ring[i]:Show() end
end

-- the panel next to the element (the side with more room), kept on the screen
function TR.PanelPoint(l, b, w, h, pw, ph, W, H)
    if not l then return (W - pw) / 2, (H - ph) / 2 end
    local x
    if l + w / 2 > W / 2 then x = l - pw - 24 else x = l + w + 24 end
    local y = b + h / 2 - ph / 2
    if x < 8 or x + pw > W - 8 then
        -- no room beside it: below or above it
        x = math.min(math.max(8, l + w / 2 - pw / 2), W - pw - 8)
        y = (b > H / 2) and (b - ph - 24) or (b + h + 24)
    end
    return math.min(math.max(8, x), W - pw - 8), math.min(math.max(8, y), H - ph - 8)
end

local function render()
    local s = TR.STEPS[TR.index]
    if not s then return end
    if not overlay then build() end
    panel.step:SetText(string.format("TOUR  %d / %d", TR.index, #TR.STEPS))
    panel.title:SetText(s.title)
    panel.text:SetText(s.text)
    local y = -32 - (tonumber((panel.title:GetStringHeight())) or 18) - 8 - (tonumber((panel.text:GetStringHeight())) or 40) - 12
    for i, chip in ipairs(panel.chips) do
        local m = s.mouse[i]
        chip:ClearAllPoints()
        if m then
            chip:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y)
            chip.key:SetText(m[1]); chip.val:SetText(m[2])
            chip:Show(); chip.val:Show()
            y = y - 22
        else
            chip:Hide(); chip.val:Hide()
        end
    end
    for i, d in ipairs(panel.dots) do
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", panel, "TOPLEFT", 18 + (i - 1) * 29, y - 6)
        if i == TR.index then d:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        elseif i < TR.index then d:SetColorTexture(0.54, 0.42, 0.14, 1)
        else d:SetColorTexture(0.23, 0.24, 0.27, 1) end
    end
    local ph = -y + 6 + 4 + 14 + 26 + 14
    panel:SetHeight(ph)
    panel.nextB:SetText(TR.index == #TR.STEPS and "Finish" or "Next")
    if TR.index == 1 then panel.backB:Disable() else panel.backB:Enable() end
    local target = s.target and s.target()
    local l, b, w, h = boxOf(target)
    layoutSpotlight(l, b, w, h)
    local W, H = screen()
    local px, py = TR.PanelPoint(l, b, w, h, tonumber((panel:GetWidth())) or 380, ph, W, H)
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", px, py)
    TR.lastTarget = target
    overlay:Show()
end

----------------------------------------------------------------------
-- Control
----------------------------------------------------------------------
local function leave(i)
    local s = TR.STEPS[i]
    if s and s.cleanup then pcall(s.cleanup) end
end
local function enter(i)
    local s = TR.STEPS[i]
    if s and s.prepare then pcall(s.prepare) end
    -- prepared frames (an opened bar, the tooltip) need a moment to lay out
    if C_Timer and C_Timer.After then C_Timer.After(0.15, function() if TR.active and TR.index == i and not TR.paused then render() end end) end
    render()
end

function TR:Start()
    if TR.active then leave(TR.index) end
    TR.active, TR.paused, TR.index = true, false, 1
    if InCombatLockdown and InCombatLockdown() then TR.paused = true; OMQ:Print("The tour starts after the fight"); return end
    enter(1)
end
function TR:Next()
    if not TR.active then return end
    if TR.index >= #TR.STEPS then return TR:Stop(true) end
    leave(TR.index); TR.index = TR.index + 1; enter(TR.index)
end
function TR:Back()
    if not TR.active or TR.index <= 1 then return end
    leave(TR.index); TR.index = TR.index - 1; enter(TR.index)
end
function TR:Stop(finished)
    if TR.active then leave(TR.index) end
    TR.active, TR.paused = false, false
    if overlay then overlay:Hide() end
    OMQ:Print(finished and "You are set! Have fun, dads. /omq tour shows the tour again." or "Tour ended. /omq tour starts it again.")
end
function TR:IsActive() return TR.active end

-- combat: pause, and come back at the same step
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_DISABLED")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if not TR.active then return end
    if event == "PLAYER_REGEN_DISABLED" then
        TR.paused = true
        leave(TR.index)
        if overlay then overlay:Hide() end
    elseif TR.paused then
        TR.paused = false
        enter(TR.index)
    end
end)

OMQ:RegisterCommand("tour", function() TR:Start() end, "the guided tour through the addon")

----------------------------------------------------------------------
-- The welcome card (first use, per account)
----------------------------------------------------------------------
if OMQ.Alerts then
    OMQ.Alerts:Register({ id = "welcome", name = "Welcome card with the guided tour", check = function()
        if OMQDB and OMQDB.tourSeen then return nil end
        if TR.active then return nil end
        return { {
            key = "welcome", tag = "WELCOME", title = "New to One More Quest?",
            sub = "Left click: guided tour - Right click: not now", text = "New to One More Quest?",
            icon = "Interface\\Icons\\INV_Misc_Book_09", color = GOLD,
            open = function() TR:Start() end,        -- then dismissed like every card, which marks it seen
        } }
    end })
    OMQ:On("ALERT_DISMISSED", function(key)
        if key == "welcome" and OMQDB then OMQDB.tourSeen = true end
    end)
end
