-- One More Quest: PvP numbers on enemy nameplates (decision 700)
-- Right of an enemy player's nameplate (past the level number) up to three numbers:
--   green = how often I or my group killed him, red = how often he killed me (all my own characters together),
--   blue  = how often he killed the other dads (their lists come over the group and the guild).
-- A number that is 0 is left out; all 0: nothing. The Shadow Word: Death and Overpower icons stay left of the bar.
--
-- Without the combat log (blocked on WoW Forever):
--   * kills: PARTY_KILL(killer, victim) names both outside instances; a player victim counts when the killer is me,
--     my pet, a group member or his pet (a group member only within RANGE yards, when his position can be read);
--   * my death: every enemy player who hit me in the last ATTACKER_FOR seconds gets +1. "Who hit me" is read on each
--     hit I take (UNIT_COMBAT player WOUND): enemy player nameplates whose target is me, else my enemy player target.
-- Dads: each client sends its "who killed me" list (PK) on login, to the group and to the guild, and the changed
-- entries after each death; a new dad heard gets the whole list once. When my group kills a player who killed a
-- dad, that dad gets a card "<me> avenged you" (PV), unless he was in my group nearby (then he saw it himself).
-- Data: OMQDB.pvpCount = { seeded, p = { [guid] = { k, d, n, t } }, dads = { [dadGuid] = { n, t, e = { [guid] = { c, n } } } } }
-- Option: options.pvpCount (default on). /omq pvp on | off | test | list | debug.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local K = {}
OMQ.PvPCount = K

K.ATTACKER_FOR = 15       -- seconds a hit on me keeps the attacker as a killer
K.RANGE = 75              -- yards a group member may be away for his kill to count
K.MAX = 2000              -- players kept (oldest go first)
K.SEND_MAX = 60           -- entries of my list sent to the dads (newest first)
K.PART = 5                -- entries per message
K.GAP = 22                -- pixels right of the health bar, past the level number
K.FONT_SIZE = 14
K.GREEN = "40ff40"
K.RED = "ff4040"
K.BLUE = "4fa8ff"
K.CARD_HOLD = 7           -- seconds the revenge card stays
K.SOUND = 888             -- level up fanfare
K.LOG = 15

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" end
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok and not secret(v) then return v end
end
local function isPlayerGuid(g) return str(g) and g:find("^Player%-") ~= nil end
local function clean(s) return (tostring(s or ""):gsub("[|,;:\n\r]", "")) end

local log = {}
local function note(text)
    table.insert(log, 1, ("%.1f %s"):format(GetTime(), text))
    while #log > K.LOG do table.remove(log) end
end
function K.Log() return log end

function K.Enabled()
    return not (OMQ.db and OMQ.db.options and OMQ.db.options.pvpCount == false)
end

----------------------------------------------------------------------
-- store
----------------------------------------------------------------------
local function store()
    if not OMQDB then return nil end
    local s = OMQDB.pvpCount
    if type(s) ~= "table" then s = {}; OMQDB.pvpCount = s end
    s.p = type(s.p) == "table" and s.p or {}
    s.dads = type(s.dads) == "table" and s.dads or {}
    return s
end
K.Store = store

local function myGuid() local me = OMQ:GetSelf(); return me and me.guid end
local function myName() local me = OMQ:GetSelf(); return me and me.name or "?" end

-- my own characters: the books of the statistics, plus the one playing now
local function ownChars()
    local out = {}
    if OMQDB and type(OMQDB.tally) == "table" then for g in pairs(OMQDB.tally) do out[g] = true end end
    local me = myGuid()
    if me then out[me] = true end
    return out
end
K.OwnChars = ownChars

local function prune(s)
    local n, oldest, oldKey = 0, nil, nil
    for g, e in pairs(s.p) do
        n = n + 1
        if not oldest or (e.t or 0) < oldest then oldest, oldKey = e.t or 0, g end
    end
    if n > K.MAX and oldKey then s.p[oldKey] = nil end
end

local function entry(guid, name)
    local s = store()
    if not s or not isPlayerGuid(guid) then return nil end
    local e = s.p[guid]
    if not e then e = { k = 0, d = 0 }; s.p[guid] = e; prune(s) end
    if str(name) then e.n = name end
    e.t = time()
    return e
end

-- once: what the statistics already know (kills of me and my group, deaths by players), all own characters
function K.Seed()
    local s = store()
    if not s or s.seeded then return false end
    s.seeded = 1
    for _, b in pairs(type(OMQDB.tally) == "table" and OMQDB.tally or {}) do
        local pvp = type(b) == "table" and b.pvp
        if type(pvp) == "table" then
            for g, v in pairs(type(pvp.victims) == "table" and pvp.victims or {}) do
                if isPlayerGuid(g) and type(v) == "table" and (v.n or 0) > 0 then
                    local e = entry(g); e.k = e.k + v.n; e.t = v.t or e.t
                end
            end
            local kb = type(pvp.killedBy) == "table" and pvp.killedBy.players
            for g, v in pairs(type(kb) == "table" and kb or {}) do
                if isPlayerGuid(g) and type(v) == "table" and (v.n or 0) > 0 then
                    local e = entry(g); e.d = e.d + v.n; e.t = v.t or e.t
                end
            end
        end
    end
    return true
end

-- green, red, blue and the dads behind blue ({ name = count })
function K.Counts(guid)
    local s = store()
    if not s or not str(guid) then return 0, 0, 0, {} end
    local e = s.p[guid]
    local own = ownChars()
    local blue, who = 0, {}
    for dg, dad in pairs(s.dads) do
        local x = not own[dg] and type(dad.e) == "table" and dad.e[guid]
        if x and (x.c or 0) > 0 then
            blue = blue + x.c
            who[dad.n or "?"] = (who[dad.n or "?"] or 0) + x.c
        end
    end
    return e and e.k or 0, e and e.d or 0, blue, who
end

function K.Text(g, r, b)
    local parts = {}
    if (g or 0) > 0 then parts[#parts + 1] = ("|cff%s%d|r"):format(K.GREEN, g) end
    if (r or 0) > 0 then parts[#parts + 1] = ("|cff%s%d|r"):format(K.RED, r) end
    if (b or 0) > 0 then parts[#parts + 1] = ("|cff%s%d|r"):format(K.BLUE, b) end
    if #parts == 0 then return nil end
    return table.concat(parts, "  ")
end

----------------------------------------------------------------------
-- group
----------------------------------------------------------------------
local function mates()
    local list = {}
    local prefix, n
    if IsInRaid and plain(IsInRaid) then prefix, n = "raid", 40
    elseif IsInGroup and plain(IsInGroup) then prefix, n = "party", 4 end
    if not prefix then return list end
    local me = myGuid()
    for i = 1, n do
        local u = prefix .. i
        local g = plain(UnitGUID, u)
        if str(g) and g ~= me then list[g] = u end
    end
    return list
end
K.Mates = mates

local function near(unit)
    if not UnitPosition then return true end
    local ok, y1, x1, _, i1 = pcall(UnitPosition, "player")
    local ok2, y2, x2, _, i2 = pcall(UnitPosition, unit)
    if not (ok and ok2) then return true end
    if type(x1) ~= "number" or type(y1) ~= "number" or type(x2) ~= "number" or type(y2) ~= "number"
        or secret(x1) or secret(x2) or secret(y1) or secret(y2) then return true end
    if i1 ~= i2 then return false end
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) <= K.RANGE
end
K.Near = near

-- the group unit of a killer guid (a member or the pet of one), nil when not my group
local function groupKiller(killer, grp)
    if grp[killer] then return grp[killer] end
    for _, u in pairs(grp) do
        local pg = plain(UnitGUID, u .. "pet")
        if str(pg) and pg == killer then return u end
    end
end

----------------------------------------------------------------------
-- names of enemy players I saw (for the lists and the card)
----------------------------------------------------------------------
local names = {}
local function remember(unit)
    local g = plain(UnitGUID, unit)
    if not isPlayerGuid(g) then return nil end
    local n = plain(UnitName, unit)
    if str(n) then names[g] = n end
    return g
end
local function nameOf(guid)
    if names[guid] then return names[guid] end
    local s = store()
    local e = s and s.p[guid]
    if e and e.n then return e.n end
    if GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, n = pcall(GetPlayerInfoByGUID, guid)
        if ok and str(n) then names[guid] = n; return n end
    end
    return nil
end
K.NameOf = nameOf

----------------------------------------------------------------------
-- sending to the dads: the group over OMQ:Send, the guild right here (with its own small pacing)
----------------------------------------------------------------------
local PREFIX = "OMQ"
local guildQueue = {}
local function inGuild() return IsInGuild and plain(IsInGuild) == true end
local function toGuild(msgType, ...)
    if not inGuild() then return end
    local text = OMQ.Encode(msgType, OMQ.protocol, ...)
    if text then guildQueue[#guildQueue + 1] = text end
end
function K.FlushGuild()
    local text = table.remove(guildQueue, 1)
    if not text then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "GUILD")
        if ok and res == false then table.insert(guildQueue, 1, text) end
    end
end
K._GuildQueue = function() return guildQueue end
local function toDads(msgType, ...)
    if OMQ:GetChannel() then OMQ:Send(msgType, ...) end
    toGuild(msgType, ...)
end

-- my "who killed me" entries, newest first; only = { [guid] = true } sends just those
function K.SendList(only)
    local s = store()
    local me = myGuid()
    if not (s and me) then return 0 end
    local rows = {}
    for g, e in pairs(s.p) do
        if (e.d or 0) > 0 and (not only or only[g]) then rows[#rows + 1] = { g = g, e = e } end
    end
    table.sort(rows, function(a, b) return (a.e.t or 0) > (b.e.t or 0) end)
    local part, sent = {}, 0
    local function out()
        if #part > 0 then toDads("PK", me, clean(myName()), table.concat(part, ";")); part = {} end
    end
    for i = 1, math.min(#rows, K.SEND_MAX) do
        local r = rows[i]
        part[#part + 1] = ("%s,%d,%s"):format(r.g, r.e.d, clean(r.e.n or nameOf(r.g) or ""))
        sent = sent + 1
        if #part >= K.PART then out() end
    end
    out()
    if sent > 0 then note(("sent %d entries"):format(sent)) end
    return sent
end

local lastFull = -1000
local function sendFullSoon()
    if K.fullPending then return end
    K.fullPending = true
    C_Timer.After(5, function()
        K.fullPending = false
        if GetTime() - lastFull < 60 then return end
        lastFull = GetTime()
        K.SendList()
    end)
end
K._SendFullSoon = sendFullSoon

local heard = {}           -- dads heard this session
local function onList(fields)
    local dg, dn, list = fields[1], fields[2], fields[3]
    if not isPlayerGuid(dg) or ownChars()[dg] then return end
    local s = store()
    if not s then return end
    local dad = s.dads[dg]
    if not dad then dad = { e = {} }; s.dads[dg] = dad end
    if str(dn) then dad.n = dn end
    dad.t = time()
    for item in tostring(list or ""):gmatch("[^;]+") do
        local g, c, n = item:match("^([^,]+),(%d+),?(.*)$")
        if isPlayerGuid(g) then
            dad.e[g] = { c = tonumber(c), n = n ~= "" and n or (dad.e[g] and dad.e[g].n) }
            if n ~= "" and not names[g] then names[g] = n end
        end
    end
    if not heard[dg] then heard[dg] = true; sendFullSoon() end
    K.RefreshAll()
end
K._OnList = onList
OMQ:RegisterMessage("PK", onList)

----------------------------------------------------------------------
-- the revenge card
----------------------------------------------------------------------
local card
local cardQueue = {}
local function buildCard()
    card = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    card:SetSize(300, 64)
    card:SetPoint("TOP", UIParent, "TOP", 0, -150)
    card:SetFrameStrata("HIGH")
    if card.SetBackdrop then
        pcall(card.SetBackdrop, card, { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        pcall(card.SetBackdropColor, card, 0.05, 0.08, 0.2, 0.92)
        pcall(card.SetBackdropBorderColor, card, 0.3, 0.65, 1, 1)
    end
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(40, 40)
    card.icon:SetPoint("LEFT", card, "LEFT", 12, 0)
    card.icon:SetTexture("Interface\\Icons\\Ability_Warrior_Revenge")
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
    card.line = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.line:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
    card.line:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    card.line:SetJustifyH("LEFT")
    card.hover = false
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self) self.hover = true end)
    card:SetScript("OnLeave", function(self) self.hover = false end)
    card:SetScript("OnMouseUp", function(self) self:Hide(); self.item = nil; K.NextCard() end)
    card:Hide()
end

function K.NextCard()
    if card and card:IsShown() then return end
    local item = table.remove(cardQueue, 1)
    if not item then return end
    if not card then buildCard() end
    card.item = item
    card.title:SetText(("%s avenged you!"):format(item.by))
    local times = (item.c or 0) > 1 and (" (he killed you %d times)"):format(item.c) or ""
    card.line:SetText(("%s is dead%s"):format(item.enemy, times))
    card:SetAlpha(1)
    card:Show()
    if PlaySound then pcall(PlaySound, K.SOUND, "Master") end
    local token = {}
    card.token = token
    local function wait(left)
        if card.token ~= token or not card:IsShown() then return end
        if left <= 0 and not card.hover then card:Hide(); card.item = nil; K.NextCard(); return end
        C_Timer.After(1, function() wait(left - 1) end)
    end
    wait(K.CARD_HOLD)
end
function K.CardShown() return card ~= nil and card:IsShown() and card.item or nil end

local avenged = {}         -- enemy guid -> GetTime(), so a kill seen by two dads gives one card
local function onRevenge(fields)
    local byG, byN, eg, en, dadG = fields[1], fields[2], fields[3], fields[4], fields[5]
    if not (isPlayerGuid(eg) and str(dadG)) then return end
    if byG == myGuid() then return end
    if not ownChars()[dadG] then return end
    if avenged[eg] and GetTime() - avenged[eg] < 30 then return end
    avenged[eg] = GetTime()
    local s = store()
    local e = s and s.p[eg]
    cardQueue[#cardQueue + 1] = { by = str(byN) and byN or "A dad", enemy = str(en) and en or (nameOf(eg) or "?"), c = e and e.d or 0 }
    note(("avenged by %s: %s"):format(tostring(byN), tostring(en)))
    K.NextCard()
end
K._OnRevenge = onRevenge
OMQ:RegisterMessage("PV", onRevenge)

-- my group killed a player: every dad he killed (not here himself) hears it
local function tellDads(victim, grp, killer)
    local s = store()
    if not s then return 0 end
    local own, n = ownChars(), 0
    local vn = clean(nameOf(victim) or "")
    for dg, dad in pairs(s.dads) do
        local x = not own[dg] and type(dad.e) == "table" and dad.e[victim]
        local here = grp[dg] and near(grp[dg])
        if x and (x.c or 0) > 0 and not here and dg ~= killer then
            toDads("PV", myGuid(), clean(myName()), victim, vn, dg)
            n = n + 1
        end
    end
    return n
end

----------------------------------------------------------------------
-- kills and deaths
----------------------------------------------------------------------
function K.OnPartyKill(killer, victim)
    if not (str(killer) and isPlayerGuid(victim)) then return false end
    local me = myGuid()
    local pet = plain(UnitGUID, "pet")
    local grp = mates()
    local mine = killer == me or (str(pet) and killer == pet)
    if not mine then
        local u = groupKiller(killer, grp)
        if not u then return false end
        if not near(u) then note("group kill too far away"); return false end
        -- a dad with the addon tells the others himself
        local users = OMQ.users and OMQ.users[killer]
        if users and OMQ.IsOnline and OMQ:IsOnline(users) then K._skipTell = true end
    end
    local e = entry(victim, nameOf(victim))
    e.k = e.k + 1
    note(("kill %s (%s) -> %d"):format(tostring(e.n), mine and "me" or "group", e.k))
    if not K._skipTell then tellDads(victim, grp, killer) end
    K._skipTell = nil
    K.RefreshAll()
    return true
end

local attackers = {}       -- guid -> GetTime() of the last hit
local plates = {}          -- nameplate units shown now
K._Attackers = function() return attackers end

local function hostilePlayer(u)
    if plain(UnitIsPlayer, u) ~= true then return nil end
    if plain(UnitCanAttack, "player", u) ~= true then return nil end
    return remember(u)
end

function K.OnHit()
    local now, found = GetTime(), false
    for u in pairs(plates) do
        if plain(UnitIsUnit, u .. "target", "player") == true then
            local g = hostilePlayer(u)
            if g then attackers[g] = now; found = true end
        end
    end
    if plain(UnitIsUnit, "targettarget", "player") == true or not found then
        local g = hostilePlayer("target")
        if g then attackers[g] = now; found = true end
    end
    return found
end

function K.OnDeath()
    local now, list = GetTime(), {}
    for g, at in pairs(attackers) do
        if now - at <= K.ATTACKER_FOR then
            local e = entry(g, nameOf(g))
            e.d = e.d + 1
            list[g] = true
            note(("death by %s -> %d"):format(tostring(e.n), e.d))
        end
    end
    attackers = {}
    if next(list) then K.SendList(list); K.RefreshAll() end
    return list
end

----------------------------------------------------------------------
-- the numbers on the nameplates
----------------------------------------------------------------------
local labels = {}          -- unit -> label frame
local pool = {}
local testUntil

local function plateOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    return plain(C_NamePlate.GetNamePlateForUnit, unit)
end
local function healthBar(plate)
    local ok, hb = pcall(function()
        local uf = plate.UnitFrame
        if not uf then return nil end
        return uf.healthBar or uf.HealthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar) or uf
    end)
    if ok and type(hb) == "table" then return hb end
    return plate
end

local function newLabel()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(60, 20)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pcall(f.text.SetFont, f.text, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", K.FONT_SIZE, "OUTLINE")
    f.text:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text:SetJustifyH("LEFT")
    f:Hide()
    return f
end

local function release(unit)
    local f = labels[unit]
    if not f then return end
    labels[unit] = nil
    f:Hide()
    pcall(f.SetParent, f, UIParent)
    pool[#pool + 1] = f
end

local function attach(unit, text)
    local plate = plateOf(unit)
    if not plate then release(unit); return false end
    local f = labels[unit] or table.remove(pool) or newLabel()
    labels[unit] = f
    local ok = pcall(function()
        f:SetParent(plate)
        f:ClearAllPoints()
        f:SetPoint("LEFT", healthBar(plate), "RIGHT", K.GAP, 0)
    end)
    if not ok then release(unit); return false end
    if f.SetIgnoreParentAlpha then pcall(f.SetIgnoreParentAlpha, f, true) end
    local lvl = plain(plate.GetFrameLevel, plate)
    if type(lvl) == "number" then pcall(f.SetFrameLevel, f, lvl + 5) end
    f.text:SetText(text)
    f:Show()
    return true
end

function K.Paint(unit)
    if not K.Enabled() then release(unit); return false end
    local g = hostilePlayer(unit)
    if not g then release(unit); return false end
    local text = K.Text(K.Counts(g))
    if not text then release(unit); return false end
    return attach(unit, text)
end

function K.RefreshAll()
    for u in pairs(plates) do K.Paint(u) end
    for u in pairs(labels) do if not plates[u] and u ~= "target" then release(u) end end
end

function K.LabelOf(unit) return labels[unit] end
function K.Labels() local n = 0; for _ in pairs(labels) do n = n + 1 end; return n end

-- the unit tooltip of an enemy player: the numbers and the dads behind blue
function K.TooltipLines(unit)
    if not K.Enabled() then return nil end
    local g = hostilePlayer(unit)
    if not g then return nil end
    local k, d, b, who = K.Counts(g)
    if k + d + b == 0 then return nil end
    local lines = {}
    if k > 0 then lines[#lines + 1] = ("|cff%sKilled by you or your group: %d|r"):format(K.GREEN, k) end
    if d > 0 then lines[#lines + 1] = ("|cff%sKilled you: %d|r"):format(K.RED, d) end
    if b > 0 then
        local parts = {}
        for n, c in pairs(who) do parts[#parts + 1] = ("%s %d"):format(n, c) end
        table.sort(parts)
        lines[#lines + 1] = ("|cff%sKilled dads: %s|r"):format(K.BLUE, table.concat(parts, ", "))
    end
    return lines
end
local function onTooltip(tt)
    if not tt or tt ~= GameTooltip then return end
    local lines = K.TooltipLines("mouseover")
    if not lines then return end
    for _, l in ipairs(lines) do tt:AddLine(l) end
    if tt.Show then tt:Show() end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt) pcall(onTooltip, tt) end)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) pcall(onTooltip, tt) end)
end

function K.Test()
    testUntil = GetTime() + 10
    local unit = plateOf("target") and "target" or nil
    if unit then
        attach("target", K.Text(3, 1, 2))
    else
        cardQueue[#cardQueue + 1] = { by = myName(), enemy = "Testplayer", c = 2 }
        K.NextCard()
    end
    return unit ~= nil
end

----------------------------------------------------------------------
-- driver
----------------------------------------------------------------------
local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, dt)
    since = since + (dt or 0)
    if since < 0.5 then return end
    since = 0
    if #guildQueue > 0 then K.FlushGuild() end
    if testUntil and GetTime() >= testUntil then
        testUntil = nil
        if labels.target then release("target") end
        K.RefreshAll()
    end
end)

for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PARTY_KILL", "PLAYER_DEAD", "UNIT_COMBAT", "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED" }) do
    pcall(driver.RegisterEvent, driver, e)
end

local entered = false
driver:SetScript("OnEvent", function(_, event, a1, a2)
    if not OMQ.db then return end
    if event == "PARTY_KILL" then
        if K.Enabled() then K.OnPartyKill(a1, a2) end
    elseif event == "UNIT_COMBAT" then
        if a1 == "player" and not secret(a2) and a2 == "WOUND" then K.OnHit() end
    elseif event == "PLAYER_DEAD" then
        K.OnDeath()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if str(a1) then plates[a1] = true; remember(a1); K.Paint(a1) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if str(a1) then plates[a1] = nil; release(a1) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        remember("target")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not entered then
            entered = true
            K.Seed()
            C_Timer.After(10, function() lastFull = GetTime(); K.SendList() end)
        end
    end
end)

-- a dad joined my group: he gets my list
OMQ:On("USER_JOINED", function() sendFullSoon() end)

function K.SetEnabled(on)
    OMQ.db.options.pvpCount = on and true or false
    if on then K.RefreshAll() else for u in pairs(labels) do release(u) end end
end

OMQ:RegisterCommand("pvp", function(arg)
    arg = (arg or ""):lower():match("^%s*(%S*)") or ""
    if arg == "on" or arg == "off" then
        K.SetEnabled(arg == "on")
        OMQ:Print("PvP numbers: " .. arg)
        OMQ:Fire("SETTINGS_CHANGED")
    elseif arg == "test" then
        if K.Test() then OMQ:Print("PvP numbers: sample 3 / 1 / 2 on the target's nameplate for 10 seconds")
        else OMQ:Print("PvP numbers: no nameplate on the target - here is the revenge card instead") end
    elseif arg == "list" then
        local s = store()
        local rows = {}
        for g, e in pairs(s and s.p or {}) do
            local k, d, b = K.Counts(g)
            if k + d + b > 0 then rows[#rows + 1] = { n = e.n or nameOf(g) or g, k = k, d = d, b = b } end
        end
        table.sort(rows, function(a, b) return a.k + a.d + a.b > b.k + b.d + b.b end)
        OMQ:Print(("PvP numbers: %d players (green you/group killed, red killed you, blue killed dads)"):format(#rows))
        for i = 1, math.min(#rows, 20) do
            local r = rows[i]
            print(("  %s: |cff%s%d|r |cff%s%d|r |cff%s%d|r"):format(r.n, K.GREEN, r.k, K.RED, r.d, K.BLUE, r.b))
        end
    elseif arg == "debug" then
        local s = store()
        local np, nd = 0, 0
        for _ in pairs(s and s.p or {}) do np = np + 1 end
        for _ in pairs(s and s.dads or {}) do nd = nd + 1 end
        local na = 0
        for _ in pairs(plates) do na = na + 1 end
        OMQ:Print(("option %s, players %d, dad lists %d, nameplates %d, labels %d, guild %s, guild queue %d"):format(
            K.Enabled() and "on" or "off", np, nd, na, K.Labels(), tostring(inGuild()), #guildQueue))
        if #log == 0 then print("  nothing seen yet") else for i = #log, 1, -1 do print("  " .. log[i]) end end
    else
        OMQ:Print("/omq pvp on | off - numbers right of enemy players' nameplates (now: " .. (K.Enabled() and "on" or "off") .. ")")
        OMQ:Print("/omq pvp test - a sample; /omq pvp list - the players; /omq pvp debug - what was seen")
    end
end)
