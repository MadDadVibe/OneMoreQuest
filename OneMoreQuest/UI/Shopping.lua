-- One More Quest: Shopping lists (decision 551)
-- A shopping list is a list of items and how many of each to buy. Places in OMQ make one (the first: a click on a cell
-- of the Profession Check, UI/ProfCheck.lua); the Auction Helper shows them in its third tab, "Shopping".
-- In the tab the dad picks a list and sees what to buy. Every row: bought / wanted, the price per piece now and the
-- price the list was made with ("plan"). Items that are cheapest at a vendor stand below "Buy at a vendor" and are
-- never bought at the auction house.
-- The big button buys the next item with one click - the whole amount still missing, the most expensive item first -
-- and is clicked again for the next one. It skips an item that costs more than 1.5 times its plan right now; a left
-- click on that row buys it anyway. The bags are never counted: only what was bought through the list counts (a dad
-- sells what is left over).
-- The lists are kept per character until the dad deletes one (the X next to the list, any time); nothing is deleted
-- by itself. Making the list of the same place again replaces it.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local S = {}
OMQ.Shopping = S

S.OVER = 1.5               -- more than 1.5 times the plan: the big button skips it
S.ROWS = 10                -- lines shown at once (mouse wheel for more)

local GOLD = { 0.89, 0.71, 0.29 }
local function B() return OMQ.AuctionBuy end
local function AH() return OMQ.AuctionHelper end
local function money(c) return AH().Money(c) end
local function clock() return (time and time()) or 0 end

----------------------------------------------------------------------
-- The lists (per character, in the saved variables)
----------------------------------------------------------------------
local function store()
    OMQDB.shop = OMQDB.shop or {}
    local guid = UnitGUID and UnitGUID("player") or "?"
    OMQDB.shop[guid] = OMQDB.shop[guid] or { lists = {} }
    return OMQDB.shop[guid]
end
function S.Lists() return store().lists end
function S.Count() return #store().lists end
function S.Find(key)
    for i, l in ipairs(store().lists) do if l.key == key then return l, i end end
    return nil
end
function S.Has(key) return S.Find(key) ~= nil end
-- the list shown in the tab: the chosen one, else the newest
function S.Selected()
    local st = store()
    return (st.sel and S.Find(st.sel)) or st.lists[1]
end
function S.Select(key)
    store().sel = key
    if AH() and AH().Refresh then AH().Refresh(); AH().Pump() end
end
-- a new list: { key, title, source, items = { { itemID, n, plan, vendor } } }; a list with the same key is replaced.
-- The newest stands first and is chosen.
function S.Add(list)
    local st = store()
    local _, i = S.Find(list.key)
    if i then table.remove(st.lists, i) end
    local items = {}
    for _, it in ipairs(list.items or {}) do
        items[#items + 1] = { itemID = it.itemID, n = it.n, plan = it.plan, vendor = it.vendor, bought = 0 }
    end
    local l = { key = list.key, title = list.title, source = list.source, at = clock(), items = items }
    table.insert(st.lists, 1, l)
    st.sel = l.key
    if AH() and AH().open then AH().Refresh(); AH().Pump() end
    return l
end
function S.Delete(key)
    local st = store()
    local _, i = S.Find(key)
    if i then table.remove(st.lists, i) end
    if st.sel == key then st.sel = st.lists[1] and st.lists[1].key or nil end
    if S.menu then S.menu:Hide() end
    if AH() and AH().Refresh then AH().Refresh() end
end
-- everything of the auction house part bought (the vendor items do not count)
function S.Done(l)
    if not l then return false end
    for _, it in ipairs(l.items) do
        if not it.vendor and (it.bought or 0) < it.n then return false end
    end
    return true
end

----------------------------------------------------------------------
-- The rows of the chosen list (searched live like the Buy tab's stock rows)
----------------------------------------------------------------------
local byId = {}                -- one search row per item, shared by every list
local rows = {}                -- the auction house rows of the chosen list
S._byId, S._rows = byId, rows
local function rowFor(id)
    local r = byId[id]
    if not r then
        local A = C_AuctionHouse
        r = { itemID = id, key = "s" .. id, state = "price", anyKey = true, kind = "shop", shop = true,
              itemKey = (A and A.MakeItemKey and A.MakeItemKey(id)) or { itemID = id } }
        byId[id] = r
    end
    return r
end
function S.Rows()
    for i = #rows, 1, -1 do rows[i] = nil end
    local l = S.Selected()
    if not l then return rows end
    for _, it in ipairs(l.items) do
        if not it.vendor then
            local r = rowFor(it.itemID)
            r.item = it
            r.need = math.max(0, it.n - (it.bought or 0))
            rows[#rows + 1] = r
        end
    end
    return rows
end
-- a purchase of a row went through (from the Buy tab's purchase code)
function S.Bought(r, qty)
    local it = r and r.item
    if not it then return end
    it.bought = math.min(it.n, (it.bought or 0) + (qty or 0))
    r.need = math.max(0, it.n - it.bought)
end
-- the price per piece of what is still missing, as the offers show it now; nil = not known
function S.Unit(r)
    if not (r and r.state == "ok" and r.offers and #r.offers > 0) then return nil end
    local n = math.max(1, r.need or 1)
    local cost, got = B().Cost(r, n)
    if got <= 0 then return nil end
    return cost / got
end
-- costs more than 1.5 times the plan right now
function S.Over(r)
    local p, u = r and r.item and r.item.plan, S.Unit(r)
    return (p and u and u > p * S.OVER) and true or false
end
-- the item the big button buys next: missing, priced, on sale and not over the plan
function S.NextRow()
    for _, r in ipairs(S.Rows()) do
        if (r.need or 0) > 0 and r.state == "ok" and r.offers and #r.offers > 0 and not S.Over(r) then return r end
    end
    return nil
end
function S.Click(r)
    if not (r and (r.need or 0) > 0) then return false end
    return B().Buy(r, r.need)
end
function S.BuyNext() return S.Click(S.NextRow()) end

-- a fresh search at every visit
function S.Open()
    for _, r in pairs(byId) do r.state, r.live, r.offers, r.estimate = "price", nil, nil, nil end
    if S.menu then S.menu:Hide() end
end
function S.Pending()
    for _, r in ipairs(S.Rows()) do if r.state == "price" then return true end end
    return false
end
-- many prices with one request (the auction helper's batch)
function S.BatchRows()
    local out, tried = {}, AH()._tried or {}
    for _, r in ipairs(S.Rows()) do
        if r.state == "price" and not tried[r.key] and not r.live then out[#out + 1] = r end
    end
    return out
end
local function onSearch(r)
    r.offers = B().ReadOffers(r)
    r.checkedAt = GetTime()
    r.state = #r.offers > 0 and "ok" or "none"
end
-- one by one: what the batch did not answer
function S.NextQuery()
    for _, r in ipairs(S.Rows()) do
        if r.state == "price" then r.onResult = onSearch; return r end
    end
    return nil
end

----------------------------------------------------------------------
-- Drawing (inside the auction helper's panel)
----------------------------------------------------------------------
local ui
S._UI = function() return ui end
local function itemName(id)
    local name, quality, icon, _
    if C_Item and C_Item.GetItemInfo then name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
    elseif GetItemInfo then name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(id) end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    if not icon and C_Item and C_Item.GetItemInfoInstant then icon = select(5, C_Item.GetItemInfoInstant(id)) end
    return name or ("item " .. id), quality, icon
end

local function button(parent, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b.edge:SetColorTexture(0.45, 0.37, 0.18, 1)
    b.bg = b:CreateTexture(nil, "BORDER"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.08, 0.086, 0.11, 1)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.08)
    return b
end

local function build(panel)
    local fs = B()._fs
    ui = CreateFrame("Frame", nil, panel)
    if panel.box then ui:SetFrameLevel(panel.box:GetFrameLevel() + 2) end
    -- the list choice where the other tabs have their mode switch, and the X that deletes the list
    local dd = button(ui, 290, 26)
    dd:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -76)
    dd.text = fs(dd, "GameFontNormal", 0.95, 0.82, 0.48); dd.text:SetPoint("LEFT", 8, 0); dd.text:SetWidth(200)
    if dd.text.SetWordWrap then dd.text:SetWordWrap(false) end
    dd.more = fs(dd, "GameFontDisableSmall"); dd.more:SetPoint("RIGHT", -8, 0); dd.more:SetJustifyH("RIGHT")
    dd:SetScript("OnClick", function() if S.menu:IsShown() then S.menu:Hide() else S.ShowMenu() end end)
    ui.dd = dd
    local x = button(ui, 26, 26)
    x:SetPoint("LEFT", dd, "RIGHT", 6, 0)
    x.bg:SetColorTexture(0.2, 0.21, 0.25, 1)
    x.text = fs(x, "GameFontNormal", 0.93, 0.93, 0.95); x.text:SetPoint("CENTER"); x.text:SetText("X")
    x:SetScript("OnClick", function() local l = S.Selected(); if l then S.Delete(l.key) end end)
    x:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Delete this shopping list"); GameTooltip:Show()
    end)
    x:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    ui.x = x
    -- the menu of all lists
    local menu = CreateFrame("Frame", nil, ui)
    menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    menu:SetSize(290, 10)
    menu:SetFrameLevel(ui:GetFrameLevel() + 30)
    menu.bg = menu:CreateTexture(nil, "BACKGROUND"); menu.bg:SetAllPoints(); menu.bg:SetColorTexture(0.05, 0.055, 0.075, 0.98)
    menu.items = {}
    menu:Hide()
    S.menu = menu
    ui.head = fs(ui, "GameFontHighlight", 0.79, 0.8, 0.84); ui.head:SetPoint("TOPLEFT", 16, -2); ui.head:SetWidth(348)
    ui.vTitle = fs(ui, "GameFontNormal", 0.95, 0.82, 0.48); ui.vTitle:SetText("Buy at a vendor")
    ui.lines = {}
    for i = 1, S.ROWS do
        local r = B()._makeRow(ui, 38)
        r:SetScript("OnClick", function(self, btn)
            if btn == "LeftButton" and self.r then S.Click(self.r) end
        end)
        r:SetScript("OnEnter", function(self)
            if GameTooltip and self.id then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.id); GameTooltip:Show()
            end
        end)
        ui.lines[i] = r
    end
    ui.offset = 0
    ui:EnableMouseWheel(true)
    ui:SetScript("OnMouseWheel", function(_, d)
        ui.offset = math.max(0, math.min(math.max(0, (ui.total or 0) - S.ROWS), ui.offset - d))
        AH().Refresh()
    end)
    ui.more = fs(ui, "GameFontDisableSmall")
    local big = CreateFrame("Button", "OneMoreQuestAuctionShopNext", ui)
    big:SetSize(348, 44)
    big.bg = big:CreateTexture(nil, "BACKGROUND"); big.bg:SetAllPoints(); big.bg:SetColorTexture(0.165, 0.141, 0.086, 1)
    big.price = fs(big, "GameFontNormal", 0.95, 0.82, 0.48); big.price:SetPoint("RIGHT", -10, 0); big.price:SetJustifyH("RIGHT")
    big.title = fs(big, "GameFontNormalLarge", 0.95, 0.82, 0.48)
    big.title:SetPoint("LEFT", 10, 0); big.title:SetPoint("RIGHT", big.price, "LEFT", -8, 0)
    big.flash = big:CreateTexture(nil, "ARTWORK"); big.flash:SetAllPoints(); big.flash:SetColorTexture(0.25, 0.85, 0.35, 0.3); big.flash:Hide()
    big:SetScript("OnClick", function() S.BuyNext() end)
    ui.big = big
    ui.hint = fs(ui, "GameFontDisableSmall"); ui.hint:SetWidth(348)
    ui.empty = fs(ui, "GameFontHighlight", 0.79, 0.8, 0.84); ui.empty:SetWidth(348)
end

-- the menu: one line per list, the chosen one in gold
function S.ShowMenu()
    local menu = S.menu
    local fs = B()._fs
    local lists = S.Lists()
    local sel = S.Selected()
    for i, l in ipairs(lists) do
        local b = menu.items[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetSize(286, 20)
            b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.08)
            b.text = fs(b, "GameFontHighlight"); b.text:SetPoint("LEFT", 6, 0)
            b:SetScript("OnClick", function(self) menu:Hide(); S.Select(self.key) end)
            menu.items[i] = b
        end
        b.key = l.key
        b.text:SetText(l.title)
        if sel and l.key == sel.key then b.text:SetTextColor(0.95, 0.82, 0.48) else b.text:SetTextColor(0.93, 0.93, 0.95) end
        b:Show()
    end
    for i = #lists + 1, #menu.items do menu.items[i]:Hide() end
    menu:SetHeight(4 + #lists * 20)
    menu:SetShown(#lists > 0)
end

local function rowText(line, it, r)
    local name, quality, icon = itemName(it.itemID)
    line.id = it.itemID
    line.icon:SetTexture(icon)
    line.name:SetText(name); line.name:SetTextColor(B()._qColor(quality))
    local bought = it.bought or 0
    if it.vendor then
        line.r = nil
        line.sub:SetText("cheaper at a vendor")
        line.top:SetText("|cffe5e3dc" .. it.n .. "|r")
        line.bottom:SetText(it.plan and money(it.plan * it.n) or "")
        line.bg:SetAlpha(0.5)
        return
    end
    line.r = r
    local parts = {}
    local u = S.Unit(r)
    if u then parts[#parts + 1] = money(u) .. " each" end
    if it.plan then parts[#parts + 1] = "plan " .. money(it.plan) end
    line.sub:SetText(table.concat(parts, " - "))
    local full = bought >= it.n
    line.top:SetText(string.format("%s%d / %d|r", full and "|cff9fdc8a" or "|cffe5e3dc", bought, it.n))
    local buying = B()._buying()
    local right
    if full then right = "|cff9fdc8aBought|r"
    elseif buying and buying.row == r then right = "Buying..."
    elseif r.state == "price" then right = "..."
    elseif r.state == "none" then right = "not on sale"
    elseif S.Over(r) then right = "|cffff8c73Costs more than planned|r"
    else
        local cost, got = B().Cost(r, r.need)
        right = (got < r.need and string.format("Buy %d (all on sale) - ", got) or string.format("Buy %d - ", r.need)) .. money(cost)
    end
    line.bottom:SetText(right)
    line.bg:SetAlpha(full and 0.45 or 1)
end

-- draws the Shopping tab below `top` and returns the height it needs
function S.Render(panel, top)
    if not ui then build(panel) end
    ui:ClearAllPoints(); ui:SetPoint("TOPLEFT", 0, -top); ui:SetPoint("BOTTOMRIGHT")
    ui:Show()
    local l = S.Selected()
    local n = S.Count()
    ui.dd.text:SetText(l and l.title or "No shopping list")
    ui.dd.more:SetText(n > 0 and string.format("%d list%s", n, n == 1 and "" or "s") or "")
    ui.x:SetShown(l ~= nil)
    if S.menu:IsShown() then S.ShowMenu() end
    local y = 4
    if not l then
        for _, line in ipairs(ui.lines) do line:Hide() end
        ui.head:Hide(); ui.vTitle:Hide(); ui.more:Hide(); ui.big:Hide(); ui.hint:Hide()
        ui.empty:Show(); ui.empty:ClearAllPoints(); ui.empty:SetPoint("TOPLEFT", 16, -y)
        ui.empty:SetText("No shopping list yet. Click a cell of the Profession Check (check bar hammer or /omq prof) to make one.")
        return y + 50
    end
    ui.empty:Hide(); ui.head:Show(); ui.hint:Show(); ui.big:Show()
    ui.head:ClearAllPoints(); ui.head:SetPoint("TOPLEFT", 16, -y)
    ui.head:SetText(string.format("%d item%s - you carry |cfff2d27a%s|r", #l.items, #l.items == 1 and "" or "s", money(GetMoney and GetMoney() or 0))
        .. (AH().Manual() and "  |cffff9933Paused - press Scan all to unpause|r" or ""))
    y = y + 22
    -- everything in one scrolled list: the auction house rows, then the vendor title and the vendor rows
    local R = S.Rows()
    local entries = {}
    for _, r in ipairs(R) do entries[#entries + 1] = { it = r.item, r = r } end
    local vendor = {}
    for _, it in ipairs(l.items) do if it.vendor then vendor[#vendor + 1] = it end end
    if #vendor > 0 then
        entries[#entries + 1] = { title = true }
        for _, it in ipairs(vendor) do entries[#entries + 1] = { it = it } end
    end
    ui.total = #entries
    ui.offset = math.min(ui.offset, math.max(0, #entries - S.ROWS))
    ui.vTitle:Hide()
    local li = 0
    for i = ui.offset + 1, math.min(#entries, ui.offset + S.ROWS) do
        local e = entries[i]
        if e.title then
            ui.vTitle:ClearAllPoints(); ui.vTitle:SetPoint("TOPLEFT", 16, -(y + 4)); ui.vTitle:Show()
            y = y + 24
        else
            li = li + 1
            local line = ui.lines[li]
            line:ClearAllPoints(); line:SetPoint("TOPLEFT", 16, -y)
            rowText(line, e.it, e.r)
            line:Show()
            y = y + 40
        end
    end
    for i = li + 1, #ui.lines do ui.lines[i]:Hide(); ui.lines[i].r = nil; ui.lines[i].id = nil end
    if #entries > S.ROWS then
        ui.more:ClearAllPoints(); ui.more:SetPoint("TOPLEFT", 16, -y)
        ui.more:SetText(string.format("Mouse wheel: %d more", #entries - S.ROWS)); ui.more:Show()
        y = y + 16
    else ui.more:Hide() end
    -- the big button: how many clicks are left and what they cost
    local clicks, total = 0, 0
    for _, r in ipairs(R) do
        if (r.need or 0) > 0 and r.state == "ok" and r.offers and #r.offers > 0 and not S.Over(r) then
            clicks = clicks + 1
            total = total + (B().Cost(r, r.need))
        end
    end
    y = y + 6
    ui.big:ClearAllPoints(); ui.big:SetPoint("TOPLEFT", 16, -y)
    ui.big.flash:SetShown(not B()._buying() and AH().Flashing())
    local done = S.Done(l)
    ui.big.title:SetText((B()._buying() and "Buying...") or (done and "|cff9fdc8aEverything bought|r")
        or (clicks > 0 and string.format("Buy next - Click %d time%s", clicks, clicks == 1 and "" or "s"))
        or (S.Pending() and "Looking at the prices...") or "Nothing to buy right now")
    ui.big.price:SetText(clicks > 0 and money(total) or "")
    y = y + 48
    ui.hint:ClearAllPoints(); ui.hint:SetPoint("TOPLEFT", 16, -(y + 4))
    ui.hint:SetText(done and "Everything bought - X next to the list deletes it."
        or "Big button: next item, most expensive first, skips \"more than planned\" - left click on a row: buy it anyway")
    return y + 36
end

function S.Hide()
    if ui then ui:Hide() end
    if S.menu then S.menu:Hide() end
end
