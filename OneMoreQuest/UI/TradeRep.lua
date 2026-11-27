-- One More Quest: the cheapest way to the trading company reputation (decision 722)
-- An optional fifth tab "Rep" of the Auction Helper (off by default, switched on in the options). It shows the
-- standing with the own trading company (Azeroth Commerce Authority / Durotar Supply and Logistics), the Merchant's
-- Favor and a goal standing (Honored by default, a click on the goal button changes it). From the scanned prices it
-- ranks every Waylaid Crate by the cost of one Favor (crate + the cheapest bundle that fills it) and plans the way to
-- the goal: below Friendly the shipping label quest and Craftsman's Writs, from Friendly on Forged Delivery Receipts
-- (15 Favor each) on the cheapest empty crates, 50 reputation each. The big button makes a shopping list of the plan
-- (crates, bundles, empty crates; writs while below Friendly) for the Shopping tab, which buys it with its 1.5x price
-- limit. Craftsman's Writs in the bags (learned when a sealed writ is opened) get a line with the item they want: a
-- click makes a shopping list of it, or fills the game's search box when the item is not known yet.
-- A crate in the bags that can be filled with what the dad carries shows a card "Fill the supply crate" (a click
-- uses the crate), unless the bundle is worth clearly more on the auction house than the Favor it brings.
-- Only item, currency and faction IDs are used: German and English clients work the same.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local TR = {}
OMQ.TradeRep = TR
local function D() return OMQ.TradeRepData end

TR.ROWS = 6                -- crate rows shown in the tab
TR.WRIT_ROWS = 3           -- writ lines shown in the tab
TR.CARD_VALUE = 2          -- no fill card when the bundle is worth more than 2x the Favor at the cheapest price
TR.KEY = "traderep"        -- the shopping list's key

local function AH() return OMQ.AuctionHelper end
local function B() return OMQ.AuctionBuy end
local function S() return OMQ.Shopping end
local function money(c) return AH().Money(c) end

function TR.Enabled() return (OMQ.db and OMQ.db.options and OMQ.db.options.tradeRep == true) and true or false end
function TR.SetEnabled(v)
    OMQ.db.options.tradeRep = v and true or false
    if not v and AH() and AH().view == "rep" then AH().view = "sell" end
    if AH() and AH().Refresh then AH().Refresh() end
    if OMQ.Alerts and OMQ.Alerts.Evaluate then OMQ.Alerts:Evaluate() end
end

local function store()
    OMQDB.tradeRep = OMQDB.tradeRep or {}
    local t = OMQDB.tradeRep
    t.writItems = t.writItems or {}
    return t
end
TR.Store = store

----------------------------------------------------------------------
-- What the game says
----------------------------------------------------------------------
local function count(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
    if GetItemCount then return GetItemCount(id) or 0 end
    return 0
end
TR.Count = count
local function itemInfo(id)
    local name, link, quality, minLevel, icon, _
    if C_Item and C_Item.GetItemInfo then name, link, quality, _, minLevel, _, _, _, _, icon = C_Item.GetItemInfo(id) end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    if not icon and C_Item and C_Item.GetItemInfoInstant then icon = select(5, C_Item.GetItemInfoInstant(id)) end
    return name, quality, icon, minLevel, link
end
TR.ItemInfo = itemInfo
local function itemName(id) return (itemInfo(id)) or ("item " .. id) end
local function level() return UnitLevel and UnitLevel("player") or 60 end
-- the crate may be used at my level (the item's required level; unknown = yes)
function TR.Usable(id)
    local _, _, _, minLevel = itemInfo(id)
    return not (type(minLevel) == "number" and minLevel > level())
end
-- the lowest known price of one piece (auction house scan or a vendor), nil = not known
local function price(id)
    local P = OMQ.Prices
    return P and P.Cost and (P.Cost(id)) or nil
end
local function onSale(id)
    local P = OMQ.Prices
    if not (P and P.Auction) then return nil end
    local _, q = P.Auction(id)
    return q
end

function TR.FactionID()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return D().FACTIONS[f or ""]
end
-- { name, value (absolute reputation), standing (5 = Friendly ...) } or nil when the game does not know it yet
function TR.Standing()
    local id = TR.FactionID()
    if not id then return nil end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
        if ok and type(d) == "table" and d.name then
            return { name = d.name, value = tonumber(d.currentStanding) or 0, standing = d.reaction }
        end
    end
    if GetFactionInfoByID then
        local ok, name, _, standing, _, _, value = pcall(GetFactionInfoByID, id)
        if ok and name then return { name = name, value = tonumber(value) or 0, standing = standing } end
    end
    return nil
end
function TR.Favor()
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, c = pcall(C_CurrencyInfo.GetCurrencyInfo, D().CURRENCY)
        if ok and type(c) == "table" then return tonumber(c.quantity) or 0 end
    end
    return 0
end

----------------------------------------------------------------------
-- The goal
----------------------------------------------------------------------
function TR.Goal()
    local g = OMQ.db.options.tradeRepGoal
    for i, s in ipairs(D().STANDINGS) do if s[1] == g then return s, i end end
    return D().STANDINGS[2], 2                       -- Honored
end
function TR.NextGoal()
    local _, i = TR.Goal()
    local list = D().STANDINGS
    OMQ.db.options.tradeRepGoal = list[i % #list + 1][1]
    if AH() and AH().Refresh then AH().Refresh() end
end
-- reputation one receipt gives: 50, or what the last turn-in really gave (a reputation bonus, decision 722)
function TR.RepPer() return store().receiptRep or D().RECEIPT_REP end

----------------------------------------------------------------------
-- The crates by the price of one Favor
----------------------------------------------------------------------
-- every crate: { crate, id, favor, cratePrice, item, n, bundlePrice, cost (crate + bundle), per (cost / Favor),
-- cap (how many the auction house has at that price), usable }; priced and usable ones first, cheapest Favor first
function TR.Options()
    local out = {}
    for _, c in ipairs(D().CRATES) do
        local o = { crate = c, id = c.id, favor = c.favor, usable = TR.Usable(c.id), guess = c.guess }
        o.cratePrice = price(c.id)
        for _, b in ipairs(c.bundles) do
            local p = price(b[1])
            if p and (not o.bundlePrice or p * b[2] < o.bundlePrice) then o.item, o.n, o.bundlePrice = b[1], b[2], p * b[2] end
        end
        if o.cratePrice and o.bundlePrice then
            o.cost = o.cratePrice + o.bundlePrice
            o.per = o.cost / c.favor
            local qc, qb = onSale(c.id), onSale(o.item)
            o.cap = math.min(qc or 1000, qb and math.floor(qb / o.n) or 1000)
        end
        out[#out + 1] = o
    end
    table.sort(out, function(a, b)
        local ra, rb = (a.per and a.usable) and 0 or 1, (b.per and b.usable) and 0 or 1
        if ra ~= rb then return ra < rb end
        if a.per and b.per and a.per ~= b.per then return a.per < b.per end
        return a.id < b.id
    end)
    return out
end
-- the cheapest price of one Favor right now (nil = nothing priced)
function TR.BestPer()
    local o = TR.Options()[1]
    return o and o.usable and o.per or nil
end
-- the cheapest empty crate for a receipt: { id, price }
function TR.EmptyCrate()
    local best
    for _, c in ipairs(D().CRATES) do
        local p = price(c.id)
        if p and TR.Usable(c.id) and (not best or p < best.price) then best = { id = c.id, price = p } end
    end
    return best
end
-- the sealed writs: { id, rep, price, per (copper per reputation) }, cheapest reputation first
function TR.Writs()
    local out = {}
    for _, w in ipairs(D().WRITS) do
        local p = price(w.id)
        out[#out + 1] = { id = w.id, rep = w.rep, price = p, per = p and p / w.rep }
    end
    table.sort(out, function(a, b)
        if (a.per ~= nil) ~= (b.per ~= nil) then return a.per ~= nil end
        if a.per and b.per and a.per ~= b.per then return a.per < b.per end
        return a.id < b.id
    end)
    return out
end

----------------------------------------------------------------------
-- The plan to the goal
----------------------------------------------------------------------
-- { value, goal, receipts, favorNeed, fills = { { opt, n } }, empty = { id, n, price }, writ = { id, n, rep, price },
--   cost, short (Favor not covered by priced crates) }
function TR.Plan()
    local st = TR.Standing()
    local value = st and st.value or 0
    local goal = TR.Goal()
    local friendly = D().STANDINGS[1][3]
    local p = { value = value, goal = goal, known = st ~= nil, fills = {}, cost = 0, short = 0 }
    -- below Friendly: writs (the shipping label quest of the first crate counts on its own)
    local below = math.max(0, math.min(goal[3], friendly) - value)
    if below > 0 then
        local w = TR.Writs()[1]
        if w and w.price then
            p.writ = { id = w.id, rep = w.rep, price = w.price, n = math.ceil(below / w.rep) }
            p.cost = p.cost + p.writ.n * w.price
        end
    end
    -- from Friendly on: receipts
    local rep = math.max(0, goal[3] - math.max(value, friendly))
    local receipts = math.ceil(rep / TR.RepPer())
    receipts = math.max(0, receipts - count(D().RECEIPT) - count(D().NOTARIZED))
    p.receipts = receipts
    local favor = math.max(0, receipts * D().RECEIPT_FAVOR - TR.Favor())
    p.favorNeed = favor
    for _, o in ipairs(TR.Options()) do
        if favor <= 0 then break end
        if o.per and o.usable and o.cap > 0 then
            local n = math.min(o.cap, math.ceil(favor / o.favor))
            p.fills[#p.fills + 1] = { opt = o, n = n }
            favor = favor - n * o.favor
            p.cost = p.cost + n * o.cost
        end
    end
    p.short = math.max(0, favor)
    if receipts > 0 then
        local e = TR.EmptyCrate()
        if e then
            p.empty = { id = e.id, price = e.price, n = receipts }
            p.cost = p.cost + receipts * e.price
        end
    end
    return p
end

-- the plan as a shopping list for the Shopping tab
function TR.ShoppingList(p)
    p = p or TR.Plan()
    local items, at = {}, {}
    local function add(id, n, plan)
        if n <= 0 then return end
        local it = at[id]
        if not it then it = { itemID = id, n = 0, plan = plan }; at[id] = it; items[#items + 1] = it end
        it.n = it.n + n
    end
    for _, f in ipairs(p.fills) do
        add(f.opt.id, f.n, f.opt.cratePrice)
        add(f.opt.item, f.n * f.opt.n, f.opt.bundlePrice / f.opt.n)
    end
    if p.empty then add(p.empty.id, p.empty.n, p.empty.price) end
    if p.writ then add(p.writ.id, p.writ.n, p.writ.price) end
    table.sort(items, function(a, b)
        local va, vb = (a.plan or 0) * a.n, (b.plan or 0) * b.n
        if va ~= vb then return va > vb end
        return a.itemID < b.itemID
    end)
    return { key = TR.KEY, title = "Rep: " .. p.goal[2], source = "traderep", items = items }
end
function TR.MakeList()
    local l = TR.ShoppingList()
    if #l.items == 0 then TR.note = "Nothing to buy - the goal is reached or nothing is priced yet"; return nil end
    local made = S().Add(l)
    TR.note = nil
    if AH() and AH().SetView then AH().SetView("shop") end
    return made
end

----------------------------------------------------------------------
-- Craftsman's Writs in the bags (learned: the item that came when a sealed writ went)
----------------------------------------------------------------------
local function bagItems()
    local seen = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return seen end
    for bag = 0, (OMQ.LastBag and OMQ.LastBag() or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then seen[info.itemID] = true end
        end
    end
    return seen
end
local lastBags, lastSealed
local function sealedCount()
    local n = 0
    for _, w in ipairs(D().WRITS) do n = n + count(w.id) end
    return n
end
function TR.OnBags()
    local now, sealed = bagItems(), sealedCount()
    if lastBags and lastSealed and sealed < lastSealed then
        local writs = store().writItems
        local sealedIds = {}
        for _, w in ipairs(D().WRITS) do sealedIds[w.id] = true end
        for id in pairs(now) do
            if not lastBags[id] and not sealedIds[id] then writs[id] = true end
        end
    end
    lastBags, lastSealed = now, sealed
end
-- the wanted item of a writ: the part of its name after the colon ("Craftsman's Writ: Azure Silk Hood")
function TR.Wanted(name)
    if type(name) ~= "string" then return nil end
    local w = name:match("^[^:]+:%s*(.+)$")
    return w or name
end
-- the writs in the bags: { id, name, wanted, wantedID (nil = not known to the client yet) }
function TR.WritsInBags()
    local out = {}
    for id in pairs(store().writItems) do
        if count(id) > 0 then
            local name = itemInfo(id)
            local wanted = TR.Wanted(name)
            local wid
            if wanted and C_Item and C_Item.GetItemInfo then
                local _, link = C_Item.GetItemInfo(wanted)
                wid = link and tonumber(tostring(link):match("item:(%d+)"))
            end
            out[#out + 1] = { id = id, name = name, wanted = wanted, wantedID = wid }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end
-- a click on a writ line: a shopping list of the wanted item, or the game's search for its name
function TR.WritClick(w)
    if not w then return false end
    if w.wantedID then
        S().Add({ key = "writ:" .. w.wantedID, title = "Writ: " .. (w.wanted or itemName(w.wantedID)), source = "traderep",
                  items = { { itemID = w.wantedID, n = 1, plan = price(w.wantedID) } } })
        if AH() and AH().SetView then AH().SetView("shop") end
        return "list"
    end
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    if bar and bar.SearchBox and w.wanted then
        pcall(bar.SearchBox.SetText, bar.SearchBox, w.wanted)
        if bar.StartSearch then pcall(bar.StartSearch, bar) end
        return "search"
    end
    return false
end

----------------------------------------------------------------------
-- The reputation one receipt really gives (the reputation bonus): a notarized container went, the bar went up
----------------------------------------------------------------------
local lastValue, lastNotarized
function TR.OnFaction()
    local st = TR.Standing()
    local n = count(D().NOTARIZED)
    if st and lastValue and lastNotarized and n == lastNotarized - 1 then
        local gain = st.value - lastValue
        if gain >= D().RECEIPT_REP and gain <= D().RECEIPT_REP * 2 then store().receiptRep = gain end
    end
    lastValue, lastNotarized = st and st.value, n
end

----------------------------------------------------------------------
-- The fill card
----------------------------------------------------------------------
-- crates in the bags that the bags can fill: { crate, item, n, value }
function TR.Fillable()
    local out = {}
    local best = TR.BestPer()
    for _, c in ipairs(D().CRATES) do
        if count(c.id) > 0 and TR.Usable(c.id) then
            local pick
            for _, b in ipairs(c.bundles) do
                if count(b[1]) >= b[2] then
                    local v = (price(b[1]) or 0) * b[2]
                    if not pick or v < pick.value then pick = { crate = c, item = b[1], n = b[2], value = v } end
                end
            end
            if pick and not (best and pick.value > c.favor * best * TR.CARD_VALUE) then out[#out + 1] = pick end
        end
    end
    return out
end

if OMQ.Alerts then
    OMQ.Alerts:Register({ id = "traderep", name = "Fill a supply crate with what you carry (trading company)",
        check = function()
            if not TR.Enabled() then return nil end
            local out = {}
            for _, f in ipairs(TR.Fillable()) do
                local _, _, icon = itemInfo(f.crate.id)
                out[#out + 1] = {
                    key = "traderep:" .. f.crate.id,
                    text = "Fill the supply crate", title = "Fill the supply crate", tag = "CRATE",
                    sub = string.format("%dx %s - %d Favor", f.n, itemName(f.item), f.crate.favor),
                    icon = icon or "Interface\\Icons\\INV_Crate_01", color = { 0.89, 0.71, 0.29 },
                    useItem = "item:" .. f.crate.id,
                }
            end
            return out
        end })
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
local ui
TR._UI = function() return ui end
local function button(parent, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b.edge:SetColorTexture(0.45, 0.37, 0.18, 1)
    b.bg = b:CreateTexture(nil, "BORDER"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.08, 0.086, 0.11, 1)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.08)
    return b
end
local function tip(self, lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for _, l in ipairs(lines) do GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
end

local function build(panel)
    local fs = B()._fs
    ui = CreateFrame("Frame", nil, panel)
    if panel.box then ui:SetFrameLevel(panel.box:GetFrameLevel() + 2) end
    local goal = button(ui, 170, 26)
    goal:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -76)
    goal.text = fs(goal, "GameFontNormal", 0.95, 0.82, 0.48); goal.text:SetPoint("CENTER")
    goal:SetScript("OnClick", function() TR.NextGoal() end)
    goal:SetScript("OnEnter", function(self) tip(self, { "Click: the next goal standing" }) end)
    goal:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    ui.goal = goal
    ui.favor = fs(ui, "GameFontHighlight", 0.79, 0.8, 0.84); ui.favor:SetPoint("LEFT", goal, "RIGHT", 12, 0)
    ui.head = fs(ui, "GameFontHighlight", 0.79, 0.8, 0.84); ui.head:SetWidth(348)
    ui.plan = fs(ui, "GameFontHighlightSmall", 0.79, 0.8, 0.84); ui.plan:SetWidth(348)
    ui.lines = {}
    for i = 1, TR.ROWS do
        local r = B()._makeRow(ui, 34)
        r:SetScript("OnEnter", function(self)
            if not (GameTooltip and self.o) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.o.id)
            if self.o.guess then GameTooltip:AddLine("OMQ: the Favor of this crate is not confirmed yet", 1, 0.6, 0.4, true) end
            GameTooltip:Show()
        end)
        ui.lines[i] = r
    end
    ui.writs = fs(ui, "GameFontHighlightSmall", 0.79, 0.8, 0.84); ui.writs:SetWidth(348)
    ui.wlines = {}
    for i = 1, TR.WRIT_ROWS do
        local w = button(ui, 348, 20)
        w.text = fs(w, "GameFontHighlightSmall"); w.text:SetPoint("LEFT", 6, 0); w.text:SetWidth(336)
        if w.text.SetWordWrap then w.text:SetWordWrap(false) end
        w:SetScript("OnClick", function(self) TR.WritClick(self.w) end)
        w:SetScript("OnEnter", function(self)
            if self.w then tip(self, { self.w.wantedID and "Click: shopping list of the wanted item"
                or "Click: search the auction house for the wanted item" }) end
        end)
        w:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        ui.wlines[i] = w
    end
    local big = CreateFrame("Button", "OneMoreQuestAuctionRepList", ui)
    big:SetSize(348, 40)
    big.bg = big:CreateTexture(nil, "BACKGROUND"); big.bg:SetAllPoints(); big.bg:SetColorTexture(0.165, 0.141, 0.086, 1)
    big.price = fs(big, "GameFontNormal", 0.95, 0.82, 0.48); big.price:SetPoint("RIGHT", -10, 0); big.price:SetJustifyH("RIGHT")
    big.title = fs(big, "GameFontNormalLarge", 0.95, 0.82, 0.48); big.title:SetPoint("LEFT", 10, 0)
    big:SetScript("OnClick", function() TR.MakeList(); if AH() and AH().Refresh then AH().Refresh() end end)
    ui.big = big
    ui.hint = fs(ui, "GameFontDisableSmall"); ui.hint:SetWidth(348)
end

local function perText(per) return per and (money(math.floor(per + 0.5)) .. " / Favor") or "no price" end

-- draws the Rep tab below `top` and returns the height it needs
function TR.Render(panel, top)
    if not ui then build(panel) end
    ui:ClearAllPoints(); ui:SetPoint("TOPLEFT", 0, -top); ui:SetPoint("BOTTOMRIGHT")
    ui:Show()
    local p = TR.Plan()
    ui.goal.text:SetText("Goal: " .. p.goal[2])
    ui.favor:SetText(string.format("Merchant's Favor: |cfff2d27a%d|r", TR.Favor()))
    local st = TR.Standing()
    local y = 4
    ui.head:ClearAllPoints(); ui.head:SetPoint("TOPLEFT", 16, -y)
    if st then
        local name = "Neutral"
        for _, s in ipairs(D().STANDINGS) do if st.value >= s[3] then name = s[2] end end
        ui.head:SetText(string.format("%s: |cfff2d27a%s|r - %d / %d reputation", st.name, name, st.value, p.goal[3]))
    else
        ui.head:SetText("Trading company not met yet - fill and hand in a first crate at its camp")
    end
    y = y + 20
    local parts = {}
    if p.writ then parts[#parts + 1] = string.format("until Friendly: %d writs (or the first crate's label quest, %d)", p.writ.n, D().LABEL_REP) end
    if p.receipts > 0 then
        parts[#parts + 1] = string.format("%d receipts (%d rep each) = %d Favor still to earn", p.receipts, TR.RepPer(), p.favorNeed)
    elseif not p.writ then parts[#parts + 1] = "|cff9fdc8aGoal reached|r" end
    if p.short > 0 then parts[#parts + 1] = string.format("|cffff8c73%d Favor not on sale right now|r", p.short) end
    ui.plan:ClearAllPoints(); ui.plan:SetPoint("TOPLEFT", 16, -y)
    ui.plan:SetText(table.concat(parts, " - "))
    y = y + 18 + ((ui.plan.GetStringHeight and tonumber((ui.plan:GetStringHeight())) or 12) > 14 and 12 or 0)
    local inPlan = {}
    for _, f in ipairs(p.fills) do inPlan[f.opt.id] = f.n end
    local opts = TR.Options()
    for i, line in ipairs(ui.lines) do
        local o = opts[i]
        line.o = o
        if o then
            local name, quality, icon = itemInfo(o.id)
            line.icon:SetTexture(icon)
            line.name:SetText(name or ("item " .. o.id)); line.name:SetTextColor(B()._qColor(quality))
            line.sub:SetText(o.item and string.format("%dx %s - %d Favor%s", o.n, itemName(o.item), o.favor, o.guess and " (?)" or "")
                or "no bundle priced yet")
            line.top:SetText(o.usable and perText(o.per) or "|cff9aa0aaabove your level|r")
            line.bottom:SetText(inPlan[o.id] and string.format("plan %dx - %s", inPlan[o.id], money(inPlan[o.id] * o.cost))
                or (o.cost and money(o.cost) or ""))
            line.bg:SetAlpha((o.per and o.usable) and 1 or 0.45)
            line:ClearAllPoints(); line:SetPoint("TOPLEFT", 16, -y)
            line:Show()
            y = y + 36
        else line:Hide() end
    end
    -- the sealed writs and the writs in the bags
    local wp = {}
    for _, w in ipairs(TR.Writs()) do
        wp[#wp + 1] = string.format("%d rep %s", w.rep, w.price and money(w.price) or "?")
    end
    ui.writs:ClearAllPoints(); ui.writs:SetPoint("TOPLEFT", 16, -(y + 2))
    ui.writs:SetText("Sealed writs (once a day each, plus the wanted item): " .. table.concat(wp, ", "))
    y = y + 34
    local bag = TR.WritsInBags()
    for i, w in ipairs(ui.wlines) do
        local x = bag[i]
        w.w = x
        if x then
            w.text:SetText("Writ in your bags: |cfff2d27a" .. (x.wanted or "?") .. "|r" .. (x.wantedID and " - click: shopping list" or " - click: search"))
            w:ClearAllPoints(); w:SetPoint("TOPLEFT", 16, -y)
            w:Show()
            y = y + 22
        else w:Hide() end
    end
    y = y + 4
    ui.big:ClearAllPoints(); ui.big:SetPoint("TOPLEFT", 16, -y)
    local any = #p.fills > 0 or p.empty ~= nil or p.writ ~= nil
    ui.big.title:SetText(any and "Make shopping list" or "Nothing to buy")
    ui.big.price:SetText(any and money(math.floor(p.cost + 0.5)) or "")
    y = y + 44
    ui.hint:ClearAllPoints(); ui.hint:SetPoint("TOPLEFT", 16, -(y + 2))
    ui.hint:SetText(TR.note or "From Friendly on: Forged Delivery Receipt (15 Favor) on any empty crate = 50 reputation. Prices from the last scan.")
    return y + 30
end
function TR.Hide() if ui then ui:Hide() end end

----------------------------------------------------------------------
-- Events and the command
----------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "UPDATE_FACTION" }) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event)
    if not TR.Enabled() then return end
    local ok, err = pcall(function()
        if event == "BAG_UPDATE_DELAYED" then TR.OnBags() end
        TR.OnFaction()
    end)
    if not ok then OMQ:Error("traderep", err) end
end)

OMQ:RegisterCommand("rep", function(arg)
    local st, p = TR.Standing(), TR.Plan()
    OMQ:Print(string.format("trading company %s: %s, value %s, Favor %d, rep per receipt %d%s",
        tostring(TR.FactionID()), st and st.name or "not known", st and st.value or "?", TR.Favor(), TR.RepPer(),
        TR.Enabled() and "" or " (Rep tab off in the options)"))
    print(string.format("  goal %s: receipts %d, Favor to earn %d, plan %s", p.goal[2], p.receipts, p.favorNeed, money(math.floor(p.cost + 0.5))))
    for i, o in ipairs(TR.Options()) do
        if i > 5 then break end
        print(string.format("  %d %s: %s%s", o.id, itemName(o.id), perText(o.per), o.usable and "" or " (above your level)"))
    end
    if arg == "probe" then
        for _, c in ipairs(D().CRATES) do
            if count(c.id) > 0 then
                local _, _, _, minLevel = itemInfo(c.id)
                print(string.format("  in bags: %d %s x%d, required level %s", c.id, itemName(c.id), count(c.id), tostring(minLevel)))
            end
        end
        for id in pairs(store().writItems) do print(string.format("  writ item %d %s x%d", id, itemName(id), count(id))) end
    end
end, "Trading company reputation: standing, Favor and the cheapest plan (/omq rep probe: crates and writs in the bags)")
