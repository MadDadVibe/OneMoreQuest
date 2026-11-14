-- One More Quest: Old Quest Check (decision 601). A check bar icon (always shown) opens a small window with every
-- grey quest of my log (the game's colour: quest level below my level minus the green range), name, level and zone,
-- each with a tick (all ticked, done ones too). One click on "Abandon N quests" abandons every ticked quest at once,
-- no second question. The icon carries the number of grey quests. No chat lines: the window says what happened.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local OQ = {}
OMQ.OldQuests = OQ

local GREY = { 0.62, 0.62, 0.62 }
local GOLD = { 0.89, 0.71, 0.29 }
local W, ROW_H, MAX_ROWS = 360, 20, 35

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function myLevel() return UnitLevel and tonumber((UnitLevel("player"))) or 1 end

-- quests below this level are grey for me (same rule as the quest log's colour)
function OQ.GreyBelow(level)
    local NQ = OMQ.NextQuest
    if NQ and NQ.GreyBelow then return NQ.GreyBelow(level) end
    return level - 5 - math.floor(level / 10)
end

-- is this log quest grey? the level the log shows, else the game's own trivial flag
function OQ.IsGrey(id, qlevel, playerLevel)
    if type(qlevel) == "number" and not isSecret(qlevel) and qlevel > 0 then
        return qlevel < OQ.GreyBelow(playerLevel or myLevel())
    end
    local QA = OMQ.QuestAuto
    if QA and QA.Trivial then return QA.Trivial(id) end
    return false
end

local function isComplete(id, info)
    if info and info.isComplete ~= nil and not isSecret(info.isComplete) then
        return (info.isComplete == true or info.isComplete == 1) and true or false
    end
    local CQ = C_QuestLog
    if CQ and CQ.IsComplete then
        local ok, r = pcall(CQ.IsComplete, id)
        if ok and not isSecret(r) then return r and true or false end
    end
    return false
end

-- the grey quests of my log: { id, title, level, zone, done }, in log order
function OQ.List()
    local out = {}
    local CQ = C_QuestLog
    if not (CQ and CQ.GetNumQuestLogEntries and CQ.GetInfo) then return out end
    local ok, num = pcall(CQ.GetNumQuestLogEntries)
    if not ok or type(num) ~= "number" or isSecret(num) then return out end
    local lvl, zone = myLevel(), nil
    for i = 1, num do
        local okI, info = pcall(CQ.GetInfo, i)
        if okI and type(info) == "table" then
            if info.isHeader then
                zone = not isSecret(info.title) and info.title or nil
            else
                local id = info.questID
                if type(id) == "number" and not isSecret(id) and id > 0 and not info.isHidden
                   and OQ.IsGrey(id, info.level, lvl) then
                    out[#out + 1] = { id = id, title = (not isSecret(info.title) and info.title) or ("Quest " .. id),
                                      level = (not isSecret(info.level)) and info.level or nil, zone = zone,
                                      done = isComplete(id, info) }
                end
            end
        end
    end
    return out
end

function OQ.Count() return #OQ.List() end

-- abandons one quest (modern API, then the old one with the log index); true when the game took the order
function OQ.Abandon(id)
    local CQ = C_QuestLog
    if CQ and CQ.SetSelectedQuest and CQ.SetAbandonQuest and CQ.AbandonQuest then
        local ok = pcall(function() CQ.SetSelectedQuest(id); CQ.SetAbandonQuest(); CQ.AbandonQuest() end)
        return ok
    end
    if SelectQuestLogEntry and SetAbandonQuest and AbandonQuest and CQ and CQ.GetLogIndexForQuestID then
        local okI, idx = pcall(CQ.GetLogIndexForQuestID, id)
        if okI and type(idx) == "number" and idx > 0 then
            return (pcall(function() SelectQuestLogEntry(idx); SetAbandonQuest(); AbandonQuest() end))
        end
    end
    return false
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local win, title, sub, rows, goBtn, note
OQ._view = { rows = {} }
local list, ticked, lastDone = {}, {}, nil

function OQ.Ticked()
    local o = {}
    for _, q in ipairs(list) do if ticked[q.id] ~= false then o[#o + 1] = q.id end end
    return o
end

local function build()
    win = CreateFrame("Frame", "OneMoreQuestOldQuestWindow", UIParent)
    win:SetSize(W, 140)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local border = win:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    local bg = win:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.086, 0.114, 0.97)
    title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Old Quest Check")
    sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 14, -34)
    sub:SetWidth(W - 28)
    sub:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() OQ:Close() end)
    rows = {}
    OQ._rows = rows
    for i = 1, MAX_ROWS do
        local r = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        r:SetSize(20, 20)
        r:SetPoint("TOPLEFT", 10, -52 - (i - 1) * ROW_H)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", r, "RIGHT", 2, 0)
        r.name:SetWidth(W - 50)
        r.name:SetJustifyH("LEFT")
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r:SetScript("OnClick", function(self)
            if self.qid then ticked[self.qid] = self:GetChecked() and true or false end
            OQ:Render(true)
        end)
        rows[i] = r
    end
    note = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetJustifyH("LEFT")
    note:SetWidth(W - 28)
    goBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    goBtn:SetSize(170, 24)
    goBtn:SetScript("OnClick", function() OQ:AbandonTicked() end)
    win:RegisterEvent("QUEST_LOG_UPDATE")
    win:RegisterEvent("QUEST_REMOVED")
    win:RegisterEvent("PLAYER_LEVEL_UP")
    win:SetScript("OnEvent", function() if win:IsShown() then OQ:Render() end end)
    win:Hide()
end

-- keepTicks: a click on a tick only redraws the button text
function OQ:Render(keepTicks)
    if not win then return end
    if not keepTicks then list = OQ.List() end
    local v = { rows = {} }
    OQ._view = v
    local n = math.min(#list, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local r, q = rows[i], list[i]
        if q and i <= n then
            if ticked[q.id] == nil then ticked[q.id] = true end   -- everything ticked at first (A4: all of them)
            r.qid = q.id
            r:SetChecked(ticked[q.id])
            local txt = string.format("[%s] %s", q.level and tostring(q.level) or "?", q.title)
            if q.zone then txt = txt .. "  |cff9a9a9a" .. q.zone .. "|r" end
            if q.done then txt = txt .. "  |cff7fc770(done)|r" end
            r.name:SetText(txt)
            r.name:SetTextColor(GREY[1], GREY[2], GREY[3])
            r:Show()
            v.rows[#v.rows + 1] = { id = q.id, text = txt, ticked = ticked[q.id] }
        else
            r.qid = nil
            r:Hide()
        end
    end
    local sel = #OQ.Ticked()
    v.ticked = sel
    if #list == 0 then
        v.sub = "No grey quests in your log."
    else
        v.sub = string.format("%d grey quest%s - they give almost no XP any more.", #list, #list == 1 and "" or "s")
    end
    sub:SetText(v.sub)
    local y = -52 - math.max(n, 0) * ROW_H - 6
    v.note = lastDone and string.format("%d quest%s abandoned.", lastDone, lastDone == 1 and "" or "s") or ""
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", 14, y)
    note:SetText(v.note)
    if v.note ~= "" then y = y - 16 end
    goBtn:ClearAllPoints()
    goBtn:SetPoint("TOPLEFT", 14, y - 2)
    v.button = string.format("Abandon %d quest%s", sel, sel == 1 and "" or "s")
    goBtn:SetText(v.button)
    v.enabled = sel > 0
    if v.enabled then goBtn:Enable() else goBtn:Disable() end
    win:SetHeight(-(y - 2) + 24 + 12)
    if OMQ.CheckBar and OMQ.CheckBar.SetBadge then OMQ.CheckBar:SetBadge("old", #list) end
end

-- one click: every ticked quest goes (A5: no second question)
function OQ:AbandonTicked()
    local ids = OQ.Ticked()
    local n = 0
    for _, id in ipairs(ids) do
        if OQ.Abandon(id) then n = n + 1; ticked[id] = nil end
    end
    lastDone = n
    OQ:Render()
    return n
end

function OQ:Open()
    if not win then build() end
    lastDone = nil
    ticked = {}
    win:Show()
    OQ:Render()
end
function OQ:Close() if win then win:Hide() end end
function OQ:IsOpen() return win and win:IsShown() and true or false end
function OQ:Toggle() if OQ:IsOpen() then OQ:Close() else OQ:Open() end end

-- the number on the check bar icon follows the log (at most every 2 s)
local pending = false
local function refreshBadge()
    pending = false
    if OMQ.CheckBar and OMQ.CheckBar.SetBadge then OMQ.CheckBar:SetBadge("old", OQ.Count()) end
end
OQ._refreshBadge = refreshBadge
local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function()
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then C_Timer.After(2, refreshBadge) else refreshBadge() end
end)

OMQ:RegisterCommand("old", function() OQ:Toggle() end, "Old Quest Check: grey quests in your log, abandon them with one click")
