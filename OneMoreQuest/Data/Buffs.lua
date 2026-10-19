-- One More Quest: data - the fixed buff list per class (section 5.2)
-- Spell IDs are the first rank of each spell; names are resolved at runtime so
-- the list works in every language. A buff group counts as covered when ANY
-- spell of the group is on the target, cast by anybody.
--
-- scope "all":  checked on the player and on party1 to party4
-- scope "self": checked on the player only
-- cast:        the player must know one of these spells to be asked for the group
-- kind "aura": aura on the unit; kind "weapon": weapon enchantment (imbue, poison)
-- minRage:     only asked for with at least this much rage (warrior)
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

OMQ.buffGroups = {
    PALADIN = {
        { id = "blessing", label = "a Blessing", scope = "all", kind = "aura",
          cast = { 19740, 19742, 20217, 1038, 19977, 20911 },
          spells = { 19740, 19742, 20217, 1038, 19977, 20911,        -- single blessings
                     25782, 25894, 25898, 25895, 25890, 25899 } },     -- greater blessings
        -- an aura (decision 241): any aura of the paladin counts; asked for is Devotion Aura
        { id = "palaura", label = "an aura", scope = "self", kind = "aura",
          cast = { 10293, 10292, 1032, 10291, 643, 10290, 465 },          -- Devotion Aura, highest rank first
          spells = { 465, 7294, 19746, 19876, 19888, 19891, 20218 } },   -- Devotion, Retribution, Concentration,
                                                                         -- Shadow, Frost, Fire Resistance, Sanctity
    },
    PRIEST = {
        { id = "fortitude", label = "Fortitude", scope = "all", kind = "aura",
          cast = { 1243 }, spells = { 1243, 21562 } },
        { id = "spirit", label = "Divine Spirit", scope = "all", kind = "aura",
          cast = { 14752 }, spells = { 14752, 27681 } },
        { id = "innerfire", label = "Inner Fire", scope = "self", kind = "aura",
          cast = { 588 }, spells = { 588 } },
    },
    MAGE = {
        { id = "intellect", label = "Arcane Intellect", scope = "all", kind = "aura",
          cast = { 1459 }, spells = { 1459, 23028 } },
        -- Frost Armor, Ice Armor and Mage Armor: any one of them is fine. When none is up there
        -- are two cards: Mage Armor, and Ice Armor (the replacement of Frost Armor) or Frost
        -- Armor as long as Ice Armor is not learned. Highest rank first inside each choice.
        { id = "magearmor", label = "an armor spell", scope = "self", kind = "aurachoice",
          choices = {
              { id = "icefrost", cast = { 27124, 10220, 10219, 7320, 7302,       -- Ice Armor
                                          7301, 7300, 168 } },                    -- Frost Armor
              { id = "mage",     cast = { 27125, 22783, 22782, 6117 } },          -- Mage Armor
          },
          spells = { 168, 7300, 7301, 7302, 7320, 10219, 10220, 27124,
                     6117, 22782, 22783, 27125 } },
    },
    HUNTER = {
        -- Aspects: any one of them on the hunter is fine. When none is up there is one card
        -- per aspect the hunter knows (Hawk on top). Highest rank first inside each choice.
        { id = "aspect", label = "an aspect", scope = "self", kind = "aurachoice",
          choices = {
              { id = "hawk",    cast = { 27044, 25296, 14322, 14321, 14320, 14319, 14318, 13165 } },
              { id = "viper",   cast = { 34074 } },
              { id = "monkey",  cast = { 13163 } },
              { id = "cheetah", cast = { 5118 } },
              { id = "pack",    cast = { 13159 } },
              { id = "wild",    cast = { 27045, 20190, 20043 } },
              { id = "beast",   cast = { 13161 } },
          },
          spells = { 13165, 14318, 14319, 14320, 14321, 14322, 25296, 27044,    -- Hawk
                     34074, 13163, 5118, 13159,                                 -- Viper, Monkey, Cheetah, Pack
                     20043, 20190, 27045, 13161 } },                            -- Wild, Beast
    },
    WARLOCK = {
        { id = "soulstone", label = "Soulstone", scope = "all", kind = "aura",
          cast = { 693 }, spells = { 20707, 20762, 20763, 20764, 20765 } },
        -- Demon Skin (level 1) and Demon Armor (level 20): either one counts. When none is
        -- up the best known one is asked for, so Demon Armor comes first in the list.
        { id = "lockarmor", label = "Demon Skin or Demon Armor", scope = "self", kind = "aura",
          cast = { 27260, 11735, 11734, 11733, 1086, 706,           -- Demon Armor, highest rank first
                   696, 687 },                                      -- Demon Skin
          spells = { 706, 1086, 11733, 11734, 11735, 27260, 687, 696 } },
    },
    DRUID = {
        { id = "motw", label = "Mark of the Wild", scope = "all", kind = "aura",
          cast = { 1126 }, spells = { 1126, 21849 } },
        { id = "thorns", label = "Thorns", scope = "all", kind = "aura",
          cast = { 467 }, spells = { 467 } },
    },
    SHAMAN = {
        -- one card per imbue the shaman knows, as long as the weapon has none of them
        -- (Frostbrand is not wanted). The first rank of each spell is listed.
        { id = "imbue", label = "a weapon imbue", scope = "self", kind = "weaponchoice", spells = {},
          choices = {
              { id = "rockbiter", cast = { 8017 } },
              { id = "windfury", cast = { 8232 } },
              { id = "flametongue", cast = { 8024 } },
          } },
        -- only asked for when the shaman has learned it (every group is checked that way)
        { id = "watershield", label = "Water Shield", scope = "self", kind = "aura",
          cast = { 24398, 33736, 408510 }, spells = { 24398, 33736, 408510, 324 } },
        -- Lightning Shield (decision 241): either shield counts
        { id = "lightningshield", label = "Lightning Shield", scope = "self", kind = "aura",
          cast = { 10432, 10431, 8134, 945, 905, 325, 324 }, spells = { 324, 24398, 33736, 408510 } },
    },
    ROGUE = {
        { id = "poison", label = "a poison on your weapon", scope = "self", kind = "weapon",
          cast = { 2842 }, spells = {} },
    },
    WARRIOR = {
        -- Battle Shout (decision 208): only out of combat, only on the warrior himself and only
        -- with at least 15 rage (it costs 10; the rest is time to react before the rage is gone)
        { id = "battleshout", label = "Battle Shout", scope = "self", kind = "aura", minRage = 15,
          cast = { 25289, 11551, 11550, 11549, 6192, 5242, 6673 },       -- highest rank first
          spells = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } },
    },
    -- Hunter: the aspects above
}
