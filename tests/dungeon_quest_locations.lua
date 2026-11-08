-- Run from the repository root: lua5.1 tests/dungeon_quest_locations.lua
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local OMQ = { RegisterCommand = function() end, RegisterMessage = function() end, On = function() end }
_G.OneMoreQuest = OMQ
GetLocale = function() return "enUS" end
local faction = "Horde"
UnitFactionGroup = function() return faction end
UnitLevel = function() return 60 end
local secretValues = {}
issecretvalue = function(value) return secretValues[value] or false end
C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, GetLogIndexForQuestID = function() end }
local names = { [1413] = "The Barrens", [1433] = "Redridge Mountains", [1436] = "Westfall", [1453] = "Stormwind City" }
C_Map = { GetMapInfo = function(map) return { name = names[map] or ("map " .. map) } end }
CreateFrame = function() error("pure model loading must not build UI") end
local function loadAddon(path) assert(loadfile("OneMoreQuest/" .. path))("OneMoreQuest", OMQ) end
for _, path in ipairs({ "Data/DungeonQuests.lua", "Data/DungeonGuide.lua", "Data/QuestPlaces.lua",
    "Data/ForeverDungeons.lua", "Data/DungeonQuestChains.lua", "UI/Ready.lua", "UI/DungeonQuestJournal.lua" }) do loadAddon(path) end
local J = OMQ.DungeonQuestJournal
local function step(id)
    for _, chain in pairs(OMQ.DungeonQuestChains) do
        for _, q in ipairs(chain) do if q.id == id then return q end end
    end
    error("missing verified quest step " .. id)
end

local q65, q135, q865 = step(65), step(135), step(865)
local start = J.Locations(q65, "start")
equal(start.targets[1].map, 1436, "Defias 65 pickup is Westfall")
equal(start.targets[1].who, "Gryan Stoutmantle", "pickup names its own giver")
equal(start.targets[1].region, "Westfall", "pickup uses the map's region name")
assert(start.description:find("Gryan Stoutmantle", 1, true), "pickup instruction names the NPC")
local finish = J.Locations(q65, "end")
equal(finish.targets[1].map, 1433, "Defias 65 ends in Redridge")
equal(finish.targets[1].who, "Wiley the Black", "turn-in names the recipient rather than pickup NPC")
equal(J.Locations(q135, "end").targets[1].map, 1453, "Defias 135 ends in Stormwind")
equal(J.Locations(q135, "obj").targets[1].map, 1453, "courier objective points at its delivery recipient")
equal(J.Level(q65), 18, "sort level is quest difficulty, not acceptance level")
equal(J.Level(step(166)), 22, "final Defias step retains dungeon quest level")
equal(J.Level(q865), 18, "sample-only quest has an actual quest level")
equal(J.Level({ id = 999999, level = 7 }), 7, "unknown quest falls back to its declared level")

local raptorStart, raptorEnd, raptorGoals = J.Locations(q865, "start"), J.Locations(q865, "end"), J.Locations(q865, "obj")
equal(raptorStart.targets[1].map, 1413, "missing QuestPlaces pickup uses verified step metadata")
equal(raptorEnd.targets[1].map, 1413, "sample turn-in override remains usable")
equal(raptorEnd.targets[1].who, "Mebok Mizzyrix", "sample turn-in names Mebok")
assert(#raptorGoals.targets > 0, "verified representative mob positions are available")
assert(raptorGoals.description:find("Raptor", 1, true), "sample instruction explains its objective")
for _, target in ipairs(raptorGoals.targets) do
    equal(target.map, 1413, "raptor markers remain in the Barrens")
    assert(target.x >= 0 and target.x <= 100 and target.y >= 0 and target.y <= 100, "objective coordinates are valid map percentages")
end
local firstX = raptorGoals.targets[1].x
raptorGoals.targets[1].x = 999
equal(J.Locations(q865, "obj").targets[1].x, firstX, "returned targets do not mutate source data")

for _, id in ipairs({ 166, 5728 }) do
    local inside = J.Locations(step(id), "obj")
    equal(#inside.targets, 0, "interior dungeon objectives have no invented world coordinates")
    assert(inside.note and inside.note:find("dungeon", 1, true), "missing interior coordinates are explained")
end
local missing = J.Locations({ id = 999999, name = "Unknown quest", level = 1 }, "obj")
equal(#missing.targets, 0, "missing objective data has no fabricated map target")
assert(type(missing.description) == "string" and missing.description ~= "", "missing objectives remain understandable")

-- A chain-start shortcut is not the final quest's actual pickup NPC.
local bandanas = J.Locations({ id = 214, name = "Red Silk Bandanas", level = 14 }, "start")
equal(bandanas.targets[1].map, 1436, "final quest uses its own pickup region")
assert(bandanas.targets[1].who ~= "Gryan Stoutmantle", "root-chain giver is not mislabelled as final quest giver")

local storedObjective = J.Locations(q865, "obj").description
C_QuestLog.GetQuestObjectives = function() return { { text = "Intact Raptor Horn: 2/5" }, { text = "" }, 7 } end
equal(J.Locations(q865, "obj").description, "Intact Raptor Horn: 2/5", "client objective text takes precedence")
C_QuestLog.GetQuestObjectives = function() error("client cache unavailable") end
equal(J.Locations(q865, "obj").description, storedObjective, "client API errors fall back to database instruction")
local secretText = {}
secretValues[secretText] = true
C_QuestLog.GetQuestObjectives = function() return { { text = secretText } } end
equal(J.Locations(q865, "obj").description, storedObjective, "secret objective text is not exposed")
local secretRow = setmetatable({}, { __index = function() error("secret objective row inspected") end })
secretValues[secretRow] = true
C_QuestLog.GetQuestObjectives = function() return { secretRow } end
equal(J.Locations(q865, "obj").description, storedObjective, "secret objective row is not inspected")
local secretList = { secretRow }
secretValues[secretList] = true
C_QuestLog.GetQuestObjectives = function() return secretList end
equal(J.Locations(q865, "obj").description, storedObjective, "secret objective list is not inspected")
C_QuestLog.GetQuestObjectives = nil

local invalid = { id = 999998, name = "Bad coordinates", level = 1, start = { 999998, "Bad coordinates", "Nobody", nil, 0, 0, 0, "npc" },
    objectiveSpots = {
        { 0, 1, 1 }, { 1413.5, 1, 1 }, { math.huge, 1, 1 },
        { 1413, -1, 20 }, { 1413, 20, 101 }, { 1413, 0 / 0, 20 }, { 1413, 20, math.huge },
        { 1413, "20", 20 }, 7,
    } }
equal(#J.Locations(invalid, "obj").targets, 0, "invalid coordinate records are ignored safely")
secretValues[12.5] = true
invalid.objectiveSpots = { { 1413, 12.5, 20 } }
equal(#J.Locations(invalid, "obj").targets, 0, "secret numeric coordinates are not exposed")
secretValues[12.5] = nil

-- Region grouping sorts by real quest level and does not rearrange its input list.
local function fixture(id, map, level)
    return { id = id, name = "Fixture " .. id, level = 1, questLevel = level,
        start = { id, "Fixture", "NPC", nil, map, 20, 30, "npc" } }
end
local high, low, medium, same = fixture(900004, 1436, 20), fixture(900002, 1436, 5), fixture(900003, 1433, 10), fixture(900001, 1436, 5)
local dungeon = { quests = { high, low, medium, same } }
J.faction = "Both"
local groups = J.Groups(dungeon)
equal(#groups, 2, "quests group by pickup region")
equal(groups[1].map, 1436, "region with lower minimum quest level sorts first")
equal(groups[1].quests[1].id, same.id, "equal-level quests sort deterministically by ID")
equal(groups[1].quests[2].id, low.id, "equal-level order is stable")
equal(groups[1].quests[3].id, high.id, "higher quest level follows lower levels in region")
equal(groups[2].map, 1433, "other region remains separately grouped")
equal(dungeon.quests[1], high, "grouping leaves original quest order untouched")
equal(dungeon.quests[2], low, "grouping does not mutate following input quests")

local function count(grouped)
    local total = 0
    for _, group in ipairs(grouped) do total = total + #group.quests end
    return total
end
for _, d in ipairs(OMQ.Dungeons) do
    J.faction = nil
    equal(count(J.Groups(d)), #J.Quests(d, "Horde"), "default character faction for " .. d.key)
    J.faction = "Alliance"
    equal(count(J.Groups(d)), #J.Quests(d, "Alliance"), "Alliance inspection for " .. d.key)
    J.faction = "Horde"
    equal(count(J.Groups(d)), #J.Quests(d, "Horde"), "Horde inspection for " .. d.key)
    J.faction = "Both"
    equal(count(J.Groups(d)), #J.Quests(d), "both factions form the full quest union for " .. d.key)
end

-- Legacy group-check aliases remain unified there; the journal must resolve actual faction variants.
local function byID(quests)
    local out = {}
    for _, q in ipairs(quests) do
        assert(not out[q.id], "journal contains no duplicate quest IDs")
        out[q.id] = q
    end
    return out
end
for _, pair in ipairs({
    { "mara", 7029, 7041, "Vark Battlescar", "Talendria" },
    { "mara", 7064, 7065, "Selendra", "Keeper Marandis" },
    { "dme", 7489, 7488, "Talo Thornhoof", "Latronicus Moonspear" },
    { "dmn", 7481, 7482, "Sage Korolusk", "Scholar Runethorn" },
}) do
    local d, hordeID, allianceID = OMQ:DungeonByKey(pair[1]), pair[2], pair[3]
    local horde, alliance, both = byID(J.Quests(d, "Horde")), byID(J.Quests(d, "Alliance")), byID(J.Quests(d))
    equal(horde[hordeID] ~= nil, true, "Horde keeps its actual quest variant " .. hordeID)
    equal(alliance[allianceID] ~= nil, true, "Alliance receives its actual quest variant " .. allianceID)
    equal(horde[allianceID], nil, "Horde excludes the Alliance variant " .. allianceID)
    equal(alliance[hordeID], nil, "Alliance excludes the Horde variant " .. hordeID)
    equal(J.Locations(horde[hordeID], "start").targets[1].who, pair[4], "Horde directions name its own giver")
    equal(J.Locations(alliance[allianceID], "start").targets[1].who, pair[5], "Alliance directions name its own giver")
    equal(horde[hordeID].alt, nil, "journal Horde progress cannot use an opposite-faction alias")
    equal(alliance[allianceID].alt, nil, "journal Alliance progress cannot use an opposite-faction alias")
    equal(both[hordeID] ~= nil and both[allianceID] ~= nil, true, "Both exposes both distinct faction variants")
    faction = "Alliance"
    C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == hordeID end
    equal(J.State(alliance[allianceID], J.Chain(alliance[allianceID])) ~= "done", true,
        "Horde completion does not complete the Alliance variant")
    C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == allianceID end
    equal(J.State(alliance[allianceID], J.Chain(alliance[allianceID])), "done", "Alliance completion remains recognized")
    local original
    for _, q in ipairs(d.quests) do if q.id == hordeID then original = q end end
    equal(original and original.alt[1], allianceID, "party-check alias metadata remains unchanged")
end
C_QuestLog.IsQuestFlaggedCompleted = function() return false end

print("Dungeon quest locations: " .. checks .. " checks passed")
