-- One More Quest: places of the new WoW Forever content that the Questie data does not have (decision 253).
-- Class trainers: warcrafttavern.com class trainer lists (Zephras Isle, Tirisfal paladins, Dun Morogh shamans).
-- The entrances of the new dungeons are in Data/ForeverDungeons.lua (decision 254).
-- Format as in Data/Places.lua: {kind, class, uiMapID, x%, y%, faction ("A","H","AH"), name, highest level taught}
-- The 8th field is optional: the Thendal Village trainers only teach up to level 6, so the arrow skips them later.
-- Not here because no source has coordinates yet: Zephras Isle vendors, innkeepers, profession trainers and the
-- Dalaran trainers. The addon learns those in game and shares them with the group (decision 218).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest
OMQ.fixedPlaces = OMQ.fixedPlaces or {}
local P = OMQ.fixedPlaces
for _, p in ipairs({
  -- Zephras Isle (uiMapID 2521), the Skyborne start zone, both factions
  {"trainer","DRUID",2521,41.7,23.4,"AH","Xyton Silverwind",6},
  {"trainer","HUNTER",2521,42.5,23.7,"AH","Tai'ree Farsight",6},
  {"trainer","MAGE",2521,41.6,23.7,"AH","Dorii Brightwhisper",6},
  {"trainer","ROGUE",2521,43.7,24.3,"AH","Akeri Duskblade",6},
  {"trainer","SHAMAN",2521,42.8,23.6,"AH","Windshaper Boro",6},
  {"trainer","WARRIOR",2521,43.7,24.2,"AH","Blademaster Ren",6},
  {"trainer","DRUID",2521,45.2,44.3,"AH","Naeluna Swiftmend"},
  {"trainer","HUNTER",2521,45.2,44.3,"AH","Elayaa Easewind"},
  {"trainer","MAGE",2521,45.1,45.9,"AH","Shenaan Spellwind"},
  {"trainer","ROGUE",2521,43.1,43.3,"AH","Miriaan Mistblade"},
  {"trainer","SHAMAN",2521,43.5,44.9,"AH","Aarnor Galestrike"},
  {"trainer","WARRIOR",2521,44.9,45.2,"AH","Corsan Earthrazer"},
  {"trainer","DRUID",2521,64.0,75.1,"AH","Lotheluum Starbreeze"},
  {"trainer","HUNTER",2521,59.6,72.7,"AH","Quel'ana Quickgale"},
  {"trainer","MAGE",2521,65.9,80.5,"AH","Anathamaas Aetherwind"},
  {"trainer","ROGUE",2521,59.9,72.5,"AH","Eltheen Nightbreeze"},
  {"trainer","SHAMAN",2521,58.3,78.6,"AH","Sessaria Skystride"},
  {"trainer","WARRIOR",2521,59.8,72.9,"AH","Seena Skybreaker"},
  -- Horde paladins in Tirisfal Glades (1420)
  {"trainer","PALADIN",1420,31.1,66.4,"H","Aramis Hammerhand"},
  {"trainer","PALADIN",1420,60.3,52.6,"H","Shari Stilwell"},
  {"trainer","PALADIN",1420,22.0,47.2,"H","Hilda the Breaker"},
  -- Alliance shamans in Dun Morogh (1426) and Ironforge (1455)
  {"trainer","SHAMAN",1426,28.8,66.2,"A","Teo Hammerstorm"},
  {"trainer","SHAMAN",1426,47.6,52.0,"A","Ingrid Dunwald"},
  {"trainer","SHAMAN",1455,47.3,13.5,"A","Eldrun Stormbreaker"},
}) do P[#P + 1] = p end

