-- One More Quest: the quest chains of the Chain Run (decision 595). Quest ids, the objects and creatures that give
-- and take the quests and their places come from the WoW Forever data of Factoruide (GPL-3.0,
-- https://github.com/brouznouf/factoruide, 2026-11-14). The places where the dead Night Watch Guard lies come from
-- the Warcraft Wiki page of "An Unfortunate End" and player guides of 2026-11 (he moves between them).
-- Everything is matched by id, so English and German clients work alike; the quest names come from the game.
--
-- chain = { key, name, minLevel, rewards = { itemID, ... }, steps = { step, ... } }
-- step  = { title (English, when the game does not know the quest yet), quests = { [faction or "both"] = { questID, ... } },   -- the first id that is done or in the log counts
--           from = { [faction or "both"] = place }, to = { [faction or "both"] = place },
--           fromText, toText, minLevel, search = { place, ... }, item = itemID }
-- place = { uiMapID, x %, y % }; a step with "search" has no fixed place: the giver lies at one of these places
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local WESTFALL, BARRENS, STONETALON, LOCH, ARATHI, DUSKWOOD = 1436, 1413, 1442, 1432, 1417, 1431

OMQ.QuestChains = {
    {
        key = "bag", name = "Cozy Sleeping Bag", minLevel = 14, rewards = { 221498, 211527 },
        steps = {
            { title = "... and that note you found", quests = { Alliance = { 79008 }, Horde = { 79007 } },
              from = { Alliance = { WESTFALL, 37.4, 50.7 }, Horde = { BARRENS, 46.4, 73.9 } },
              to = { Alliance = { WESTFALL, 37.4, 50.8 }, Horde = { BARRENS, 46.4, 73.8 } },
              fromText = "click the Burned-Out Remains", toText = "click the Nailed Plank next to it" },
            { title = "Stepping Stones", quests = { both = { 79192 } },
              from = { Alliance = { WESTFALL, 37.4, 50.8 }, Horde = { BARRENS, 46.4, 73.8 } },
              to = { both = { STONETALON, 40.8, 52.6 } },
              fromText = "click the Nailed Plank", toText = "click the Pocket Litter" },
            { title = "Scramble", quests = { both = { 79980 } },
              from = { both = { STONETALON, 40.8, 52.6 } }, to = { both = { STONETALON, 39.6, 49.8 } },
              fromText = "click the Pocket Litter", toText = "click the Mound of Dirt" },
            { title = "Wet Job", quests = { both = { 79974 } },
              from = { both = { STONETALON, 39.6, 49.8 } }, to = { both = { LOCH, 49.4, 12.9 } },
              fromText = "click the Mound of Dirt", toText = "click the Carved Figurine at the dam", enemyZone = { Horde = true } },
            { title = "Eagle's Fist", quests = { both = { 79975 } },
              from = { both = { LOCH, 49.4, 12.9 } }, to = { both = { ARATHI, 22.5, 24.1 } },
              fromText = "click the Carved Figurine", toText = "click the Messenger Bag", enemyZone = { Horde = true } },
            { title = "This Must Be The Place", quests = { both = { 79976 } },
              from = { both = { ARATHI, 22.5, 24.1 } }, to = { both = { ARATHI, 22.4, 24.2 } },
              fromText = "click the Messenger Bag", toText = "click the Hastily Rolled-Up Satchel" },
        },
    },
    {
        key = "torch", name = "Night Watchman's Torch", minLevel = 1, rewards = { 280612 },
        steps = {
            { title = "An Unfortunate End", quests = { both = { 98372, 99267 } }, item = 280612,
              search = { { DUSKWOOD, 17.0, 54.7 }, { DUSKWOOD, 23.5, 33.4 }, { DUSKWOOD, 20.9, 34.4 }, { DUSKWOOD, 22.2, 73.1 },
                         { DUSKWOOD, 30.0, 67.5 }, { DUSKWOOD, 45.6, 79.0 }, { DUSKWOOD, 47.6, 59.5 }, { DUSKWOOD, 66.0, 33.9 },
                         { DUSKWOOD, 68.8, 69.6 } },
              fromText = "find the dead Night Watch Guard and right click him", toText = "turn it in at the body" },
        },
    },
}
