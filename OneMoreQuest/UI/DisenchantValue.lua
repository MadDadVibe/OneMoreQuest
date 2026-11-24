-- One More Quest - disenchant value in the item tooltip (decision 670)
-- Green, blue and purple armor and weapons get the line "Disenchant: ~X" in the price block: the expected worth of the materials,
-- from the classic disenchant tables (item level, quality, weapon or armor) and the scanned auction prices.
-- Shift shows every material with its chance. A material without an auction price: "(prices incomplete)".
local OMQ = OneMoreQuest
local D = {}
OMQ.Disenchant = D

local function isSecret(v) return issecretvalue and issecretvalue(v) end

-- materials: item id and the English name (the client's own name is used when the game has it)
D.MATS = {
    [10940] = "Strange Dust", [11083] = "Soul Dust", [11137] = "Vision Dust", [11176] = "Dream Dust", [16204] = "Illusion Dust",
    [10938] = "Lesser Magic Essence", [10939] = "Greater Magic Essence", [10998] = "Lesser Astral Essence",
    [11082] = "Greater Astral Essence", [11134] = "Lesser Mystic Essence", [11135] = "Greater Mystic Essence",
    [11174] = "Lesser Nether Essence", [11175] = "Greater Nether Essence", [16202] = "Lesser Eternal Essence",
    [16203] = "Greater Eternal Essence",
    [10978] = "Small Glimmering Shard", [11084] = "Large Glimmering Shard", [11138] = "Small Glowing Shard",
    [11139] = "Large Glowing Shard", [11177] = "Small Radiant Shard", [11178] = "Large Radiant Shard",
    [14343] = "Small Brilliant Shard", [14344] = "Large Brilliant Shard", [20725] = "Nexus Crystal",
}
-- uncommon: { max item level, dust, dust min, dust max, essence, ess min, ess max, shard (5%) }
-- armor: 75% dust, 20% essence; weapons: 20% dust, 75% essence (5-10: 80/20 without shard)
D.GREEN = {
    { 10, 10940, 1, 2, 10938, 1, 2, nil },
    { 15, 10940, 2, 3, 10939, 1, 2, 10978 },
    { 20, 10940, 4, 6, 10998, 1, 2, 10978 },
    { 25, 11083, 1, 2, 11082, 1, 2, 11084 },
    { 30, 11083, 2, 5, 11134, 1, 2, 11138 },
    { 35, 11137, 1, 2, 11135, 1, 2, 11139 },
    { 40, 11137, 2, 5, 11174, 1, 2, 11177 },
    { 45, 11176, 1, 2, 11175, 1, 2, 11178 },
    { 50, 11176, 2, 5, 16202, 1, 2, 14343 },
    { 55, 16204, 1, 2, 16203, 1, 2, 14344 },
    { 999, 16204, 2, 5, 16203, 2, 3, 14344 },
}
-- rare: { max item level, shard } (one shard; 56+ has 0.5% Nexus Crystal)
D.BLUE = {
    { 20, 10978 }, { 25, 11084 }, { 30, 11138 }, { 35, 11139 }, { 40, 11177 }, { 45, 11178 }, { 50, 14343 }, { 999, 14344 },
}
-- epic: { max item level, material, min, max }
D.EPIC = {
    { 45, 11177, 2, 4 }, { 50, 11178, 2, 4 }, { 55, 14343, 2, 4 }, { 60, 20725, 1, 1 }, { 999, 20725, 1, 2 },
}
local NO_LOC = { [""] = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BAG = true, INVTYPE_AMMO = true }

local function row(t, lvl)
    for _, r in ipairs(t) do if lvl <= r[1] then return r end end
end
-- the outcomes { chance, item, min, max } of one item, or nil when it cannot be disenchanted
function D.Outcomes(quality, ilvl, weapon)
    if type(quality) ~= "number" or type(ilvl) ~= "number" or ilvl < 1 then return nil end
    if quality == 2 then
        if ilvl < 5 then return nil end
        local r = row(D.GREEN, ilvl)
        if not r[8] then return { { weapon and 0.2 or 0.8, r[2], r[3], r[4] }, { weapon and 0.8 or 0.2, r[5], r[6], r[7] } } end
        return { { weapon and 0.2 or 0.75, r[2], r[3], r[4] }, { weapon and 0.75 or 0.2, r[5], r[6], r[7] }, { 0.05, r[8], 1, 1 } }
    elseif quality == 3 then
        if ilvl < 11 then return nil end
        local r = row(D.BLUE, ilvl)
        if ilvl >= 56 then return { { 0.995, r[2], 1, 1 }, { 0.005, 20725, 1, 1 } } end
        return { { 1, r[2], 1, 1 } }
    elseif quality == 4 then
        if ilvl < 40 then return nil end
        local r = row(D.EPIC, ilvl)
        return { { 1, r[2], r[3], r[4] } }
    end
end

-- item facts: quality, item level, weapon?  nil when the item is no armor or weapon or not cached yet
function D.ItemFacts(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, _, _, quality, ilvl, _, _, _, _, loc, _, _, classID, subID = pcall(f, id)
    if not ok or quality == nil or isSecret(quality) or isSecret(ilvl) or isSecret(classID) then return nil end
    if classID ~= 2 and classID ~= 4 then return nil end
    if classID == 2 and subID == 20 then return nil end              -- fishing poles
    if NO_LOC[loc or ""] then return nil end
    return quality, ilvl, classID == 2
end

local function matName(id)
    local f = C_Item and C_Item.GetItemNameByID
    local ok, n = false, nil
    if f then ok, n = pcall(f, id) end
    if ok and type(n) == "string" and n ~= "" and not isSecret(n) then return n end
    return D.MATS[id] or ("item " .. id)
end
local function money(c)
    local C = OMQ.CraftProfit
    if C and C.Money then return C.Money(c) end
    return c .. "c"
end

-- expected value in copper, the outcome rows with their worth, and whether a material had no price
function D.Value(id)
    local quality, ilvl, weapon = D.ItemFacts(id)
    if not quality then return nil end
    local outs = D.Outcomes(quality, ilvl, weapon)
    if not outs then return nil end
    local P = OMQ.Prices
    local total, missing, priced, rows = 0, false, 0, {}
    for _, o in ipairs(outs) do
        local price = P and P.Auction and P.Auction(o[2])
        local avg = (o[3] + o[4]) / 2
        local worth
        if type(price) == "number" and price > 0 then
            worth = o[1] * avg * price
            total = total + worth
            priced = priced + 1
        else missing = true end
        rows[#rows + 1] = { chance = o[1], item = o[2], min = o[3], max = o[4], price = price, worth = worth }
    end
    return math.floor(total + 0.5), rows, missing, priced
end

function D.On() return not (OMQ.db and OMQ.db.options and OMQ.db.options.disenchantTip == false) end

-- the value for the price block of the tooltip (UI/CraftPrices.lua, decision 675) and, with Shift, the materials
function D.Text(id, shift)
    if not D.On() then return nil end
    local v, rows, missing, priced = D.Value(id)
    if not v then return nil end
    local text
    if priced == 0 then text = "no auction prices of the materials yet"
    else text = "~" .. money(v) .. (missing and "  (prices incomplete)" or "") end
    local more = {}
    if shift then
        for _, r in ipairs(rows) do
            local pct = math.floor(r.chance * 1000 + 0.5) / 10
            local pctText = (pct == math.floor(pct)) and string.format("%d%%", pct) or string.format("%.1f%%", pct)
            local count = r.min == r.max and tostring(r.min) or (r.min .. "-" .. r.max)
            more[#more + 1] = { string.format("   %s  %sx %s  %s", pctText, count, matName(r.item),
                r.price and r.price > 0 and money(r.price) .. " each" or "no price"), 0.6, 0.6, 0.6 }
        end
    end
    return text, more
end
OMQ:RegisterCommand("de", function(arg)
    local id = tonumber(arg or "") or D.last
    if not id then OMQ:Print("de: hover an item or give an item id: /omq de <item id>"); return end
    local quality, ilvl, weapon = D.ItemFacts(id)
    if not quality then OMQ:Print(("de: item %d - no armor or weapon, or not known to the game yet"):format(id)); return end
    local v, rows = D.Value(id)
    if not v then OMQ:Print(("de: item %d (quality %d, item level %d) cannot be disenchanted"):format(id, quality, ilvl)); return end
    OMQ:Print(("de: item %d, quality %d, item level %d, %s: ~%s"):format(id, quality, ilvl, weapon and "weapon" or "armor", money(v)))
    for _, r in ipairs(rows) do
        OMQ:Print(("  %.1f%% %d-%d %s (%d): %s"):format(r.chance * 100, r.min, r.max, matName(r.item), r.item,
            r.price and money(r.price) or "no price"))
    end
end, "de [item id] - disenchant value of the last hovered item", true)

-- the tooltip line itself comes with the price block of UI/CraftPrices.lua (decision 675)
