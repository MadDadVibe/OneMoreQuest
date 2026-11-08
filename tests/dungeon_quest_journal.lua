-- Run from the repository root: lua5.1 tests/dungeon_quest_journal.lua
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local OMQ = { RegisterCommand = function() end }
_G.OneMoreQuest = OMQ
local function loadAddon(path) assert(loadfile("OneMoreQuest/" .. path))("OneMoreQuest", OMQ) end
loadAddon("Data/DungeonQuests.lua")
loadAddon("Data/DungeonQuestChains.lua")
loadAddon("UI/DungeonQuestJournal.lua")
local J = OMQ.DungeonQuestJournal
local completed, inLog, level = {}, {}, 60
local secret = {}
issecretvalue = function(value) return value == secret end
UnitLevel = function() return level end
local function reset()
    completed, inLog, level = {}, {}, 60
    C_QuestLog = {
        IsQuestFlaggedCompleted = function(id) return completed[id] or false end,
        GetLogIndexForQuestID = function(id) return inLog[id] end,
    }
end

local chains = OMQ.DungeonQuestChains
for id, expected in pairs({ [166] = "65,132,135,141,142,155,166", [1491] = "865,1491", [5728] = "5726,5727,5728" }) do
    local chain, ids = chains[id], {}
    equal(J.Chain({ id = id }), chain, "known chain " .. id)
    for _, step in ipairs(chain) do
        ids[#ids + 1] = step.id
        equal(step.start[1], step.id, "each step points to its own giver")
        assert(step.nameDe and step.level > 0 and step.start[5] > 0, "sample metadata is present")
        assert(step.start[6] >= 0 and step.start[6] <= 100 and step.start[7] >= 0 and step.start[7] <= 100,
            "giver coordinates are map percentages")
    end
    equal(table.concat(ids, ","), expected, "complete ordered chain " .. id)
end

local function listed(key, faction, id)
    for _, q in ipairs(OMQ:DungeonQuests(OMQ:DungeonByKey(key), faction)) do
        if q.id == id then return true end
    end
    return false
end
equal(listed("dm", "Alliance", 166), true, "Alliance sees its Defias quest")
equal(listed("dm", "Horde", 166), false, "Horde does not see the Defias quest")
equal(listed("rfc", "Horde", 5728), true, "Horde sees Hidden Enemies")
equal(listed("rfc", "Alliance", 5728), false, "Alliance does not see Hidden Enemies")
equal(listed("wc", "Alliance", 1491), true, "Alliance sees neutral Smart Drinks")
equal(listed("wc", "Horde", 1491), true, "Horde sees neutral Smart Drinks")

-- Every real sample moves forward one step only after the previous quest is handed in.
for _, chain in pairs(chains) do
    reset()
    local final = chain[#chain]
    equal(J.State(final, chain), "prereq", "terminal starts blocked")
    for i, step in ipairs(chain) do
        equal(J.State(step, chain, i - 1), "ready", "next step has its prerequisites met")
        inLog[step.id] = 4
        equal(J.State(step, chain, i - 1), "log", "accepted step is in log")
        if i < #chain then
            equal(J.State(chain[i + 1], chain, i), "prereq", "accepted is not handed in")
        end
        completed[step.id] = true
        equal(J.State(step, chain, i - 1), "done", "handed in beats in log")
        inLog[step.id] = nil
    end
    equal(J.State(final, chain), "done", "terminal completed")
end

reset()
local chain = chains[1491]
local first, final = chain[1], chain[2]
inLog[first.id] = 0
equal(J.State(first, chain, 0), "ready", "zero log index means absent")
level = 1
equal(J.State(first, chain, 0), "level", "minimum level is checked")
equal(J.State(final, chain), "level", "minimum level precedes prerequisite status")
inLog[final.id] = 2
equal(J.State(final, chain), "log", "in-log beats level and prerequisite requirements")
completed[final.id] = true
equal(J.State(final, chain), "done", "completion beats every other state")

reset()
equal(J.Chain({ id = 999999 }), nil, "uncovered quest has no invented chain")
equal(J.State({ id = 999999, level = 1 }), "unknown", "missing chain data is explicit")
completed[999999] = true
equal(J.State({ id = 999999, level = 1 }), "done", "known progress still shows without chain data")
equal(J.Chain({ id = 999999, alt = { 1491 } }), chain, "alternate ID resolves chain")
local alternate = { id = 999998, alt = { 999997 }, level = 13 }
completed[first.id] = true
inLog[999997] = 3
equal(J.State(alternate, chain), "log", "alternate ID in log")
completed[999998] = true
equal(J.State(alternate, chain), "done", "primary completion beats alternate in log")
completed[999998], completed[999997] = nil, true
equal(J.State(alternate, chain), "done", "alternate completion is recognized")

reset()
C_QuestLog = nil
equal(J.State(first, chain, 0), "unknown", "missing quest API does not mean ready")
reset()
C_QuestLog.IsQuestFlaggedCompleted = nil
equal(J.State(first, chain, 0), "unknown", "missing completion API is unknown")
reset()
C_QuestLog.GetLogIndexForQuestID = nil
equal(J.State(first, chain, 0), "unknown", "missing log API is unknown")
reset()
C_QuestLog.IsQuestFlaggedCompleted = function() error("not available") end
equal(J.State(first, chain, 0), "unknown", "completion API errors are contained")
reset()
C_QuestLog.GetLogIndexForQuestID = function() error("not available") end
equal(J.State(first, chain, 0), "unknown", "log API errors are contained")
reset()
C_QuestLog.IsQuestFlaggedCompleted = function() return secret end
equal(J.State(first, chain, 0), "unknown", "secret completion flag is not inspected")
reset()
C_QuestLog.GetLogIndexForQuestID = function() return secret end
equal(J.State(first, chain, 0), "unknown", "secret log index is not inspected")
reset()
C_QuestLog.IsQuestFlaggedCompleted = function(id)
    if id == first.id then return secret end
    return false
end
equal(J.State(final, chain), "unknown", "unknown prerequisite does not mean ready")

-- Exercise the actual shared quest-start resolver before mocking only the click action.
loadAddon("Data/DungeonGuide.lua")
OMQ.RegisterMessage, OMQ.On = function() end, function() end
loadAddon("UI/Ready.lua")
equal(OMQ.Ready.QuestStart({ id = 166 }).root, 65, "existing dungeon shortcut still resolves the root")
equal(OMQ.Ready.QuestStart({ id = 999999, alt = { 166 } }).root, 65, "existing alternate shortcut survives")
equal(OMQ.Ready.QuestStart(chains[166][2]).root, 132, "journal step resolves its immediate giver")
equal(OMQ.Ready.QuestStart(chains[166][2]).giver, "Wiley the Black", "step does not point back to root giver")
GetLocale = function() return "deDE" end
equal(OMQ.Ready.QuestStart(chains[166][2]).giver, "Wiley der Schwarze", "shared resolver localizes step giver")
GetLocale = nil
reset()
local guided, selected
UnitPosition = function() return 20, 30, 0, 1 end
OMQ.Guide = {
    WorldOf = function() return { 10, 11, 1 } end,
    StartAt = function(_, giver) guided = giver; return true end,
}
QuestMapFrame_OpenToQuestDetails = function(id) selected = id end
equal(OMQ.Ready:Frame(), nil, "Group Check is not built by module loading")
equal(OMQ.Ready:QuestClick(chains[166][2]), "arrow", "journal action works before Group Check opens")
equal(guided, "Wiley the Black", "real action guides to the immediate step giver")
inLog[132] = 0
equal(OMQ.Ready:QuestClick(chains[166][2]), "arrow", "real action treats zero index as absent")
inLog[132] = secret
equal(OMQ.Ready:QuestClick(chains[166][2]), "arrow", "real action ignores secret log index")
inLog[132] = 4
equal(OMQ.Ready:QuestClick(chains[166][2]), "log", "real action opens accepted quest without Group Check")
equal(selected, 132, "real quest-log helper selects the step quest")

-- Failed client actions must not be reported as successful or dismiss the journal.
local notice
OMQ.Print = function(_, message) notice = message end
QuestMapFrame_OpenToQuestDetails = nil
equal(OMQ.Ready:QuestClick(chains[166][2]), "none", "missing quest-log UI does not claim success")
assert(notice, "unavailable quest log is explained")
ToggleQuestLog = function() error("blocked by client") end
equal(OMQ.Ready.OpenQuestLog(132, 4), false, "blocked fallback does not claim success")
ToggleQuestLog = nil
QuestLogFrame = {}
ShowUIPanel = function() error("blocked by client") end
equal(OMQ.Ready.OpenQuestLog(132, 4), false, "blocked panel does not claim success")
local fallbackOpened = false
ToggleQuestLog = function() fallbackOpened = true end
equal(OMQ.Ready.OpenQuestLog(132, 4), true, "blocked panel falls back to another supported API")
equal(fallbackOpened, true, "fallback really executes")
QuestLogFrame, ShowUIPanel, ToggleQuestLog = nil, nil, nil

-- Use the real guidance switch and destination, without starting any game or UI.
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local guidanceOn = false
OMQ.Master = function(_, name) return name == "guidance" and guidanceOn end
OMQ.Fire = function() end
loadAddon("Guide/Guide.lua")
OMQ.Guide.WorldOf = function() return { 10, 11, 1 } end
inLog[132] = nil
equal(OMQ.Guide:StartAt("test giver", 10, 11, 1), false, "disabled guidance reports no destination")
equal(OMQ.Ready:QuestClick(chains[166][2]), "none", "disabled guidance does not claim an arrow")
equal(OMQ.Guide:IsActive(), false, "disabled guidance stays inactive")
guidanceOn = true
equal(OMQ.Guide:StartAt("test giver", 10, 11, 1), true, "enabled guidance reports success")
OMQ.Guide:Clear()
equal(OMQ.Ready:QuestClick(chains[166][2]), "arrow", "real enabled guidance starts from the step action")
equal(OMQ.Guide:IsActive(), true, "successful action has a destination")
OMQ.Guide:Clear()

-- Finite mock API: unimplemented frame methods remain nil so API typos fail this smoke flow.
local frames, methods = {}, {}
local function object(kind, name, parent)
    local o = setmetatable({ kind = kind, name = name, parent = parent, shown = true, scripts = {} }, { __index = methods })
    frames[#frames + 1] = o
    return o
end
for _, name in ipairs({ "SetPoint", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse",
    "RegisterForDrag", "SetAllPoints", "SetColorTexture", "SetJustifyH", "SetWordWrap", "SetHighlightTexture",
    "StartMoving", "StopMovingOrSizing", "ClearAllPoints", "SetTextColor", "SetNormalTexture", "SetPushedTexture" }) do methods[name] = function() end end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetText(value) self.text = value end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetShown(value) self.shown = value end
function methods:GetStringWidth() return #(self.text or "") * 6 end
function methods:CreateTexture() return object("Texture", nil, self) end
function methods:CreateFontString() return object("FontString", nil, self) end
function methods:SetScrollChild(child) self.child = child end
function methods:SetVerticalScroll(value) self.scrollPosition = value end
CreateFrame = object
UIParent, UISpecialFrames = {}, {}
local faction, clicked = "Alliance", nil
UnitFactionGroup = function() return faction end
local realQuestClick = OMQ.Ready.QuestClick
OMQ.Ready.QuestClick = function(_, q) clicked = q; return "arrow" end
local function row(id, parent)
    for _, f in ipairs(frames) do
        if f.shown and f.quest and f.quest.id == id and f.parentId == parent then return f end
    end
end
local function rowCount()
    local n = 0
    for _, f in ipairs(frames) do if f.shown and f.quest then n = n + 1 end end
    return n
end
local function click(button) assert(button, "expected visible button"); button.scripts.OnClick(button) end
reset()
equal(J:Open("not-a-dungeon"), false, "invalid dungeon cannot open")
equal(#frames, 0, "invalid dungeon does not build UI")
equal(J:Open("dm"), true, "journal builds and opens")
local journal, emptyNotice
for _, f in ipairs(frames) do
    if f.name == "OneMoreQuestDungeonJournal" then journal = f end
    if f.text == "No quests are listed for your faction in this dungeon." then emptyNotice = f end
end
assert(emptyNotice, "journal explains an empty faction-filtered list")
equal(journal:IsShown(), true, "journal is shown")
equal(emptyNotice:IsShown(), false, "populated dungeon hides empty notice")
equal(UISpecialFrames[1], journal.name, "Escape can close journal")
local collapsed = rowCount()
click(row(166, 166))
equal(rowCount(), collapsed + #chains[166], "expansion shows full chain")
local mockQuestClick = OMQ.Ready.QuestClick
OMQ.Ready.QuestClick = realQuestClick
guidanceOn = false
click(row(132))
equal(journal:IsShown(), true, "journal stays open when guidance is disabled")
guidanceOn, inLog[132] = true, 4
click(row(132))
equal(journal:IsShown(), true, "journal stays open when no quest-log UI is available")
QuestMapFrame_OpenToQuestDetails = function(id) selected = id end
click(row(132))
equal(journal:IsShown(), false, "successful real quest-log action hides journal")
inLog[132] = nil
OMQ.Ready.QuestClick = mockQuestClick
J:Open("dm")
click(row(132))
equal(clicked, chains[166][2], "step click uses shared quest action with immediate giver data")
equal(journal:IsShown(), false, "arrow action hides journal")
J:Open("dm")
click(row(166, 166))
equal(rowCount(), collapsed, "collapsing hides every stale chain row")
J:Open("sfk")
equal(rowCount(), 0, "dungeon without this faction's quests hides old rows")
equal(emptyNotice:IsShown(), true, "Alliance Shadowfang Keep explains its empty list")
faction = "Horde"
J:Render()
equal(rowCount(), 3, "faction switch displays matching quests")
equal(emptyNotice:IsShown(), false, "populated faction switch hides empty notice")
J:Open("dm")
equal(rowCount(), 0, "Horde cannot see Alliance sample quests")
equal(emptyNotice:IsShown(), true, "Horde Deadmines explains its empty list")
J:Open(OMQ.Dungeons[1].key)
J:Step(-1)
equal(J.dungeon, OMQ.Dungeons[#OMQ.Dungeons].key, "previous wraps to last dungeon")
J:Step(1)
equal(J.dungeon, OMQ.Dungeons[1].key, "next wraps to first dungeon")
J:Step(1)
equal(J.dungeon, OMQ.Dungeons[2].key, "next selects adjacent dungeon")
J:Step(-1)
equal(J.dungeon, OMQ.Dungeons[1].key, "previous selects adjacent dungeon")
for _, f in ipairs(frames) do if f.parent == journal and f.text == "x" then click(f) end end
equal(journal:IsShown(), false, "close button hides journal")

-- Every listed dungeon must remain usable for both factions, including uncovered chains.
local combinations, expansions = 0, 0
for _, side in ipairs({ "Alliance", "Horde" }) do
    faction = side
    for _, d in ipairs(OMQ.Dungeons) do
        J:Open(d.key)
        local quests, expected = OMQ:DungeonQuests(d, side), 0
        for _, q in ipairs(quests) do
            local header = assert(row(q.id, q.id), "dungeon quest header is visible")
            if header.title.text:sub(1, 3) == "[+]" then click(header) end
            expected = expected + 1 + #(J.Chain(q) or { q })
            expansions = expansions + 1
        end
        equal(rowCount(), expected, "full expansion for " .. side .. " " .. d.key)
        for _, q in ipairs(quests) do click(row(q.id, q.id)) end
        equal(rowCount(), #quests, "full collapse for " .. side .. " " .. d.key)
        combinations = combinations + 1
    end
end
print("Dungeon/faction combinations: " .. combinations .. "; quest expansions: " .. expansions)

-- Build the actual Group Check and exercise its journal button for different selections.
GetTime = function() return 100 end
OMQ.Send = function() end
OMQ.Ready.Rows = function() return { { name = "Test", isSelf = true, row = { dur = 100, free = 20 } } } end
faction = "Alliance"
OMQ.Ready:Open("dm")
local ready, journalButton = OMQ.Ready:Frame()
for _, f in ipairs(frames) do
    if f.parent == ready and f.text == "Quest journal (sample)" then journalButton = f end
end
assert(journalButton, "Group Check has a journal button")
equal(journalButton:IsShown(), true, "journal button is visible for a dungeon")
click(journalButton)
equal(J.dungeon, "dm", "Group Check passes its selected dungeon to the journal")
equal(ready:IsShown(), false, "Group Check closes after opening the journal")
OMQ.Ready:Open("wc")
click(journalButton)
equal(J.dungeon, "wc", "journal button follows a changed dungeon selection")
OMQ.Ready:Open()
equal(journalButton:IsShown(), false, "general Group Check hides the dungeon journal button")

print("Dungeon quest journal: " .. checks .. " checks passed")
