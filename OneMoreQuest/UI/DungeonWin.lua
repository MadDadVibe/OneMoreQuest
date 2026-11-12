-- One More Quest: the dungeon window (decision 530)
-- Shows itself in every 5-player dungeon (not in raids) and hides outside. Top: the dungeon, Time, Mobs XP and Gold
-- (coins looted). Below: the bosses as round portraits (the game's creature portrait from the display id; without
-- one a small 3D model of the creature), a red X on a dead boss. Then "Rare": the rares, grey while alive, in colour
-- with the X once dead. Hover over a boss or rare: its loot as item icons right under the icon; hover over an item:
-- the game's own item tooltip at once (with the item score line, a green "+" marks an upgrade).
-- No close button: the "-" button folds the window to one line (dungeon, time, mob XP, gold); a click on the line
-- or "+" opens it again. Drag to move; the place and the folded state are kept (OMQDB.dwin). /omq dwin reset puts it
-- back. Option "Dungeon window" (options.dungeonWin). Numbers come from OMQ.DungeonWin (Stats/DungeonWin.lua).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local U = {}
OMQ.DungeonWinUI = U

U.PAD = 10
U.ICON = 40
U.GAP = 6
U.COLS = 5
U.LOOT_ICON = 30
U.LOOT_COLS = 4
U.TEST_SECS = 60

local GOLD = { 1.00, 0.82, 0.00 }
local TAN = { 0.72, 0.68, 0.60 }
local WIDTH = U.PAD * 2 + U.COLS * U.ICON + (U.COLS - 1) * U.GAP
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function W() return OMQ.DungeonWin end
local function LP() return OMQ.LootPreview end
local function call(f, ...)
    if not f then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    return unpack(r, 2)
end

local dragged = false
local win, head, title, minBtn, line, body, stats, divider, rareHead, fly
local icons, flyIcons = {}, {}
local test                  -- the sample visit of /omq dwin test and when it ends
U._icons, U._flyIcons = icons, flyIcons

local function saved() return W() and W().Saved() end

----------------------------------------------------------------------
-- Money text: coin icons when the game has them
----------------------------------------------------------------------
function U.Coins(c)
    c = math.floor(c or 0)
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    local s = f and call(f, c)
    if type(s) == "string" and s ~= "" then return s end
    return W().Gold(c)
end

----------------------------------------------------------------------
-- Boss and rare icons
----------------------------------------------------------------------
-- per icon: its round mask, its 3D model and the npc in that model (side tables: never unset frame fields)
local maskOf, modelOf, modelNpc = {}, {}, {}
local function mask(b, tex)
    if not (b.CreateMaskTexture and tex.AddMaskTexture) then return end
    if not maskOf[b] then
        local m = b:CreateMaskTexture()
        if not m then return end
        maskOf[b] = m
        m:SetAllPoints(b)
        call(m.SetTexture, m, MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    call(tex.AddMaskTexture, tex, maskOf[b])
end

-- the icon frame that a loot strip of this icon hangs beside (the window, or the Dungeon Check, decision 531)
local anchorOf = {}

local function makeIcon(parent, size, anchor)
    size = size or U.ICON
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    anchorOf[b] = anchor
    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetAllPoints()
    b.back:SetColorTexture(0.02, 0.02, 0.03, 1)
    mask(b, b.back)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 2, -2)
    b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    mask(b, b.tex)
    b.cross = b:CreateTexture(nil, "OVERLAY")
    b.cross:SetSize(size * 0.7, size * 0.7)
    b.cross:SetPoint("CENTER")
    b.cross:SetTexture(CROSS)
    b.cross:Hide()
    b:SetScript("OnEnter", function(self) U.ShowLoot(self) end)
    return b
end
-- a boss icon for another window: hover shows the loot beside that window
function U.MakeBossIcon(parent, size, anchor) return makeIcon(parent, size, anchor or parent) end

-- the 3D model (only made when an icon needs one: no display id for a portrait)
local function model(b)
    if not modelOf[b] then
        local m = CreateFrame("PlayerModel", nil, b)
        m:SetPoint("TOPLEFT", 3, -3)
        m:SetPoint("BOTTOMRIGHT", -3, 3)
        modelOf[b] = m
    end
    return modelOf[b]
end

function U.SetIcon(b, e, dead)
    b.omqBoss = e
    local D = OMQ.DungeonWinData or {}
    local disp = D.display and D.display[e.npc]
    local portrait = disp and SetPortraitTextureFromCreatureDisplayID
    if portrait then
        b.tex:Show()
        call(SetPortraitTextureFromCreatureDisplayID, b.tex, disp)
        if modelOf[b] then modelOf[b]:Hide() end
        b.omqLook = "portrait"
    else
        b.tex:Hide()
        local m = model(b)
        m:Show()
        if modelNpc[b] ~= e.npc then
            modelNpc[b] = e.npc
            if disp then call(m.SetDisplayInfo, m, disp) else call(m.SetCreature, m, e.npc) end
            call(m.SetPortraitZoom, m, 1)
        end
        b.omqLook = "model"
    end
    -- a dead boss dark with the X; a rare grey until it is dead, then in colour with the X
    local grey = (e.rare and not dead) and true or false
    local dark = (dead and not e.rare) and true or false
    if b.tex.SetDesaturated then b.tex:SetDesaturated(grey) end
    local c = dark and 0.45 or 1
    if b.tex.SetVertexColor then b.tex:SetVertexColor(c, c, c) end
    if modelOf[b] then call(modelOf[b].SetAlpha, modelOf[b], (grey or dark) and 0.45 or 1) end
    if dead then b.cross:Show() else b.cross:Hide() end
    b.omqDead, b.omqGrey = dead and true or false, grey
    b:Show()
end

----------------------------------------------------------------------
-- Loot beside the window
----------------------------------------------------------------------
local hoverIcon, leaveAt

local function buildFly()
    fly = CreateFrame("Frame", "OneMoreQuestDungeonLoot", UIParent)
    fly:SetFrameStrata("FULLSCREEN_DIALOG")
    fly:SetClampedToScreen(true)
    fly:EnableMouse(true)
    local bg = fly:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.07, 0.08, 0.105, 0.97)
    local border = fly:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.48, 0.39, 0.2, 1)
    fly.title = fly:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fly.title:SetPoint("TOPLEFT", 8, -8)
    fly.note = fly:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fly.note:SetPoint("TOPLEFT", 8, -24)
    fly:SetScript("OnUpdate", function() U.FlyTick() end)
    fly:Hide()
end

function U.FlyTick()
    if not (fly and fly:IsShown()) then return end
    local box = hoverIcon and (anchorOf[hoverIcon] or win)
    if not (hoverIcon and hoverIcon:IsShown() and box and box:IsShown()) then U.HideLoot(); return end
    local over = fly:IsMouseOver() or hoverIcon:IsMouseOver()
    if over then leaveAt = nil; return end
    leaveAt = leaveAt or GetTime() + 0.4
    if GetTime() >= leaveAt then U.HideLoot() end
end

function U.HideLoot()
    if fly then fly:Hide() end
    hoverIcon, leaveAt = nil, nil
    U._loot = nil
end

function U.ShowLoot(b)
    local e = b and b.omqBoss
    local box = b and (anchorOf[b] or win)
    if not (e and box) then return end
    if not fly then buildFly() end
    hoverIcon, leaveAt = b, nil
    local name = W().Name(e.npc) or (e.rare and "Rare" or "Boss")
    fly.title:SetText(name)
    local state = b.omqDead and "|cffff5050dead|r" or (e.rare and "|cff9aa0aarare, alive|r" or "|cff9aa0aaalive|r")
    local list, loading = {}, 0
    if LP() and LP().ItemEntries and #e.items > 0 then
        list, loading = LP().IconEntries(LP().ItemEntries(e.items))
    end
    fly.note:SetText(#e.items == 0 and (state .. "  |cff9aa0aano known loot|r") or state)
    for i, it in ipairs(list) do
        local ic = flyIcons[i]
        if not ic then
            ic = LP().MakeRewardIcon(fly)
            ic:SetSize(U.LOOT_ICON, U.LOOT_ICON)
            flyIcons[i] = ic
        end
        LP().SetRewardIcon(ic, it)
        local r, c = math.floor((i - 1) / U.LOOT_COLS), (i - 1) % U.LOOT_COLS
        ic:ClearAllPoints()
        ic:SetPoint("TOPLEFT", fly, "TOPLEFT", 8 + c * (U.LOOT_ICON + 4), -42 - r * (U.LOOT_ICON + 4))
        ic:Show()
    end
    for i = #list + 1, #flyIcons do flyIcons[i]:Hide() end
    local rows = math.max(1, math.ceil(#list / U.LOOT_COLS))
    local w = math.max(150, 16 + U.LOOT_COLS * (U.LOOT_ICON + 4) - 4)
    fly:SetSize(w, #list > 0 and (50 + rows * (U.LOOT_ICON + 4)) or 44)
    -- directly under the icon (decision 531, Tobias): the mouse goes straight down onto the items; the strip may
    -- cover the other icons for the time being
    fly:ClearAllPoints()
    fly:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, 1)
    fly:Show()
    U._loot = { npc = e.npc, name = name, n = #list, loading = loading }
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local function statCol(i, label)
    local x = U.PAD + (i - 1) * 78
    local l = stats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", stats, "TOPLEFT", x, 0)
    l:SetText(label)
    l:SetTextColor(TAN[1], TAN[2], TAN[3])
    local v = stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    v:SetPoint("TOPLEFT", stats, "TOPLEFT", x, -14)
    return v
end

function U.Place()
    if not win then return end
    local s = saved()
    local p = s and s.pos
    win:ClearAllPoints()
    if type(p) == "table" and p[1] then
        win:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        win:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -230)
    end
    U.Refresh()
end

local function build()
    win = CreateFrame("Frame", "OneMoreQuestDungeonWin", UIParent)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) dragged = true; self:StartMoving() end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        local s = saved()
        if s and p then s.pos = { p, rp, x, y } end
    end)
    win:SetScript("OnMouseUp", function(self, button)
        if dragged then dragged = false; return end
        local s = saved()
        if button == "LeftButton" and s and s.min then U.SetMin(false) end
    end)
    local bg = win:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.07, 0.08, 0.105, 0.94)
    local border = win:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.48, 0.39, 0.2, 1)

    title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", U.PAD, -8)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    line = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint("LEFT", title, "RIGHT", 8, 0)
    minBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    minBtn:SetSize(22, 18)
    minBtn:SetPoint("TOPRIGHT", -5, -4)
    minBtn:SetScript("OnClick", function()
        local s = saved()
        U.SetMin(not (s and s.min))
    end)

    body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", 0, -28)
    body:SetPoint("TOPRIGHT", 0, -28)
    body:SetHeight(1)
    stats = CreateFrame("Frame", nil, body)
    stats:SetPoint("TOPLEFT", 0, 0)
    stats:SetSize(WIDTH, 34)
    U._time = statCol(1, "Time")
    U._xp = statCol(2, "Mobs XP")
    U._gold = statCol(3, "Gold")
    divider = body:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", U.PAD, -40)
    divider:SetSize(WIDTH - U.PAD * 2, 1)
    divider:SetColorTexture(0.48, 0.39, 0.2, 0.8)
    rareHead = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rareHead:SetText("Rare")
    rareHead:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    U._empty = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    U._empty:SetPoint("TOPLEFT", U.PAD, -50)
    U._empty:SetText("Bosses show after the first dead boss")
    U._empty:SetTextColor(0.6, 0.63, 0.68)

    local f = CreateFrame("Frame")
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function()
        if fly and fly:IsShown() and hoverIcon then pcall(U.ShowLoot, hoverIcon) end
    end)
    win:Hide()
    U.Place()
end

-- the visit to draw: the sample of /omq dwin test, else the one I am in
function U.Current()
    if test then
        if GetTime() < test.untilAt then return test.v end
        test = nil
    end
    local w = W()
    if not (w and w.On()) then return nil end
    return w.Inside()
end

function U.SetMin(on)
    local s = saved()
    if s then s.min = on and true or nil end
    U.HideLoot()
    U.Refresh()
end

-- the numbers: called every second
function U.Texts(v)
    local w = W()
    local t, xp, g = w.Clock(v.s), w.Num(w.MobXP(v)), U.Coins(v.gold)
    U._time:SetText(t)
    U._xp:SetText(xp)
    U._gold:SetText(g)
    if v.done then U._time:SetTextColor(0.4, 0.85, 0.4) else U._time:SetTextColor(1, 1, 1) end
    line:SetText(t .. "  |cff9aa0aa·|r  " .. xp .. " XP  |cff9aa0aa·|r  " .. g)
    U._shown = { title = title:GetText(), time = t, xp = xp, gold = g, min = line:IsShown() }
end

local function placeRow(list, startIdx, y, dead)
    for i, e in ipairs(list) do
        local idx = startIdx + i - 1
        local b = icons[idx]
        if not b then b = makeIcon(body); icons[idx] = b end
        local r, c = math.floor((i - 1) / U.COLS), (i - 1) % U.COLS
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", body, "TOPLEFT", U.PAD + c * (U.ICON + U.GAP), y - r * (U.ICON + U.GAP))
        U.SetIcon(b, e, dead[e.npc])
    end
    local rows = math.ceil(#list / U.COLS)
    return y - rows * (U.ICON + U.GAP), startIdx + #list
end

function U.Refresh()
    if not win then return end
    local v = U.Current()
    if not v then win:Hide(); U.HideLoot(); U._shown = nil; return end
    local w = W()
    local s = saved()
    local min = s and s.min
    title:SetText(v.key and w.Title(v.key) or v.nm or "Dungeon")
    minBtn:SetText(min and "+" or "-")
    if min then
        body:Hide()
        line:Show()
        win:SetSize(math.max(WIDTH, 40 + (title:GetStringWidth() or 0) + 200), 28)
        U.HideLoot()
    else
        line:Hide()
        body:Show()
        local bosses, rares = {}, {}
        if v.key then bosses, rares = w.Bosses(v.key) end
        local y, idx = -48, 1
        if #bosses == 0 and #rares == 0 then U._empty:Show(); y = -66 else U._empty:Hide() end
        y, idx = placeRow(bosses, idx, y, v.dead or {})
        if #rares > 0 then
            rareHead:ClearAllPoints()
            rareHead:SetPoint("TOPLEFT", body, "TOPLEFT", U.PAD, y - 2)
            rareHead:Show()
            y, idx = placeRow(rares, idx, y - 20, v.dead or {})
        else
            rareHead:Hide()
        end
        for i = idx, #icons do icons[i]:Hide() end
        win:SetSize(WIDTH, 28 - y + U.PAD - U.GAP)
        U._layout = { bosses = #bosses, rares = #rares }
    end
    U.Texts(v)
    win:Show()
end

function U.Tick()
    if not win then
        if not U.Current() then return end
        build()
    end
    local v = U.Current()
    if not v then if win:IsShown() then U.Refresh() end; return end
    if not win:IsShown() then U.Refresh(); return end
    U.Texts(v)
end

function U.Shown() return win and win:IsShown() or false end

-- /omq dwin test: Zul'Farrak for a minute, two bosses dead
function U.Test()
    local v = { id = 209, key = "zf", nm = "Zul'Farrak", s = 752, xp = 11450, qxp = 0, gold = 588000, dead = {}, t = time() }
    local bosses = W().Bosses("zf")
    for i = 1, math.min(2, #bosses) do v.dead[bosses[i].npc] = time() end
    test = { v = v, untilAt = GetTime() + U.TEST_SECS }
    if not win then build() end
    U.Refresh()
end

OMQ:On("DUNGEON_WIN_CHANGED", function()
    if not win then if U.Current() then build() end; return end
    U.Refresh()
end)
OMQ:On("DUNGEON_WIN_TICK", function() U.Tick() end)
