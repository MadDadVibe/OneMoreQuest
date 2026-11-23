-- One More Quest: Auction Helper, buy mode (decision 264)
-- The switch on top of the auction helper turns it from selling to buying. It suggests only what fits
-- the class, the role and the level, each with what I carry and what it suggests:
--   gear upgrades for every slot (item score against what I wear, only what I can put on right now - level,
--   weapon skill and class from the game's tooltip, decision 431 - up to the gold limit of the Upgrades tab,
--   UI/AuctionUpgrades.lua, decision 637, which also shows the bags), and the stock rows of
--   UI/BuyRules.lua: small, cheap buffs under a price limit per use (decision 431), armor kits for chest,
--   legs, hands and feet without an enchantment, a shield spike for a shield without one.
-- Every row is searched live once the Buy tab is open; the dump of the whole house is not used here (decision 431).
-- Bags too (decision 265): a bigger bag, profession bags, soul bags, quivers and ammo pouches.
-- Two ways to buy: "Fill up" (a click buys what is missing; one button fills everything, one click per
-- item) and "Single" (a click buys one piece). Right click: never suggest it again. A purchase never goes over
-- the price limit of its row (decision 431).
-- A purchase counts at once, even while it waits in the mailbox (decision 271).
-- Buying a commodity: StartCommoditiesPurchase (needs the click), then the price quote comes back and
-- ConfirmCommoditiesPurchase completes it. Single auctions (weapons, bags): a fresh search on the first click,
-- PlaceBid with the buyout on the second (decision 431).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local B = {}
OMQ.AuctionBuy = B

B.TARGET = { potion = 5, scroll = 5, elixir = 10, stone = 10, oil = 2, food = 10, flask = 2, juju = 5, kit = 1, spike = 1 }
B.KIND_LABEL = { potion = "potion", scroll = "scroll", elixir = "elixir", stone = "weapon stone", oil = "weapon oil",
                 food = "buff food", flask = "flask", juju = "juju", kit = "armor kit", spike = "shield spike" }
B.KIND_ORDER = { potion = 1, elixir = 2, flask = 3, food = 4, scroll = 5, stone = 6, oil = 7, kit = 8, spike = 9, juju = 10 }
-- gear only that I can wear right now: no level above mine (decision 431; was 2, decision 402)
B.WEAPON_LEVELS = 0
B.ROWS = 10

local GOLD = { 0.89, 0.71, 0.29 }
local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return GetTime() end
local CA = function() return C_AuctionHouse end
local function AH() return OMQ.AuctionHelper end
local function money(c) return AH().Money(c) end
local function money0(c) return (c and c > 0) and money(c) or "-" end

local function db()
    OMQDB.ah = OMQDB.ah or {}
    OMQDB.ah.never = OMQDB.ah.never or {}
    OMQDB.ah.used = OMQDB.ah.used or {}
    local guid = UnitGUID and UnitGUID("player") or "?"
    OMQDB.ah.used[guid] = OMQDB.ah.used[guid] or {}
    return OMQDB.ah, OMQDB.ah.used[guid]
end
function B.Mode()
    local o = OMQ.db and OMQ.db.options
    return (o and o.ahBuyMode == "single") and "single" or "fill"
end
function B.SetMode(m)
    OMQ.db.options.ahBuyMode = (m == "single") and "single" or "fill"
    AH().Refresh()
end

local function instant(id)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end
local function info(x)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(x) end
    if GetItemInfo then return GetItemInfo(x) end
end
local function count(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, false) or 0 end
    if GetItemCount then return GetItemCount(id) or 0 end
    return 0
end
-- bought at the auction house but still in the mailbox (decision 271): a purchase counts at once
B.MAIL_DAYS = 30
local function mailbox()
    OMQDB.ah = OMQDB.ah or {}
    OMQDB.ah.mail = OMQDB.ah.mail or {}
    local guid = UnitGUID and UnitGUID("player") or "?"
    OMQDB.ah.mail[guid] = OMQDB.ah.mail[guid] or {}
    return OMQDB.ah.mail[guid]
end
local function clock() return (time and time()) or 0 end
-- what I have: in the bags, or bought and on the way (once the bags hold it, the note goes)
function B.Have(id)
    local bags = count(id)
    local m = mailbox()
    local e = m[id]
    if e and (bags >= (e.n or 0) or clock() - (e.t or 0) > B.MAIL_DAYS * 86400) then m[id] = nil; e = nil end
    return e and math.max(bags, e.n) or bags
end
-- the mailbox is open and holds no auction mail with the item any more: it was taken (or used up), the note goes
-- (decision 402) - else a dad who used some of his stock before he went to the mailbox stayed "stocked" for 30 days
B.MAIL_GRACE = 60          -- seconds: the mail of a purchase needs a moment to arrive
function B.CheckMail()
    if not (GetInboxNumItems and GetInboxItem) then return end
    local shown, total = GetInboxNumItems()
    shown = tonumber(shown) or 0
    if total and tonumber(total) and tonumber(total) > shown then return end     -- not every mail is listed: keep the notes
    local inMail = {}
    for i = 1, shown do
        for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local ok, _, id = pcall(GetInboxItem, i, a)
            if ok and type(id) == "number" and not isSecret(id) then inMail[id] = true end
        end
    end
    local m = mailbox()
    for id, e in pairs(m) do
        if not inMail[id] and clock() - (e.t or 0) > B.MAIL_GRACE then m[id] = nil end
    end
end
-- base: what I had when I clicked (if the bags already got it, it is not counted twice)
function B.Bought(id, qty, base)
    if not (id and qty and qty > 0) then return end
    local m = mailbox()
    m[id] = { n = (base or B.Have(id)) + qty, t = clock() }
end
local function level() return UnitLevel and tonumber((UnitLevel("player"))) or 1 end

----------------------------------------------------------------------
-- What fits my class and role
----------------------------------------------------------------------
-- the lines of Data/BuyList.lua a class and role use (decision 431: the groups of UI/BuyRules.lua)
function B.Lines(class, role)
    local out = {}
    for _, g in ipairs((OMQ.BuyRules.Groups(class, role, { stones = { "stone" }, kitSlots = 1, spike = true }))) do out[#out + 1] = g.line end
    return out
end

-- blade or blunt: which stone the main hand weapon takes
local BLADE = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true, [13] = true }
function B.StoneLine(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot or 16)
    if not link or isSecret(link) then return nil end
    local _, _, _, _, _, classID, subID = instant(link)
    if classID ~= 2 then return nil end
    if BLADE[subID] then return "stone_sharp" end
    if BLUNT[subID] then return "stone_weight" end
    return nil
end
-- does this weapon stone fit a weapon in my hands? A sharpening stone takes a blade, a weightstone a
-- blunt weapon (decision 426). true, false, or nil when it is no stone of a line or no weapon can be read
function B.StoneFits(id)
    local line
    for _, key in ipairs({ "stone_sharp", "stone_weight" }) do
        local l = OMQ.BuyLines and OMQ.BuyLines[key]
        for _, e in ipairs(l and l[2] or {}) do if e[1] == id then line = key end end
    end
    if not line then return nil end
    local main, off = B.StoneLine(16), B.StoneLine(17)
    if not main and not off then return nil end
    return main == line or off == line
end

local function enchanted(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if not link or isSecret(link) then return nil end
    local e = tonumber(tostring(link):match("item:%d+:(%d*)") or "") or 0
    return e > 0
end
-- armor kits: chest, legs, hands, feet without an enchantment
function B.KitSlots()
    local n = 0
    for _, slot in ipairs({ 5, 7, 10, 8 }) do if enchanted(slot) == false then n = n + 1 end end
    return n
end
function B.ShieldWithoutSpike()
    local link = GetInventoryItemLink and GetInventoryItemLink("player", 17)
    if not link or isSecret(link) then return false end
    local _, _, _, equipLoc = instant(link)
    return equipLoc == "INVTYPE_SHIELD" and enchanted(17) == false
end

-- the best item of a line for my level
-- buffs that do not stack (decision 284)
-- 1. a class that buffs the same stat itself needs no consumable for it (Arcane Intellect, Power Word:
--    Fortitude, Divine Spirit); only once it knows the spell
B.CLASS_BUFFS = {
    MAGE   = { { lines = { "s_int" }, spells = { 1459, 1460, 1461, 10156, 10157 } } },     -- elixirs stay: Greater Intellect beats ranks 1-4
    PRIEST = { { lines = { "s_sta" }, spells = { 1243, 1244, 1245, 2791, 10937, 10938 } },
               { lines = { "s_spi", "e_spi" }, spells = { 14752, 14818, 14819, 27841 } } },   -- e_spi: decision 591
}
-- 2. consumables that do not stack with each other: once one of them is in stock (or bought and on
--    its way), the others are not suggested
-- (decision 591, the same value does not stack: the scroll and the elixir of one stat)
B.EXCLUSIVE = { { "e_def", "s_prot" }, { "e_int", "s_int" }, { "e_spi", "s_spi" }, { "e_str", "s_str" }, { "e_agi", "s_agi" } }
local function knowsSpell(id)
    if IsPlayerSpell then local ok, k = pcall(IsPlayerSpell, id); if ok and k then return true end end
    if IsSpellKnown then local ok, k = pcall(IsSpellKnown, id); if ok and k then return true end end
    return false
end
local lineOfItem
function B.LineOf(id)
    if not lineOfItem then
        lineOfItem = {}
        for key, L in pairs(OMQ.BuyLines or {}) do
            for _, it in ipairs(L[2]) do lineOfItem[it[1]] = lineOfItem[it[1]] or key end
        end
    end
    return lineOfItem[id]
end
local function lineStock(line)
    local L = OMQ.BuyLines and OMQ.BuyLines[line]
    local n = 0
    for _, it in ipairs(L and L[2] or {}) do n = n + B.Have(it[1]) end
    return n
end
-- the lines left out for me: set of line keys
function B.Excluded(class, lines)
    local out = {}
    for _, b in ipairs(B.CLASS_BUFFS[class or ""] or {}) do
        local known = false
        for _, id in ipairs(b.spells) do if knowsSpell(id) then known = true; break end end
        if known then for _, l in ipairs(b.lines) do out[l] = true end end
    end
    for _, g in ipairs(B.EXCLUSIVE) do
        local stocked = {}
        for _, l in ipairs(g) do if not out[l] and lineStock(l) > 0 then stocked[l] = true end end   -- also one bought before
        if next(stocked) then
            for _, l in ipairs(g) do if not stocked[l] then out[l] = true end end
        end
    end
    return out
end

-- (the best item of a line for my level is chosen by UI/BuyRules.lua since decision 431)

-- what kind of buff item this is: from the buy list, or a buff food the list does not know (decision 278).
-- A food (class 0, subclass 5) whose tooltip promises "Well Fed" counts as buff food - WoW Forever has
-- foods the Questie data does not list. The answer is kept for the session.
B.WELL_FED = 19705
B.WELL_FED_WORDS = { "well fed", "satt" }       -- English and German tooltip wording, besides the buff's own name
local foodSeen = {}
local function tipText(id)
    local T = C_TooltipInfo
    if not (T and T.GetItemByID) then return nil end
    local ok, data = pcall(T.GetItemByID, id)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local parts = {}
    for _, l in ipairs(data.lines) do
        local t = l.leftText
        if type(t) == "string" and not (issecretvalue and issecretvalue(t)) then parts[#parts + 1] = t end
    end
    return table.concat(parts, "\n"):lower()
end
function B.IsBuffFood(id)
    if foodSeen[id] ~= nil then return foodSeen[id] end
    local _, _, _, _, _, classID, subID = instant(id)
    if classID ~= 0 or subID ~= 5 then foodSeen[id] = false; return false end
    local text = tipText(id)
    if not text then return false end                       -- not known yet: ask again later
    local words = {}
    local wf = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(B.WELL_FED) or (GetSpellInfo and (GetSpellInfo(B.WELL_FED)))
    if type(wf) == "string" and wf ~= "" then words[#words + 1] = wf:lower() end
    for _, w in ipairs(B.WELL_FED_WORDS) do words[#words + 1] = w end
    local yes = false
    for _, w in ipairs(words) do
        if text:find(w, 1, true) then yes = true; break end
    end
    foodSeen[id] = yes
    return yes
end
-- does this buff food still give the +5% XP from kills? (decision 475) Its tooltip is read in the game: a food
-- whose readable text names no experience is left out of the cheapest XP food. The test only counts once one food
-- of the list has shown such a line this session, so a client whose food tooltips never name it keeps the list.
-- Answers: true (XP line), false (readable, no XP line), nil (tooltip not loaded yet).
B.XP_WORDS = { "experience", "erfahrung" }       -- English and German tooltip wording
local xpSeen = {}
B.xpProof = nil                                  -- the first food whose tooltip named experience
function B.FoodXP(id)
    if xpSeen[id] ~= nil then return xpSeen[id] end
    local text = tipText(id)
    if not text or text == "" then return nil end
    local yes = false
    for _, w in ipairs(B.XP_WORDS) do
        if text:find(w, 1, true) then yes = true; break end
    end
    xpSeen[id] = yes
    if yes and not B.xpProof then B.xpProof = id end
    return yes
end
-- is the food out of the cheapest XP food row? only when its tooltip has no XP line and another food's has one
function B.NoXP(id)
    for _, f in ipairs(OMQ.BuyFoods or {}) do if B.xpProof then break end; B.FoodXP(f[1]) end
    return B.xpProof ~= nil and B.FoodXP(id) == false
end
function B._ResetXP() for k in pairs(xpSeen) do xpSeen[k] = nil end; B.xpProof = nil end
-- /omq ah food: what the tooltips say about the XP of every buff food up to my level
function B.FoodReport()
    local lines = { "buff foods with +5% XP (tooltip check): " .. (B.xpProof and ("on, proof item " .. B.xpProof) or "off, no food tooltip names experience yet") }
    local lvl = UnitLevel and UnitLevel("player") or 60
    for _, f in ipairs(OMQ.BuyFoods or {}) do
        if f[2] <= lvl then
            local x = B.FoodXP(f[1])
            local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(f[1]) or ("item " .. f[1])
            lines[#lines + 1] = string.format("  %s (%d): %s", tostring(name), f[1], x == true and "XP" or x == false and "NO XP - left out" or "tooltip not loaded")
        end
    end
    return lines
end
function OMQ.BuyKind(id)
    if not id then return nil end
    local k = OMQ.BuyKnown and OMQ.BuyKnown[id]
    if k then return k end
    if B.IsBuffFood(id) then return "food" end
    return nil
end

-- remember buff items found in the bags
function B.LearnBags()
    local C = C_Container
    if not (C and C.GetContainerNumSlots) then return end
    local _, used = db()
    for bag = 0, OMQ.LastBag() do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local it = C.GetContainerItemInfo(bag, slot)
            local kind = it and it.itemID and OMQ.BuyKind(it.itemID)
            if kind then used[it.itemID] = kind end
        end
    end
end

----------------------------------------------------------------------
-- The rows
----------------------------------------------------------------------
local rows, byId = {}, {}
local foods = {}           -- the buff foods for the cheapest-food row (decision 268)
local alts = {}            -- the weaker item of each line, priced to offer it when the best is dear (decision 269)
B._alts = alts
B._foods = foods
local weapons = {}
B._rows, B._weapons = rows, weapons

local function rowFor(id, kind, line, target, mine)
    local r = byId[id]
    if not r then
        local A = CA()
        r = { itemID = id, key = "b" .. id, state = "price", anyKey = true, onResult = nil,
              itemKey = (A and A.MakeItemKey and A.MakeItemKey(id)) or { itemID = id } }
        byId[id] = r
    end
    r.kind, r.line, r.target, r.mine, r.cheaper = kind, line, target, mine, nil
    return r
end

-- the fill-up target of an item on my buy list, nil when it is not on it (decision 274: selling keeps it)
function B.TargetFor(id)
    for _, r in ipairs(rows) do
        if r.itemID == id then return r.target end
    end
    for _, r in ipairs(alts) do                      -- every item of my groups, also the one not shown (decision 431)
        if r.itemID == id then return r.target end
    end
    return nil
end

-- the price of one piece as the live search saw it: a number, false (nobody sells it) or nil (not asked yet)
local function priceOf(id)
    local r = byId[id]
    if not r or r.state == "price" then return nil end
    if r.state ~= "ok" then return false end
    local o = r.offers and r.offers[1]
    return o and o.unit or false
end
B.PriceOf = priceOf

-- the stones my weapons take: the main hand's kind, and the off hand's when it is another kind (decision 431)
function B.MyStones()
    local main, off = B.StoneLine(16), B.StoneLine(17)
    local out = {}
    if main then out[#out + 1] = main end
    if off and off ~= main then out[#out + 1] = off end
    return out
end

-- the stock rows (decision 431): one per group of UI/BuyRules.lua, the strongest item under the limit; every item
-- that could be the one is priced live first (cands), a group waits while a stronger item is not priced yet
function B.Build()
    for i = #rows, 1, -1 do rows[i] = nil end
    for i = #alts, 1, -1 do alts[i] = nil end
    local R = OMQ.BuyRules
    local SC = OMQ.Score
    local class = SC and SC.MyClass() or select(2, UnitClass("player"))
    local role = SC and SC.MyRole() or "damage"
    local lvl = level()
    local never = (db()).never
    local seen = {}
    local function add(r)
        if not seen[r.itemID] and not never[r.itemID] then seen[r.itemID] = true; rows[#rows + 1] = r; r.order = #rows end
    end
    local all = {}
    for _, g in ipairs((R.Groups(class, role, {}))) do all[#all + 1] = g.line end
    local excluded = B.Excluded(class, all)
    local groups, prof = R.Groups(class, role, { stones = B.MyStones(), kitSlots = B.KitSlots(),
        spike = B.ShieldWithoutSpike(), excluded = excluded, level = lvl })
    B.pending = 0
    for _, g in ipairs(groups) do
        local ids = {}
        for _, id in ipairs(R.Candidates(g, lvl)) do
            if not never[id] then
                ids[#ids + 1] = id
                local c = rowFor(id, g.kind, g.line, g.target, false)
                c.cap = g.cap
                alts[#alts + 1] = c
            end
        end
        local id, waiting = R.Pick(ids, g.cap, priceOf)
        if id then add(byId[id]) elseif waiting then B.pending = B.pending + 1 end
    end
    -- buff food (decision 431): the cheapest food with Well Fed, and the class food under the limit;
    -- the class food alone when it costs at most 50% more
    for _, f in ipairs(foods) do f.xp = nil end
    local xp = B.CheapestFood(lvl)
    local fg = { line = R.FoodLine(prof), kind = "food", cap = R.CapFor("food", lvl) }
    local fids = {}
    for _, id in ipairs(R.Candidates(fg, lvl)) do
        if not never[id] then
            fids[#fids + 1] = id
            local c = rowFor(id, "food", fg.line, B.TARGET.food or 10, false)
            c.cap = fg.cap
            alts[#alts + 1] = c
        end
    end
    local classFood, waiting = R.Pick(fids, fg.cap, priceOf)
    if waiting then B.pending = B.pending + 1 end
    local xpId, cId = R.Foods(xp and xp.itemID, xp and priceOf(xp.itemID), classFood, classFood and priceOf(classFood))
    if xpId then
        local r = rowFor(xpId, "food", "xp", B.TARGET.food or 10, false)
        r.xp, r.cap = true, nil
        add(r)
    end
    if cId then add(byId[cId]) end
    for _, r in ipairs(rows) do
        r.have = B.Have(r.itemID)
        r.need = math.max(0, r.target - r.have)
        r.itemKey = r.itemKey or { itemID = r.itemID }
    end
    table.sort(rows, function(a, b)
        local ka, kb = B.KIND_ORDER[a.kind] or 99, B.KIND_ORDER[b.kind] or 99
        if ka ~= kb then return ka < kb end
        return (a.order or 0) < (b.order or 0)
    end)
    return rows
end

-- the offers of a search: commodities by unit price, single auctions by buyout
local function readOffers(r)
    local A = CA()
    local offers = {}
    local nc = A.GetNumCommoditySearchResults and A.GetNumCommoditySearchResults(r.itemID) or 0
    if r.commodity ~= false and nc > 0 then
        r.commodity = true
        for i = 1, nc do
            local x = A.GetCommoditySearchResultInfo(r.itemID, i)
            -- my own pieces cannot be bought: the game leaves them out of a purchase, so they do not count (fix 562)
            local q = x and x.quantity and x.quantity - (x.numOwnerItems or 0)
            if x and x.unitPrice and q and q > 0 then offers[#offers + 1] = { unit = x.unitPrice, qty = q } end
        end
    else
        local ni = A.GetNumItemSearchResults and A.GetNumItemSearchResults(r.itemKey) or 0
        if ni > 0 then r.commodity = false end
        for i = 1, ni do
            local x = A.GetItemSearchResultInfo(r.itemKey, i)
            if x and x.buyoutAmount and x.buyoutAmount > 0 then
                offers[#offers + 1] = { auctionID = x.auctionID, buyout = x.buyoutAmount, qty = x.quantity or 1,
                                        unit = math.floor(x.buyoutAmount / math.max(1, x.quantity or 1)), link = x.itemLink }
            end
        end
        table.sort(offers, function(a, b) return a.unit < b.unit end)
    end
    return offers
end

B.ReadOffers = readOffers                     -- the Shopping tab reads its offers the same way (decision 551)
local function onStock(r)
    r.offers = readOffers(r)
    r.checkedAt = now()
    r.state = #r.offers > 0 and "ok" or "none"
    B.Build()                                   -- the cheapest food may have changed (decision 268)
end

-- what n pieces cost, and how many are there; a row with a price limit counts only the offers under it (decision 431)
function B.Cost(r, n)
    local total, got = 0, 0
    for _, o in ipairs(r.offers or {}) do
        if got >= n then break end
        if r.cap and o.unit and o.unit > r.cap then break end
        local take = r.commodity and math.min(o.qty, n - got) or o.qty
        total = total + (r.commodity and o.unit * take or o.buyout)
        got = got + take
    end
    return total, got
end

----------------------------------------------------------------------
-- Gear upgrades (decision 637, the Upgrades tab; before: weapon upgrades only, decision 264): browses for the
-- weapons, the wands of cloth casters and every armor kind I can wear, up to my level; every result is scored
-- against what I wear (LootPreview.GainAt: the slot it would go into, rings and trinkets against the weaker one,
-- an empty slot counts the full value). The best few of every slot are then looked at closely (their real offers).
----------------------------------------------------------------------
-- what is scanned only on request (decision 290): the gear browses and the bag browse
B.want = { weapons = false, bags = false }
local browse = { state = "idle", gen = 0 }
local candidates = {}
B._browse, B._candidates = browse, candidates

-- the slot groups of the Upgrades tab, in the order of the character window; rings and trinkets one group each
B.GEAR_GROUPS = {
    { key = "head", label = "Head", slots = { 1 } }, { key = "neck", label = "Neck", slots = { 2 } },
    { key = "shoulder", label = "Shoulders", slots = { 3 } }, { key = "back", label = "Back", slots = { 15 } },
    { key = "chest", label = "Chest", slots = { 5 } }, { key = "wrist", label = "Wrists", slots = { 9 } },
    { key = "hands", label = "Hands", slots = { 10 } }, { key = "waist", label = "Waist", slots = { 6 } },
    { key = "legs", label = "Legs", slots = { 7 } }, { key = "feet", label = "Feet", slots = { 8 } },
    { key = "finger", label = "Rings", slots = { 11, 12 } }, { key = "trinket", label = "Trinkets", slots = { 13, 14 } },
    { key = "main", label = "Main hand", slots = { 16 } }, { key = "off", label = "Off hand", slots = { 17 } },
    { key = "ranged", label = "Ranged", slots = { 18 } },
}
local groupOfSlot = {}
for _, g in ipairs(B.GEAR_GROUPS) do for _, s in ipairs(g.slots) do groupOfSlot[s] = g.key end end
function B.GroupOf(slot) return groupOfSlot[slot or 0] end
B.GEAR_PICKS = 3          -- items shown per slot (decision 637)
B.GEAR_CHECK = 3          -- items per slot looked at closely
B.GEAR_MIN_LEVELS = 8     -- the browses start this many levels below mine

-- the gold limit per item (decision 637): 10s, 50s, 1g, 3g, 5g or no limit (0); per character, 1g at first.
-- Never more than the gold I carry. It also holds for the bags.
B.LIMITS = { 1000, 5000, 10000, 30000, 50000, 0 }
B.LIMIT_DEFAULT = 10000
function B.Limit()
    local ah = db()
    ah.upgLimit = ah.upgLimit or {}
    local v = ah.upgLimit[UnitGUID and UnitGUID("player") or "?"]
    return v or B.LIMIT_DEFAULT
end
function B.Budget()
    local gold = GetMoney and GetMoney() or 0
    local lim = B.Limit()
    if lim <= 0 then return gold end
    return math.min(lim, gold)
end
local budget = B.Budget

-- the armor kinds a class can wear (item class 4): 0 miscellaneous (rings, necks, trinkets, off-hand items),
-- 1 cloth (also every cloak), 2 leather, 3 mail, 4 plate, 6 shields.
-- Fix 658: only the best kind I may wear at my level is browsed (plate from 40, mail for hunters and shamans from
-- 40: OMQ.Score's table), with the misc items, the cloaks (cloth, the back slot only) and the shields; the lighter
-- kinds were 3 or 4 browses more, each asked again slot by slot once its page was full.
B.ARMOR_ORDER = { 4, 3, 2, 1 }
B.ARMOR_FALLBACK = {
    WARRIOR = { 1, 2, 3, 4, 6 }, PALADIN = { 1, 2, 3, 4, 6 }, SHAMAN = { 1, 2, 3, 6 }, HUNTER = { 1, 2, 3 },
    ROGUE = { 1, 2 }, DRUID = { 1, 2 }, PRIEST = { 1 }, MAGE = { 1 }, WARLOCK = { 1 },
}
-- may the class wear armor kind sub at level lvl?
local function mayWear(class, sub, lvl)
    local SC = OMQ.Score
    local t = SC and SC.ARMOR and SC.ARMOR[sub]
    if t then return t[class] ~= nil and (lvl or 1) >= t[class] end
    for _, s in ipairs(B.ARMOR_FALLBACK[class or ""] or { 1 }) do if s == sub then return true end end
    return false
end
-- the best body armor kind at my level (cloth when nothing else)
function B.BestArmor(class, lvl)
    for _, sub in ipairs(B.ARMOR_ORDER) do
        if mayWear(class, sub, lvl) then return sub end
    end
    return 1
end

local function gainAt(link, equipLoc)
    local LP = OMQ.LootPreview
    local f = LP and (LP.GainAt or LP.Gain)
    if not f then return nil end
    local ok, g, at = pcall(f, link, equipLoc)
    if not ok then return nil end
    if g and not at then                               -- no slot named: the first slot of the item's kind
        local s = OMQ.Compare and OMQ.Compare.SLOTS and OMQ.Compare.SLOTS[equipLoc or ""]
        at = s and s[1]
    end
    return g, at
end

-- cloth casters also look at wands (decision 298): a browse of its own, so the cheap weapons do not crowd them out
B.WAND_CLASSES = { PRIEST = true, MAGE = true, WARLOCK = true }
B.WAND_SUBCLASS = 19
function B.WantsWands(class)
    local SC = OMQ.Score
    class = class or (SC and SC.MyClass())
    return B.WAND_CLASSES[class or ""] and true or false
end

-- the browses of one gear search: the weapons, the wands, the misc items, the best armor kind at my level, the
-- cloaks (when that kind is not cloth) and the shields (fix 658)
function B.GearSearches(class, lvl)
    local SC = OMQ.Score
    class = class or (SC and SC.MyClass()) or select(2, UnitClass("player"))
    lvl = lvl or level()
    local out = { { 2 } }
    if B.WantsWands(class) then out[#out + 1] = { 2, B.WAND_SUBCLASS } end
    out[#out + 1] = { 4, 0 }
    local best = B.BestArmor(class, lvl)
    out[#out + 1] = { 4, best }
    if best ~= 1 then
        local E = Enum and Enum.InventoryType
        out[#out + 1] = { 4, 1, (E and E.IndexCloakType) or 16 }
    end
    if mayWear(class, 6, lvl) then out[#out + 1] = { 4, 6 } end
    return out
end

-- the link to score a browse result with: a random suffix ("of the Bear") is part of the key, when the game names it
function B.KeyLink(k)
    local id = k and k.itemID
    if not id then return nil end
    local s = k.itemSuffix
    if type(s) == "number" and s ~= 0 then return "item:" .. id .. ":0:0:0:0:0:" .. s end
    return "item:" .. id
end

local function offerResult(x)
    x.state = "done"
    local offers = readOffers(x)
    x.offer, x.gain, x.slot = B._bestGearOffer(x, offers)
    x.offers = #offers
end

-- an item that comes with a random suffix ("of the Bear", "des Bären", fix 638): the plain item has no stats of its
-- own, only each offer tells what it carries. The game's tooltip of the plain item says "<Random enchantment>"; without
-- that line, a green or better item whose stats are only armor counts too. nil while the game has not loaded it.
B.RANDOM_WORDS = { "random enchant", "zufällige verzauberung", "zufaellige verzauberung" }
B.PLAIN_STATS = { RESISTANCE0_NAME = true, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = true }
function B.RandomSuffix(id)
    local T = C_TooltipInfo
    if T and T.GetItemByID then
        local ok, data = pcall(T.GetItemByID, id)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            local want = ITEM_RANDOM_ENCHANT and ITEM_RANDOM_ENCHANT:lower()
            for _, l in ipairs(data.lines) do
                local t = type(l.leftText) == "string" and not isSecret(l.leftText) and l.leftText:lower()
                if t then
                    if want and t:find(want, 1, true) then return true end
                    for _, w in ipairs(B.RANDOM_WORDS) do if t:find(w, 1, true) then return true end end
                end
            end
        end
    end
    local quality = select(3, info(id))
    if not quality then return nil end
    if quality < 2 then return false end
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not fn then return false end
    local ok, t = pcall(fn, "item:" .. id)
    if not ok or type(t) ~= "table" then return false end
    for k in pairs(t) do if not B.PLAIN_STATS[k] then return false end end
    return true
end
B.GEAR_SUFFIX = 5         -- items with a random suffix looked at closely per slot (fix 638), the highest item level first

-- what the last gear search saw (fix 638): /omq ah upg prints it, OMQDB.ah.upgLog keeps it
local function upgLog()
    local ah = db()
    ah.upgLog = ah.upgLog or {}
    return ah.upgLog
end
B.UpgLog = upgLog

-- every browse result scored; per slot group the best GEAR_CHECK by score and the GEAR_SUFFIX random-suffix items
-- with the highest item level are looked at closely, the best of every slot first in turn
local function judgeGear(list)
    for i = #candidates, 1, -1 do candidates[i] = nil end
    local SC = OMQ.Score
    local class = SC and SC.MyClass()
    local lvl = level()
    local bySlot, rnd, seen = {}, {}, {}
    local log = upgLog()
    log.at, log.limit, log.budget, log.level, log.results = (time and time()) or 0, B.Limit(), budget(), lvl, #list
    local drop = { dear = 0, level = 0, use = 0, slot = 0, zero = 0, kind = 0 }
    log.drop = drop
    for _, res in ipairs(list) do
        local id = res.itemKey and res.itemKey.itemID
        local _, _, _, equipLoc, _, classID = instant(id or 0)
        local minLevel = select(5, info(id or 0))
        local k = id and AH()._KeyString(res.itemKey)
        if not (id and (classID == 2 or classID == 4)) then drop.kind = drop.kind + 1
        elseif seen[k] then
        elseif (res.minPrice or 0) > budget() then drop.dear = drop.dear + 1
        elseif minLevel and minLevel > lvl + B.WEAPON_LEVELS then drop.level = drop.level + 1
        elseif SC and not SC.CanUse("item:" .. id, class, lvl) then drop.use = drop.use + 1
        else
            seen[k] = true
            local link = B.KeyLink(res.itemKey)
            local g, at = gainAt(link, equipLoc)
            local grp = B.GroupOf(at)
            local random = (res.itemKey.itemSuffix or 0) == 0 and B.RandomSuffix(id)
            local c = { itemKey = res.itemKey, itemID = id, equipLoc = equipLoc, est = g or 0, group = grp, random = random or nil,
                        ilvl = res.itemKey.itemLevel or select(4, info(id)) or 0, price = res.minPrice or 0 }
            if not grp then drop.slot = drop.slot + 1
            elseif random then rnd[grp] = rnd[grp] or {}; table.insert(rnd[grp], c)
            elseif (g or 0) > 0 or (g == 0 and random == nil) then bySlot[grp] = bySlot[grp] or {}; table.insert(bySlot[grp], c)
            else drop.zero = drop.zero + 1 end
        end
    end
    for _, t in pairs(bySlot) do table.sort(t, function(a, b) return a.est > b.est end) end
    for _, t in pairs(rnd) do table.sort(t, function(a, b) if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end return a.price < b.price end) end
    local slots = {}
    log.slots = slots
    for rank = 1, math.max(B.GEAR_CHECK, B.GEAR_SUFFIX) do
        for _, g in ipairs(B.GEAR_GROUPS) do
            for _, c in ipairs({ rank <= B.GEAR_CHECK and bySlot[g.key] and bySlot[g.key][rank] or false,
                                 rank <= B.GEAR_SUFFIX and rnd[g.key] and rnd[g.key][rank] or false }) do
                if c then
                    c.key, c.state, c.commodity, c.onResult = "w" .. AH()._KeyString(c.itemKey), "price", false, offerResult
                    candidates[#candidates + 1] = c
                end
            end
        end
    end
    for _, g in ipairs(B.GEAR_GROUPS) do
        local n1, n2 = #(bySlot[g.key] or {}), #(rnd[g.key] or {})
        if n1 + n2 > 0 then slots[#slots + 1] = string.format("%s: %d scored, %d with a random suffix", g.key, n1, n2) end
    end
end
B.JudgeGear = judgeGear

-- the slots of an armor kind (Enum.InventoryType, the game's numbers as fallback), for the search slot by slot (fix 640)
B.PAGE_FULL = 500
local function inv(name, n) local E = Enum and Enum.InventoryType; return (E and E[name]) or n end
function B.InvTypes(sub)
    if sub == 0 then   -- miscellaneous: necks, rings, trinkets, off-hand items
        return { inv("IndexNeckType", 2), inv("IndexFingerType", 11), inv("IndexTrinketType", 12), inv("IndexHoldableType", 23) }
    end
    if sub == 6 then return {} end
    local t = { inv("IndexHeadType", 1), inv("IndexShoulderType", 3), inv("IndexChestType", 5), inv("IndexRobeType", 20),
                inv("IndexWaistType", 6), inv("IndexLegsType", 7), inv("IndexFeetType", 8), inv("IndexWristType", 9), inv("IndexHandType", 10) }
    if sub == 1 then t[#t + 1] = inv("IndexCloakType", 16) end   -- every cloak is cloth
    return t
end

local function onBrowse(gen)
    if gen ~= browse.gen then return end                  -- the limit changed meanwhile: a new search runs
    local A = CA()
    local list = A.GetBrowseResults and A.GetBrowseResults() or {}
    browse.results = browse.results or {}
    for _, res in ipairs(list) do browse.results[#browse.results + 1] = res end
    local sch = browse.searches and browse.searches[(browse.step or 0) + 1]
    local full = A.HasFullBrowseResults and A.HasFullBrowseResults()
    browse.lines = browse.lines or {}
    browse.lines[#browse.lines + 1] = string.format("%s.%s%s: %d lines%s", tostring(sch and sch[1]), tostring(sch and sch[2]),
        (sch and sch[3]) and ("/" .. sch[3]) or "", #list,
        full == false and " (more pages)" or "")
    -- fix 640: a full page (500 lines, the cheapest first) misses the better items of an armor kind: the kind is
    -- asked again slot by slot (the game's own category filters, e.g. Cloth > Head), right after this search
    if sch and sch[1] == 4 and not sch[3] and (#list >= B.PAGE_FULL or full == false) then
        local at = (browse.step or 0) + 2
        for _, inv in ipairs(B.InvTypes(sch[2])) do table.insert(browse.searches, at, { 4, sch[2], inv }); at = at + 1 end
    end
    browse.step = (browse.step or 0) + 1
    if browse.step < #(browse.searches or {}) then browse.state = "next"; return end
    browse.state = "done"
    list = browse.results
    browse.results = nil
    judgeGear(list)
    upgLog().browses, browse.lines = browse.lines, nil
end

-- the level a weapon offer needs; nil while the game has not loaded the item (it is asked for)
local function needLevel(link)
    local need = select(5, info(link))
    if need == nil and C_Item and C_Item.RequestLoadItemDataByID then
        local id = tonumber(tostring(link):match("item:(%d+)"))
        if id then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    return need
end
B.NeedLevel = needLevel
-- can I put it on right now (decision 431)? The game's tooltip writes in red what stops me: the level, the weapon
-- skill I have not learned, the class. true, false, or nil while the game has not loaded the item.
-- No tooltip data on this client: the level and the class decide.
local function red(c)
    if type(c) ~= "table" then return false end
    local r, g, b = c.r, c.g, c.b
    if type(r) ~= "number" or isSecret(r) or isSecret(g) or isSecret(b) then return false end
    return r > 0.9 and (g or 1) < 0.3 and (b or 1) < 0.3
end
function B.CanEquipNow(link)
    if not link then return nil end
    local need = needLevel(link)
    if need and need > level() then return false end
    local SC = OMQ.Score
    if SC and SC.CanUse and not SC.CanUse(link, SC.MyClass(), level()) then return false end
    local T = C_TooltipInfo
    if not (T and T.GetHyperlink) then return need ~= nil or nil end
    local ok, data = pcall(T.GetHyperlink, link)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines == 0 then return nil end
    for _, l in ipairs(data.lines) do
        if red(l.leftColor) or red(l.rightColor) then return false end
    end
    return true
end

-- every gear upgrade found, the biggest first (each with its offer, gain and slot group)
function B.Gear()
    local out = {}
    local never = (db()).never
    local maxLevel = level() + B.WEAPON_LEVELS
    for _, c in ipairs(candidates) do
        -- only what I can wear: an offer whose level is not known yet waits (decision 402)
        local need = c.offer and needLevel(c.offer.link)
        if c.offer and c.gain and need and need <= maxLevel and B.CanEquipNow(c.offer.link) == true
            and not never[c.itemID] and not c.bought then out[#out + 1] = c end
    end
    table.sort(out, function(a, b) return a.gain > b.gain end)
    return out
end
-- /omq ah upg (fix 638): what the last gear search saw and what became of each item looked at closely
function B.UpgReport()
    local log = upgLog()
    local d = log.drop or {}
    local lines = {
        string.format("v%s upgrades: level %s, limit %s, budget %s, search %s", tostring(OMQ.version), tostring(log.level),
            money0(log.limit or 0), money0(log.budget or 0), tostring(browse.state)),
        string.format("results %d: too dear %d, level too high %d, not for my class %d, no slot %d, no gain %d, not gear %d",
            log.results or 0, d.dear or 0, d.level or 0, d.use or 0, d.slot or 0, d.zero or 0, d.kind or 0),
    }
    for _, l in ipairs(log.browses or {}) do lines[#lines + 1] = "  browse " .. l end
    for _, l in ipairs(log.slots or {}) do lines[#lines + 1] = "  " .. l end
    local never = (db()).never
    for _, c in ipairs(candidates) do
        local name = select(1, info(c.offer and c.offer.link or c.itemID)) or ("item " .. c.itemID)
        local why
        if c.state == "price" then why = "waiting"
        elseif not c.offer then why = string.format("no offer under the limit with a gain (%d offers)", c.offers or 0)
        elseif never[c.itemID] then why = "never (right click)"
        elseif c.bought then why = "bought"
        elseif needLevel(c.offer.link) == nil then why = "not loaded yet"
        elseif B.CanEquipNow(c.offer.link) ~= true then why = "can not wear it now"
        else why = "shown +" .. tostring(c.gain) .. " " .. money0(c.offer.buyout) end
        lines[#lines + 1] = string.format("  %s %s (%d)%s est %s: %s", tostring(c.group), name, c.itemID,
            c.random and " random" or "", tostring(c.est), why)
    end
    return lines
end

-- the best GEAR_PICKS of every slot group, in the order of B.GEAR_GROUPS: { { group, items }, ... }
function B.GearSlots()
    local by = {}
    for _, c in ipairs(B.Gear()) do
        local k = c.slot and B.GroupOf(c.slot) or c.group
        if k then
            by[k] = by[k] or {}
            if #by[k] < B.GEAR_PICKS then by[k][#by[k] + 1] = c end
        end
    end
    local out = {}
    for _, g in ipairs(B.GEAR_GROUPS) do
        if by[g.key] then out[#out + 1] = { group = g, items = by[g.key] } end
    end
    return out
end

----------------------------------------------------------------------
-- Bags (decision 265): a bigger bag for the smallest one (or an empty bag slot), the bag of a
-- profession I have (herbs, enchanting, engineering), a soul bag for warlocks, a quiver or ammo pouch
-- for hunters - each only when none of that kind is worn or a bigger one is on sale, at most half
-- my gold. Slots come from the item's tooltip ("16 Slot Bag"), in the client's language.
----------------------------------------------------------------------
local bagBrowse = { state = "idle", gen = 0 }
local bagCands = {}
B._bagBrowse, B._bagCands = bagBrowse, bagCands
B.BAG_ROWS = 6
B.BAG_LABEL = { ["1/0"] = "bag", ["1/1"] = "soul bag", ["1/2"] = "herb bag", ["1/3"] = "enchanting bag", ["1/4"] = "engineering bag",
                ["11/2"] = "quiver", ["11/3"] = "ammo pouch" }
B.PROF_BAG = { [182] = 2, [333] = 3, [202] = 4 }       -- skill line -> bag subclass (herbs, enchanting, engineering)

-- The reagent bag (decision 330; "Handwerkstaschen" in the German client): the general bag for every crafting
-- reagent, worn in its own slot (Enum.BagIndex.ReagentBag). It is a container subclass of its own; which number
-- it has the game tells: the subclass names of the containers (the auction house's category list) are read and
-- the one that names reagents or crafting is the reagent bag. Failing that, the reagent bag I wear tells it.
B.REAGENT_WORDS = { "reagent", "reagenz", "crafting", "handwerk" }
local reagentKey
function B.ResetReagentKey() reagentKey = nil end
local function subClassName(c, sub)
    local f = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    if not f then return nil end
    local ok, n = pcall(f, c, sub)
    if ok and type(n) == "string" and n ~= "" and not isSecret(n) then return n end
end
-- the container categories of the game: { { sub = 0, name = "Bag" }, ... }
function B.ContainerSubclasses()
    local out = {}
    for sub = 0, 20 do
        local n = subClassName(1, sub)
        if n then out[#out + 1] = { sub = sub, name = n } end
    end
    return out
end
function B.ReagentKey()
    if reagentKey then return reagentKey end
    local E = Enum and Enum.ItemContainerSubclass
    if E and type(E.Reagent) == "number" then reagentKey = "1/" .. E.Reagent; return reagentKey end
    for _, c in ipairs(B.ContainerSubclasses()) do
        local l = c.name:lower()
        for _, w in ipairs(B.REAGENT_WORDS) do
            if l:find(w, 1, true) then reagentKey = "1/" .. c.sub; return reagentKey end
        end
    end
    local R = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    local C = C_Container
    local inv = type(R) == "number" and C and C.ContainerIDToInventoryID and C.ContainerIDToInventoryID(R)
    local id = inv and GetInventoryItemID and GetInventoryItemID("player", inv)
    if id then
        local _, _, _, _, _, classID, sub = instant(id)
        if classID == 1 and (sub or 0) > 4 then reagentKey = "1/" .. sub; return reagentKey end
    end
    return nil
end
function B.KindLabel(k)
    if k and k == B.ReagentKey() then return "reagent bag" end
    return B.BAG_LABEL[k]
end

-- The tooltip line with the slot count, from the game's own format CONTAINER_SLOTS (decision 327). The
-- format may use positional arguments ("%2$s ... %1$d", common in German); they are turned into plain
-- placeholders first, then everything else is escaped. A format that still can not be used falls back to
-- "a number at the start of the line".
function B.SlotPattern(f)
    f = f or CONTAINER_SLOTS or "%d Slot %s"
    local p = f:gsub("%%%d+%$d", "\001"):gsub("%%d", "\001"):gsub("%%%d+%$s", "\002"):gsub("%%s", "\002")
    p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = "^" .. p:gsub("\001", "(%%d+)"):gsub("\002", ".+") .. "$"
    if not pcall(string.match, "", p) then p = "^(%d+)%s" end
    return p
end
local slotPattern
function B.ResetSlotPattern() slotPattern = nil end
function B.BagSlots(id)
    if not slotPattern then slotPattern = B.SlotPattern() end
    local T = C_TooltipInfo
    if not (T and T.GetItemByID) then return nil end
    local ok, data = pcall(T.GetItemByID, id)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, l in ipairs(data.lines) do
        local t = l.leftText
        if type(t) == "string" and not isSecret(t) then
            local ok2, m = pcall(string.match, t, slotPattern)
            local n = ok2 and tonumber(m or "")
            if n then return n end
        end
    end
    return nil
end

-- what I wear in the four bag slots: { normal = smallest slots (0 = an empty slot), kinds = { [classID.."/"..sub] = slots } }
function B.WornBags()
    local C = C_Container
    local smallest, kinds, sizes = nil, {}, {}
    for bag = 1, (NUM_BAG_SLOTS or 4) do
        local inv = C and C.ContainerIDToInventoryID and C.ContainerIDToInventoryID(bag)
        local id = inv and GetInventoryItemID and GetInventoryItemID("player", inv)
        local n = C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag) or 0
        if not id or n == 0 then smallest = 0; sizes[#sizes + 1] = 0
        else
            local _, _, _, _, _, classID, sub = instant(id)
            if classID == 1 and (sub or 0) == 0 then
                sizes[#sizes + 1] = n
                if not smallest or n < smallest then smallest = n end
            else
                local k = (classID or 0) .. "/" .. (sub or 0)
                kinds[k] = math.max(kinds[k] or 0, n)
            end
        end
    end
    -- the reagent bag sits in its own slot (decision 330); no bag there = 0 slots
    local R, rk = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag, B.ReagentKey()
    if rk and type(R) == "number" then
        local n = C and C.GetContainerNumSlots and C.GetContainerNumSlots(R) or 0
        kinds[rk] = math.max(kinds[rk] or 0, n)
    end
    return { normal = smallest, kinds = kinds, sizes = sizes }
end
-- how many of my bag slots a bag of this kind and size would make bigger (decision 441): a normal bag every
-- smaller normal bag or empty slot, a special bag one
function B.Upgrades(worn, kind, slots)
    if kind ~= "1/0" then return 1 end
    local n = 0
    for _, s in ipairs(worn.sizes or {}) do if s < slots then n = n + 1 end end
    return math.max(1, n)
end

-- which special bags I could use: "1/2" herbs, "1/3" enchanting, "1/4" engineering, "1/1" soul, "11/2" quiver, "11/3" ammo pouch
function B.WantedKinds()
    local want = {}
    if GetProfessions and GetProfessionInfo then
        for _, idx in ipairs({ GetProfessions() }) do
            if idx then
                local line = select(7, GetProfessionInfo(idx))
                if B.PROF_BAG[line] then want["1/" .. B.PROF_BAG[line]] = true end
            end
        end
    end
    local rk = B.ReagentKey()
    if rk then want[rk] = true end                         -- the reagent bag: for everybody, next to the profession bag
    local _, class = UnitClass("player")
    if class == "WARLOCK" then want["1/1"] = true end
    if class == "HUNTER" then
        local link = GetInventoryItemLink and GetInventoryItemLink("player", 18)
        local sub = link and select(7, instant(link))
        if sub == 3 then want["11/3"] = true else want["11/2"] = true end     -- a gun takes bullets
    end
    return want
end

-- The bag search (decision 325, like the weapon search): one browse for containers (class 1, the game's
-- "Containers" category), for hunters a second one for quivers and ammo pouches (class 11, like the wand
-- browse of the weapons). Each answer is read at once, there is no paging. Then every result is judged:
-- one row per bag type with the cheapest offer. The slot count comes from the item's tooltip; the game
-- knows it only once the item is loaded, so unread bags are loaded and judged again (at most B.BAG_TRIES).
B.BAG_TRIES, B.BAG_RETRY = 3, 1.5

local function judgeBags()
    for i = #bagCands, 1, -1 do bagCands[i] = nil end
    local worn, want = B.WornBags(), B.WantedKinds()
    local bestOf, unread = {}, {}
    local st = { results = 0, bags = 0, unread = 0, tooDear = 0, notBetter = 0, kinds = {} }
    for _, res in ipairs(bagBrowse.results or {}) do
        st.results = st.results + 1
        local okR, errR = pcall(function()
        local id = res.itemKey and res.itemKey.itemID
        local _, _, _, _, _, classID, sub = instant(id or 0)
        if classID == 1 or classID == 11 then
            st.bags = st.bags + 1
            local kk = (classID or 0) .. "/" .. (sub or 0)
            st.kinds[kk] = (st.kinds[kk] or 0) + 1
            local slots = id and B.BagSlots(id)
            if not slots then
                st.unread = st.unread + 1; unread[#unread + 1] = id
            elseif (res.minPrice or 0) > budget() then
                st.tooDear = st.tooDear + 1
            else
                local k = (classID or 0) .. "/" .. (sub or 0)
                local ok
                if k == "1/0" then ok = worn.normal ~= nil and slots > worn.normal
                else ok = want[k] and slots > (worn.kinds[k] or 0) end
                if not ok then st.notBetter = st.notBetter + 1 end
                -- one row per bag type (decision 322): the kind and the slots, e.g. "herb bag 12"; the cheapest of it
                local t = k .. ":" .. slots
                local cur = bestOf[t]
                if ok and (not cur or (res.minPrice or 0) < cur.price) then
                    bestOf[t] = { itemKey = res.itemKey, itemID = id, slots = slots, price = res.minPrice or 0, bagKind = k }
                end
            end
        end
        end)
        if not okR then st.errors = (st.errors or 0) + 1; st.err = st.err or tostring(errR) end
    end
    bagBrowse.stats = st
    for t, c in pairs(bestOf) do
        local k = c.bagKind
        c.key, c.state, c.anyKey = "g" .. t, "price", true
        c.onResult = function(x) x.offers = readOffers(x); x.checkedAt = now(); x.state = #x.offers > 0 and "ok" or "none" end
        c.replaces = (k == "1/0") and worn.normal or (worn.kinds[k] or 0)
        c.upgrades, c.boughtN = B.Upgrades(worn, k, c.slots), 0
        bagCands[#bagCands + 1] = c
    end
    -- normal bags first, then the reagent bags, then the other special kinds; within a kind the biggest first
    local rk = B.ReagentKey()
    local function rank(k) return (k == "1/0" and 0) or (k == rk and 1) or 2 end
    table.sort(bagCands, function(a, b)
        local ra, rb = rank(a.bagKind), rank(b.bagKind)
        if ra ~= rb then return ra < rb end
        if a.bagKind ~= b.bagKind then return a.bagKind < b.bagKind end
        return a.slots > b.slots
    end)
    return unread
end

function B.JudgeBags()
    local okJ, unread = pcall(judgeBags)
    if not okJ then
        bagBrowse.stats = bagBrowse.stats or {}
        bagBrowse.stats.err = tostring(unread)
        bagBrowse.state = "done"
        return
    end
    if #unread > 0 and (bagBrowse.tries or 0) < B.BAG_TRIES then
        -- not loaded yet: ask the game for the items and look again a moment later
        for i = #bagCands, 1, -1 do bagCands[i] = nil end
        bagBrowse.state = "loading"
        bagBrowse.tries = (bagBrowse.tries or 0) + 1
        local I = C_Item
        for _, id in ipairs(unread) do
            if I and I.RequestLoadItemDataByID then pcall(I.RequestLoadItemDataByID, id) end
        end
        local again = function()
            if bagBrowse.state ~= "loading" then return end
            B.JudgeBags()
            local H = AH(); if H then H.Refresh(); H.Pump() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(B.BAG_RETRY, again) else again() end
        return
    end
    bagBrowse.state = "done"
end

local function wantsQuivers()
    local _, class = UnitClass("player")
    return class == "HUNTER"
end

-- the answer of a bag browse: read it at once, like the weapons (decision 325)
local function onBagBrowse(q)
    local A = CA()
    bagBrowse.answered = (bagBrowse.answered or 0) + (q and q.answered and 1 or 0)
    bagBrowse.results = bagBrowse.results or {}
    local got = A.GetBrowseResults and A.GetBrowseResults() or {}
    for _, res in ipairs(got) do bagBrowse.results[#bagBrowse.results + 1] = res end
    -- what each browse saw (decision 326): the game's answers and how many results were read
    bagBrowse.log = bagBrowse.log or {}
    bagBrowse.log[#bagBrowse.log + 1] = string.format("%s: %s, read %d", tostring(q and q.key), (q and q.answers) and table.concat(q.answers, "; ") or "no answer (timeout)", #got)
    if bagBrowse.state == "asking" and wantsQuivers() then bagBrowse.state = "quivers"; return end   -- the quiver browse next
    bagBrowse.tries = 0
    B.JudgeBags()
end

-- /omq ah bags: what the bag search saw (decisions 320, 325)
function B.BagReport()
    local worn, want = B.WornBags(), B.WantedKinds()
    local kinds, wk = {}, {}
    for k, n in pairs(worn.kinds) do kinds[#kinds + 1] = (B.KindLabel(k) or k) .. " " .. n end
    for k in pairs(want) do wk[#wk + 1] = B.KindLabel(k) or k end
    local st = bagBrowse.stats or {}
    local H = AH()
    local q, age = nil, 0
    if H and H._Asking then q, age = H._Asking() end
    local lines = {
        string.format("v%s bags: scan %s, state %s, answers of the game %d", tostring(OMQ.version),
            B.want.bags and "requested" or "not requested", tostring(bagBrowse.state), bagBrowse.answered or 0),
        "worn: smallest normal bag " .. tostring(worn.normal) .. (#kinds > 0 and (", " .. table.concat(kinds, ", ")) or ""),
        "special bags for you: " .. (#wk > 0 and table.concat(wk, ", ") or "none") .. ", budget " .. money0(budget()),
        string.format("results %d, bags %d, slots unread %d (tries %d), too dear %d, not bigger %d",
            st.results or 0, st.bags or 0, st.unread or 0, bagBrowse.tries or 0, st.tooDear or 0, st.notBetter or 0),
        "the queue waits for: " .. (q and (tostring(q.key) .. " since " .. math.floor(age) .. "s") or "nothing"),
        "slot line format: " .. tostring(CONTAINER_SLOTS) .. " -> " .. B.SlotPattern(),
    }
    -- the container categories of the game and which one is the reagent bag (decision 330)
    local cats = {}
    for _, c in ipairs(B.ContainerSubclasses()) do cats[#cats + 1] = c.sub .. " " .. c.name end
    lines[#lines + 1] = "container categories: " .. (#cats > 0 and table.concat(cats, ", ") or "not readable") ..
        "; reagent bag kind: " .. tostring(B.ReagentKey())
    local seen = {}
    for k, n in pairs(st.kinds or {}) do seen[#seen + 1] = k .. " x" .. n end
    table.sort(seen)
    lines[#lines + 1] = "kinds seen in the answers: " .. (#seen > 0 and table.concat(seen, ", ") or "none")
    if st.err then lines[#lines + 1] = string.format("ERROR (%d): %s", st.errors or 1, st.err) end
    for _, l in ipairs(bagBrowse.log or {}) do lines[#lines + 1] = "  " .. l end
    for _, c in ipairs(bagCands) do
        lines[#lines + 1] = string.format("  %s: item %d, %d slots, %s (%s)", B.KindLabel(c.bagKind) or c.bagKind, c.itemID, c.slots, money0(c.price or 0), tostring(c.state))
    end
    return lines
end

function B.Bags()
    local out = {}
    local never = (db()).never
    for _, c in ipairs(bagCands) do
        -- a bag of which one was just bought stays in view while its next offer is searched (decision 441)
        local again = c.state == "price" and (c.boughtN or 0) > 0
        if (c.state == "ok" or again) and not never[c.itemID] and not c.bought then out[#out + 1] = c end
    end
    B.bagsMore = math.max(0, #out - B.BAG_ROWS)
    -- every bag type gets its first (biggest) row before one type fills them all: the reagent bag is always shown
    -- next to the profession bag (decision 330); the rest of the rows go by the usual order
    local keep, seenKind, nKeep = {}, {}, 0
    for _, c in ipairs(out) do
        if not seenKind[c.bagKind] and nKeep < B.BAG_ROWS then seenKind[c.bagKind] = true; keep[c] = true; nKeep = nKeep + 1 end
    end
    for _, c in ipairs(out) do
        if not keep[c] and nKeep < B.BAG_ROWS then keep[c] = true; nKeep = nKeep + 1 end
    end
    local shown = {}
    for _, c in ipairs(out) do if keep[c] then shown[#shown + 1] = c end end
    return shown
end

-- buff foods I can eat: their prices are looked at once, the cheapest per piece becomes a row
function B.FoodCandidates(lvl)
    for i = #foods, 1, -1 do foods[i] = nil end
    for _, f in ipairs(OMQ.BuyFoods or {}) do
        if f[2] <= lvl and not B.NoXP(f[1]) then
            local r = rowFor(f[1], "food", nil, B.TARGET.food or 10, false)
            foods[#foods + 1] = r
        end
    end
    return foods
end
function B.CheapestFood(lvl)
    local best
    for _, r in ipairs(foods) do
        local o = r.offers and r.offers[1]
        if r.state == "ok" and o and not B.NoXP(r.itemID) and (not best or o.unit < best.offers[1].unit) then best = r end
    end
    return best
end

-- is a search of the buy mode still to come? (decision 286)
function B.Pending()
    for _, list in ipairs({ rows, foods, alts }) do
        for _, r in ipairs(list) do if r.state == "price" then return true end end
    end
    return false
end
-- is a search of the Upgrades tab still to come? (decision 637)
function B.UpgPending()
    for _, list in ipairs({ candidates, bagCands }) do
        for _, r in ipairs(list) do if r.state == "price" then return true end end
    end
    return (B.want.weapons and browse.state ~= "done") or (B.want.bags and bagBrowse.state ~= "done") and true or false
end
local function resetGear()
    browse.gen = (browse.gen or 0) + 1
    browse.state, browse.step, browse.results, browse.searches, browse.lines = "idle", 0, nil, nil, nil
    for i = #candidates, 1, -1 do candidates[i] = nil end
end
-- the gear scan, on request (decision 290)
function B.ScanWeapons()
    B.want.weapons = true
    resetGear()
    AH().Refresh(); AH().Pump()
end
-- the bag scan, on request (decision 320, like the weapons)
local function resetBags()
    bagBrowse.state, bagBrowse.tries, bagBrowse.results, bagBrowse.stats, bagBrowse.answered, bagBrowse.log = "idle", 0, nil, nil, 0, nil
    bagBrowse.gen = (bagBrowse.gen or 0) + 1          -- an answer of an older bag search is not read (decision 637)
    for i = #bagCands, 1, -1 do bagCands[i] = nil end
end
function B.ScanBags()
    B.want.bags = true
    resetBags()
    AH().Refresh(); AH().Pump()
end
-- the Upgrades tab looked at (decision 637): its searches start once per visit of the auction house
function B.OpenUpgrades()
    if B.want.weapons and B.want.bags then return end
    B.want.weapons, B.want.bags = true, true
    resetGear()
    resetBags()
end
-- a new gold limit (decision 637): everything of the Upgrades tab is searched again
function B.SetLimit(c)
    local ah = db()
    ah.upgLimit = ah.upgLimit or {}
    ah.upgLimit[UnitGUID and UnitGUID("player") or "?"] = c
    B.want.weapons, B.want.bags = true, true
    resetGear()
    resetBags()
    AH().Refresh(); AH().Pump()
end
-- everything again: the stock prices, the gear, the bags (decision 290)
function B.ScanAll()
    B.want.weapons, B.want.bags = true, true
    resetGear()
    resetBags()
    for _, r in pairs(byId) do r.state = "price" end
    B.Build()
end

-- (the dump of the whole house no longer feeds the weapons, bags and stock rows: decision 431)

-- Decision 604: a browse search of the buy mode in the form of the game's own window (all quality filters, one
-- class filter per subcategory, a level range). The server of Forever limits browse searches without quality
-- filters: after a few of them it answers with empty lists for a while, and the price scan lost its categories.
function B.BrowseQuery(class, sub, minLevel, maxLevel, sortOrder)
    local sorts = { { sortOrder = sortOrder, reverseSort = false } }
    local PR = OMQ.Prices
    if PR and PR.GameQuery then return PR.GameQuery(class, sub, minLevel, maxLevel, sorts) end
    return { searchString = "", sorts = sorts, minLevel = minLevel, maxLevel = maxLevel,
             itemClassFilters = { { classID = class, subClassID = sub } } }
end

-- the next search the auction helper's queue should send (after its own price checks)
-- The stock rows of the Buy tab; the gear and bag searches belong to the Upgrades tab (decision 637).
function B.NextQuery()
    for _, r in ipairs(rows) do
        if r.state == "price" then r.onResult = onStock; return r end
    end
    for _, r in ipairs(foods) do
        if r.state == "price" then r.onResult = onStock; return r end
    end
    for _, r in ipairs(alts) do
        if r.state == "price" then r.onResult = onStock; return r end
    end
    return nil
end
-- the next search of the Upgrades tab (decision 637): the gear browses one after another, the closer looks at the
-- best of each slot, then the bags
function B.NextUpgQuery()
    if B.want.weapons and (browse.state == "idle" or browse.state == "next") then
        local P = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
        local lvl = level()
        if browse.state == "idle" then browse.results, browse.step, browse.searches = nil, 0, B.GearSearches() end
        local sch = browse.searches[(browse.step or 0) + 1]
        browse.state = "asking"
        local gen = browse.gen
        local q = B.BrowseQuery(sch[1], sch[2], math.max(1, lvl - B.GEAR_MIN_LEVELS), lvl + B.WEAPON_LEVELS, P)
        if sch[3] then q.itemClassFilters = { { classID = sch[1], subClassID = sch[2], inventoryType = sch[3] } } end   -- one slot (fix 640)
        return { browse = true, key = "gear" .. sch[1] .. "." .. tostring(sch[2]) .. (sch[3] and ("/" .. sch[3]) or ""),
                 onResult = function() onBrowse(gen) end, query = q }
    end
    for _, c in ipairs(candidates) do
        if c.state == "price" then return c end
    end
    if B.want.bags and (bagBrowse.state == "idle" or bagBrowse.state == "quivers") then
        local P = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
        local class = bagBrowse.state == "quivers" and 11 or 1
        bagBrowse.state = class == 1 and "asking" or "asking quivers"
        local gen = bagBrowse.gen
        return { browse = true, key = "bags" .. class, onResult = function(q) if gen == bagBrowse.gen then onBagBrowse(q) end end,
                 query = B.BrowseQuery(class, nil, nil, nil, P) }
    end
    for _, c in ipairs(bagCands) do
        if c.state == "price" then return c end
    end
    return nil
end

----------------------------------------------------------------------
-- Buying (from a click)
----------------------------------------------------------------------
local buying = nil
B._buying = function() return buying end
-- fast clicks (decision 281): one purchase at a time. A click while one is on its way is ignored; a
-- purchase the game never answers is given up after B.BUY_WAIT seconds, so nothing hangs.
B.BUY_WAIT = 6
local done
local late = nil           -- the purchase given up last: a confirmation that comes late still counts (decision 402)
B.LATE_WAIT = 30
function B.Busy()
    if not buying then return false end
    if now() - (buying.at or 0) < B.BUY_WAIT then return true end
    local b = buying
    done(false, "no answer from the auction house - click again")
    late = { b = b, at = now() }
    return false
end
local function succeeded()
    if not buying and late and now() - late.at < B.LATE_WAIT then buying = late.b end
    late = nil
    done(true)
end
local function watch()
    if C_Timer and C_Timer.After then C_Timer.After(B.BUY_WAIT + 0.1, function() B.Busy() end) end
end

local function afford(cost)
    if (GetMoney and GetMoney() or 0) < cost then
        OMQ:Print("auction helper: not enough gold (" .. money(cost) .. ")")
        return false
    end
    return true
end

function B.Buy(r, n)
    local A = CA()
    if not (A and r and r.offers and #r.offers > 0) or B.Busy() or not AH().open then return false end
    AH().Quiet()                                                       -- clicks go first (decision 293)
    if A.IsThrottledMessageSystemReady and not A.IsThrottledMessageSystemReady() then AH().WaitNote(); return false end   -- a search is on its way
    n = math.max(1, n or 1)
    if r.commodity then
        local cost, got = B.Cost(r, n)
        n = math.min(n, got)
        if n < 1 or not afford(cost) then return false end
        -- the price the game named after a refusal: the next click within AGREED_TIME buys at it (fix 562)
        local ag = r.agreed
        r.agreed = nil
        local agreed = ag and now() - (ag.at or 0) < B.AGREED_TIME and ag.unit * n or nil
        buying = { row = r, qty = n, base = B.Have(r.itemID), at = now(), expect = cost, limit = r.cap and r.cap * n, agreed = agreed }
        AH().Own(A.StartCommoditiesPurchase, r.itemID, n)
    else
        local o = r.offers[1]
        if not afford(o.buyout) then return false end
        buying = { row = r, qty = o.qty, auctionID = o.auctionID, base = B.Have(r.itemID), at = now() }
        table.remove(r.offers, 1)
        AH().Own(A.PlaceBid, o.auctionID, o.buyout)
    end
    watch()
    AH().Refresh()
    return true
end

-- Single auctions (weapons, bags) are bought from a fresh search (decision 431): the first click searches exactly
-- this item again, the queue then holds still for FRESH seconds, and the second click buys the auction the game
-- has just shown. A purchase from an old search failed, because the game no longer knew the auction.
B.FRESH = 10
B.check = nil              -- { row, kind = "weapon" | "bag", sent }
function B.Fresh(x)
    local f = x and x.fresh
    local H = AH()
    return f and now() - f.at < B.FRESH and f.seq == (H.searchSeq or 0) or false
end
-- the best offer of a gear search: under the limit, wearable now, the biggest gain (with the slot it goes into)
local function bestGearOffer(x, offers)
    local bestO, bestG, bestS
    for _, o in ipairs(offers) do
        local need = select(5, info(o.link or 0))
        if o.link and o.buyout <= budget() and not (need and need > level() + B.WEAPON_LEVELS) and B.CanEquipNow(o.link) ~= false then
            local g, at = gainAt(o.link, x.equipLoc)
            if g and g > 0 and (not bestG or g > bestG or (g == bestG and o.buyout < bestO.buyout)) then bestO, bestG, bestS = o, g, at end
        end
    end
    return bestO, bestG, bestS
end
B._bestGearOffer = bestGearOffer
local function onCheck(q)
    local c = B.check
    B.check = nil
    if not c then return end
    local x = c.row
    x.checking = nil
    x.itemKey = q.itemKey or x.itemKey
    local offers = readOffers(q)
    if c.kind == "weapon" then
        x.offer, x.gain, x.slot = bestGearOffer(x, offers)
        if not x.offer then x.state = "done"; OMQ:Print("auction helper: that item is gone") end
    else
        x.offers = offers
        x.state = #offers > 0 and "ok" or "none"
        if #offers == 0 then OMQ:Print("auction helper: that bag is gone") end
    end
    local H = AH()
    x.fresh = (c.kind == "weapon" and x.offer or (c.kind ~= "weapon" and #offers > 0)) and { at = now(), seq = H.searchSeq or 0 } or nil
    if x.fresh then
        H.quietUntil = now() + B.FRESH                       -- no other search: the auction stays the game's latest
        if C_Timer and C_Timer.After then C_Timer.After(B.FRESH + 0.1, function() H.Refresh() end) end
    end
end
-- the check search for the queue: it goes before everything else
function B.CheckQuery()
    local c = B.check
    if not c or c.sent then return nil end
    c.sent = true
    local x = c.row
    local A = CA()
    return { key = "check" .. tostring(x.itemID), itemID = x.itemID, itemKey = x.itemKey or (A and A.MakeItemKey and A.MakeItemKey(x.itemID)) or { itemID = x.itemID },
             anyKey = true, commodity = false, onResult = onCheck }
end
function B.StartCheck(x, kind)
    if not x or B.check then return false end
    x.checking, x.fresh = true, nil
    B.check = { row = x, kind = kind }
    AH().Refresh(); AH().Pump()
    return true
end

function B.BuyBag(g)
    if not g or B.Busy() or not AH().open then return false end
    if not B.Fresh(g) then return B.StartCheck(g, "bag") end
    g.fresh = nil
    return B.Buy(g, 1)
end

function B.BuyGear(w)
    local A = CA()
    if not (A and w and w.offer) or B.Busy() or not AH().open then return false end
    if not B.Fresh(w) then return B.StartCheck(w, "weapon") end
    w.fresh = nil
    AH().Quiet()
    if A.IsThrottledMessageSystemReady and not A.IsThrottledMessageSystemReady() then AH().WaitNote(); return false end
    if not afford(w.offer.buyout) then return false end
    buying = { weapon = w, auctionID = w.offer.auctionID, at = now() }
    AH().Own(A.PlaceBid, w.offer.auctionID, w.offer.buyout)
    watch()
    AH().Refresh()
    return true
end

-- a click on a stock row: fill up (what is missing) or a single piece
function B.Click(r)
    if not r then return false end
    if B.Mode() == "single" then return B.Buy(r, 1) end
    return B.Buy(r, math.max(1, r.need or 1))
end

-- "Fill everything up": the next row that misses something
function B.FillNext()
    for _, r in ipairs(rows) do
        if (r.need or 0) > 0 and r.offers and #r.offers > 0 then return B.Buy(r, r.need) end
    end
    return false
end

-- the consumables clicked away (right click: never suggest) - not the gear, weapons and bags (decisions 275, 637)
local function isConsumable(id)
    if OMQ.BuyKind(id) then return true end
    local classID = select(6, instant(id))
    return classID ~= nil and classID ~= 1 and classID ~= 2 and classID ~= 4 and classID ~= 11
end
function B.NeverCount()
    local n = 0
    for id in pairs(db().never) do if isConsumable(id) then n = n + 1 end end
    return n
end
function B.ResetNever()
    local never = db().never
    for id in pairs(never) do if isConsumable(id) then never[id] = nil end end
    for _, r in pairs(byId) do r.state = "price" end
    B.Build()
    AH().Refresh()
    AH().Pump()
end

function B.Never(id)
    db().never[id] = true
    B.Build()
    AH().Refresh()
end

function done(ok, why)
    local b = buying
    buying = nil
    if b and b.weapon then
        b.weapon.bought = ok or nil
        if not ok then b.weapon.state, b.weapon.offer, b.weapon.gain = "price", nil, nil end   -- gone or refused: look again (decision 402)
    end
    if b and b.row then
        if ok and not b.row.bagKind then B.Bought(b.row.itemID, b.qty, b.base); B.Consume(b.row, b.qty) end
        if ok and b.row.shop and OMQ.Shopping then OMQ.Shopping.Bought(b.row, b.qty) end      -- a shopping list row (decision 551)
        if b.row.bagKind then
            -- a bag stays while more of my slots would get bigger (decision 441): 3 bags of 6 slots, one 8 bought,
            -- the row stays for the other two; the next offer is searched again
            local g = b.row
            if ok then
                g.boughtN = (g.boughtN or 0) + 1
                if g.boughtN >= (g.upgrades or 1) then g.bought = true
                else g.fresh, g.state = nil, "price" end
            end
        elseif not ok then b.row.state, b.row.live, b.row.estimate = "price", true, nil end    -- failed: a real search of the offers, no estimate (decision 402)
    end
    if not ok and why then OMQ:Print("auction helper: " .. why) end
    B.Build()
    AH().Ready()
    AH().Refresh()
    AH().Pump()
end
-- a purchase went through: what I bought is gone from the known offers, no new search (decision 293)
function B.Consume(r, n)
    if not (r and r.offers) then return end
    if r.commodity then
        local left = n or 0
        while left > 0 and r.offers[1] do
            local o = r.offers[1]
            local take = math.min(o.qty or 0, left)
            o.qty, left = (o.qty or 0) - take, left - take
            if o.qty <= 0 then table.remove(r.offers, 1) end
        end
    end
    if #r.offers == 0 then r.state = "none" end
end
-- the stock rows one batch request can price: stackable items, not asked yet (decision 293)
function B.BatchRows()
    local out, tried = {}, AH()._tried or {}
    for _, list in ipairs({ rows, foods, alts }) do
        for _, r in ipairs(list) do
            if r.state == "price" and not tried[r.key] and not r.listed and not r.live then
                -- consumables stack: one not loaded yet goes into the batch too, only shield spikes do not (decision 432)
                local stack = select(8, info(r.itemID))
                if (stack and stack > 1) or (stack == nil and r.kind and r.kind ~= "spike") then r.listed = true; out[#out + 1] = r end
            end
        end
    end
    for _, r in ipairs(out) do r.listed = nil end
    return out
end
-- the answer of a batch: the lowest price per piece and how many there are, an estimate until a click
function B.FromBatch(r, res)
    r.checkedAt = now()
    if res then
        r.offers = { { unit = res.minPrice, qty = res.totalQuantity or 1 } }
        r.commodity, r.estimate, r.state = true, true, "ok"
    else
        r.offers, r.state = {}, "none"
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
                     "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
                     "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "MAIL_INBOX_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
-- the game's price for a purchase may be above an estimate: then no purchase, the offers are looked at
-- closely and the next click buys at the real price (decision 293)
B.PRICE_SLACK = 1.2
-- after "click once more to buy" the dad has seen the real price: the next click buys up to it (fix 562; before, the
-- next click compared with the offers again and could be refused forever, e.g. Moss Agate in the Shopping tab)
B.AGREED_TIME, B.AGREED_SLACK = 120, 1.02
function B.PriceOk(expect, total, limit, agreed)
    if not (expect and total) then return true end
    if limit and total > limit then return false end           -- never over the price limit of the row (decision 431)
    if agreed and total <= agreed * B.AGREED_SLACK + 100 then return true end
    return total <= expect * B.PRICE_SLACK + 100
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    local ok, err = pcall(function()
        if event == "MAIL_INBOX_UPDATE" then B.CheckMail(); return end
        if not (AH() and AH().open) then return end
        local A = CA()
        if event == "COMMODITY_PRICE_UPDATED" then
            if buying and buying.row then
                if B.PriceOk(buying.expect, a2, buying.limit, buying.agreed) then
                    AH().Own(A.ConfirmCommoditiesPurchase, buying.row.itemID, buying.qty)
                else
                    if A.CancelCommoditiesPurchase then A.CancelCommoditiesPurchase() end
                    local r, over = buying.row, buying.limit and a2 and a2 > buying.limit
                    r.estimate = nil
                    if over then
                        done(false, "the price is above the limit of this row (" .. money(a2) .. " in all) - not bought")
                    else
                        r.agreed = a2 and { unit = a2 / math.max(1, buying.qty or 1), at = now() } or nil
                        done(false, "the price is higher than shown (" .. money(a2) .. " in all) - click once more to buy at this price")
                    end
                end
            end
        elseif event == "COMMODITY_PRICE_UNAVAILABLE" then done(false, "that price is gone - looking again")
        elseif event == "COMMODITY_PURCHASE_SUCCEEDED" or event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then succeeded()
        elseif event == "COMMODITY_PURCHASE_FAILED" then done(false, "the purchase failed")
        elseif event == "AUCTION_HOUSE_SHOW_ERROR" then if buying then done(false, "the auction house refused it") end
        elseif event == "BAG_UPDATE_DELAYED" then B.LearnBags(); B.Build(); AH().Refresh()
        elseif event == "GET_ITEM_INFO_RECEIVED" then AH().Refresh() end
    end)
    if not ok then OMQ:Error("auction buy", err) end
end)

function B.Open()
    buying, late, B.check = nil, nil, nil
    B.want.weapons, B.want.bags = false, false        -- searched once the Upgrades tab is looked at (decision 637)
    resetGear()
    resetBags()
    for _, r in pairs(byId) do r.state, r.live = "price", nil end
    B.LearnBags()
    B.FoodCandidates(level())
    B.Build()
end

----------------------------------------------------------------------
-- Drawing (inside the auction helper's panel)
----------------------------------------------------------------------
local ui
B._ui = function() return ui end
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

local function makeRow(parent, h)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(348, h)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.11, 0.122, 0.153, 1)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(h - 8, h - 8); r.icon:SetPoint("LEFT", 4, 0)
    r.name = fs(r, "GameFontHighlight"); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1); r.name:SetWidth(240)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.sub = fs(r, "GameFontDisableSmall"); r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1); r.sub:SetWidth(200)
    if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
    r.top = fs(r, "GameFontNormal"); r.top:SetPoint("TOPRIGHT", -6, -4); r.top:SetJustifyH("RIGHT")
    r.bottom = fs(r, "GameFontNormalSmall", 0.95, 0.82, 0.48); r.bottom:SetPoint("BOTTOMRIGHT", -6, 4); r.bottom:SetJustifyH("RIGHT")
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return r
end
B._makeRow, B._fs, B._qColor = makeRow, fs, qColor      -- shared with the Shopping tab (decision 551)

local function build(panel)
    ui = CreateFrame("Frame", nil, panel)
    if panel.box then ui:SetFrameLevel(panel.box:GetFrameLevel() + 2) end
    ui.head = fs(ui, "GameFontHighlight", 0.79, 0.8, 0.84); ui.head:SetPoint("TOPLEFT", 16, -2); ui.head:SetWidth(348)
    ui.sTitle = fs(ui, "GameFontNormal", 0.95, 0.82, 0.48); ui.sTitle:SetText("Stock up")
    ui.sRows = {}
    ui.offset = 0
    ui:EnableMouseWheel(true)
    ui:SetScript("OnMouseWheel", function(_, d)
        ui.offset = math.max(0, math.min(math.max(0, #rows - B.ROWS), ui.offset - d))
        AH().Refresh()
    end)
    for i = 1, B.ROWS do
        local r = makeRow(ui, 38)
        r:SetScript("OnClick", function(self, button)
            if not self.r then return end
            if button == "RightButton" then B.Never(self.r.itemID) else B.Click(self.r) end
        end)
        r:SetScript("OnEnter", function(self)
            if GameTooltip and self.r then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.r.itemID); GameTooltip:Show()
            end
        end)
        ui.sRows[i] = r
    end
    local all = CreateFrame("Button", "OneMoreQuestAuctionBuyAll", ui)
    all:SetSize(348, 44)
    all.bg = all:CreateTexture(nil, "BACKGROUND"); all.bg:SetAllPoints(); all.bg:SetColorTexture(0.165, 0.141, 0.086, 1)
    all.price = fs(all, "GameFontNormal", 0.95, 0.82, 0.48); all.price:SetPoint("RIGHT", -10, 0); all.price:SetJustifyH("RIGHT")
    all.title = fs(all, "GameFontNormalLarge", 0.95, 0.82, 0.48)          -- one big line, no small text (decision 271)
    all.title:SetPoint("LEFT", 10, 0); all.title:SetPoint("RIGHT", all.price, "LEFT", -8, 0)
    all.flash = all:CreateTexture(nil, "ARTWORK"); all.flash:SetAllPoints(); all.flash:SetColorTexture(0.25, 0.85, 0.35, 0.3); all.flash:Hide()
    all:SetScript("OnClick", function() B.FillNext() end)
    ui.all = all
    ui.hint = fs(ui, "GameFontDisableSmall"); ui.hint:SetWidth(270)
    -- bottom right: bring back the consumables clicked away (decision 275)
    local reset = CreateFrame("Button", "OneMoreQuestAuctionBuyReset", ui)
    reset:SetSize(70, 20)
    reset.edge = reset:CreateTexture(nil, "BACKGROUND"); reset.edge:SetPoint("TOPLEFT", -1, 1); reset.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    reset.edge:SetColorTexture(0.45, 0.37, 0.18, 1)
    reset.bg = reset:CreateTexture(nil, "BORDER"); reset.bg:SetAllPoints(); reset.bg:SetColorTexture(0.2, 0.21, 0.25, 1)
    reset.text = fs(reset, "GameFontNormalSmall", 0.93, 0.93, 0.95); reset.text:SetPoint("CENTER"); reset.text:SetText("Reset")
    reset.hl = reset:CreateTexture(nil, "HIGHLIGHT"); reset.hl:SetAllPoints(); reset.hl:SetColorTexture(1, 1, 1, 0.08)
    reset:SetScript("OnClick", function() B.ResetNever() end)
    reset:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset")
        local n = B.NeverCount()
        GameTooltip:AddLine("All consumables you clicked away (right click) come back to the list.", 1, 1, 1, true)
        GameTooltip:AddLine(n > 0 and (n .. " clicked away right now") or "Nothing clicked away right now", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    ui.reset = reset
    ui.more = fs(ui, "GameFontDisableSmall")
end
B._UI = function() return ui end


-- draws the buy view below `top` and returns the height it needs
function B.Render(panel, top)
    if not ui then build(panel) end
    ui:ClearAllPoints(); ui:SetPoint("TOPLEFT", 0, -top); ui:SetPoint("BOTTOMRIGHT")
    ui:Show()
    local SC = OMQ.Score
    local class = SC and SC.MyClass() or select(2, UnitClass("player"))
    local cname = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class or "?"
    ui.head:SetText(string.format("For your %s, level %d - you carry |cfff2d27a%s|r", cname, level(), money(GetMoney and GetMoney() or 0))
        .. (AH().Manual() and "  |cffff9933Paused - press Scan all to unpause|r" or ""))
    local y = 26
    -- stock (the weapons and bags moved to the Upgrades tab, decision 637)
    ui.sTitle:ClearAllPoints(); ui.sTitle:SetPoint("TOPLEFT", 16, -y)
    y = y + 20
    ui.offset = math.min(ui.offset, math.max(0, #rows - B.ROWS))
    local single = B.Mode() == "single"
    local clicks, total = 0, 0
    for _, r in ipairs(rows) do
        if (r.need or 0) > 0 and r.offers and #r.offers > 0 then
            clicks = clicks + 1
            total = total + B.Cost(r, r.need)
        end
    end
    for i, row in ipairs(ui.sRows) do
        local r = rows[i + ui.offset]
        row.r = r
        row:SetShown(r ~= nil)
        if r then
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 16, -y)
            local name, _, quality, _, _, _, _, _, _, icon = info(r.itemID)
            if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, r.itemID) end
            row.icon:SetTexture(icon or select(5, instant(r.itemID)))
            -- the cheapest XP food says so behind its name (decision 272)
            row.name:SetText((name or ("item " .. r.itemID)) .. (r.xp and " (Cheapest 5% Buff)" or "")); row.name:SetTextColor(qColor(quality))
            local unit = r.offers and r.offers[1] and r.offers[1].unit
            -- no category line any more (decision 270): only what helps to choose
            local parts = {}
            if unit then parts[#parts + 1] = money(unit) .. " each" end
            if r.cheaper then parts[#parts + 1] = "weaker, cheaper" end
            if r.mine then parts[#parts + 1] = "you use it" end
            row.sub:SetText(table.concat(parts, " - "))
            local full = (r.need or 0) == 0
            row.top:SetText(string.format("%s%d / %d|r", full and "|cff9fdc8a" or "|cffe5e3dc", r.have or 0, r.target))
            local right
            if buying and buying.row == r then right = "Buying..."
            elseif r.state == "price" then right = "..."
            elseif r.state == "none" then right = "not on sale"
            elseif single then right = "Buy 1 - " .. money0(B.Cost(r, 1))
            elseif full then right = "stocked"
            else right = string.format("Buy %d - %s", r.need, money0(B.Cost(r, r.need))) end
            row.bottom:SetText(right)
            row.bg:SetAlpha((full and not single) and 0.5 or 1)
            y = y + 40
        end
    end
    if #rows > B.ROWS then
        ui.more:ClearAllPoints(); ui.more:SetPoint("TOPLEFT", 16, -y)
        ui.more:SetText(string.format("Mouse wheel: %d more", #rows - B.ROWS)); ui.more:Show()
        y = y + 16
    else ui.more:Hide() end
    -- fill everything up (fill mode)
    ui.all:SetShown(not single)
    if not single then
        y = y + 6
        ui.all:ClearAllPoints(); ui.all:SetPoint("TOPLEFT", 16, -y)
        ui.all.flash:SetShown(not buying and AH().Flashing())
        ui.all.title:SetText((buying and "Buying...") or clicks > 0 and string.format("Fill all Consumables - Click %d time%s", clicks, clicks == 1 and "" or "s")
            or "All Consumables stocked up")
        ui.all.price:SetText(clicks > 0 and money(total) or "")
        y = y + 48
    end
    ui.hint:ClearAllPoints(); ui.hint:SetPoint("TOPLEFT", 16, -(y + 4))
    ui.reset:ClearAllPoints(); ui.reset:SetPoint("TOPRIGHT", ui, "TOPLEFT", 364, -y)
    ui.hint:SetText(single and "Left click: buy one - right click: never suggest it"
        or "Left click: buy what is missing - right click: never suggest it")
    return y + 24
end

function B.Hide() if ui then ui:Hide() end end
