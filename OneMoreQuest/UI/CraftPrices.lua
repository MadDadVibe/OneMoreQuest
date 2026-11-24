-- One More Quest: auction house prices of everything (decision 341, step 1 of the crafting profit)
-- The whole auction house is read once with an empty browse search, page by page (decision 432; the
-- ReplicateItems dump of decision 342 gave a frozen old list on Forever), and the
-- lowest price of every item is kept in the saved variables (per realm) until the next scan replaces it.
-- The crafting profit (UI/CraftProfit.lua) reads these prices. The scan starts by itself when the auction
-- house opens and the last one is older than 4 hours (option, decision 428), or with
-- /omq prices scan. It gives way to the auction helper: it never starts while the helper asks for something,
-- and it waits while a post or a purchase is going on. While it runs, the helper's panel and the game's auction
-- house window are covered (decision 431); the dad's own window no longer pauses it.
-- Decision 604: every search has the form of the game's own window (quality filters, a class filter per
-- subcategory); the server limits browse searches without quality filters. The scan writes an event log.
-- Decision 431: the scan only serves the crafting profit and the tooltip price. Selling and buying search live.
-- The first live answers of a visit are compared with the scan (/omq prices check), so a wrong scan shows.
-- Vendor prices are learned too: every merchant window written down what an item costs there, so reagents
-- from a vendor (thread, vials) count in the profit with their vendor price.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.Prices = P

P.MAX_AGE = 900             -- a live price stays this long, also through the next dump (decision 427)
P.AUTO_AGE = 4 * 3600       -- an automatic scan only when the last one is older than 4 hours (decision 428; was 15 minutes, decision 343)
P.START_DELAY = 0.2         -- seconds after the window opens before the scan starts (decision 343)

local function now() return GetTime() end
local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function stamp() return time and time() or 0 end

local function realm() return (GetRealmName and GetRealmName()) or "?" end
local function store()
    OMQDB.prices = OMQDB.prices or {}
    local r = realm()
    OMQDB.prices[r] = OMQDB.prices[r] or { items = {}, at = 0, n = 0 }
    return OMQDB.prices[r]
end
-- decision 636: only offers a vendor always has are learned (no limited stock such as Peacebloom); the prices
-- learned before that are dropped once and learned again at the next merchant visit
P.VENDOR_V = 2
local function vendorStore()
    if OMQDB.vendorPricesV ~= P.VENDOR_V then OMQDB.vendorPrices, OMQDB.vendorPricesV = {}, P.VENDOR_V end
    OMQDB.vendorPrices = OMQDB.vendorPrices or {}
    return OMQDB.vendorPrices
end

function P.AutoOn() return not (OMQ.db and OMQ.db.options and OMQ.db.options.priceScan == false) end

-- the lowest auction price of one piece (copper), its quantity on offer, and the time of the scan
-- (or of the live search that corrected it, decision 427)
function P.Auction(itemID)
    local e = store().items[itemID]
    if e then return e.p, e.q, e.t or store().at end
end
-- a price that a live search saw (the helper's own or one in the game's window) at most maxAge seconds ago:
-- the dump can be far off (decision 427), so selling and buying go by this
function P.Live(itemID, maxAge)
    local e = store().items[itemID]
    if e and e.t and stamp() - e.t <= (maxAge or P.MAX_AGE) then return e.p, e.q, e.t end
end
-- every live answer of the auction house corrects the stored price of a commodity (decision 427)
function P.Learn(itemID, unit, qty)
    if not itemID or isSecret(itemID) or isSecret(unit) or type(unit) ~= "number" or unit <= 0 then return end
    local items = store().items
    local old = items[itemID]
    if not old then store().n = (store().n or 0) + 1 end
    if old and not old.t and old.p and old.p > 0 then P.Compare(itemID, old.p, old.q, math.floor(unit), tonumber(qty)) end
    items[itemID] = { p = math.floor(unit), q = tonumber(qty) or (old and old.q) or 0, t = stamp() }
end
local function learnCommodity(itemID)
    local api = C_AuctionHouse
    if not (api and api.GetNumCommoditySearchResults and api.GetCommoditySearchResultInfo) or isSecret(itemID) then return end
    local n = tonumber(api.GetNumCommoditySearchResults(itemID)) or 0
    local best, qty = nil, 0
    for i = 1, math.min(n, 50) do
        local r = api.GetCommoditySearchResultInfo(itemID, i)
        local u = r and r.unitPrice
        if u and not isSecret(u) and u > 0 then
            if not best or u < best then best = u end
            qty = qty + (tonumber(r.quantity) or 0)
        end
    end
    if api.GetCommoditySearchResultsQuantity then
        local ok, t = pcall(api.GetCommoditySearchResultsQuantity, itemID)
        if ok and type(t) == "number" and not isSecret(t) and t > qty then qty = t end
    end
    if best then P.Learn(itemID, best, qty) end
end
local function isCommodityKey(k)
    local api = C_AuctionHouse
    if api and api.GetItemKeyInfo then
        local ok, ki = pcall(api.GetItemKeyInfo, k)
        if ok and type(ki) == "table" and ki.isCommodity ~= nil then return ki.isCommodity and true or false end
    end
    local G = C_Item and C_Item.GetItemInfo or GetItemInfo
    local stack = G and select(8, G(k.itemID))
    return (tonumber(stack) or 1) > 1
end
local function learnBrowse()
    local api = C_AuctionHouse
    for _, res in ipairs(api and api.GetBrowseResults and api.GetBrowseResults() or {}) do
        local k = res.itemKey
        if k and k.itemID and type(res.minPrice) == "number" and not isSecret(res.minPrice) and res.minPrice > 0 and isCommodityKey(k) then
            P.Learn(k.itemID, res.minPrice, res.totalQuantity)
        end
    end
end
P._learnCommodity, P._learnBrowse = learnCommodity, learnBrowse

-- the self check (decision 431): a dump price next to the live price of the same item, the last CHECK_KEEP of them
P.CHECK_KEEP = 40
function P.Compare(itemID, dumpP, dumpQ, liveP, liveQ)
    local st = store()
    st.check = st.check or {}
    local c = st.check
    for i = #c, 1, -1 do if c[i].id == itemID then table.remove(c, i) end end
    c[#c + 1] = { id = itemID, dp = dumpP, dq = dumpQ, lp = liveP, lq = liveQ, t = stamp() }
    while #c > P.CHECK_KEEP do table.remove(c, 1) end
end
-- how far off the dump was: { n, off = how many are more than 50% away, worst = the five worst lines }
function P.CheckReport()
    local c = store().check or {}
    local list, off = {}, 0
    for _, e in ipairs(c) do
        local r = e.dp / math.max(1, e.lp)
        local far = r > 1.5 or r < 1 / 1.5
        if far then off = off + 1 end
        list[#list + 1] = { e = e, d = math.abs(math.log(math.max(r, 0.0001))) }
    end
    table.sort(list, function(a, b) return a.d > b.d end)
    local worst = {}
    for i = 1, math.min(5, #list) do worst[i] = list[i].e end
    return { n = #c, off = off, worst = worst }
end
function P.Vendor(itemID) return vendorStore()[itemID] end
-- what the item costs me to get: the cheaper of the auction house and a vendor; nil = unknown
function P.Cost(itemID)
    local a, v = P.Auction(itemID), P.Vendor(itemID)
    if a and v then return math.min(a, v), a <= v and "ah" or "vendor" end
    if a then return a, "ah" end
    if v then return v, "vendor" end
    return nil
end
function P.ScannedAt() local at = store().at; return at and at > 0 and at or nil end
function P.Count() return store().n or 0 end

----------------------------------------------------------------------
-- The scan: the browse list of everything, page by page (decision 432)
----------------------------------------------------------------------
local scan = nil           -- { state "start" | "browsing", queue, qi, q (the current search), items, seen, results, startedAt }
function P.Busy() return scan ~= nil end
-- the scan is good for this window: a scan finished, or the last one is fresh (decision 343)
local sessionAt = nil
function P.Session() return sessionAt ~= nil and not scan end
function P.SessionAt() return sessionAt end
function P.EndSession() sessionAt = nil end
function P.Items() return store().items end
function P.Progress()
    if not scan then return nil end
    local q = scan.q or {}
    return { results = scan.results + (q.results or 0), total = scan.results + (q.results or 0), state = scan.state,
             pages = q.pages, tries = q.tries, part = scan.qi, parts = #scan.queue }
end
P.last = nil               -- how the last scan ended: { ok, items, secs, results, pages, why, partial }
P.WAIT = 30                -- seconds to wait for the next answer of the auction house
P.PAGES = 200              -- at most this many pages of one search, so a scan always ends
-- decision 447: the game's own window searches when it opens; a search of ours in the same moment can go
-- unanswered. The scan waits FIRST_WAIT seconds after the start. Decision 604: a search the server answered with
-- nothing at all for ANSWER_WAIT seconds, dropped (AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED) or failed is sent
-- again, at most TRIES times.
P.FIRST_WAIT, P.ANSWER_WAIT, P.TRIES = 2, 5, 3
-- decision 448: a complete scan with less than SHRINK of the items of the last complete scan only counts as partial.
P.SHRINK = 0.5
-- decision 450: one search for everything stops at 500 lines. The scan searches category by category; a
-- category whose complete list is a whole number of full PAGEs may have been cut off and is searched once more
-- per subcategory.
P.CLASSES = { 0, 7, 5, 8, 9, 1, 11, 6, 3, 12, 15, 2, 4 }
P.SUBCLASSES = { [2] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 14, 15, 16, 17, 18, 19, 20 }, [4] = { 0, 1, 2, 3, 4, 6 } }
P.PAGE = 500
-- Decision 604 (measured 2026-11-15 with /omq prices probe and /omq ahtest): the server of Forever limits browse
-- searches that carry no quality filters - after about seven of them it answers a couple of minutes with an
-- empty list (and such a search never brings more than 500 lines). The search the game's own window sends is
-- not limited: all six quality filters, level range 0-0 and one class filter per subcategory. Every browse
-- search of the addon has that form now (P.GameQuery), and the scan paces itself the way the measurement did:
-- the next search GAP seconds after the last one ended, and only when the game says its message system is ready.
-- An empty list counts as "nothing on sale" when the server's answer came with it (RESPONSE_RECEIVED) and the
-- game calls the list complete. A category that came empty, did not answer, or brought less than CAT_SHRINK of
-- its lines of the last complete scan loses nothing: its items keep their old prices (fix 549).
P.GAP = 2
P.CHECK_LINES = 30   -- fix 557: this many lines of an answer are checked for their category
P.CAT_SHRINK, P.CAT_MIN = 0.5, 20   -- short: under half the lines of a category that had at least 20
P.LOG_MAX = 800      -- lines of the scan's event log kept (OMQDB.priceScanLast.log)
P.LOG_SHOWN = 40     -- lines /omq prices log prints

local function helper() return OMQ.AuctionHelper end
local function A() return C_AuctionHouse end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- ok: every category came complete; partial: only a part came, its prices are kept but nothing is removed
local function finish(ok, why, partial)
    if not scan then return end
    local st = store()
    local n = count(scan.seen)
    if ok then
        -- the scan replaces the list: what was sold is gone; a live price of the last minutes stays (decision 427)
        local own = n
        for id, e in pairs(st.items) do
            -- a category that stopped at a full page may miss items: those keep their old price (decision 450);
            -- so do the items of a category that came empty or short (fix 549), and the items the item pass asked
        -- for without an answer (decision 580)
            if (e.t and stamp() - e.t <= P.MAX_AGE) or (not scan.items[id] and (scan.capped or P._Lost(scan, id) or (scan.asked and scan.asked[id]))) then
                if not scan.items[id] then n = n + 1 end
                scan.items[id] = e
            end
        end
        st.items = scan.items
        st.at, st.n = stamp(), n
        st.full = own                                   -- decision 450 (fullN of 448 could hold a wrong scan)
        st.fullN = nil
        st.check = {}
        local catN = {}                                 -- lines per category; a lost one keeps its last count (fix 549)
        for k, v in pairs(st.catN or {}) do catN[k] = v end
        st.catN = catN
        for _, c in ipairs(scan.cats) do
            if c.how == "ok" or c.how == "capped" then st.catN[P.CatKey(c.c, c.s)] = c.n end
        end
        sessionAt = now()
    elseif partial and n > 0 then
        for id, e in pairs(scan.items) do
            local old = st.items[id]
            if not (old and old.t and stamp() - old.t <= P.MAX_AGE) then
                if not old then st.n = (st.n or 0) + 1 end
                st.items[id] = e
            end
        end
    end
    P.last = { ok = ok, items = n, secs = now() - scan.startedAt, results = scan.results, pages = scan.pages, why = why,
               partial = partial and true or nil, searches = math.min(scan.qi, #scan.queue), capped = scan.capped,
               cats = scan.cats, log = scan.log, form = "game" }
    if OMQDB then OMQDB.priceScanLast = P.last end
    scan = nil
    local H = helper()
    if (ok or partial) and H and H.Evaluate then pcall(H.Evaluate) end
    if H and H.Refresh then pcall(H.Refresh) end
    if H and H.Pump then pcall(H.Pump) end
    if OMQ.Fire then OMQ:Fire("PRICES_UPDATED", ok) end
end

local function classOf(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, _, _, _, _, c, sc = pcall(f, id)
    if ok then return c, sc end
end

-- fix 549: which categories of a scan count as lost (empty, no answer, or far fewer lines than last time)
function P.CatKey(c, s) return s and (c .. "." .. s) or tostring(c) end
function P._Lost(sc, id)
    if not sc.lost or not next(sc.lost) then return false end
    local c, s = classOf(id)
    if c == nil then return false end
    return sc.lost[tostring(c)] or (s ~= nil and sc.lost[c .. "." .. s]) or false
end
-- what one search brought: lines, and how it ended (ok, empty, failed, capped, split)
local function noteCat(q, how)
    local n = q.results or 0
    -- fix 579: what the auction house did for this search, kept in the saved variables (priceScanLast.cats) to find
    -- out why a category comes empty: events, empty lists, foreign lists (and the class of one), asks, throttle
    -- waits, seconds until the first list with lines
    scan.cats[#scan.cats + 1] = { c = q.classID, s = q.subClassID, n = n, how = how, ev = q.ev, emp = q.emp, rej = q.rej,
                                  rc = q.rejC, asks = q.tries, thr = q.thr,
                                  secs = q.gotAt and math.floor(q.gotAt * 10 + 0.5) / 10 or nil }
    local key = P.CatKey(q.classID, q.subClassID)
    local lastN = (store().catN or {})[key]
    if how == "empty" or how == "failed" or (how == "ok" and lastN and lastN >= P.CAT_MIN and n < lastN * P.CAT_SHRINK) then
        scan.lost[key] = true
        if how == "ok" then scan.cats[#scan.cats].how = "short" end
    end
end

-- the browse list of the current search: one line per item with the lowest price of one piece and the pieces on
-- offer, the same list the game's own window shows. Gear of one item with different item levels comes as several
-- lines: the cheapest counts, the pieces add up. Returns the lines, and false when the list is not ours: its
-- items belong to another category (decision 450, the answer to another search).
local function readList()
    local api, q = A(), scan.q
    local ok, list = pcall(api.GetBrowseResults)
    if not ok or type(list) ~= "table" then return 0, true end
    local items, foreign, checked = {}, 0, 0
    for _, res in ipairs(list) do
        local k = res.itemKey
        local id, price, qty = k and k.itemID, res.minPrice, res.totalQuantity
        if id and not isSecret(id) and not isSecret(price) and type(price) == "number" and price > 0 then
            if checked < P.CHECK_LINES then
                checked = checked + 1
                -- fix 578: only the class counts - the game's own subclass of an item can differ from the one the
                -- auction house files it under (every answer to a consumables subcategory was thrown away)
                local c = classOf(id)
                if c and c ~= q.classID then foreign = foreign + 1 end
            end
            qty = (not isSecret(qty) and tonumber(qty)) or 0
            local e = items[id]
            if e then
                if price < e.p then e.p = math.floor(price) end
                e.q = e.q + qty
            else items[id] = { p = math.floor(price), q = qty } end
        end
    end
    -- fix 557: a list with items of other categories is not ours (the game's favorites list when the window opens
    -- came as the answer to the consumables: 41 lines, and every other consumable lost its price)
    if foreign >= 2 or (foreign >= 1 and checked < 10) then
        q.rej = (q.rej or 0) + 1
        if not q.rejC then
            local k = list[1] and list[1].itemKey
            q.rejC = k and k.itemID and not isSecret(k.itemID) and classOf(k.itemID) or -1
        end
        return #list, false
    end
    q.items, q.results = items, #list
    return #list, true
end
local function full()
    local api = A()
    if not api.HasFullBrowseResults then return true end
    local ok, f = pcall(api.HasFullBrowseResults)
    return ok and f and true or false
end

local function throttleReady()
    local api = A()
    return not (api and api.IsThrottledMessageSystemReady) or api.IsThrottledMessageSystemReady()
end
P._Ready = throttleReady

local function yielding()
    local H = helper()
    if not H then return false end
    if H.Busy and H.Busy() then return true end
    if H.quietUntil and now() < H.quietUntil then return true end
    -- a search of the helper still on its way needs no extra wait (decision 604): the scan only sends when the
    -- game's message system is ready again, and the helper sends nothing while the scan runs
    -- the dad's own window no longer holds the scan back: it is covered while the scan runs (decision 431)
    return false
end

-- an own call of the addon: the helper does not count it as the dad's window (decision 427)
local function own(fn, ...)
    local H = helper()
    if H and H.Own then return H.Own(fn, ...) end
    return fn(...)
end

-- the scan's event log (decision 604): every search, page and auction house event with its time since the
-- start, kept with the result of the scan in the saved variables (/omq prices log shows the end of it)
local function log(text)
    if not scan or #scan.log >= P.LOG_MAX then return end
    scan.log[#scan.log + 1] = string.format("%.2f %s", now() - scan.startedAt, text)
end

----------------------------------------------------------------------
-- Decision 604: the browse search in the form of the game's own window
----------------------------------------------------------------------
-- all quality filters, as the game's window has them by default
function P.QualityFilters()
    local F = Enum and Enum.AuctionHouseFilter
    local out = {}
    if not F then return out end
    for _, k in ipairs({ "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality", "EpicQuality", "LegendaryQuality" }) do
        if F[k] ~= nil then out[#out + 1] = F[k] end
    end
    return out
end
-- the subcategories the game names for a class (a list, or several return values), else the known ones
function P.Subclasses(c)
    local out, seen = {}, {}
    local api = A()
    if api and api.GetAuctionItemSubClasses then
        local ok, list = pcall(function() return { api.GetAuctionItemSubClasses(c) } end)
        if ok and type(list) == "table" and type(list[1]) == "table" then list = list[1] end
        for _, v in ipairs(ok and type(list) == "table" and list or {}) do
            if type(v) == "number" and not seen[v] then seen[v] = true; out[#out + 1] = v end
        end
    end
    if #out == 0 then for _, v in ipairs(P.SUBCLASSES[c] or {}) do out[#out + 1] = v end end
    return out
end
local function twoSorts()
    local E = Enum and Enum.AuctionHouseSortOrder
    return { { sortOrder = E and E.Price or 0, reverseSort = false }, { sortOrder = E and E.Name or 1, reverseSort = false } }
end
-- the search for a class the way the game's window asks for a category: one class filter per subcategory (or
-- the one subcategory asked for), all qualities, a level range (0-0: every level)
function P.GameQuery(c, sub, minLevel, maxLevel, sorts)
    local f = {}
    if sub ~= nil then f[1] = { classID = c, subClassID = sub }
    else
        for _, s in ipairs(P.Subclasses(c)) do f[#f + 1] = { classID = c, subClassID = s } end
        if #f == 0 then f[1] = { classID = c } end
    end
    return { searchString = "", minLevel = minLevel or 0, maxLevel = maxLevel or 0, filters = P.QualityFilters(),
             sorts = sorts or twoSorts(), itemClassFilters = f }
end
-- the search of one category (and subcategory); two sort keys mark it as the scan's own (decision 450)
P.QUERY = function(f)
    f = f or {}
    return P.GameQuery(f.classID, f.subClassID)
end

local function send()
    local api, q = A(), scan.q
    q.lastAt, q.answered, q.more, q.results, q.resp, q.dropped, q.sawEmpty = now(), false, false, 0, false, nil, nil
    q.sentAt = q.sentAt or now()
    log(string.format("SEND %s try %d ready=%s", P.CatKey(q.classID, q.subClassID), q.tries or 1, tostring(P._Ready())))
    local ok, err = pcall(own, api.SendBrowseQuery, P.QUERY(q))
    if not ok then finish(false, "SendBrowseQuery failed: " .. tostring(err)) end
end

-- the next search of the list, or the end
local function nextSearch()
    scan.qi = scan.qi + 1
    local f = scan.queue[scan.qi]
    if not f then
        local items = count(scan.seen)
        local last = store().full
        if scan.failed > 0 then
            scan.endArgs = { false, scan.failed .. " categories did not answer", true }
        elseif last and items < last * P.SHRINK then
            scan.endArgs = { false, string.format("only %d items, the last complete scan had %d", items, last), true }
        else scan.endArgs = { true } end
        log(string.format("ITEMS after %d searches, %d items", #scan.queue, items))
        P._StartItems()                                  -- decision 580: then the important items one by one
        return
    end
    scan.q = { classID = f.classID, subClassID = f.subClassID, pages = 1, tries = 1 }
    scan.state = "browsing"
    if throttleReady() then send() else scan.q.waiting = true end
end

-- the current search is done: its items go to the scan; a search that stopped at a full page is split
local function searchDone(capped, how)
    local q = scan.q
    local subs = capped and q.subClassID == nil and P.Subclasses(q.classID) or nil
    if subs and #subs >= 2 then
        noteCat(q, "split")
        for _, sub in ipairs(subs) do
            scan.queue[#scan.queue + 1] = { classID = q.classID, subClassID = sub }
        end
    else
        if capped then scan.capped = (scan.capped or 0) + 1 end
        noteCat(q, how or (capped and "capped") or "ok")
        for id, e in pairs(q.items or {}) do
            local old = scan.items[id]
            if old then
                if e.p < old.p then old.p = e.p end
                old.q = old.q + e.q
            else scan.items[id] = { p = e.p, q = e.q }; scan.seen[id] = true end
        end
        scan.results = scan.results + (q.results or 0)
    end
    scan.pages = scan.pages + (q.pages or 0)
    log(string.format("DONE %s %s lines=%d pages=%d", P.CatKey(q.classID, q.subClassID), scan.cats[#scan.cats].how, q.results or 0, q.pages or 0))
    -- the next search a moment later, at the pace the measurement ran at (decision 604)
    scan.q, scan.state, scan.gapAt = nil, "gap", now()
    P.Step()
end

-- an answer of the auction house came (first page or more): ask for the next page or end the search
local function onAnswer(event)
    if not scan or scan.state ~= "browsing" or not scan.q or scan.q.waiting then return end
    local q = scan.q
    q.ev = (q.ev or 0) + 1
    local n, mine = readList()
    local complete = full()
    log(string.format("%s lines=%d complete=%s%s", event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" and "ADD" or "UPD", n, tostring(complete),
        mine and "" or " foreign"))
    if not mine then return end                            -- the answer to another search
    if n == 0 then
        q.emp = (q.emp or 0) + 1
        q.sawEmpty = true
        -- the server's own answer and the list is complete: nothing of this category is on sale (decision 604).
        -- Without the answer mark it is an event of an older search: wait for ours.
        if q.resp and complete then q.items, q.results = {}, 0; searchDone(false, "empty") end
        return
    end
    q.lastAt = now()
    q.answered = true
    q.gotAt = q.gotAt or (now() - (q.sentAt or now()))
    if complete then searchDone(n % P.PAGE == 0)
    elseif q.pages >= P.PAGES then searchDone(true)
    else q.more = true; P.Step() end
end
P._onAnswer = onAnswer

-- the game's message events while a category is searched (decision 604)
P.THROTTLE = { AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = "DROP", AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED = "QUEUE",
               AUCTION_HOUSE_THROTTLED_MESSAGE_SENT = "SENT", AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED = "RESP",
               AUCTION_HOUSE_THROTTLED_SYSTEM_READY = "READY" }
local function onThrottle(event)
    if not scan then return end
    local short = P.THROTTLE[event]
    log(short)
    local q = scan.state == "browsing" and scan.q
    if not q or q.waiting then return end
    if short == "RESP" then q.resp = true
    elseif short == "DROP" then q.dropped = true; q.drops = (q.drops or 0) + 1
    elseif short == "READY" then P.Step() end                -- the next page at once, not at the next tick
end
P._onThrottle = onThrottle

-- the next step: send the request, ask for the next page, or give up when the answers stop
function P.Step()
    if not scan then return end
    local api = A()
    local H = helper()
    if not (api and H and H.open) then finish(false, "the window closed"); return end
    if scan.state == "items" then                          -- decision 580: no answer in time = not on sale, next batch
        if not scan.iq or now() - scan.iq.at > P.ITEM_WAIT then scan.iq = nil; P._NextItems() end
        return
    end
    if scan.state == "start" then
        if now() - scan.startedAt < P.FIRST_WAIT then return end
        if yielding() or not throttleReady() then return end
        nextSearch()
        return
    end
    if scan.state == "gap" then
        if now() - scan.gapAt < P.GAP or not throttleReady() then return end
        nextSearch()
        return
    end
    local q = scan.q
    if not q then return end
    if q.waiting then
        if not throttleReady() then q.thr = (q.thr or 0) + 1; return end
        q.waiting = nil
        send()
    elseif q.dropped then
        -- the server dropped our message: the page again, or the whole search again (decision 604)
        if not throttleReady() then return end
        q.dropped = nil
        if q.answered then q.more, q.pages = true, q.pages - 1; P.Step()
        elseif q.tries >= P.TRIES then scan.failed = scan.failed + 1; q.items = nil; searchDone(false, "failed")
        else q.tries = q.tries + 1; send() end
    elseif not q.answered and now() - q.lastAt > P.ANSWER_WAIT then
        -- nothing but empty lists and no word of the server: nothing of this category on sale (fix 549)
        if q.sawEmpty then q.items, q.results = {}, 0; searchDone(false, "empty"); return end
        -- no list at all: ask again, a few times (decision 447); then the next category
        if q.tries >= P.TRIES then scan.failed = scan.failed + 1; q.items = nil; searchDone(false, "failed"); return end
        if not throttleReady() then return end
        q.tries = q.tries + 1
        send()
    elseif q.more then
        if not throttleReady() then return end
        q.more, q.lastAt, q.pages = false, now(), q.pages + 1
        log("MORE page " .. q.pages)
        local ok, err = pcall(own, api.RequestMoreBrowseResults)
        if not ok then finish(false, "RequestMoreBrowseResults failed: " .. tostring(err), true) end
    elseif q.answered and now() - q.lastAt > P.WAIT then
        -- the next page never came: what is there counts, the category is not complete
        scan.failed = scan.failed + 1
        searchDone(false, "failed")
    end
end

----------------------------------------------------------------------
-- Decision 580: after the categories, the important items the categories did not bring are searched by name
-- (SearchForItemKeys, ITEM_BATCH at once, like the auction helper's batch): everything the Profession Check
-- crafts or needs, what the buy mode can suggest, and the items of the shopping lists. On Forever the
-- category search brings only part of the consumables and trade goods, and a search per subcategory runs into
-- empty answers (fix 579 log). An item that is not on sale keeps its old price.
----------------------------------------------------------------------
P.ITEM_BATCH, P.ITEM_WAIT, P.ITEM_MAX = 40, 5, 800
function P.ImportantItems()
    local ids, seen = {}, {}
    local function add(id)
        id = tonumber(id)
        if id and id > 0 and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    for _, r in pairs(OMQ.ProfRecipes or {}) do
        add(r[1])
        for k = 1, #(r[3] or {}), 2 do add(r[3][k]) end
    end
    for _, line in pairs(OMQ.BuyLines or {}) do
        for _, e in ipairs(line[2] or {}) do add(e[1]) end
    end
    for _, e in ipairs(OMQ.BuyFoods or {}) do add(e[1]) end
    local S = OMQ.Shopping
    if S and S.Lists then
        local ok, lists = pcall(S.Lists)
        for _, l in ipairs(ok and lists or {}) do
            for _, it in ipairs(l.items or {}) do if not it.vendor then add(it.itemID) end end
        end
    end
    table.sort(ids)
    return ids
end
local function itemKey(id)
    local api = A()
    if api and api.MakeItemKey then
        local ok, k = pcall(api.MakeItemKey, id)
        if ok and k then return k end
    end
    return { itemID = id, itemLevel = 0, itemSuffix = 0 }
end
function P._StartItems()
    local want = {}
    local vendor = OMQ.ProfVendorPrices or {}
    for _, id in ipairs(P.ImportantItems()) do
        -- already in the categories, or a vendor item (thread, vials): nothing to ask
        if not scan.items[id] and not vendor[id] and not vendorStore()[id] then want[#want + 1] = id end
        if #want >= P.ITEM_MAX then break end
    end
    local api = A()
    if #want == 0 or not (api and api.SearchForItemKeys) then finish(unpack(scan.endArgs)); return end
    scan.want, scan.wi, scan.state, scan.itemsFound = want, 0, "items", 0
    scan.cats[#scan.cats + 1] = { c = "items", n = 0, how = "ok", asks = 0, ev = 0, emp = 0 }
    P._NextItems()
end
function P._NextItems()
    if scan.wi >= #scan.want then
        local c = scan.cats[#scan.cats]
        c.n = scan.itemsFound
        finish(unpack(scan.endArgs))
        return
    end
    if not throttleReady() then scan.iq = nil; return end
    local keys, batch = {}, {}
    for i = scan.wi + 1, math.min(#scan.want, scan.wi + P.ITEM_BATCH) do
        keys[#keys + 1] = itemKey(scan.want[i]); batch[scan.want[i]] = true
    end
    scan.wi = scan.wi + #keys
    scan.asked = scan.asked or {}
    for id in pairs(batch) do scan.asked[id] = true end   -- asked and not found: keeps its old price
    scan.iq = { batch = batch, at = now() }
    scan.cats[#scan.cats].asks = scan.cats[#scan.cats].asks + 1
    log(string.format("ASK %d items (%d of %d)", #keys, scan.wi, #scan.want))
    local Eo = Enum and Enum.AuctionHouseSortOrder
    local ok, err = pcall(own, A().SearchForItemKeys, keys, { { sortOrder = Eo and Eo.Price or 0, reverseSort = false } })
    if not ok then finish(false, "SearchForItemKeys failed: " .. tostring(err), true) end
end
-- an answer during the item pass: the lines of the items asked for count, every other line is not ours
local function onItems()
    local iq = scan.iq
    if not iq then return end
    local c = scan.cats[#scan.cats]
    c.ev = c.ev + 1
    local ok, list = pcall(A().GetBrowseResults)
    if not ok or type(list) ~= "table" then return end
    local got = 0
    for _, res in ipairs(list) do
        local k = res.itemKey
        local id, price, qty = k and k.itemID, res.minPrice, res.totalQuantity
        if id and not isSecret(id) and iq.batch[id] and type(price) == "number" and not isSecret(price) and price > 0 then
            qty = (not isSecret(qty) and tonumber(qty)) or 0
            local e = scan.items[id]
            if e then
                if price < e.p then e.p = math.floor(price) end
            else
                scan.items[id] = { p = math.floor(price), q = qty }; scan.seen[id] = true
                scan.itemsFound = scan.itemsFound + 1
            end
            got = got + 1
        end
    end
    if got == 0 then c.emp = c.emp + 1; return end      -- an empty list or another search's: wait for ours
    scan.results = scan.results + got
    scan.iq = nil
    P._NextItems()
end
P._onItems = onItems

function P.Start(manual)
    if scan then return false, "a scan is running" end
    if OMQ.PriceProbe and OMQ.PriceProbe.Running() then return false, "the probe is running" end   -- fix 587
    if OMQ.AHTest and OMQ.AHTest.Running() then return false, "the test window is searching" end   -- decision 597
    local H = helper()
    if not (H and H.open) then return false, "open the auction house first" end
    local api = A()
    if not (api and api.SendBrowseQuery and api.GetBrowseResults) then
        return false, "this client has no browse list"
    end
    local queue = {}
    for _, c in ipairs(P.CLASSES) do queue[#queue + 1] = { classID = c } end
    scan = { state = "start", items = {}, seen = {}, results = 0, pages = 0, startedAt = now(), queue = queue, qi = 0, failed = 0,
             cats = {}, lost = {}, log = {} }
    if manual then OMQ:Print("prices: asking the auction house category by category - this takes a little while") end
    sessionAt = nil
    if H.Refresh then pcall(H.Refresh) end
    P.Step()
    return true
end

function P.Cancel() if scan then finish(false, "stopped") end end

----------------------------------------------------------------------
-- Events and commands
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW", "MERCHANT_UPDATE",
                     "COMMODITY_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
                     "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
                     "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
                     "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- what a merchant sells and for how much one piece (decisions 341, 345). The client may have the old globals or
-- C_MerchantFrame; both are tried, and the result is told once per merchant window.
local function merchantItem(i)
    local link, price, qty, extended, avail
    local M = C_MerchantFrame
    if M and M.GetItemInfo then
        local ok, t = pcall(M.GetItemInfo, i)
        if ok and type(t) == "table" then price, qty, extended, avail = t.price, t.stackCount, t.hasExtendedCost, t.numAvailable end
    end
    if price == nil and GetMerchantItemInfo then
        local ok, _, _, p, q, a, _, _, x = pcall(GetMerchantItemInfo, i)   -- 8th value: extendedCost
        if ok then price, qty, extended, avail = p, q, x, a end
    end
    if GetMerchantItemLink then link = GetMerchantItemLink(i)
    elseif M and M.GetItemLink then link = M.GetItemLink(i) end
    return link, price, qty, extended, avail
end
-- a vendor offer with a limited stock (numAvailable 0 or more; -1 = always there), decision 636
function P.Limited(avail) return type(avail) == "number" and not isSecret(avail) and avail >= 0 end
function P.LearnVendor()
    local num = GetMerchantNumItems and GetMerchantNumItems() or (C_MerchantFrame and C_MerchantFrame.GetNumItems and C_MerchantFrame.GetNumItems()) or 0
    local n, vs = 0, vendorStore()
    for i = 1, num do
        local link, price, qty, extended, avail = merchantItem(i)
        local id = link and tonumber(tostring(link):match("item:(%d+)"))
        if id and type(price) == "number" and not isSecret(price) and price > 0 and not extended and not P.Limited(avail) then
            vs[id] = math.floor(price / math.max(1, tonumber(qty) or 1))
            n = n + 1
        end
    end
    P.lastMerchant = { items = num, learned = n }
    return n
end

-- the latest scanned price in every item tooltip (decision 345)
local function agoText(at)
    if not at then return "" end
    local d = (time and time() or 0) - at
    if d < 120 then return "just now" end
    if d < 7200 then return math.floor(d / 60) .. " min ago" end
    if d < 172800 then
        local h = math.floor(d / 3600)
        return h .. (h == 1 and " hour ago" or " hours ago")
    end
    return math.floor(d / 86400) .. " days ago"
end
P._agoText = agoText
local function money(c)
    local C = OMQ.CraftProfit
    if C and C.Money then return C.Money(c) end
    return c .. "c"
end
-- how many pieces the hovered item is (decision 430): the item GUID of the tooltip data, else the bag slot of the
-- tooltip's owner. Anything unreadable or secret counts as one piece.
local function stackCount(tt, data)
    local n
    local own = tt and rawget(tt, "omqCount")                     -- the recipe item tooltip: pieces per craft (decision 661)
    if type(own) == "number" and own > 1 then return math.floor(own) end
    local C = C_Item
    if data and data.guid and not isSecret(data.guid) and C and C.GetItemLocation and C.GetStackCount then
        local ok, loc = pcall(C.GetItemLocation, data.guid)
        if ok and loc then
            local ok2, c = pcall(C.GetStackCount, loc)
            if ok2 then n = c end
        end
    end
    if n == nil and tt and tt.GetOwner and C_Container and C_Container.GetContainerItemInfo then
        local ok, owner = pcall(tt.GetOwner, tt)
        if ok and type(owner) == "table" and owner.GetID then
            local bag
            if owner.GetBagID then bag = owner:GetBagID()
            elseif owner.GetName and tostring(owner:GetName() or ""):match("^ContainerFrame%d+Item%d+$")
                and owner.GetParent and owner:GetParent() and owner:GetParent().GetID then
                bag = owner:GetParent():GetID()                -- older bag buttons: the bag frame holds the bag id
            end
            local slot = owner:GetID()
            if type(bag) == "number" and type(slot) == "number" and not isSecret(bag) and not isSecret(slot) then
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if ok2 and type(info) == "table" then n = info.stackCount end
            end
        end
    end
    if type(n) ~= "number" or isSecret(n) or n < 1 then return 1 end
    return math.floor(n)
end
P._stackCount = stackCount
-- the price block of the item tooltip (decision 675): a header "OMQ (scanned 4 hours ago, 413 items)", then
-- Vendor (white, what the vendor pays), Auction (green, the scanned price) and Disenchant (purple, UI/DisenchantValue.lua)
-- one below the other, the values in one column. A stack shows the whole stack and one piece in brackets (decision 430).
P.COLORS = { head = { 1, 0.82, 0 }, vendor = { 1, 1, 1 }, auction = { 0.25, 1, 0.25 }, disenchant = { 0.78, 0.45, 1 } }
-- what the vendor pays for one piece (copper), nil when he buys nothing or the game has not loaded the item
function P.SellPrice(itemID)
    local function try(fn)
        if not fn then return nil end
        local ok, name, _, _, _, _, _, _, _, _, _, sell = pcall(fn, itemID)
        if ok and type(name) == "string" and name ~= "" and type(sell) == "number" and not isSecret(sell) then return sell end
    end
    local v = try(C_Item and C_Item.GetItemInfo)
    if v == nil then v = try(GetItemInfo) end
    if type(v) == "number" and v > 0 then return v end
end
-- the width of a text in the tooltip font, to put the values in one column; without a font: 6 per letter
local meter
local function width(s)
    if meter == nil then
        meter = false
        if UIParent and UIParent.CreateFontString then
            local ok, fs = pcall(UIParent.CreateFontString, UIParent, nil, "OVERLAY", "GameTooltipText")
            if ok and fs then meter = fs; if fs.Hide then fs:Hide() end end
        end
    end
    if meter and meter.SetText and meter.GetStringWidth then
        meter:SetText(s)
        local ok, w = pcall(meter.GetStringWidth, meter)
        if ok and type(w) == "number" and not isSecret(w) and w > 0 then return w end
    end
    return #s * 6
end
-- labels padded with spaces so that the texts behind them start in one column
function P.PadLabels(labels)
    local sp = width("a a") - width("aa")
    if sp <= 0 then sp = 3 end
    local wide = 0
    for _, l in ipairs(labels) do wide = math.max(wide, width(l)) end
    local out = {}
    for i, l in ipairs(labels) do
        local n = math.max(1, math.floor((wide - width(l)) / sp + 0.5) + 2)
        out[i] = l .. string.rep(" ", n)
    end
    return out
end
local function stackText(each, count)
    if count > 1 then return money(each * count) .. "  (" .. money(each) .. " each)" end
    return money(each)
end
function P.TooltipLines(id, count, shift)
    count = math.max(1, math.floor(tonumber(count) or 1))
    local a, q, at = P.Auction(id)
    local sell = P.SellPrice(id)
    local D = OMQ.Disenchant
    local deText, deMore
    if D and D.Text then deText, deMore = D.Text(id, shift) end
    if not a and not sell and not deText then return nil end
    local head = "OMQ"
    if a then
        local live = store().items[id] and store().items[id].t
        head = head .. string.format("  |cff9d9d9d(%s %s%s)|r", live and "seen" or "scanned", agoText(at),
            q and (", " .. q .. (q == 1 and " item" or " items")) or "")
    end
    local C = P.COLORS
    local rows = {}
    if sell then rows[#rows + 1] = { "Vendor:", stackText(sell, count), C.vendor } end
    if a then rows[#rows + 1] = { "Auction:", stackText(a, count), C.auction } end
    if deText then rows[#rows + 1] = { "Disenchant:", deText, C.disenchant }; if D then D.last = id end end
    local labels = {}
    for i, r in ipairs(rows) do labels[i] = r[1] end
    labels = P.PadLabels(labels)
    local lines = { { head, C.head[1], C.head[2], C.head[3] } }
    for i, r in ipairs(rows) do lines[#lines + 1] = { labels[i] .. r[2], r[3][1], r[3][2], r[3][3] } end
    for _, l in ipairs(deMore or {}) do lines[#lines + 1] = l end
    return lines
end
local function onTip(tt, data)
    if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
    local id = data and data.id
    if not id and tt.GetItem then
        local _, link = tt:GetItem()
        id = link and tonumber(tostring(link):match("item:(%d+)"))
    end
    if not id or isSecret(id) then return end
    local lines = P.TooltipLines(id, stackCount(tt, data), IsShiftKeyDown and IsShiftKeyDown() or false)
    if not lines then return end
    for _, l in ipairs(lines) do tt:AddLine(l[1], l[2], l[3], l[4]) end
    if tt.Show then tt:Show() end
end
P._onTip = onTip
-- the game's own sell price line goes away (decision 680): the Vendor line of the block shows the same, stack included.
-- Only when the block has a Vendor line for that item, so the price never disappears altogether.
function P.SkipSellLine(tt)
    if not tt or (tt.IsForbidden and tt:IsForbidden()) then return false end
    local id
    if tt.GetPrimaryTooltipData then
        local ok, d = pcall(tt.GetPrimaryTooltipData, tt)
        if ok and type(d) == "table" then id = d.id end
    end
    if not id and tt.GetItem then
        local ok, _, link = pcall(tt.GetItem, tt)
        id = ok and link and tonumber(tostring(link):match("item:(%d+)"))
    end
    if not id or isSecret(id) then return false end
    return P.SellPrice(id) ~= nil
end
OMQ:On("READY", function()
    local L = Enum and Enum.TooltipDataLineType
    if TooltipDataProcessor and TooltipDataProcessor.AddLinePreCall and L and L.SellPrice then
        TooltipDataProcessor.AddLinePreCall(L.SellPrice, function(tt)
            local ok, skip = pcall(P.SkipSellLine, tt)
            return ok and skip or nil
        end)
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            local ok, err = pcall(onTip, tt, data)
            if not ok then OMQ:Error("price tooltip", err) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local ok, err = pcall(onTip, tt, nil)
            if not ok then OMQ:Error("price tooltip", err) end
        end)
    end
end)

ev:SetScript("OnEvent", function(_, event, a1)
    local ok, err = pcall(function()
        if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then learnCommodity(a1)
        elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
            if scan and scan.state == "items" then onItems() elseif scan then onAnswer(event) else learnBrowse() end
        elseif P.THROTTLE[event] then onThrottle(event)
        elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
            if scan then log("FAILURE") end
            if scan and scan.state == "browsing" and scan.q and not scan.q.answered then scan.q.lastAt = 0 end   -- ask again at once (decision 447)
        elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
            local n = P.LearnVendor()
            if event == "MERCHANT_SHOW" and C_Timer and C_Timer.After then
                C_Timer.After(1, function()                      -- the list may be filled a moment later
                    P.LearnVendor()
                end)
            end
        elseif event == "AUCTION_HOUSE_SHOW" then
            if P.AutoOn() and C_Timer and C_Timer.After then
                C_Timer.After(P.START_DELAY, function()
                    local at = P.ScannedAt()
                    if scan then return end
                    if not at or stamp() - at > P.AUTO_AGE then P.Start(false)
                    else                                      -- fresh: the dump of a moment ago serves this window
                        sessionAt = now()
                        local H = helper()
                        if H and H.Evaluate then pcall(H.Evaluate) end
                        if H and H.Refresh then pcall(H.Refresh) end
                        if H and H.Pump then pcall(H.Pump) end
                    end
                end)
            end
        elseif event == "AUCTION_HOUSE_CLOSED" then
            sessionAt = nil
            if scan then finish(false, "the window closed") end
        end
    end)
    if not ok then OMQ:Error("prices", err) end
end)

local tick, acc = CreateFrame("Frame"), 0
tick:SetScript("OnUpdate", function(_, dt)
    if not scan then return end
    acc = acc + (dt or 0)
    if acc < (scan.state == "reading" and 0.05 or 0.5) then return end
    acc = 0
    local ok, err = pcall(P.Step)
    if not ok then OMQ:Error("prices", err) end
end)

local function ago(at)
    local d = stamp() - at
    if d < 120 then return "just now" end
    if d < 7200 then return math.floor(d / 60) .. " min ago" end
    if d < 172800 then return math.floor(d / 3600) .. " h ago" end
    return math.floor(d / 86400) .. " d ago"
end
P.Ago = ago

OMQ:RegisterCommand("prices", function(arg)
    arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "scan" then
        local ok, why = P.Start(true)
        if not ok then OMQ:Print("prices: " .. tostring(why)) end
        return
    end
    if arg == "cancel" then P.Cancel(); OMQ:Print("prices: scan stopped"); return end
    if arg == "probe" then                                   -- fix 587: measure the browse search, log in OMQDB.priceProbe
        local ok, why = false, "not loaded"
        if OMQ.PriceProbe then ok, why = OMQ.PriceProbe.Start() end
        if not ok then OMQ:Print("prices probe: " .. tostring(why)) end
        return
    end
    if arg == "log" then                                     -- decision 604: the event log of the last scan
        local L = P.last or (OMQDB and OMQDB.priceScanLast)
        local lines = L and L.log
        if not lines or #lines == 0 then OMQ:Print("prices: no scan log yet - /omq prices scan writes one"); return end
        OMQ:Print(string.format("prices: scan log, %d lines (all of it is in the saved variables after /reload), the last %d:", #lines, math.min(#lines, P.LOG_SHOWN)))
        for i = math.max(1, #lines - P.LOG_SHOWN + 1), #lines do OMQ:Print("  " .. lines[i]) end
        return
    end
    if arg == "check" then                                   -- the dump against live prices of this visit (decision 431)
        local r = P.CheckReport()
        local L = P.last or (OMQDB and OMQDB.priceScanLast)
        if L then
            OMQ:Print(string.format("prices: last scan %s, %d lines on %d pages, %d items%s",
                L.ok and "complete" or (L.partial and "partial" or "failed"), L.results or 0, L.pages or 0, L.items or 0, L.why and (" (" .. L.why .. ")") or ""))
        end
        if L and L.cats and #L.cats > 0 then                   -- lines per category (fix 549)
            local parts = {}
            for _, c in ipairs(L.cats) do
                if c.how ~= "split" then
                    parts[#parts + 1] = P.CatKey(c.c, c.s) .. ":" .. (c.n or 0) .. ((c.how ~= "ok") and ("(" .. c.how .. ")") or "")
                end
            end
            OMQ:Print("prices: lines per category " .. table.concat(parts, " "))
        end
        if r.n == 0 then OMQ:Print("prices: no live price compared with the scan yet - open the Sell or Buy tab first"); return end
        OMQ:Print(string.format("prices: %d items compared with live prices, %d more than 50%% off", r.n, r.off))
        for _, e in ipairs(r.worst) do
            OMQ:Print(string.format("  item %d: scan %s (%s on offer), live %s (%s on offer)", e.id, money(e.dp), tostring(e.dq or "?"), money(e.lp), tostring(e.lq or "?")))
        end
        return
    end
    local id = tonumber(arg)
    if id then
        local a, q, at = P.Auction(id)
        local v = P.Vendor(id)
        OMQ:Print(string.format("prices: item %d - auction %s%s, vendor %s", id, a and (OMQ.AuctionHelper and OMQ.AuctionHelper.Money(a) or a) or "none",
            q and q > 0 and (" (" .. q .. " on offer)") or "", v and (OMQ.AuctionHelper and OMQ.AuctionHelper.Money(v) or v) or "unknown"))
        return
    end
    local at = P.ScannedAt()
    local nv = 0
    for _ in pairs(vendorStore()) do nv = nv + 1 end
    local line = string.format("prices: %d auction items %s, %d vendor prices learned", P.Count(), at and ("scanned " .. ago(at)) or "- not scanned yet", nv)
    if scan then line = line .. string.format("; scan running: %d lines on %d pages", scan.results, scan.pages or 0) end
    if P.last then line = line .. string.format("; last scan %s: %d lines, %d items, %.0f s%s", P.last.ok and "complete" or (P.last.partial and "partial" or "failed"), P.last.results, P.last.items, P.last.secs, P.last.why and (" (" .. P.last.why .. ")") or "") end
    OMQ:Print(line .. ".  /omq prices scan | cancel | check | log | probe | <item id>")
end, "auction prices: /omq prices | scan | cancel | check | log | probe | <item id>")
