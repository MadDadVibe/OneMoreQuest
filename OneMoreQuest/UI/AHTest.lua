-- One More Quest: auction house test window (decision 597).
-- /omq ahtest opens a window next to the auction house with one button per category (and per subcategory the game
-- names). A click sends one browse search of that category, asks for more pages until the game says the list is
-- complete, and stores the prices the way a part of the price scan does (new price and quantity, nothing removed,
-- the time of the last full scan stays). The window shows everything about the search: the query sent, the time
-- to the first answer and in all, every auction house event with its time, the raw lines of the answer and the
-- items collected. The text can be copied (Ctrl+A, Ctrl+C); the last RUNS_KEPT runs stay in OMQDB.ahTest.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local T = {}
OMQ.AHTest = T

T.PAGES = 200        -- at most this many pages of one search
T.QUIET = 15         -- a search ends this many seconds after its last event
T.RAW_LINES = 20     -- lines of the answer shown with every field
T.ITEMS_SHOWN = 400  -- items listed in the window
T.ITEMS_KEPT = 200   -- items kept per run in the saved variables
T.EV_MAX = 300       -- events kept per run
T.RUNS_KEPT = 10
T.HELPER_WAIT = 6    -- a search of the helper still on its way is waited for (as the price scan does, decision 448)
T.mode = "omq"       -- "omq": the price scan's own search, the form of the game's window (decision 604);
                     -- "old": the search without quality filters the scan sent before - the server limits it

T.EVENTS = { "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE",
             "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
             "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
             "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }
T.SHORT = { AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = "UPDATED", AUCTION_HOUSE_BROWSE_RESULTS_ADDED = "ADDED",
            AUCTION_HOUSE_BROWSE_FAILURE = "FAILURE", AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = "THROTTLE DROPPED",
            AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED = "THROTTLE QUEUED", AUCTION_HOUSE_THROTTLED_MESSAGE_SENT = "THROTTLE SENT",
            AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED = "THROTTLE RESPONSE",
            AUCTION_HOUSE_THROTTLED_SYSTEM_READY = "THROTTLE READY" }

local function now() return GetTime() end
local function stamp() return time and time() or 0 end
local function A() return C_AuctionHouse end
local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function P() return OMQ.Prices end
local function H() return OMQ.AuctionHelper end

local run          -- the search running now
local frame        -- the window
local expanded = {}

----------------------------------------------------------------------
-- Categories, names, queries
----------------------------------------------------------------------
function T.Classes()
    local list = (P() and P().CLASSES) or { 0, 7, 5, 8, 9, 1, 11, 6, 3, 12, 15, 2, 4 }
    local out = {}
    for _, c in ipairs(list) do out[#out + 1] = c end
    return out
end
function T.Subclasses(c)
    local list = P() and P().Subclasses and P().Subclasses(c) or {}
    local out = {}
    for _, s in ipairs(list) do if type(s) == "number" then out[#out + 1] = s end end
    return out
end
-- the name of a category in the client's language, or its number
function T.Name(c, s)
    local f
    if s ~= nil then f = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    else f = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo end
    local name
    if f then
        local ok, n
        if s ~= nil then ok, n = pcall(f, c, s) else ok, n = pcall(f, c) end
        if ok and type(n) == "string" and n ~= "" and not isSecret(n) then name = n end
    end
    if s ~= nil then return (name or "subcategory") .. " (" .. c .. "." .. s .. ")" end
    return (name or "category") .. " (" .. c .. ")"
end
function T.Query(c, s, mode)
    if (mode or T.mode) == "old" and OMQ.PriceProbe and OMQ.PriceProbe.OldQuery then return OMQ.PriceProbe.OldQuery(c, s) end
    if P() and P().QUERY then return P().QUERY({ classID = c, subClassID = s }) end
    return { searchString = "", sorts = {}, itemClassFilters = { { classID = c, subClassID = s } } }
end

-- any value as one line of text: tables with their fields in a fixed order
local function dump(v, depth)
    depth = depth or 0
    if isSecret(v) then return "<secret>" end
    if type(v) ~= "table" then
        if type(v) == "string" then return string.format("%q", v) end
        return tostring(v)
    end
    if depth > 3 then return "{...}" end
    local keys, arr = {}, #v
    for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= arr and k % 1 == 0) then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for i = 1, arr do parts[#parts + 1] = dump(v[i], depth + 1) end
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. dump(v[k], depth + 1) end
    return "{" .. table.concat(parts, ", ") .. "}"
end
T.Dump = dump

local function classOf(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, _, _, _, _, c, sc = pcall(f, id)
    if ok then return c, sc end
end
local function itemName(id)
    local f = (C_Item and C_Item.GetItemNameByID) or (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if f then
        local ok, n = pcall(f, id)
        if ok and type(n) == "string" and not isSecret(n) then return n end
    end
    return "item " .. id
end
local function money(c)
    local h = H()
    if h and h.Money then return h.Money(c) end
    return tostring(c) .. "c"
end
local function ready()
    local api = A()
    if not (api and api.IsThrottledMessageSystemReady) then return nil end
    local ok, r = pcall(api.IsThrottledMessageSystemReady)
    return ok and r or false
end
local function listState()
    local api = A()
    local ok, list = pcall(api.GetBrowseResults)
    if not ok or type(list) ~= "table" then list = {} end
    local full = false
    if api.HasFullBrowseResults then
        local ok2, f = pcall(api.HasFullBrowseResults)
        full = ok2 and f == true
    end
    return list, full
end

----------------------------------------------------------------------
-- The search
----------------------------------------------------------------------
function T.Running() return run ~= nil end
function T.Runs() OMQDB.ahTest = OMQDB.ahTest or {}; return OMQDB.ahTest end

local function log(text)
    if not run or #run.ev >= T.EV_MAX then return end
    run.ev[#run.ev + 1] = string.format("%6.2f  %s", now() - run.t0, text)
end

-- the lines of the list: per item the cheapest piece and all pieces; lines of another class count as foreign
local function collect(list, cls)
    local items, foreign, n = {}, 0, 0
    for _, res in ipairs(list) do
        local k = res.itemKey
        local id, price, qty = k and k.itemID, res.minPrice, res.totalQuantity
        if id and not isSecret(id) and type(price) == "number" and not isSecret(price) and price > 0 then
            n = n + 1
            local c = classOf(id)
            if c and c ~= cls then foreign = foreign + 1 end
            qty = (not isSecret(qty) and tonumber(qty)) or 0
            local e = items[id]
            if e then
                if price < e.p then e.p = math.floor(price) end
                e.q = e.q + qty
            else items[id] = { p = math.floor(price), q = qty } end
        end
    end
    return items, foreign, n
end

-- the prices go into the price list like a part of the scan: new price and quantity, nothing removed, the time
-- of the last full scan stays; a live price of the last minutes is not overwritten (decision 427)
function T.Save(items, since)
    local st = P().Store()                               -- the price list of my realm (fix 711)
    local maxAge = (P() and P().MAX_AGE) or 900
    local saved = 0
    for id, e in pairs(items) do
        local old = st.items[id]
        if old and old.t and since and old.t >= since then
            saved = saved + 1                            -- this answer itself, stored as a live price already
        elseif not (old and old.t and stamp() - old.t <= maxAge) then
            if not old then st.n = (st.n or 0) + 1 end
            st.items[id] = { p = e.p, q = e.q }
            saved = saved + 1
        end
    end
    if OMQ.Fire then OMQ:Fire("PRICES_UPDATED", false) end
    return saved
end

local function report(r)
    local L = {}
    L[#L + 1] = string.format("%s - %s search - %s", r.label, r.mode == "old" and "old (no quality filters)" or "OMQ", r.why or "running")
    L[#L + 1] = "query: " .. (r.query or "?")
    L[#L + 1] = "SendBrowseQuery returned: " .. (r.ret or "?")
    L[#L + 1] = string.format("first answer after %s, %s in all, %d pages, %d lines, %d items%s, complete: %s",
        r.first and string.format("%.2f s", r.first) or "-", string.format("%.2f s", r.secs or 0), r.pages or 0, r.lines or 0,
        r.n or 0, (r.foreign or 0) > 0 and string.format(", %d foreign lines (other class)", r.foreign) or "",
        r.full and "yes" or "no")
    if r.saved then L[#L + 1] = string.format("saved: %d prices (%d kept: live prices seen before this search)", r.saved, (r.n or 0) - r.saved) end
    L[#L + 1] = ""
    L[#L + 1] = "events (seconds after the click):"
    for _, e in ipairs(r.ev or {}) do L[#L + 1] = e end
    L[#L + 1] = ""
    L[#L + 1] = string.format("raw answer, first %d lines of GetBrowseResults:", T.RAW_LINES)
    for i, line in ipairs(r.raw or {}) do L[#L + 1] = i .. ": " .. line end
    L[#L + 1] = ""
    L[#L + 1] = "items (cheapest first): id, name, category, price of one, on offer, price before"
    for _, it in ipairs(r.items or {}) do
        L[#L + 1] = string.format("%d  %s  [%s]  %s  x%d  before %s", it.id, it.name, it.cat or "?", money(it.p), it.q or 0,
            it.old and money(it.old) or "-")
    end
    if (r.n or 0) > #(r.items or {}) then L[#L + 1] = string.format("... and %d more", r.n - #r.items) end
    return table.concat(L, "\n")
end
T.Report = report

local function finish(why)
    if not run then return end
    local r = run
    run = nil
    local list, full = listState()
    local items, foreign, lines = collect(list, r.c)
    r.full, r.lines, r.foreign = full, lines, foreign
    r.secs = now() - r.t0
    r.why = why
    local raw = {}
    for i = 1, math.min(T.RAW_LINES, #list) do raw[i] = dump(list[i]) end
    r.raw = raw
    -- the price before, then save
    local st = P() and P().Store and P().Store()
    local sorted, n = {}, 0
    for id, e in pairs(items) do
        n = n + 1
        local old = st and st.items[id]
        local c, s = classOf(id)
        sorted[#sorted + 1] = { id = id, p = e.p, q = e.q, old = old and old.p, cat = c and (c .. (s and ("." .. s) or "")) or nil }
    end
    table.sort(sorted, function(a, b) if a.p ~= b.p then return a.p < b.p end return a.id < b.id end)
    r.n = n
    r.saved = n > 0 and T.Save(items, r.at) or 0
    for i = #sorted, T.ITEMS_SHOWN + 1, -1 do sorted[i] = nil end
    for _, it in ipairs(sorted) do it.name = itemName(it.id) end
    r.items = sorted
    r.text = report(r)
    local h = H()
    if h then h.quietUntil = nil end
    -- the run without its long text and with fewer items in the saved variables
    local keep = { at = r.at, label = r.label, mode = r.mode, query = r.query, ret = r.ret, why = why, first = r.first,
                   secs = math.floor(r.secs * 100 + 0.5) / 100, pages = r.pages, lines = lines, n = n, full = full or nil,
                   foreign = foreign, saved = r.saved, ev = r.ev, raw = raw, items = {} }
    for i = 1, math.min(T.ITEMS_KEPT, #sorted) do
        local it = sorted[i]
        keep.items[i] = string.format("%d %s %s p=%d q=%d", it.id, it.name, it.cat or "?", it.p, it.q or 0)
    end
    local runs = T.Runs()
    table.insert(runs, 1, keep)
    for i = #runs, T.RUNS_KEPT + 1, -1 do runs[i] = nil end
    T.last = r
    OMQ:Print(string.format("ahtest: %s - %d lines, %d items, %.1f s (%s)", r.label, lines, n, r.secs, why))
    T.Paint()
end

local function send()
    local api = A()
    run.sentAt = now()
    run.state = "waiting"
    run.lastAt = now()
    log("SEND SendBrowseQuery ready=" .. tostring(ready()))
    local fn = function(q) return api.SendBrowseQuery(q) end
    local h = H()
    local ok, a, b = pcall(function() if h and h.Own then return h.Own(fn, run.q) end return fn(run.q) end)
    if not ok then run.ret = "error: " .. tostring(a); finish("SendBrowseQuery failed"); return end
    run.ret = (a == nil and b == nil) and "nothing (nil)" or (dump(a) .. (b ~= nil and (", " .. dump(b)) or ""))
end

function T.Start(c, s)
    if run then return false, "a test search is running" end
    local h = H()
    if not (h and h.open) then return false, "open the auction house first" end
    local api = A()
    if not (api and api.SendBrowseQuery and api.GetBrowseResults) then return false, "this client has no browse list" end
    if OMQ.PriceProbe and OMQ.PriceProbe.Running and OMQ.PriceProbe.Running() then return false, "the probe is running" end
    if P() and P().Busy and P().Busy() then P().Cancel(); OMQ:Print("ahtest: the price scan was stopped (prices so far are kept)") end
    local q = T.Query(c, s)
    run = { c = c, s = s, q = q, label = T.Name(c, s), mode = T.mode, query = dump(q), at = stamp(), t0 = now(),
            ev = {}, pages = 0, state = "start" }
    h.quietUntil = now() + 60
    T.Paint()
    T.Step()
    return true
end
function T.Cancel() if run then finish("cancelled") end end

function T.Step()
    if not run then return end
    local h = H()
    if not (h and h.open) then finish("the window closed"); return end
    if h then h.quietUntil = now() + 60 end
    if run.state == "start" then
        -- a search of the helper still on its way would be read as ours; and the game must be ready
        if h and h._Asking then
            local q, age = h._Asking()
            if q and age < T.HELPER_WAIT then return end
        end
        if ready() == false then
            if not run.waitLogged then run.waitLogged = true; log("waiting: IsThrottledMessageSystemReady = false") end
            if now() - run.t0 < 30 then return end
            log("still not ready after 30 s - sending anyway")
        end
        run.pages = 1
        send()
        return
    end
    if run.more then
        if ready() == false then return end
        run.more = false
        run.pages = run.pages + 1
        run.lastAt = now()
        log("MORE RequestMoreBrowseResults page=" .. run.pages)
        local api = A()
        local ok, err = pcall(function() if h and h.Own then return h.Own(api.RequestMoreBrowseResults) end return api.RequestMoreBrowseResults() end)
        if not ok then log("RequestMoreBrowseResults error: " .. tostring(err)); finish("RequestMoreBrowseResults failed") end
        return
    end
    if now() - run.lastAt >= T.QUIET then
        finish(run.gotList and "no more answers" or "no answer")
    end
end

function T.OnEvent(event, ...)
    if event == "AUCTION_HOUSE_CLOSED" then
        if run then finish("the window closed") end
        if frame then frame:Hide() end
        return
    end
    if not run or run.state == "start" then return end
    local args = {}
    for i = 1, select("#", ...) do args[#args + 1] = dump((select(i, ...))) end
    local extra = #args > 0 and (" args " .. table.concat(args, ", ")) or ""
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        local list, full = listState()
        local _, foreign = collect(list, run.c)
        log(string.format("%s lines=%d complete=%s foreign=%d%s", T.SHORT[event], #list, tostring(full), foreign, extra))
        run.lastAt = now()
        if #list > 0 then
            run.gotList = true
            run.first = run.first or (now() - run.sentAt)
        end
        if full then finish("complete")
        elseif #list > 0 and run.pages < T.PAGES and A().RequestMoreBrowseResults then run.more = true; T.Step()
        elseif #list > 0 then finish("page limit") end
        return
    end
    log((T.SHORT[event] or event) .. extra)
    if event ~= "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then run.lastAt = now() end
    if event == "AUCTION_HOUSE_BROWSE_FAILURE" then finish("browse failure") end
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local buttons = {}
local function button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame.list, "UIPanelButtonTemplate")
    b:SetSize(176, 20)
    b:SetScript("OnClick", function(self, mouse)
        local ok, err = pcall(function()
            local d = self.omq
            if d.toggle then
                expanded[d.c] = not expanded[d.c] or nil
                T.Paint()
                return
            end
            local started, why = T.Start(d.c, d.s)
            if not started then OMQ:Print("ahtest: " .. tostring(why)) end
        end)
        if not ok then OMQ:Error("ahtest", err) end
    end)
    buttons[i] = b
    return b
end
T._buttons = buttons

local function build()
    local ok, f = pcall(CreateFrame, "Frame", "OneMoreQuestAHTest", UIParent, "BasicFrameTemplateWithInset")
    if not ok then return end
    frame = f
    f:SetSize(760, 520)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText("One More Quest - auction house test (Ctrl+A, Ctrl+C to copy)")
    local mode = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    mode:SetSize(200, 22)
    mode:SetPoint("TOPLEFT", 12, -30)
    mode:SetScript("OnClick", function()
        T.mode = (T.mode == "omq") and "old" or "omq"
        T.Paint()
    end)
    f.mode = mode
    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(80, 22)
    cancel:SetPoint("LEFT", mode, "RIGHT", 6, 0)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() T.Cancel() end)
    f.cancel = cancel
    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("LEFT", cancel, "RIGHT", 10, 0)
    f.status = status
    local lsf = CreateFrame("ScrollFrame", "OneMoreQuestAHTestList", f, "UIPanelScrollFrameTemplate")
    lsf:SetPoint("TOPLEFT", 12, -58)
    lsf:SetPoint("BOTTOMLEFT", 12, 12)
    lsf:SetWidth(186)
    local list = CreateFrame("Frame", nil, lsf)
    list:SetSize(180, 400)
    lsf:SetScrollChild(list)
    f.list = list
    local sf = CreateFrame("ScrollFrame", "OneMoreQuestAHTestScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 226, -58)
    sf:SetPoint("BOTTOMRIGHT", -32, 12)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    eb:SetWidth(500)
    eb:SetAutoFocus(false)
    if eb.SetMaxLetters then eb:SetMaxLetters(0) end
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.edit = eb
    if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestAHTest") end
end

local function anchor()
    frame:ClearAllPoints()
    local helperPanel = _G.OneMoreQuestAuctionHelper
    local ahf = _G.AuctionHouseFrame
    if helperPanel and helperPanel:IsShown() then frame:SetPoint("TOPLEFT", helperPanel, "TOPRIGHT", 6, 0)
    elseif ahf then frame:SetPoint("TOPLEFT", ahf, "TOPRIGHT", 6, 0)
    else frame:SetPoint("CENTER") end
end

function T.Paint()
    if not frame or not frame:IsShown() then return end
    frame.mode:SetText(T.mode == "old" and "Search: old (no quality filters)" or "Search: OMQ (price scan)")
    if run then
        frame.status:SetText(string.format("searching %s: %.0f s, page %d", run.label, now() - run.t0, run.pages or 0))
    else
        frame.status:SetText(T.last and ("last: " .. T.last.label .. " - " .. (T.last.why or "")) or "click a category")
    end
    -- the buttons: per class a [+]/[-] that opens its subcategories and the name that searches the whole class;
    -- below an open class one button per subcategory
    local i, line = 0, 0
    local function place(toggle, c, s, label, x, w)
        i = i + 1
        local b = button(i)
        b.omq = { toggle = toggle, c = c, s = s }
        b:ClearAllPoints()
        b:SetSize(w, 20)
        b:SetPoint("TOPLEFT", frame.list, "TOPLEFT", x, -(line - 1) * 22)
        b:SetText(label)
        if b.SetEnabled then b:SetEnabled(toggle or not run) end
        b:Show()
    end
    for _, c in ipairs(T.Classes()) do
        line = line + 1
        place(true, c, nil, expanded[c] and "-" or "+", 0, 22)
        place(nil, c, nil, T.Name(c), 24, 152)
        if expanded[c] then
            for _, s in ipairs(T.Subclasses(c)) do
                line = line + 1
                place(nil, c, s, T.Name(c, s), 24, 152)
            end
        end
    end
    for k = i + 1, #buttons do buttons[k]:Hide() end
    frame.list:SetHeight(math.max(400, line * 22 + 4))
    T.lines = line
    local text
    if run then text = report(run)
    elseif T.last then text = T.last.text
    else text = "Click a category on the left: one browse search of it, every page, every event.\n" ..
                "The prices found are stored like a part of the price scan.\n" ..
                "The top button switches between the price scan's own search and the search the game's window sends." end
    local _, nl = text:gsub("\n", "\n")
    frame.edit:SetHeight(math.max(420, (nl + 2) * 15))
    frame.edit:SetText(text)
end

function T.Show()
    if not frame then build() end
    if not frame then return false end
    anchor()
    frame:Show()
    T.Paint()
    return true
end
function T.Toggle()
    local h = H()
    if not (h and h.open) then OMQ:Print("ahtest: open the auction house first"); return end
    if frame and frame:IsShown() then frame:Hide(); return end
    T.Show()
end
function T.Frame() return frame end

local ev = CreateFrame("Frame")
for _, e in ipairs(T.EVENTS) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(T.OnEvent, event, ...)
    if not ok then OMQ:Error("ahtest", err); run = nil end
end)
local acc, paintAcc = 0, 0
ev:SetScript("OnUpdate", function(_, dt)
    if not run then return end
    acc, paintAcc = acc + (dt or 0), paintAcc + (dt or 0)
    if acc < 0.1 then return end
    acc = 0
    local ok, err = pcall(T.Step)
    if not ok then OMQ:Error("ahtest", err); run = nil; return end
    if paintAcc >= 1 then paintAcc = 0; pcall(T.Paint) end
end)

OMQ:RegisterCommand("ahtest", function() T.Toggle() end, "auction house test window: search single categories by hand")
