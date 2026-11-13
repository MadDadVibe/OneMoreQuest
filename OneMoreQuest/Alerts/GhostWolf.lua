-- One More Quest: Ghost Wolf reminder for shamans with an instant Ghost Wolf (decision 582)
-- A shaman whose Ghost Wolf has no cast time (read from the spell info, so no talent name is
-- needed and German and English clients behave the same) gets a card "Ghost Wolf" while running:
--   * running longer than N seconds (default 5) without a fight, or
--   * more than N yards (default 40) away from the nearest dad (positions OMQ shares in the group).
-- Solo only the running time counts. Never in combat, in dungeons/instances, mounted, on a flight,
-- swimming, dead or already in wolf form. The card goes once the shaman stands still for 2 s, enters
-- combat or is a wolf. A left click casts Ghost Wolf; right click / shift+right click as on every card.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local G = {}
OMQ.GhostWolf = G

G.SPELL = 2645                   -- Ghost Wolf
G.FORM_ID = 16                   -- GetShapeshiftFormID() in Ghost Wolf
G.KEY = "ghostwolf"
G.STOP_GRACE = 2                 -- seconds standing still before the run counts as over
G.DEFAULT_RUN, G.MIN_RUN, G.MAX_RUN = 5, 2, 30
G.DEFAULT_DIST, G.MIN_DIST, G.MAX_DIST = 40, 10, 100
G.runSince = nil                 -- GetTime() the current run started (nil: not running)
G.lastMove = nil                 -- GetTime() of the last check that saw me moving
local COLOR = { 0.35, 0.6, 0.95 }
local ICON = "Interface\\Icons\\Spell_Nature_SpiritWolf"

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function plain(v) return v ~= nil and not isSecret(v) end
local function now() return GetTime and GetTime() or 0 end
local function call(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then return nil end
    return v
end

local function opts()
    local o = OMQ.db and OMQ.db.options
    if not o then return {} end
    o.ghostWolf = o.ghostWolf or {}
    return o.ghostWolf
end
local function clamp(v, lo, hi, def)
    v = tonumber(v) or def
    return math.max(lo, math.min(hi, v))
end
function G.RunSeconds() return clamp(opts().run, G.MIN_RUN, G.MAX_RUN, G.DEFAULT_RUN) end
function G.Distance() return clamp(opts().dist, G.MIN_DIST, G.MAX_DIST, G.DEFAULT_DIST) end
function G.SetRunSeconds(v) opts().run = clamp(v, G.MIN_RUN, G.MAX_RUN, G.DEFAULT_RUN) end
function G.SetDistance(v) opts().dist = clamp(v, G.MIN_DIST, G.MAX_DIST, G.DEFAULT_DIST) end

local function knows(id)
    if IsPlayerSpell and call(IsPlayerSpell, id) then return true end
    if IsSpellKnown and call(IsSpellKnown, id) then return true end
    return false
end
function G.SpellName()
    local n = (C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, G.SPELL))
        or (GetSpellInfo and call(GetSpellInfo, G.SPELL))
    return type(n) == "string" and n or nil
end

-- the cast time of Ghost Wolf in milliseconds (talents included), or nil when unknown
function G.CastTime()
    if C_Spell and C_Spell.GetSpellInfo then
        local info = call(C_Spell.GetSpellInfo, G.SPELL)
        if type(info) == "table" and plain(info.castTime) and type(info.castTime) == "number" then return info.castTime end
    end
    if GetSpellInfo then
        local ok, _, _, _, ct = pcall(GetSpellInfo, G.SPELL)
        if ok and plain(ct) and type(ct) == "number" then return ct end
    end
    return nil
end

function G.IsInstantWolf()
    local _, class = UnitClass("player")
    if class ~= "SHAMAN" or not knows(G.SPELL) then return false end
    return G.CastTime() == 0
end

function G.InWolf()
    local id = GetShapeshiftFormID and call(GetShapeshiftFormID)
    if id == G.FORM_ID then return true end
    for i = 1, 40 do
        local a, hidden = OMQ.ReadAura("player", i, "HELPFUL")
        if hidden or not a then break end
        if plain(a.spellId) and a.spellId == G.SPELL then return true end
    end
    return false
end

function G.Moving()
    if GetUnitSpeed then
        local s = call(GetUnitSpeed, "player")
        if type(s) == "number" then return s > 0 end
    end
    return call(IsPlayerMoving) and true or false
end

-- yards to the nearest dad with a fresh position in my instance; nil: nobody known
function G.NearestDad()
    local A, me = OMQ.Arrow, OMQ.GetSelf and OMQ:GetSelf()
    if not (A and A.DistanceTo and me and OMQ.users) then return nil end
    local best
    for guid, u in pairs(OMQ.users) do
        if guid ~= me.guid and u.pos and not u.pos.dead and not u.pos.taxi
            and (not OMQ.IsOnline or OMQ:IsOnline(u)) then
            local d = A:DistanceTo(guid)
            if d and (not best or d < best) then best = d end
        end
    end
    return best
end

local function reset() G.runSince, G.lastMove = nil, nil end

local function blocked()
    if UnitIsDeadOrGhost and call(UnitIsDeadOrGhost, "player") then return true end
    if IsMounted and call(IsMounted) then return true end
    if UnitOnTaxi and call(UnitOnTaxi, "player") then return true end
    if IsSwimming and call(IsSwimming) then return true end
    if IsInInstance and call(IsInInstance) then return true end
    return false
end

-- why the card shows: "run", "far" or nil
function G.Reason()
    if not G.IsInstantWolf() then reset(); return nil end
    if blocked() or G.InWolf() then reset(); return nil end
    local t = now()
    if G.Moving() then
        G.runSince = G.runSince or t
        G.lastMove = t
    elseif not G.lastMove or t - G.lastMove >= G.STOP_GRACE then
        reset(); return nil
    end
    local d = G.NearestDad()
    if d and d > G.Distance() then return "far", d end
    if t - G.runSince >= G.RunSeconds() then return "run" end
    return nil
end

function G.Card()
    local why, d = G.Reason()
    if not why then return nil end
    local name = G.SpellName() or "Ghost Wolf"
    local sub = why == "far" and string.format("%d yd to the next dad - left click: %s", math.floor(d + 0.5), name)
        or ("Left click: " .. name)
    return {
        key = G.KEY, text = name, title = name, sub = sub,
        tag = "SHAMAN", icon = ICON, color = COLOR,
        cast = name, unit = "player",
        tipLines = { "You are running - " .. name .. " is instant for you." },
    }
end

function G.Check()
    -- in combat the cards are hidden anyway; the run starts again after the fight
    if InCombatLockdown and InCombatLockdown() then reset(); return "keep" end
    local c = G.Card()
    return c and { c } or nil
end

local watch = CreateFrame("Frame")
pcall(watch.RegisterEvent, watch, "PLAYER_REGEN_DISABLED")
watch:SetScript("OnEvent", reset)

M:Register({ id = "ghostwolf", name = "Shaman: Ghost Wolf while running", check = G.Check })
