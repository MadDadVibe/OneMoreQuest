-- One More Quest: the pet basics (decision 241, improvement 18 "the basics every class forgets")
-- Out of combat, alive, not mounted and not on a flight:
--   hunter:  no pet out           -> "Call your pet"   (click casts Call Pet)
--            pet dead             -> "Revive your pet" (click casts Revive Pet)
--            pet unhappy          -> "Feed your pet"   (click casts Feed Pet, then click the food)
--   warlock: no demon out         -> "Summon your demon" (click summons the Voidwalker, before it the Imp)
-- Only spells the character knows are asked for. Paladin auras and the shaman's Lightning Shield are
-- buff groups in Data/Buffs.lua; aspects, armors, imbues and poisons were there already.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local P = {}
OMQ.PetBasics = P

P.CALL, P.REVIVE, P.FEED = 883, 982, 6991
P.DEMONS = { 697, 688 }          -- Voidwalker first, then Imp

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
        for _, id in ipairs(P.DEMONS) do
            if knows(id) then
                return { card("pet:demon", "Summon your demon", "No demon at your side", id) }
            end
        end
    end
    return nil
end

M:Register({ id = "pet", name = "Pet basics: call, revive, feed, summon", check = function()
    local r = P.Check()
    if type(r) == "table" and #r == 0 then return nil end
    return r
end })
