-- One More Quest: item score per class and role (decision 200)
-- Every stat of an item gets a weight for the class and role of the wearer; the weighted sum is
-- the score. The main stat of the role is worth 1, so "+13" means about as good as 13 points of
-- the main stat more. Used in the dads' columns of Alt on an item (Compare.lua).
--
-- Where the stats come from:
--  1. the game's item stats (C_Item.GetItemStats): primary stats, armour, weapon DPS and whatever
--     the client reports of the rest;
--  2. the "Equip:" lines of the item tooltip, for what the stats leave out in the classic game:
--     spell damage and healing, healing, damage of one school, hit, spell hit, critical strike,
--     attack power, mana per 5 seconds, defense, dodge, parry, block. Read by key words in English
--     and German, so both clients work.
--
-- The weights are leveling values from the classic stat conversions (e.g. 1 strength = 2 attack
-- power for warriors, 14 attack power = 1 weapon DPS, 1% hit or crit worth 10 to 12 main stat
-- points). WoW Forever has one critical strike stat for melee and spells. They are a starting
-- point and can be tuned here.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local SC = {}
OMQ.Score = SC

-- roles per class, the first is the default
SC.ROLES = {
    WARRIOR = { "damage", "tank" },
    PALADIN = { "damage", "heal", "tank" },
    HUNTER  = { "damage" },
    ROGUE   = { "damage" },
    PRIEST  = { "damage", "heal" },
    MAGE    = { "damage" },
    WARLOCK = { "damage" },
    SHAMAN  = { "damage", "caster", "heal" },
    DRUID   = { "damage", "tank", "caster", "heal" },
}
SC.ROLE_LABEL = { damage = "Damage", tank = "Tank", heal = "Healer", caster = "Caster damage" }
-- spec icons for the "Preferred Role" picker (decision 203)
local IC = "Interface\\Icons\\"
SC.ROLE_ICON = {
    WARRIOR = { damage = "Ability_Warrior_InnerRage", tank = "Ability_Warrior_DefensiveStance" },
    PALADIN = { damage = "Spell_Holy_AuraOfLight", heal = "Spell_Holy_HolyBolt", tank = "Spell_Holy_DevotionAura" },
    HUNTER  = { damage = "Ability_Marksmanship" },
    ROGUE   = { damage = "Ability_BackStab" },
    PRIEST  = { damage = "Spell_Shadow_ShadowWordPain", heal = "Spell_Holy_Renew" },
    MAGE    = { damage = "Spell_Frost_FrostBolt02" },
    WARLOCK = { damage = "Spell_Shadow_ShadowBolt" },
    SHAMAN  = { damage = "Spell_Nature_LightningShield", caster = "Spell_Nature_Lightning", heal = "Spell_Nature_MagicImmunity" },
    DRUID   = { damage = "Ability_Druid_CatForm", tank = "Ability_Racial_BearForm", caster = "Spell_Nature_StarFall",
                heal = "Spell_Nature_HealingTouch" },
}
function SC.RoleIcon(class, role)
    local r = SC.RoleOf(class, role)
    local t = r and SC.ROLE_ICON[class or ""]
    return t and t[r] and ("Interface\\Icons\\" .. t[r]) or nil
end
-- what "damage" means for the hybrids, for the option text
SC.ROLE_HINT = {
    WARRIOR = { damage = "Arms / Fury" }, PALADIN = { damage = "Retribution" }, PRIEST = { damage = "Shadow" },
    SHAMAN = { damage = "Enhancement", caster = "Elemental" }, DRUID = { damage = "Cat", tank = "Bear", caster = "Balance" },
}

-- weights: main stat = 1. DPS_M / DPS_R: weapon damage per second of a melee / ranged weapon.
local W = {}
SC.WEIGHTS = W
W.WARRIOR = {
    damage = { STR = 1, AGI = 0.8, STA = 0.4, AP = 0.5, HIT = 10, CRIT = 12, HASTE = 8, DPS_M = 7, DPS_R = 0.5,
                     ARMOR = 0.02, DEF = 0.3, DODGE = 4, PARRY = 4, BLOCK = 2, BLOCKVAL = 0.1, SPI = 0.05 },
    tank   = { STA = 1, STR = 0.6, AGI = 0.7, DEF = 1.5, DODGE = 12, PARRY = 10, BLOCK = 6, BLOCKVAL = 0.4, ARMOR = 0.07,
               HIT = 6, CRIT = 3, AP = 0.2, DPS_M = 2, HASTE = 3 },
}
W.PALADIN = {
    damage = { STR = 1, AGI = 0.6, STA = 0.4, INT = 0.35, SPI = 0.1, AP = 0.5, SP = 0.3, HOLY = 0.25, HIT = 9, CRIT = 10,
               HASTE = 6, DPS_M = 7, MP5 = 0.8, ARMOR = 0.02, DEF = 0.2, DODGE = 3, PARRY = 3, BLOCK = 1 },
    heal   = { INT = 1, HEAL = 0.8, SP = 0.8, MP5 = 2, CRIT = 8, SPCRIT = 8, STA = 0.3, SPI = 0.1, HASTE = 4, ARMOR = 0.005 },
    tank   = { STA = 1, STR = 0.5, AGI = 0.6, INT = 0.3, SP = 0.5, HOLY = 0.4, DEF = 1.5, DODGE = 12, PARRY = 10, BLOCK = 6,
               BLOCKVAL = 0.4, ARMOR = 0.07, HIT = 5, CRIT = 3, MP5 = 1, DPS_M = 2 },
}
W.HUNTER = {
    damage = { AGI = 1, RAP = 0.5, AP = 0.1, STR = 0.05, STA = 0.4, INT = 0.3, SPI = 0.05, HIT = 12, CRIT = 10, HASTE = 8,
               DPS_R = 7, DPS_M = 0.5, MP5 = 0.5, ARMOR = 0.01, DODGE = 2 },
}
W.ROGUE = {
    damage = { AGI = 1, STR = 0.5, AP = 0.5, STA = 0.4, HIT = 12, CRIT = 11, HASTE = 8, DPS_M = 8, DPS_R = 0.3,
               ARMOR = 0.01, DODGE = 3, PARRY = 2 },
}
W.PRIEST = {
    damage = { SP = 1, SPDMG = 1, SHADOW = 1, INT = 0.4, SPI = 0.4, STA = 0.4, SPHIT = 10, HIT = 0, SPCRIT = 6, CRIT = 6,
               HASTE = 8, MP5 = 1.5, HEAL = 0.1, DPS_R = 2, ARMOR = 0.005 },
    heal   = { HEAL = 1, SP = 1, INT = 0.6, SPI = 0.5, MP5 = 2, SPCRIT = 7, CRIT = 7, STA = 0.3, HASTE = 5, DPS_R = 0.5,
               ARMOR = 0.005 },
}
W.MAGE = {
    damage = { SP = 1, SPDMG = 1, FIRE = 0.7, FROST = 0.7, ARCANE = 0.5, INT = 0.6, SPI = 0.2, STA = 0.4, SPHIT = 12,
               SPCRIT = 9, CRIT = 9, HASTE = 9, MP5 = 1, DPS_R = 2, ARMOR = 0.005 },
}
W.WARLOCK = {
    damage = { SP = 1, SPDMG = 1, SHADOW = 1, FIRE = 0.5, STA = 0.6, INT = 0.4, SPI = 0.3, SPHIT = 12, SPCRIT = 6,
               CRIT = 6, HASTE = 9, MP5 = 0.8, DPS_R = 2, ARMOR = 0.005 },
}
W.SHAMAN = {
    damage = { STR = 1, AGI = 0.6, STA = 0.4, INT = 0.35, SPI = 0.05, AP = 0.5, SP = 0.3, NATURE = 0.25, HIT = 9,
               CRIT = 10, HASTE = 6, DPS_M = 7, MP5 = 0.8, ARMOR = 0.02, BLOCK = 1 },
    caster = { SP = 1, SPDMG = 1, NATURE = 1, FIRE = 0.6, FROST = 0.4, INT = 0.5, STA = 0.4, SPI = 0.1, SPHIT = 10,
               SPCRIT = 9, CRIT = 9, HASTE = 8, MP5 = 1.5, ARMOR = 0.005 },
    heal   = { HEAL = 1, SP = 1, INT = 0.7, SPI = 0.2, MP5 = 2.2, SPCRIT = 7, CRIT = 7, STA = 0.3, HASTE = 5, ARMOR = 0.005 },
}
W.DRUID = {
    -- on WoW Forever the weapon counts in cat and bear form (decision 205): weapon DPS like the other melee
    damage = { STR = 1, AGI = 1, STA = 0.4, AP = 0.5, INT = 0.2, SPI = 0.05, HIT = 9, CRIT = 10, HASTE = 6, ARMOR = 0.02,
               DODGE = 3, DPS_M = 7 },
    tank   = { STA = 1, AGI = 0.8, STR = 0.5, ARMOR = 0.1, DEF = 1.2, DODGE = 12, AP = 0.2, HIT = 5, CRIT = 3, DPS_M = 7 },
    caster = { SP = 1, SPDMG = 1, NATURE = 1, ARCANE = 1, INT = 0.5, SPI = 0.3, STA = 0.4, SPHIT = 10, SPCRIT = 8,
               CRIT = 8, HASTE = 8, MP5 = 1.5, HEAL = 0.1, ARMOR = 0.005 },
    heal   = { HEAL = 1, SP = 1, INT = 0.6, SPI = 0.5, MP5 = 2, SPCRIT = 6, CRIT = 6, STA = 0.3, HASTE = 5, ARMOR = 0.005 },
}

-- the game's stat keys -> our keys
SC.API_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI", RESISTANCE0_NAME = "ARMOR",
    ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
    ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SPDMG",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL", ITEM_MOD_HEALING_DONE_SHORT = "HEAL",
    ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT", ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPHIT",
    ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPCRIT",
    ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF", ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
    ITEM_MOD_PARRY_RATING_SHORT = "PARRY", ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK", ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVAL",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

----------------------------------------------------------------------
-- Equip lines (English and German), read by key words
----------------------------------------------------------------------
local SCHOOLS = {
    { key = "SHADOW", words = { "shadow", "schatten" } }, { key = "FIRE", words = { "fire", "feuer" } },
    { key = "FROST", words = { "frost" } }, { key = "ARCANE", words = { "arcane", "arkan" } },
    { key = "NATURE", words = { "nature", "natur" } }, { key = "HOLY", words = { "holy", "heilig" } },
}
local function has(l, ...)
    for i = 1, select("#", ...) do if l:find((select(i, ...)), 1, true) then return true end end
    return false
end

-- one tooltip line -> key, value (or nil)
function SC.ParseLine(line)
    if type(line) ~= "string" then return nil end
    local l = line:lower()
    local n = tonumber(l:match("(%d+)"))
    if not n then return nil end
    local spell = has(l, "spell", "zauber")
    if has(l, "mana per 5", "mana every 5", "mana wieder", "mana alle 5", "punkt mana", "punkte mana") and has(l, "5") then
        return "MP5", n
    end
    if has(l, "critical", "kritisch") then return spell and "SPCRIT" or "CRIT", n end
    if has(l, "chance to hit", "trefferchance", "chance, mit zaubern zu treffen", "zu treffen") then
        return spell and "SPHIT" or "HIT", n
    end
    if has(l, "heal", "heilung") and has(l, "damage", "schaden") then
        -- "healing by up to 22 and damage by up to 8": two values, each to the word in front of it (decision 283);
        -- "damage and healing by up to 12": one value for both
        local nums = {}
        for pos, d in l:gmatch("()(%d+)") do nums[#nums + 1] = { pos = pos, n = tonumber(d) } end
        if #nums >= 2 then
            local function last(words, before)
                local best = 0
                for _, w in ipairs(words) do
                    local i = 1
                    while true do
                        local f = l:find(w, i, true)
                        if not f or f > before then break end
                        if f > best then best = f end
                        i = f + 1
                    end
                end
                return best
            end
            local heal, dmg
            for _, x in ipairs(nums) do
                local h, d = last({ "heal", "heilung" }, x.pos), last({ "damage", "schaden" }, x.pos)
                if h > d and not heal then heal = x.n elseif d > h and not dmg then dmg = x.n end
            end
            if heal and dmg then return "HEAL", heal, "SPDMG", dmg end
        end
        return "SP", n
    end
    if has(l, "heal", "heilung") then return "HEAL", n end
    if has(l, "damage", "schaden") and spell then
        for _, s in ipairs(SCHOOLS) do
            for _, w in ipairs(s.words) do if l:find(w, 1, true) then return s.key, n end end
        end
        return "SPDMG", n
    end
    if has(l, "ranged attack power", "distanzangriffskraft") then return "RAP", n end
    if has(l, "attack power", "angriffskraft") then return "AP", n end
    if has(l, "defense", "verteidigung") then return "DEF", n end
    if has(l, "dodge", "ausweichen") then return "DODGE", n end
    if has(l, "parry", "parieren") then return "PARRY", n end
    if has(l, "block value", "blockwert") then return "BLOCKVAL", n end
    if has(l, "block", "blocken") then return "BLOCK", n end
    if has(l, "attack speed", "angriffstempo", "haste", "tempo") then return "HASTE", n end
    return nil
end

-- the text lines of an item tooltip
local scanTip
local function tooltipLines(link)
    local out = {}
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for _, ln in ipairs(data.lines) do
                if type(ln.leftText) == "string" then out[#out + 1] = ln.leftText end
            end
            return out
        end
    end
    if not CreateFrame then return out end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "OneMoreQuestScanTip", UIParent, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:SetHyperlink(link)
    local n = tonumber(scanTip.NumLines and scanTip:NumLines()) or 0
    for i = 1, n do
        local fs = _G["OneMoreQuestScanTipTextLeft" .. i]
        local t = fs and fs.GetText and fs:GetText()
        if type(t) == "string" then out[#out + 1] = t end
    end
    scanTip:Hide()
    return out
end
SC._tooltipLines = tooltipLines

local cache = {}
-- all stats of an item in our keys; the tooltip fills what the game's stats leave out
function SC.Stats(link)
    if type(link) ~= "string" then return {} end
    local key = link:match("item:[%-%d:]+") or link
    if cache[key] then return cache[key] end
    local out = {}
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    if fn then
        local ok, t = pcall(fn, link)
        if ok and type(t) == "table" then
            for k, v in pairs(t) do
                local our = SC.API_KEYS[k]
                if our and type(v) == "number" then out[our] = (out[our] or 0) + v end
            end
        end
    end
    local trigger = (ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"):lower()
    local fromTip = {}
    for _, line in ipairs(tooltipLines(link)) do
        local l = line:lower()
        if l:find(trigger, 1, true) or l:find("equip:", 1, true) or l:find("anlegen:", 1, true) then
            local k, v, k2, v2 = SC.ParseLine(line)
            if k then fromTip[k] = (fromTip[k] or 0) + v end
            if k2 then fromTip[k2] = (fromTip[k2] or 0) + v2 end
        end
    end
    -- the game may report healing as spell power: the tooltip says "healing", so it is healing (decision 283)
    if fromTip.HEAL and not fromTip.SP and out.SP and out.SP == fromTip.HEAL then
        out.HEAL = (out.HEAL or 0) > 0 and out.HEAL or out.SP
        out.SP = nil
    end
    for k, v in pairs(fromTip) do
        if not out[k] or out[k] == 0 then out[k] = v end
    end
    -- the item is not loaded yet: do not keep an empty result
    if next(out) or (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(link)) then cache[key] = out end
    return out
end

----------------------------------------------------------------------
-- Can the class wear or wield it? (decision 214) Armour types and weapon types of the classic game,
-- as trainable at the class trainer. Rings, necks, trinkets, cloaks and off-hand items: everybody.
----------------------------------------------------------------------
-- armour subclass: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem
-- the number is the level from which the class may wear it (mail and plate come at 40)
SC.ARMOR = {
    [1] = { WARRIOR = 1, PALADIN = 1, HUNTER = 1, ROGUE = 1, PRIEST = 1, MAGE = 1, WARLOCK = 1, SHAMAN = 1, DRUID = 1 },
    [2] = { WARRIOR = 1, PALADIN = 1, HUNTER = 1, ROGUE = 1, SHAMAN = 1, DRUID = 1 },
    [3] = { WARRIOR = 1, PALADIN = 1, HUNTER = 40, SHAMAN = 40 },
    [4] = { WARRIOR = 40, PALADIN = 40 },
    [6] = { WARRIOR = 1, PALADIN = 1, SHAMAN = 1 },
    [7] = { PALADIN = 1 }, [8] = { DRUID = 1 }, [9] = { SHAMAN = 1 },
}
-- weapon subclass: 0 one-hand axe, 1 two-hand axe, 2 bow, 3 gun, 4 one-hand mace, 5 two-hand mace,
-- 6 polearm, 7 one-hand sword, 8 two-hand sword, 10 staff, 13 fist weapon, 15 dagger, 16 thrown,
-- 18 crossbow, 19 wand (14 miscellaneous and 20 fishing pole: everybody)
SC.WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER  = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE   = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST  = { 4, 10, 15, 19 },
    MAGE    = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    SHAMAN  = { 0, 1, 4, 5, 10, 13, 15 },
    DRUID   = { 4, 5, 10, 13, 15 },
}
local weaponSet = {}
for cls, list in pairs(SC.WEAPONS) do
    weaponSet[cls] = {}
    for _, v in ipairs(list) do weaponSet[cls][v] = true end
end

-- true, or false plus the reason ("Plate", "Plate at level 40"); the type name comes from the game
function SC.CanUse(link, class, level)
    if not (link and class) then return true end
    local _, _, subName, _, _, classID, subID
    if C_Item and C_Item.GetItemInfoInstant then _, _, subName, _, _, classID, subID = C_Item.GetItemInfoInstant(link)
    elseif GetItemInfoInstant then _, _, subName, _, _, classID, subID = GetItemInfoInstant(link) end
    classID, subID = tonumber(classID), tonumber(subID)
    if not classID or not subID then return true end
    local name = (type(subName) == "string" and subName ~= "") and subName or ("type " .. subID)
    if classID == 4 then
        local t = SC.ARMOR[subID]
        if not t then return true end                     -- miscellaneous: rings, necks, off-hand items
        local from = t[class]
        if not from then return false, name end
        if level and level < from then return false, name .. " at level " .. from end
        return true
    elseif classID == 2 then
        if subID == 14 or subID == 20 then return true end
        local set = weaponSet[class]
        if set and not set[subID] then return false, name end
        return true
    end
    return true
end

----------------------------------------------------------------------
-- Score
----------------------------------------------------------------------
function SC.RoleOf(class, role)
    local roles = SC.ROLES[class or ""]
    if not roles then return nil end
    for _, r in ipairs(roles) do if r == role then return r end end
    return roles[1]
end

function SC.WeightsOf(class, role)
    local t = W[class or ""]
    if not t then return nil end
    return t[SC.RoleOf(class, role)] or t.damage
end

local function ranged(link)
    local equipLoc
    if C_Item and C_Item.GetItemInfoInstant then equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    elseif GetItemInfoInstant then equipLoc = select(4, GetItemInfoInstant(link)) end
    return equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN"
end

-- value of one item for a class and role
function SC.Value(link, class, role)
    if not link then return 0 end
    local w = SC.WeightsOf(class, role)
    if not w then return 0 end
    local total = 0
    for k, v in pairs(SC.Stats(link)) do
        local weight
        if k == "DPS" then weight = ranged(link) and (w.DPS_R or 0) or (w.DPS_M or 0)
        elseif k == "SPCRIT" then weight = w.SPCRIT or 0
        elseif k == "SPHIT" then weight = w.SPHIT or 0
        else weight = w[k] or 0 end
        total = total + weight * v
    end
    return total
end

-- the score of link against the worn item: a whole number
function SC.Delta(link, worn, class, role)
    local d = SC.Value(link, class, role) - SC.Value(worn, class, role)
    if d >= 0 then return math.floor(d + 0.5) end
    return -math.floor(-d + 0.5)
end

-- weapons and off-hands against what is in both hands (decision 285):
-- an off-hand item (shield, held in off-hand, off-hand weapon) cannot be used next to a two-hander,
-- so it gets no score (nil, "twohand"); a two-hander replaces main hand and off-hand together
SC.OFFHAND = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
function SC.IsTwoHand(link)
    if type(link) ~= "string" then return false end
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return false end
    local ok, _, _, _, loc = pcall(f, link)
    return ok and loc == "INVTYPE_2HWEAPON" or false
end
function SC.HandDelta(link, equipLoc, worn, mainHand, offHand, class, role)
    if SC.OFFHAND[equipLoc or ""] and SC.IsTwoHand(mainHand) then return nil, "twohand" end
    if equipLoc == "INVTYPE_2HWEAPON" then
        local d = SC.Value(link, class, role) - SC.Value(mainHand, class, role) - SC.Value(offHand, class, role)
        return d >= 0 and math.floor(d + 0.5) or -math.floor(-d + 0.5)
    end
    return SC.Delta(link, worn, class, role)
end

function SC.Format(d)
    if d > 0 then return "|cff40e060+" .. d .. "|r" end
    if d < 0 then return "|cffff5050" .. d .. "|r" end
    return "|cff9aa0a6+-0|r"
end

----------------------------------------------------------------------
-- My role (option in the full options window, sent with the gear)
----------------------------------------------------------------------
function SC.MyClass() local _, c = UnitClass("player"); return c end
function SC.MyRole()
    local r = OMQ.db and OMQ.db.options and OMQ.db.options.role
    return SC.RoleOf(SC.MyClass(), r) or "damage"
end
function SC.SetMyRole(r)
    OMQ.db.options.role = r
    if OMQ.Gear then OMQ.Gear:Send({}) end          -- the others learn the new role
end
function SC.RoleChoices()
    local c = SC.MyClass()
    local out = {}
    for _, r in ipairs(SC.ROLES[c or ""] or { "damage" }) do
        local hint = SC.ROLE_HINT[c or ""] and SC.ROLE_HINT[c][r]
        local icon = SC.ROLE_ICON[c or ""] and SC.ROLE_ICON[c][r]
        out[#out + 1] = { id = r, label = SC.ROLE_LABEL[r] .. (hint and (" (" .. hint .. ")") or ""),
                          short = hint or SC.ROLE_LABEL[r], icon = icon and (IC .. icon) or nil }
    end
    return out
end

-- /omq score: what the addon reads from the item under the mouse, to check it in the game
OMQ:RegisterCommand("score", function()
    local link
    if GameTooltip and GameTooltip.GetItem then
        local ok, _, l = pcall(GameTooltip.GetItem, GameTooltip)
        if ok then link = l end
    end
    if not link then OMQ:Print("hover an item and type /omq score (bind it to a macro) to see what is read from it"); return end
    cache[link:match("item:[%-%d:]+") or link] = nil
    local parts = {}
    for k, v in pairs(SC.Stats(link)) do parts[#parts + 1] = k .. "=" .. v end
    table.sort(parts)
    OMQ:Print(link .. ": " .. (#parts > 0 and table.concat(parts, " ") or "no stats read"))
    local c = SC.MyClass()
    OMQ:Print(string.format("value for you (%s, %s): %.1f", tostring(c), SC.MyRole(), SC.Value(link, c, SC.MyRole())))
end, "what the item score reads from the item under the mouse")
