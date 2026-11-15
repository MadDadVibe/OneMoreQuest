-- One More Quest: Shadowform reminder for shadow priests (decision 605)
-- A priest who knows Shadowform (spell ID, so German and English clients behave the same) gets a card
-- "Shadowform" out of combat while he is not in Shadowform, also in dungeons. Not while dead or a ghost,
-- mounted, on a flight or eating/drinking (the cast would end the meal). After a fight the card waits
-- 3 seconds, so leaving the form for a quick heal does not pop it up at once. A left click casts
-- Shadowform; right click / shift+right click as on every card.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local SF = {}
OMQ.Shadowform = SF

SF.SPELL = 15473                 -- Shadowform
SF.FORM_ID = 28                  -- GetShapeshiftFormID() in Shadowform
SF.KEY = "shadowform"
SF.AFTER_COMBAT = 3              -- seconds after a fight before the card may show
SF.combatEnd = nil               -- GetTime() the last fight ended
-- food and drink buffs (classic foods and waters); compared by spell ID and by their client names
SF.MEAL_SPELLS = { 430, 431, 432, 1133, 1135, 1137, 22734, 24355, 25696, 26475, 29007,
    433, 434, 435, 1127, 1129, 1131, 2639, 5004, 5005, 5006, 5007, 18229, 18230, 18231,
    18232, 18233, 18234, 24005, 24707, 25700, 25886, 26474, 29073 }
local COLOR = { 0.55, 0.3, 0.8 }
local ICON = "Interface\\Icons\\Spell_Shadow_Shadowform"

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function plain(v) return v ~= nil and not isSecret(v) end
local function now() return GetTime and GetTime() or 0 end
local function call(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then return nil end
    return v
end

local function spellName(id)
    local n = (C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, id))
        or (GetSpellInfo and call(GetSpellInfo, id))
    return type(n) == "string" and n or nil
end
function SF.SpellName() return spellName(SF.SPELL) end

function SF.Knows()
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return false end
    if IsPlayerSpell and call(IsPlayerSpell, SF.SPELL) then return true end
    if IsSpellKnown and call(IsSpellKnown, SF.SPELL) then return true end
    return false
end

local mealIds, mealNames
local function meals()
    if not mealIds then
        mealIds = {}
        for _, id in ipairs(SF.MEAL_SPELLS) do mealIds[id] = true end
    end
    if not mealNames or not next(mealNames) then
        mealNames = {}
        for _, id in ipairs(SF.MEAL_SPELLS) do
            local n = spellName(id)
            if n then mealNames[n] = true end
        end
    end
    return mealIds, mealNames
end

-- in Shadowform, eating or drinking (one pass over my buffs); nil when the buffs cannot be read
local function readBuffs()
    local inForm, eating = false, false
    local id = GetShapeshiftFormID and call(GetShapeshiftFormID)
    if id == SF.FORM_ID then inForm = true end
    local ids, names = meals()
    for i = 1, 40 do
        local a, hidden = OMQ.ReadAura("player", i, "HELPFUL")
        if hidden then return nil end
        if not a then break end
        local sid = plain(a.spellId) and a.spellId or nil
        if sid == SF.SPELL then inForm = true end
        if (sid and ids[sid]) or (plain(a.name) and names[a.name]) then eating = true end
    end
    return inForm, eating
end

function SF.InForm() return (readBuffs()) end

local function blocked()
    if UnitIsDeadOrGhost and call(UnitIsDeadOrGhost, "player") then return true end
    if IsMounted and call(IsMounted) then return true end
    if UnitOnTaxi and call(UnitOnTaxi, "player") then return true end
    return false
end

-- should the card show? true or false
function SF.Missing()
    if not SF.Knows() or blocked() then return false end
    if SF.combatEnd and now() - SF.combatEnd < SF.AFTER_COMBAT then return false end
    local inForm, eating = readBuffs()
    if inForm == nil then return false end
    return not inForm and not eating
end

function SF.Card()
    if not SF.Missing() then return nil end
    local name = SF.SpellName() or "Shadowform"
    return {
        key = SF.KEY, text = name, title = name, sub = "Left click: " .. name,
        tag = "PRIEST", icon = ICON, color = COLOR,
        cast = name, unit = "player",
        tipLines = { "You are not in " .. name .. "." },
    }
end

function SF.Check()
    -- in combat the cards are hidden anyway
    if InCombatLockdown and InCombatLockdown() then return "keep" end
    -- an empty list (not nil) tells the manager the problem is gone, so a card clicked away comes back next time
    local c = SF.Card()
    return { c }
end

local watch = CreateFrame("Frame")
pcall(watch.RegisterEvent, watch, "PLAYER_REGEN_ENABLED")
watch:SetScript("OnEvent", function() SF.combatEnd = now() end)

M:Register({ id = "shadowform", name = "Priest: Shadowform missing", check = SF.Check })
