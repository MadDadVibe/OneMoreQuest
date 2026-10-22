-- One More Quest: the pet basics (decision 241, improvement 18 "the basics every class forgets")
-- Out of combat, alive, not mounted and not on a flight:
--   hunter:  no pet out           -> "Call your pet"   (click casts Call Pet)
--            pet dead             -> "Revive your pet" (click casts Revive Pet)
--            pet unhappy          -> "Feed your pet"   (click casts Feed Pet, then click the food)
--   warlock: no demon out         -> up to three cards "Summon <demon>": the last three demons he summoned
--                                    (kept per character), filled up with Imp, Voidwalker, Succubus; only learned ones
--                                    (decision 340)
-- Only spells the character knows are asked for. Paladin auras and the shaman's Lightning Shield are
-- buff groups in Data/Buffs.lua; aspects, armors, imbues and poisons were there already.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local P = {}
OMQ.PetBasics = P

P.CALL, P.REVIVE, P.FEED = 883, 982, 6991
P.DEMONS = { 688, 697, 712 }     -- the defaults when nothing was summoned yet: Imp, Voidwalker, Succubus (Incubus)
P.ALL_DEMONS = { 688, 697, 712, 691, 30146 }        -- also Felhunter and Felguard count as used demons
P.KEEP = 3
local ALL = {}
for _, id in ipairs(P.ALL_DEMONS) do ALL[id] = true end

local function knows(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function icon(id)
    return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or "Interface\\Icons\\Ability_Hunter_BeastCall"
end
local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function flag(fn, ...)
    if not fn then return false end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then return nil end
    return v and true or false
end

-- the last demons summoned by this character, most recent first (saved with the alerts, per GUID)
local function recentList(create)
    local guid = UnitGUID and UnitGUID("player")
    if not (guid and OMQ.db) then return nil end
    OMQ.db.alerts = OMQ.db.alerts or {}
    local a = OMQ.db.alerts
    a.demons = a.demons or {}
    if create and not a.demons[guid] then a.demons[guid] = {} end
    return a.demons[guid]
end

function P.Remember(id)
    if not ALL[id] then return false end
    local list = recentList(true)
    if not list then return false end
    for i = #list, 1, -1 do if list[i] == id then table.remove(list, i) end end
    table.insert(list, 1, id)
    while #list > P.KEEP do table.remove(list) end
    return true
end

-- the demons to offer: the recent ones, then the defaults, only the learned, at most three
function P.Offer()
    local out, seen = {}, {}
    local function add(id)
        if #out < P.KEEP and not seen[id] and knows(id) then seen[id] = true; out[#out + 1] = id end
    end
    for _, id in ipairs(recentList(false) or {}) do add(id) end
    for _, id in ipairs(P.DEMONS) do add(id) end
    return out
end

local COLOR = { 0.6, 0.8, 0.4 }
local function card(key, title, sub, spell)
    local n = spellName(spell)
    if not n then return nil end
    return { key = key, title = title, sub = sub, text = title, tag = "PET", cast = n, unit = "player",
             icon = icon(spell), color = COLOR }
end

function P.Check()
    if InCombatLockdown and InCombatLockdown() then return "keep" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
    if (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player")) then return nil end
    local _, class = UnitClass("player")
    local exists = flag(UnitExists, "pet")
    if exists == nil then return nil end               -- not readable: say nothing
    if class == "HUNTER" and knows(P.CALL) then
        if not exists then
            return { card("pet:call", "Call your pet", "Your pet is not with you", P.CALL) }
        end
        local dead = flag(UnitIsDead, "pet")
        if dead and knows(P.REVIVE) then
            return { card("pet:revive", "Revive your pet", "Your pet is dead", P.REVIVE) }
        end
        if GetPetHappiness and knows(P.FEED) then
            local ok, happy = pcall(GetPetHappiness)
            if ok and happy == 1 then
                return { card("pet:feed", "Feed your pet", "It is unhappy and fights badly - click, then the food", P.FEED) }
            end
        end
    elseif class == "WARLOCK" and not exists then
        local out = {}
        for _, id in ipairs(P.Offer()) do
            local c = card("pet:demon:" .. id, spellName(id) or "Summon your demon", "No demon at your side", id)
            if c then out[#out + 1] = c end
        end
        if #out > 0 then return out end
    end
    return nil
end

M:Register({ id = "pet", name = "Pet basics: call, revive, feed, summon", check = function()
    local r = P.Check()
    if type(r) == "table" and #r == 0 then return nil end
    return r
end })

-- every demon the warlock summons is remembered (also from the action bar)
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
watcher:SetScript("OnEvent", function(_, _, unit, _, spellId)
    if unit == "player" and type(spellId) == "number" and not isSecret(spellId) then P.Remember(spellId) end
end)
