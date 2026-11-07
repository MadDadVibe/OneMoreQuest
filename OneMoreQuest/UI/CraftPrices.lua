-- One More Quest: auction house prices of everything (decision 341, step 1 of the crafting profit)
-- The whole auction house is read once with an empty browse search, page by page (decision 432; the
-- ReplicateItems dump of decision 342 gave a frozen old list on Forever), and the
-- lowest price of every item is kept in the saved variables (per realm) until the next scan replaces it.
-- The crafting profit (UI/CraftProfit.lua) reads these prices. The scan starts by itself when the auction
-- house opens and the last one is older than 4 hours (option, decision 428), or with
-- /omq prices scan. It gives way to the auction helper: it never starts while the helper asks for something,
-- and it waits while a post or a purchase is going on. While it runs, the helper's panel and the game's auction
-- house window are covered (decision 431); the dad's own window no longer pauses it.
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
local function vendorStore()
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
local scan = nil           -- { state "start" | "browsing", items, seen, results, startedAt, more, lastAt, pages }
function P.Busy() return scan ~= nil end
-- the scan is good for this window: a scan finished, or the last one is fresh (decision 343)
local sessionAt = nil
function P.Session() return sessionAt ~= nil and not scan end
function P.SessionAt() return sessionAt end
function P.EndSession() sessionAt = nil end
function P.Items() return store().items end
function P.Progress() return scan and { results = scan.results, total = scan.results, state = scan.state, pages = scan.pages } or nil end
P.last = nil               -- how the last scan ended: { ok, items, secs, results, pages, why, partial }
P.WAIT = 30                -- seconds to wait for the next answer of the auction house
P.PAGES = 200              -- at most this many pages of the list, so a scan always ends

local function helper() return OMQ.AuctionHelper end
local function A() return C_AuctionHouse end

-- ok: the whole list came; partial: only a part came, its prices are kept but nothing is removed (decision 432)
local function finish(ok, why, partial)
    if not scan then return end
    local st = store()
    local n = 0
    for _ in pairs(scan.seen) do n = n + 1 end
    if ok then
        -- the scan replaces the list: what was sold is gone; a live price of the last minutes stays (decision 427)
        for id, e in pairs(st.items) do
            if e.t and stamp() - e.t <= P.MAX_AGE then
                if not scan.items[id] then n = n + 1 end
                scan.items[id] = e
            end
        end
        st.items = scan.items
        st.at, st.n = stamp(), n
        st.check = {}
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
               partial = partial and true or nil }
    if OMQDB then OMQDB.priceScanLast = P.last end
    scan = nil
    local H = helper()
    if (ok or partial) and H and H.Evaluate then pcall(H.Evaluate) end
    if H and H.Refresh then pcall(H.Refresh) end
    if H and H.Pump then pcall(H.Pump) end
    if OMQ.Fire then OMQ:Fire("PRICES_UPDATED", ok) end
end

-- the browse list of the whole auction house (decision 432): one line per item with the lowest price of one
-- piece and the pieces on offer, the same list the game's own window shows. Gear of one item with different
-- item levels comes as several lines: the cheapest counts, the pieces add up.
local function readList()
    local api = A()
    local ok, list = pcall(api.GetBrowseResults)
    if not ok or type(list) ~= "table" then return 0 end
    scan.items, scan.seen = {}, {}
    for _, res in ipairs(list) do
        local k = res.itemKey
        local id, price, qty = k and k.itemID, res.minPrice, res.totalQuantity
        if id and not isSecret(id) and not isSecret(price) and type(price) == "number" and price > 0 then
            qty = (not isSecret(qty) and tonumber(qty)) or 0
            local e = scan.items[id]
            if e then
                if price < e.p then e.p = math.floor(price) end
                e.q = e.q + qty
            else
                scan.items[id] = { p = math.floor(price), q = qty }
                scan.seen[id] = true
            end
        end
    end
    scan.results = #list
    return #list
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

local function yielding()
    local H = helper()
    if not H then return false end
    if H.Busy and H.Busy() then return true end
    if H.quietUntil and now() < H.quietUntil then return true end
    -- the dad's own window no longer holds the scan back: it is covered while the scan runs (decision 431)
    return false
end

-- an own call of the addon: the helper does not count it as the dad's window (decision 427)
local function own(fn, ...)
    local H = helper()
    if H and H.Own then return H.Own(fn, ...) end
    return fn(...)
end

P.QUERY = function()
    local sort = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    return { searchString = "", sorts = { { sortOrder = sort, reverseSort = false } }, itemClassFilters = {} }
end

-- an answer of the auction house came (first page or more): ask for the next page or end
local function onAnswer()
    if not scan or scan.state ~= "browsing" then return end
    scan.lastAt = now()
    local n = readList()
    if n == 0 then return end                              -- an empty first answer: the list comes a moment later (decision 326)
    if full() then finish(true)
    elseif scan.pages >= P.PAGES then finish(false, "the list did not end after " .. scan.pages .. " pages", true)
    else scan.more = true; P.Step() end
end
P._onAnswer = onAnswer

-- the next step: send the request, ask for the next page, or give up when the answers stop
function P.Step()
    if not scan then return end
    local api = A()
    local H = helper()
    if not (api and H and H.open) then finish(false, "the window closed"); return end
    if scan.state == "start" then
        if yielding() or not throttleReady() then return end
        scan.state, scan.lastAt, scan.pages = "browsing", now(), 1
        local ok, err = pcall(own, api.SendBrowseQuery, P.QUERY())
        if not ok then finish(false, "SendBrowseQuery failed: " .. tostring(err)) end
    elseif scan.state == "browsing" then
        if scan.more then
            if not throttleReady() then return end
            scan.more, scan.lastAt, scan.pages = false, now(), scan.pages + 1
            local ok, err = pcall(own, api.RequestMoreBrowseResults)
            if not ok then finish(false, "RequestMoreBrowseResults failed: " .. tostring(err), true) end
        elseif now() - scan.lastAt > P.WAIT then
            if readList() == 0 then finish(false, "the auction house sent no list")
            elseif full() then finish(true)
            else finish(false, "the auction house stopped answering after " .. scan.results .. " items", true) end
        end
    end
end

function P.Start(manual)
    if scan then return false, "a scan is running" end
    local H = helper()
    if not (H and H.open) then return false, "open the auction house first" end
    local api = A()
    if not (api and api.SendBrowseQuery and api.GetBrowseResults) then
        return false, "this client has no browse list"
    end
    scan = { state = "start", items = {}, seen = {}, results = 0, pages = 0, startedAt = now() }
    if manual then OMQ:Print("prices: asking the auction house for its whole list - the game answers in a moment") end
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
                     "COMMODITY_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- what a merchant sells and for how much one piece (decisions 341, 345). The client may have the old globals or
-- C_MerchantFrame; both are tried, and the result is told once per merchant window.
local function merchantItem(i)
    local link, price, qty, extended
    local M = C_MerchantFrame
    if M and M.GetItemInfo then
        local ok, t = pcall(M.GetItemInfo, i)
        if ok and type(t) == "table" then price, qty, extended = t.price, t.stackCount, t.hasExtendedCost end
    end
    if price == nil and GetMerchantItemInfo then
        local ok, _, _, p, q, _, _, x = pcall(GetMerchantItemInfo, i)
        if ok then price, qty, extended = p, q, x end
    end
    if GetMerchantItemLink then link = GetMerchantItemLink(i)
    elseif M and M.GetItemLink then link = M.GetItemLink(i) end
    return link, price, qty, extended
end
function P.LearnVendor()
    local num = GetMerchantNumItems and GetMerchantNumItems() or (C_MerchantFrame and C_MerchantFrame.GetNumItems and C_MerchantFrame.GetNumItems()) or 0
    local n, vs = 0, vendorStore()
    for i = 1, num do
        local link, price, qty, extended = merchantItem(i)
        local id = link and tonumber(tostring(link):match("item:(%d+)"))
        if id and type(price) == "number" and not isSecret(price) and price > 0 and not extended then
            vs[id] = math.floor(price / math.max(1, tonumber(qty) or 1))
            n = n + 1
        end
    end
    P.lastMerchant = { items = num, learned = n }
    return n
end

-- the latest scanned price in every item tooltip (decision 345): the cheaper of auction house and vendor
local function agoText(at)
    if not at then return "" end
    local d = (time and time() or 0) - at
    if d < 120 then return "just now" end
    if d < 7200 then return math.floor(d / 60) .. " min ago" end
    if d < 172800 then return math.floor(d / 3600) .. " h ago" end
    return math.floor(d / 86400) .. " days ago"
end
local function money(c)
    local C = OMQ.CraftProfit
    if C and C.Money then return C.Money(c) end
    return c .. "c"
end
-- how many pieces the hovered item is (decision 430): the item GUID of the tooltip data, else the bag slot of the
-- tooltip's owner. Anything unreadable or secret counts as one piece.
local function stackCount(tt, data)
    local n
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
-- the price of the whole stack like the game's own vendor line, one piece behind it (decision 430)
function P.TooltipLines(id, count)
    local a, q, at = P.Auction(id)
    local v = P.Vendor(id)
    if not a and not v then return nil end
    count = math.max(1, math.floor(tonumber(count) or 1))
    local best, src = P.Cost(id)
    local tag = src == "vendor" and "  (vendor)" or "  (auction house)"
    local first = count > 1 and ("Price: " .. money(best * count) .. "  (" .. money(best) .. " each)" .. tag)
        or ("Price: " .. money(best) .. tag)
    local lines = { { first, 0.85, 0.75, 0.4 } }
    if a and v then
        lines[#lines + 1] = { string.format("Auction house %s - vendor %s%s", money(a), money(v), count > 1 and " each" or ""), 0.6, 0.6, 0.6 }
    end
    if a then
        local live = store().items[id] and store().items[id].t
        lines[#lines + 1] = { string.format("%s %s%s", live and "seen" or "scanned", agoText(at), q and (", " .. q .. " on offer") or ""), 0.5, 0.5, 0.5 }
    end
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
    local lines = P.TooltipLines(id, stackCount(tt, data))
    if not lines then return end
    for _, l in ipairs(lines) do tt:AddLine(l[1], l[2], l[3], l[4]) end
    if tt.Show then tt:Show() end
end
P._onTip = onTip
OMQ:On("READY", function()
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
            if scan then onAnswer() else learnBrowse() end
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
    if arg == "check" then                                   -- the dump against live prices of this visit (decision 431)
        local r = P.CheckReport()
        local L = P.last or (OMQDB and OMQDB.priceScanLast)
        if L then
            OMQ:Print(string.format("prices: last scan %s, %d lines on %d pages, %d items%s",
                L.ok and "complete" or (L.partial and "partial" or "failed"), L.results or 0, L.pages or 0, L.items or 0, L.why and (" (" .. L.why .. ")") or ""))
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
    OMQ:Print(line .. ".  /omq prices scan | cancel | check | <item id>")
end, "auction prices: /omq prices | scan | cancel | check | <item id>")
