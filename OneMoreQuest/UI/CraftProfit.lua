-- One More Quest: crafting profit (decision 341, step 2)
-- For every recipe: what the materials cost (auction house or vendor, the cheaper) against what the product
-- brings on the auction house after the 5% cut. Shown in the profession window as a number at the right of every recipe in
-- the list and as a "Profit - Auction House" block under the reagents of the selected recipe. The prices come from
-- UI/CraftPrices.lua. Sold per day is not used.
-- Unknown prices are never guessed: a recipe with a material that has no price, or whose product nobody
-- sells, shows a grey "?" and the block names what is missing.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local C = {}
OMQ.CraftProfit = C

C.CUT = 0.05
local function isSecret(v) return issecretvalue and issecretvalue(v) end
function C.On() return not (OMQ.db and OMQ.db.options and OMQ.db.options.craftProfit == false) end

----------------------------------------------------------------------
-- Recipe data and the profit
----------------------------------------------------------------------
local cache = {}
local function reduce(schematic)
    if type(schematic) ~= "table" then return nil end
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        local required = tonumber(slot.quantityRequired) or 0
        if (basic == nil or slot.reagentType == basic) and first and first.itemID and required > 0 then
            reagents[#reagents + 1] = { itemID = first.itemID, qty = required }
        end
    end
    local qmin, qmax = tonumber(schematic.quantityMin) or 1, tonumber(schematic.quantityMax) or 1
    return { out = schematic.outputItemID, qty = (qmin + qmax) / 2, reagents = reagents }
end

function C.Recipe(recipeID)
    if cache[recipeID] ~= nil then return cache[recipeID] or nil end
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic) then return nil end
    local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
    local r = ok and reduce(schematic) or nil
    if r and #r.reagents > 0 then cache[recipeID] = r else cache[recipeID] = false end
    return cache[recipeID] or nil
end
function C.Forget() cache = {} end

-- { cost, sale, net, pct, missing = {item ids}, noSale, noProduct, complete, at }
function C.Profit(recipeID)
    local r = C.Recipe(recipeID)
    local P = OMQ.Prices
    if not (r and P) then return nil end
    local res = { cost = 0, missing = {}, at = P.ScannedAt() }
    for _, m in ipairs(r.reagents) do
        local c = P.Cost(m.itemID)
        if c then res.cost = res.cost + c * m.qty else res.missing[#res.missing + 1] = m.itemID end
    end
    if not r.out then
        res.noProduct = true
    else
        local price = P.Auction(r.out)
        if price then res.sale = math.floor(price * r.qty + 0.5) else res.noSale = true end
    end
    res.complete = #res.missing == 0 and res.sale ~= nil
    if res.complete then
        res.net = math.floor(res.sale * (1 - C.CUT) + 0.5) - res.cost
        res.pct = res.cost > 0 and (res.net / res.cost * 100) or nil
    end
    return res
end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------
local ICON = { g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
               c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" }
-- a whole amount: 3 g 35 s with icons
function C.Money(copper)
    copper = math.floor(math.abs(copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local t = {}
    if g > 0 then t[#t + 1] = g .. ICON.g end
    if s > 0 then t[#t + 1] = s .. ICON.s end
    if c > 0 or #t == 0 then t[#t + 1] = c .. ICON.c end
    return table.concat(t, " ")
end
-- the short form of the list: the biggest unit only, with a sign
function C.Short(net)
    local sign = net < 0 and "-" or "+"
    local a = math.abs(net)
    local body
    if a >= 10000 then
        local g, s = math.floor(a / 10000), math.floor(a / 100) % 100
        body = g .. ICON.g .. (s > 0 and (" " .. s .. ICON.s) or "")
    elseif a >= 100 then body = math.floor(a / 100) .. ICON.s
    else body = math.floor(a) .. ICON.c end
    return sign .. body
end
local GREEN, RED, GREY = "ff4ddb4d", "ffff5a4d", "ff8d93a1"
function C.ListText(res)
    if not res then return nil end
    if not res.complete then return "|c" .. GREY .. "?|r" end
    local col = res.net >= 0 and GREEN or RED
    return "|c" .. col .. C.Short(res.net) .. "|r"
end

local function itemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n and GetItemInfo then n = (GetItemInfo(id)) end
    return n or ("item " .. id)
end

----------------------------------------------------------------------
-- The profession window
----------------------------------------------------------------------
local function pf() return _G.ProfessionsFrame end
local function form() local f = pf(); return f and f.CraftingPage and f.CraftingPage.SchematicForm end
local function scrollBox()
    local f = pf()
    local list = f and f.CraftingPage and f.CraftingPage.RecipeList
    return list and list.ScrollBox
end

local function recipeIDOf(frame, elementData)
    local d = elementData
    if type(d) == "table" and d.GetData then d = d:GetData() end
    if type(d) == "table" then
        if d.recipeInfo and d.recipeInfo.recipeID then return d.recipeInfo.recipeID end
        if d.data and d.data.recipeInfo and d.data.recipeInfo.recipeID then return d.data.recipeInfo.recipeID end
        if d.recipeID then return d.recipeID end
    end
    if frame and frame.GetElementData and not elementData then return recipeIDOf(frame, frame:GetElementData()) end
    return nil
end

local function paintRow(frame, elementData)
    local id = recipeIDOf(frame, elementData)
    local label = frame.OMQProfit
    local text = id and C.ListText(C.Profit(id)) or nil
    if not text then
        if label then label:SetText("") end
        return
    end
    if not label then
        label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
        label:SetJustifyH("RIGHT")
        frame.OMQProfit = label
    end
    label:SetText(text)
end

function C.PaintList()
    local sb = scrollBox()
    if not (sb and sb.ForEachFrame) then return 0 end
    local n = 0
    sb:ForEachFrame(function(frame, elementData) n = n + 1; paintRow(frame, elementData) end)
    return n
end

-- the block under the reagents
local block
local function buildBlock(parent)
    if block then return block end
    block = CreateFrame("Frame", "OneMoreQuestProfit", parent)
    block:SetHeight(104)
    local bg = block:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.06, 0.08, 0.85)
    local edge = block:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.64, 0.50, 0.21, 0.8)
    edge:SetDrawLayer("BACKGROUND", -1)
    local function fs(font) local f = block:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall"); f:SetJustifyH("LEFT"); return f end
    block.title = fs("GameFontNormal")
    block.title:SetPoint("TOPLEFT", 10, -8)
    block.age = fs()
    block.age:SetPoint("TOPRIGHT", -10, -9)
    block.age:SetJustifyH("RIGHT")
    block.age:SetTextColor(0.55, 0.58, 0.63)
    block.rows = {}
    for i = 1, 3 do
        local l, v = fs(), fs()
        l:SetPoint("TOPLEFT", 10, -26 - (i - 1) * 16)
        v:SetPoint("TOPRIGHT", -10, -26 - (i - 1) * 16)
        v:SetJustifyH("RIGHT")
        block.rows[i] = { l = l, v = v }
    end
    block.note = fs()
    block.note:SetPoint("TOPLEFT", 10, -76)
    block.note:SetPoint("RIGHT", block, "RIGHT", -10, 0)
    block.note:SetTextColor(0.55, 0.58, 0.63)
    block.note:SetWordWrap(true)
    return block
end

function C.RecipeOfForm()
    local f = form()
    if not f then return nil end
    local info = f.GetRecipeInfo and f:GetRecipeInfo() or f.recipeInfo
    return info and info.recipeID
end

function C.PaintBlock()
    local f = form()
    if not f then return false end
    local id = C.RecipeOfForm()
    local res = id and C.Profit(id)
    if not (C.On() and res) then
        if block then block:Hide() end
        return false
    end
    buildBlock(f)
    block:ClearAllPoints()
    block:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    block:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    block.title:SetText("Profit - Auction House")
    local at = OMQ.Prices and OMQ.Prices.ScannedAt()
    block.age:SetText(at and ("scanned " .. OMQ.Prices.Ago(at)) or "not scanned yet")
    local R = block.rows
    R[1].l:SetText("Total craft cost")
    R[1].v:SetText(res.cost > 0 and C.Money(res.cost) or "-")
    R[2].l:SetText("Expected sale price")
    R[2].v:SetText(res.sale and C.Money(res.sale) or (res.noProduct and "no item" or "none on sale"))
    R[3].l:SetText("Net profit")
    if res.complete then
        local col = res.net >= 0 and GREEN or RED
        local pct = res.pct and string.format(" (%+.0f%%)", res.pct) or ""
        R[3].v:SetText("|c" .. col .. (res.net < 0 and "-" or "") .. C.Money(res.net) .. pct .. "|r")
    else
        R[3].v:SetText("|c" .. GREY .. "?|r")
    end
    local why = {}
    if #res.missing > 0 then
        local names = {}
        for i = 1, math.min(3, #res.missing) do names[#names + 1] = itemName(res.missing[i]) end
        why[#why + 1] = "No price for " .. table.concat(names, ", ") .. (#res.missing > 3 and "..." or "")
    end
    if res.noSale and not res.noProduct then why[#why + 1] = "nobody sells the product" end
    block.note:SetText(table.concat(why, " - "))
    block:Show()
    return true
end

local function safe(fn, name)
    local ok, err = pcall(fn)
    if not ok then OMQ:Error(name, err) end
end

local hooked, ticking = false, false
local function startTicker()
    if ticking or not (C_Timer and C_Timer.After) then return end
    ticking = true
    local function loop()
        local f = pf()
        if f and f.IsShown and f:IsShown() and C.On() then
            safe(C.PaintList, "craft profit list")
            C_Timer.After(0.5, loop)
        else
            ticking = false
        end
    end
    loop()
end

local function hookForm()
    local f = form()
    if not f or hooked then return end
    hooked = true
    if hooksecurefunc and f.Init then
        hooksecurefunc(f, "Init", function()
            if C_Timer and C_Timer.After then C_Timer.After(0.2, function() safe(C.PaintBlock, "craft profit block") end) end
        end)
    end
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "ADDON_LOADED", "TRADE_SKILL_LIST_UPDATE" }) do pcall(frame.RegisterEvent, frame, e) end
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_Professions" then return end
    safe(hookForm, "craft profit")
    if event ~= "ADDON_LOADED" then
        startTicker()
        if C_Timer and C_Timer.After then C_Timer.After(0.3, function() safe(C.PaintBlock, "craft profit block") end) end
    end
end)
OMQ:On("PRICES_UPDATED", function() safe(C.PaintList, "craft profit list"); safe(C.PaintBlock, "craft profit block") end)
OMQ:On("READY", function() safe(hookForm, "craft profit") end)

-- /omq craft: the recipe that is open, its materials and prices; what was found of the window
OMQ:RegisterCommand("craft", function()
    local f = pf()
    OMQ:Print("craft profit: ProfessionsFrame " .. tostring(f ~= nil) .. ", SchematicForm " .. tostring(form() ~= nil)
        .. ", list " .. tostring(scrollBox() ~= nil) .. ", rows painted " .. C.PaintList() .. ", block " .. tostring(block and block:IsShown() or false))
    local id = C.RecipeOfForm()
    if not id then OMQ:Print("craft profit: no recipe selected"); return end
    local r = C.Recipe(id)
    if not r then OMQ:Print("craft profit: recipe " .. id .. " has no readable materials"); return end
    local P = OMQ.Prices
    OMQ:Print(string.format("recipe %d makes %s x%s", id, r.out and itemName(r.out) or "no item", tostring(r.qty)))
    for _, m in ipairs(r.reagents) do
        local c, src = P.Cost(m.itemID)
        OMQ:Print(string.format("  %dx %s: %s", m.qty, itemName(m.itemID), c and (C.Money(c) .. " (" .. src .. ")") or "no price"))
    end
    local res = C.Profit(id)
    if res and res.complete then
        OMQ:Print(string.format("cost %s, sale %s, net %s%s", C.Money(res.cost), C.Money(res.sale), res.net < 0 and "-" or "", C.Money(res.net)))
    end
end, "crafting profit: what the open recipe costs and brings")
