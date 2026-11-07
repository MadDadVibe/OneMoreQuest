-- One More Quest: buff back a player who buffed me in passing (decision 435)
-- A player outside the group casts a buff on me: a card "Buff back <Name>" comes up. A left click casts my
-- class's main buff on him (priest Fortitude, mage Arcane Intellect, druid Mark of the Wild, paladin a
-- Blessing); a right click puts the card away. Only for classes with such a buff, only out of a fight
-- (the card frame is hidden in a fight), at most two cards, each for a minute after the buff (or after
-- the end of the fight it came in). The card goes once my cast went out or he carries my buff already.
-- The dads of the group are left out: the "Missing buffs" cards look after them.
-- Seen through the new aura on me (UNIT_AURA addedAuras): its caster unit (name plate, mouseover, target)
-- names the player. Never the combat log: on WoW Forever already registering it brings the game's
-- "blocked" popup (decision 435 fix, see the combat log probe of v0.16.4).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local B = {}
OMQ.BuffBack = B

B.KEEP = 60                       -- seconds a card stays after the buff
B.MAX = 2                         -- at most two cards at a time, the newest
local COLOR = { 0.95, 0.80, 0.30 }
-- classes without mana get no Arcane Intellect, and no Blessing of Wisdom
local NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, DEMONHUNTER = true }
local CASTER = { MAGE = true, PRIEST = true, WARLOCK = true }
-- first rank ids; the rank is picked for his level when it is known
local KINGS, WISDOM, MIGHT = 20217, 19742, 19740
local MAIN = {
    PRIEST = function() return 1243 end,                                     -- Power Word: Fortitude
    MAGE = function(cls) if not NO_MANA[cls or ""] then return 1459 end end, -- Arcane Intellect
    DRUID = function() return 1126 end,                                      -- Mark of the Wild
    PALADIN = function(cls, knows)
        if knows(KINGS) then return KINGS end
        if CASTER[cls or ""] and knows(WISDOM) then return WISDOM end
        return MIGHT
    end,
}
B.MAIN = MAIN

local pending = {}                -- guid -> { guid, name, spell, t, class, level }
local combatEnd = -1000

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return GetTime and GetTime() or 0 end
local function plain(v) return v ~= nil and not isSecret(v) end
local function knows(id)
    if IsPlayerSpell then return IsPlayerSpell(id) and true or false end
    if IsSpellKnown then return IsSpellKnown(id) and true or false end
    return false
end
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellInfo then return select(3, GetSpellInfo(id)) end
end
local function myClass() local _, c = UnitClass("player"); return c end
local function short(name) return type(name) == "string" and (name:match("^([^%-]+)") or name) or "?" end

-- my main buff for a player of this class: spell id, or nil (no such buff for my class, not learned)
function B.MainBuff(targetClass)
    local f = MAIN[myClass() or ""]
    local id = f and f(targetClass, knows)
    if id and knows(id) then return id end
end

-- a unit token for the player right now (no mouseover: that is the card under the mouse at the click)
local function tokens()
    local t = { "target", "focus" }
    for i = 1, 4 do t[#t + 1] = "party" .. i end
    for i = 1, 40 do t[#t + 1] = "raid" .. i end
    for i = 1, 40 do t[#t + 1] = "nameplate" .. i end
    return t
end
local TOKENS = tokens()
function B.UnitOf(guid)
    if not (guid and UnitGUID) then return nil end
    for _, u in ipairs(TOKENS) do
        local g = UnitGUID(u)
        if plain(g) and g == guid then return u end
    end
end

-- a dad of my group (party or raid): left to the "Missing buffs" cards
local function inGroup(guid)
    for i = 1, 4 do
        local g = UnitGUID and UnitGUID("party" .. i)
        if plain(g) and g == guid then return true end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local g = UnitGUID and UnitGUID("raid" .. i)
            if plain(g) and g == guid then return true end
        end
    end
    return false
end

-- does the unit carry any rank of this buff? true / false, nil when it cannot be read
local function carries(unit, castId)
    local want = spellName(castId)
    if not (want and OMQ.ReadAura) then return nil end
    for i = 1, 40 do
        local a, hidden = OMQ.ReadAura(unit, i, "HELPFUL")
        if hidden then return nil end
        if not a then return false end
        if isSecret(a.name) then return nil end
        if a.name == want then return true end
    end
    return false
end

-- a buff from another player arrived on me
function B.Note(guid, name, spell)
    if not (plain(guid) and plain(name)) or type(guid) ~= "string" or not guid:find("^Player%-") then return end
    local me = UnitGUID and UnitGUID("player")
    if guid == me or inGroup(guid) then return end
    local cls, level
    if GetPlayerInfoByGUID then
        local ok, _, c = pcall(GetPlayerInfoByGUID, guid)
        if ok and plain(c) then cls = c end
    end
    local u = B.UnitOf(guid)
    if u then
        local l = UnitLevel and UnitLevel(u)
        if plain(l) and type(l) == "number" and l > 0 then level = l end
        if not cls and UnitClass then local _, c = UnitClass(u); if plain(c) then cls = c end end
    end
    if not B.MainBuff(cls) then return end
    local p = pending[guid] or {}
    p.guid, p.name, p.spell, p.t = guid, name, plain(spell) and spell or p.spell, now()
    p.class, p.level = cls or p.class, level or p.level
    pending[guid] = p
    if M.Evaluate and not (InCombatLockdown and InCombatLockdown()) then M:Evaluate() end
end

-- my cast went out on a name: that card is done
function B.Sent(target, spellId)
    if not plain(target) or type(target) ~= "string" then return end
    for guid, p in pairs(pending) do
        local id = B.MainBuff(p.class)
        local same = not spellId or not plain(spellId) or (id and spellName(id) == spellName(spellId))
        if same and (p.name == target or short(p.name) == short(target)) then pending[guid] = nil end
    end
end

function B.Reset() pending = {}; combatEnd = -1000 end
function B._Pending() return pending end

-- the cards
function B.Check()
    if InCombatLockdown and InCombatLockdown() then return "keep" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
    local list = {}
    for guid, p in pairs(pending) do
        if now() - math.max(p.t, combatEnd) > B.KEEP then
            pending[guid] = nil
        else
            list[#list + 1] = p
        end
    end
    table.sort(list, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.guid < b.guid end)
    local out = {}
    for _, p in ipairs(list) do
        local id = B.MainBuff(p.class)
        local u = B.UnitOf(p.guid)
        if u and UnitLevel then
            local l = UnitLevel(u)
            if plain(l) and type(l) == "number" and l > 0 then p.level = l end
        end
        if id and u and carries(u, id) == true then
            pending[p.guid] = nil                      -- he has it already (my cast, or somebody else's)
        elseif id then
            local cast = (M.CastForLevel and M.CastForLevel(id, p.level)) or spellName(id)
            local buff = spellName(id) or "your buff"
            local who = short(p.name)
            local a = {
                key = "bback:" .. p.guid, tag = "BUFF BACK", color = COLOR, icon = spellIcon(id),
                title = "Buff back " .. who, text = "Buff back " .. who,
                sub = (p.spell and (p.spell .. " from " .. who) or (who .. " buffed you")) .. " - left click: " .. buff,
                tipLines = { "Buff back " .. who, (p.spell and (who .. " gave you " .. p.spell) or (who .. " buffed you")) .. ".",
                             "Left click: " .. buff .. " on " .. who .. ".", "Right click: away." },
            }
            if u == "target" then
                a.cast, a.unit = cast, "target"
            else
                -- target him by his full name, cast, back to the old target; a cast on his name plate unit
                -- did nothing on WoW Forever (fix row 439)
                a.macro = "/target " .. p.name .. "\n/cast [@target,help,nodead] " .. cast .. "\n/targetlasttarget"
            end
            out[#out + 1] = a
            if #out >= B.MAX then break end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_AURA", "UNIT_SPELLCAST_SENT", "PLAYER_REGEN_ENABLED" }) do pcall(ev.RegisterEvent, ev, e) end

-- the new aura names its caster unit (when the game tells it)
function B.FromAura(unit, info)
    if unit ~= "player" or type(info) ~= "table" or info.isFullUpdate then return end
    for _, a in ipairs(info.addedAuras or {}) do
        local src = a.sourceUnit
        if plain(src) and type(src) == "string" and plain(a.isHelpful) and a.isHelpful
            and UnitIsPlayer and UnitIsPlayer(src) and not (UnitIsUnit and UnitIsUnit(src, "player")) then
            local g = UnitGUID(src)
            local n, n2 = UnitName(src)
            -- Forever names have two parts ("Vorname Nachname"): /target needs both (fix row 439)
            if plain(n) and plain(n2) and type(n2) == "string" and n2 ~= "" then n = n .. " " .. n2 end
            if plain(g) and plain(n) then B.Note(g, n, plain(a.name) and a.name or nil) end
        end
    end
end

ev:SetScript("OnEvent", function(_, event, ...)
    local args = { ... }
    local ok, err = pcall(function()
        if event == "UNIT_AURA" then
            B.FromAura(args[1], args[2])
        elseif event == "UNIT_SPELLCAST_SENT" then
            if args[1] == "player" then
                B.Sent(args[2], args[4])
                if M.Evaluate then M:Evaluate() end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            combatEnd = now()
        end
    end)
    if not ok then OMQ:Error("buffback " .. event, err) end
end)

M:Register({ id = "buffback", name = "Buff back a player who buffed you", check = function()
    local r = B.Check()
    if type(r) == "table" and #r == 0 then return nil end
    return r
end })
