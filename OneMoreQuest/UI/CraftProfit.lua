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

local paintBadgesRef
local function paintRow(frame, elementData)
    local id = recipeIDOf(frame, elementData)
    if paintBadgesRef then local ok, err = pcall(paintBadgesRef, frame, id); if not ok then OMQ:Error("craft badges", err) end end
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
    if event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_SHOW" then C.ForgetRanking() end
    if event ~= "ADDON_LOADED" then
        startTicker()
        if C_Timer and C_Timer.After then C_Timer.After(0.3, function() safe(C.PaintBlock, "craft profit block") end) end
    end
end)
OMQ:On("PRICES_UPDATED", function() C.ForgetRanking(); safe(C.PaintList, "craft profit list"); safe(C.PaintBlock, "craft profit block") end)
OMQ:On("READY", function() safe(hookForm, "craft profit") end)

----------------------------------------------------------------------
-- Cheapest way to level a profession (decision 346)
----------------------------------------------------------------------
-- The chance of a skill-up: orange always; yellow and green (G - X) / (G - Y), X = my skill, Y = where the recipe turns
-- yellow, G = where it turns gray. Gray never. The thresholds are read from the recipe info of the game by their names.
local function numberFields(t, out, depth)
    for k, v in pairs(t) do
        local name = tostring(k):lower()
        if type(v) == "number" and not isSecret(v) then
            if name:find("orange") or name:find("optimal") then out.orange = out.orange or v
            elseif name:find("yellow") or name:find("medium") then out.yellow = out.yellow or v
            elseif name:find("green") or name:find("easy") then out.green = out.green or v
            elseif name:find("gray") or name:find("grey") or name:find("trivial") then out.gray = out.gray or v end
        elseif type(v) == "table" and depth < 2 then numberFields(v, out, depth + 1) end
    end
end
function C.Thresholds(info)
    if type(info) ~= "table" then return nil end
    local out = {}
    -- the table of SkillUp Forever first (Data/SkillThresholds.lua), then what the game says itself
    local row = OMQ.SkillThresholds and info.recipeID and OMQ.SkillThresholds[info.recipeID]
    if row then return { orange = row[1], yellow = row[2], green = row[3], gray = row[4] } end
    -- the names the game uses: minSkill, yellowSkillLevel, greenSkillLevel, graySkillLevel
    local function num(v) return type(v) == "number" and not isSecret(v) and v or nil end
    out.orange, out.yellow, out.green, out.gray = num(info.minSkill), num(info.yellowSkillLevel), num(info.greenSkillLevel), num(info.graySkillLevel)
    if not (out.yellow and out.gray) then numberFields(info, out, 0) end
    if out.yellow and out.gray then return out end
    return nil
end
function C.Chance(skill, th)
    if not (skill and th and th.yellow and th.gray) then return nil end
    if skill < th.yellow then return 1 end
    if skill >= th.gray then return 0 end
    return (th.gray - skill) / (th.gray - th.yellow)
end
function C.MySkill()
    local T = C_TradeSkillUI
    if T and T.GetBaseProfessionInfo then
        local ok, p = pcall(T.GetBaseProfessionInfo)
        if ok and type(p) == "table" and tonumber(p.skillLevel) and not isSecret(p.skillLevel) then return tonumber(p.skillLevel) end
    end
    local f = pf()
    local p = f and f.professionInfo
    if p and tonumber(p.skillLevel) then return tonumber(p.skillLevel) end
    if T and T.GetTradeSkillLine then
        local ok, _, rank = pcall(T.GetTradeSkillLine)
        if ok and tonumber(rank) then return tonumber(rank) end
    end
    if GetTradeSkillLine then
        local ok, _, rank = pcall(GetTradeSkillLine)
        if ok and tonumber(rank) then return tonumber(rank) end
    end
    return nil
end
local function recipeIDs()
    local T = C_TradeSkillUI
    for _, fn in ipairs({ "GetAllRecipeIDs", "GetFilteredRecipeIDs" }) do
        if T and T[fn] then
            local ok, ids = pcall(T[fn])
            if ok and type(ids) == "table" and #ids > 0 then return ids end
        end
    end
    return {}
end

local rank = nil
-- every recipe I know of the open profession, with what one skill-up costs; { [recipeID] = {chance, perUp, perUpNet} }
function C.Ranking()
    if rank then
        local empty = next(rank.by) == nil
        if not (empty and (GetTime and GetTime() or 0) - (rank.at or 0) > 3) then return rank end   -- an empty answer is asked again soon
    end
    rank = { by = {}, best = nil, bestNet = nil, at = GetTime and GetTime() or 0,
             stats = { listed = 0, unlearned = 0, noThreshold = 0, gray = 0, noPrice = 0, ranked = 0 } }
    local T = C_TradeSkillUI
    local skill = C.MySkill()
    rank.skill = skill
    if not (T and T.GetRecipeInfo and skill) then return rank end
    local st = rank.stats
    for _, id in ipairs(recipeIDs()) do
        st.listed = st.listed + 1
        local okI, info = pcall(T.GetRecipeInfo, id)
        if okI and type(info) == "table" and info.learned ~= false then
            if not info.recipeID then info.recipeID = id end
            local th = C.Thresholds(info)
            local chance = C.Chance(skill, th)
            local res = C.Profit(id)
            if not chance then st.noThreshold = st.noThreshold + 1
            elseif chance <= 0 then st.gray = st.gray + 1
            elseif not (res and #res.missing == 0) then st.noPrice = st.noPrice + 1
            else
                st.ranked = st.ranked + 1
                local e = { chance = chance, th = th, cost = res.cost, perUp = res.cost / chance }
                if res.sale then e.perUpNet = (res.cost - math.floor(res.sale * (1 - C.CUT) + 0.5)) / chance end
                rank.by[id] = e
                if not rank.best or e.perUp < rank.by[rank.best].perUp then rank.best = id end
                if e.perUpNet and (not rank.bestNet or e.perUpNet < rank.by[rank.bestNet].perUpNet) then rank.bestNet = id end
            end
        else
            st.unlearned = st.unlearned + 1
        end
    end
    return rank
end
function C.ForgetRanking() rank = nil end

local ICON_CHEAP, ICON_NET = "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\INV_Misc_Coin_17"
local function badge(frame, key, tex, anchor, dx)
    local b = frame[key]
    if not b then
        b = CreateFrame("Frame", nil, frame)
        b:SetSize(16, 16)
        b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexture(tex)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            if not (GameTooltip and self.tip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            for i, line in ipairs(self.tip) do
                if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 0.9, 0.9, 0.9) end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        frame[key] = b
    end
    b:ClearAllPoints()
    b:SetPoint("RIGHT", anchor, "LEFT", dx or -4, 0)
    return b
end
local function paintBadges(frame, id)
    local R = C.Ranking()
    local e = id and R.by[id]
    for _, key in ipairs({ "OMQCheap", "OMQNet" }) do if frame[key] then frame[key]:Hide() end end
    if not e then return end
    local anchor = (frame.SkillUps and frame.SkillUps.IsShown and frame.SkillUps:IsShown() and frame.SkillUps) or frame.OMQProfit or frame
    local x = nil
    if R.best == id then
        local b = badge(frame, "OMQCheap", ICON_CHEAP, anchor)
        b.tip = { "Cheapest skill-up", string.format("%s per skill-up (%d%% chance, craft cost %s)", C.Money(math.floor(e.perUp + 0.5)), math.floor(e.chance * 100 + 0.5), C.Money(e.cost)) }
        b:Show(); anchor = b
    end
    if R.bestNet == id then
        local b = badge(frame, "OMQNet", ICON_NET, anchor)
        local v = math.floor(e.perUpNet + 0.5)
        b.tip = { "Cheapest skill-up with selling", string.format("%s%s per skill-up after selling the product (%d%% chance)", v < 0 and "gain " or "", C.Money(v), math.floor(e.chance * 100 + 0.5)) }
        b:Show()
    end
end

paintBadgesRef = paintBadges
C._paintBadges = paintBadges

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

-- /omq craft info: what the game tells about the open recipe (the skill-up thresholds are read from it, decision 346)
OMQ:RegisterCommand("craftinfo", function()
    local id = C.RecipeOfForm()
    if not id then OMQ:Print("craft info: no recipe selected"); return end
    local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(id)
    local keys = {}
    for k, v in pairs(info or {}) do
        local sv = (type(v) == "table") and "{table}" or tostring(v)
        keys[#keys + 1] = tostring(k) .. "=" .. sv
        if type(v) == "table" then for k2, v2 in pairs(v) do keys[#keys + 1] = "  " .. tostring(k) .. "." .. tostring(k2) .. "=" .. ((type(v2) == "table") and "{table}" or tostring(v2)) end end
    end
    table.sort(keys)
    OMQ:Print("craft info: recipe " .. id .. ", my skill " .. tostring(C.MySkill()) .. ", recipes listed " .. #recipeIDs())
    for _, l in ipairs(keys) do OMQ:Print("  " .. l) end
    local th = C.Thresholds(info)
    OMQ:Print("thresholds: " .. (th and string.format("orange %s yellow %s green %s gray %s", tostring(th.orange), tostring(th.yellow), tostring(th.green), tostring(th.gray)) or "not found in the recipe info"))
    local R = C.Ranking()
    local n = 0
    for _ in pairs(R.by) do n = n + 1 end
    OMQ:Print(string.format("ranking: %d recipes with a chance and a price, cheapest %s, cheapest with selling %s", n, tostring(R.best), tostring(R.bestNet)))
    local T = C_TradeSkillUI
    for _, k in ipairs({ "best", "bestNet" }) do
        local rid = R[k]
        local inf = rid and T and T.GetRecipeInfo and T.GetRecipeInfo(rid)
        OMQ:Print(string.format("  %s: recipe %s (%s)", k == "best" and "cheapest by craft cost" or "cheapest with selling", tostring(rid), inf and tostring(inf.name) or "?"))
    end
    local seen, shown, ids = 0, 0, {}
    local sb = scrollBox()
    if sb and sb.ForEachFrame then
        sb:ForEachFrame(function(frame, data)
            seen = seen + 1
            ids[#ids + 1] = tostring(recipeIDOf(frame, data))
            if (frame.OMQCheap and frame.OMQCheap:IsShown()) or (frame.OMQNet and frame.OMQNet:IsShown()) then shown = shown + 1 end
        end)
    end
    OMQ:Print(string.format("  list rows now: %d, with a badge: %d; ids %s", seen, shown, table.concat(ids, ",")))
    local st = R.stats
    if st then
        OMQ:Print(string.format("ranking: skill %s, listed %d, not learned %d, no thresholds %d, gray %d, a material without price %d, ranked %d",
            tostring(R.skill), st.listed, st.unlearned, st.noThreshold, st.gray, st.noPrice, st.ranked))
    end
end, "profession skill-ups: what the game says about the open recipe")
