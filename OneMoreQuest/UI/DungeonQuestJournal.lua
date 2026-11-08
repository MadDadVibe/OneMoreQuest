-- Optional dungeon prerequisite journal sample. Progress stays local to this character.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local J = {}
OMQ.DungeonQuestJournal = J

function J.Chain(q)
    local chains = OMQ.DungeonQuestChains or {}
    if chains[q.id] then return chains[q.id] end
    for _, id in ipairs(q.alt or {}) do if chains[id] then return chains[id] end end
end

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function progress(q)
    local CQ = C_QuestLog
    if not CQ then return "unknown" end
    local ids = { q.id }
    for _, id in ipairs(q.alt or {}) do ids[#ids + 1] = id end
    local logged, known = false, true
    for _, id in ipairs(ids) do
        local ok, done = pcall(CQ.IsQuestFlaggedCompleted or function() end, id)
        if ok and not isSecret(done) and done == true then return "done" end
        if not ok or isSecret(done) or type(done) ~= "boolean" then known = false end
        local logOK, idx = pcall(CQ.GetLogIndexForQuestID or function() end, id)
        if logOK and not isSecret(idx) and type(idx) == "number" and idx > 0 then logged = true end
        if not CQ.GetLogIndexForQuestID or not logOK or isSecret(idx)
            or (idx ~= nil and type(idx) ~= "number") then known = false end
    end
    if logged then return "log" end
    return known and "none" or "unknown"
end

-- "ready" means these known prerequisites are met, not that the server will offer the quest.
function J.State(q, chain, before)
    local state = progress(q)
    if state == "done" or state == "log" then return state end
    local node = q
    for _, step in ipairs(chain or {}) do if step.id == q.id then node = step; break end end
    local faction = node.faction or q.faction or (OMQ.QuestPlaces and OMQ.QuestPlaces[q.id] and OMQ.QuestPlaces[q.id][4])
    local playerFaction = UnitFactionGroup and UnitFactionGroup("player")
    local playerCode = playerFaction == "Alliance" and "A" or (playerFaction == "Horde" and "H")
    if faction and playerCode and faction ~= playerCode then return "faction" end
    local identityUnknown = false
    for _, restriction in ipairs({ { node.classes, UnitClass, "class" }, { node.races, UnitRace, "race" } }) do
        if restriction[1] and #restriction[1] > 0 then
            local ok, _, _, id = pcall(restriction[2] or function() end, "player")
            if ok and not isSecret(id) and type(id) == "number" then
                local allowed = false
                for _, value in ipairs(restriction[1]) do if value == id then allowed = true end end
                if not allowed then return restriction[3] end
            else identityUnknown = true end
        end
    end
    local level = UnitLevel and UnitLevel("player")
    if not isSecret(level) and type(level) == "number" and (node.level or q.level) and level < (node.level or q.level) then return "level" end
    if state == "unknown" or not chain or isSecret(level) or type(level) ~= "number" then return "unknown" end
    if node.requiresAll or node.requiresAny then
        for _, id in ipairs(node.requiresAll or {}) do
            local prior = progress({ id = id })
            if prior == "unknown" then return "unknown" end
            if prior ~= "done" then return "prereq" end
        end
        if node.requiresAny and #node.requiresAny > 0 then
            local any, unknown = false, false
            for _, id in ipairs(node.requiresAny) do
                local prior = progress({ id = id })
                any = any or prior == "done"
                unknown = unknown or prior == "unknown"
            end
            if not any then return unknown and "unknown" or "prereq" end
        end
        for _, id in ipairs(node.requiresActive or {}) do
            local prior = progress({ id = id })
            if prior == "unknown" then return "unknown" end
            if prior ~= "log" then return "prereq" end
        end
        if node.requiresStarted and #node.requiresStarted > 0 then return "unknown" end
    else
        for i = 1, before or (#chain - 1) do
            local prior = progress(chain[i])
            if prior == "unknown" then return "unknown" end
            if prior ~= "done" then return "prereq" end
        end
    end
    if chain.complete == false or identityUnknown then return "unknown" end
    return "ready"
end

local de = GetLocale and GetLocale() == "deDE"
local function text(en, german) return de and german or en end
local LABEL = {
    done = text("Done", "Erledigt"), log = text("In quest log", "Im Questlog"),
    level = text("Level too low", "Level zu niedrig"), prereq = text("Needs prerequisites", "Vorquests fehlen"),
    ready = text("Known prerequisites met", "Bekannte Vorquests erledigt"), unknown = text("Unknown", "Unbekannt"),
    faction = text("Other faction", "Andere Fraktion"),
    class = text("Other class", "Andere Klasse"), race = text("Other race", "Anderes Volk"),
}

local function questTitle(q)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, name = pcall(C_QuestLog.GetTitleForQuestID, q.id)
        if ok and not isSecret(name) and type(name) == "string" and name ~= "" then return name end
    end
    local chain = J.Chain(q)
    return (de and (q.nameDe or (chain and chain[#chain].nameDe))) or q.name
end

local function stepData(q)
    if q.start then return q end
    local chain = J.Chain(q)
    return chain and chain[#chain] or q
end

local function placeData(q)
    local places = OMQ.QuestPlaces or {}
    if places[q.id] then return places[q.id] end
    for _, id in ipairs(q.alt or {}) do if places[id] then return places[id] end end
end

local function zone(map)
    if not map then return text("Unknown region", "Unbekannte Region") end
    if OMQ.Ready and OMQ.Ready.ZoneName then return OMQ.Ready.ZoneName(map) end
    return "map " .. map
end

function J.Level(q)
    local data, step = placeData(q), stepData(q)
    local level = step.questLevel or (data and data[3])
    return (level and level > 0 and level) or q.level or 0
end

-- Positions are database locations, never a live scan of creatures.
function J.Locations(q, phase)
    local step, data = stepData(q), placeData(q)
    local st = OMQ.Ready and OMQ.Ready.QuestStart(step)
    local spots, who, description, note
    if phase == "start" then
        who = st and not st.chain and st.giver or text("quest giver", "Questgeber")
        spots = step.startSpots or (data and data[7])
        if not step.startSpots and step.start and step.start[5] ~= 0 then spots = { { step.start[5], step.start[6], step.start[7] } } end
        description = text("Pick up the quest from ", "Nimm die Quest an bei ") .. who .. "."
        if st and st.chain then note = text("The complete prerequisite chain is not included here.", "Die vollständige Vorquestkette ist hier nicht enthalten.") end
        if st and st.kind == "item" then
            local item = step.startItem and ((de and step.startItem[2]) or step.startItem[1]) or st.giver
            description = text("Begin this quest with the item: ", "Starte diese Quest mit dem Gegenstand: ") .. (item or "?")
                .. text(". Known sources are listed below.", ". Bekannte Fundorte stehen unten.")
        end
        if st and st.kind == "inside" then description = text("Pick up the quest inside the dungeon.", "Nimm die Quest im Dungeon an.") end
    elseif phase == "end" then
        who = step.turnIn and (step.turnIn[de and 2 or 1] or step.turnIn[1]) or text("quest recipient", "Questempfänger")
        spots = step.endSpots or (data and data[8])
        description = text("Turn in the completed quest to ", "Gib die erledigte Quest ab bei ") .. who .. "."
    else
        spots = step.objectiveSpots or (data and data[9])
        description = step.objective and (step.objective[de and 2 or 1] or step.objective[1])
        if C_QuestLog and C_QuestLog.GetQuestObjectives then
            local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, q.id)
            local lines = {}
            if ok and not isSecret(objectives) and type(objectives) == "table" then
                for _, objective in ipairs(objectives) do
                    if not isSecret(objective) and type(objective) == "table" and not isSecret(objective.text) and type(objective.text) == "string" and objective.text ~= "" then
                        lines[#lines + 1] = objective.text
                    end
                end
            end
            if #lines > 0 then description = table.concat(lines, "; ") end
        end
        if not description then description = text("Complete the quest objectives shown in your quest log.", "Erledige die im Questlog beschriebenen Ziele.") end
        if step.delivery and step.turnIn then
            local recipient = (de and step.turnIn[2]) or step.turnIn[1]
            description = text("Visit ", "Suche ") .. (recipient or "?") .. text(" for this step.", " für diesen Schritt auf.")
        end
        local inside = step.inside or (data and data[13] and math.floor(data[13] / 8) % 2 == 1)
        if (not spots or #spots == 0) and not inside and (step.delivery or (step.objectiveSpots == nil and step.objective)) then
            spots = step.endSpots or (data and data[8])
        end
        note = inside and text("For objectives inside a dungeon, unverified interior coordinates are not marked.",
            "Dungeonziele ohne verifizierte Koordinaten im Inneren werden nicht markiert.")
            or text("Map markers show known objective locations, not live mob positions.", "Kartenpunkte zeigen bekannte Zielorte, keine Live-Positionen von Mobs.")
    end
    local targets = {}
    for _, p in ipairs(spots or {}) do
        if not isSecret(p) and type(p) == "table" and not isSecret(p[1]) and not isSecret(p[2]) and not isSecret(p[3])
            and type(p[1]) == "number" and p[1] > 0 and p[1] < math.huge and p[1] % 1 == 0 and type(p[2]) == "number" and p[2] >= 0 and p[2] <= 100
            and type(p[3]) == "number" and p[3] >= 0 and p[3] <= 100 then
            local at = type(p[4]) == "string" and ((de and p[5]) or p[4]) or who
            local action = phase == "start" and text("Pick up: ", "Annehmen: ") or (phase == "end" and text("Turn in: ", "Abgeben: ") or text("Objectives: ", "Erledigen: "))
            targets[#targets + 1] = { map = p[1], x = p[2], y = p[3], label = action .. questTitle(q) .. (at and (" - " .. at) or ""), who = at, region = zone(p[1]) }
        end
    end
    table.sort(targets, function(a, b)
        if a.region ~= b.region then return a.region < b.region end
        if a.map ~= b.map then return a.map < b.map end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return { description = description, note = note, targets = targets }
end

function J.Quests(d, faction)
    local quests, seen = {}, {}
    for _, list in ipairs({ d.quests, (OMQ.DungeonQuestAdditions or {})[d.key] or {} }) do
        for _, q in ipairs(list) do
            local variants = { q.id }
            for _, id in ipairs(q.alt or {}) do variants[#variants + 1] = id end
            for _, id in ipairs(variants) do
                if not seen[id] then
                    local chain = (OMQ.DungeonQuestChains or {})[id]
                    local node = chain and chain[#chain] or q
                    local entry = {}
                    for key, value in pairs(q) do entry[key] = value end
                    entry.id, entry.alt = id, nil
                    entry.name, entry.nameDe, entry.level = node.name, node.nameDe, node.level
                    entry.faction, entry.classes, entry.races = node.faction or q.faction, node.classes, node.races
                    quests[#quests + 1] = entry
                    seen[id] = true
                end
            end
        end
    end
    return OMQ:DungeonQuests({ quests = quests }, faction)
end

-- Group dungeon quests by pickup region; each expanded chain keeps its prerequisite order.
function J.Groups(d)
    local groups, byMap = {}, {}
    local faction = J.faction or (UnitFactionGroup and UnitFactionGroup("player"))
    if faction == "Both" then faction = nil end
    for _, q in ipairs(J.Quests(d, faction)) do
        local first = J.Locations(q, "start").targets[1]
        local map = first and first.map or 0
        if not byMap[map] then
            byMap[map] = { map = map, name = zone(map ~= 0 and map or nil), quests = {}, level = J.Level(q) }
            groups[#groups + 1] = byMap[map]
        end
        local group = byMap[map]
        group.quests[#group.quests + 1] = q
        group.level = math.min(group.level, J.Level(q))
    end
    for _, group in ipairs(groups) do
        table.sort(group.quests, function(a, b)
            if J.Level(a) ~= J.Level(b) then return J.Level(a) < J.Level(b) end
            return a.id < b.id
        end)
    end
    table.sort(groups, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.map < b.map
    end)
    return groups
end

local frame, title, scroll, content, emptyNotice, detailsTitle, detailsText, targetContent, targetScroll, logButton
local buttons, expanded, groupHeads, targetButtons, actionButtons = {}, {}, {}, {}, {}
local ROW_H, ROW_W, DETAIL_X = 56, 390, 438

function J:Select(q, chain)
    self.selected = q
    self.selectedChain = chain or J.Chain(q)
    self.phase = progress(q) == "log" and "obj" or "start"
    if self.phase == "obj" and OMQ.NextQuest and OMQ.NextQuest.IsComplete(q.id) then self.phase = "end" end
    self.targetIndex = 1
    if targetScroll then targetScroll:SetVerticalScroll(0) end
    self:RenderDetails()
end

function J:ShowMap()
    local target = self.targets and self.targets[self.targetIndex or 1]
    if not target or not OMQ.QuestLocations then return false end
    local ok, reason = OMQ.QuestLocations:Show(self.targets, target.map)
    if ok then frame:Hide() else OMQ:Print(reason) end
    return ok
end

function J:GuideToTarget()
    local target = self.targets and self.targets[self.targetIndex or 1]
    if not target then return false end
    local w = OMQ.Guide and OMQ.Guide.WorldOf({ nil, nil, target.map, target.x, target.y })
    if not w then OMQ:Print(text("No world position is available for this target.", "Für dieses Ziel ist keine Weltposition verfügbar.")); return false end
    if not OMQ.Guide:StartAt(target.label, w[1], w[2], w[3], nil, nil,
        { name = target.who or target.region, radius = self.phase == "obj" and 40 or 12 }) then
        OMQ:Print(text("Guidance is disabled.", "Die Wegführung ist deaktiviert.")); return false
    end
    frame:Hide()
    return true
end

function J:ShareTarget()
    local target = self.targets and self.targets[self.targetIndex or 1]
    if not target or not OMQ.QuestLocations then return false end
    local ok, reason = OMQ.QuestLocations:Share(target)
    OMQ:Print(ok and text("Destination sent to the group.", "Ziel an die Gruppe gesendet.") or reason)
    return ok
end

local function build()
    frame = CreateFrame("Frame", "OneMoreQuestDungeonJournal", UIParent)
    frame:SetSize(940, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.07, 0.08, 0.105, 0.98)
    if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestDungeonJournal") end
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 40, -14)
    title:SetWidth(800)
    title:SetJustifyH("LEFT")
    local function button(label, x, fn)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(26, 24)
        b:SetPoint("TOPLEFT", x, -8)
        b:SetText(label)
        b:SetScript("OnClick", fn)
    end
    button("<", 8, function() J:Step(-1) end)
    button(">", 870, function() J:Step(1) end)
    button("x", 904, function() frame:Hide() end)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 12, -40)
    note:SetWidth(900)
    note:SetJustifyH("LEFT")
    note:SetText(text("Quest journal proposal: pickup regions, then quest level. Click a quest for directions; expand for prerequisites.\nMissing source data stays unknown. Map markers show database locations, not live creatures.",
        "Questlogbuch-Vorschlag: Annahmegebiete, dann Questlevel. Quest anklicken für Wegbeschreibung und Vorquests.\nFehlende Quelldaten bleiben unbekannt. Kartenpunkte zeigen Datenbankorte, keine Live-Mobs."))
    for i, option in ipairs({ { "Horde", "Horde" }, { "Alliance", text("Alliance", "Allianz") }, { "Both", text("Both factions", "Beide Fraktionen") } }) do
        local key = option[1]
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(126, 22)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 130, -77)
        b:SetText(option[2])
        b:SetScript("OnClick", function() J.faction = key; J.selected = nil; scroll:SetVerticalScroll(0); J:Render() end)
    end
    scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -108)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 408, 12)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_W, 1)
    scroll:SetScrollChild(content)
    emptyNotice = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyNotice:SetPoint("TOPLEFT", 12, -111)
    emptyNotice:SetWidth(ROW_W)
    emptyNotice:SetJustifyH("LEFT")
    emptyNotice:SetText(text("No quests are listed for your faction in this dungeon.",
        "Für deine Fraktion sind für diesen Dungeon keine Quests hinterlegt."))
    emptyNotice:Hide()
    detailsTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailsTitle:SetPoint("TOPLEFT", DETAIL_X, -80)
    detailsTitle:SetWidth(480)
    detailsTitle:SetJustifyH("LEFT")
    for i, phase in ipairs({ { "start", text("Pick up", "Annehmen") }, { "obj", text("Objectives", "Erledigen") }, { "end", text("Turn in", "Abgeben") } }) do
        local key = phase[1]
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(128, 24)
        b:SetPoint("TOPLEFT", DETAIL_X + (i - 1) * 132, -110)
        b:SetText(phase[2])
        b:SetScript("OnClick", function() J.phase = key; J.targetIndex = 1; targetScroll:SetVerticalScroll(0); J:RenderDetails() end)
    end
    detailsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailsText:SetPoint("TOPLEFT", DETAIL_X, -145)
    detailsText:SetWidth(480)
    detailsText:SetHeight(110)
    detailsText:SetJustifyH("LEFT")
    detailsText:SetJustifyV("TOP")
    targetScroll = CreateFrame("ScrollFrame", "OneMoreQuestJournalTargets", frame, "UIPanelScrollFrameTemplate")
    targetScroll:SetPoint("TOPLEFT", DETAIL_X, -263)
    targetScroll:SetPoint("BOTTOMRIGHT", -32, 83)
    targetContent = CreateFrame("Frame", nil, targetScroll)
    targetContent:SetSize(460, 1)
    targetScroll:SetScrollChild(targetContent)
    local actions = {
        { text("Map: region targets", "Karte: Ziele der Region"), 160, function() J:ShowMap() end },
        { text("My arrow", "Mein Pfeil"), 105, function() J:GuideToTarget() end },
        { text("Tell group", "Gruppe informieren"), 195, function() J:ShareTarget() end },
    }
    local x = DETAIL_X
    for _, action in ipairs(actions) do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(action[2], 26)
        b:SetPoint("BOTTOMLEFT", x, 44)
        b:SetText(action[1])
        b:SetScript("OnClick", action[3])
        actionButtons[#actionButtons + 1] = b
        x = x + action[2] + 4
    end
    logButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    logButton:SetSize(180, 24)
    logButton:SetPoint("BOTTOMLEFT", DETAIL_X, 12)
    logButton:SetText(text("Open quest log", "Questlog öffnen"))
    logButton:SetScript("OnClick", function()
        if not J.selected or progress(J.selected) ~= "log" then return end
        if OMQ.Ready:QuestClick(J.selected) == "log" then frame:Hide() end
    end)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then elapsed = 0; J:Render() end
    end)
end

local function rowButton(i)
    if buttons[i] then return buttons[i] end
    local b = CreateFrame("Button", nil, content)
    b:SetSize(ROW_W, ROW_H)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.title:SetPoint("TOPLEFT", 2, -3)
    b.title:SetWidth(ROW_W - 4)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)
    b.detail = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.detail:SetPoint("TOPLEFT", 2, -22)
    b.detail:SetWidth(ROW_W - 4)
    b.detail:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self)
        if self.parentId then
            expanded[self.parentId] = not expanded[self.parentId]
            J:Select(self.quest, self.chain)
            J:Render()
        else J:Select(self.quest, self.chain) end
    end)
    buttons[i] = b
    return b
end

local function prerequisiteNote(q, chain)
    local node = stepData(q)
    local ids, prefix
    if node.requiresActive and #node.requiresActive > 0 then
        ids, prefix = node.requiresActive, text("Keep this prerequisite in your quest log: ", "Diese Vorquest muss im Questlog sein: ")
    elseif node.requiresAny and #node.requiresAny > 1 then
        ids, prefix = node.requiresAny, text("One of these prerequisites is sufficient: ", "Eine dieser Vorquests genügt: ")
    elseif node.requiresAll and #node.requiresAll > 1 then
        ids, prefix = node.requiresAll, text("All of these prerequisites are required: ", "Alle diese Vorquests sind erforderlich: ")
    else return "" end
    local names = {}
    for _, id in ipairs(ids) do
        local prior = { id = id, name = "Quest #" .. id }
        for _, step in ipairs(chain or {}) do if step.id == id then prior = step; break end end
        names[#names + 1] = questTitle(prior)
    end
    return prefix .. table.concat(names, ", ") .. "\n"
end

function J:RenderDetails()
    if not detailsTitle then return end
    for _, b in ipairs(targetButtons) do b:Hide() end
    local q = self.selected
    if not q then
        detailsTitle:SetText(text("Select a quest", "Wähle eine Quest aus"))
        detailsText:SetText(text("Click a quest on the left to see who to visit, where its objectives are and where to turn it in.",
            "Klicke links auf eine Quest. Hier siehst du, zu wem du gehen musst, wo ihre Ziele liegen und wo du sie abgibst."))
        self.targets = {}
    else
        local locations = J.Locations(q, self.phase or "start")
        self.targets = locations.targets
        self.targetIndex = math.max(1, math.min(self.targetIndex or 1, #self.targets))
        detailsTitle:SetText(questTitle(q) .. " |cff9aa0aa(" .. text("level ", "Level ") .. J.Level(q) .. ")|r")
        detailsText:SetText(LABEL[J.State(q, self.selectedChain)] .. "\n" .. locations.description .. "\n\n"
            .. prerequisiteNote(q, self.selectedChain)
            .. (q.wingUnknown and text("Dungeon complex: exact wing is not verified.\n", "Dungeonkomplex: genauer Flügel nicht belegt.\n") or "")
            .. (self.selectedChain and self.selectedChain.complete == false and text("Prerequisite source data is incomplete.\n", "Die Quelldaten der Vorquestkette sind unvollständig.\n") or "")
            .. (locations.note or "") .. (#self.targets == 0 and ("\n" .. text("No verified map location is available.", "Kein verifizierter Kartenort verfügbar.")) or ""))
        for i, target in ipairs(self.targets) do
            if not targetButtons[i] then
                local b = CreateFrame("Button", nil, targetContent, "UIPanelButtonTemplate")
                b:SetSize(456, 34)
                b:SetPoint("TOPLEFT", 0, -(i - 1) * 38)
                b:SetScript("OnClick", function(self) J.targetIndex = self.index; J:RenderDetails() end)
                targetButtons[i] = b
            end
            local b = targetButtons[i]
            b.index = i
            b:SetText((i == self.targetIndex and "> " or "") .. target.region
                .. string.format(" (%.1f, %.1f)", target.x, target.y) .. (target.who and (" - " .. target.who) or ""))
            b:Show()
        end
    end
    targetContent:SetHeight(math.max(1, #self.targets * 38))
    for _, b in ipairs(actionButtons) do b:SetEnabled(#self.targets > 0) end
    logButton:SetShown(q and progress(q) == "log" and true or false)
end

function J:Render()
    if not frame or not frame:IsShown() then return end
    local d = OMQ:DungeonByKey(self.dungeon)
    if not d then return end
    local faction = self.faction or (UnitFactionGroup and UnitFactionGroup("player"))
    local factionName = faction == "Both" and text("Both factions", "Beide Fraktionen")
        or (faction == "Alliance" and text("Alliance", "Allianz") or "Horde")
    title:SetText(text("Quest journal: ", "Questlogbuch: ") .. d.name .. " - " .. factionName)
    local n, y = 0, 0
    local function add(q, state, parentId, detail, chain)
        n = n + 1
        local b = rowButton(n)
        b.quest, b.state, b.parentId = q, state, parentId
        b.chain = chain
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        y = y + ROW_H
        local prefix = parentId and (expanded[parentId] and "[-] " or "[+] ") or "    "
        b.title:SetText(prefix .. questTitle(q) .. "  |cff9aa0aa" .. J.Level(q) .. "|r")
        b.detail:SetText(LABEL[state] .. " | " .. detail)
        b:Show()
    end
    local groups = J.Groups(d)
    for g, group in ipairs(groups) do
        if not groupHeads[g] then groupHeads[g] = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") end
        local head = groupHeads[g]
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", 0, -y)
        head:SetText(group.name)
        head:Show()
        y = y + 24
        for _, q in ipairs(group.quests) do
            local chain = J.Chain(q)
            add(q, J.State(q, chain), q.id, text("Click: directions and prerequisites", "Klick: Wegbeschreibung und Vorquests"), chain)
            if expanded[q.id] then
                for i, step in ipairs(chain or { q }) do
                    local first = J.Locations(step, "start").targets[1]
                    add(step, J.State(step, chain, i - 1), nil, "#" .. step.id .. " - " .. (first and first.region or zone()), chain)
                end
            end
        end
    end
    for i = #groups + 1, #groupHeads do groupHeads[i]:Hide() end
    for i = n + 1, #buttons do buttons[i]:Hide() end
    if n == 0 then
        emptyNotice:SetText(#d.quests == 0
            and text("The source has no verified quests for this dungeon yet.", "Die Quelle enthält für diesen Dungeon noch keine verifizierten Quests.")
            or text("No quests are listed for the selected faction in this dungeon.", "Für die gewählte Fraktion sind in diesem Dungeon keine Quests hinterlegt."))
    end
    emptyNotice:SetShown(n == 0)
    content:SetHeight(math.max(1, y))
    self:RenderDetails()
end

function J:Open(key)
    local d = OMQ:DungeonByKey(key)
    if not d then return false end
    if not frame then build() end
    self.selected, self.selectedChain, self.targets = nil, nil, {}
    self.dungeon = key
    scroll:SetVerticalScroll(0)
    frame:Show()
    self:Render()
    return true
end

function J:Step(dir)
    for i, d in ipairs(OMQ.Dungeons) do
        if d.key == self.dungeon then return self:Open(OMQ.Dungeons[(i - 1 + dir) % #OMQ.Dungeons + 1].key) end
    end
end

OMQ:RegisterCommand("journal", function(arg)
    local key = arg and arg:match("^%s*(%S+)")
    key = key or (OMQ.Ready and OMQ.Ready.dungeon) or "dm"
    if not J:Open(key) then OMQ:Print(text("Unknown dungeon key: ", "Unbekannter Dungeon: ") .. key) end
end, "SAMPLE: dungeon prerequisite quest journal [dungeon key]")
