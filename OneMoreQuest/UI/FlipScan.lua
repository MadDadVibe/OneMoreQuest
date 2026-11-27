-- One More Quest - item flips in the auction house (decision 721, replaces the disenchant bargains of decision 710)
-- /omq ah flip opens a window next to the auction helper and looks for green weapons and armor of required level 30
-- to 50 with one of the suffixes of the Sorcerer, Bandit, Knight, Beast, Elder, Channeler or Hierophant (English and
-- German names, F.SUFFIXES; weapons only with the caster ones, F.CASTER, fix 723). Every item with its suffix counts on its own. A flip: at least 6 offers and the 6th
-- cheapest at least 1.5 times the cheapest - the cheap ones are bought and sold again at the 6th price minus 1 copper;
-- every offer under 2/3 of that price is bought (never one over 1 gold, fix 724; a second method "gap3": 3rd >= 2x 1st). Fewer than 6 offers: every offer under 1 gold is listed too
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

F.CLASSES = { 2, 4 }      -- weapons, armor
F.MIN_LEVEL, F.MAX_LEVEL = 30, 50
F.NTH = 6                 -- the offer the cheapest is compared with
F.RATIO = 1.5             -- the 6th cheapest at least this much times the cheapest
F.CHEAP = 10000           -- fewer than NTH offers: every offer under 1 gold
F.MAX_BUY = 10000         -- fix 724 (MadDadVibe): no offer over 1 gold is ever bought or shown
-- fix 724: two methods, chosen with the two buttons on top; the search starts only after the choice
--   "flip": the 6th cheapest >= 1.5x the cheapest (decision 721), fewer than 6 offers: every one under 1 gold
--   "gap3": the 3rd cheapest >= 2x the cheapest - easy buyouts, sold again at the 3rd price minus 1 copper
F.METHODS = {
    flip = { nth = 6, ratio = 1.5, few = true, label = "6th 1.5x, lvl 30-50" },
    gap3 = { nth = 3, ratio = 2, few = false, label = "3rd 2x, lvl 30-50" },
    -- decision 727: the same for the levels 10-29
    gap3low = { nth = 3, ratio = 2, few = false, label = "3rd 2x, lvl 10-29", minLevel = 10, maxLevel = 29 },
}
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
    d.skip = d.skip or {}
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
    if (e.price or 0) > F.MAX_BUY or not ((e.qty or 0) >= m.nth or (m.few and (e.price or 0) < F.CHEAP)) then e.match = false; return false end
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
    e.suffix = F.SuffixOf(name)
    local c, sc = classOf(e.id)
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
function F.Judge(offers, method)
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
    else
        return nil
    end
    maxBuy = math.min(maxBuy, F.MAX_BUY)                   -- fix 724
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

local function skipped(ks, price)
    local s = db().skip[ks]
    if not s then return false end
    if stamp() - (s.t or 0) > F.SKIP_TIME or price < (s.p or 0) then db().skip[ks] = nil; return false end
    return true
end

-- the answer of one item search: the row of the item, judged
function F.Take(e, offers, check)
    local ks = e.ks
    local r = rows[ks]
    if not r then
        r = { ks = ks, itemKey = e.key, itemID = e.id, commodity = false, onDone = F.OnDone }
        rows[ks] = r
    end
    r.name, r.icon = e.name or r.name, e.icon or r.icon
    local j = F.Judge(offers, F.method)
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
    for _, c in ipairs(F.CLASSES) do queue[#queue + 1] = { c = c } end
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
        F.lastName = r.name
        F.Remember(r.itemID, r.paid, r.sell, F.LinkSuffix(r.paidLink))
        F.lastName = nil
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
end

----------------------------------------------------------------------
-- decision 728 (MadDadVibe): the flip history (/omq flip) and the resale rules
-- Per item: bought, sold, came back unsold, vendored, spent and got (OMQDB.flip.items, kept for good); the totals
-- are their sums. A flip is posted up to REPOSTS times; one that came back unsold that often goes to the vendor
-- (no protection any more, the helper's "unsold" rule takes it). One that came back is posted again only while
-- that brings at least REPOST_GAIN over what it cost, after the cut - else it waits in the bags.
----------------------------------------------------------------------
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
    elseif kind == "v" then it.v, it.got = it.v + 1, it.got + c end
    it.t = stamp()
end
-- the result mail of a flip auction (AH.ScanMail via AH.Result); true when the helper's own unsold rule must not count it
function F.Result(id, sold, got, name)
    local x = db().owned[id]
    if not x then return false end
    if sold then
        local paid = F.Paid(id) or 0
        F.Note(id, "s", got, name)
        local it = items()[id]
        it.cost = (it.cost or 0) + paid                    -- what the sold pieces cost
        x.n = (x.n or 1) - 1
        if x.n <= 0 then db().owned[id] = nil end
        return false
    end
    F.Note(id, "u", 0, name)
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
    it = items()[id]
    it.cost = (it.cost or 0) + (F.PaidAny(id) or 0)
    x.n = (x.n or 1) - 1
    if x.n <= 0 then db().owned[id] = nil end
end
function F.Posted(id)
    local x = db().owned[id]
    if x then x.posts, x.t = (x.posts or 0) + 1, stamp() end
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
function F.Totals()
    local t = { b = 0, s = 0, u = 0, v = 0, spent = 0, got = 0, cost = 0 }
    for _, it in pairs(items()) do
        for k in pairs(t) do t[k] = t[k] + (it[k] or 0) end
    end
    t.profit = t.got - t.cost                             -- what the sold and vendored pieces brought over their price
    t.open = t.spent - t.cost                             -- still in the bags or on the auction house
    return t
end
local function signed(c)
    if c < 0 then return "-" .. money(-c) end
    return "+" .. money(c)
end
function F.History()
    local out = {}
    local t = F.Totals()
    out[#out + 1] = string.format("item flips: bought %d for %s, sold %d (%s), %d came back unsold, %d to the vendor",
        t.b, money(t.spent), t.s, money(t.got), t.u, t.v)
    out[#out + 1] = string.format("  earned with flips: %s on %s of sold pieces; still out (bags / auction house): %s",
        signed(t.profit), money(t.cost), money(t.open))
    local list_ = {}
    for id, it in pairs(items()) do list_[#list_ + 1] = { id = id, it = it } end
    table.sort(list_, function(a, b) return (a.it.t or 0) > (b.it.t or 0) end)
    for i = 1, math.min(15, #list_) do
        local it = list_[i].it
        out[#out + 1] = string.format("  %s: bought %d, sold %d, unsold %d%s, %s", it.name or ("item " .. list_[i].id), it.b, it.s, it.u,
            it.v > 0 and (", vendor " .. it.v) or "", (it.s + it.v) > 0 and signed((it.got or 0) - (it.cost or 0)) or ("spent " .. money(it.spent)))
    end
    if #list_ > 15 then out[#out + 1] = string.format("  ... and %d more items", #list_ - 15) end
    if #list_ == 0 then out[#out + 1] = "  nothing bought with item flips yet" end
    return out
end
OMQ:RegisterCommand("flip", function(arg)
    for _, l in ipairs(F.History()) do OMQ:Print(l) end
end, "item flips: what was bought, sold, came back, gold spent and earned")

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
-- decision 725 (MadDadVibe): a bought flip is posted at twice what it cost, but at most at the next auction of
-- exactly its suffix (minus 1 copper; the game's sell search also shows the other suffixes of the item, they do not
-- count, neither do my own). offers: the other auctions of the item { unit, link }. The floor (F.Floor) comes after.
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
    if paid and paid > 0 then
        price = paid * 2
        if nextP and nextP - 1 < price then price = nextP - 1 end
    else
        price = nextP or false
    end
    if price and price < 1 then price = 1 end
    return price
end
function F.Owns(id)
    if type(id) ~= "number" or isSecret(id) or not OMQDB or not OMQDB.flip or not OMQDB.flip.owned then return false end
    local x = OMQDB.flip.owned[id]
    if not x then return false end
    if stamp() - (x.t or 0) > F.KEEP_DAYS * 86400 then OMQDB.flip.owned[id] = nil; return false end
    if x.released then return false end                     -- came back unsold REPOSTS times: to the vendor (728)
    return true
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
    if type(r) ~= "table" then return end
    db().skip[r.ks] = { p = r.offers and r.offers[1] and r.offers[1].unit or r.price, t = stamp() }
    r.hold = nil
    F.Build()
end
function F.ResetSkip()
    local n = 0
    for k in pairs(db().skip) do db().skip[k] = nil; n = n + 1 end
    F.Build()
    return n
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
F.offset = 0
local rowFrames = {}
F._rowFrames = function() return rowFrames end

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
            if mouse == "RightButton" then F.Discard(self.omq)
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
        else
            GameTooltip:AddLine(string.format("only %d offers, %d of them under 1 gold", x.n or 0, #(x.offers or {})), 1, 0.82, 0)
        end
        GameTooltip:AddLine("Left click: buy the next cheap one (the first click looks for the auctions)", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift + left click: show it in the auction house window", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right click: discard (back when it is offered cheaper)", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    rowFrames[i] = r
    return r
end

local function build()
    local ok, f = pcall(CreateFrame, "Frame", "OneMoreQuestFlip", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then return end
    frame = f
    f:SetSize(380, 156 + F.ROWS * (F.ROW_H + 2))
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText("One More Quest - item flips")
    local st = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    st:SetPoint("TOPLEFT", 14, -32)
    st:SetWidth(352)
    st:SetJustifyH("LEFT")
    f.status = st
    local again = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    again:SetSize(110, 22)
    again:SetPoint("TOPLEFT", 12, -88)
    -- fix 724: the two methods; a click starts the search with it
    f.methods = {}
    for i, key in ipairs({ "flip", "gap3", "gap3low" }) do
        local mb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        mb:SetSize(116, 22)
        mb:SetPoint("TOPLEFT", 12 + (i - 1) * 120, -60)
        mb:SetText(F.METHODS[key].label)
        mb:SetScript("OnClick", function()
            local ok2, err = pcall(function()
                if run then F.Cancel() end
                local started, why = F.Start(key)
                if not started then OMQ:Print("item flips: " .. tostring(why)) end
                F.Paint()
            end)
            if not ok2 then OMQ:Error("item flips", err) end
        end)
        mb.key = key
        f.methods[i] = mb
    end
    again:SetText("Search again")
    again:SetScript("OnClick", function()
        if run and not run.checkOnly then F.Cancel() else
            if run then F.Cancel() end
            local started, why = F.Start()
            if not started then OMQ:Print("item flips: " .. tostring(why)) end
        end
        F.Paint()
    end)
    f.again = again
    local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    all:SetSize(236, 22)
    all:SetPoint("LEFT", again, "RIGHT", 6, 0)
    all:SetScript("OnClick", function()
        local ok2, err = pcall(function() F.BuyNext(); F.Paint() end)
        if not ok2 then OMQ:Error("item flips", err) end
    end)
    f.all = all
    local listFrame = CreateFrame("Frame", nil, f)
    listFrame:SetPoint("TOPLEFT", 14, -116)
    listFrame:SetSize(348, F.ROWS * (F.ROW_H + 2))
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, d)
        F.offset = math.max(0, math.min(math.max(0, #list - F.ROWS), F.offset - d))
        F.Paint()
    end)
    f.list = listFrame
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 12)
    hint:SetWidth(352)
    hint:SetJustifyH("LEFT")
    hint:SetText("Left click: buy   Right click: discard   Mouse wheel: scroll")
    f.hint = hint
    f:SetScript("OnHide", function() if run then F.Cancel() end end)
    if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestFlip") end
end

local function anchor()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", _G.OneMoreQuestAuctionHelper or UIParent, "TOPRIGHT", 6, 0)   -- right of the auction helper
end

function F.Paint()
    if not frame or not frame:IsShown() then return end
    local text = F.statusText or ""
    if F.bought.n > 0 then
        text = text .. string.format("\nbought: %d for %s, sells for about %s", F.bought.n, money(F.bought.spent), money(F.bought.worth))
    end
    frame.status:SetText(text)
    frame.again:SetText((run and not run.checkOnly) and "Cancel" or "Search again")
    if frame.again.SetEnabled then frame.again:SetEnabled(F.method ~= nil) end
    for _, mb in ipairs(frame.methods) do
        if mb.SetButtonState then mb:SetButtonState(mb.key == F.method and "PUSHED" or "NORMAL", mb.key == F.method) end
    end
    local nx = list[1]
    if not nx then frame.all:SetText("Buy next: nothing to buy")
    else
        local st = rowState(nx)
        frame.all:SetText(string.format("Buy next: %s%s", money(nx.offers[1].buyout),
            st == "ready - click to buy" and "" or (st and " (searching)" or "")))
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
end

function F.Show()
    if not frame then build() end
    if not frame then return false end
    anchor()
    frame:Show()
    F.Paint()
    return true
end
function F.Frame() return frame end
function F.Open()
    local h = H()
    if not (h and h.open) then OMQ:Print("item flips: open the auction house first (with the auction helper on)"); return false end
    F.Show()
    if not run and not F.method then status("choose a method above - the search starts then") end   -- fix 724
    return true
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
                     "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
                     "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
                     "ITEM_SEARCH_RESULTS_UPDATED", "GET_ITEM_INFO_RECEIVED", "ITEM_KEY_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local considerAt = nil
ev:SetScript("OnEvent", function(_, event, a1)
    local ok, err = pcall(function()
        if event == "AUCTION_HOUSE_CLOSED" then
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
