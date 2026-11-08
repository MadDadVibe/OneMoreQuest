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
    local level = UnitLevel and UnitLevel("player")
    if not isSecret(level) and type(level) == "number" and q.level and level < q.level then return "level" end
    if state == "unknown" or not chain or isSecret(level) or type(level) ~= "number" then return "unknown" end
    for i = 1, before or (#chain - 1) do
        local prior = progress(chain[i])
        if prior == "unknown" then return "unknown" end
        if prior ~= "done" then return "prereq" end
    end
    return "ready"
end

local de = GetLocale and GetLocale() == "deDE"
local function text(en, german) return de and german or en end
local LABEL = {
    done = text("Done", "Erledigt"), log = text("In quest log", "Im Questlog"),
    level = text("Level too low", "Level zu niedrig"), prereq = text("Needs prerequisites", "Vorquests fehlen"),
    ready = text("Known prerequisites met", "Bekannte Vorquests erledigt"), unknown = text("Unknown", "Unbekannt"),
}

local function questTitle(q)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, name = pcall(C_QuestLog.GetTitleForQuestID, q.id)
        if ok and not isSecret(name) and type(name) == "string" and name ~= "" then return name end
    end
    local chain = J.Chain(q)
    return (de and (q.nameDe or (chain and chain[#chain].nameDe))) or q.name
end

local frame, title, scroll, content, emptyNotice
local buttons, expanded = {}, {}
local ROW_H = 52

local function build()
    frame = CreateFrame("Frame", "OneMoreQuestDungeonJournal", UIParent)
    frame:SetSize(650, 460)
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
    title:SetWidth(520)
    title:SetJustifyH("LEFT")
    local function button(label, x, fn)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(26, 24)
        b:SetPoint("TOPLEFT", x, -8)
        b:SetText(label)
        b:SetScript("OnClick", fn)
    end
    button("<", 8, function() J:Step(-1) end)
    button(">", 580, function() J:Step(1) end)
    button("x", 614, function() frame:Hide() end)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 12, -40)
    note:SetWidth(618)
    note:SetJustifyH("LEFT")
    note:SetText(text("SAMPLE: 3 chains (DM / WC / RFC). Click a quest to expand its prerequisites.\nOther chains are unverified. Progress is yours; quest acceptance may have other requirements.",
        "SAMPLE: 3 Ketten (DM / WC / RFC). Quest anklicken, um Vorquests aufzuklappen.\nAndere Ketten sind ungeprüft. Dein Fortschritt; weitere Annahmebedingungen sind möglich."))
    scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -82)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 1)
    scroll:SetScrollChild(content)
    emptyNotice = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyNotice:SetPoint("TOPLEFT", 12, -85)
    emptyNotice:SetWidth(600)
    emptyNotice:SetJustifyH("LEFT")
    emptyNotice:SetText(text("No quests are listed for your faction in this dungeon.",
        "Für deine Fraktion sind für diesen Dungeon keine Quests hinterlegt."))
    emptyNotice:Hide()
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then elapsed = 0; J:Render() end
    end)
end

local function rowButton(i)
    if buttons[i] then return buttons[i] end
    local b = CreateFrame("Button", nil, content)
    b:SetSize(600, ROW_H)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.title:SetPoint("TOPLEFT", 2, -3)
    b.title:SetWidth(596)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)
    b.detail = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.detail:SetPoint("TOPLEFT", 2, -22)
    b.detail:SetWidth(596)
    b.detail:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self)
        if self.parentId then
            expanded[self.parentId] = not expanded[self.parentId]
            J:Render()
        elseif self.state ~= "done" then
            local action = OMQ.Ready:QuestClick(self.quest)
            if action == "log" or action == "arrow" then frame:Hide() end
        end
    end)
    buttons[i] = b
    return b
end

function J:Render()
    if not frame or not frame:IsShown() then return end
    local d = OMQ:DungeonByKey(self.dungeon)
    if not d then return end
    title:SetText(text("Quest journal: ", "Questlogbuch: ") .. d.name)
    local n = 0
    local function add(q, state, parentId, detail)
        n = n + 1
        local b = rowButton(n)
        b.quest, b.state, b.parentId = q, state, parentId
        local prefix = parentId and (expanded[parentId] and "[-] " or "[+] ") or "    "
        b.title:SetText(prefix .. questTitle(q) .. "  |cffd9b65a" .. LABEL[state] .. "|r")
        b.detail:SetText(detail)
        b:Show()
    end
    for _, q in ipairs(OMQ:DungeonQuests(d, UnitFactionGroup and UnitFactionGroup("player"))) do
        local chain = J.Chain(q)
        local detail = chain and text("Click: show / hide the full chain", "Klick: ganze Kette ein- / ausklappen")
            or text("Prerequisite chain not included in this sample", "Vorquestkette in diesem Sample nicht enthalten")
        add(q, J.State(q, chain), q.id, detail)
        if expanded[q.id] then
            for i, step in ipairs(chain or { q }) do
                local st = OMQ.Ready.QuestStart(step)
                local giver = st and (st.giver .. (st.map ~= 0 and (", " .. OMQ.Ready.ZoneName(st.map)) or "")) or "?"
                local hint = text("Click: quest log or arrow to giver", "Klick: Questlog oder Pfeil zum Questgeber")
                add(step, J.State(step, chain, i - 1), nil, "    #" .. step.id .. " - " .. giver .. " | " .. hint)
            end
        end
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end
    emptyNotice:SetShown(n == 0)
    content:SetHeight(math.max(1, n * ROW_H))
end

function J:Open(key)
    local d = OMQ:DungeonByKey(key)
    if not d then return false end
    if not frame then build() end
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
