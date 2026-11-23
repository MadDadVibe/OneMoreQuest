-- One More Quest: profession cooldowns (decision 662)
-- A recipe with a cooldown of a day or more (transmutes, Mooncloth, recipes new in Forever) gets a card
-- "<recipe> ready" once it can be made again. No hand list of recipes is needed: whenever the profession window
-- is open, every learned recipe the game reports with a day cooldown (C_TradeSkillUI.GetRecipeCooldown) is
-- written down with the time it is ready again, so this works on German and English clients alike. A few
-- recipes are known by spell ID, so they are noted even before their first use. After such a craft the window
-- is read again (the transmutes share one cooldown, so all of them update together). The Salt Shaker (an item,
-- leatherworking) is read from its item cooldown while it is in the bags.
-- Card per group (all "Transmute: ..." recipes are one group): left click opens the profession (Salt Shaker:
-- uses it), right click hides it until the next cooldown has run (kept over logout), shift + right click
-- 5 minutes. No card in dungeons or raids or while the profession window is open; in combat the cards are hidden anyway.
-- Other characters of the account: their cooldowns stand in the characters table of the XP bar and in
-- /omq cd, never as a card. Stored per character in OMQDB.alts[guid].cds (UI/Alts.lua).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local PCD = {}
OMQ.ProfCD = PCD

PCD.KEY = "pcd"
PCD.MIN_CD = 20 * 3600            -- a cooldown this long counts as a day cooldown
PCD.DRIFT = 120                   -- ready times closer than this are the same (no new card key)
PCD.GUESS = 24 * 3600             -- after a craft, until the window tells the real time
PCD.SALT = 15846                  -- Salt Shaker
-- known day cooldown recipes (spell IDs): transmutes and Mooncloth
PCD.KNOWN = { [11479] = true, [11480] = true, [17187] = true, [17559] = true, [17560] = true, [17561] = true,
              [17562] = true, [17563] = true, [17564] = true, [17565] = true, [17566] = true, [25146] = true,
              [18560] = true }
local COLOR = { 0.35, 0.8, 0.95 }
local DEFAULT_ICON = "Interface\\Icons\\Trade_Alchemy"

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok or isSecret(a) then return nil end
    return a, b, c, d
end
local function str(v) return type(v) == "string" and not isSecret(v) and v ~= "" and v or nil end
local function num(v) return type(v) == "number" and not isSecret(v) and v or nil end
local function now() return time() end

----------------------------------------------------------------------
-- Store
----------------------------------------------------------------------
-- the cooldowns of a character: { [recipe ID or "i<item>"] = { n = name, i = icon, p = profession, r = ready (epoch) } }
function PCD.Store(guid, create)
    local alts = OMQ.Alts and OMQ.Alts.Store and OMQ.Alts.Store()
    guid = guid or UnitGUID("player")
    if not alts or not guid or isSecret(guid) then return nil end
    if not alts[guid] then
        if not create then return nil end
        alts[guid] = {}
    end
    local row = alts[guid]
    if not row.cds and create then row.cds = {} end
    return row.cds
end

-- right click: hidden until the next cooldown, per character (key -> true)
local function awayStore()
    local db = OMQ.db and OMQ.db.alerts
    local guid = UnitGUID("player")
    if not db or not guid then return {} end
    db.pcdAway = db.pcdAway or {}
    db.pcdAway[guid] = db.pcdAway[guid] or {}
    return db.pcdAway[guid]
end

-- writes one entry; a ready time is only moved when it really changed (the card key stays the same)
function PCD.Note(key, name, icon, prof, left)
    local cds = PCD.Store(nil, true)
    if not cds then return nil end
    local e = cds[key] or {}
    e.n = name or e.n
    e.i = icon or e.i
    e.p = prof or e.p
    local t = math.floor(now())
    if left and left > 0 then
        local r = math.floor(t + left + 0.5)
        if not e.r or math.abs(e.r - r) > PCD.DRIFT then e.r = r end
        e.g = nil
    elseif not e.r or e.r > t then
        -- ready now: keep an older ready time, so a card clicked away stays away
        e.r = (e.r and not e.g and e.r <= t) and e.r or 0
        e.g = nil
    end
    cds[key] = e
    return e
end

----------------------------------------------------------------------
-- Reading the profession window
----------------------------------------------------------------------
local function profName()
    local T = C_TradeSkillUI
    if T and T.GetBaseProfessionInfo then
        local p = call(T.GetBaseProfessionInfo)
        if type(p) == "table" and str(p.professionName) then return p.professionName end
    end
    if T and T.GetTradeSkillLine then
        local n = call(T.GetTradeSkillLine)
        if str(n) then return n end
    end
    if GetTradeSkillLine then
        local n = call(GetTradeSkillLine)
        if str(n) then return n end
    end
    return nil
end

local function foreign()
    local T = C_TradeSkillUI
    if not T then return false end
    for _, fn in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
        if T[fn] and call(T[fn]) then return true end
    end
    return false
end

-- every learned day cooldown recipe of the open window; returns how many were noted
function PCD.Scan()
    if foreign() then return 0 end
    local T = C_TradeSkillUI
    local prof = profName()
    local n = 0
    if T and T.GetAllRecipeIDs and T.GetRecipeCooldown then
        local ids = call(T.GetAllRecipeIDs)
        for _, id in ipairs(type(ids) == "table" and ids or {}) do
            id = num(id)
            local info = id and T.GetRecipeInfo and call(T.GetRecipeInfo, id)
            if id and (type(info) ~= "table" or info.learned ~= false) then
                local cd, isDay = call(T.GetRecipeCooldown, id)
                cd = num(cd)
                local cds = PCD.Store(nil, false)
                if PCD.KNOWN[id] or (isDay == true) or (cd and cd >= PCD.MIN_CD) or (cds and cds[id]) then
                    local name = type(info) == "table" and str(info.name) or nil
                    local icon = type(info) == "table" and (num(info.icon) or str(info.icon)) or nil
                    if PCD.Note(id, name, icon, prof, cd) then n = n + 1 end
                end
            end
        end
    elseif GetNumTradeSkills and GetTradeSkillCooldown and GetTradeSkillInfo then
        -- the old window: recipes by name
        for i = 1, (call(GetNumTradeSkills) or 0) do
            local name, kind = call(GetTradeSkillInfo, i)
            if str(name) and kind ~= "header" then
                local cd = num(call(GetTradeSkillCooldown, i))
                local cds = PCD.Store(nil, false)
                if (cd and cd >= PCD.MIN_CD) or (cds and cds["n:" .. name]) then
                    local icon = GetTradeSkillIcon and call(GetTradeSkillIcon, i)
                    if PCD.Note("n:" .. name, name, icon, prof, cd) then n = n + 1 end
                end
            end
        end
    end
    return n
end

-- the Salt Shaker: in the bags -> its item cooldown, gone from the bags -> no entry
function PCD.ReadSalt()
    local count = num(call(C_Item and C_Item.GetItemCount or GetItemCount, PCD.SALT)) or 0
    local cds = PCD.Store(nil, false)
    local key = "i" .. PCD.SALT
    if count <= 0 then
        if cds then cds[key] = nil end
        return nil
    end
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    local start, dur = call(f, PCD.SALT)
    start, dur = num(start), num(dur)
    local left = (start and dur and start > 0 and dur > 0) and (start + dur - GetTime()) or 0
    local name = str(call(C_Item and C_Item.GetItemNameByID or nil, PCD.SALT))
        or str(GetItemInfo and (call(GetItemInfo, PCD.SALT))) or "Salt Shaker"
    local icon = (C_Item and C_Item.GetItemIconByID and call(C_Item.GetItemIconByID, PCD.SALT)) or "Interface\\Icons\\INV_Egg_05"
    return PCD.Note(key, name, icon, nil, left > 0 and left or nil)
end

----------------------------------------------------------------------
-- Groups ("Transmute: Arcanite" and "Transmute: Iron to Gold" are one cooldown)
----------------------------------------------------------------------
function PCD.Label(name)
    name = tostring(name or "?")
    return name:match("^(.-):%s") or name
end

-- the groups of a character's cooldowns, sorted by name: { label, r = ready time, ready, icon, prof, item, names }
function PCD.Groups(cds, t)
    t = t or now()
    local by, out = {}, {}
    for key, e in pairs(cds or {}) do
        if type(e) == "table" and e.n then
            local label = PCD.Label(e.n)
            local gk = tostring(e.p or "") .. "|" .. label
            local g = by[gk]
            if not g then
                g = { label = label, r = 0, icon = e.i, prof = e.p, names = {} }
                by[gk] = g
                out[#out + 1] = g
            end
            if type(key) == "string" and key:match("^i%d+$") then g.item = tonumber(key:sub(2)) end
            g.r = math.max(g.r, tonumber(e.r) or 0)
            g.names[#g.names + 1] = e.n
        end
    end
    for _, g in ipairs(out) do
        g.ready = g.r <= t
        table.sort(g.names)
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

function PCD.Left(sec)
    -- rounded up to the minute: "2d 0h" right after a 2 day cooldown started
    sec = math.max(0, math.floor((sec or 0) + 59))
    local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", math.max(1, m))
end

-- one short text for the characters table: ready in green, the others with the time left in grey
function PCD.AltText(guid, t)
    t = t or now()
    local parts = {}
    for _, g in ipairs(PCD.Groups(PCD.Store(guid, false), t)) do
        if g.ready then
            parts[#parts + 1] = "|cff40ff40" .. g.label .. "|r"
        else
            parts[#parts + 1] = "|cff9d9d9d" .. g.label .. " " .. PCD.Left(g.r - t) .. "|r"
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

----------------------------------------------------------------------
-- The card
----------------------------------------------------------------------
function PCD.CardKey(g) return PCD.KEY .. ":" .. tostring(g.prof or "") .. ":" .. g.label .. ":" .. tostring(g.r) end

function PCD.WindowOpen()
    for _, n in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
        local f = _G[n]
        if type(f) == "table" and f.IsShown and call(f.IsShown, f) then return true end
    end
    return false
end

function PCD.Cards()
    local inInst, kind = call(IsInInstance)
    if inInst and (kind == "party" or kind == "raid") then return {} end
    if UnitIsDeadOrGhost and call(UnitIsDeadOrGhost, "player") then return {} end
    PCD.ReadSalt()
    -- the profession window is open: the player is at it already
    if PCD.WindowOpen() then return {} end
    local away = awayStore()
    local list, keep = {}, {}
    for _, g in ipairs(PCD.Groups(PCD.Store(nil, false))) do
        if g.ready then
            local key = PCD.CardKey(g)
            keep[key] = true
            if not away[key] then
                local tip = { g.label .. " can be made again." }
                if #g.names > 1 then
                    tip[1] = g.label .. " can be made again (one cooldown for all):"
                    for i = 1, math.min(#g.names, 8) do tip[#tip + 1] = "  " .. g.names[i] end
                    if #g.names > 8 then tip[#tip + 1] = "  ... and " .. (#g.names - 8) .. " more" end
                end
                local c = { key = key, text = g.label, title = g.label, tag = "PROFESSION",
                            icon = g.icon or DEFAULT_ICON, color = COLOR, tipLines = tip }
                if g.item then
                    c.sub = "Ready - left click: use it"
                    c.useItem = "item:" .. g.item
                elseif g.prof then
                    c.sub = "Ready - left click: " .. g.prof
                    c.cast = g.prof
                else
                    c.sub = "Ready again"
                end
                list[#list + 1] = c
            end
        end
    end
    -- forget clicked-away keys of cooldowns that ran again
    for k in pairs(away) do if not keep[k] then away[k] = nil end end
    return list
end

function PCD.Check()
    if InCombatLockdown and InCombatLockdown() then return "keep" end
    return PCD.Cards()
end

OMQ:On("ALERT_DISMISSED", function(key, snooze)
    if snooze or type(key) ~= "string" or not key:find("^pcd:") then return end
    awayStore()[key] = true
end)

M:Register({ id = "profcd", name = "Profession cooldown ready", check = PCD.Check })

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local pending = false
local function rescan(delay)
    if pending then return end
    pending = true
    local run = function() pending = false; PCD.Scan() end
    if C_Timer and C_Timer.After then C_Timer.After(delay or 0.5, run) else run() end
end

-- after a craft of a noted recipe: on cooldown at once (all of its group), the window corrects the time
function PCD.Crafted(spellID)
    local cds = PCD.Store(nil, false)
    local e = cds and cds[spellID]
    if not e and not PCD.KNOWN[spellID] then return false end
    local t = now()
    if e then
        local label = PCD.Label(e.n)
        for _, o in pairs(cds) do
            if type(o) == "table" and o.p == e.p and PCD.Label(o.n) == label and (tonumber(o.r) or 0) <= t then
                o.r, o.g = t + PCD.GUESS, true
            end
        end
    end
    rescan(1)
    return true
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "BAG_UPDATE_COOLDOWN" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, _, a3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" and num(a3) then PCD.Crafted(a3) end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        PCD.ReadSalt()
    else
        rescan(0.5)
    end
end)

----------------------------------------------------------------------
-- /omq cd: every character's cooldowns
----------------------------------------------------------------------
function PCD.Report()
    local lines = {}
    local list = OMQ.Alts and OMQ.Alts.Store and OMQ.Alts.Store() or {}
    local rows = {}
    for guid, row in pairs(list) do
        if type(row) == "table" and row.cds and next(row.cds) then rows[#rows + 1] = { guid = guid, name = row.name or "?" } end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    for _, r in ipairs(rows) do
        local txt = PCD.AltText(r.guid)
        if txt then lines[#lines + 1] = r.name .. ": " .. txt end
    end
    return lines
end

OMQ:RegisterCommand("cd", function()
    PCD.ReadSalt()
    local lines = PCD.Report()
    if #lines == 0 then
        OMQ:Print("profession cooldowns: none known yet - open the profession window once on each character")
        return
    end
    OMQ:Print("profession cooldowns (green = ready):")
    for _, l in ipairs(lines) do OMQ:Print("  " .. l) end
end, "profession cooldowns of all your characters")
