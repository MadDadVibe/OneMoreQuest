-- One More Quest - item flips in the auction house (decision 721, replaces the disenchant bargains of decision 710)
-- /omq ah flip opens a window next to the auction helper and looks for green weapons and armor of required level 30
-- to 50 with one of the suffixes of the Sorcerer, Bandit, Knight, Beast, Elder, Channeler or Hierophant (English and
-- German names, F.SUFFIXES; weapons only with the caster ones, F.CASTER, fix 723). Every item with its suffix counts on its own. A flip: at least 6 offers and the 6th
-- cheapest at least 1.5 times the cheapest - the cheap ones are bought and sold again at the 6th price minus 1 copper;
-- every offer under 2/3 of that price is bought (never one over 1 gold, 1.50 gold from required level 40 - fix 733; fix 724; a second method "gap3": 3rd >= 2x 1st). Fewer than 6 offers: every offer under 1 gold is listed too
-- (MadDadVibe). Only buyouts count.
-- The search: two browse searches (weapons, armor) in the form of the game's own window with the quality filter green
-- and the levels 30-50 (decision 604), every page, a class whose list stops at a full page per subcategory; then one
-- search per matching item (its offers, the cheapest first). The list fills while it runs.
-- Left click on a row buys its next cheap offer: the first click searches that item again (a purchase needs the
-- auction of the game's latest search, decision 431) and the search holds still a few seconds, every next click buys
-- one more. Shift + left click shows the item in the game's own window (fix 724). Right click: discarded until it is offered cheaper or for SKIP_TIME. "Buy next" buys from the first row.
-- What I bought is remembered (OMQDB.flip.owned, KEEP_DAYS): never sold to the vendor, never disenchanted, posted at
-- the auction house never under its price plus the house's cut (F.Floor). While the search runs the auction helper and
-- the price scan send nothing.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local F = {}
OMQ.Flip = F

F.CLASSES = { 4 }         -- armor only (fix 737, MadDadVibe: green weapons do not sell; was weapons + armor)
F.WEAPONS = false         -- fix 737: weapons never looked at
F.NO_SLOTS = { INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true }   -- fixes 749, 750 (MadDadVibe): no off-hand items, no shields
F.MIN_LEVEL, F.MAX_LEVEL = 30, 50
F.NTH = 6                 -- the offer the cheapest is compared with
F.RATIO = 1.5             -- the 6th cheapest at least this much times the cheapest
F.CHEAP = 10000           -- fewer than NTH offers: every offer under 1 gold
F.MAX_BUY = 10000         -- fix 724 (MadDadVibe): no offer over 1 gold is ever bought or shown
F.MAX_BUY_HIGH = 15000    -- fix 733 (MadDadVibe): items of required level 40 and up may cost up to 1.50 gold
F.HIGH_LEVEL = 40
function F.MaxBuy(level)
    if type(level) == "number" and level >= F.HIGH_LEVEL then return F.MAX_BUY_HIGH end
    return F.MAX_BUY
end
-- fix 724: two methods, chosen with the two buttons on top; the search starts only after the choice
--   "flip": the 6th cheapest >= 1.5x the cheapest (decision 721), fewer than 6 offers: every one under 1 gold
--   "gap3": the 3rd cheapest >= 2x the cheapest - easy buyouts, sold again at the 3rd price minus 1 copper
F.METHODS = {
    flip = { nth = 6, ratio = 1.5, few = true, label = "6th 1.5x, lvl 30-50" },
    gap3 = { nth = 3, ratio = 2, few = false, label = "3rd 2x, lvl 30-50" },
    -- decision 727: the same for the levels 10-29
    gap3low = { nth = 3, ratio = 2, few = false, label = "3rd 2x, lvl 10-29", minLevel = 10, maxLevel = 29 },
    -- decision 731: the same for plate armor of level 40-42 only (one browse: armor, subcategory plate)
    gap3plate = { nth = 3, ratio = 2, few = false, label = "3rd 2x, plate 40-42", minLevel = 40, maxLevel = 42,
                  only = { c = 4, s = 4 } },
    -- decision 746 (MadDadVibe): always the 2nd cheapest (>= 2x the cheapest; only the cheapest is bought); a single
    -- offer is bought when it costs at most twice the vendor price ("the perfect flip"); six level brackets
    b10 = { nth = 2, ratio = 2, single = true, label = "2nd 2x, lvl 10-19", minLevel = 10, maxLevel = 19 },
    b20 = { nth = 2, ratio = 2, single = true, label = "2nd 2x, lvl 20-29", minLevel = 20, maxLevel = 29 },
    b30 = { nth = 2, ratio = 2, single = true, label = "2nd 2x, lvl 30-39", minLevel = 30, maxLevel = 39 },
    b40 = { nth = 2, ratio = 2, single = true, label = "2nd 2x, lvl 40-49", minLevel = 40, maxLevel = 49 },
    b50 = { nth = 2, ratio = 2, single = true, label = "2nd 2x, lvl 50-59", minLevel = 50, maxLevel = 59 },
    plate = { nth = 2, ratio = 2, single = true, label = "2nd 2x, plate 40-42", minLevel = 40, maxLevel = 42,
              only = { c = 4, s = 4 } },
}
F.BUTTONS = { "b10", "b20", "b30", "b40", "b50", "plate" }   -- decision 746: the six buttons (the older methods stay for the tests)
F.CUT = 0.05              -- the auction house's cut of a sale
-- the suffixes as the game names them, lower case ("Ä" stays as it is: string.lower leaves non-ASCII bytes alone)
F.SUFFIXES = {
    { key = "sorcerer",   "of the sorcerer",   "des zauberers" },
    { key = "bandit",     "of the bandit",     "des banditen" },
    { key = "knight",     "of the knight",     "des ritters" },
    { key = "beast",      "of the beast",      "der bestie" },
    { key = "elder",      "of the elder",      "des \195\132ltesten", "des \195\164ltesten" },
    { key = "channeler",  "of the channeler",  "des kanalisierers" },
    { key = "hierophant", "of the hierophant", "des hierophanten" },
}
-- fix 739 (MadDadVibe): Hierophant no longer looked for; Knight only on plate armor of required level 40 and up
F.OFF = { hierophant = true, channeler = true }   -- fix 740: Channeler out too
F.KNIGHT_PLATE = 40       -- false: Knight everywhere
F.KNIGHT_MAIL = { 10, 39 } -- fix 741 (MadDadVibe): Knight also on mail ("Schwere Ruestung") of required level 10-39
function F.KnightFits(c, sc, level)
    if not F.KNIGHT_PLATE then return true end
    local l = level or 0
    if c ~= 4 then return false end
    if sc == 4 then return l >= F.KNIGHT_PLATE end
    if sc == 3 and F.KNIGHT_MAIL then return l >= F.KNIGHT_MAIL[1] and l <= F.KNIGHT_MAIL[2] end
    return false
end
-- fix 723 (MadDadVibe): melee weapons are blue all the time, nobody buys green ones - weapons count only with a
-- caster suffix; armor keeps all seven
F.CASTER = { sorcerer = true, elder = true, channeler = true, hierophant = true }
-- fix 729 (MadDadVibe): of the weapons only staves, daggers and maces (one- and two-handed), the rest never
F.WEAPON_KINDS = { [4] = true, [5] = true, [10] = true, [15] = true }
F.PAGE = 500              -- a list that stops at a whole number of these lines may be cut off
F.PAGES = 100             -- at most this many pages of one browse search
F.FIRST_WAIT = 2          -- seconds before the first search: an answer of the helper still on its way passes
F.GAP = 2                 -- seconds between two browse searches (the pace of the price scan, decision 604)
F.ITEM_GAP = 0.3          -- seconds between two item searches (each also waits for the game's throttle)
F.QUIET = 15              -- a browse search without any answer for this long is sent again (TRIES in all) or given up
F.ITEM_QUIET = 8          -- the same for an item search
F.TRIES = 3
F.SKIP_TIME = 86400       -- a discarded item stays away this long (or until it is offered cheaper)
F.LOAD_WAIT = 20          -- seconds an item may take to load (as fix 712)
F.REBUILD_GAP = 2
F.KEEP_DAYS = 14          -- a bought flip is protected this long
F.ROWS = 10
F.ROW_H = 36

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return GetTime() end
local function stamp() return (time and time()) or 0 end
local function A() return C_AuctionHouse end
local function H() return OMQ.AuctionHelper end
local function B() return OMQ.AuctionBuy end
local function money(c) return H().Money(c) end
local function keyString(k) return H()._KeyString(k) end
local function db()
    OMQDB = OMQDB or {}
    OMQDB.deBargain = nil                                  -- the old disenchant bargains (decision 710) are gone
    OMQDB.flip = OMQDB.flip or {}
    local d = OMQDB.flip
    d.skip = nil                                           -- fix 753: the 24 h discards are gone, a dismissed item is on the blacklist
    d.black = d.black or {}
    d.owned = d.owned or {}
    return d
end
local function ready()
    local api = A()
    if not (api and api.IsThrottledMessageSystemReady) then return true end
    local ok, r = pcall(api.IsThrottledMessageSystemReady)
    return not ok or r ~= false
end
local function own(fn, ...) return H().Own(fn, ...) end
local function reqLevelOf(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, _, _, _, _, lvl = pcall(f, id)
    if ok and type(lvl) == "number" and not isSecret(lvl) then return lvl end
end
-- fix 744 (MadDadVibe): never buy a flip for more than twice its vendor price
F.VENDOR_FACTOR = 1.25    -- fix 748 (MadDadVibe): at most 1.25x the vendor price (fix 747: 1.5x, fix 744: 2x)
local function vendorOf(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, v = pcall(f, id)
    if ok and type(v) == "number" and not isSecret(v) and v > 0 then return v end
end
F.VendorOf = vendorOf
local function classOf(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, _, _, _, _, c, sc = pcall(f, id)
    if ok then return c, sc end
end
local function sorts()
    local E = Enum and Enum.AuctionHouseSortOrder
    return { { sortOrder = E and E.Price or 0, reverseSort = false } }
end

local run = nil           -- the search running now
local lines = {}          -- what the browse searches found: per item key { key, id, price, qty }
local rows = {}           -- per item key: the item's offers and its purchase state
local list = {}           -- the flips shown
local frame
F.bought = { n = 0, spent = 0, worth = 0 }

----------------------------------------------------------------------
-- The suffix
----------------------------------------------------------------------
-- the key of the suffix a name ends with ("Polierter Bidenhänder des Banditen" -> "bandit"), or nil
function F.SuffixOf(name)
    if type(name) ~= "string" or isSecret(name) then return nil end
    local l = name:lower()
    for _, s in ipairs(F.SUFFIXES) do
        for _, w in ipairs(s) do
            if #l > #w and l:sub(-#w - 1) == " " .. w then return s.key end
        end
    end
    return nil
end

-- the name and quality of a browse line: the item key's own name carries the suffix; nil while the game loads it
local function nameOf(e)
    local api = A()
    if api and api.GetItemKeyInfo then
        local ok, ki = pcall(api.GetItemKeyInfo, e.key)
        if ok and type(ki) == "table" and type(ki.itemName) == "string" and not isSecret(ki.itemName) then
            e.icon = ki.iconFileID or e.icon
            local q = ki.quality
            if isSecret(q) then q = nil end
            return ki.itemName, q
        end
    end
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local link = B() and B().KeyLink and B().KeyLink(e.key)
    if not (f and link) then return nil end
    local ok, name, _, q, _, _, _, _, _, _, icon = pcall(f, link)
    if not ok or type(name) ~= "string" or isSecret(name) then return nil end
    e.icon = e.icon or icon
    if isSecret(q) then q = nil end
    return name, q
end

-- is a browse line an item to look at closely: true, false, or "wait" while the game loads it
function F.Consider(e)
    if e.match ~= nil then return e.match end
    local m = F.METHODS[(run and run.method) or "flip"]
    if (e.price or 0) > F.MAX_BUY_HIGH or not ((e.qty or 0) >= m.nth or (m.few and (e.price or 0) < F.CHEAP) or (m.single and (e.qty or 0) >= 1)) then e.match = false; return false end
    local name, q = nameOf(e)
    if not name then
        if not e.askedAt then
            e.askedAt = now()
            if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e.id) end
            return "wait"
        end
        if now() - e.askedAt > F.LOAD_WAIT then e.match = false; return false end
        return "wait"
    end
    e.name = name
    e.level = reqLevelOf(e.id)
    if (e.price or 0) > F.MaxBuy(e.level) then e.match = false; return false end   -- fix 733
    e.vendor = vendorOf(e.id)
    if e.vendor and F.VENDOR_FACTOR and (e.price or 0) > e.vendor * F.VENDOR_FACTOR then e.match = false; return false end   -- fix 744
    e.suffix = F.SuffixOf(name)
    local c, sc = classOf(e.id)
    if m.only and not (c == m.only.c and sc == m.only.s) then e.match = false; return false end   -- decision 731
    if c == 2 and not F.WEAPONS then e.match = false; return false end   -- fix 737
    if F.NO_SLOTS and F.NO_SLOTS[select(4, ((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant)(e.id))] then e.match = false; return false end   -- fix 749
    if e.suffix and F.OFF[e.suffix] then e.suffix = nil end                -- fix 739
    if e.suffix == "knight" and not F.KnightFits(c, sc, e.level) then e.suffix = nil end   -- fixes 739, 741
    if e.suffix and c == 2 and not (F.CASTER[e.suffix] and F.WEAPON_KINDS[sc]) then e.suffix = nil end   -- fixes 723, 729
    e.match = (e.suffix ~= nil and (q == nil or q == 2)) and true or false
    return e.match
end

----------------------------------------------------------------------
-- What is a flip
----------------------------------------------------------------------
-- the offers of one item search: buyouts, the cheapest first; mine marked
function F.ReadOffers(key)
    local api = A()
    local out = {}
    local n = api.GetNumItemSearchResults and api.GetNumItemSearchResults(key) or 0
    for i = 1, n do
        local x = api.GetItemSearchResultInfo(key, i)
        local b = x and x.buyoutAmount
        if b and not isSecret(b) and b > 0 then
            local qty = math.max(1, x.quantity or 1)
            out[#out + 1] = { auctionID = x.auctionID, buyout = b, qty = qty, unit = math.floor(b / qty), link = x.itemLink,
                              mine = (x.containsOwnerItem or x.containsAccountItem) and true or nil }
        end
    end
    table.sort(out, function(a, b) return a.unit < b.unit end)
    return out
end

-- the verdict of an item's offers: nil, or { kind = "gap" | "few", n, sell, maxBuy, buy = offers to buy, cost, profit }
function F.Judge(offers, method, level, vendor)
    local m = F.METHODS[method or "flip"] or F.METHODS.flip
    local n = #offers
    if n == 0 then return nil end
    local sell, maxBuy, kind
    if n >= m.nth then
        local c1, cn = offers[1].unit, offers[m.nth].unit
        if cn < c1 * m.ratio then return nil end
        kind, sell = "gap", cn - 1
        maxBuy = math.floor(sell / m.ratio)
    elseif m.few then
        kind, maxBuy = "few", F.CHEAP - 1
    elseif m.single and n == 1 and vendor then             -- decision 746: the only offer, at most 2x the vendor price
        kind, maxBuy = "single", math.floor(vendor * (F.VENDOR_FACTOR or 1.25))   -- fixes 747, 748
    else
        return nil
    end
    maxBuy = math.min(maxBuy, F.MaxBuy(level))            -- fix 724, 733: 1.50 gold from level 40
    if vendor and F.VENDOR_FACTOR then maxBuy = math.min(maxBuy, math.floor(vendor * F.VENDOR_FACTOR)) end   -- fixes 744, 747
    local buy, cost, profit = {}, 0, 0
    for _, o in ipairs(offers) do
        if not o.mine and o.qty == 1 and o.unit <= maxBuy then
            buy[#buy + 1] = o
            cost = cost + o.buyout
            if sell then profit = profit + math.floor(sell * (1 - F.CUT)) - o.buyout end
        end
    end
    if #buy == 0 then return nil end
    return { kind = kind, n = n, sell = sell, maxBuy = maxBuy, buy = buy, cost = cost, profit = sell and profit or nil }
end

-- fix 753 (MadDadVibe): a dismissed item (item + suffix) never comes back in the flip searches
function F.Blocked(ks) return ks ~= nil and db().black[ks] ~= nil end
local function skipped(ks) return F.Blocked(ks) end

-- the answer of one item search: the row of the item, judged
function F.Take(e, offers, check)
    local ks = e.ks
    local r = rows[ks]
    if not r then
        r = { ks = ks, itemKey = e.key, itemID = e.id, commodity = false, onDone = F.OnDone }
        rows[ks] = r
    end
    r.name, r.icon = e.name or r.name, e.icon or r.icon
    r.level = e.level or r.level or reqLevelOf(e.id)
    r.vendor = e.vendor or r.vendor or vendorOf(e.id)
    local j = F.Judge(offers, F.method, r.level, r.vendor)
    local room = F.MAX_HELD and (F.MAX_HELD - F.Held(e.id, r.name)) or nil   -- fix 750
    if j and room then
        if room <= 0 then j = nil
        else
            while #j.buy > room do table.remove(j.buy) end
            j.cost, j.profit = 0, j.sell and 0 or nil
            for _, o in ipairs(j.buy) do
                j.cost = j.cost + o.buyout
                if j.sell then j.profit = j.profit + math.floor(j.sell * (1 - F.CUT)) - o.buyout end
            end
        end
    end
    r.offers, r.fresh, r.hold = nil, nil, nil
    if not j then
        r.kind = nil
        if check then OMQ:Print("item flips: " .. (r.name or ("item " .. r.itemID)) .. " is no flip any more") end
    else
        r.kind, r.n, r.sell, r.maxBuy, r.cost, r.profit = j.kind, j.n, j.sell, j.maxBuy, j.cost, j.profit
        r.offers = j.buy
        r.price = j.buy[1].buyout
        r.link = j.buy[1].link or r.link
        r.fresh = { at = now(), seq = H().searchSeq or 0 }
        if check then r.hold = now() + ((B() and B().FRESH) or 10) end    -- the next clicks buy: no other search meanwhile
    end
    F.Build()
    return r
end

function F.Build()
    for i = #list, 1, -1 do list[i] = nil end
    for ks, r in pairs(rows) do
        if r.kind and r.offers and #r.offers > 0 and not r.bought and not skipped(ks, r.offers[1].unit) then list[#list + 1] = r end
    end
    table.sort(list, function(a, b)
        if (a.kind == "gap") ~= (b.kind == "gap") then return a.kind == "gap" end
        if a.kind == "gap" and a.profit ~= b.profit then return a.profit > b.profit end
        if a.kind ~= "gap" and a.cost ~= b.cost then return a.cost < b.cost end
        return a.ks < b.ks
    end)
    if frame and frame:IsShown() then F.Paint() end
end
function F.List() return list end
F._rows = function() return rows end

----------------------------------------------------------------------
-- The searches
----------------------------------------------------------------------
function F.Quality()
    local Q = Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.UncommonQuality
    return Q and { Q } or {}
end
function F.Query(c, s)
    local m = F.METHODS[(run and run.method) or F.method or "flip"] or F.METHODS.flip
    local q = OMQ.Prices.GameQuery(c, s, m.minLevel or F.MIN_LEVEL, m.maxLevel or F.MAX_LEVEL, sorts())
    q.filters = F.Quality()
    return q
end

function F.Running() return run ~= nil end
F._run = function() return run end

local function status(text)
    F.statusText = text
    if frame and frame:IsShown() then F.Paint() end
end
local function progress()
    if not run then return end
    if run.qi < #run.queue or run.q and run.q.kind == "browse" then
        status(string.format("searching the auction house... %d of %d searches, %d items to look at", run.qi, #run.queue, #run.items))
    else
        status(string.format("looking at the items... %d of %d, %d flips so far", run.ii, #run.items, #list))
    end
end

local function send()
    local q = run.q
    q.lastAt, q.resp, q.dropped, q.answered = now(), nil, nil, nil
    run.state = "waiting"
    local api = A()
    local ok, err
    if q.kind == "browse" then ok, err = pcall(own, api.SendBrowseQuery, F.Query(q.c, q.s))
    else ok, err = pcall(own, api.SendSearchQuery, q.e.key, sorts(), true) end
    if not ok then F.Finish("the search failed: " .. tostring(err)) end
end

-- the lines of the browse list; false when it is not ours (its items belong to another class)
local function readList()
    local api = A()
    local ok, l = pcall(api.GetBrowseResults)
    if not ok or type(l) ~= "table" then return {}, true end
    local foreign, checked = 0, 0
    for _, res in ipairs(l) do
        local id = res.itemKey and res.itemKey.itemID
        if id and not isSecret(id) and checked < 30 then
            checked = checked + 1
            local c = classOf(id)
            if c and c ~= run.q.c then foreign = foreign + 1 end
        end
    end
    if foreign >= 2 or (foreign >= 1 and checked < 10) then return l, false end
    return l, true
end
local function fullBrowse()
    local api = A()
    if not api.HasFullBrowseResults then return true end
    local ok, f = pcall(api.HasFullBrowseResults)
    return ok and f and true or false
end

-- the loaded lines that match go into the queue of item searches; how many still load
local function consider()
    if not run then return 0 end
    local waiting = 0
    for _, e in pairs(lines) do
        if not e.queued then
            local m = F.Consider(e)
            if m == "wait" then waiting = waiting + 1
            elseif m and F.Blocked(e.ks) then e.queued = true                  -- fix 753: on the blacklist
            elseif m then e.queued = true; run.items[#run.items + 1] = e end
        end
    end
    run.waiting = waiting
    return waiting
end
F.waitingCount = function() return run and run.waiting or 0 end

local function browseDone(l, how)
    local q = run.q
    local capped = l and #l > 0 and #l % F.PAGE == 0
    local P = OMQ.Prices
    local subs = capped and q.s == nil and P and P.Subclasses and P.Subclasses(q.c) or nil
    if subs and #subs >= 2 then
        for _, s in ipairs(subs) do run.queue[#run.queue + 1] = { c = q.c, s = s } end
    else
        for _, res in ipairs(l or {}) do
            local k, price, qty = res.itemKey, res.minPrice, res.totalQuantity
            if k and k.itemID and not isSecret(k.itemID) and type(price) == "number" and not isSecret(price) and price > 0 then
                local ks = keyString(k)
                local e = lines[ks]
                if not e then
                    lines[ks] = { ks = ks, key = k, id = k.itemID, price = math.floor(price), qty = (not isSecret(qty) and tonumber(qty)) or 1 }
                end
            end
        end
        run.lines = run.lines + #(l or {})
    end
    run.log[#run.log + 1] = string.format("%d%s: %s, %d lines, %d pages", q.c, q.s and ("." .. q.s) or "", how, #(l or {}), q.pages or 0)
    run.q, run.state, run.gapAt = nil, "gap", now()
    consider()
    progress()
end

local function itemDone(offers, how)
    local q = run.q
    run.q, run.state, run.gapAt = nil, "gap", now()
    if offers then F.Take(q.e, offers, q.check) end
    if how ~= "ok" then run.log[#run.log + 1] = string.format("item %s: %s", q.e.ks, how) end
    run.searched = run.searched + 1
    progress()
end

-- a row checked for a click holds the searches still, so its auctions stay the game's latest
function F.Holding()
    for _, r in pairs(rows) do
        if r.hold and now() < r.hold and r.offers and #r.offers > 0 and not r.bought then return true end
    end
    return false
end

local function nextSearch()
    if #run.checks > 0 then
        local e = table.remove(run.checks, 1)
        run.q = { kind = "item", e = e, check = true, tries = 1 }
        send()
        return
    end
    if run.qi < #run.queue then
        run.qi = run.qi + 1
        local f = run.queue[run.qi]
        run.q = { kind = "browse", c = f.c, s = f.s, pages = 1, tries = 1 }
        send()
        return
    end
    if run.ii < #run.items then
        run.ii = run.ii + 1
        run.q = { kind = "item", e = run.items[run.ii], tries = 1 }
        send()
        return
    end
    -- items still loading: their searches come when they are there
    if consider() > 0 or run.ii < #run.items then return end
    F.Finish()
end

function F.Step()
    if not run then return end
    local h = H()
    if not (h and h.open) then F.Finish("the auction house closed"); return end
    h.quietUntil = now() + 60                              -- the helper holds still while the search runs
    local P = OMQ.Prices
    if run.state == "start" or run.state == "gap" then
        if P and P.Busy and P.Busy() then status("waiting for the price scan to end..."); return end
        local wait = run.state == "start" and F.FIRST_WAIT or ((run.qi < #run.queue and #run.checks == 0) and F.GAP or F.ITEM_GAP)
        if now() - (run.state == "start" and run.t0 or run.gapAt) < wait then return end
        if F.Holding() then return end
        if not ready() then return end
        if B() and B().Busy and B().Busy() then return end   -- a purchase on its way goes first
        nextSearch()
        return
    end
    local q = run.q
    if not q then return end
    if q.kind == "item" then
        if q.dropped then
            if not ready() then return end
            q.dropped = nil
            if q.tries >= F.TRIES then itemDone(nil, "no answer") else q.tries = q.tries + 1; send() end
            return
        end
        if now() - q.lastAt > F.ITEM_QUIET then
            if q.answered then itemDone(F.ReadOffers(q.e.key), "stopped")
            elseif q.tries >= F.TRIES then itemDone(nil, "no answer")
            elseif ready() then q.tries = q.tries + 1; send() end
        end
        return
    end
    if q.dropped then
        if not ready() then return end
        q.dropped = nil
        if q.answered then q.more, q.pages = true, q.pages - 1
        elseif q.tries >= F.TRIES then browseDone(nil, "no answer"); return
        else q.tries = q.tries + 1; send(); return end
    end
    if q.more then
        if not ready() then return end
        q.more, q.lastAt, q.pages = false, now(), q.pages + 1
        local ok, err = pcall(own, A().RequestMoreBrowseResults)
        if not ok then browseDone(nil, "page failed: " .. tostring(err)) end
        return
    end
    if now() - q.lastAt > F.QUIET then
        if q.answered then browseDone(readList(), "stopped")
        elseif q.tries >= F.TRIES then browseDone(nil, "no answer")
        elseif ready() then q.tries = q.tries + 1; send() end
    end
end

function F.OnBrowse()
    if not run or run.state ~= "waiting" or not run.q or run.q.kind ~= "browse" then return end
    local q = run.q
    local l, mine = readList()
    if not mine then return end                            -- the answer to another search
    if #l == 0 then
        if q.resp and fullBrowse() then browseDone(l, "empty") end
        return
    end
    q.answered, q.lastAt = true, now()
    if fullBrowse() then browseDone(l, "complete")
    elseif q.pages >= F.PAGES then browseDone(l, "page limit")
    elseif A().RequestMoreBrowseResults then q.more = true; F.Step()
    else browseDone(l, "one page") end
end

local function sameKey(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.itemID == b.itemID and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end
function F.OnItem(key)
    if not run or run.state ~= "waiting" or not run.q or run.q.kind ~= "item" then return end
    local q = run.q
    if not sameKey(key, q.e.key) then return end
    q.answered, q.lastAt = true, now()
    local offers = F.ReadOffers(q.e.key)
    local api = A()
    local full = true
    if api.HasFullItemSearchResults then
        local ok, f = pcall(api.HasFullItemSearchResults, q.e.key)
        full = not ok or f ~= false
    end
    if #offers >= F.METHODS[run.method or "flip"].nth or full then itemDone(offers, "ok") end   -- the first page holds the cheapest ones
end

local function newRun(queue)
    run = { method = F.method, state = "start", t0 = now(), queue = queue, qi = 0, items = {}, ii = 0, checks = {}, lines = 0, searched = 0,
            waiting = 0, log = {} }
end

-- decision 736 (parked flips searched first) was taken back in decision 745: expired flips go to the vendor or the enchanter

function F.Start(method)
    if method then F.method = method end
    if run then return false, "already searching" end
    if not F.METHODS[F.method or ""] then return false, "choose a method first" end
    local h = H()
    if not (h and h.open) then return false, "open the auction house first (with the auction helper on)" end
    local api = A()
    if not (api and api.SendBrowseQuery and api.GetBrowseResults and api.SendSearchQuery) then return false, "this client has no browse list" end
    if OMQ.AHTest and OMQ.AHTest.Running and OMQ.AHTest.Running() then return false, "the test window is searching" end
    local queue = {}
    local om = F.METHODS[F.method].only
    if om then queue[1] = { c = om.c, s = om.s }                -- decision 731: one subcategory
    else for _, c in ipairs(F.CLASSES) do queue[#queue + 1] = { c = c } end end
    for k in pairs(lines) do lines[k] = nil end
    for k in pairs(rows) do rows[k] = nil end              -- a new search: every offer is new
    newRun(queue)
    F.Build()
    local m = F.METHODS[F.method]
    status(string.format("searching the auction house for green gear of level %d-%d (%s)...", m.minLevel or F.MIN_LEVEL,
        m.maxLevel or F.MAX_LEVEL, m.label))
    return true
end

function F.Finish(why)
    if not run then return end
    local r = run
    run = nil
    local h = H()
    if h then h.quietUntil = nil end
    if not r.checkOnly then
        F.last = { why = why, lines = r.lines, items = #r.items, secs = now() - r.t0, log = r.log }
        db().log = r.log
    end
    F.Build()
    if why then status("search stopped: " .. why)
    elseif not r.checkOnly then
        status(string.format("%d flips among %d items with the suffixes (%d offers, %.0f s)", #list, #r.items, r.lines, now() - r.t0))
    end
    if h and h.Pump then pcall(h.Pump) end
end
function F.Cancel() if run then F.Finish("cancelled") end end

-- a row searched again for a click: ahead of everything else; without a running search a short one just for it
function F.Check(r)
    local e = { ks = r.ks, key = r.itemKey, id = r.itemID, name = r.name, icon = r.icon }
    if not run then
        local h = H()
        if not (h and h.open) then return false end
        newRun({})
        run.checkOnly, run.state, run.gapAt = true, "gap", now() - 10
    end
    for _, x in ipairs(run.checks) do if x.ks == e.ks then return true end end
    table.insert(run.checks, 1, e)
    r.checking = true
    F.Step()
    return true
end

----------------------------------------------------------------------
-- Buying (from a click)
----------------------------------------------------------------------
local function fresh(r)
    return r.fresh and r.offers and #r.offers > 0 and B().Fresh(r)
end
function F.Ready(r) return fresh(r) and true or false end

function F.Buy(r)
    local b, h = B(), H()
    if not (type(r) == "table" and h.open) then return false end
    if r.bought or b.Busy() then return false end
    if F.MAX_HELD and F.Held(r.itemID, r.name) >= F.MAX_HELD then   -- fix 750: already 2 of it
        r.bought = true; F.Build()
        OMQ:Print("item flips: you already have " .. F.MAX_HELD .. "x " .. (r.name or "this item"))
        return false
    end
    if fresh(r) then
        r.paid, r.paidLink = r.offers[1].buyout, r.offers[1].link
        r.hold = now() + (b.FRESH or 10)
        return b.Buy(r, 1)
    end
    if run and run.q and run.q.kind == "item" and run.q.check and run.q.e.ks == r.ks then return false end   -- on its way
    return F.Check(r)
end
function F.BuyNext() return F.Buy(list[1]) end

-- the purchase of one offer is through (or refused)
function F.OnDone(r, ok)
    if ok then
        F.bought.n = F.bought.n + 1
        F.bought.spent = F.bought.spent + (r.paid or 0)
        F.bought.worth = F.bought.worth + (r.sell and math.floor(r.sell * (1 - F.CUT)) or 0)
        F.lastName, F.lastKey = r.name, r.itemKey
        F.Remember(r.itemID, r.paid, r.sell, F.LinkSuffix(r.paidLink))
        F.lastName, F.lastKey = nil, nil
        if not (r.offers and #r.offers > 0) then r.bought = true end
    else
        r.fresh, r.hold = nil, nil
    end
    F.Build()
end

-- the flips I bought: never to the vendor or the enchanter, never posted under what they cost
function F.Remember(id, paid, sell, sfx)
    if not id then return end
    local o = db().owned
    local x = o[id] or { n = 0, paid = 0 }
    x.n, x.paid, x.sell, x.t = x.n + 1, math.max(x.paid or 0, paid or 0), sell or x.sell, stamp()
    if sfx then                                            -- per suffix (decision 725)
        x.sfx = x.sfx or {}
        x.sfx[sfx] = math.max(x.sfx[sfx] or 0, paid or 0)
    end
    o[id] = x
    F.Note(id, "b", paid, F.lastName)
    x.sk = F.SuffixOf(F.lastName) or x.sk                  -- decision 743: the suffix of what I bought
    if type(F.lastName) == "string" then                   -- fix 750: pieces held per name (item + suffix)
        x.held = x.held or {}
        x.held[F.lastName] = (x.held[F.lastName] or 0) + 1
        if type(F.lastKey) == "table" then                 -- fix 753: for the search from the blacklist
            x.keys = x.keys or {}
            x.keys[F.lastName] = { itemID = F.lastKey.itemID, itemLevel = F.lastKey.itemLevel, itemSuffix = F.lastKey.itemSuffix }
        end
    end
    F.Stat(id, "b", paid, F.lastName)
end

-- decision 735 (MadDadVibe): green BoE gear I looted (mailed to the flip character) is sold like a flip; what it "cost"
-- is its vendor price. Taken in at the bag scan of the auction helper, once per item while it is mine.
function F.LootGreen(it, classID, equipLoc, comm)
    if comm or not it or it.isBound then return false end
    if it.quality ~= 2 or not (classID == 2 or classID == 4) then return false end
    return type(equipLoc) == "string" and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and equipLoc ~= "INVTYPE_BAG"
end
function F.AdoptLoot(id, vendor, link, name)
    if type(id) ~= "number" or F.Owns(id) then return false end
    F.lastName = name
    F.Remember(id, vendor or 0, nil, F.LinkSuffix(link))
    F.lastName = nil
    local x = db().owned[id]
    x.loot = true
    local it = db().items and db().items[id]               -- F.Note (below) made it
    if it then it.loot = (it.loot or 0) + 1 end
    return true
end
function F.IsLoot(id)
    local x = OMQDB and OMQDB.flip and OMQDB.flip.owned and OMQDB.flip.owned[id]
    return x and x.loot and true or false
end

----------------------------------------------------------------------
-- decision 728 (MadDadVibe): the flip history (/omq flip) and the resale rules
-- Per item: bought, sold, came back unsold, vendored, spent and got (OMQDB.flip.items, kept for good); the totals
-- are their sums. A flip is posted up to REPOSTS times; one that came back unsold that often goes to the vendor
-- (no protection any more, the helper's "unsold" rule takes it). One that came back is posted again only while
-- that brings at least REPOST_GAIN over what it cost, after the cut - else it waits in the bags.
----------------------------------------------------------------------
F.SELL_FACTOR = 3        -- fix 730 (MadDadVibe): a flip is posted at up to 3 times its price (decision 725: 2)
F.SELL_MIN_CAP = 9900    -- fix 751 (MadDadVibe): a cap under 1 gold is raised to 99 silver (cheap cloth not sold for a few silver)
F.REPOSTS = 5
F.REPOST_GAIN = 1.2
local function items()
    local d = db()
    d.items = d.items or {}
    return d.items
end
-- one event of an item: "b" bought (c = paid), "s" sold (c = the money of the mail), "u" unsold, "v" vendored (c = price)
function F.Note(id, kind, c, name)
    if type(id) ~= "number" then return end
    local it = items()[id] or { b = 0, s = 0, u = 0, v = 0, spent = 0, got = 0, cost = 0 }
    items()[id] = it
    if type(name) == "string" and not isSecret(name) then it.name = name end
    c = tonumber(c) or 0
    if kind == "b" then it.b, it.spent = it.b + 1, it.spent + c
    elseif kind == "s" then it.s, it.got = it.s + 1, it.got + c
    elseif kind == "u" then it.u = it.u + 1
    elseif kind == "v" then it.v, it.got = it.v + 1, it.got + c
    elseif kind == "d" then it.d, it.got = (it.d or 0) + 1, it.got + c end   -- decision 745: disenchanted (its value)
    it.t = stamp()
end
-- the result mail of a flip auction (AH.ScanMail via AH.Result); true when the helper's own unsold rule must not count it
function F.Result(id, sold, got, name)
    local x = db().owned[id]
    if not x then return false end
    if sold then
        local paid = F.Paid(id) or 0
        got = tonumber(got) or 0
        if x.dep and got > x.dep then got = got - x.dep end   -- decision 732: the mail gives the deposit back, not earned
        x.dep = nil
        F.Note(id, "s", got, name)
        F.Stat(id, "s", got, name, paid)                   -- decision 743
        F.Release(id, name)                                -- fix 750
        local it = items()[id]
        it.cost = (it.cost or 0) + paid                    -- what the sold pieces cost
        x.n = (x.n or 1) - 1
        if x.n <= 0 then db().owned[id] = nil end
        return false
    end
    F.Note(id, "u", 0, name)
    F.Stat(id, "u", 0, name, nil, x.dep)                   -- decision 743
    local it = items()[id]
    it.fees = (it.fees or 0) + (x.dep or 0)                -- decision 732: the deposit of an unsold auction is lost
    x.dep = nil
    x.unsold = (x.unsold or 0) + 1
    if x.unsold >= F.REPOSTS then x.released = true; return false end   -- to the vendor now
    return true
end
-- sold at the vendor (UI/Vendor.lua): a flip that came back too often, or one sold by hand there
function F.Vendored(id, price)
    local x = db().owned[id]
    if not x then return end
    local it = items()[id]
    F.Note(id, "v", price)
    F.Stat(id, "v", price, nil, F.PaidAny(id) or 0)        -- decision 743
    F.Release(id)                                          -- fix 750
    if x.released or F.Expired(x) then F.NoteVendored(id, price, x) end   -- 5x unsold or 48 hours (decision 745)
    it = items()[id]
    it.cost = (it.cost or 0) + (F.PaidAny(id) or 0)
    x.n = (x.n or 1) - 1
    if x.n <= 0 then db().owned[id] = nil end
end
function F.Posted(id, deposit)
    local x = db().owned[id]
    if x then x.posts, x.t, x.dep = (x.posts or 0) + 1, stamp(), tonumber(deposit) or 0 end
end
-- a flip that came back: posted again only when it brings at least REPOST_GAIN times its price after the cut
function F.Waits(id, price)
    local x = OMQDB and OMQDB.flip and OMQDB.flip.owned and OMQDB.flip.owned[id]
    if not (x and (x.unsold or 0) >= 1 and x.paid and x.paid > 0) or type(price) ~= "number" then return false end
    return price * (1 - F.CUT) < x.paid * F.REPOST_GAIN
end
function F.PaidAny(id)
    local x = OMQDB and OMQDB.flip and OMQDB.flip.owned and OMQDB.flip.owned[id]
    return x and x.paid
end
----------------------------------------------------------------------
-- decision 743 (MadDadVibe): which suffixes sell - per suffix (and armor kind): bought, sold, came back, to the vendor,
-- spent, got, cost of the sold/vendored pieces, lost deposits. OMQDB.flip.sfx[key] = { all = rec, [subclass] = rec }.
-- Suffix from the item name (EN + DE), else the one remembered at the purchase, else "other".
----------------------------------------------------------------------
F.ARMOR_KINDS = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate" }
local function newRec() return { b = 0, s = 0, u = 0, v = 0, spent = 0, got = 0, cost = 0, fees = 0 } end
local function addRec(r, kind, c, cost, fee)
    c = tonumber(c) or 0
    if kind == "b" then r.b, r.spent = r.b + 1, r.spent + c
    elseif kind == "s" then r.s, r.got, r.cost, r.rev = r.s + 1, r.got + c, r.cost + (cost or 0), (r.rev or 0) + c
    elseif kind == "u" then r.u, r.fees = r.u + 1, r.fees + (tonumber(fee) or 0)
    elseif kind == "v" then r.v, r.got, r.cost = r.v + 1, r.got + c, r.cost + (cost or 0)
    elseif kind == "d" then r.d, r.got, r.cost = (r.d or 0) + 1, r.got + c, r.cost + (cost or 0) end
end
function F.KindOf(id)
    local c, sc = classOf(id)
    if c == 4 and F.ARMOR_KINDS[sc] then return sc end
    return 0                                                -- rings, amulets, cloaks of no kind, weapons
end
function F.Stat(id, kind, c, name, cost, fee)
    if type(id) ~= "number" then return end
    F.MigrateStats()                                       -- the old history first, so nothing counts twice
    local d = db()
    d.sfx = d.sfx or {}
    local x = d.owned and d.owned[id]
    local key = F.SuffixOf(name) or (x and x.sk) or "other"
    local e = d.sfx[key] or { all = newRec() }
    d.sfx[key] = e
    local k = F.KindOf(id)
    e[k] = e[k] or newRec()
    addRec(e.all, kind, c, cost, fee)
    addRec(e[k], kind, c, cost, fee)
    F.MigrateBrackets()                                    -- decision 746: per level bracket of the buttons
    d.brk = d.brk or {}
    for _, b in ipairs(F.BracketsOf(id)) do
        d.brk[b] = d.brk[b] or newRec()
        addRec(d.brk[b], kind, c, cost, fee)
    end
end
-- decision 746: the buttons an item belongs to by its required level (plate 40-42 counts in both of its brackets)
function F.BracketsOf(id)
    local out = {}
    local lvl = reqLevelOf(id)
    if type(lvl) ~= "number" then return out end
    local c, sc = classOf(id)
    for _, key in ipairs(F.BUTTONS) do
        local m = F.METHODS[key]
        if m and lvl >= (m.minLevel or 0) and lvl <= (m.maxLevel or 999)
           and (not m.only or (c == m.only.c and sc == m.only.s)) then out[#out + 1] = key end
    end
    return out
end
-- once: the whole per-item history from before into the brackets (the level is known per item)
function F.MigrateBrackets()
    local d = db()
    if d.brkDone then return end
    d.brkDone = true
    d.brk = d.brk or {}
    for id, it in pairs(items()) do
        for _, b in ipairs(F.BracketsOf(id)) do
            local r = d.brk[b] or newRec()
            d.brk[b] = r
            for _, f in ipairs({ "b", "s", "u", "v", "d", "spent", "got", "cost", "fees" }) do r[f] = (r[f] or 0) + (it[f] or 0) end
            r.rev = (r.rev or 0) + ((it.s or 0) > 0 and (it.got or 0) or 0)   -- before: the sold pieces' money (vendor included)
        end
    end
end
function F.BracketRec(key)
    F.MigrateBrackets()
    local d = db()
    return (d.brk and d.brk[key]) or newRec()
end
-- the track record of one button, for its tooltip
function F.BracketTip(key)
    local r = F.BracketRec(key)
    return string.format("bought %d, sold %d, revenue %s", r.b, r.s, money(r.rev or 0)),
        string.format("back unsold %d, vendor %d, disenchanted %d, profit %s", r.u, r.v, r.d or 0, F.Signed(r.got - r.cost - r.fees))
end
function F.BracketRows()
    local out = {}
    for _, key in ipairs(F.BUTTONS) do
        local r = F.BracketRec(key)
        local profit = r.got - r.cost - r.fees
        local done = r.s + r.v + (r.d or 0)
        out[#out + 1] = { key = key, name = F.METHODS[key].label,
            text = string.format("bought %d, sold %d, back %d, vendor/DE %d", r.b, r.s, r.u, r.v + (r.d or 0)),
            result = "revenue " .. money(r.rev or 0) .. ", " .. F.Signed(profit), gain = done > 0 and profit or nil }
    end
    return out
end
-- the last flips that came back too often and went to the vendor
F.VENDOR_LOG = 10
function F.NoteVendored(id, price, x)
    local d = db()
    d.vlog = d.vlog or {}
    local it = items()[id] or {}
    local paid = F.PaidAny(id) or 0
    table.insert(d.vlog, 1, { id = id, name = it.name or ("item " .. id), sk = x.sk or F.SuffixOf(it.name) or "other",
        back = x.unsold or 0, loss = (tonumber(price) or 0) - paid - (it.fees or 0), t = stamp() })
    while #d.vlog > F.VENDOR_LOG do table.remove(d.vlog) end
end
-- once: the per-item history from before, where the stored name shows the suffix clearly
function F.MigrateStats()
    local d = db()
    if d.sfxDone then return end
    d.sfxDone = true
    d.sfx = d.sfx or {}
    for id, it in pairs(items()) do
        local key = F.SuffixOf(it.name)
        if key then
            local e = d.sfx[key] or { all = newRec() }
            d.sfx[key] = e
            local k = F.KindOf(id)
            e[k] = e[k] or newRec()
            for _, r in ipairs({ e.all, e[k] }) do
                for _, f in ipairs({ "b", "s", "u", "v", "spent", "got", "cost", "fees" }) do r[f] = r[f] + (it[f] or 0) end
            end
        end
    end
end
local function label(key)
    if key == "other" then return "other suffixes" end
    return "of the " .. key:sub(1, 1):upper() .. key:sub(2)
end
local function rate(r)
    local n = r.s + r.v + (r.d or 0)
    if n == 0 then return nil end
    return math.floor(r.s * 100 / n + 0.5)
end
-- the rows of the suffix view: one per suffix, best selling first, then the vendor log
function F.SuffixRows()
    F.MigrateStats()
    local d = db()
    local out = {}
    for key, e in pairs(d.sfx or {}) do
        local r = e.all
        local tip = {}
        for k = 1, 4 do
            local a = e[k]
            if a and a.b + a.s + a.u + a.v > 0 then
                local q = rate(a)
                tip[#tip + 1] = string.format("%s: bought %d, sold %d, back %d, vendor %d%s", F.ARMOR_KINDS[k], a.b, a.s, a.u, a.v,
                    q and (", " .. q .. "% sold") or "")
            end
        end
        if e[0] and e[0].b + e[0].s + e[0].u + e[0].v > 0 then
            tip[#tip + 1] = string.format("other gear: bought %d, sold %d, back %d, vendor %d", e[0].b, e[0].s, e[0].u, e[0].v)
        end
        local q = rate(r)
        local profit = r.got - r.cost - r.fees
        out[#out + 1] = { key = key, name = label(key), rate = q,
            text = string.format("bought %d, sold %d, back %d, vendor %d%s", r.b, r.s, r.u, r.v,
                (r.d or 0) > 0 and (", disenchanted " .. r.d) or ""),
            result = (q and (q .. "% sold, ") or "") .. F.Signed(profit), gain = (r.s + r.v + (r.d or 0)) > 0 and profit or nil,
            low = q and q < 50, tip = tip }
    end
    table.sort(out, function(a, b)
        if (a.rate or -1) ~= (b.rate or -1) then return (a.rate or -1) > (b.rate or -1) end
        return a.key < b.key
    end)
    local vl = d.vlog or {}
    if #vl > 0 then
        out[#out + 1] = { name = "|cffffd100To the vendor after " .. F.REPOSTS .. "x unsold:|r", text = "", result = "", head = true }
        for _, v in ipairs(vl) do
            out[#out + 1] = { name = "  " .. v.name, text = label(v.sk) .. ", back " .. v.back .. "x", result = F.Signed(v.loss),
                gain = v.loss }
        end
    end
    return out
end

function F.Totals()
    local t = { b = 0, s = 0, u = 0, v = 0, d = 0, spent = 0, got = 0, cost = 0, fees = 0, loot = 0 }
    for _, it in pairs(items()) do
        for k in pairs(t) do t[k] = t[k] + (it[k] or 0) end
    end
    t.profit = t.got - t.cost - t.fees                    -- what the sold and vendored pieces brought over their price, minus lost deposits
    t.open = t.spent - t.cost                             -- still in the bags or on the auction house
    return t
end
local function signed(c)
    if c < 0 then return "-" .. money(-c) end
    return "+" .. money(c)
end
F.Signed = signed
-- decision 732 (MadDadVibe): the history in a small window; F.Rows gives its lines, F.History the same as text
function F.Rows()
    local t = F.Totals()
    local head = {
        { "Bought", string.format("%d for %s", t.b, money(t.spent)) },
        { "Sold", string.format("%d for %s", t.s, money(t.got)) },
        { "Came back unsold", tostring(t.u) },
        { "To the vendor / disenchanted", t.v .. " / " .. t.d },   -- decision 745
        { "Deposits lost (unsold)", money(t.fees) },
        { "Earned with flips", signed(t.profit) .. " (on " .. money(t.cost) .. " of sold pieces)" },
        { "Still out (bags / AH)", money(t.open) },
        { "Of them from loot", string.format("%d (vendor price as cost)", t.loot) },   -- decision 735
    }
    local rows = {}
    for id, it in pairs(items()) do rows[#rows + 1] = { id = id, it = it } end
    table.sort(rows, function(a, b) return (a.it.t or 0) > (b.it.t or 0) end)
    local out = {}
    for _, r in ipairs(rows) do
        local it = r.it
        local done = (it.s + it.v + (it.d or 0)) > 0
        out[#out + 1] = {
            id = r.id, name = it.name or ("item " .. r.id),
            text = string.format("bought %d, sold %d, unsold %d%s%s", it.b, it.s, it.u, (it.v > 0 and (", vendor " .. it.v) or "") .. ((it.d or 0) > 0 and (", disenchanted " .. it.d) or ""),
                (it.fees or 0) > 0 and (", deposits " .. money(it.fees)) or ""),
            result = done and signed((it.got or 0) - (it.cost or 0) - (it.fees or 0)) or ("spent " .. money(it.spent)),
            gain = done and ((it.got or 0) - (it.cost or 0) - (it.fees or 0)) or nil,
        }
    end
    return head, out
end
function F.History()
    local head, rows = F.Rows()
    local out = { "item flips:" }
    for _, h in ipairs(head) do out[#out + 1] = "  " .. h[1] .. ": " .. h[2] end
    for i = 1, math.min(15, #rows) do out[#out + 1] = "  " .. rows[i].name .. ": " .. rows[i].text .. ", " .. rows[i].result end
    if #rows > 15 then out[#out + 1] = string.format("  ... and %d more items", #rows - 15) end
    if #rows == 0 then out[#out + 1] = "  nothing bought with item flips yet" end
    out[#out + 1] = "by level bracket:"                    -- decision 746
    for _, r in ipairs(F.BracketRows()) do out[#out + 1] = "  " .. r.name .. ": " .. r.text .. ", " .. r.result end
    local sr = F.SuffixRows()                              -- decision 743
    if #sr > 0 then out[#out + 1] = "by suffix:" end
    for _, r in ipairs(sr) do out[#out + 1] = "  " .. r.name .. (r.text ~= "" and (": " .. r.text) or "") .. (r.result ~= "" and (", " .. r.result) or "") end
    return out
end

local hist
F.HIST_ROWS = 14
F.histOffset = 0
local function histBuild()
    local ok, f = pcall(CreateFrame, "Frame", "OneMoreQuestFlipHistory", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then return end
    hist = f
    f:SetSize(420, 212 + F.HIST_ROWS * 16)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText("One More Quest - flip history")
    local view = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")   -- decision 743: items / suffixes
    view:SetSize(90, 20)
    view:SetPoint("TOPRIGHT", -12, -28)
    view:SetScript("OnClick", function()
        F.histView = (F.histView == "sfx") and "brk" or (F.histView == "brk") and "items" or "sfx"   -- decision 746
        F.histOffset = 0
        F.PaintHistory()
    end)
    f.view = view
    f.head = {}
    for i = 1, 8 do
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", 16, -30 - (i - 1) * 16)
        local v = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        v:SetPoint("TOPLEFT", 170, -30 - (i - 1) * 16)
        v:SetWidth(234)
        v:SetJustifyH("LEFT")
        f.head[i] = { l = l, v = v }
    end
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", 14, -166)
    box:SetSize(392, F.HIST_ROWS * 16)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, d)
        F.histOffset = math.max(0, F.histOffset - d)
        F.PaintHistory()
    end)
    f.rows = {}
    for i = 1, F.HIST_ROWS do
        local r = CreateFrame("Frame", nil, box)
        r:SetSize(392, 16)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
        r:EnableMouse(true)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 2, 0)
        r.name:SetWidth(300)
        r.name:SetJustifyH("LEFT")
        r.res = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.res:SetPoint("RIGHT", -2, 0)
        r.res:SetJustifyH("RIGHT")
        r:SetScript("OnEnter", function(self)
            if not (self.data and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.data.name)
            if self.data.text ~= "" then GameTooltip:AddLine(self.data.text, 1, 1, 1, true) end
            if self.data.result ~= "" then GameTooltip:AddLine(self.data.result, 1, 1, 1) end
            for _, l in ipairs(self.data.tip or {}) do GameTooltip:AddLine(l, 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = r
    end
    f.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 2, -2)
    f.empty:SetText("nothing bought with item flips yet")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 12)
    hint:SetText("Mouse wheel: scroll   Hover: details")
    if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestFlipHistory") end
end
function F.PaintHistory()
    if not hist then return end
    local head, rows = F.Rows()
    for i, h in ipairs(head) do hist.head[i].l:SetText(h[1]); hist.head[i].v:SetText(h[2]) end
    local sfxView = F.histView == "sfx"
    if sfxView then rows = F.SuffixRows() elseif F.histView == "brk" then rows = F.BracketRows() end
    if hist.view then hist.view:SetText(sfxView and "Brackets" or (F.histView == "brk") and "Items" or "Suffixes") end
    F.histOffset = math.max(0, math.min(F.histOffset, math.max(0, #rows - F.HIST_ROWS)))
    for i, r in ipairs(hist.rows) do
        local d = rows[i + F.histOffset]
        r.data = d
        if d then
            r.name:SetText(d.name .. (d.text ~= "" and ("  |cffaaaaaa" .. d.text .. "|r") or ""))
            r.res:SetText(d.result)
            if d.low or (d.gain and d.gain < 0) then r.res:SetTextColor(1, 0.3, 0.3) elseif d.gain then r.res:SetTextColor(0.3, 1, 0.3) else r.res:SetTextColor(0.8, 0.8, 0.8) end
            r:Show()
        else r:Hide() end
    end
    hist.empty:SetShown(#rows == 0)
end
function F.ShowHistory()
    if not hist then histBuild() end
    if not hist then return false end
    F.histOffset = 0
    F.PaintHistory()
    hist:Show()
    return true
end
----------------------------------------------------------------------
-- fix 752 (MadDadVibe): /omq flip mark lists green BoE gear in the bags that is no flip; a left click makes it one,
-- its vendor price is what it cost. Then the rules of bought flips: 3x sell cap (at least 99s), 48 h, history, stats.
-- A flip is kept per item, so a click marks every piece of that item in the bags (one record per piece).
----------------------------------------------------------------------
function F.Unmarked()
    local C = C_Container
    local out, byId = {}, {}
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return out end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local last = (OMQ.LastBag and OMQ.LastBag()) or 4
    for bag = 0, last do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local it = C.GetContainerItemInfo(bag, slot)
            local id = it and it.itemID
            if id and not isSecret(id) and not isSecret(it.quality) and not F.Owns(id) and not F.Gone(id) then
                local classID, equipLoc
                if instant then
                    local ok, _, _, _, el, _, cid = pcall(instant, id)
                    if ok then classID, equipLoc = cid, el end
                end
                if F.LootGreen(it, classID, equipLoc, false) then
                    local e = byId[id]
                    if e then e.n = e.n + 1
                    else
                        local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                        local name, lvl
                        if f then
                            local ok, n, _, _, _, l = pcall(f, it.hyperlink or id)
                            if ok then name, lvl = n, l end
                        end
                        e = { id = id, bag = bag, slot = slot, link = it.hyperlink, icon = it.iconFileID, n = 1,
                              name = name or it.itemName or ("item " .. id), level = lvl, vendor = vendorOf(id) or 0 }
                        byId[id] = e
                        out[#out + 1] = e
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end
function F.Mark(e)
    if not (e and type(e.id) == "number") or F.Owns(e.id) then return 0 end
    local o = db().owned
    if o[e.id] and F.Gone(e.id) then o[e.id] = nil end      -- a done flip of before starts again
    for _ = 1, e.n or 1 do
        F.lastName = e.name
        F.Remember(e.id, e.vendor or 0, nil, F.LinkSuffix(e.link))
        F.lastName = nil
    end
    if o[e.id] then o[e.id].manual = true end
    return e.n or 1
end

local mark
F.MARK_ROWS = 14
F.markOffset = 0
local function markBuild()
    local ok, f = pcall(CreateFrame, "Frame", "OneMoreQuestFlipMark", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then return end
    mark = f
    f:SetSize(380, 70 + F.MARK_ROWS * 20)
    f:SetPoint("CENTER", 60, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText("One More Quest - mark as flip")
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", 12, -30)
    box:SetSize(356, F.MARK_ROWS * 20)
    f.box = box
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, d)
        F.markOffset = math.max(0, F.markOffset - d)
        F.PaintMark()
    end)
    f.rows = {}
    for i = 1, F.MARK_ROWS do
        local r = CreateFrame("Button", nil, box)
        r:SetSize(356, 20)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
        r:RegisterForClicks("LeftButtonUp")
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 1, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 24, 0)
        r.name:SetWidth(230)
        r.name:SetJustifyH("LEFT")
        r.res = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.res:SetPoint("RIGHT", -2, 0)
        r.res:SetJustifyH("RIGHT")
        r:SetScript("OnClick", function(self)
            local d = self.data
            if not d then return end
            local n = F.Mark(d)
            if n > 0 then OMQ:Print(string.format("%s%s is a flip now (cost %s each).", d.link or d.name, n > 1 and (" x" .. n) or "", money(d.vendor or 0))) end
            if GameTooltip then GameTooltip:Hide() end
            F.PaintMark()
        end)
        r:SetScript("OnEnter", function(self)
            local d = self.data
            if not (d and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local shown = false
            if GameTooltip.SetBagItem then shown = pcall(GameTooltip.SetBagItem, GameTooltip, d.bag, d.slot) end
            if not shown and d.link and GameTooltip.SetHyperlink then pcall(GameTooltip.SetHyperlink, GameTooltip, d.link) end
            GameTooltip:AddLine("Left click: mark as flip (cost = vendor price)", 0.3, 1, 0.3)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = r
    end
    f.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 2, -2)
    f.empty:SetText("no green BoE gear in the bags that is not a flip")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 12)
    hint:SetText("Left click: mark as flip   Mouse wheel: scroll")
    f:SetScript("OnEvent", function() if f:IsShown() then F.PaintMark() end end)
    pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
    if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestFlipMark") end
end
function F.PaintMark()
    if not mark then return end
    local rows = F.Unmarked()
    F.markOffset = math.max(0, math.min(F.markOffset, math.max(0, #rows - F.MARK_ROWS)))
    for i, r in ipairs(mark.rows) do
        local d = rows[i + F.markOffset]
        r.data = d
        if d then
            r.icon:SetTexture(d.icon)
            r.name:SetText("|cff1eff00" .. tostring(d.name) .. "|r" .. ((d.n or 1) > 1 and (" x" .. d.n) or "") .. (d.level and ("  |cffaaaaaalvl " .. d.level .. "|r") or ""))
            r.res:SetText(money(d.vendor or 0))
            r:Show()
        else r:Hide() end
    end
    mark.empty:SetShown(#rows == 0)
    return rows
end
function F.ShowMark()
    if not mark then markBuild() end
    if not mark then return false end
    F.markOffset = 0
    F.PaintMark()
    mark:Show()
    return true
end
OMQ:RegisterCommand("flip", function(arg)
    if arg == "mark" then                                  -- fix 752
        if not F.ShowMark() then
            for _, e in ipairs(F.Unmarked()) do OMQ:Print("  " .. tostring(e.name) .. " (" .. money(e.vendor or 0) .. ")") end
        end
        return
    end
    if arg == "chat" or not F.ShowHistory() then
        for _, l in ipairs(F.History()) do OMQ:Print(l) end
    end
end, "item flips: window with what was bought, sold, came back, deposits, gold spent and earned (chat = as text, mark = green bag items to mark as flip)")

-- decision 726 (MadDadVibe): a flip is posted for 2 hours (short) by day, for 8 hours from 23:59 German time until
-- 8:00 the next morning. German time = UTC+1, UTC+2 from the last Sunday of March to the last Sunday of October (1:00 UTC).
local function lastSunday(y, m)
    local last = (m == 3) and 31 or 31                     -- March and October both have 31 days
    local t = time({ year = y, month = m, day = last, hour = 12 })
    local wd = tonumber(date("!%w", t)) or 0               -- 0 = Sunday
    return last - wd
end
function F.BerlinClock(utc)
    if not (date and time) then return 12, 0 end            -- no clock: daytime
    utc = utc or time() or 0
    local u = date("!*t", utc)
    local summer = false
    if u.month > 3 and u.month < 10 then summer = true
    elseif u.month == 3 then summer = u.day > lastSunday(u.year, 3) or (u.day == lastSunday(u.year, 3) and u.hour >= 1)
    elseif u.month == 10 then summer = u.day < lastSunday(u.year, 10) or (u.day == lastSunday(u.year, 10) and u.hour < 1) end
    local b = date("!*t", utc + (summer and 7200 or 3600))
    return b.hour, b.min
end
function F.PostHours(utc)
    local h, m = F.BerlinClock(utc)
    if (h == 23 and m >= 59) or h < 8 then return 8 end
    return 2
end
-- the game's duration index for so many hours: read from its own names ("2 Hours", "8 Stunden"), else 1 = short, 2 = medium
function F.DurationIndex(hours)
    for i, s in ipairs({ AUCTION_DURATION_ONE or false, AUCTION_DURATION_TWO or false, AUCTION_DURATION_THREE or false }) do
        if type(s) == "string" and tonumber(s:match("(%d+)")) == hours then return i end
    end
    return hours == 8 and 2 or 1
end
function F.PostDuration(utc) return F.DurationIndex(F.PostHours(utc)) end

-- the random suffix number in an item link ("item:id:enchant:gem1:gem2:gem3:gem4:suffix:..."), nil without one
function F.LinkSuffix(link)
    if type(link) ~= "string" or isSecret(link) then return nil end
    local body = link:match("item:([%-%d:]+)")
    if not body then return nil end
    local i = 0
    for f in (body .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if i == 7 then local n = tonumber(f); return (n and n ~= 0) and n or nil end
    end
    return nil
end
-- what I paid for a bought flip with this suffix (the highest of that item when the suffix is unknown)
function F.Paid(id, sfx)
    if not F.Owns(id) then return nil end
    local x = OMQDB.flip.owned[id]
    return (sfx and x.sfx and x.sfx[sfx]) or x.paid
end
-- decision 725 (MadDadVibe): a bought flip is posted at F.SELL_FACTOR times what it cost (3, fix 730; was 2), but at most at the next auction of
-- exactly its suffix (minus 1 copper; the game's sell search also shows the other suffixes of the item, they do not
-- count, neither do my own). offers: the other auctions of the item { unit, link }. The floor (F.Floor) comes after.
-- fix 734 (MadDadVibe): rings and amulets may be posted up to 1 gold over 3 times their price
F.JEWEL_BONUS = 10000
F.JEWEL_SLOTS = { INVTYPE_FINGER = true, INVTYPE_NECK = true }
function F.JewelBonus(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not (f and id) then return 0 end
    local ok, _, _, _, slot = pcall(f, id)
    if ok and F.JEWEL_SLOTS[slot] then return F.JEWEL_BONUS end
    return 0
end
function F.SellPrice(e, offers)
    local sfx = F.LinkSuffix(e.link)
    local paid = F.Paid(e.itemID, sfx)
    local name = e.name
    local nextP
    for _, o in ipairs(offers or {}) do
        local same
        local os = F.LinkSuffix(o.link)
        if sfx or os then same = os == sfx
        else
            local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local ok, n = pcall(f, o.link or "")
            same = not ok or n == nil or n == name
        end
        if same and o.unit and (not nextP or o.unit < nextP) then nextP = o.unit end
    end
    local price
    if F.IsLoot(e.itemID) then                             -- decision 735: looted greens at the market price
        if not nextP then return nil end                   -- nothing of its suffix on sale: the helper's normal price
        price = nextP - 1
    elseif paid and paid > 0 then
        price = paid * F.SELL_FACTOR + F.JewelBonus(e.itemID)   -- fix 734: rings and amulets 1 gold more
        if F.SELL_MIN_CAP and price < F.SELL_MIN_CAP then price = F.SELL_MIN_CAP end   -- fix 751: cap never under 99s
        if nextP and nextP - 1 < price then price = nextP - 1 end
    else
        price = nextP or false
    end
    if price and price < 1 then price = 1 end
    return price
end
-- fix 750 (MadDadVibe): at most F.MAX_HELD pieces of one item with its suffix, in the bags or on the auction house;
-- one more only after one is sold (or gone to the vendor / the enchanter)
F.MAX_HELD = 2
function F.Held(id, name)
    local x = OMQDB and OMQDB.flip and OMQDB.flip.owned and OMQDB.flip.owned[id]
    if not (x and x.held and type(name) == "string") then return 0 end
    return x.held[name] or 0
end
function F.Release(id, name)                               -- one piece less: by its name, else any of the item
    local x = OMQDB and OMQDB.flip and OMQDB.flip.owned and OMQDB.flip.owned[id]
    if not (x and x.held) then return end
    local k = (type(name) == "string" and (x.held[name] or 0) > 0) and name or nil
    if not k then for n, c in pairs(x.held) do if c > 0 then k = n; break end end end
    if k then x.held[k] = x.held[k] - 1; if x.held[k] <= 0 then x.held[k] = nil end end
end
function F.Owns(id)
    if type(id) ~= "number" or isSecret(id) or not OMQDB or not OMQDB.flip or not OMQDB.flip.owned then return false end
    local x = OMQDB.flip.owned[id]
    if not x then return false end
    if stamp() - (x.t or 0) > F.KEEP_DAYS * 86400 then OMQDB.flip.owned[id] = nil; return false end
    if x.released then return false end                     -- came back unsold REPOSTS times: to the vendor (728)
    if F.Expired(x) then return false end                   -- decision 745: not posted for 48 hours
    return true
end
----------------------------------------------------------------------
-- decision 745 (MadDadVibe): a flip not posted for 48 hours (real time, from the purchase or the last post) is done,
-- like one that came back unsold 5 times: it goes to the vendor or is disenchanted, whichever is worth more.
-- Disenchanting only with an enchanter of mine on the realm (the disenchant category, UI/DisenchantSell.lua).
----------------------------------------------------------------------
F.EXPIRE_HOURS = 48
function F.Expired(x)
    return x and not x.released and (stamp() - (x.t or 0)) > F.EXPIRE_HOURS * 3600 or false
end
function F.Left(id)                                         -- seconds until it expires, nil when it is no flip of mine
    local x = OMQDB and OMQDB.flip and OMQDB.flip.owned and OMQDB.flip.owned[id]
    if not x or x.released then return nil end
    return math.max(0, F.EXPIRE_HOURS * 3600 - (stamp() - (x.t or 0)))
end
-- a flip that is done: still in the records, no protection any more
function F.Gone(id)
    if type(id) ~= "number" or isSecret(id) then return false end
    local x = OMQDB and OMQDB.flip and OMQDB.flip.owned and OMQDB.flip.owned[id]
    if not x then return false end
    if stamp() - (x.t or 0) > F.KEEP_DAYS * 86400 then return false end
    return (x.released or F.Expired(x)) and true or false
end
-- "vendor" or "disenchant": what brings more, and disenchanting only when the disenchant category is on
function F.ExitWay(id)
    local vendor = vendorOf(id) or 0
    local D, DS = OMQ.Disenchant, OMQ.DESell
    local way = "vendor"
    if D and D.Value and DS and DS.Mode and DS.Mode() then
        local ok, v, _, _, priced = pcall(D.Value, id)
        if ok and type(v) == "number" and priced and priced > 0 and v > vendor then way = "disenchant" end
    end
    local x = OMQDB and OMQDB.flip and OMQDB.flip.owned and OMQDB.flip.owned[id]
    if x then x.exit = way end
    return way
end
-- a done flip that left the bags another way than the vendor (disenchanted, or mailed to the enchanter): counted once
function F.CheckGone()
    local d = OMQDB and OMQDB.flip
    local count = C_Item and C_Item.GetItemCount
    if not (d and d.owned and count) then return end
    for id, x in pairs(d.owned) do
        if x.exit == "disenchant" and F.Gone(id) then
            local ok, n = pcall(count, id)
            n = ok and tonumber(n) or nil
            if n and n < (x.n or 1) then
                local D = OMQ.Disenchant
                local okV, v = pcall(function() return D and D.Value and D.Value(id) end)
                v = okV and tonumber(v) or 0
                for _ = 1, (x.n or 1) - n do F.Disenchanted(id, v) end
            end
        end
    end
end
function F.Disenchanted(id, value)
    local x = db().owned[id]
    if not x then return end
    local paid = F.PaidAny(id) or 0
    F.Note(id, "d", value)
    F.Stat(id, "d", value, nil, paid)
    F.Release(id)                                          -- fix 750
    local it = items()[id]
    it.cost = (it.cost or 0) + paid
    x.n = (x.n or 1) - 1
    if x.n <= 0 then db().owned[id] = nil end
end
-- the lowest price a bought flip is posted at: what it cost plus the house's cut
function F.Floor(id)
    if not F.Owns(id) then return nil end
    local x = OMQDB.flip.owned[id]
    if not x.paid or x.paid <= 0 then return nil end
    return math.ceil(x.paid / (1 - F.CUT)) + 1
end

-- fix 724: Shift + left click opens exactly this item (with its suffix) in the game's own window, its Buy page
function F.ShowInGame(r)
    local f = _G.AuctionHouseFrame
    if type(r) ~= "table" or not (f and f.SelectBrowseResult) then return false end
    local ok, err = pcall(f.SelectBrowseResult, f, { itemKey = r.itemKey, minPrice = r.price })
    if not ok then OMQ:Print("item flips: the auction house window could not show it (" .. tostring(err) .. ")") end
    return ok
end

function F.Discard(r)
    if type(r) ~= "table" or not r.ks then return end
    local k = r.itemKey
    db().black[r.ks] = { id = r.itemID, name = r.name, icon = r.icon, link = r.link, t = stamp(),
                         key = type(k) == "table" and { itemID = k.itemID, itemLevel = k.itemLevel, itemSuffix = k.itemSuffix } or nil }
    r.hold = nil
    F.Build()
    F.RepaintBlack()
end
function F.Unblock(ks)
    if not (ks and db().black[ks]) then return false end
    db().black[ks] = nil
    F.Build()
    F.RepaintBlack()
    return true
end
function F.ResetSkip()                                     -- /omq ah flip reset: the whole blacklist (not the temp lines)
    local n = 0
    for k in pairs(db().black) do db().black[k] = nil; n = n + 1 end
    F.Build()
    F.RepaintBlack()
    return n
end
-- the blacklist: the temp lines first (2 of them held, fix 750; they go by themselves once one is sold), then the
-- dismissed ones, the newest first
function F.BlackRows()
    local out = {}
    local d = db()
    if F.MAX_HELD then
        for id, x in pairs(d.owned) do
            if x.held and F.Owns(id) then
                for name, c in pairs(x.held) do
                    if c >= F.MAX_HELD then
                        local key = x.keys and x.keys[name]
                        out[#out + 1] = { temp = true, id = id, name = name, n = c, ks = "temp:" .. id .. ":" .. name,
                                          itemKey = key or { itemID = id, itemLevel = 0, itemSuffix = 0 } }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    local perm = {}
    for ks, b in pairs(d.black) do
        perm[#perm + 1] = { id = b.id, name = b.name, icon = b.icon, link = b.link, t = b.t or 0, ks = ks,
                            itemKey = b.key or { itemID = b.id, itemLevel = 0, itemSuffix = 0 } }
    end
    table.sort(perm, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.ks < b.ks end)
    for _, r in ipairs(perm) do out[#out + 1] = r end
    return out
end

----------------------------------------------------------------------
-- The Flip Helper (fix 753, MadDadVibe): the auction helper turns into it with the Flip button. Its tabs are
-- Sell | Buy | Blacklist; Buy (this part) holds the search profile, the Search button, the found flips and Buy next,
-- drawn like the auction helper's own tabs. Switched on per character in the options (Interface).
----------------------------------------------------------------------
F.offset = 0
local rowFrames = {}
F._rowFrames = function() return rowFrames end
local GOLD = { 0.89, 0.71, 0.29 }

-- per character: on/off, the helper the auction house opens with, the last search profile
local function charKey() return (UnitGUID and UnitGUID("player")) or "?" end
function F.Char()
    local d = db()
    d.chars = d.chars or {}
    local k = charKey()
    d.chars[k] = d.chars[k] or {}
    return d.chars[k]
end
function F.Enabled() return F.Char().on == true end
function F.SetEnabled(v)
    local c = F.Char()
    c.on = v and true or false
    if not v then c.helper = nil end
    local h = H()
    if h and h.FlipChanged then pcall(h.FlipChanged) end
end
function F.SavedHelper() return (F.Enabled() and F.Char().helper == "flip") and "flip" or "ah" end
function F.SaveHelper(which) F.Char().helper = (which == "flip") and "flip" or "ah" end
function F.Pick(key)                                       -- a profile from the box: chosen, not yet searched
    if not F.METHODS[key or ""] then return false end
    if run and not run.checkOnly then F.Cancel() end
    F.method = key
    F.Char().method = key
    status("search profile: " .. F.METHODS[key].label .. " - press Search")
    return true
end

-- the small buttons of our own look (as the auction helper's Reset button)
local function button(parent, w, h, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b.edge:SetColorTexture(0.45, 0.37, 0.18, 1)
    b.bg = b:CreateTexture(nil, "BORDER"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.2, 0.21, 0.25, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.text:SetPoint("CENTER"); b.text:SetText(label)
    b.text:SetTextColor(0.93, 0.93, 0.95)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.08)
    function b:SetText(t) self.text:SetText(t) end
    function b:GetText() return self.text:GetText() end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end
F._button = button

local function rowState(r)
    if run and run.q and run.q.kind == "item" and run.q.check and run.q.e.ks == r.ks then return "searching the auction..." end
    if r.checking and run then for _, x in ipairs(run.checks) do if x.ks == r.ks then return "searching the auction..." end end end
    if r.hold and fresh(r) then return "ready - click to buy" end
    return nil
end

local function makeRow(i)
    local r = B()._makeRow(frame.list, F.ROW_H)            -- the row of the Buy tab (icon, name, two lines right)
    r:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, -(i - 1) * (F.ROW_H + 2))
    r:SetScript("OnClick", function(self, mouse)
        local ok, err = pcall(function()
            if mouse == "RightButton" then F.Discard(self.omq)                   -- fix 753: to the blacklist for good
            elseif IsShiftKeyDown and IsShiftKeyDown() then F.ShowInGame(self.omq)    -- fix 724
            else F.Buy(self.omq) end
            F.Paint()
        end)
        if not ok then OMQ:Error("item flips", err) end
    end)
    r:SetScript("OnEnter", function(self)
        local x = self.omq
        if type(x) ~= "table" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if x.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(x.link)
        elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(x.itemID) end
        if x.kind == "gap" then
            GameTooltip:AddLine(string.format("%d offers; %d under %s, sell at %s", x.n or 0, #(x.offers or {}), money(x.maxBuy or 0), money(x.sell or 0)), 1, 0.82, 0)
        elseif x.kind == "single" then
            GameTooltip:AddLine(string.format("the only offer, at most " .. (F.VENDOR_FACTOR or 1.25) .. "x the vendor price (%s)", money(x.maxBuy or 0)), 1, 0.82, 0)
        else
            GameTooltip:AddLine(string.format("only %d offers, %d of them under 1 gold", x.n or 0, #(x.offers or {})), 1, 0.82, 0)
        end
        GameTooltip:AddLine("Left click: buy the next cheap one (the first click looks for the auctions)", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift + left click: show it in the auction house window", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right click: dismiss for good (to the blacklist)", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    rowFrames[i] = r
    return r
end

local function build(parent)
    local f = CreateFrame("Frame", "OneMoreQuestFlip", parent or UIParent)
    frame = f
    f:SetSize(380, 100 + F.ROWS * (F.ROW_H + 2))
    if parent and parent.box and f.SetFrameLevel then f:SetFrameLevel(parent.box:GetFrameLevel() + 8) end
    -- the search profile box and the Search button, in the row of the auction helper's mode switch
    local pick = button(f, 230, 26, "Choose a search profile", function()
        if frame.drop:IsShown() then frame.drop:Hide() else frame.drop:Show() end
    end)
    pick:SetPoint("TOPLEFT", 22, -6)
    pick.text:ClearAllPoints(); pick.text:SetPoint("LEFT", 10, 0)
    pick.arrow = pick:CreateFontString(nil, "OVERLAY", "GameFontNormal"); pick.arrow:SetPoint("RIGHT", -8, 0); pick.arrow:SetText("v")
    pick.arrow:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.pick = pick
    local drop = CreateFrame("Frame", nil, f)
    drop:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -2)
    drop:SetSize(230, #F.BUTTONS * 24 + 4)
    if drop.SetFrameLevel then drop:SetFrameLevel(f:GetFrameLevel() + 20) end
    drop.bg = drop:CreateTexture(nil, "BACKGROUND"); drop.bg:SetAllPoints(); drop.bg:SetColorTexture(0.05, 0.055, 0.075, 0.98)
    drop:EnableMouse(true)
    drop:Hide()
    f.drop = drop
    f.methods = {}
    for i, key in ipairs(F.BUTTONS) do
        local mb = button(drop, 222, 22, F.METHODS[key].label, function()
            local ok2, err = pcall(function()
                F.Pick(key)
                frame.drop:Hide()
                F.Paint()
            end)
            if not ok2 then OMQ:Error("item flips", err) end
        end)
        mb:SetPoint("TOPLEFT", 4, -2 - (i - 1) * 24)
        mb:SetScript("OnEnter", function(self)                 -- decision 746: the track record of this bracket
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(F.METHODS[key].label)
            local a, b = F.BracketTip(key)
            GameTooltip:AddLine(a, 1, 1, 1)
            GameTooltip:AddLine(b, 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        mb.key = key
        f.methods[i] = mb
    end
    local again = button(f, 100, 26, "Search", function()
        local ok2, err = pcall(function()
            frame.drop:Hide()
            if run and not run.checkOnly then F.Cancel() else
                if run then F.Cancel() end
                local started, why = F.Start()
                if not started then OMQ:Print("item flips: " .. tostring(why)) end
            end
            F.Paint()
        end)
        if not ok2 then OMQ:Error("item flips", err) end
    end)
    again:SetPoint("TOPLEFT", 258, -6)
    f.again = again
    local st = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    st:SetPoint("TOPLEFT", 16, -42)
    st:SetWidth(348)
    st:SetJustifyH("LEFT")
    st:SetTextColor(0.79, 0.8, 0.84)
    f.status = st
    local listFrame = CreateFrame("Frame", nil, f)
    listFrame:SetPoint("TOPLEFT", 16, -72)
    listFrame:SetSize(348, F.ROWS * (F.ROW_H + 2))
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, d)
        F.offset = math.max(0, math.min(math.max(0, #list - F.ROWS), F.offset - d))
        F.Paint()
    end)
    f.list = listFrame
    -- Buy next: the gold button of the auction helper's Buy tab
    local all = CreateFrame("Button", "OneMoreQuestFlipBuyNext", f)
    all:SetSize(348, 44)
    all.bg = all:CreateTexture(nil, "BACKGROUND"); all.bg:SetAllPoints(); all.bg:SetColorTexture(0.165, 0.141, 0.086, 1)
    all.edge = all:CreateTexture(nil, "BORDER"); all.edge:SetPoint("TOPLEFT", -1, 1); all.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    all.edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
    all.bg:SetDrawLayer("BACKGROUND", 1); all.edge:SetDrawLayer("BACKGROUND", 0)
    all.price = all:CreateFontString(nil, "OVERLAY", "GameFontNormal"); all.price:SetPoint("RIGHT", -10, 0); all.price:SetJustifyH("RIGHT")
    all.price:SetTextColor(0.95, 0.82, 0.48)
    all.title = all:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); all.title:SetPoint("LEFT", 10, 0); all.title:SetJustifyH("LEFT")
    all.title:SetTextColor(0.95, 0.82, 0.48)
    all.hl = all:CreateTexture(nil, "HIGHLIGHT"); all.hl:SetAllPoints(); all.hl:SetColorTexture(1, 1, 1, 0.06)
    function all:SetText(t) self.title:SetText(t) end
    function all:GetText() return self.title:GetText() end
    all:SetScript("OnClick", function()
        local ok2, err = pcall(function() F.BuyNext(); F.Paint() end)
        if not ok2 then OMQ:Error("item flips", err) end
    end)
    f.all = all
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetWidth(348)
    hint:SetJustifyH("LEFT")
    hint:SetText("Left click: buy - Shift + left click: show in the auction house - right click: dismiss for good")
    f.hint = hint
    f:SetScript("OnHide", function() if run then F.Cancel() end; if frame.drop then frame.drop:Hide() end end)
end

function F.Paint()
    if not frame or not frame:IsShown() then return 0 end
    local text = F.statusText or ""
    if F.bought.n > 0 then
        text = text .. string.format("\nbought: %d for %s, sells for about %s", F.bought.n, money(F.bought.spent), money(F.bought.worth))
    end
    frame.status:SetText(text)
    frame.again:SetText((run and not run.checkOnly) and "Cancel" or "Search")
    frame.again.text:SetTextColor(F.method and 0.93 or 0.5, F.method and 0.93 or 0.5, F.method and 0.95 or 0.5)
    frame.pick:SetText(F.method and F.METHODS[F.method] and F.METHODS[F.method].label or "Choose a search profile")
    for _, mb in ipairs(frame.methods) do
        local on = mb.key == F.method
        if on then mb.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1) else mb.bg:SetColorTexture(0.2, 0.21, 0.25, 1) end
        if on then mb.text:SetTextColor(0.07, 0.07, 0.08) else mb.text:SetTextColor(0.93, 0.93, 0.95) end
    end
    local nx = list[1]
    if not nx then frame.all:SetText("Buy next: nothing to buy"); frame.all.price:SetText("")
    else
        local st = rowState(nx)
        frame.all:SetText("Buy next" .. (st == "ready - click to buy" and "" or (st and " (searching)" or "")))
        frame.all.price:SetText(money(nx.offers[1].buyout))
    end
    if frame.all.SetEnabled then frame.all:SetEnabled(nx ~= nil) end
    F.offset = math.max(0, math.min(F.offset, math.max(0, #list - F.ROWS)))
    local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[2]
    for i = 1, F.ROWS do
        local r = rowFrames[i] or makeRow(i)
        local x = list[F.offset + i]
        r.omq = x
        if x then
            r.name:SetText(x.name or ("item " .. x.itemID))
            if qc then r.name:SetTextColor(qc.r, qc.g, qc.b) else r.name:SetTextColor(0.12, 1, 0) end
            local st = rowState(x)
            if x.kind == "gap" then
                r.sub:SetText(st or string.format("%d cheap, sell at %s", #x.offers, money(x.sell or 0)))
                r.bottom:SetText("+" .. money(x.profit or 0))
            elseif x.kind == "single" then
                r.sub:SetText(st or "the only offer")
                r.bottom:SetText("<= " .. (F.VENDOR_FACTOR or 1.25) .. "x vendor")
            else
                r.sub:SetText(st or string.format("only %d on offer", x.n or 0))
                r.bottom:SetText("under 1g")
            end
            r.top:SetText(money(x.cost or 0))
            r.icon:SetTexture(x.icon)
            if st == "ready - click to buy" then r.bg:SetColorTexture(0.1, 0.3, 0.12, 1) else r.bg:SetColorTexture(0.11, 0.122, 0.153, 1) end
            r:Show()
        else
            r:Hide()
        end
    end
    -- the list (always F.ROWS rows high: the panel keeps its size), Buy next and the hint below it
    local rowsH = F.ROWS * (F.ROW_H + 2)
    frame.list:SetHeight(rowsH)
    local y = 72 + rowsH + 6
    frame.all:ClearAllPoints(); frame.all:SetPoint("TOPLEFT", 16, -y)
    frame.hint:ClearAllPoints(); frame.hint:SetPoint("TOPLEFT", 16, -(y + 50))
    return y + 66
end

-- the Buy tab of the flip helper inside the auction helper: drawn below the tabs, returns the height it needs
-- (counted from `top`, the frame starts 38 higher in the row of the mode switch)
function F.Render(panel, top)
    if not frame then build(panel) end
    if frame.GetParent and frame:GetParent() ~= panel and frame.SetParent then frame:SetParent(panel) end
    if not F.method and F.METHODS[F.Char().method or ""] then F.method = F.Char().method end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(top - 38))
    frame:SetPoint("RIGHT", panel, "RIGHT")
    if not frame:IsShown() then
        frame:Show()
        if not run and not F.method then status("choose a search profile above, then press Search") end
    end
    local h = F.Paint()
    frame:SetHeight(h)
    return h - 38
end
function F.Hide() if frame and frame:IsShown() then frame:Hide() end end
function F.Show()                                          -- without the auction helper's panel (it is off): on its own
    local h = H()
    local p = _G.OneMoreQuestAuctionHelper
    if h and h.SetView and p and p:IsShown() then h.SetView("fbuy"); return frame ~= nil end
    if not frame then build(UIParent) end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    frame:Show()
    if not run and not F.method then status("choose a search profile above, then press Search") end
    F.Paint()
    return true
end
function F.Frame() return frame end
function F.Open()
    local h = H()
    if not F.Enabled() then OMQ:Print("item flips: switch the flip helper on first (options, Interface: Flip helper)"); return false end
    if not (h and h.open) then OMQ:Print("item flips: open the auction house first (with the auction helper on)"); return false end
    if not F.method and F.METHODS[F.Char().method or ""] then F.method = F.Char().method end
    F.Show()
    if not run and not F.method then status("choose a search profile above, then press Search") end   -- fix 724
    return true
end

----------------------------------------------------------------------
-- The Blacklist tab (fix 753): dismissed items for good (right click: off the list again), and the "temp" lines of
-- items held twice, which go by themselves once one is sold. Shift + left click searches it in the game's window.
----------------------------------------------------------------------
F.BLACK_ROWS = 10
F.blackOffset = 0
local black
local blackRows = {}
F._blackRows = function() return blackRows end
local function blackBuild(panel)
    black = CreateFrame("Frame", "OneMoreQuestFlipBlack", panel or UIParent)
    if panel and panel.box and black.SetFrameLevel then black:SetFrameLevel(panel.box:GetFrameLevel() + 2) end
    black.head = black:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    black.head:SetPoint("TOPLEFT", 16, -4); black.head:SetWidth(348); black.head:SetJustifyH("LEFT")
    black.head:SetTextColor(0.79, 0.8, 0.84)
    black:EnableMouseWheel(true)
    black:SetScript("OnMouseWheel", function(_, d)
        local n = #F.BlackRows()
        F.blackOffset = math.max(0, math.min(math.max(0, n - F.BLACK_ROWS), F.blackOffset - d))
        F.RepaintBlack()
    end)
    for i = 1, F.BLACK_ROWS do
        local r = B()._makeRow(black, F.ROW_H)
        r:SetPoint("TOPLEFT", 16, -26 - (i - 1) * (F.ROW_H + 2))
        r:SetScript("OnClick", function(self, mouse)
            local ok, err = pcall(function()
                local x = self.omq
                if not x then return end
                if mouse == "RightButton" then
                    if x.temp then OMQ:Print("item flips: " .. tostring(x.name) .. " comes back by itself once one of the two is sold")
                    else F.Unblock(x.ks) end
                elseif IsShiftKeyDown and IsShiftKeyDown() then F.ShowInGame(x) end
            end)
            if not ok then OMQ:Error("item flips", err) end
        end)
        r:SetScript("OnEnter", function(self)
            local x = self.omq
            if not (x and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if x.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(x.link)
            elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(x.id) end
            if x.temp then
                GameTooltip:AddLine("temp: you hold " .. (x.n or 2) .. " - back once one is sold", 1, 0.6, 0.2)
            else
                GameTooltip:AddLine("Right click: off the blacklist", 0.6, 0.6, 0.6)
            end
            GameTooltip:AddLine("Shift + left click: search it in the auction house window", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        blackRows[i] = r
    end
    black.more = black:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    black.hint = black:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    black.hint:SetWidth(348); black.hint:SetJustifyH("LEFT")
    black.hint:SetText("Right click: off the blacklist (not temp) - Shift + left click: search in the auction house")
end
function F.PaintBlack()
    if not (black and black:IsShown()) then return 0 end
    local all = F.BlackRows()
    local temp = 0
    for _, x in ipairs(all) do if x.temp then temp = temp + 1 end end
    black.head:SetText(#all == 0 and "Nothing on the blacklist - right click in Buy dismisses an item for good"
        or string.format("%d dismissed for good, %d temp (%d held)", #all - temp, temp, F.MAX_HELD or 2))
    F.blackOffset = math.max(0, math.min(F.blackOffset, math.max(0, #all - F.BLACK_ROWS)))
    local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[2]
    local y = 26
    for i, r in ipairs(blackRows) do
        local x = all[F.blackOffset + i]
        r.omq = x
        if x then
            local icon = x.icon
            if not icon then
                local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
                if inst then local ok, _, _, _, _, ic = pcall(inst, x.id); if ok then icon = ic end end
            end
            r.icon:SetTexture(icon)
            r.name:SetText(x.name or ("item " .. tostring(x.id)))
            if qc then r.name:SetTextColor(qc.r, qc.g, qc.b) else r.name:SetTextColor(0.12, 1, 0) end
            if x.temp then
                r.top:SetText("|cffff9933temp|r")
                r.sub:SetText("you hold " .. (x.n or 2) .. " - back once one is sold")
                r.bottom:SetText("")
            else
                r.top:SetText("")
                r.sub:SetText(x.t and x.t > 0 and date and ("dismissed " .. date("%d.%m. %H:%M", x.t)) or "dismissed")
                r.bottom:SetText("right click: remove")
            end
            r.bg:SetColorTexture(0.11, 0.122, 0.153, 1)
            r:Show()
            y = y + F.ROW_H + 2
        else r:Hide() end
    end
    if #all > F.BLACK_ROWS then
        black.more:ClearAllPoints(); black.more:SetPoint("TOPLEFT", 16, -y)
        black.more:SetText(string.format("Mouse wheel: %d more", #all - F.BLACK_ROWS)); black.more:Show()
        y = y + 16
    else black.more:Hide() end
    black.hint:ClearAllPoints(); black.hint:SetPoint("TOPLEFT", 16, -(y + 4))
    return y + 24
end
function F.RenderBlack(panel, top)
    if not black then blackBuild(panel) end
    black:ClearAllPoints(); black:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -top); black:SetPoint("RIGHT", panel, "RIGHT")
    black:Show()
    local h = F.PaintBlack()
    black:SetHeight(h)
    return h
end
function F.HideBlack() if black then black:Hide() end end
function F.RepaintBlack()                                  -- a line more or less: the panel takes the new height
    if not (black and black:IsShown()) then return end
    local h = H()
    if h and h.Refresh then h.Refresh() else F.PaintBlack() end
end
F._Black = function() return black end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
                     "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
                     "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
                     "ITEM_SEARCH_RESULTS_UPDATED", "GET_ITEM_INFO_RECEIVED", "ITEM_KEY_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local considerAt = nil
ev:SetScript("OnEvent", function(_, event, a1)
    local ok, err = pcall(function()
        if event == "BAG_UPDATE_DELAYED" then F.CheckGone(); return   -- decision 745
        elseif event == "AUCTION_HOUSE_CLOSED" then
            if run then F.Finish("the auction house closed") end
            if frame then frame:Hide() end
            for k in pairs(lines) do lines[k] = nil end
            for k in pairs(rows) do rows[k] = nil end
            for i = #list, 1, -1 do list[i] = nil end
            F.bought = { n = 0, spent = 0, worth = 0 }
        elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
            if run and (run.waiting or 0) > 0 and not considerAt then considerAt = now() + F.REBUILD_GAP end
        elseif not run then return
        elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then F.OnBrowse()
        elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then F.OnItem(a1)
        elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
            if run.q and run.state == "waiting" then run.q.dropped = true end
        elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED" then
            if run.q and run.state == "waiting" then run.q.resp = true end
        elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then F.Step() end
    end)
    if not ok then OMQ:Error("item flips", err); run = nil end
end)
-- a slow tick: the pace of the searches, the items that finished loading
local acc = 0
ev:SetScript("OnUpdate", function(_, el)
    acc = acc + (el or 0)
    if acc < 0.25 then return end
    acc = 0
    if considerAt and now() >= considerAt then
        considerAt = nil
        pcall(consider)
    end
    if run then
        local ok, err = pcall(F.Step)
        if not ok then OMQ:Error("item flips", err); run = nil end
    end
    if frame and frame:IsShown() then pcall(F.Paint) end   -- "ready" runs out after a few seconds
end)
