-- One More Quest: Profession Check (decision 535)
-- A window from the check bar (or /omq prof): what it costs to skill every crafting profession from 1 to 75,
-- 75 to 150, 150 to 225 and 225 to 300, with the materials at the prices OMQ knows.
-- The route is the Wowhead WoW Forever leveling guide of each profession (Data/ProfRoutes.lua, checked against the
-- Forever skill-up thresholds); the crafts are the average the guide counts with, no safety margin.
-- Only materials are counted, no trainer or recipe costs; a recipe from a vendor is marked in the tooltip.
-- Prices: the auction house scan (UI/CraftPrices.lua), a vendor price seen at a merchant, or the Forever vendor
-- price of the item (Data/ProfRoutes.lua) - the cheapest of them. A price that nobody knows is never guessed:
-- the cell shows the known sum and a grey "+?", and the tooltip names what is missing.
-- Intermediate products that the route makes itself (bolts, blasting powder, cured hides ...) count only through
-- their raw materials; what the route needs more of than it made is made from raw materials, too. Any other item
-- of the same profession without a price is made from its materials as well.
-- Step 2 (later): the auction house integration.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local PC = {}
OMQ.ProfCheck = PC

PC.BRACKETS = { { 1, 75 }, { 75, 150 }, { 150, 225 }, { 225, 300 } }
PC.DEPTH = 3                          -- how deep a missing price is replaced by the materials of the item

local function isSecret(v) return issecretvalue and issecretvalue(v) end

----------------------------------------------------------------------
-- Prices
----------------------------------------------------------------------
-- the cheapest price of one piece (copper) and where it comes from: "ah", "vendor"; nil = unknown
function PC.Price(itemID)
    local P = OMQ.Prices
    local best, from
    local function take(v, f)
        if type(v) == "number" and not isSecret(v) and v > 0 and (not best or v < best) then best, from = v, f end
    end
    if P then
        take((P.Auction(itemID)), "ah")
        take(P.Vendor(itemID), "vendor")
    end
    take((OMQ.ProfVendorPrices or {})[itemID], "vendor")
    return best, from
end

----------------------------------------------------------------------
-- The calculation
----------------------------------------------------------------------
local function bracketOf(from)
    for i, b in ipairs(PC.BRACKETS) do if from < b[2] then return i end end
    return #PC.BRACKETS
end

-- the recipe of the same profession that makes an item: { [item] = recipe }
local function makers(route)
    local R, out = OMQ.ProfRecipes or {}, {}
    for _, st in ipairs(route.steps) do
        local r = R[st[3]]
        if r and r[1] and r[1] > 0 then out[r[1]] = out[r[1]] or st[3] end
    end
    return out
end
local fallbackMakers
local function fallbackMaker(item)
    if not fallbackMakers then
        fallbackMakers = {}
        local ids = {}
        for id in pairs(OMQ.ProfRecipes or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local r = OMQ.ProfRecipes[id]
            if r[1] and r[1] > 0 and not fallbackMakers[r[1]] then fallbackMakers[r[1]] = id end
        end
    end
    return fallbackMakers[item]
end

-- one profession: { id, name, brackets = { { cost, missing = {item = n}, buy = {item = n}, price = {item = p},
-- steps = {...}, de = true }, ... }, total, complete }
function PC.Compute(route)
    local R = OMQ.ProfRecipes or {}
    local own = makers(route)
    local stock = {}
    local res = { id = route.id, name = route.name, brackets = {}, total = 0, complete = true }
    for i = 1, #PC.BRACKETS do
        res.brackets[i] = { cost = 0, missing = {}, buy = {}, price = {}, steps = {}, nMissing = 0 }
    end
    local need
    local function craft(b, recipe, n, depth)
        local r = R[recipe]
        if not r then return end
        for k = 1, #r[3], 2 do need(b, r[3][k], r[3][k + 1] * n, depth) end
        if r[1] and r[1] > 0 then stock[r[1]] = (stock[r[1]] or 0) + (r[2] or 1) * n end
    end
    need = function(b, item, amount, depth)
        local have = stock[item] or 0
        if have > 0 then
            local take = math.min(have, amount)
            stock[item] = have - take
            amount = amount - take
        end
        if amount <= 1e-6 then return end
        local mine = own[item]
        if mine and depth < PC.DEPTH then        -- the route makes it itself: from the raw materials
            local r = R[mine]
            craft(b, mine, amount / (r[2] or 1), depth + 1)
            stock[item] = (stock[item] or 0) - amount
            return
        end
        local p = PC.Price(item)
        if p then
            b.cost = b.cost + p * amount
            b.buy[item] = (b.buy[item] or 0) + amount
            b.price[item] = p
            return
        end
        local other = fallbackMaker(item)
        if other and depth < PC.DEPTH then       -- no price, but this profession can make it
            local r = R[other]
            craft(b, other, amount / (r[2] or 1), depth + 1)
            stock[item] = (stock[item] or 0) - amount
            return
        end
        b.buy[item] = (b.buy[item] or 0) + amount
        if not b.missing[item] then b.nMissing = b.nMissing + 1 end
        b.missing[item] = (b.missing[item] or 0) + amount
    end
    for _, st in ipairs(route.steps) do
        local b = res.brackets[bracketOf(st[1])]
        b.steps[#b.steps + 1] = st
        if st[5] == "D" then b.de = true
        else craft(b, st[3], st[4], 0) end
    end
    for _, b in ipairs(res.brackets) do
        res.total = res.total + b.cost
        if b.nMissing > 0 then res.complete = false end
    end
    return res
end

function PC.All()
    local out = {}
    for _, route in ipairs(OMQ.ProfRoutes or {}) do out[#out + 1] = PC.Compute(route) end
    return out
end

-- my professions: { [skill line id] = rank }, by skill line, else by the English or German name
local NAME_LINE = {
    alchemy = 171, alchemie = 171, blacksmithing = 164, schmiedekunst = 164, enchanting = 333, verzauberkunst = 333,
    engineering = 202, ingenieurskunst = 202, leatherworking = 165, lederverarbeitung = 165,
    tailoring = 197, schneiderei = 197, cooking = 185, kochkunst = 185, kochen = 185,
    ["first aid"] = 129, ["erste hilfe"] = 129,
}
PC.NAME_LINE = NAME_LINE
function PC.Mine()
    local out = {}
    if GetProfessions and GetProfessionInfo then
        for _, idx in pairs({ GetProfessions() }) do
            if idx then
                local ok, name, _, rank, _, _, _, line = pcall(GetProfessionInfo, idx)
                if ok and type(rank) == "number" and not isSecret(rank) then
                    local id = (type(line) == "number" and not isSecret(line) and line) or nil
                    id = id or (type(name) == "string" and NAME_LINE[name:lower()])
                    if id then out[id] = rank end
                end
            end
        end
        if next(out) then return out end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank = GetSkillLineInfo(i)
            local id = not header and type(name) == "string" and NAME_LINE[name:lower()]
            if id and type(rank) == "number" then out[id] = rank end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Names (from the game, in the client's language)
----------------------------------------------------------------------
function PC.ItemName(id)
    local n
    if C_Item and C_Item.GetItemNameByID then
        local ok, v = pcall(C_Item.GetItemNameByID, id)
        if ok and type(v) == "string" and v ~= "" then n = v end
    end
    if not n and GetItemInfo then
        local ok, v = pcall(GetItemInfo, id)
        if ok and type(v) == "string" and v ~= "" then n = v end
    end
    if not n and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return n or ("item " .. id)
end
function PC.RecipeName(spell)
    local n
    if C_Spell and C_Spell.GetSpellName then
        local ok, v = pcall(C_Spell.GetSpellName, spell)
        if ok and type(v) == "string" and v ~= "" then n = v end
    end
    if not n and GetSpellInfo then
        local ok, v = pcall(GetSpellInfo, spell)
        if ok and type(v) == "string" and v ~= "" then n = v end
    end
    return n or ("recipe " .. spell)
end
function PC.ProfName(route)
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, v = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, route.id)
        if ok and type(v) == "string" and v ~= "" then return v end
    end
    return route.name
end

local function money(c)
    local C = OMQ.CraftProfit
    if C and C.Money then return C.Money(c) end
    return math.floor(c + 0.5) .. "c"
end
PC.Money = money
-- the cell: the gold (rounded to silver) and a grey "+?" when prices are missing
function PC.CellText(b)
    if b.cost <= 0 and b.nMissing > 0 then return "|cff8a8f99?|r" end
    local c = b.cost >= 10000 and math.floor(b.cost / 100 + 0.5) * 100 or b.cost
    local t = money(c)
    if b.nMissing > 0 then t = t .. " |cff8a8f99+?|r" end
    return t
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local f, cells, rows = nil, {}, {}
local GOLD = { 0.89, 0.71, 0.29 }
local GOLD_LIGHT = { 0.95, 0.82, 0.48 }
local GREY = { 0.54, 0.56, 0.61 }
local NAME_W, COL_W, ROW_H = 150, 112, 30
local LEARN = { V = "recipe from a vendor", Q = "special trainer after a quest" }
local ICON = {
    [171] = "Interface\\Icons\\Trade_Alchemy", [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [333] = "Interface\\Icons\\Trade_Engraving", [202] = "Interface\\Icons\\Trade_Engineering",
    [165] = "Interface\\Icons\\Trade_LeatherWorking", [197] = "Interface\\Icons\\Trade_Tailoring",
    [185] = "Interface\\Icons\\INV_Misc_Food_15", [129] = "Interface\\Icons\\INV_Misc_Bandage_15",
}

local function text(parent, template, c, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end
local function edge(parent, c, inset)
    for i = 1, 4 do
        local e = parent:CreateTexture(nil, "BORDER")
        e:SetColorTexture(c[1], c[2], c[3], 1)
        if i == 1 then e:SetPoint("TOPLEFT", inset, -inset); e:SetPoint("TOPRIGHT", -inset, -inset); e:SetHeight(1)
        elseif i == 2 then e:SetPoint("BOTTOMLEFT", inset, inset); e:SetPoint("BOTTOMRIGHT", -inset, inset); e:SetHeight(1)
        elseif i == 3 then e:SetPoint("TOPLEFT", inset, -inset); e:SetPoint("BOTTOMLEFT", inset, inset); e:SetWidth(1)
        else e:SetPoint("TOPRIGHT", -inset, -inset); e:SetPoint("BOTTOMRIGHT", -inset, inset); e:SetWidth(1) end
    end
end

-- the tooltip of one cell: the steps, then what to buy with its price, then what has no price
function PC.FillTooltip(tt, res, i)
    local b = res.brackets[i]
    if not b then return end
    local br = PC.BRACKETS[i]
    tt:AddLine(string.format("%s %d-%d", res.label or res.name, br[1], br[2]), GOLD[1], GOLD[2], GOLD[3])
    for _, st in ipairs(b.steps) do
        if st[5] == "D" then
            tt:AddDoubleLine(string.format("%d-%d  Disenchant green items", st[1], st[2]), "no cost", 0.85, 0.85, 0.85, 0.6, 0.62, 0.66)
        else
            local note = LEARN[st[5]] and (" |cff8a8f99(" .. LEARN[st[5]] .. ")|r") or ""
            tt:AddDoubleLine(string.format("%d-%d  %s%s", st[1], st[2], PC.RecipeName(st[3]), note),
                "x" .. math.ceil(st[4] - 1e-6), 0.85, 0.85, 0.85, 1, 1, 1)
        end
    end
    local list = {}
    for item, n in pairs(b.buy) do list[#list + 1] = { item = item, n = n } end
    table.sort(list, function(a, c)
        local pa, pc = (b.price[a.item] or 0) * a.n, (b.price[c.item] or 0) * c.n
        if pa ~= pc then return pa > pc end
        return a.item < c.item
    end)
    if #list > 0 then
        tt:AddLine(" ")
        tt:AddLine("Materials", GOLD[1], GOLD[2], GOLD[3])
        for _, e in ipairs(list) do
            local n = math.ceil(e.n - 1e-6)
            local p = b.price[e.item]
            if p then
                tt:AddDoubleLine(string.format("%dx %s", n, PC.ItemName(e.item)), money(p * e.n), 0.85, 0.85, 0.85, 1, 1, 1)
            else
                tt:AddDoubleLine(string.format("%dx %s", n, PC.ItemName(e.item)), "no price", 0.85, 0.85, 0.85, 1, 0.35, 0.3)
            end
        end
    end
    if b.nMissing > 0 then
        tt:AddLine(" ")
        tt:AddLine(string.format("%d item%s without a price - not in the sum. Scan the auction house to fill them.",
            b.nMissing, b.nMissing == 1 and "" or "s"), 1, 0.55, 0.45, true)
    end
end

local function cellButton(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(COL_W - 4, ROW_H - 4)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0.1, 0.11, 0.14, 0.9)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints()
    c.hl:SetColorTexture(1, 1, 1, 0.08)
    c.text = text(c, "GameFontHighlightSmall", nil, "RIGHT")
    c.text:SetPoint("RIGHT", -6, 0)
    c:SetScript("OnEnter", function(self)
        if not (GameTooltip and self.res) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.col then PC.FillTooltip(GameTooltip, self.res, self.col)
        else
            GameTooltip:AddLine(self.res.label or self.res.name, GOLD[1], GOLD[2], GOLD[3])
            GameTooltip:AddDoubleLine("1-300, materials", money(self.res.total), 0.85, 0.85, 0.85, 1, 1, 1)
            if not self.res.complete then GameTooltip:AddLine("Some prices are missing - the real cost is higher.", 1, 0.55, 0.45, true) end
        end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return c
end

local function agoText(at)
    local s = math.max(0, ((time and time()) or at) - at)
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " days ago"
end
function PC.PriceLine()
    local P = OMQ.Prices
    local at = P and P.ScannedAt and P.ScannedAt()
    if not at then return "No auction house scan yet - open the auction house once, then the prices fill in." end
    return string.format("Auction prices: scan %s (%d items). Vendor items at the vendor price.", agoText(at), P.Count())
end

function PC.Refresh()
    if not f then return end
    local mine = PC.Mine()
    local all = PC.All()
    PC._last = all
    for r, res in ipairs(all) do
        local row = rows[r]
        res.label = PC.ProfName(res)
        local rank = mine[res.id]
        row.icon:SetTexture(ICON[res.id])
        row.name:SetText(res.label .. (rank and string.format(" |cffa9afba(%d)|r", rank) or ""))
        if rank then row.name:SetTextColor(GOLD_LIGHT[1], GOLD_LIGHT[2], GOLD_LIGHT[3]) else row.name:SetTextColor(0.85, 0.85, 0.85) end
        for i = 1, #PC.BRACKETS + 1 do
            local c = cells[r][i]
            c.res = res
            if i <= #PC.BRACKETS then
                c.col = i
                c.text:SetText(PC.CellText(res.brackets[i]))
                local br = PC.BRACKETS[i]
                local here = rank and rank >= br[1] and (rank < br[2] or (i == #PC.BRACKETS and rank <= br[2]))
                if here then c.bg:SetColorTexture(0.42, 0.33, 0.13, 0.9)
                elseif rank and rank >= br[2] then c.bg:SetColorTexture(0.08, 0.085, 0.1, 0.9)
                else c.bg:SetColorTexture(0.1, 0.11, 0.14, 0.9) end
            else
                c.col = false
                c.text:SetText(money(res.total >= 10000 and math.floor(res.total / 100 + 0.5) * 100 or res.total) ..
                    (res.complete and "" or " |cff8a8f99+?|r"))
                c.bg:SetColorTexture(0.14, 0.12, 0.08, 0.9)
            end
        end
    end
    f.prices:SetText(PC.PriceLine())
end

local function build()
    local n = #(OMQ.ProfRoutes or {})
    local width = 30 * 2 + NAME_W + (#PC.BRACKETS + 1) * COL_W
    f = CreateFrame("Frame", "OneMoreQuestProfCheck", UIParent)
    f:SetSize(width, 150 + n * ROW_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.075, 0.082, 0.11, 0.97)
    edge(f, { 0.63, 0.50, 0.21 }, 0)
    edge(f, { 0.29, 0.23, 0.10 }, 3)
    f.tag = text(f, "GameFontNormalSmall", { 0.72, 0.63, 0.42 })
    f.tag:SetPoint("TOPLEFT", 30, -18)
    f.tag:SetText("PROFESSION CHECK")
    f.head = text(f, "GameFontNormalLarge", GOLD_LIGHT)
    f.head:SetPoint("TOPLEFT", 30, -32)
    f.head:SetText("What it costs to skill a profession")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    local top = -68
    for i = 1, #PC.BRACKETS + 1 do
        local h = text(f, "GameFontNormalSmall", { 0.72, 0.63, 0.42 }, "RIGHT")
        h:SetPoint("TOPRIGHT", f, "TOPLEFT", 30 + NAME_W + i * COL_W - 10, top)
        h:SetText(i <= #PC.BRACKETS and string.format("%d-%d", PC.BRACKETS[i][1], PC.BRACKETS[i][2]) or "1-300")
    end
    for r = 1, n do
        local y = top - 16 - (r - 1) * ROW_H
        local row = {}
        row.icon = f:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("TOPLEFT", 30, y - 3)
        row.name = text(f, "GameFontHighlight", nil, "LEFT")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        rows[r] = row
        cells[r] = {}
        for i = 1, #PC.BRACKETS + 1 do
            local c = cellButton(f)
            c:SetPoint("TOPLEFT", f, "TOPLEFT", 30 + NAME_W + (i - 1) * COL_W, y)
            cells[r][i] = c
        end
    end
    f.prices = text(f, "GameFontDisableSmall", GREY, "LEFT")
    f.prices:SetPoint("BOTTOMLEFT", 30, 36)
    f.note = text(f, "GameFontDisableSmall", GREY, "LEFT")
    f.note:SetPoint("BOTTOMLEFT", 30, 20)
    f.note:SetText("Route: the Wowhead WoW Forever leveling guides. Average crafts, materials only (no trainer or recipe costs). Hover a cell for the details.")
    f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestProfCheck") end
end

function PC:Show()
    if not f then build() end
    PC.Refresh()
    f:Show()
end
function PC:Toggle()
    if f and f:IsShown() then f:Hide() else self:Show() end
end
function PC:Frame() return f end
function PC:Cell(r, i) return cells[r] and cells[r][i] end

OMQ:RegisterCommand("prof", function() PC:Toggle() end, "Profession Check: what each crafting profession costs to skill")
