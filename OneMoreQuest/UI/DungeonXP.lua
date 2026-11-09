-- One More Quest: the dungeon XP card (decision 493)
-- Comes when I leave a dungeon (OMQ.DungeonXP fires DUNGEON_XP_DONE): the dungeon, its XP and XP per hour,
-- and the XP per hour outside with the difference in percent. Top of the screen, 20 seconds (the mouse over
-- it holds it), right click or Close hides it. No chat line. Option "Dungeon XP card" (options.dungeonXP).
-- /omq dxp test shows a sample card.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local U = {}
OMQ.DungeonXPCard = U

U.SHOW = 20
local GOLD = { 0.89, 0.71, 0.29 }
local TAN = { 0.72, 0.63, 0.42 }
local GREEN = { 0.40, 0.85, 0.40 }
local RED = { 1.00, 0.45, 0.40 }
local GRAY = { 0.70, 0.70, 0.72 }

local card, title, line1, line2
local hideAt

local function build()
    card = CreateFrame("Frame", "OneMoreQuestDungeonXP", UIParent)
    card:SetSize(330, 104)
    card:SetPoint("TOP", UIParent, "TOP", 0, -150)
    card:SetFrameStrata("DIALOG")
    card:EnableMouse(true)
    local border = card:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    local bg = card:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.086, 0.114, 0.97)
    local head = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head:SetPoint("TOP", 0, -10)
    head:SetText("DUNGEON XP")
    head:SetTextColor(TAN[1], TAN[2], TAN[3])
    title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -26)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    line1 = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line1:SetPoint("TOP", 0, -50)
    line2 = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line2:SetPoint("TOP", 0, -68)
    local close = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    close:SetSize(22, 20)
    close:SetText("x")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() U.Hide() end)
    card:SetScript("OnMouseUp", function(_, b) if b == "RightButton" then U.Hide() end end)
    card:Hide()
end

function U.On() return not (OMQ.db and OMQ.db.options and OMQ.db.options.dungeonXP == false) end

function U.Show(r)
    if not r then return end
    if not card then build() end
    local D = OMQ.DungeonXP
    local a, b, pct = D.Lines(r)
    title:SetText(r.nm or "Dungeon")
    line1:SetText(a)
    line2:SetText(b)
    local c = pct == nil and GRAY or (pct >= 0 and GREEN or RED)
    line2:SetTextColor(c[1], c[2], c[3])
    U._shown = { title = r.nm, a = a, b = b, pct = pct }
    card:Show()
    hideAt = GetTime() + U.SHOW
    if OMQ.Sound and OMQ.Sound.Play then pcall(OMQ.Sound.Play, OMQ.Sound, "done") end
end

function U.Hide()
    if card then card:Hide() end
    hideAt = nil
    U._shown = nil
end

function U.Shown() return card and card:IsShown() or false end

function U.Tick()
    if not hideAt then return end
    if card and card.IsMouseOver and card:IsMouseOver() then hideAt = math.max(hideAt, GetTime() + 3); return end
    if GetTime() >= hideAt then U.Hide() end
end

OMQ:On("DUNGEON_XP_DONE", function(r) if U.On() then U.Show(r) end end)
OMQ:On("READY", function()
    C_Timer.NewTicker(0.5, function()
        local ok, err = pcall(U.Tick)
        if not ok then OMQ:Error("dungeonxp card", err) end
    end)
end)
