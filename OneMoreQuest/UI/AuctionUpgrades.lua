-- One More Quest: Auction Helper, the Upgrades tab (decision 637)
-- The third tab of the auction helper: for every gear slot the three best upgrades on sale (the item score of
-- my class and role against what I wear, an empty slot counts the full value; rings and trinkets one group each,
-- against the weaker one), the weapons (the main hand, the off hand, the ranged slot with the wands of cloth
-- casters) and the bags - all moved here from the Buy tab. On top the gold per item: 10s, 50s, 1g, 3g, 5g or no
-- limit; every change searches again. Never more than the gold I carry.
-- The searches themselves live in UI/AuctionBuy.lua (B.NextUpgQuery, B.GearSlots, B.Bags); buying is the same as
-- before: the first click looks at the offer again, the second buys it. Right click: never suggest it again.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local U = {}
OMQ.AuctionUpgrades = U

U.LIMIT_LABEL = { [1000] = "10s", [5000] = "50s", [10000] = "1g", [30000] = "3g", [50000] = "5g", [0] = "No limit" }
U.GROUPS_SHOWN = 6        -- slot groups shown at once; the mouse wheel shows the others
U.TILE_W, U.TILE_H = 114, 40

local function B() return OMQ.AuctionBuy end
local function AH() return OMQ.AuctionHelper end
local function money(c) return AH().Money(c) end
local function money0(c) return (c and c > 0) and money(c) or "-" end
local function info(x)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(x) end
    if GetItemInfo then return GetItemInfo(x) end
end
local function instant(x)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(x) end
    if GetItemInfoInstant then return GetItemInfoInstant(x) end
end
local function level() return UnitLevel and tonumber((UnitLevel("player"))) or 1 end

-- what the line under the gold buttons says while the tab searches or found nothing
function U.Status(slots)
    local b = B()
    local br = b._browse
    if not b.want.weapons then return "" end
    if br.state ~= "done" then
        return string.format("Looking at the gear... (search %d of %d)", math.min((br.step or 0) + 1, #(br.searches or { 1 })), #(br.searches or { 1 }))
    end
    local n, left = #b._candidates, 0
    for _, c in ipairs(b._candidates) do if c.state == "price" then left = left + 1 end end
    if left > 0 then return string.format("Checking the best offers %d/%d...", n - left, n) end
    if #slots == 0 then
        local lim = b.Limit()
        return lim > 0 and ("No upgrade on sale for up to " .. money(lim) .. " each") or "No upgrade on sale right now"
    end
    return ""
end

-- the slot groups without an upgrade, once everything is looked at
function U.Missing(slots)
    local b = B()
    if b._browse.state ~= "done" then return {} end
    for _, c in ipairs(b._candidates) do if c.state == "price" then return {} end end
    local have = {}
    for _, s in ipairs(slots) do have[s.group.key] = true end
    local out = {}
    for _, g in ipairs(b.GEAR_GROUPS) do if not have[g.key] then out[#out + 1] = g.label end end
    return out
end

-- the text in the bottom line of a tile
function U.TileText(c)
    local b = B()
    if c.bought then return "Bought" end
    if c.checking then return "Checking..." end
    if b.Fresh(c) then return "|cff40e060Buy|r " .. money(c.offer.buyout) end
    return "|cff40e060+" .. c.gain .. "|r  " .. money(c.offer.buyout)
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------
local ui
U._UI = function() return ui end

local function tooltip(self)
    local c = self.c
    if not (GameTooltip and c and c.offer and c.offer.link) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(c.offer.link)
    GameTooltip:AddLine(string.format("+%d score for your %s", c.gain or 0, string.lower(self.label or "slot")), 0.25, 0.88, 0.38)
    GameTooltip:AddLine("Left click: look at the offer again, then click once more to buy it", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Right click: never suggest it again", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function makeTile(parent)
    local b = B()
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(U.TILE_W, U.TILE_H)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t.bg = t:CreateTexture(nil, "BACKGROUND"); t.bg:SetAllPoints(); t.bg:SetColorTexture(0.11, 0.122, 0.153, 1)
    t.hl = t:CreateTexture(nil, "HIGHLIGHT"); t.hl:SetAllPoints(); t.hl:SetColorTexture(1, 1, 1, 0.06)
    t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetSize(30, 30); t.icon:SetPoint("LEFT", 4, 0)
    t.name = b._fs(t, "GameFontHighlightSmall"); t.name:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 5, -1); t.name:SetWidth(U.TILE_W - 42)
    if t.name.SetWordWrap then t.name:SetWordWrap(false) end
    t.price = b._fs(t, "GameFontNormalSmall", 0.95, 0.82, 0.48); t.price:SetPoint("BOTTOMLEFT", t.icon, "BOTTOMRIGHT", 5, 1)
    t.price:SetWidth(U.TILE_W - 42)
    if t.price.SetWordWrap then t.price:SetWordWrap(false) end
    t:SetScript("OnClick", function(self, button)
        if not self.c then return end
        if button == "RightButton" then B().Never(self.c.itemID) else B().BuyGear(self.c) end
    end)
    t:SetScript("OnEnter", tooltip)
    t:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return t
end

local function build(panel)
    local b = B()
    ui = CreateFrame("Frame", nil, panel)
    if panel.box then ui:SetFrameLevel(panel.box:GetFrameLevel() + 2) end
    -- the gold buttons stand where the other tabs have their mode switch
    ui.limits = {}
    local x = 16
    for i, c in ipairs(b.LIMITS) do
        local label = U.LIMIT_LABEL[c] or money(c)
        local btn = panel.Segment(label, c, x, function() B().SetLimit(c) end)
        local w = c == 0 and 78 or 50
        btn:SetSize(w, 24)
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(c == 0 and "No gold limit" or ("Up to " .. money(c) .. " per item"))
            GameTooltip:AddLine("Searches the gear, the weapons and the bags again. Never more than the gold you carry.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        ui.limits[i] = btn
        x = x + w + 4
    end
    ui.head = b._fs(ui, "GameFontHighlight", 0.79, 0.8, 0.84); ui.head:SetPoint("TOPLEFT", 16, -2); ui.head:SetWidth(348)
    ui.note = b._fs(ui, "GameFontDisableSmall"); ui.note:SetWidth(348)
    ui.offset = 0
    ui:EnableMouseWheel(true)
    ui:SetScript("OnMouseWheel", function(_, d)
        local n = #B().GearSlots()
        ui.offset = math.max(0, math.min(math.max(0, n - U.GROUPS_SHOWN), ui.offset - d))
        AH().Refresh()
    end)
    ui.groups = {}
    for i = 1, U.GROUPS_SHOWN do
        local g = {}
        g.title = b._fs(ui, "GameFontNormalSmall", 0.95, 0.82, 0.48); g.title:SetWidth(348)
        g.tiles = {}
        for k = 1, b.GEAR_PICKS do g.tiles[k] = makeTile(ui) end
        ui.groups[i] = g
    end
    ui.more = b._fs(ui, "GameFontDisableSmall")
    ui.missing = b._fs(ui, "GameFontDisableSmall"); ui.missing:SetWidth(348)
    ui.gTitle = b._fs(ui, "GameFontNormal", 0.95, 0.82, 0.48); ui.gTitle:SetText("Bags")
    ui.gNote = b._fs(ui, "GameFontDisableSmall")
    ui.gRows = {}
    for i = 1, b.BAG_ROWS do
        local r = b._makeRow(ui, 38)
        r:SetScript("OnClick", function(self, button)
            if not self.g then return end
            if button == "RightButton" then B().Never(self.g.itemID) else B().BuyBag(self.g) end
        end)
        r:SetScript("OnEnter", function(self)
            if GameTooltip and self.g then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.g.itemID); GameTooltip:Show() end
        end)
        ui.gRows[i] = r
    end
    ui.hint = b._fs(ui, "GameFontDisableSmall"); ui.hint:SetWidth(348)
end

-- the bag section (decision 265, moved here by decision 637); returns the new y
local function renderBags(y)
    local b = B()
    local bb = b._bagBrowse
    local G = b.Bags()
    ui.gTitle:ClearAllPoints(); ui.gTitle:SetPoint("TOPLEFT", 16, -(y + 4))
    y = y + 24
    local gText
    local pricing, n, left = false, #b._bagCands, 0
    for _, c in ipairs(b._bagCands) do if c.state == "price" then pricing = true; left = left + 1 end end
    local st = bb.stats or {}
    if not b.want.bags then gText = ""
    elseif bb.state == "loading" then gText = string.format("Loading %d bags...", st.unread or 0)
    elseif bb.state ~= "done" then gText = "Looking at the bags..."
    elseif pricing then gText = string.format("Checking prices %d/%d...", n - left, n)
    elseif #G == 0 then
        gText = "No bigger bag on sale right now"
        if (st.unread or 0) > 0 then gText = gText .. " (" .. st.unread .. " could not be read)" end
    elseif (b.bagsMore or 0) > 0 then gText = string.format("and %d more bag types", b.bagsMore) end
    local buying = b._buying()
    for i, r in ipairs(ui.gRows) do
        local g = G[i]
        r.g = g
        r:SetShown(g ~= nil)
        if g then
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 16, -y)
            local name, _, quality, _, _, _, _, _, _, icon = info(g.itemID)
            r.icon:SetTexture(icon or select(5, instant(g.itemID)))
            r.name:SetText(name or ("item " .. g.itemID)); r.name:SetTextColor(b._qColor(quality))
            local what = b.KindLabel(g.bagKind) or "bag"
            r.sub:SetText((g.replaces == 0 and (what .. " - an empty bag slot") or string.format("%s - instead of %d slots", what, g.replaces))
                .. (((g.boughtN or 0) > 0) and string.format(" (%d of %d bought)", g.boughtN, g.upgrades or 1) or ""))
            r.top:SetText("|cff40e060" .. g.slots .. " slots|r")
            r.bottom:SetText((buying and buying.row == g) and "Buying..." or (g.bought and "Bought") or ((g.checking or g.state == "price") and "Checking...")
                or (b.Fresh(g) and ("|cff40e060Click: buy|r " .. money0(b.Cost(g, 1)))) or money0(b.Cost(g, 1)))
            y = y + 40
        end
    end
    ui.gNote:ClearAllPoints(); ui.gNote:SetPoint("TOPLEFT", 16, -y)
    ui.gNote:SetText(gText or "")
    if gText and gText ~= "" then y = y + 18 end
    return y
end

-- draws the Upgrades tab below `top` and returns the height it needs
function U.Render(panel, top)
    if not ui then build(panel) end
    local b = B()
    ui:ClearAllPoints(); ui:SetPoint("TOPLEFT", 0, -top); ui:SetPoint("BOTTOMRIGHT")
    ui:Show()
    local lim = b.Limit()
    for i, btn in ipairs(ui.limits) do
        btn:Show()
        local on = b.LIMITS[i] == lim
        if on then btn.bg:SetColorTexture(0.89, 0.71, 0.29, 1); btn.text:SetTextColor(0.07, 0.07, 0.08)
        else btn.bg:SetColorTexture(0.2, 0.21, 0.25, 1); btn.text:SetTextColor(0.93, 0.93, 0.95) end
    end
    local SC = OMQ.Score
    local class = SC and SC.MyClass() or select(2, UnitClass("player"))
    local cname = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class or "?"
    ui.head:SetText(string.format("For your %s, level %d - you carry |cfff2d27a%s|r", cname, level(), money(GetMoney and GetMoney() or 0))
        .. (AH().Manual() and "  |cffff9933Paused - press Scan all to unpause|r" or ""))
    local y = 22
    local slots = b.GearSlots()
    local status = U.Status(slots)
    ui.note:ClearAllPoints(); ui.note:SetPoint("TOPLEFT", 16, -y)
    ui.note:SetText(status)
    if status ~= "" then y = y + 16 end
    ui.offset = math.min(ui.offset, math.max(0, #slots - U.GROUPS_SHOWN))
    for i, g in ipairs(ui.groups) do
        local s = slots[i + ui.offset]
        g.title:SetShown(s ~= nil)
        for k, t in ipairs(g.tiles) do
            local c = s and s.items[k]
            t.c, t.label = c, s and s.group.label
            t:SetShown(c ~= nil)
            if c then
                t:ClearAllPoints(); t:SetPoint("TOPLEFT", 16 + (k - 1) * (U.TILE_W + 3), -(y + 16))
                local name, _, quality, _, _, _, _, _, _, icon = info(c.offer.link)
                t.icon:SetTexture(icon or select(5, instant(c.itemID)))
                t.name:SetText(name or ("item " .. c.itemID)); t.name:SetTextColor(b._qColor(quality))
                t.price:SetText(U.TileText(c))
            end
        end
        if s then
            g.title:ClearAllPoints(); g.title:SetPoint("TOPLEFT", 16, -y)
            g.title:SetText(s.group.label)
            y = y + 16 + U.TILE_H + 6
        end
    end
    if #slots > U.GROUPS_SHOWN then
        ui.more:ClearAllPoints(); ui.more:SetPoint("TOPLEFT", 16, -y)
        ui.more:SetText(string.format("Mouse wheel: %d more slots", #slots - U.GROUPS_SHOWN)); ui.more:Show()
        y = y + 16
    else ui.more:Hide() end
    local miss = U.Missing(slots)
    if #miss > 0 and #slots > 0 then
        ui.missing:ClearAllPoints(); ui.missing:SetPoint("TOPLEFT", 16, -y)
        ui.missing:SetText("No upgrade: " .. table.concat(miss, ", ")); ui.missing:Show()
        y = y + (ui.missing.GetStringHeight and ui.missing:GetStringHeight() or 14) + 4
    else ui.missing:Hide() end
    y = renderBags(y)
    ui.hint:ClearAllPoints(); ui.hint:SetPoint("TOPLEFT", 16, -(y + 4))
    ui.hint:SetText("Left click: look at the offer, click again: buy - right click: never suggest it")
    return y + 24
end

function U.Hide()
    if not ui then return end
    ui:Hide()
    for _, btn in ipairs(ui.limits) do btn:Hide() end
end
