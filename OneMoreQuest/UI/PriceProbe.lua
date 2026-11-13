-- One More Quest: a short measurement of the auction house browse search (fix 587).
-- /omq prices probe asks a few categories one after the other and writes every auction house event with its time
-- into OMQDB.priceProbe. It compares the price scan's own search (one class filter, no quality filters) with the
-- search the game's own window sends (all quality filters, levels 0, one filter per subcategory), and it shows
-- whether the server drops searches (AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED). The scan's price list is not touched.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local R = {}
OMQ.PriceProbe = R

R.END_WAIT = 10       -- a step ends this many seconds after its last event
R.STEP_MAX = 20       -- and at the latest after this many seconds
R.GAP = 2             -- seconds between two steps (and the system must be ready)
R.PAGES = 5           -- at most this many pages per step
R.SUBS = 6            -- subcategories of consumables and of trade goods asked one by one
R.MAX_EV = 600        -- events kept in the log

local function now() return GetTime() end
local function A() return C_AuctionHouse end
local run

R.EVENTS = { "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE",
             "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
             "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
             "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_CLOSED" }
R.SHORT = { AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = "UPD", AUCTION_HOUSE_BROWSE_RESULTS_ADDED = "ADD",
            AUCTION_HOUSE_BROWSE_FAILURE = "FAIL", AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = "DROP",
            AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED = "QUEUE", AUCTION_HOUSE_THROTTLED_MESSAGE_SENT = "SENT",
            AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED = "RESP", AUCTION_HOUSE_THROTTLED_SYSTEM_READY = "READY",
            AUCTION_HOUSE_CLOSED = "CLOSED", SEND = "SEND", MORE = "MORE" }

-- all quality filters, as the game's window has them by default
function R.QualityFilters()
    local F = Enum and Enum.AuctionHouseFilter
    if not F then return {} end
    local out = {}
    for _, k in ipairs({ "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality", "EpicQuality", "LegendaryQuality" }) do
        if F[k] ~= nil then out[#out + 1] = F[k] end
    end
    return out
end

function R.Subclasses(c)
    local api = A()
    local ok, list = pcall(function() return api and api.GetAuctionItemSubClasses and { api.GetAuctionItemSubClasses(c) } end)
    if ok and type(list) == "table" and type(list[1]) == "table" then list = list[1] end
    return ok and type(list) == "table" and list or {}
end

local function sorts()
    local E = Enum and Enum.AuctionHouseSortOrder
    return { { sortOrder = E and E.Price or 0, reverseSort = false }, { sortOrder = E and E.Name or 1, reverseSort = false } }
end

-- the scan's own search of a whole class (as the price scan asks it)
function R.OldQuery(c)
    return { searchString = "", sorts = sorts(), itemClassFilters = { { classID = c } } }
end

-- the search the game's window sends for a category: one filter per subcategory, all qualities, levels 0
function R.GameQuery(c, sub)
    local f = {}
    if sub then f[1] = { classID = c, subClassID = sub }
    else
        for _, s in ipairs(R.Subclasses(c)) do f[#f + 1] = { classID = c, subClassID = s } end
        if #f == 0 then f[1] = { classID = c } end
    end
    return { searchString = "", minLevel = 0, maxLevel = 0, filters = R.QualityFilters(), sorts = sorts(), itemClassFilters = f }
end

function R.Steps()
    local s = { { name = "0 old", q = R.OldQuery(0) }, { name = "0 game", q = R.GameQuery(0) },
                { name = "7 old", q = R.OldQuery(7) }, { name = "7 game", q = R.GameQuery(7) } }
    for _, c in ipairs({ 0, 7 }) do
        local subs = R.Subclasses(c)
        for i = 1, math.min(R.SUBS, #subs) do s[#s + 1] = { name = c .. "." .. subs[i] .. " game", q = R.GameQuery(c, subs[i]) } end
    end
    return s
end

function R.Running() return run ~= nil end

local function ready()
    local api = A()
    if not (api and api.IsThrottledMessageSystemReady) then return nil end
    local ok, r = pcall(api.IsThrottledMessageSystemReady)
    return ok and r or false
end

-- how many lines the browse list holds, whether it is complete, and the item class most of the first lines have
local function listState()
    local api = A()
    local ok, list = pcall(api.GetBrowseResults)
    if not ok or type(list) ~= "table" then return 0, false, nil end
    local full = api.HasFullBrowseResults and select(2, pcall(api.HasFullBrowseResults)) == true
    local count = {}
    for i = 1, math.min(30, #list) do
        local key = list[i] and list[i].itemKey
        local id = key and key.itemID
        local cls = id and GetItemInfoInstant and select(6, GetItemInfoInstant(id))
        if cls then count[cls] = (count[cls] or 0) + 1 end
    end
    local best, bn = nil, 0
    for c, n in pairs(count) do if n > bn then best, bn = c, n end end
    return #list, full, best
end

local function log(kind, extra)
    if not run then return end
    local L = run.log
    if #L.ev >= R.MAX_EV then return end
    local st = run.steps[run.i]
    L.ev[#L.ev + 1] = string.format("%.2f %s s%d%s", now() - run.t0, R.SHORT[kind] or kind, run.i or 0, extra and (" " .. extra) or "")
    if st then st.ev[R.SHORT[kind] or kind] = (st.ev[R.SHORT[kind] or kind] or 0) + 1 end
end

local function closeStep(why)
    local st = run.steps[run.i]
    if not st or st.done then return end
    local n, full, cls = listState()
    st.done, st.n, st.full, st.cls, st.why, st.secs = true, n, full, cls, why, now() - st.at
    run.log.steps[#run.log.steps + 1] = { name = st.name, n = n, full = full or nil, cls = cls, why = why, pages = st.pages,
                                         secs = math.floor(st.secs * 10 + 0.5) / 10, ev = st.ev, readyAtSend = st.readyAtSend }
    run.gapAt = now()
end

local function finish(why)
    if not run then return end
    if run.steps[run.i] and not run.steps[run.i].done then closeStep(why) end
    local L = run.log
    L.why, L.secs = why, math.floor((now() - run.t0) * 10 + 0.5) / 10
    OMQDB.priceProbe = L
    local H = OMQ.AuctionHelper
    if H then H.quietUntil = nil end
    run = nil
    OMQ:Print("prices probe: " .. (why or "done") .. " - /reload and send me the SavedVariables")
    for _, s in ipairs(L.steps) do
        local evs = {}
        for _, k in ipairs({ "SENT", "RESP", "DROP", "UPD", "ADD", "FAIL" }) do
            if s.ev[k] then evs[#evs + 1] = k .. "=" .. s.ev[k] end
        end
        OMQ:Print(string.format("  %s: %d lines%s, %.1f s, %s", s.name, s.n or 0, s.full and " (complete)" or "", s.secs or 0,
            #evs > 0 and table.concat(evs, " ") or "no events"))
    end
end

local function send()
    local st = run.steps[run.i]
    st.at, st.lastAt, st.pages, st.ev = now(), now(), 1, {}
    st.readyAtSend = ready()
    log("SEND", "ready=" .. tostring(st.readyAtSend))
    local H = OMQ.AuctionHelper
    local fn = function(q) return A().SendBrowseQuery(q) end
    local ok, err = pcall(function() if H and H.Own then H.Own(fn, st.q) else fn(st.q) end end)
    if not ok then st.ev.ERR = 1; closeStep("send failed: " .. tostring(err)) end
end

function R.Step()
    if not run then return end
    local st = run.steps[run.i]
    if st and not st.done then
        if now() - st.lastAt >= R.END_WAIT then closeStep("quiet")
        elseif now() - st.at >= R.STEP_MAX then closeStep("time") end
        return
    end
    if now() - (run.gapAt or 0) < R.GAP then return end
    if ready() == false and now() - (run.gapAt or 0) < R.GAP + 30 then return end   -- the game says not yet
    run.i = run.i + 1
    if not run.steps[run.i] then finish("done"); return end
    local H = OMQ.AuctionHelper
    if H then H.quietUntil = now() + 60 end
    send()
end

function R.OnEvent(event)
    if not run then return end
    if event == "AUCTION_HOUSE_CLOSED" then finish("the window closed"); return end
    local st = run.steps[run.i]
    local extra
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        local n, full, cls = listState()
        extra = string.format("n=%d full=%s cls=%s", n, tostring(full), tostring(cls))
    end
    log(event, extra)
    if not st or st.done then return end
    st.lastAt = now()
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        local n, full = listState()
        if full then
            closeStep("complete")
        elseif n > 0 and st.pages < R.PAGES and A().RequestMoreBrowseResults then
            st.pages = st.pages + 1
            log("MORE", "page=" .. st.pages)
            pcall(A().RequestMoreBrowseResults)
        elseif n > 0 then
            closeStep("pages")
        end
    end
end

function R.Start()
    if run then return false, "the probe is already running" end
    local H = OMQ.AuctionHelper
    if not (H and H.open) then return false, "open the auction house first" end
    local api = A()
    if not (api and api.SendBrowseQuery and api.GetBrowseResults) then return false, "this client has no browse list" end
    if OMQ.Prices and OMQ.Prices.Busy and OMQ.Prices.Busy() then OMQ.Prices.Cancel() end   -- old prices stay
    local steps = R.Steps()
    for _, s in ipairs(steps) do s.ev = {} end
    run = { steps = steps, i = 0, t0 = now(), gapAt = now() + 1,
            log = { at = time and time() or 0, ev = {}, steps = {}, quality = #R.QualityFilters(),
                    subs0 = table.concat(R.Subclasses(0), ","), subs7 = table.concat(R.Subclasses(7), ",") } }
    if H then H.quietUntil = now() + 60 end
    OMQ:Print(string.format("prices probe: %d searches, about %d s - keep the auction house open and do not click in it", #steps, #steps * 8))
    return true
end

local ev = CreateFrame("Frame")
for _, e in ipairs(R.EVENTS) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(R.OnEvent, event)
    if not ok then OMQ:Error("prices", err) end
end)
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    if not run then return end
    acc = acc + (dt or 0)
    if acc < 0.2 then return end
    acc = 0
    local ok, err = pcall(R.Step)
    if not ok then OMQ:Error("prices", err); run = nil end
end)
