-- One More Quest: the quest zones of the Journey (Progress Check), decision 296.
-- { uiMapID, lowest level, highest level, faction ("A", "H", "C" contested), English name }
-- Level ranges as in the classic game guides. The name shown comes from the game (C_Map), so a German client
-- shows the German name; the English one is the fallback. The quest hub is worked out from the quest givers
-- of Data/QuestPlaces.lua (NextQuest.ZoneHub). Zephras Isle (2521) is missing: the quest data has no quests there.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest
OMQ.QuestZones = {
  -- Eastern Kingdoms
  { 1429, 1, 10, "A", "Elwynn Forest" },
  { 1426, 1, 10, "A", "Dun Morogh" },
  { 1420, 1, 10, "H", "Tirisfal Glades" },
  { 1436, 10, 20, "A", "Westfall" },
  { 1432, 10, 20, "A", "Loch Modan" },
  { 1421, 10, 20, "H", "Silverpine Forest" },
  { 1433, 15, 25, "A", "Redridge Mountains" },
  { 1431, 18, 30, "A", "Duskwood" },
  { 1437, 20, 30, "A", "Wetlands" },
  { 1424, 20, 30, "C", "Hillsbrad Foothills" },
  { 1416, 30, 40, "C", "Alterac Mountains" },
  { 1417, 30, 40, "C", "Arathi Highlands" },
  { 1434, 30, 45, "C", "Stranglethorn Vale" },
  { 1418, 35, 45, "C", "Badlands" },
  { 1435, 35, 45, "C", "Swamp of Sorrows" },
  { 1425, 40, 50, "C", "The Hinterlands" },
  { 1427, 43, 50, "C", "Searing Gorge" },
  { 1419, 45, 55, "C", "Blasted Lands" },
  { 1428, 50, 58, "C", "Burning Steppes" },
  { 1422, 51, 58, "C", "Western Plaguelands" },
  { 1423, 53, 60, "C", "Eastern Plaguelands" },
  -- Kalimdor
  { 1411, 1, 10, "H", "Durotar" },
  { 1412, 1, 10, "H", "Mulgore" },
  { 1438, 1, 10, "A", "Teldrassil" },
  { 1439, 10, 20, "A", "Darkshore" },
  { 1413, 10, 25, "H", "The Barrens" },
  { 1442, 15, 27, "C", "Stonetalon Mountains" },
  { 1440, 18, 30, "C", "Ashenvale" },
  { 1441, 25, 35, "C", "Thousand Needles" },
  { 1443, 30, 40, "C", "Desolace" },
  { 1445, 35, 45, "C", "Dustwallow Marsh" },
  { 1444, 40, 50, "C", "Feralas" },
  { 1446, 40, 50, "C", "Tanaris" },
  { 1447, 45, 55, "C", "Azshara" },
  { 1448, 48, 55, "C", "Felwood" },
  { 1449, 48, 55, "C", "Un'Goro Crater" },
  { 1451, 55, 60, "C", "Silithus" },
  { 1452, 55, 60, "C", "Winterspring" },
}
