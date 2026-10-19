-- One More Quest: Vendor Helper (decision 292)
-- Opens next to the vendor window: the items in my bags I should sell there.
--   Grey items (junk).
--   Gear that is not bound (any quality): my last auction house scan found it not worth posting.
--   Anything not bound that came back unsold twice in a row (gear, trade goods, ... - decision 300).
--   White items: my last auction house scan found them not worth more than the vendor price.
--   Bound gear: worse than what I wear by the item score, or gear my class cannot use at all.
--   Old food and drink: a lower level than the best plain food / water I carry (decision 299).
--   Profession tools of a profession I do not have (decision 299).
--   Soulbound recipes of a profession I do not have (decision 310).
-- Never offered: quest items, ammo, tools of my professions, the drinks and class supplies of the Group
-- Check, consumables of my buy list, an upgrade for me, items of an equipment
-- set, items without a vendor price, and what I marked "keep" with a right click.
-- A click on a row sells that item; "Sell all" sells the whole list. A right click on the header
-- closes the helper until the next vendor visit.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local V = {}
OMQ.Vendor = V

V.ROWS = 10
local GOLD = { 0.89, 0.71, 0.29 }
local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function money(c) return OMQ.AuctionHelper and OMQ.AuctionHelper.Money(c) or tostring(c) end

local function db()
    OMQDB.vendor = OMQDB.vendor or {}
    OMQDB.vendor.keep = OMQDB.vendor.keep or {}           -- item ID -> true: never offered again
    return OMQDB.vendor
end
function V.Enabled()
    local o = OMQ.db and OMQ.db.options
    return o and o.vendorHelper ~= false and OMQ:Master("vendor")
end

local function instant(id)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end
local function info(x)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(x) end
    if GetItemInfo then return GetItemInfo(x) end
end
local function level() return UnitLevel and tonumber((UnitLevel("player"))) or 1 end

-- the items of my equipment sets: never sold (another spec's gear)
local function setItems()
    local out = {}
    local E = C_EquipmentSet
    if not (E and E.GetEquipmentSetIDs and E.GetItemIDs) then return out end
    local ok, ids = pcall(E.GetEquipmentSetIDs)
    if not ok or type(ids) ~= "table" then return out end
    for _, sid in ipairs(ids) do
        local ok2, items = pcall(E.GetItemIDs, sid)
        if ok2 and type(items) == "table" then
            for _, id in pairs(items) do if type(id) == "number" and id > 0 then out[id] = true end end
        end
    end
    return out
end

local NO_GEAR = { INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true, INVTYPE_BODY = true,
                  INVTYPE_AMMO = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true }
local function isGear(equipLoc)
    if not equipLoc or equipLoc == "" or NO_GEAR[equipLoc] then return false end
    local S = OMQ.Compare and OMQ.Compare.SLOTS
    return S and S[equipLoc] and true or false
end

-- food and drink (decision 299): plain food and water (not buff food) of a lower level than the best of
-- the same kind I carry and can use are old. The kind comes from the item's spell, compared with the
-- game's own "Food" and "Drink" spells in the client's language; "Refreshment" (both) is left alone.
V.FOOD_SPELL, V.DRINK_SPELL = 433, 430
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id); if ok and type(n) == "string" then return n end end
    if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok and type(n) == "string" then return n end end
end
function V.FoodKind(id)
    local _, _, _, _, _, classID, subID = instant(id)
    if classID ~= 0 or subID ~= 5 then return nil end
    if OMQ.BuyKind and OMQ.BuyKind(id) then return nil end                   -- buff food: the buy list's business
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not fn then return nil end
    local ok, sname = pcall(fn, id)
    if not ok or type(sname) ~= "string" or isSecret(sname) then return nil end
    if sname == spellName(V.FOOD_SPELL) then return "food" end
    if sname == spellName(V.DRINK_SPELL) then return "drink" end
    return nil
end
-- the best level of each kind in my bags that I can use now
function V.BestFood()
    local best = {}
    local C = C_Container
    if not (C and C.GetContainerNumSlots) then return best end
    local lvl = level()
    for bag = 0, OMQ.LastBag() do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local it = C.GetContainerItemInfo(bag, slot)
            local kind = it and it.itemID and V.FoodKind(it.itemID)
            if kind then
                local need = select(5, info(it.itemID)) or 1
                if need <= lvl and need > (best[kind] or 0) then best[kind] = need end
            end
        end
    end
    return best
end

-- profession tools (decision 299): kept while I have one of their professions, else sold.
-- Thieves' Tools belong to rogues, not to a profession: never sold.
V.TOOL_PROFS = { [6219] = { "Engineering" }, [10498] = { "Engineering" }, [9149] = { "Alchemy" } }
function V.ToolProfs(id)
    local out = {}
    for _, p in ipairs(V.TOOL_PROFS[id] or {}) do out[#out + 1] = p end
    local M = OMQ.Alerts
    for prof, tools in pairs(M and M.TOOLS or {}) do
        for _, t in ipairs(tools) do
            local hit = t.item == id
            for _, a in ipairs(t.also or {}) do if a == id then hit = true end end
            if hit then out[#out + 1] = prof end
        end
    end
    return out
end
-- recipe subclass -> profession key (decision 310); books (0) and unknown ones are not judged
V.RECIPE_PROF = { [1] = "Leatherworking", [2] = "Tailoring", [3] = "Engineering", [4] = "Blacksmithing", [5] = "Cooking",
                  [6] = "Alchemy", [7] = "First Aid", [8] = "Enchanting", [9] = "Fishing" }

-- my professions by key, or nil when the game does not tell
function V.MyProfs()
    local M = OMQ.Alerts
    local lines = M and M.ProfessionLines and M.ProfessionLines()
    if not lines then return nil end
    local out = {}
    for _, l in ipairs(lines) do if l.key then out[l.key] = true end end
    return out
end

-- why an item should go to the vendor, or nil (decision 292)
-- it: the bag slot's info (C_Container.GetContainerItemInfo); extra: { vendor, equipLoc, classID, link }
-- ctx: { sets = items of my equipment sets, food = V.BestFood(), profs = V.MyProfs() }
function V.Reason(it, extra, ctx)
    ctx = ctx or {}
    local sets = ctx.sets
    local id = it.itemID
    if not id or isSecret(it.quality) then return nil end
    local q = it.quality or 1
    local vendor = extra.vendor or 0
    if vendor <= 0 or it.hasNoValue then return nil end
    if db().keep[id] then return nil end
    local classID, equipLoc, link = extra.classID, extra.equipLoc, extra.link
    if classID == 12 or classID == 6 then return nil end                     -- quest items, ammo
    local AH = OMQ.AuctionHelper
    if AH and AH.IsTool and AH.IsTool(id) then
        local profs = V.ToolProfs(id)
        if #profs == 0 or not ctx.profs then return nil end
        for _, p in ipairs(profs) do if ctx.profs[p] then return nil end end
        return "tool", "tool of a profession you do not have (" .. table.concat(profs, ", ") .. ")"
    end
    -- food and drink: only old ones, never because of the auction house (decision 299)
    local kind = V.FoodKind(id)
    if kind then
        local best = ctx.food and ctx.food[kind]
        local need = select(5, info(link or id)) or 1
        if best and need < best then return "old", "old " .. kind .. " - you carry better" end
        return nil
    end
    if OMQ.Ready and OMQ.Ready.KEEP and OMQ.Ready.KEEP[id] then return nil end
    local B = OMQ.AuctionBuy
    if B and B.TargetFor and B.TargetFor(id) then return nil end             -- my consumables
    if B and OMQ.BuyKind and OMQ.BuyKind(id) then return nil end
    if (sets or {})[id] then return nil end
    if q == 0 then return "junk", "grey item" end
    local gear = isGear(equipLoc)
    local ah = OMQDB and OMQDB.ah or {}
    if not it.isBound then
        if gear and AH and AH.UpgradeForMe and AH.UpgradeForMe(link, equipLoc) then return nil end
        local worth = ah.worth and ah.worth[id]
        local fails = ah.fails and ah.fails[id] or 0
        -- unsold twice in a row: gear and everything else, e.g. trade goods in the reagent bag (decision 300)
        if fails >= ((AH and AH.UNSOLD_LIMIT) or 2) then return "unsold", "came back unsold twice" end
        if gear then
            if worth == false then return "low", "not worth the auction house" end
            return nil
        end
        if q == 1 and worth == false then return "low", "no more at the auction house than here" end
        return nil
    end
    -- bound recipes of a profession I do not have (decision 310); unknown professions: kept
    if classID == 9 then
        local prof = V.RECIPE_PROF[select(7, instant(id)) or -1]
        if prof and ctx.profs and not ctx.profs[prof] then
            return "recipe", "soulbound recipe for a profession you do not have (" .. prof .. ")"
        end
        return nil
    end
    -- bound: only gear, judged by the item score
    if not gear or not link or isSecret(link) then return nil end
    local S = OMQ.Score
    if not S then return nil end
    local class = S.MyClass and S.MyClass()
    local minLevel = select(5, info(link))
    if S.CanUse and not S.CanUse(link, class, math.max(level(), minLevel or 0)) then
        return "unusable", "your class cannot use it"
    end
    local LP = OMQ.LootPreview
    if not (LP and LP.Gain) then return nil end
    local ok, g = pcall(LP.Gain, link, equipLoc)
    if ok and g and g < 0 then return "worse", "worse than what you wear (" .. g .. ")" end
    return nil
end

-- the list: { bag, slot, itemID, link, name, icon, quality, qty, price, why, reason }
local list = {}
V._list = list
function V.Scan()
    for i = #list, 1, -1 do list[i] = nil end
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return list end
    local ctx = { sets = setItems(), food = V.BestFood(), profs = V.MyProfs() }
    for bag = 0, OMQ.LastBag() do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local it = C.GetContainerItemInfo(bag, slot)
            if it and it.itemID then
                local link = it.hyperlink
                local name, _, quality, _, _, _, _, _, _, icon, vendor = info(link or it.itemID)
                local _, _, _, equipLoc, icon2, classID = instant(it.itemID)
                if name then
                    local why, reason = V.Reason(it, { vendor = vendor, equipLoc = equipLoc, classID = classID, link = link }, ctx)
                    if why then
                        local qty = it.stackCount or 1
                        list[#list + 1] = { bag = bag, slot = slot, itemID = it.itemID, link = link, name = name,
                                            icon = it.iconFileID or icon or icon2, quality = quality or it.quality, qty = qty,
                                            price = (vendor or 0) * qty, why = why, reason = reason }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.price ~= b.price then return a.price > b.price end
        return a.itemID < b.itemID
    end)
    return list
end

function V.Total()
    local t = 0
    for _, e in ipairs(list) do t = t + e.price end
    return t
end

local function stillThere(e)
    local it = C_Container.GetContainerItemInfo(e.bag, e.slot)
    return it and it.itemID == e.itemID
end
function V.Sell(e)
    local C = C_Container
    if not (e and C and C.UseContainerItem) or not V.open then return false end
    if not stillThere(e) then V.Refresh(); return false end
    C.UseContainerItem(e.bag, e.slot)
    for i, x in ipairs(list) do if x == e then table.remove(list, i); break end end
    V.Refresh()
    return true
end
function V.SellAll()
    local C = C_Container
    if not (C and C.UseContainerItem) or not V.open then return 0 end
    local n, total = 0, 0
    for _, e in ipairs(list) do
        if stillThere(e) then
            C.UseContainerItem(e.bag, e.slot)
            n, total = n + 1, total + e.price
        end
    end
    for i = #list, 1, -1 do list[i] = nil end
    if n > 0 then OMQ:Print(string.format("vendor helper: sold %d item%s for %s", n, n == 1 and "" or "s", money(total))) end
    V.Refresh()
    return n
end
function V.Keep(e)
    if not e then return end
    db().keep[e.itemID] = true
    for i, x in ipairs(list) do if x == e then table.remove(list, i); break end end
    V.Refresh()
end
function V.ResetKeep()
    db().keep = {}
    V.Scan(); V.Refresh()
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local panel, rows = nil, {}
local function fs(parent, font, r, g, b)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    t:SetJustifyH("LEFT")
    if r then t:SetTextColor(r, g, b) end
    return t
end
local function qColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function build()
    panel = CreateFrame("Frame", "OneMoreQuestVendorHelper", UIParent)
    panel:SetSize(380, 200)
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.086, 0.094, 0.122, 0.97)
    local edge = panel:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(2)
    edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    local tag = fs(panel, "GameFontNormalSmall", GOLD[1], GOLD[2], GOLD[3])
    tag:SetPoint("TOPLEFT", 16, -14); tag:SetText("VENDOR HELPER")
    -- right click on the header: closed until the next visit
    local head = CreateFrame("Button", nil, panel)
    head:SetSize(250, 30); head:SetPoint("TOPLEFT", 0, 0)
    head:RegisterForClicks("RightButtonUp")
    head:SetScript("OnClick", function(_, button) if button == "RightButton" then V.Close() end end)
    head:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Right click: close until the next visit"); GameTooltip:Show() end
    end)
    head:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- "keep" marks can be undone
    local reset = CreateFrame("Button", "OneMoreQuestVendorReset", panel)
    reset:SetSize(70, 18); reset:SetPoint("TOPRIGHT", -12, -10)
    reset.bg = reset:CreateTexture(nil, "BACKGROUND"); reset.bg:SetAllPoints(); reset.bg:SetColorTexture(0.165, 0.141, 0.086, 1)
    reset.hl = reset:CreateTexture(nil, "HIGHLIGHT"); reset.hl:SetAllPoints(); reset.hl:SetColorTexture(1, 1, 1, 0.08)
    reset.text = fs(reset, "GameFontNormalSmall", GOLD[1], GOLD[2], GOLD[3]); reset.text:SetPoint("CENTER"); reset.text:SetText("Reset")
    reset:SetScript("OnClick", function() V.ResetKeep() end)
    reset:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Every item you kept with a right click is offered again"); GameTooltip:Show() end
    end)
    reset:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.reset = reset

    panel.head = fs(panel, "GameFontHighlight", 0.79, 0.8, 0.84); panel.head:SetPoint("TOPLEFT", 16, -36); panel.head:SetWidth(348)
    panel.offset = 0
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, d)
        panel.offset = math.max(0, math.min(math.max(0, #list - V.ROWS), panel.offset - d))
        V.Refresh()
    end)
    for i = 1, V.ROWS do
        local r = CreateFrame("Button", nil, panel)
        r:SetSize(348, 38)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.11, 0.122, 0.153, 1)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(30, 30); r.icon:SetPoint("LEFT", 4, 0)
        r.name = fs(r, "GameFontHighlight"); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1); r.name:SetWidth(230)
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.sub = fs(r, "GameFontDisableSmall"); r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1); r.sub:SetWidth(230)
        if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
        r.price = fs(r, "GameFontNormal", GOLD[1], GOLD[2], GOLD[3]); r.price:SetPoint("RIGHT", -8, 0); r.price:SetJustifyH("RIGHT")
        r:SetScript("OnClick", function(self, button)
            if not self.e then return end
            if button == "RightButton" then V.Keep(self.e) else V.Sell(self.e) end
        end)
        r:SetScript("OnEnter", function(self)
            if GameTooltip and self.e then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetBagItem then GameTooltip:SetBagItem(self.e.bag, self.e.slot)
                elseif self.e.link then GameTooltip:SetHyperlink(self.e.link) end
                GameTooltip:AddLine("Left click: sell - right click: keep, never offer again", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        rows[i] = r
    end
    local all = CreateFrame("Button", "OneMoreQuestVendorSellAll", panel)
    all:SetSize(348, 44)
    all.bg = all:CreateTexture(nil, "BACKGROUND"); all.bg:SetAllPoints(); all.bg:SetColorTexture(0.165, 0.141, 0.086, 1)
    all.hl = all:CreateTexture(nil, "HIGHLIGHT"); all.hl:SetAllPoints(); all.hl:SetColorTexture(1, 1, 1, 0.06)
    all.price = fs(all, "GameFontNormal", GOLD[1], GOLD[2], GOLD[3]); all.price:SetPoint("RIGHT", -10, 0); all.price:SetJustifyH("RIGHT")
    all.title = fs(all, "GameFontNormalLarge", GOLD[1], GOLD[2], GOLD[3])
    all.title:SetPoint("LEFT", 10, 0); all.title:SetPoint("RIGHT", all.price, "LEFT", -8, 0)
    all:SetScript("OnClick", function() V.SellAll() end)
    panel.all = all
    panel.more = fs(panel, "GameFontDisableSmall")
    panel.hint = fs(panel, "GameFontDisableSmall"); panel.hint:SetWidth(348)
    panel.hint:SetText("Left click: sell - right click: keep, never offer again")
    panel:Hide()
end

local function anchor()
    panel:ClearAllPoints()
    local mf = _G.MerchantFrame
    if mf then panel:SetPoint("TOPLEFT", mf, "TOPRIGHT", 6, 0) else panel:SetPoint("LEFT", UIParent, "CENTER", 200, 0) end
end

function V.Refresh()
    if not panel or not V.open then return end
    panel.offset = math.min(panel.offset, math.max(0, #list - V.ROWS))
    local y = 36
    if #list == 0 then panel.head:SetText("Nothing to sell here")
    else panel.head:SetText(string.format("%d item%s to sell", #list, #list == 1 and "" or "s")) end
    y = y + 22
    for i, r in ipairs(rows) do
        local e = list[i + panel.offset]
        r.e = e
        r:SetShown(e ~= nil)
        if e then
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 16, -y)
            r.icon:SetTexture(e.icon)
            r.name:SetText(e.name .. ((e.qty or 1) > 1 and (" x" .. e.qty) or "")); r.name:SetTextColor(qColor(e.quality))
            r.sub:SetText(e.reason or "")
            r.price:SetText(money(e.price))
            y = y + 40
        end
    end
    if #list > V.ROWS then
        panel.more:ClearAllPoints(); panel.more:SetPoint("TOPLEFT", 16, -y)
        panel.more:SetText(string.format("Mouse wheel: %d more", #list - V.ROWS)); panel.more:Show()
        y = y + 16
    else panel.more:Hide() end
    panel.all:SetShown(#list > 0)
    if #list > 0 then
        y = y + 6
        panel.all:ClearAllPoints(); panel.all:SetPoint("TOPLEFT", 16, -y)
        panel.all.title:SetText(string.format("Sell all - %d item%s", #list, #list == 1 and "" or "s"))
        panel.all.price:SetText(money(V.Total()))
        y = y + 48
    end
    panel.hint:ClearAllPoints(); panel.hint:SetPoint("TOPLEFT", 16, -(y + 4))
    panel.hint:SetShown(#list > 0)
    if #list > 0 then y = y + 20 end
    panel:SetHeight(y + 12)
end

function V.Open()
    if not V.Enabled() then return end
    if not panel then build() end
    V.open = true
    panel.offset = 0
    anchor()
    V.Scan()
    panel:Show()
    V.Refresh()
end
function V.Close()
    V.open = false
    if panel then panel:Hide() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local pending = false
ev:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
        if event == "MERCHANT_SHOW" then
            V.atMerchant = true
            -- after "sell grey items" (QoL.lua) had its turn
            if C_Timer and C_Timer.After then C_Timer.After(0.6, function() if V.atMerchant then V.Open() end end)
            else V.Open() end
        elseif event == "MERCHANT_CLOSED" then V.atMerchant = false; V.Close()
        elseif V.open and not pending then
            pending = true
            local function again() pending = false; if V.open then V.Scan(); V.Refresh() end end
            if C_Timer and C_Timer.After then C_Timer.After(0.2, again) else again() end
        end
    end)
    if not ok then OMQ:Error("vendor helper", err) end
end)
