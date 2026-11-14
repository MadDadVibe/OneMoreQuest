-- One More Quest: run bar (decision 602). A third small icon bar that sits directly above the check bar
-- and holds every run: Quest Run, Area Run, Grind Run, Chain Run and the dungeon buttons (the Group
-- Check of a dungeon, where the Dungeon Run starts). Same look and behaviour as the check bar: collapsed
-- it shows one icon, hovering slides out the others; it grows to the right and only when it would leave
-- the screen it grows to the left (mirrored). Collapsed it shows the icon of the run that is going on
-- now (with a frame in that run's colour), otherwise the Quest Run icon.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local SIZE, GAP, PAD = 34, 3, 4        -- same as the check bar

local RB = {}
OMQ.RunBar = RB
RB.COLLAPSED = 1

local frame, buttons = nil, {}
local items = {}
local expanded, suppressed = false, false
local flipped = false
local shownSig

local MEDIA = "Interface\\AddOns\\OneMoreQuest\\Media\\"
RB.COLORS = {
    run = { 0.89, 0.71, 0.29 },        -- Quest Run: gold
    area = { 0.49, 0.78, 0.44 },       -- Area Run: green
    grind = { 0.86, 0.26, 0.22 },      -- Grind Run: red
    chain = { 0.66, 0.33, 0.94 },      -- Chain Run: purple
    dungeon = { 0.30, 0.62, 1.00 },    -- Dungeon Run: blue
}
local ITEMS = {
    { id = "run", label = "Quest Run", tip = "Click: pick 1, 3, 5 or 7 quests - OMQ plans the shortest way and a small arrow above the quest tracker leads you",   -- decision 465
      icon = MEDIA .. "Icon_Run" },
    { id = "area", label = "Area Run", tip = "Click: pick a zone - OMQ plans one way through all its quests and their follow-ups",   -- decision 491, from level 5
      icon = MEDIA .. "Icon_Area", show = function() return not OMQ.Unlock or OMQ.Unlock:Has("area") end },
    { id = "grind", label = "Grind Run", tip = "Click: pick a zone or grind right here - the arrow leads you to a spot full of mobs, then 30 or 60 minutes",   -- decision 518, from level 10
      icon = MEDIA .. "Icon_Grind", show = function() return not OMQ.Unlock or OMQ.Unlock:Has("grind") end },
    { id = "chain", label = "Chain Run", tip = "Click: quest chains every dad should do (the Cozy Sleeping Bag, the Night Watchman's Torch) - OMQ leads you step by step",   -- decision 595
      icon = MEDIA .. "Icon_Chain" },
}

local pendingLevel
local function currentItems()
    local list = {}
    for _, it in ipairs(ITEMS) do if not it.show or it.show() then list[#list + 1] = it end end
    local level = math.max(UnitLevel and UnitLevel("player") or 1, pendingLevel or 0)   -- UnitLevel can lag behind PLAYER_LEVEL_UP
    if OMQ.DungeonsForLevel and (not OMQ.Unlock or OMQ.Unlock:Has("dungeon")) then   -- the dungeon checks from level 13
        for _, d in ipairs(OMQ:DungeonsForLevel(level)) do
            list[#list + 1] = { id = "d:" .. d.key, label = d.name, dungeon = d.key, text = d.abbr,
                tip = "Click: Group Check with the dungeon quests, the entrance and who is how far from it (level " .. d.min .. "-" .. d.max .. ")" }
        end
    end
    return list
end

-- the run going on now: the item id and its colour (nil when no run)
function RB.ActiveRun()
    local C = OMQ.ChainRun
    if C and C.Active and C:Active() then return "chain", RB.COLORS.chain end
    local G = OMQ.Grind
    if G and G.Active and G:Active() then return "grind", RB.COLORS.grind end
    local R = OMQ.QuestRun
    if R and R.Active and R:Active() then
        local r = R.Run and R:Run() or {}
        if r.kind == "area" then return "area", RB.COLORS.area end
        if r.kind == "dungeon" and r.dungeon then return "d:" .. r.dungeon, RB.COLORS.dungeon end
        return "run", RB.COLORS.run
    end
    return nil
end

local makeButton

local function layout()
    if not frame then return end
    items = currentItems()
    local active, color = RB.ActiveRun()
    local first = 1                      -- collapsed: the active run's icon (when it is on the bar)
    if active then
        for i, it in ipairs(items) do if it.id == active then first = i; break end end
    end
    local n = expanded and #items or math.min(RB.COLLAPSED, #items)
    local width = PAD * 2 + math.max(n, 1) * (SIZE + GAP) - GAP
    local GB = OMQ.GuideBar
    local guide = GB and GB:Frame()
    local anchorBtn = GB and GB.AnchorButton and GB:AnchorButton()
    local left = GB and GB.AnchorLeft and GB:AnchorLeft()
    local screenW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1920
    flipped = left and (left + width > screenW) and true or false
    local up = 6 + ((OMQ.CheckBar and OMQ.CheckBar.HEIGHT) or (SIZE + PAD * 2)) + 3   -- above the check bar, 3 px gap
    frame:ClearAllPoints()
    if anchorBtn then
        if flipped then frame:SetPoint("BOTTOMRIGHT", anchorBtn, "TOPRIGHT", 4, up)
        else frame:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", -4, up) end
    elseif _G.OneMoreQuestCheckBar then
        frame:SetPoint("BOTTOMLEFT", _G.OneMoreQuestCheckBar, "TOPLEFT", 0, 3)
    elseif guide then
        frame:SetPoint("BOTTOMLEFT", guide, "TOPLEFT", 0, 2)
    end
    frame:SetSize(width, SIZE + PAD * 2)
    local used = {}
    for i, it in ipairs(items) do
        local b = buttons[it.id] or makeButton(it)
        used[it.id] = true
        local slot
        if expanded then slot = i - 1
        elseif i == first then slot = 0 end
        if slot then
            if flipped then slot = n - 1 - slot end
            b:ClearAllPoints()
            b:SetPoint("LEFT", frame, "LEFT", PAD + slot * (SIZE + GAP), 0)
            b:Show()
        else
            b:Hide()
        end
        local on = (it.id == active)
        for _, e in ipairs(b.edges) do
            if on then e:SetColorTexture(color[1], color[2], color[3], 1); e:Show() else e:Hide() end
        end
    end
    for id, b in pairs(buttons) do if not used[id] then b:Hide() end end
    RB._first = items[first] and items[first].id
    -- a purple dot: a chain became ready for me (595, K4); on the shown icon while the bar is closed
    local new = OMQ.ChainRun and OMQ.ChainRun.NewForMe and OMQ.ChainRun.NewForMe() or false
    RB._dot = new
    for i, it in ipairs(items) do
        local b = buttons[it.id]
        if b and b.dot then
            local on = new and ((it.id == "chain" and expanded) or (i == first and not expanded))
            if on then b.dot:Show() else b.dot:Hide() end
        end
    end
    shownSig = tostring(active) .. "|" .. tostring(new)
end

local function click(item)
    if item.dungeon then
        if OMQ.Ready then OMQ.Ready:Toggle(item.dungeon) end
    elseif item.id == "run" then
        if OMQ.QuestRunUI then OMQ.QuestRunUI:Toggle() end
    elseif item.id == "area" then
        if OMQ.AreaRunUI then OMQ.AreaRunUI:Toggle() end
    elseif item.id == "grind" then
        if OMQ.GrindUI then OMQ.GrindUI:Toggle() end
    elseif item.id == "chain" then
        if OMQ.ChainRunUI then OMQ.ChainRunUI:Toggle() end
    end
    suppressed = true
    expanded = false
    layout()
end

local function mouseOver()
    if frame.IsMouseOver then
        local ok, v = pcall(frame.IsMouseOver, frame)
        if ok then return v and true or false end
    end
    return MouseIsOver and MouseIsOver(frame) and true or false
end

function makeButton(item)
    local b = CreateFrame("Button", nil, frame)
    buttons[item.id] = b
    b:SetSize(SIZE, SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    if item.icon then
        b.icon:SetTexture(item.icon)
    else
        b.icon:SetTexture(MEDIA .. "Icon_Dungeon")             -- dungeon buttons: the short name engraved on stone
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.label:SetPoint("CENTER", 0, -1)
        if b.label.SetFont then pcall(b.label.SetFont, b.label, "Fonts\\MORPHEUS.TTF", 13, "OUTLINE") end
        b.label:SetText(item.text or "?")
        b.label:SetTextColor(0.94, 0.78, 0.38)
    end
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    -- the frame in the colour of the run going on (2 px on each side)
    b.edges = {}
    local function edge(p1, p2, w, h)
        local e = b:CreateTexture(nil, "OVERLAY")
        e:SetPoint(p1); e:SetPoint(p2)
        if w then e:SetWidth(w) else e:SetHeight(h) end
        e:Hide()
        b.edges[#b.edges + 1] = e
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 2)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetSize(9, 9)
    b.dot:SetPoint("TOPRIGHT", 1, 1)
    b.dot:SetColorTexture(0.66, 0.33, 0.94, 1)
    b.dot:Hide()
    b.item = item
    b:SetScript("OnClick", function(self) click(self.item) end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.item.label)
        GameTooltip:AddLine(self.item.tip, 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local function build()
    frame = CreateFrame("Frame", "OneMoreQuestRunBar", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    local plate = frame:CreateTexture(nil, "BACKGROUND")
    plate:SetAllPoints()
    plate:SetColorTexture(0.07, 0.08, 0.105, 0.92)
    local t, slow = 0, 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        t = t + (elapsed or 0)
        slow = slow + (elapsed or 0)
        if t < 0.05 then return end
        t = 0
        local over = mouseOver()
        if not over then suppressed = false end
        local want = RB.tourOpen or (over and not suppressed)          -- tourOpen: the guided tour
        if want ~= expanded then expanded = want; layout(); return end
        if slow >= 0.5 then                                          -- a run started or ended: other icon / frame
            slow = 0
            local active = RB.ActiveRun()
            local new = OMQ.ChainRun and OMQ.ChainRun.NewForMe and OMQ.ChainRun.NewForMe() or false
            if tostring(active) .. "|" .. tostring(new) ~= shownSig then layout() end
        end
    end)
    layout()
end

-- follows the guidance bar like the check bar: same visibility, same screen edge
function RB:Follow(guide)
    if not frame then return end
    if guide and guide:IsShown() then frame:Show() else frame:Hide() end
    layout()
end

function RB:IsExpanded() return expanded end
function RB:IsFlipped() return flipped end
function RB:Count()
    local n = 0
    for _, it in ipairs(ITEMS) do if not it.show or it.show() then n = n + 1 end end
    return n
end
function RB:Items() return items end
function RB:Refresh() layout() end
function RB:Button(id) return buttons[id] end
function RB:First() return RB._first end
function RB:Frame() return frame end

local lvl = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do pcall(lvl.RegisterEvent, lvl, e) end
lvl:SetScript("OnEvent", function(_, e, newLevel)
    if e == "PLAYER_LEVEL_UP" then pendingLevel = tonumber(newLevel) end
    if frame then layout() end
end)

OMQ:On("UNLOCK", function() if frame then layout() end end)

OMQ:On("READY", function()
    build()
    local g = OMQ.GuideBar and OMQ.GuideBar:Frame()
    if g then RB:Follow(g) end
end)
