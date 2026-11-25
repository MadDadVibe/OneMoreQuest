-- One More Quest - disenchant bargains in the auction house (decision 710)
-- /omq ah de opens a window next to the auction helper and searches the auction house for green and blue armor and
-- weapons offered at least MIN_GAIN (10 silver) under their disenchant value (OMQ.Disenchant.Value: the classic
-- disenchant tables times the scanned prices of the materials). The list shows the biggest gain first.
-- Left click on a row buys it: the first click searches that auction again (a purchase needs the auction of the
-- game's latest search, decision 431), the second click buys it. Right click: discarded - the item comes back only
-- when it is offered cheaper, or after SKIP_TIME. "Buy all" buys the first row of the list, one purchase per click
-- (the game takes a purchase only from a click); after each purchase the next row is searched at once, so the next
-- click buys again. The search is two browse searches (weapons, armor) in the form of the game's own window with
-- the quality filters green and blue (decision 604), every page; a class whose list stops at a full page is searched
-- again per subcategory. While it runs the auction helper and the price scan send nothing.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local DB = {}
OMQ.DEBargain = DB

DB.MIN_GAIN = 1000        -- copper: at least 10 silver under the disenchant value
DB.CLASSES = { 2, 4 }     -- weapons, armor
DB.PAGE = 500             -- a list that stops at a whole number of these lines may be cut off
DB.PAGES = 100            -- at most this many pages of one search
DB.FIRST_WAIT = 2         -- seconds before the first search: an answer of the helper still on its way passes
DB.GAP = 2                -- seconds between two searches (the pace of the price scan, decision 604)
DB.QUIET = 15             -- a search without any answer for this long is sent again (TRIES in all) or given up
DB.TRIES = 3
DB.SKIP_TIME = 86400      -- a discarded item stays away this long (or until it is offered cheaper)
DB.ROWS = 10
DB.ROW_H = 36

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
    OMQDB.deBargain = OMQDB.deBargain or {}
    local d = OMQDB.deBargain
    d.skip = d.skip or {}
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

local run = nil           -- the search running now
local lines = {}          -- what the searches found: per item key { key, id, price, qty }
local rows = {}           -- the rows of the list, kept per item key (their search and purchase state)
local list = {}           -- the bargains shown, the biggest gain first
local frame
DB.bought = { n = 0, spent = 0, worth = 0 }

----------------------------------------------------------------------
-- The searches
----------------------------------------------------------------------
-- the quality filters green and blue, the way the game's window has them
function DB.Qualities()
    local F = Enum and Enum.AuctionHouseFilter
    local out = {}
    if not F then return out end
    for _, k in ipairs({ "UncommonQuality", "RareQuality" }) do
        if F[k] ~= nil then out[#out + 1] = F[k] end
    end
    return out
end
function DB.Query(c, s)
    local E = Enum and Enum.AuctionHouseSortOrder
    local sorts = { { sortOrder = E and E.Price or 0, reverseSort = false } }
    local q = OMQ.Prices.GameQuery(c, s, 0, 0, sorts)
    q.filters = DB.Qualities()
    return q
end

function DB.Running() return run ~= nil end
DB._run = function() return run end

local function status(text)
    DB.statusText = text
    if frame and frame:IsShown() then DB.Paint() end
end

local function send()
    local q = run.q
    q.lastAt, q.resp, q.dropped, q.answered = now(), nil, nil, nil
    run.state = "waiting"
    local api = A()
    local ok, err = pcall(own, api.SendBrowseQuery, DB.Query(q.c, q.s))
    if not ok then DB.Finish("the search failed: " .. tostring(err)) end
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
local function full()
    local api = A()
    if not api.HasFullBrowseResults then return true end
    local ok, f = pcall(api.HasFullBrowseResults)
    return ok and f and true or false
end

local function searchDone(l, how)
    local q = run.q
    local capped = l and #l > 0 and #l % DB.PAGE == 0
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
                if not e or price < e.price then
                    lines[ks] = { key = k, id = k.itemID, price = math.floor(price), qty = (not isSecret(qty) and tonumber(qty)) or 1 }
                end
            end
        end
        run.lines = run.lines + #(l or {})
    end
    run.log[#run.log + 1] = string.format("%d%s: %s, %d lines, %d pages", q.c, q.s and ("." .. q.s) or "", how, #(l or {}), q.pages or 0)
    run.q, run.state, run.gapAt = nil, "gap", now()
    if run.qi >= #run.queue then DB.Finish(); return end     -- the last search: the list is complete
    DB.Build()
    status(string.format("searching... %d of %d searches, %d bargains so far", run.qi, #run.queue, #list))
end

local function nextSearch()
    run.qi = run.qi + 1
    local f = run.queue[run.qi]
    if not f then DB.Finish(); return end
    run.q = { c = f.c, s = f.s, pages = 1, tries = 1 }
    send()
end

function DB.Step()
    if not run then return end
    local h = H()
    if not (h and h.open) then DB.Finish("the auction house closed"); return end
    h.quietUntil = now() + 60                          -- the helper holds still while the search runs
    local P = OMQ.Prices
    if run.state == "start" or run.state == "gap" then
        if P and P.Busy and P.Busy() then status("waiting for the price scan to end..."); return end
        if now() - (run.state == "start" and run.t0 or run.gapAt) < (run.state == "start" and DB.FIRST_WAIT or DB.GAP) then return end
        if not ready() then return end
        nextSearch()
        return
    end
    local q = run.q
    if not q then return end
    if q.dropped then
        if not ready() then return end
        q.dropped = nil
        if q.answered then q.more, q.pages = true, q.pages - 1
        elseif q.tries >= DB.TRIES then searchDone(nil, "no answer"); return
        else q.tries = q.tries + 1; send(); return end
    end
    if q.more then
        if not ready() then return end
        q.more, q.lastAt, q.pages = false, now(), q.pages + 1
        local ok, err = pcall(own, A().RequestMoreBrowseResults)
        if not ok then searchDone(nil, "page failed: " .. tostring(err)) end
        return
    end
    if now() - q.lastAt > DB.QUIET then
        if q.answered then
            local l = readList()
            searchDone(l, "stopped")
        elseif q.tries >= DB.TRIES then searchDone(nil, "no answer")
        elseif ready() then q.tries = q.tries + 1; send() end
    end
end

function DB.OnBrowse()
    if not run or run.state ~= "waiting" or not run.q then return end
    local q = run.q
    local l, mine = readList()
    if not mine then return end                        -- the answer to another search
    if #l == 0 then
        if q.resp and full() then searchDone(l, "empty") end
        return
    end
    q.answered, q.lastAt = true, now()
    if full() then searchDone(l, "complete")
    elseif q.pages >= DB.PAGES then searchDone(l, "page limit")
    elseif A().RequestMoreBrowseResults then q.more = true; DB.Step()
    else searchDone(l, "one page") end
end

function DB.Start()
    if run then return false, "already searching" end
    local h = H()
    if not (h and h.open) then return false, "open the auction house first (with the auction helper on)" end
    local api = A()
    if not (api and api.SendBrowseQuery and api.GetBrowseResults) then return false, "this client has no browse list" end
    if not (OMQ.Disenchant and OMQ.Disenchant.Value) then return false, "no disenchant values" end
    if OMQ.AHTest and OMQ.AHTest.Running and OMQ.AHTest.Running() then return false, "the test window is searching" end
    local queue = {}
    for _, c in ipairs(DB.CLASSES) do queue[#queue + 1] = { c = c } end
    for k in pairs(lines) do lines[k] = nil end
    for k in pairs(rows) do rows[k] = nil end              -- a new search: every offer is new
    run = { state = "start", t0 = now(), queue = queue, qi = 0, lines = 0, log = {} }
    DB.Build()
    status("searching the auction house for green and blue gear...")
    return true
end

function DB.Finish(why)
    if not run then return end
    local r = run
    run = nil
    local h = H()
    if h then h.quietUntil = nil end
    DB.last = { why = why, lines = r.lines, secs = now() - r.t0, log = r.log }
    DB.Build()
    if why then status("search stopped: " .. why)
    else status(string.format("%d bargains among %d offers (%.0f s)", #list, r.lines, now() - r.t0)) end
    if not why then DB.Prepare() end
    if h and h.Pump then pcall(h.Pump) end
end
function DB.Cancel() if run then DB.Finish("cancelled") end end

----------------------------------------------------------------------
-- What is a bargain
----------------------------------------------------------------------
local function quality(e)
    local api = A()
    if api and api.GetItemKeyInfo then
        local ok, ki = pcall(api.GetItemKeyInfo, e.key)
        if ok and type(ki) == "table" and type(ki.quality) == "number" and not isSecret(ki.quality) then
            if type(ki.itemName) == "string" and not isSecret(ki.itemName) then e.name = ki.itemName end
            e.icon = ki.iconFileID or e.icon
            return ki.quality
        end
    end
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, name, _, q, _, _, _, _, _, _, icon = pcall(f, e.id)
    if not ok or q == nil or isSecret(q) then return nil end
    if type(name) == "string" and not isSecret(name) then e.name = e.name or name end
    e.icon = e.icon or icon
    return q
end
-- the disenchant value and the gain of one line; nil when it is no bargain, "wait" while the game loads the item
function DB.Judge(e)
    local q = quality(e)
    if q == nil then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e.id) end
        return "wait"
    end
    if q ~= 2 and q ~= 3 then return nil end
    local v, _, missing, priced = OMQ.Disenchant.Value(e.id)
    if not v or (priced or 0) == 0 then return nil end
    local gain = v - e.price
    if gain < DB.MIN_GAIN then return nil end
    return v, gain, missing, q
end

local function skipped(ks, price)
    local s = db().skip[ks]
    if not s then return false end
    if stamp() - (s.t or 0) > DB.SKIP_TIME or price < (s.p or 0) then db().skip[ks] = nil; return false end
    return true
end

function DB.Build()
    for i = #list, 1, -1 do list[i] = nil end
    local waiting = 0
    for ks, e in pairs(lines) do
        local v, gain, missing, q = DB.Judge(e)
        if v == "wait" then waiting = waiting + 1
        elseif v and not skipped(ks, e.price) then
            local r = rows[ks]
            if not r then
                r = { ks = ks, itemKey = e.key, itemID = e.id, commodity = false, onCheck = DB.OnCheck, onDone = DB.OnDone }
                rows[ks] = r
            end
            if not (r.bought or r.gone) then
                r.price, r.value, r.gain, r.missing, r.quality = e.price, v, gain, missing, q
                r.name, r.icon = e.name, e.icon
                list[#list + 1] = r
            end
        end
    end
    table.sort(list, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.ks < b.ks
    end)
    DB.waiting = waiting
    if frame and frame:IsShown() then DB.Paint() end
end
function DB.List() return list end

----------------------------------------------------------------------
-- Buying (from a click)
----------------------------------------------------------------------
-- the answer of the search of one auction: the offers still under the value by MIN_GAIN, the cheapest first
function DB.OnCheck(r, offers)
    local good = {}
    for _, o in ipairs(offers or {}) do
        if o.auctionID and o.buyout and (o.qty or 1) == 1 and (r.value or 0) - o.buyout >= DB.MIN_GAIN then good[#good + 1] = o end
    end
    r.offers = good
    if #good == 0 then
        r.gone = true
        local cheapest = offers and offers[1] and offers[1].buyout
        OMQ:Print("disenchant bargains: " .. (r.name or ("item " .. r.itemID)) ..
            (cheapest and (" is no bargain any more (now " .. money(cheapest) .. ")") or " is gone"))
        DB.Build()
        if C_Timer and C_Timer.After then C_Timer.After(0, DB.Prepare) else DB.Prepare() end
    else
        r.price, r.gain = good[1].buyout, (r.value or 0) - good[1].buyout
        r.link = good[1].link or r.link
    end
    if frame and frame:IsShown() then DB.Paint() end
end
function DB.OnDone(r, ok)
    if ok then
        r.bought = true
        DB.bought.n = DB.bought.n + 1
        DB.bought.spent = DB.bought.spent + (r.paid or r.price or 0)
        DB.bought.worth = DB.bought.worth + (r.value or 0)
    else
        r.fresh = nil
    end
    DB.Build()
    DB.Prepare()
end

-- the next row "Buy all" buys: its auction is searched at once, so the next click buys
function DB.Next() return list[1] end
function DB.Prepare()
    if run then return end
    local r = list[1]
    local b = B()
    if not (r and b and b.StartCheck) or b.check or (b.Busy and b.Busy()) then return end
    if b.Fresh(r) and r.offers and #r.offers > 0 then return end
    b.StartCheck(r, "de")
end

function DB.Buy(r)
    local b, h = B(), H()
    if not (type(r) == "table" and h.open) then return false end
    if run then OMQ:Print("disenchant bargains: still searching - one moment"); return false end
    if r.bought or r.gone or b.Busy() then return false end
    if b.Fresh(r) and r.offers and #r.offers > 0 then
        r.fresh = nil
        r.paid = r.offers[1].buyout
        return b.Buy(r, 1)
    end
    if b.check then return false end                    -- another auction is searched right now
    return b.StartCheck(r, "de")
end
function DB.BuyNext() return DB.Buy(list[1]) end

function DB.Discard(r)
    if type(r) ~= "table" then return end
    db().skip[r.ks] = { p = r.price, t = stamp() }
    local b = B()
    if b and b.check and b.check.row == r then b.check = nil end
    DB.Build()
    if list[1] ~= r then DB.Prepare() end
end
function DB.ResetSkip()
    local n = 0
    for k in pairs(db().skip) do db().skip[k] = nil; n = n + 1 end
    DB.Build()
    return n
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
DB.offset = 0
local rowFrames = {}
DB._rowFrames = function() return rowFrames end

local function qColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if c then return c.r, c.g, c.b end
    if q == 3 then return 0, 0.44, 0.87 end
    return 0.12, 1, 0
end

local function rowState(r)
    local b = B()
    if b and b.check and b.check.row == r then return "searching the auction..." end
    if b and b.Fresh and b.Fresh(r) and r.offers and #r.offers > 0 then return "ready - click to buy" end
    return nil
end

local function makeRow(i)
    local r = B()._makeRow(frame.list, DB.ROW_H)           -- the row of the Buy tab (icon, name, two lines right)
    r:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, -(i - 1) * (DB.ROW_H + 2))
    r:SetScript("OnClick", function(self, mouse)
        local ok, err = pcall(function()
            if mouse == "RightButton" then DB.Discard(self.omq) else DB.Buy(self.omq) end
            DB.Paint()
        end)
        if not ok then OMQ:Error("disenchant bargains", err) end
    end)
    r:SetScript("OnEnter", function(self)
        local x = self.omq
        if type(x) ~= "table" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if x.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(x.link)
        elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(x.itemID) end
        GameTooltip:AddLine("Left click: buy (the first click looks for the auction, the next one buys)", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right click: discard (back when it is offered cheaper)", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    rowFrames[i] = r
    return r
end

local function build()
    local ok, f = pcall(CreateFrame, "Frame", "OneMoreQuestDEBargain", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then return end
    frame = f
    f:SetSize(380, 120 + DB.ROWS * (DB.ROW_H + 2))
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText("One More Quest - disenchant bargains")
    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 14, -32)
    status:SetWidth(352)
    status:SetJustifyH("LEFT")
    f.status = status
    local again = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    again:SetSize(110, 22)
    again:SetPoint("TOPLEFT", 12, -50)
    again:SetText("Search again")
    again:SetScript("OnClick", function()
        if run then DB.Cancel() else
            local started, why = DB.Start()
            if not started then OMQ:Print("disenchant bargains: " .. tostring(why)) end
        end
        DB.Paint()
    end)
    f.again = again
    local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    all:SetSize(236, 22)
    all:SetPoint("LEFT", again, "RIGHT", 6, 0)
    all:SetScript("OnClick", function()
        local ok2, err = pcall(function() DB.BuyNext(); DB.Paint() end)
        if not ok2 then OMQ:Error("disenchant bargains", err) end
    end)
    f.all = all
    local listFrame = CreateFrame("Frame", nil, f)
    listFrame:SetPoint("TOPLEFT", 14, -80)
    listFrame:SetSize(348, DB.ROWS * (DB.ROW_H + 2))
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, d)
        DB.offset = math.max(0, math.min(math.max(0, #list - DB.ROWS), DB.offset - d))
        DB.Paint()
    end)
    f.list = listFrame
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 12)
    hint:SetWidth(352)
    hint:SetJustifyH("LEFT")
    hint:SetText("Left click: buy   Right click: discard   Mouse wheel: scroll")
    f.hint = hint
    f:SetScript("OnHide", function() if run then DB.Cancel() end end)
    if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestDEBargain") end
end

local function anchor()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", _G.OneMoreQuestAuctionHelper or UIParent, "TOPRIGHT", 6, 0)   -- right of the auction helper
end

function DB.Paint()
    if not frame or not frame:IsShown() then return end
    local text = DB.statusText or ""
    if DB.bought.n > 0 then
        text = text .. string.format("\nbought: %d for %s, disenchant value %s", DB.bought.n, money(DB.bought.spent), money(DB.bought.worth))
    end
    frame.status:SetText(text)
    frame.again:SetText(run and "Cancel" or "Search again")
    local total = 0
    for _, r in ipairs(list) do total = total + (r.price or 0) end
    local nx = list[1]
    if run then frame.all:SetText("Buy all (after the search)")
    elseif not nx then frame.all:SetText("Buy all: nothing to buy")
    else
        local st = rowState(nx)
        frame.all:SetText(string.format("Buy all: %d for %s%s", #list, money(total),
            st == "ready - click to buy" and "" or (st and " (searching)" or "")))
    end
    if frame.all.SetEnabled then frame.all:SetEnabled(not run and nx ~= nil) end
    DB.offset = math.max(0, math.min(DB.offset, math.max(0, #list - DB.ROWS)))
    for i = 1, DB.ROWS do
        local r = rowFrames[i] or makeRow(i)
        local x = list[DB.offset + i]
        r.omq = x
        if x then
            r.name:SetText(x.name or ("item " .. x.itemID))
            r.name:SetTextColor(qColor(x.quality))
            local st = rowState(x)
            r.sub:SetText(st or string.format("disenchant ~%s%s", money(x.value or 0), x.missing and " (prices incomplete)" or ""))
            r.top:SetText(money(x.price or 0))
            r.bottom:SetText("+" .. money(x.gain or 0))
            r.icon:SetTexture(x.icon)
            if st == "ready - click to buy" then r.bg:SetColorTexture(0.1, 0.3, 0.12, 1) else r.bg:SetColorTexture(0.11, 0.122, 0.153, 1) end
            r:Show()
        else
            r:Hide()
        end
    end
end

function DB.Show()
    if not frame then build() end
    if not frame then return false end
    anchor()
    frame:Show()
    DB.Paint()
    return true
end
function DB.Frame() return frame end
function DB.Open()
    local h = H()
    if not (h and h.open) then OMQ:Print("disenchant bargains: open the auction house first (with the auction helper on)"); return false end
    DB.Show()
    if not run then
        local started, why = DB.Start()
        if not started then OMQ:Print("disenchant bargains: " .. tostring(why)); return false end
    end
    return true
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
                     "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
                     "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
                     "GET_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local rebuildAt = nil
ev:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
        if event == "AUCTION_HOUSE_CLOSED" then
            if run then DB.Finish("the auction house closed") end
            if frame then frame:Hide() end
            for k in pairs(lines) do lines[k] = nil end
            for k in pairs(rows) do rows[k] = nil end
            for i = #list, 1, -1 do list[i] = nil end
            DB.bought = { n = 0, spent = 0, worth = 0 }
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            if (DB.waiting or 0) > 0 and not rebuildAt then rebuildAt = now() + 0.5 end
        elseif not run then return
        elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then DB.OnBrowse()
        elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
            if run.q and run.state == "waiting" then run.q.dropped = true end
        elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED" then
            if run.q and run.state == "waiting" then run.q.resp = true end
        elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then DB.Step() end
    end)
    if not ok then OMQ:Error("disenchant bargains", err); run = nil end
end)
-- a slow tick: the pace of the searches, and a list rebuilt once loaded items came
local acc = 0
ev:SetScript("OnUpdate", function(_, el)
    acc = acc + (el or 0)
    if acc < 0.5 then return end
    acc = 0
    if run then
        local ok, err = pcall(DB.Step)
        if not ok then OMQ:Error("disenchant bargains", err); run = nil end
    end
    if rebuildAt and now() >= rebuildAt then
        rebuildAt = nil
        pcall(DB.Build)
    end
    if frame and frame:IsShown() then pcall(DB.Paint) end      -- "ready" runs out after a few seconds
end)
