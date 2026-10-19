-- One More Quest: dungeons and their dungeon quests on WoW Forever (decision 145).
-- Truth: Wowhead "Every dungeon quest location" (wowhead.com/forever/guide/dungeons/every-dungeon-quest-location).
--   Level range of a dungeon = the page's lowest ("Hard") to highest ("Easy") level; where the page has no "Easy" (Dire Maul
--   West and North, Scholomance) the upper end is 60. Quests, quest levels and ids as listed there.
--   Faction: the page's "Side" column (the icon, read from the page itself): Horde / Alliance icon = that faction only,
--   "-" = both (no faction field). Never derived from a quest giver's zone (v0.25.1). Dungeons the page does not
--   cover keep the faction of the earlier sources.
--   Not listed here: class-only quests (paladin, mage, warlock).
-- Dungeons that the page does not cover (Drowned City, Krol'dok, Alcaz, Blackmaw Hold, Shaper's Terrace, Stratholme, Upper
-- Blackrock Spire) keep their earlier values (decision 143: in-game dungeon browser).
-- Quest: { id, name, level, faction } faction "A" Alliance only, "H" Horde only, nil = both.
--   alt = further ids of the same quest (the game has one id per faction version); a dad has it with any of them.
-- Scarlet Monastery: the page gives the Graveyard and Library their own quests, the Armory and Cathedral only the shared ones;
--   the level ranges of the wings are those of the in-game dungeon browser.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

OMQ.Dungeons = {
    { key = "rfc", abbr = "RFC", name = "Ragefire Chasm", min = 9, max = 19, quests = {
        { id = 5761, name = "Slaying the Beast", level = 9, faction = "H" },
        { id = 5725, name = "The Power to Destroy...", level = 9, faction = "H" },
        { id = 5723, name = "Testing an Enemy's Strength", level = 9, faction = "H" },
        { id = 5722, name = "Searching for the Lost Satchel", level = 9, faction = "H" },
        { id = 5728, name = "Hidden Enemies", level = 9, faction = "H" },
        { id = 5724, name = "Returning the Lost Satchel", level = 9, faction = "H" },  -- WoW Forever (decision 255)
    } },
    { key = "hot", abbr = "HoT", name = "Hall of Thanes", min = 11, max = 19, quests = {
        { id = 96403, name = "Important Heirlooms", level = 14, faction = "A" },
        { id = 96394, name = "The Restless Dead", level = 15, faction = "A" },
        { id = 96393, name = "Old Ironforge Incursion", level = 15, faction = "A" },
        { id = 98423, name = "The Treaty of Understanding", level = 16, faction = "A" },
        { id = 96395, name = "An Ancient Grudge", level = 14, faction = "A" },
    } },
    { key = "wc", abbr = "WC", name = "Wailing Caverns", min = 15, max = 24, quests = {
        { id = 962, name = "Serpentbloom", level = 14, faction = "H" },
        { id = 1491, name = "Smart Drinks", level = 13 },
        { id = 959, name = "Trouble at the Docks", level = 14 },
        { id = 1486, name = "Deviate Hides", level = 13 },
        { id = 1487, name = "Deviate Eradication", level = 15 },
        { id = 6981, name = "The Glowing Shard", level = 10 },
        { id = 914, name = "Leaders of the Fang", level = 15, faction = "H" },
    } },
    { key = "rol", abbr = "RoL", name = "Ruins of Lordaeron", min = 15, max = 24, quests = {
        { id = 92401, name = "A Frightened Request", level = 15, faction = "H" },
        { id = 92422, name = "The Wrath of Rath'mael", level = 15, faction = "H" },
        { id = 95216, name = "The New Plague", level = 16, faction = "H" },
        { id = 92421, name = "Light's Justice", level = 15, faction = "H" },
        { id = 97288, name = "Unending Torment", level = 15, faction = "H" },
        { id = 95250, name = "Abominable Creatures", level = 16, faction = "A" },
        { id = 95195, name = "Bloodied Insignia", level = 16, faction = "A" },
        { id = 92415, name = "Remember That I Love You", level = 15, faction = "A" },
        { id = 95189, name = "Crest of Lordaeron", level = 16, faction = "A" },  -- WoW Forever (decision 255)
        { id = 95204, name = "Crest of Lordaeron", level = 16, faction = "H" },  -- WoW Forever (decision 255)
    } },
    { key = "dm", abbr = "DM", name = "The Deadmines", min = 14, max = 24, quests = {
        { id = 168, name = "Collecting Memories", level = 14, faction = "A" },
        { id = 167, name = "Oh Brother...", level = 15, faction = "A" },
        { id = 2040, name = "Underground Assault", level = 15, faction = "A" },
        { id = 373, name = "The Unsent Letter", level = 16, faction = "A" },
        { id = 214, name = "Red Silk Bandanas", level = 14, faction = "A" },
        { id = 166, name = "The Defias Brotherhood", level = 14, faction = "A" },
        { id = 92753, name = "Destruction in Deadmines", level = 14, faction = "A" },
    } },
    { key = "sfk", abbr = "SFK", name = "Shadowfang Keep", min = 18, max = 28, quests = {
        { id = 1013, name = "The Book of Ur", level = 16, faction = "H" },
        { id = 1098, name = "Deathstalkers in Shadowfang", level = 18, faction = "H" },
        { id = 1014, name = "Arugal Must Die", level = 18, faction = "H" },
    } },
    { key = "bfd", abbr = "BFD", name = "Blackfathom Deeps", min = 21, max = 30, quests = {
        { id = 6563, name = "The Essence of Aku'Mai", level = 17, faction = "H" },
        { id = 6561, name = "Blackfathom Villainy", level = 18, faction = "H" },
        { id = 6921, name = "Amongst the Ruins", level = 21, faction = "H" },
        { id = 6922, name = "Baron Aquanis", level = 21, faction = "H" },
        { id = 6565, name = "Allegiance to the Old Gods", level = 17, faction = "H" },
        { id = 971, name = "Knowledge in the Deeps", level = 10, faction = "A" },
        { id = 1275, name = "Researching the Corruption", level = 18, faction = "A" },
        { id = 1199, name = "Twilight Falls", level = 20, faction = "A" },
        { id = 1198, name = "In Search of Thaelrid", level = 18, faction = "A" },
        { id = 1200, name = "Blackfathom Villainy", level = 18, faction = "A" },
        { id = 6562, name = "Trouble in the Deeps", level = 17, faction = "H" },  -- WoW Forever (decision 255)
    } },
    { key = "stk", abbr = "Stk", name = "The Stockade", min = 22, max = 30, quests = {
        { id = 387, name = "Quell the Uprising", level = 22, faction = "A" },
        { id = 388, name = "The Color of Blood", level = 22, faction = "A" },
        { id = 377, name = "Crime and Punishment", level = 22, faction = "A" },
        { id = 386, name = "What Comes Around...", level = 22, faction = "A" },
        { id = 378, name = "The Fury Runs Deep", level = 25, faction = "A" },
        { id = 391, name = "The Stockade Riots", level = 16, faction = "A" },
    } },
    { key = "exc", abbr = "Exc", name = "Excavation Site: Wetlands", min = 24, max = 31, quests = {
        { id = 98815, name = "Highland Hides", level = 24, faction = "A" },
        { id = 95772, name = "Songblade Search", level = 24, faction = "A" },
        { id = 95646, name = "Horrors in the Highland", level = 24, faction = "A" },
        { id = 95647, name = "Lost in the Thicket Things", level = 24, faction = "A" },
        { id = 95809, name = "Heartwoven", level = 24, faction = "A" },
        { id = 95810, name = "Lost Relic Carry", level = 24, faction = "A" },
        { id = 98824, name = "Prehistoric Prism", level = 24, faction = "A" },
        { id = 95697, name = "Changing Tastes", level = 24, faction = "H" },
        { id = 95664, name = "Elder Knowledge", level = 24, faction = "H" },
        { id = 98823, name = "Earthen Echo", level = 24, faction = "H" },
        { id = 95682, name = "Open the Maw", level = 24, faction = "H" },
        { id = 95795, name = "Fallen in the Fen", level = 24, faction = "A" },  -- WoW Forever (decision 255)
    } },
    { key = "gnom", abbr = "Gno", name = "Gnomeregan", min = 25, max = 38, quests = {
        { id = 2841, name = "Rig Wars", level = 25, faction = "H" },
        { id = 2842, name = "Chief Engineer Scooty", level = 20, faction = "H" },
        { id = 2843, name = "Gnomer-gooooone!", level = 20, faction = "H" },
        { id = 2922, name = "Save Techbot's Brain!", level = 20, faction = "A" },
        { id = 2928, name = "Gyrodrillmatic Excavationators", level = 20, faction = "A" },
        { id = 2924, name = "Essential Artificials", level = 24, faction = "A" },
        { id = 2930, name = "Data Rescue", level = 25, faction = "A" },
        { id = 2929, name = "The Grand Betrayal", level = 25, faction = "A" },
        { id = 2926, name = "Gnogaine", level = 20, faction = "A" },
        { id = 2962, name = "The Only Cure is More Green Glow", level = 20, faction = "A" },
        { id = 2951, name = "The Sparklematic 5200!", level = 25 },
        { id = 2904, name = "A Fine Mess", level = 20 },
        { id = 2945, name = "Grime-Encrusted Ring", level = 28 },
        { id = 2948, name = "Gnome Improvement", level = 28, faction = "A" },  -- WoW Forever (decision 255)
        { id = 2950, name = "Nogg's Ring Redo", level = 28, faction = "H" },  -- WoW Forever (decision 255)
    } },
    { key = "dal", abbr = "Dal", name = "City of Dalaran", min = 26, max = 34, quests = {
        { id = 96986, name = "The Grave Knight", level = 24, faction = "H" },
        { id = 96988, name = "Source of Power", level = 24, faction = "H" },
        { id = 96987, name = "Opportunistic Education", level = 24, faction = "H" },
        { id = 96984, name = "Heart of Disruption", level = 24, faction = "H" },
        { id = 92489, name = "Power Overwhelming", level = 24, faction = "A" },
        { id = 92458, name = "Heart of Disruption", level = 24, faction = "A" },
        { id = 92456, name = "A Green Sample", level = 24, faction = "A" },
        { id = 92457, name = "Starving Arcane", level = 24, faction = "A" },
    } },
    { key = "rfk", abbr = "RFK", name = "Razorfen Kraul", min = 25, max = 34, quests = {
        { id = 1102, name = "A Vengeful Fate", level = 29, faction = "H" },
        { id = 1109, name = "Going, Going, Guano!", level = 30, faction = "H" },
        { id = 6522, name = "An Unholy Alliance", level = 28, faction = "H" },
        { id = 1101, name = "The Crone of the Kraul", level = 29, faction = "A" },
        { id = 1142, name = "Mortality Wanes", level = 25, faction = "A" },
        { id = 1221, name = "Blueleaf Tubers", level = 20 },
        { id = 1144, name = "Willix the Importer", level = 22 },
    } },
    { key = "smg", abbr = "SMG", name = "Scarlet Monastery: Graveyard", min = 30, max = 38, quests = {
        { id = 1048, name = "Into The Scarlet Monastery", level = 33, faction = "H" },
        { id = 1053, name = "In the Name of the Light", level = 34, faction = "A" },
        { id = 1051, name = "Vorrel's Revenge", level = 25, faction = "H" },
        { id = 1113, name = "Hearts of Zeal", level = 30, faction = "H" },
    } },
    { key = "sml", abbr = "SML", name = "Scarlet Monastery: Library", min = 33, max = 41, quests = {
        { id = 1048, name = "Into The Scarlet Monastery", level = 33, faction = "H" },
        { id = 1053, name = "In the Name of the Light", level = 34, faction = "A" },
        { id = 1049, name = "Compendium of the Fallen", level = 28, faction = "H" },
        { id = 1160, name = "Test of Lore", level = 25, faction = "H" },
        { id = 1050, name = "Mythology of the Titans", level = 28, faction = "A" },
        { id = 1394, name = "Final Passage", level = 25, faction = "H" },  -- WoW Forever (decision 255)
        { id = 96800, name = "Past Due", level = 30, faction = "A" },  -- WoW Forever (decision 255)
    } },
    { key = "sma", abbr = "SMA", name = "Scarlet Monastery: Armory", min = 36, max = 44, quests = {
        { id = 1048, name = "Into The Scarlet Monastery", level = 33, faction = "H" },
        { id = 1053, name = "In the Name of the Light", level = 34, faction = "A" },
    } },
    { key = "smc", abbr = "SMC", name = "Scarlet Monastery: Cathedral", min = 38, max = 46, quests = {
        { id = 1048, name = "Into The Scarlet Monastery", level = 33, faction = "H" },
        { id = 1053, name = "In the Name of the Light", level = 34, faction = "A" },
    } },
    { key = "rfd", abbr = "RFD", name = "Razorfen Downs", min = 35, max = 44, quests = {
        { id = 3341, name = "Bring the End", level = 37, faction = "H" },
        { id = 6521, name = "An Unholy Alliance", level = 28, faction = "H" },
        { id = 3636, name = "Bring the Light", level = 39, faction = "A" },
        { id = 6626, name = "A Host of Evil", level = 28 },
        { id = 3523, name = "Scourge of the Downs", level = 32 },
        { id = 3525, name = "Extinguishing the Idol", level = 32 },
    } },
    { key = "uld", abbr = "Uld", name = "Uldaman", min = 37, max = 47, quests = {
        { id = 2342, name = "Reclaimed Treasures", level = 33, faction = "H" },
        { id = 2202, name = "Uldaman Reagent Run", level = 36, faction = "H" },
        { id = 2283, name = "Necklace Recovery", level = 37, faction = "H" },
        { id = 1360, name = "Reclaimed Treasures", level = 33, faction = "A" },
        { id = 2398, name = "The Lost Dwarves", level = 35, faction = "A" },
        { id = 2240, name = "The Hidden Chamber", level = 35, faction = "A" },
        { id = 17, name = "Uldaman Reagent Run", level = 38, faction = "A" },
        { id = 704, name = "Agmond's Fate", level = 33, faction = "A" },
        { id = 1139, name = "The Lost Tablets of Will", level = 30, faction = "A" },
        { id = 2198, name = "The Shattered Necklace", level = 37, faction = "A" },
        { id = 2418, name = "Power Stones", level = 30 },
        { id = 709, name = "Solution to Doom", level = 30 },
        { id = 2278, name = "The Platinum Discs", level = 40 },
    } },
    { key = "zf", abbr = "ZF", name = "Zul'Farrak", min = 40, max = 50, quests = {
        { id = 2936, name = "The Spider God", level = 40, faction = "H" },
        { id = 2991, name = "Nekrum's Medallion", level = 40, faction = "A" },
        { id = 2768, name = "Divino-matic Rod", level = 40 },
        { id = 2865, name = "Scarab Shells", level = 40 },
        { id = 3042, name = "Troll Temper", level = 40 },
        { id = 2846, name = "Tiara of the Deep", level = 40 },
        { id = 2770, name = "Gahz'rilla", level = 40 },
        { id = 3527, name = "The Prophecy of Mosh'aru", level = 40 },
    } },
    { key = "mara", abbr = "Mar", name = "Maraudon", min = 41, max = 50, quests = {
        { id = 7068, name = "Shadowshard Fragments", level = 39, faction = "H" },
        { id = 7070, name = "Shadowshard Fragments", level = 39, faction = "A" },
        { id = 7029, name = "Vyletongue Corruption", level = 41, alt = { 7041 } },
        { id = 7064, name = "Corruption of Earth and Seed", level = 45, alt = { 7065 } },
        { id = 7028, name = "Twisted Evils", level = 41 },
        { id = 7044, name = "Legends of Maraudon", level = 41 },
        { id = 7066, name = "Seed of Life", level = 39 },
        { id = 7067, name = "The Pariah's Instructions", level = 39 },
        { id = 7046, name = "The Scepter of Celebras", level = 41 },
    } },
    { key = "st", abbr = "ST", name = "Temple of Atal'Hakkar", min = 46, max = 54, quests = {
        { id = 1445, name = "The Temple of Atal'Hakkar", level = 38, faction = "H" },
        { id = 4146, name = "Zapper Fuel", level = 47, faction = "H" },
        { id = 4143, name = "Haze of Evil", level = 47, faction = "A" },
        { id = 1475, name = "Into The Temple of Atal'Hakkar", level = 38, faction = "A" },
        { id = 1446, name = "Jammal'an the Prophet", level = 38 },
        { id = 3373, name = "The Essence of Eranikus", level = 48 },
        { id = 3447, name = "Secret of the Circle", level = 46 },
        { id = 3528, name = "The God Hakkar", level = 40 },
    } },
    { key = "brd", abbr = "BRD", name = "Blackrock Depths", min = 50, max = 60, quests = {
        { id = 4081, name = "KILL ON SIGHT: Dark Iron Dwarves", level = 48, faction = "H" },
        { id = 4134, name = "Lost Thunderbrew Recipe", level = 50, faction = "H" },
        { id = 4082, name = "KILL ON SIGHT: High Ranking Dark Iron Officials", level = 50, faction = "H" },
        { id = 4063, name = "The Rise of the Machines", level = 52, faction = "H" },
        { id = 3906, name = "Disharmony of Flame", level = 48, faction = "H" },
        { id = 3907, name = "Disharmony of Fire", level = 48, faction = "H" },
        { id = 3981, name = "Commander Gor'shak", level = 48, faction = "H" },
        { id = 7201, name = "The Last Element", level = 48, faction = "H" },
        { id = 4132, name = "Operation: Death to Angerforge", level = 52, faction = "H" },
        { id = 4003, name = "The Royal Rescue", level = 48, faction = "H" },
        { id = 4262, name = "Overmaster Pyron", level = 48, faction = "A" },
        { id = 4263, name = "Incendius!", level = 48, faction = "A" },
        { id = 4286, name = "The Good Stuff", level = 50, faction = "A" },
        { id = 4126, name = "Hurley Blackbreath", level = 50, faction = "A" },
        { id = 4341, name = "Kharan Mighthammer", level = 50, faction = "A" },
        { id = 4362, name = "The Fate of the Kingdom", level = 50, faction = "A" },
        { id = 4241, name = "Marshal Windsor", level = 48, faction = "A" },
        { id = 4322, name = "Jail Break!", level = 50, faction = "A" },
        { id = 4136, name = "Ribbly Screwspigot", level = 50 },
        { id = 4123, name = "The Heart of the Mountain", level = 50 },
        { id = 7848, name = "Attunement to the Core", level = 55 },
        { id = 3802, name = "Dark Iron Legacy", level = 48 },
        { id = 4201, name = "The Love Potion", level = 50 },
        { id = 4024, name = "A Taste of Flame", level = 52 },
    } },
    { key = "dme", abbr = "DME", name = "Dire Maul: East", min = 52, max = 60, quests = {
        { id = 7489, name = "Lethtendris's Web", level = 54, alt = { 7488 } },
        { id = 7441, name = "Pusillin and the Elder Azj'Tordin", level = 54 },
        { id = 5526, name = "Shards of the Felvine", level = 56 },
    } },
    { key = "dmw", abbr = "DMW", name = "Dire Maul: West", min = 54, max = 60, quests = {
        { id = 7461, name = "The Madness Within", level = 56 },
        { id = 7507, name = "Foror's Compendium", level = 60 },
    } },
    { key = "dmn", abbr = "DMN", name = "Dire Maul: North", min = 54, max = 60, quests = {
        { id = 7481, name = "Elven Legends", level = 54, alt = { 7482 } },
        { id = 5525, name = "Free Knot!", level = 56 },
        { id = 5518, name = "The Gordok Ogre Suit", level = 56 },
        { id = 5528, name = "The Gordok Taste Test", level = 56 },
        { id = 7703, name = "Unfinished Gordok Business", level = 56 },
    } },
    { key = "lbrs", abbr = "LBR", name = "Lower Blackrock Spire", min = 55, max = 60, quests = {
        { id = 4724, name = "The Pack Mistress", level = 55, faction = "H" },
        { id = 4981, name = "Operative Bijou", level = 55, faction = "H" },
        { id = 4903, name = "Warlord's Command", level = 55, faction = "H" },
        { id = 4701, name = "Put Her Down", level = 55, faction = "A" },
        { id = 5089, name = "General Drakkisath's Command", level = 55, faction = "A" },
        { id = 5001, name = "Bijou's Belongings", level = 55, faction = "A" },
        { id = 4862, name = "En-Ay-Es-Tee-Why", level = 55 },
        { id = 4729, name = "Kibler's Exotic Pets", level = 55 },
        { id = 4866, name = "Mother's Milk", level = 55 },
        { id = 4742, name = "Seal of Ascension", level = 57 },
        { id = 4867, name = "Urok Doomhowl", level = 55 },
        { id = 4788, name = "The Final Tablets", level = 40 },
    } },
    { key = "sch", abbr = "Sch", name = "Scholomance", min = 54, max = 60, quests = {
    } },
    { key = "drown", abbr = "Drn", name = "The Drowned City", min = 35, max = 40, quests = {
        { id = 95776, name = "The Only Good Brinescale...", level = 38, faction = "H" },
        { id = 96774, name = "Ancient Gurubashi Idol", level = 40, faction = "H" },
        { id = 95775, name = "The Drowned City", level = 40, faction = "H" },
    } },
    { key = "kro", abbr = "Kro", name = "Krol'dok Stronghold", min = 40, max = 45, quests = {
    } },
    { key = "alc", abbr = "Alc", name = "Alcaz Island Prison", min = 48, max = 53, quests = {
    } },
    { key = "bmh", abbr = "BMH", name = "Blackmaw Hold", min = 55, max = 60, quests = {
    } },
    { key = "shp", abbr = "Shp", name = "Shaper's Terrace", min = 58, max = 60, quests = {
    } },
    { key = "stl", abbr = "StL", name = "Stratholme: Living", min = 58, max = 60, quests = {
    } },
    { key = "stu", abbr = "StU", name = "Stratholme: Undead", min = 58, max = 60, quests = {
    } },
    { key = "ubrs", abbr = "UBR", name = "Upper Blackrock Spire", min = 59, max = 60, quests = {
    } },
}
-- sorted by the lowest level, then the highest, then the name
table.sort(OMQ.Dungeons, function(a, b)
    if a.min ~= b.min then return a.min < b.min end
    if a.max ~= b.max then return a.max < b.max end
    return a.name < b.name
end)

local byKey = {}
for _, d in ipairs(OMQ.Dungeons) do
    byKey[d.key] = d
end

function OMQ:DungeonByKey(key) return byKey[key] end

-- dungeons whose range contains the level, in order of the lowest level
function OMQ:DungeonsForLevel(level)
    local out = {}
    for _, d in ipairs(OMQ.Dungeons) do
        if level >= d.min and level <= d.max then out[#out + 1] = d end
    end
    return out
end

-- quests of the dungeon that the faction can take ("Alliance" / "Horde")
function OMQ:DungeonQuests(d, faction)
    local out = {}
    local want = faction == "Alliance" and "A" or (faction == "Horde" and "H" or nil)
    for _, q in ipairs(d.quests) do
        if not q.faction or not want or q.faction == want then out[#out + 1] = q end
    end
    return out
end
