-- One More Quest: quests at the NPC (decision 305), three switches in the AUTOMATIONS tab (was VENDOR), all on by default.
--   Accept: a quest giver's quests are accepted, one after the other, unless they are grey (trivial) for me.
--   Turn in: finished quests are handed in; the reward is taken when there is nothing to choose.
--   Reward hint: with a choice of rewards the best one for me (item score, LootPreview.Gain) gets a gold
--     frame, its tooltip says why (gain, or "sells for most" when none is an upgrade), and it is preselected
--     in the window (decision 308) - "Complete Quest" takes it unless I click another one.
-- Holding Shift while talking to the NPC switches all of it off for that conversation.
-- Quests shared by a dad are left to QuestSync (decision 128).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local QA = {}
OMQ.QuestAuto = QA

local function isSecret(v) return issecretvalue and issecretvalue(v) end
function QA.On(part)
    local o = OMQ.db and OMQ.db.options and OMQ.db.options.qol
    return OMQ:Master("vendor") and (not o or o[part] ~= false)
end
local function paused() return IsShiftKeyDown and IsShiftKeyDown() and true or false end
local function fromPlayer()
    -- a quest shared by a player: the "npc" unit is that player
    return UnitIsPlayer and UnitExists and UnitExists("npc") and UnitIsPlayer("npc") and true or false
end
local function level() return UnitLevel and tonumber((UnitLevel("player"))) or 1 end

-- grey for me? the game says it (isTrivial); else the quest level from the data against the green range
function QA.Trivial(questID, flag)
    if flag ~= nil then return flag and true or false end
    local CQ = C_QuestLog
    if questID and CQ and CQ.IsQuestTrivial then
        local ok, t = pcall(CQ.IsQuestTrivial, questID)
        if ok and t ~= nil and not isSecret(t) then return t and true or false end
    end
    local d = questID and OMQ.QuestPlaces and OMQ.QuestPlaces[questID]
    local NQ = OMQ.NextQuest
    if d and d[3] and d[3] > 0 and NQ and NQ.GreyBelow then return d[3] < NQ.GreyBelow(level()) end
    return false
end

----------------------------------------------------------------------
-- The NPC's list: gossip (modern API, then the old one) and the quest greeting
----------------------------------------------------------------------
local function gossipLists()
    local G = C_GossipInfo
    local avail, active = {}, {}
    if G and G.GetAvailableQuests then
        for _, q in ipairs(G.GetAvailableQuests() or {}) do
            avail[#avail + 1] = { id = q.questID, trivial = q.isTrivial, pick = function() G.SelectAvailableQuest(q.questID) end }
        end
        for _, q in ipairs(G.GetActiveQuests and G.GetActiveQuests() or {}) do
            active[#active + 1] = { id = q.questID, complete = q.isComplete, pick = function() G.SelectActiveQuest(q.questID) end }
        end
        return avail, active
    end
    -- old API: GetGossipAvailableQuests returns 7 values per quest (title, level, trivial, frequency, repeatable, legendary, ignored)
    if GetNumGossipAvailableQuests and SelectGossipAvailableQuest then
        local t = { GetGossipAvailableQuests() }
        for i = 1, GetNumGossipAvailableQuests() do
            local trivial = t[(i - 1) * 7 + 3]
            avail[#avail + 1] = { trivial = trivial, pick = function() SelectGossipAvailableQuest(i) end }
        end
        local a = { GetGossipActiveQuests and GetGossipActiveQuests() or nil }
        for i = 1, (GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0) do
            local complete = a[(i - 1) * 6 + 4]
            active[#active + 1] = { complete = complete, pick = function() SelectGossipActiveQuest(i) end }
        end
    end
    return avail, active
end
local function greetingLists()
    local avail, active = {}, {}
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
        local isTrivial = GetAvailableQuestInfo and select(1, GetAvailableQuestInfo(i))
        avail[#avail + 1] = { trivial = isTrivial, pick = function() SelectAvailableQuest(i) end }
    end
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
        local _, complete = GetActiveTitle(i)
        active[#active + 1] = { complete = complete, pick = function() SelectActiveQuest(i) end }
    end
    return avail, active
end

-- first a finished quest to hand in, then a quest to take
function QA.Choose(avail, active)
    if QA.On("autoTurnIn") then
        for _, q in ipairs(active) do if q.complete then return q, "turnin" end end
    end
    if QA.On("autoAccept") then
        for _, q in ipairs(avail) do if not QA.Trivial(q.id, q.trivial) then return q, "accept" end end
    end
end
-- a quest that cannot be taken (full log) would come back again and again: at most PICKS picks in a row
-- within PICK_WINDOW seconds, then the dad does it by hand
QA.PICKS, QA.PICK_WINDOW = 12, 10
local picks = {}
local function mayPick()
    local now = GetTime()
    for i = #picks, 1, -1 do if now - picks[i] > QA.PICK_WINDOW then table.remove(picks, i) end end
    if #picks >= QA.PICKS then return false end
    picks[#picks + 1] = now
    return true
end
local function onList(lists)
    if paused() then return end
    local avail, active = lists()
    local q = QA.Choose(avail, active)
    if q and mayPick() then q.pick() end
end

----------------------------------------------------------------------
-- The quest window
----------------------------------------------------------------------
local function onDetail()
    if paused() or not QA.On("autoAccept") or fromPlayer() then return end
    local id = GetQuestID and GetQuestID()
    if QA.Trivial(id) then return end
    if QuestGetAutoAccept and QuestGetAutoAccept() then return end    -- the game takes it itself
    AcceptQuest()
end
local function onProgress()
    if paused() or not QA.On("autoTurnIn") then return end
    if IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
end

-- the best reward: { index, gain } by score, else by vendor price
local hint
function QA.BestReward(n, getLink)
    getLink = getLink or function(i) return GetQuestItemLink and GetQuestItemLink("choice", i) end
    local LP = OMQ.LootPreview
    local bestI, bestG, bestP, bestPI
    for i = 1, n do
        local link = getLink(i)
        if link and not isSecret(link) then
            local equipLoc
            if C_Item and C_Item.GetItemInfoInstant then equipLoc = select(4, C_Item.GetItemInfoInstant(link)) end
            local g
            if LP and LP.Gain and equipLoc and equipLoc ~= "" then
                local ok, v = pcall(LP.Gain, link, equipLoc)
                g = ok and v or nil
            end
            if g and g > 0 and (not bestG or g > bestG) then bestI, bestG = i, g end
            local price = 0
            if C_Item and C_Item.GetItemInfo then price = select(11, C_Item.GetItemInfo(link)) or 0 end
            local qty
            if GetQuestItemInfo then qty = select(3, GetQuestItemInfo("choice", i)) end
            price = price * (tonumber(qty) or 1)
            if not bestP or price > bestP then bestP, bestPI = price, i end
        end
    end
    if bestI then return bestI, "upgrade", bestG end
    if bestPI then return bestPI, "gold", bestP end
end

local function rewardButton(i)
    local f = _G.QuestInfoRewardsFrame
    if f and f.RewardButtons and f.RewardButtons[i] then return f.RewardButtons[i] end
    return _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
end
local function showHint(i, kind, value)
    local b = rewardButton(i)
    if not b then return end
    if not hint then
        hint = CreateFrame("Frame", nil, UIParent)
        hint.edge = {}
        for k = 1, 4 do
            local t = hint:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(0.95, 0.78, 0.25, 1)
            hint.edge[k] = t
        end
        hint.edge[1]:SetPoint("TOPLEFT"); hint.edge[1]:SetPoint("TOPRIGHT"); hint.edge[1]:SetHeight(2)
        hint.edge[2]:SetPoint("BOTTOMLEFT"); hint.edge[2]:SetPoint("BOTTOMRIGHT"); hint.edge[2]:SetHeight(2)
        hint.edge[3]:SetPoint("TOPLEFT"); hint.edge[3]:SetPoint("BOTTOMLEFT"); hint.edge[3]:SetWidth(2)
        hint.edge[4]:SetPoint("TOPRIGHT"); hint.edge[4]:SetPoint("BOTTOMRIGHT"); hint.edge[4]:SetWidth(2)
    end
    hint:SetParent(b)
    hint:SetFrameLevel((b.GetFrameLevel and b:GetFrameLevel() or 1) + 5)
    hint:ClearAllPoints(); hint:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2); hint:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    hint:Show()
    -- the words go into the item's tooltip, not onto the quest window (decision 307)
    local money = OMQ.AuctionHelper and OMQ.AuctionHelper.Money
    local line = kind == "upgrade" and ("|cff40e060One More Quest: best for you (+" .. value .. ")|r")
        or ("|cfff2d27aOne More Quest: sells for most" .. (money and value > 0 and (" (" .. money(value) .. ")") or "") .. "|r")
    QA._hint = { index = i, kind = kind, value = value, line = line }
end

-- the line goes in every time the game builds the item tooltip of the marked reward (decision 309): the
-- quest window rebuilds that tooltip right after it is shown, a line added once on hover was gone at once
function QA.AddHintLine(tt)
    local h = QA._hint
    if not (h and tt and tt.GetOwner and tt.AddLine) then return false end
    local owner = tt:GetOwner()
    if not owner or owner ~= rewardButton(h.index) then return false end
    tt:AddLine(h.line)
    return true
end
local function hookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
            if tt == GameTooltip then pcall(QA.AddHintLine, tt) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt) pcall(QA.AddHintLine, tt) end)
    end
end
OMQ:On("READY", hookTooltips)
function QA.HintLine() return QA._hint and QA._hint.line end

-- the marked reward is chosen in the quest window (decision 308): "Complete Quest" takes it, another click
-- on a different reward still changes it
function QA.Preselect(i)
    local b = rewardButton(i)
    if not b then return false end
    local ok = false
    if QuestInfoItem_OnClick then ok = pcall(QuestInfoItem_OnClick, b) end
    if not ok and b.Click then ok = pcall(b.Click, b) end
    QA._preselected = ok and i or nil
    return ok
end
local function hideHint() if hint then hint:Hide() end; QA._hint = nil end

local function onComplete()
    hideHint()
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n > 1 then
        if QA.On("rewardHint") then
            local i, kind, value = QA.BestReward(n)
            if i then showHint(i, kind, value); QA.Preselect(i) end
        end
        return
    end
    if paused() or not QA.On("autoTurnIn") then return end
    GetQuestReward(n == 1 and 1 or nil)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
        if event == "GOSSIP_SHOW" then onList(gossipLists)
        elseif event == "QUEST_GREETING" then onList(greetingLists)
        elseif event == "QUEST_DETAIL" then onDetail()
        elseif event == "QUEST_PROGRESS" then onProgress()
        elseif event == "QUEST_COMPLETE" then onComplete()
        elseif event == "QUEST_FINISHED" then hideHint() end
    end)
    if not ok then OMQ:Error("quest automation", err) end
end)
