-- One More Quest: auction house prices of everything (decision 341, step 1 of the crafting profit)
-- The whole auction house is read once with an unfiltered browse, page after page, and the lowest price of every
-- item is kept in the saved variables (per realm). Nothing is thrown away until the next full scan replaces it.
-- The crafting profit (UI/CraftProfit.lua) reads these prices. The scan starts by itself when the auction
-- house opens and the last one is older than an hour (option), or with
-- /omq prices scan. It gives way to the auction helper: it never starts while the helper asks for something,
-- and it waits while a post or a purchase is going on.
-- Vendor prices are learned too: every merchant window written down what an item costs there, so reagents
-- from a vendor (thread, vials) count in the profit with their vendor price.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.Prices = P

P.MAX_AGE = 3600            -- an automatic scan only when the last one is older (seconds)
P.PAGE_TIMEOUT = 8          -- no new page for so long: the scan ends with what it has
P.START_DELAY = 3           -- seconds after the window opens before an automatic scan starts

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
local function vendorStore()
    OMQDB.vendorPrices = OMQDB.vendorPrices or {}
    return OMQDB.vendorPrices
end

function P.AutoOn() return not (OMQ.db and OMQ.db.options and OMQ.db.options.priceScan == false) end

-- the lowest auction price of one piece (copper), its quantity on offer, and the time of the scan
function P.Auction(itemID)
    local e = store().items[itemID]
    if e then return e.p, e.q, store().at end
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
-- The scan
----------------------------------------------------------------------
local scan = nil           -- { read, seen, results, pages, lastAt, startedAt }
function P.Busy() return scan ~= nil end
function P.Progress() return scan and { results = scan.results, pages = scan.pages } or nil end
P.last = nil               -- how the last scan ended: { ok, items, pages, secs }

local function helper() return OMQ.AuctionHelper end
local function A() return C_AuctionHouse end

local function finish(ok)
    if not scan then return end
    local st = store()
    local n = 0
    for _ in pairs(scan.seen) do n = n + 1 end
    if ok then
        for id in pairs(st.items) do if not scan.seen[id] then st.items[id] = nil end end   -- sold out since the last scan
        st.at, st.n = stamp(), n
    end
    P.last = { ok = ok, items = n, pages = scan.pages, secs = now() - scan.startedAt, results = scan.results }
    scan = nil
    local H = helper()
    if H and H.Refresh then pcall(H.Refresh) end
    if H and H.Pump then pcall(H.Pump) end
    if OMQ.Fire then OMQ:Fire("PRICES_UPDATED", ok) end
end

-- read what the game has handed out so far (the list grows page by page; a shorter list starts again)
local function consume()
    local api = A()
    local got = api and api.GetBrowseResults and api.GetBrowseResults() or {}
    if #got < scan.read then scan.read = 0 end
    local st = store()
    for i = scan.read + 1, #got do
        local r = got[i]
        local key = r and r.itemKey
        local id = key and key.itemID
        local price = r and r.minPrice
        if id and not isSecret(id) and type(price) == "number" and not isSecret(price) and price > 0 then
            local qty = type(r.totalQuantity) == "number" and not isSecret(r.totalQuantity) and r.totalQuantity or 0
            local e = st.items[id]
            if scan.seen[id] then
                if price < e.p then e.p = price end
                e.q = e.q + qty
            else
                scan.seen[id] = true
                st.items[id] = { p = price, q = qty }
            end
        end
        scan.results = scan.results + 1
    end
    if #got > scan.read then scan.lastAt = now() end
    scan.read = #got
end

local function throttleReady()
    local api = A()
    return not (api and api.IsThrottledMessageSystemReady) or api.IsThrottledMessageSystemReady()
end

local function yielding()
    local H = helper()
    if not H then return false end
    if H.Busy and H.Busy() then return true end
    if H.quietUntil and now() < H.quietUntil then return true end
    return false
end

-- the next step: send the first query, ask for the next page, or end
function P.Step()
    if not scan then return end
    local api = A()
    local H = helper()
    if not (api and H and H.open) then finish(false); return end
    if scan.state == "start" then
        if yielding() or not throttleReady() then return end
        local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
        scan.state, scan.lastAt = "asked", now()
        api.SendBrowseQuery({ searchString = "", sorts = { { sortOrder = order, reverseSort = false } } })
        return
    end
    consume()
    if api.HasFullBrowseResults and api.HasFullBrowseResults() and scan.results > 0 then finish(true); return end
    if now() - scan.lastAt > P.PAGE_TIMEOUT then
        -- nothing new for a while: an empty auction house is a result too, otherwise the scan ends partial
        finish(scan.results == 0 and api.HasFullBrowseResults and api.HasFullBrowseResults() or false)
        return
    end
    if scan.state == "wait" and now() - scan.askedAt > 1.5 and not yielding() and throttleReady() then
        scan.state = "asked"
    end
    if scan.state == "asked" and not yielding() and throttleReady() and api.RequestMoreBrowseResults then
        scan.state, scan.askedAt, scan.pages = "wait", now(), scan.pages + 1
        api.RequestMoreBrowseResults()
    end
end

function P.Start(manual)
    if scan then return false, "a scan is running" end
    local H = helper()
    if not (H and H.open) then return false, "open the auction house first" end
    local api = A()
    if not (api and api.SendBrowseQuery) then return false, "this client has no browse query" end
    if H.Scanning and H.Scanning() then return false, "the auction helper is still scanning" end
    scan = { state = "start", read = 0, seen = {}, results = 0, pages = 0, startedAt = now(), lastAt = now(), askedAt = now() }
    if manual then OMQ:Print("prices: reading the whole auction house - this takes a while") end
    if H.Refresh then pcall(H.Refresh) end
    P.Step()
    return true
end

function P.Cancel() if scan then finish(false) end end

----------------------------------------------------------------------
-- Events and commands
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
                     "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "MERCHANT_SHOW" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- what a merchant sells and for how much one piece (decision 341)
function P.LearnVendor()
    if not (GetMerchantNumItems and GetMerchantItemLink and GetMerchantItemInfo) then return 0 end
    local n, vs = 0, vendorStore()
    for i = 1, GetMerchantNumItems() or 0 do
        local link = GetMerchantItemLink(i)
        local id = link and tonumber(tostring(link):match("item:(%d+)"))
        local _, _, price, qty, _, _, extended = GetMerchantItemInfo(i)
        if id and type(price) == "number" and not isSecret(price) and price > 0 and not extended then
            vs[id] = math.floor(price / math.max(1, tonumber(qty) or 1))
            n = n + 1
        end
    end
    return n
end

ev:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
        if event == "MERCHANT_SHOW" then P.LearnVendor()
        elseif event == "AUCTION_HOUSE_SHOW" then
            if P.AutoOn() and C_Timer and C_Timer.After then
                C_Timer.After(P.START_DELAY, function()
                    local at = P.ScannedAt()
                    if not scan and (not at or stamp() - at > P.MAX_AGE) then P.Start(false) end
                end)
            end
        elseif event == "AUCTION_HOUSE_CLOSED" then
            if scan then finish(false) end
        elseif scan then
            scan.state = scan.state == "asked" and "asked" or scan.state
            consume()
            if scan.state == "wait" then scan.state = "asked" end
            P.Step()
        end
    end)
    if not ok then OMQ:Error("prices", err) end
end)

local tick, acc = CreateFrame("Frame"), 0
tick:SetScript("OnUpdate", function(_, dt)
    if not scan then return end
    acc = acc + (dt or 0)
    if acc < 0.5 then return end
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
    if scan then line = line .. string.format("; scan running: %d results, %d pages", scan.results, scan.pages) end
    if P.last then line = line .. string.format("; last scan %s: %d items, %d pages, %.0f s", P.last.ok and "complete" or "partial", P.last.items, P.last.pages, P.last.secs) end
    OMQ:Print(line .. ".  /omq prices scan | cancel | <item id>")
end, "auction prices: /omq prices | scan | cancel | <item id>")
