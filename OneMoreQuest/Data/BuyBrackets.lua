-- One More Quest: the consumables of the Buy tab, a fixed list by level and class (decision 691)
-- Kept by hand from MadDadVibe's list "Cheap WOW FOREVER Consumes V2". Every row: { elixir, weapon buff, food, potion },
-- false = nothing in that column (hunters: the weapon stone is only for melee weaving, so none).
-- A level uses the row of the highest bracket it has reached; below the first bracket the first row, only the items
-- the level can already use (NEED). The druid takes FERAL (damage, tank) or CASTER (caster, healer) by its role.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local L = {}
OMQ.BuyBrackets = L

L.BRACKETS = { 15, 25, 35, 45 }
L.COLUMNS = { "elixir", "weapon", "food", "potion" }

-- item IDs:  elixirs   2454 Elixir of Lion's Strength (Minor Strength), 2457 Elixir of Minor Agility, 247754 Minor Arcane Elixir,
--                      3391 Elixir of Ogre's Strength, 3390 Elixir of Lesser Agility, 250342 Lesser Arcane Elixir,
--                      8949 Elixir of Agility, 250349 Elixir of Strength, 9187 Elixir of Greater Agility, 9155 Arcane Elixir
--            weapon    2871/3241 Heavy Sharpening Stone/Weightstone, 7964/7965 Solid, 12404/12643 Dense,
--                      20744 Minor Wizard Oil, 20750 Wizard Oil
--            food      5480 Lean Venison, 3727 Hot Lion Chops, 21072 Smoked Sagefish, 250074 Bear Brisket,
--                      20074 Heavy Crocolisk Stew, 13932 Poached Sunscale Salmon, 12212 Jungle Stew, 6887 Spotted Yellowtail
--            potions   929 Healing Potion, 1710 Greater Healing Potion, 3928 Superior Healing Potion,
--                      3385 Lesser Mana Potion, 3827 Mana Potion, 6149 Greater Mana Potion
L.LIST = {
    WARRIOR = {
        [15] = { 2454, 2871, 5480, 929 },
        [25] = { 3391, 7964, 250074, 1710 },
        [35] = { 3391, 12404, 13932, 3928 },
        [45] = { 250349, 12404, 13932, 3928 },
    },
    ROGUE = {
        [15] = { 2457, 2871, 3727, 929 },
        [25] = { 3390, 7964, 20074, 1710 },
        [35] = { 8949, 12404, 12212, 3928 },
        [45] = { 9187, 12404, 12212, 3928 },
    },
    HUNTER = {
        [15] = { 2457, false, 3727, 3385 },
        [25] = { 3390, false, 20074, 3827 },
        [35] = { 8949, false, 12212, 6149 },
        [45] = { 9187, false, 12212, 6149 },
    },
    PALADIN = {
        [15] = { 2454, 2871, 5480, 3385 },
        [25] = { 3391, 7964, 250074, 3827 },
        [35] = { 3391, 12643, 13932, 6149 },
        [45] = { 250349, 12643, 13932, 6149 },
    },
    SHAMAN = {
        [15] = { 2454, 3241, 5480, 3385 },
        [25] = { 3391, 7965, 250074, 3827 },
        [35] = { 3391, 12643, 13932, 6149 },
        [45] = { 250349, 12643, 13932, 6149 },
    },
    DRUID_FERAL = {
        [15] = { 2454, 3241, 5480, 929 },
        [25] = { 3391, 7965, 250074, 1710 },
        [35] = { 8949, 12643, 13932, 3928 },
        [45] = { 9187, 12643, 13932, 3928 },
    },
    DRUID_CASTER = {
        [15] = { 247754, 20744, 21072, 3385 },
        [25] = { 250342, 20744, 21072, 3827 },
        [35] = { 250342, 20744, 6887, 6149 },
        [45] = { 9155, 20750, 6887, 6149 },
    },
}
-- priest, mage and warlock have the caster druid's rows, the warlock a healing potion instead of the mana potion
L.LIST.PRIEST = L.LIST.DRUID_CASTER
L.LIST.MAGE = L.LIST.DRUID_CASTER
L.LIST.WARLOCK = {
    [15] = { 247754, 20744, 21072, 929 },
    [25] = { 250342, 20744, 21072, 1710 },
    [35] = { 250342, 20744, 6887, 3928 },
    [45] = { 9155, 20750, 6887, 3928 },
}

-- the level an item needs (only the first bracket's items can be above my level)
L.NEED = {
    [2454] = 1, [2457] = 2, [247754] = 1, [2871] = 15, [3241] = 15, [20744] = 5,
    [5480] = 15, [3727] = 15, [21072] = 10, [929] = 12, [3385] = 14,
    [3391] = 20, [3390] = 18, [250342] = 25, [7964] = 25, [7965] = 25, [250074] = 25, [20074] = 20, [1710] = 21, [3827] = 22,
    [8949] = 27, [12404] = 35, [12643] = 35, [13932] = 35, [12212] = 25, [6887] = 35, [3928] = 35, [6149] = 31,
    [250349] = 45, [9187] = 38, [9155] = 37, [20750] = 40,
}

-- sharpening stone (blade) <-> weightstone (blunt) of the same tier: the stone that fits the weapon in hand
L.SHARP = { [2871] = true, [7964] = true, [12404] = true }
L.STONE_PAIR = { [2871] = 3241, [3241] = 2871, [7964] = 7965, [7965] = 7964, [12404] = 12643, [12643] = 12404 }
