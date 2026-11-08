-- Dungeon prerequisite journal sample: three complete chains, independently selected from QuestieDB.
-- Source: QuestieDB Forever, GPL-3.0, commit 3a621efafce6aef99b0f106d22aa71ca980ee552:
-- https://github.com/Questie/QuestieDB/blob/3a621efafce6aef99b0f106d22aa71ca980ee552/data/Forever/foreverQuestDB.lua
-- https://github.com/Questie/QuestieDB/blob/3a621efafce6aef99b0f106d22aa71ca980ee552/data/Forever/foreverNpcDB.lua
-- German quest and giver names: l10n/Forever/lookupQuests/deDE.lua and lookupNpcs/deDE.lua at the same commit.
-- start uses OMQ.QuestStarts' positional format, but points to this step's immediate giver.
-- shortcut: only these three chains are covered; add verified data before claiming full dungeon coverage.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

OMQ.DungeonQuestChains = {
    [166] = {
        { id = 65, name = "The Defias Brotherhood", nameDe = "Die Bruderschaft der Defias", level = 14,
          start = { 65, "The Defias Brotherhood", "Gryan Stoutmantle", "Gryan Stoutmantle", 1436, 56.33, 47.52, "npc" } },
        { id = 132, name = "The Defias Brotherhood", nameDe = "Die Bruderschaft der Defias", level = 14,
          start = { 132, "The Defias Brotherhood", "Wiley the Black", "Wiley der Schwarze", 1433, 21.39, 45.35, "npc" } },
        { id = 135, name = "The Defias Brotherhood", nameDe = "Die Bruderschaft der Defias", level = 14,
          start = { 135, "The Defias Brotherhood", "Gryan Stoutmantle", "Gryan Stoutmantle", 1436, 56.33, 47.52, "npc" } },
        { id = 141, name = "The Defias Brotherhood", nameDe = "Die Bruderschaft der Defias", level = 14,
          start = { 141, "The Defias Brotherhood", "Master Mathias Shaw", "Meister Mathias Shaw", 1453, 78.31, 70.74, "npc" } },
        { id = 142, name = "The Defias Brotherhood", nameDe = "Die Bruderschaft der Defias", level = 14,
          start = { 142, "The Defias Brotherhood", "Gryan Stoutmantle", "Gryan Stoutmantle", 1436, 56.33, 47.52, "npc" } },
        { id = 155, name = "The Defias Brotherhood", nameDe = "Die Bruderschaft der Defias", level = 14,
          start = { 155, "The Defias Brotherhood", "The Defias Traitor", "Der Verräter der Defias", 1436, 55.68, 47.50, "npc" } },
        { id = 166, name = "The Defias Brotherhood", nameDe = "Die Bruderschaft der Defias", level = 14,
          start = { 166, "The Defias Brotherhood", "Gryan Stoutmantle", "Gryan Stoutmantle", 1436, 56.33, 47.52, "npc" } },
    },
    [1491] = {
        { id = 865, name = "Raptor Horns", nameDe = "Raptorhörner", level = 13,
          start = { 865, "Raptor Horns", "Mebok Mizzyrix", "Mebok Mizzyrix", 1413, 62.37, 37.62, "npc" } },
        { id = 1491, name = "Smart Drinks", nameDe = "Klugheitstränke", level = 13,
          start = { 1491, "Smart Drinks", "Mebok Mizzyrix", "Mebok Mizzyrix", 1413, 62.37, 37.62, "npc" } },
    },
    [5728] = {
        { id = 5726, name = "Hidden Enemies", nameDe = "Verborgene Feinde", level = 9,
          start = { 5726, "Hidden Enemies", "Thrall", "Thrall", 1454, 31.73, 37.82, "npc" } },
        { id = 5727, name = "Hidden Enemies", nameDe = "Verborgene Feinde", level = 9,
          start = { 5727, "Hidden Enemies", "Thrall", "Thrall", 1454, 31.73, 37.82, "npc" } },
        { id = 5728, name = "Hidden Enemies", nameDe = "Verborgene Feinde", level = 9,
          start = { 5728, "Hidden Enemies", "Thrall", "Thrall", 1454, 31.73, 37.82, "npc" } },
    },
}
