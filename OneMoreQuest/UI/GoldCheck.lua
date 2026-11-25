-- One More Quest: Goldgrind Check (decision 695)
--   The coin icon of the check bar: the mobs with the most gold per hour at 60 kills per hour (OMQ.Grind.GoldMobs,
--   loot of Data/GrindLoot.lua x auction or vendor prices, no leather). A switch at the top: "Global" (every mob) or
--   "My level" (6 levels under me to 2 over me); the window keeps the last choice (OMQDB.goldCheck.global). Columns:
--   place, mob, level, zone, gold per kill, gold per hour, measured or estimated. The best 25, the mouse wheel
--   scrolls. Mouse over a row: the best drops and the coin per kill; a click: the big arrow to the mob's best spot,
--   there the Grind Run asks 30 or 60 minutes.
-- Plain frames without protected calls.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local GC = {}
OMQ.GoldCheck = GC

local GOLD = { 1, 0.82, 0 }
local W, ROWS, ROW_H = 560, 12, 22
local win, title, sub, switch, foot, rows
GC.offset = 0
GC._view = {}

local function G() return OMQ.Grind end
local function money(c) return OMQ.GrindUI and OMQ.GrindUI.Money(c) or tostring(math.floor(c or 0)) end
local function store()
    OMQDB = OMQDB or {}
    OMQDB.goldCheck = OMQDB.goldCheck or {}
    return OMQDB.goldCheck
end
function GC:Global() return store().global == true end
function GC:SetGlobal(v)
    store().global = v and true or false
    GC.offset = 0
    self:Render()
end

local COLS = { { "#", 24 }, { "Mob", 150 }, { "Level", 50 }, { "Zone", 120 }, { "per kill", 70 }, { "per hour", 76 }, { "", 40 } }

local function cellsOf(parent, font)
    local cells, x = {}, 0
    for i, c in ipairs(COLS) do
        local fs = parent:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(c[2])
        fs:SetJustifyH(i >= 5 and i <= 6 and "RIGHT" or "LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        cells[i] = fs
        x = x + c[2] + 6
    end
    return cells
end

local function build()
    win = CreateFrame("Frame", "OneMoreQuestGoldCheck", UIParent)
    win:SetSize(W, 120)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local border = win:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.72, 0.58, 0.2, 1)
    local bg = win:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.086, 0.114, 0.97)
    title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    title:SetText("Goldgrind Check")
    sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 14, -36)
    sub:SetWidth(W - 150)
    sub:SetJustifyH("LEFT")
    switch = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    switch:SetSize(110, 22)
    switch:SetPoint("TOPRIGHT", -34, -10)
    switch:SetScript("OnClick", function() GC:SetGlobal(not GC:Global()) end)
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() GC:Close() end)
    local head = CreateFrame("Frame", nil, win)
    head:SetSize(W - 28, ROW_H)
    head:SetPoint("TOPLEFT", 14, -56)
    local hc = cellsOf(head, "GameFontNormalSmall")
    for i, c in ipairs(COLS) do hc[i]:SetText(c[1]) end
    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(W - 28, ROW_H)
        r:SetPoint("TOPLEFT", 14, -56 - i * ROW_H)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
        r.hl:Hide()
        r.cells = cellsOf(r, "GameFontHighlightSmall")
        r:SetScript("OnClick", function(self) GC:RowClick(self) end)
        r:SetScript("OnEnter", function(self) self.hl:Show(); GC:RowTip(self) end)
        r:SetScript("OnLeave", function(self) self.hl:Hide(); if GameTooltip then GameTooltip:Hide() end end)
        r:Hide()
        rows[i] = r
    end
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta) GC:Scroll(-delta) end)
    foot = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetPoint("BOTTOMLEFT", 14, 10)
    foot:SetWidth(W - 28)
    foot:SetJustifyH("LEFT")
    foot:SetText("Mouse over: the best drops. Click: the arrow to the mob's best spot. Mouse wheel: more.")
    win:Hide()
end

function GC:List()
    return G().GoldMobs(self:Global(), G().Level())
end

function GC:Render()
    if not win then return end
    local level = G().Level()
    local list = self:List()
    local global = self:Global()
    switch:SetText(global and "Global" or "My level")
    if global then
        sub:SetText(string.format("All mobs, gold per hour at %d kills per hour.", G().PACE))
    else
        sub:SetText(string.format("Mobs for level %d (%d-%d), gold per hour at %d kills per hour.", level,
            math.max(1, level - G().GOLD_BELOW), level + G().ABOVE, G().PACE))
    end
    local maxOff = math.max(0, #list - ROWS)
    if GC.offset > maxOff then GC.offset = maxOff end
    if GC.offset < 0 then GC.offset = 0 end
    local view = { global = global, rows = {}, total = #list, offset = GC.offset }
    GC._view = view
    local shown = 0
    for i = 1, ROWS do
        local r, e = rows[i], list[GC.offset + i]
        r.entry = e
        if e then
            local c = r.cells
            c[1]:SetText(tostring(GC.offset + i))
            c[2]:SetText(e.name)
            c[3]:SetText(e.lo == e.hi and tostring(e.lo) or (e.lo .. "-" .. e.hi))
            c[4]:SetText(e.zoneName or "?")
            c[5]:SetText(money(e.per))
            c[6]:SetText("|cffffd100" .. money(e.gph) .. "|r")
            c[7]:SetText(e.measured and "|cff7fc76fmeas.|r" or "|cff9d9d9dest.|r")
            r:Show()
            shown = shown + 1
            view.rows[i] = { npc = e.npc, name = e.name, per = e.per, gph = e.gph, zone = e.zone, measured = e.measured }
        else
            r:Hide()
        end
    end
    if #list == 0 then sub:SetText(sub:GetText() .. "\nNo mob with loot data here.") end
    win:SetSize(W, 56 + (shown + 1) * ROW_H + 34)
end

function GC:Scroll(n)
    GC.offset = GC.offset + (n or 0)
    self:Render()
end

-- the tooltip lines of a row: per hour, coin, the best drops, measured or estimated
function GC.TipLines(e)
    local out = { string.format("%s: %s per hour (%s per kill x %d)", e.name, money(e.gph), money(e.per), G().PACE) }
    if (e.coin or 0) > 0 then out[#out + 1] = "Coin: " .. money(e.coin) .. " per kill" end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    for _, it in ipairs(e.top or {}) do
        local ok, name = pcall(info or function() end, it.id)
        out[#out + 1] = string.format("%s: %s per kill", (ok and name) or ("Item " .. it.id), money(it.w))
    end
    out[#out + 1] = e.measured and "Loot measured in Forever." or "Loot from drop chances (estimated)."
    out[#out + 1] = "Auction prices from your scan, else the vendor price. No leather."
    return out
end
function GC:RowTip(r)
    local e = r and r.entry
    if not (e and GameTooltip) then return end
    local lines = GC.TipLines(e)
    GC._tip = lines
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetText(lines[1], GOLD[1], GOLD[2], GOLD[3])
    for i = 2, #lines do GameTooltip:AddLine(lines[i], 1, 1, 1) end
    GameTooltip:Show()
end
function GC:RowClick(r)
    local e = r and r.entry
    if not (e and e.spot) then return false end
    G():Go(e.spot)
    self:Close()
    return true
end

function GC:IsOpen() return win and win:IsShown() or false end
function GC:Open()
    if not win then build() end
    GC.offset = 0
    win:Show()
    self:Render()
end
function GC:Close() if win then win:Hide() end end
function GC:Toggle() if self:IsOpen() then self:Close() else self:Open() end end

OMQ:On("GRIND_CHANGED", function() if GC:IsOpen() then GC:Render() end end)
OMQ:RegisterCommand("gold", function(arg)
    arg = (arg or ""):lower()
    if arg == "global" then GC:Open(); GC:SetGlobal(true) return end
    if arg == "level" then GC:Open(); GC:SetGlobal(false) return end
    GC:Toggle()
end, "Goldgrind Check: /omq gold [global|level]")
