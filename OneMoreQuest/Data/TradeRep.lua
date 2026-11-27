-- One More Quest: the trading companies of Forever (decision 722)
-- Azeroth Commerce Authority (Alliance, Three Corners in Redridge) and Durotar Supply and Logistics (Horde, west of
-- the Crossroads). Waylaid Crates drop everywhere and are sold at the auction house; filled with ONE bundle of their
-- list they become sealed crates that the camp takes for Merchant's Favor (no reputation). Reputation comes from the
-- first crate's shipping label (2000), from Craftsman's Writs (75 / 125 / 200, each writ once a day) and, from
-- Friendly on, from Forged Delivery Receipts (15 Favor): a receipt on any empty crate gives a Notarized Shipping
-- Container worth 50 reputation, without a limit.
-- Sources (2026-11-27): Wowhead Forever guide, wow-professions.com, skillcarry.net, mobalytics.gg. Only item and
-- currency IDs are used, never names, so German and English clients work the same. The Artisan crates' Favor and
-- some Artisan bundles were not confirmed by any source (marked guess = true).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

OMQ.TradeRepData = {
    CURRENCY = 3402,                                         -- Merchant's Favor
    FACTIONS = { Alliance = 2586, Horde = 2587 },            -- Azeroth Commerce Authority, Durotar Supply and Logistics
    RECEIPT = 262902, RECEIPT_FAVOR = 15, NOTARIZED = 262917, RECEIPT_REP = 50,
    LABEL = 280180, LABEL_REP = 2000,
    -- the sealed writs: item, reputation of the writ inside
    WRITS = { { id = 262888, rep = 75 }, { id = 262889, rep = 125 }, { id = 262890, rep = 200 } },
    -- reputation of the standings from Neutral on (absolute values of the game's reputation bar)
    STANDINGS = { { 5, "Friendly", 3000 }, { 6, "Honored", 9000 }, { 7, "Revered", 21000 }, { 8, "Exalted", 42000 } },
    -- the crates: id, Favor of the sealed crate, bundles { item, count } (one of them fills the crate)
    CRATES = {
        { id = 248684, favor = 5, bundles = { { 2589, 40 }, { 2318, 20 } } },                                    -- Apprentice Textiles
        { id = 248683, favor = 5, bundles = { { 2770, 20 }, { 2771, 20 } } },                                    -- Apprentice Ore
        { id = 248682, favor = 5, bundles = { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } }, -- Apprentice Herbs
        { id = 248685, favor = 5, bundles = { { 10940, 20 }, { 10939, 4 }, { 10978, 6 }, { 11084, 2 } } },       -- Apprentice Curiosities
        { id = 248702, favor = 10, bundles = { { 4231, 2 }, { 2996, 20 } } },                                    -- Apprentice Fabrics
        { id = 248703, favor = 10, bundles = { { 2840, 20 }, { 3576, 20 }, { 2841, 10 } } },                     -- Apprentice Ingots
        { id = 248704, favor = 10, bundles = { { 4359, 16 }, { 4361, 16 }, { 4363, 4 } } },                      -- Apprentice Parts
        { id = 248688, favor = 10, bundles = { { 2592, 40 }, { 4306, 40 }, { 2319, 20 } } },                     -- Journeyman Textiles
        { id = 248687, favor = 10, bundles = { { 2775, 10 }, { 2772, 20 } } },                                   -- Journeyman Ore
        { id = 248686, favor = 10, bundles = { { 3820, 10 }, { 2453, 10 }, { 3355, 10 }, { 3369, 10 }, { 3356, 10 } } }, -- Journeyman Herbs
        { id = 248689, favor = 10, bundles = { { 11083, 20 }, { 11082, 4 }, { 11138, 6 }, { 11139, 2 } } },      -- Journeyman Curiosities
        { id = 248705, favor = 20, bundles = { { 2997, 6 }, { 4305, 10 }, { 4233, 2 } } },                       -- Journeyman Fabrics
        { id = 248706, favor = 20, bundles = { { 2842, 10 }, { 3575, 20 } } },                                   -- Journeyman Ingots
        { id = 248707, favor = 20, bundles = { { 4371, 8 }, { 4375, 7 }, { 4382, 4 }, { 10558, 45 } } },         -- Journeyman Parts
        { id = 248693, favor = 15, bundles = { { 4338, 40 }, { 4234, 20 } } },                                   -- Expert Textiles
        { id = 248692, favor = 15, bundles = { { 2776, 10 }, { 3858, 20 } } },                                   -- Expert Ore
        { id = 248690, favor = 15, bundles = { { 3357, 20 }, { 3818, 10 }, { 3821, 10 }, { 3358, 10 } } },       -- Earthly Expert Herbs
        { id = 248691, favor = 15, bundles = { { 3819, 10 }, { 4625, 10 }, { 8831, 20 }, { 8836, 10 } } },       -- Flowering Expert Herbs
        { id = 248694, favor = 15, bundles = { { 11137, 20 }, { 11135, 4 }, { 11177, 6 }, { 11178, 2 } } },      -- Expert Curiosities
        { id = 248708, favor = 30, bundles = { { 4339, 8 }, { 4236, 2 } } },                                     -- Expert Fabrics
        { id = 248709, favor = 30, bundles = { { 3860, 20 }, { 3859, 15 }, { 3577, 10 } } },                     -- Expert Ingots
        { id = 248710, favor = 30, bundles = { { 4387, 8 }, { 10559, 5 }, { 10560, 12 }, { 10561, 5 } } },       -- Expert Parts
        { id = 248698, favor = 20, guess = true, bundles = { { 14047, 40 }, { 4304, 20 }, { 8170, 20 } } },      -- Artisan Textiles
        { id = 248697, favor = 20, guess = true, bundles = { { 7911, 10 }, { 10620, 20 } } },                    -- Artisan Ore
        { id = 248695, favor = 20, guess = true, bundles = { { 13464, 10 }, { 8838, 20 }, { 8839, 10 }, { 8845, 10 }, { 8846, 10 } } }, -- Earthly Artisan Herbs
        { id = 248696, favor = 20, guess = true, bundles = { { 13463, 20 }, { 13465, 20 }, { 13466, 20 }, { 13467, 20 } } }, -- Flowering Artisan Herbs
        { id = 248699, favor = 20, guess = true, bundles = { { 11176, 20 }, { 11175, 4 }, { 14343, 6 }, { 14344, 2 } } }, -- Artisan Curiosities
        { id = 248711, favor = 40, guess = true, bundles = { { 14048, 8 }, { 8172, 2 } } },                      -- Artisan Fabrics
        { id = 248712, favor = 40, guess = true, bundles = { { 11371, 2 }, { 6037, 10 }, { 12359, 20 } } },      -- Artisan Ingots
        { id = 248713, favor = 40, guess = true, bundles = { { 15994, 5 }, { 18631, 5 }, { 16000, 2 } } },       -- Artisan Parts
    },
}
