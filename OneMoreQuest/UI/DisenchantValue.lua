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
-- The tables are copied from warcraft.wiki.gg "Disenchanting tables" (by item level), only the brackets whose
-- materials exist in classic (fix 681). A row: { lowest item level, highest item level, { chance, item, min, max }, ... }
-- uncommon armor
D.GREEN_ARMOR = {
    { 5, 15,  { 0.80, 10940, 1, 2 }, { 0.20, 10938, 1, 2 } },
    { 16, 20, { 0.75, 10940, 2, 3 }, { 0.20, 10939, 1, 2 }, { 0.05, 10978, 1, 1 } },
    { 21, 25, { 0.75, 10940, 4, 6 }, { 0.15, 10998, 1, 2 }, { 0.10, 10978, 1, 1 } },
    { 26, 30, { 0.75, 11083, 1, 2 }, { 0.20, 11082, 1, 2 }, { 0.05, 11084, 1, 1 } },
    { 31, 35, { 0.75, 11083, 2, 5 }, { 0.20, 11134, 1, 2 }, { 0.05, 11138, 1, 1 } },
    { 36, 40, { 0.75, 11137, 1, 2 }, { 0.20, 11135, 1, 2 }, { 0.05, 11139, 1, 1 } },
    { 41, 45, { 0.75, 11137, 2, 5 }, { 0.20, 11174, 1, 2 }, { 0.05, 11177, 1, 1 } },
    { 46, 50, { 0.75, 11176, 1, 2 }, { 0.20, 11175, 1, 2 }, { 0.05, 11178, 1, 1 } },
    { 51, 55, { 0.75, 11176, 2, 5 }, { 0.20, 16202, 1, 2 }, { 0.05, 14343, 1, 1 } },
    { 56, 60, { 0.75, 16204, 1, 2 }, { 0.20, 16203, 1, 2 }, { 0.05, 14344, 1, 1 } },
    { 61, 65, { 0.75, 16204, 2, 5 }, { 0.20, 16203, 2, 3 }, { 0.05, 14344, 1, 1 } },
}
-- uncommon weapons
D.GREEN_WEAPON = {
    { 6, 15,  { 0.20, 10940, 1, 2 }, { 0.80, 10938, 1, 2 } },
    { 16, 20, { 0.20, 10940, 2, 3 }, { 0.75, 10939, 1, 2 }, { 0.05, 10978, 1, 1 } },
    { 21, 25, { 0.15, 10940, 4, 6 }, { 0.75, 10998, 1, 2 }, { 0.10, 10978, 1, 1 } },
    { 26, 30, { 0.20, 11083, 1, 2 }, { 0.75, 11082, 1, 2 }, { 0.05, 11084, 1, 1 } },
    { 31, 35, { 0.20, 11083, 2, 5 }, { 0.75, 11134, 1, 2 }, { 0.05, 11138, 1, 1 } },
    { 36, 40, { 0.20, 11137, 1, 2 }, { 0.75, 11135, 1, 2 }, { 0.05, 11139, 1, 1 } },
    { 41, 45, { 0.20, 11137, 2, 5 }, { 0.75, 11174, 1, 2 }, { 0.05, 11177, 1, 1 } },
    { 46, 50, { 0.20, 11176, 1, 2 }, { 0.75, 11175, 1, 2 }, { 0.05, 11178, 1, 1 } },
    { 51, 55, { 0.22, 11176, 2, 5 }, { 0.75, 16202, 1, 2 }, { 0.03, 14343, 1, 1 } },
    { 56, 60, { 0.22, 16204, 1, 2 }, { 0.75, 16203, 1, 2 }, { 0.03, 14344, 1, 1 } },
    { 61, 65, { 0.22, 16204, 2, 5 }, { 0.75, 16203, 2, 3 }, { 0.03, 14344, 1, 1 } },
}
-- rare, armor and weapons alike
D.BLUE = {
    { 1, 25,  { 1, 10978, 1, 1 } },
    { 26, 30, { 1, 11084, 1, 1 } },
    { 31, 35, { 1, 11138, 1, 1 } },
    { 36, 40, { 1, 11139, 1, 1 } },
    { 41, 45, { 1, 11177, 1, 1 } },
    { 46, 50, { 1, 11178, 1, 1 } },
    { 51, 55, { 1, 14343, 1, 1 } },
    { 56, 65, { 0.995, 14344, 1, 1 }, { 0.005, 20725, 1, 1 } },
}
-- epic, armor and weapons alike (the wiki: 76-80 weapons give 1 Nexus Crystal 33%, 2 at 67%)
D.EPIC = {
    { 40, 45, { 1, 11177, 2, 4 } },
    { 46, 50, { 1, 11178, 2, 4 } },
    { 51, 55, { 1, 14343, 2, 4 } },
    { 56, 60, { 1, 20725, 1, 1 } },
    { 61, 88, { 1, 20725, 1, 2 } },
}
local NO_LOC = { [""] = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BAG = true, INVTYPE_AMMO = true }

-- the outcomes { chance, item, min, max, average } of one item, or nil when the tables have no row for it
function D.Outcomes(quality, ilvl, weapon)
    if type(quality) ~= "number" or type(ilvl) ~= "number" then return nil end
    local t = quality == 2 and (weapon and D.GREEN_WEAPON or D.GREEN_ARMOR) or quality == 3 and D.BLUE or quality == 4 and D.EPIC
    if not t then return nil end
    for _, r in ipairs(t) do
        if ilvl >= r[1] and ilvl <= r[2] then
            local outs = {}
            for i = 3, #r do
                local o = r[i]
                local avg = o[5] or (o[3] + o[4]) / 2
                if quality == 4 and weapon and ilvl >= 76 and ilvl <= 80 then avg = 0.33 * 1 + 0.67 * 2 end
                outs[#outs + 1] = { o[1], o[2], o[3], o[4], avg }
            end
            return outs
        end
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
        local avg = o[5] or (o[3] + o[4]) / 2
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

-- the value for the price block of the tooltip (UI/CraftPrices.lua, decision 675) and, with Shift, the materials;
-- third value: the copper worth (nil without any price) to find the highest price of the block (decision 701)
function D.Text(id, shift)
    if not D.On() then return nil end
    local v, rows, missing, priced = D.Value(id)
    if not v then return nil end
    local text
    if priced == 0 then text = "no auction prices of the materials yet"
    else text = money(v) .. (missing and "  (prices incomplete)" or "") end
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
    return text, more, priced > 0 and v or nil
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
