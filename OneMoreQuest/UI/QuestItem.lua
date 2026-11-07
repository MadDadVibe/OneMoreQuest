-- One More Quest: quest items next to the group quest tracker (decisions 354, 355, 452)
-- The objective tracker is hidden, so its click buttons for quest items are gone. The usable quest items of
-- the quests whose card the tracker holds get secure buttons in a column right of the card, only while the
-- card is on screen. The tracker holds the cards of nearby quests and of fresh progress (decision 453), so
-- only the item a quest close by needs is there. No row under the player frame any more (decision 453).
-- Left click uses the item. Right click hides that item until I use it myself the next time (from the
-- bags or a bar); hidden items are kept in OMQDB.questItemHidden.
-- Which items: for every quest of my log the game's quest item (GetQuestLogSpecialItemInfo) and the items
-- of Data/QuestItems.lua (source item, required source items and item objectives of class Quest, from
-- QuestieDB). An item counts when it is in the bags and has an on-use spell (the game's own quest item needs
-- no spell). The items of a finished quest (all objectives done, not yet turned in) are left out.
-- Combat: secure buttons cannot be shown, hidden, moved or given another item in combat. At the start of a
-- fight (PLAYER_REGEN_DISABLED, before the lockdown) every item of the quests around me (held by the tracker
-- or within its PREP_YD) gets a shown button, invisible (alpha 0) unless its quest has a card on screen. In
-- combat only the alpha changes, which the game allows. An invisible button ignores the right click and
-- shows no tooltip. A quest I reach only in the fight shows its item after the fight.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local Q = {}
OMQ.QuestItem = Q

local SIZE, GAP, MAX = 30, 4, 10
local DIM = 0.4
-- the card is at least 380 wide and grows by 60 per dad over four (UI/QuestTracker.lua)
local CARD_MIN, CARD_BASE, CARD_COL = 380, 144, 60

local buttons = {}           -- the secure buttons, reused
local list = {}              -- { { item, qid } } the buttons hold, in order
local vis = {}               -- [button index] = true: seen now (shown and alpha above 0)
local pending = false        -- the column has to change once the combat ends
local layout = nil           -- "tracker" while the card is on screen, else nil
local armed = false          -- the buttons of the quests around me are shown for the fight
local moveMode = false

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function num(v) return type(v) == "number" and not isSecret(v) and v or nil end

local function hiddenSet()
    if not OMQ.db then return {} end
    OMQ.db.questItemHidden = OMQ.db.questItemHidden or {}
    return OMQ.db.questItemHidden
end
function Q.IsHidden(id) return hiddenSet()[id] == true end

----------------------------------------------------------------------
-- Items (C_ versions with the old globals as fallback)
----------------------------------------------------------------------
local function itemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, id)
    return ok and num(n) or 0
end

-- the on-use spell: name and spell id, or nil
local function itemSpell(id)
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not f then return nil end
    local ok, name, spellID = pcall(f, id)
    if not ok or isSecret(name) or isSecret(spellID) then return nil end
    if not (name or spellID) and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)        -- not cached yet: the next look finds it
    end
    if not (name or spellID) then return nil end
    return name or spellID, num(spellID)
end
Q._itemSpell = itemSpell

local function itemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if f then
        local ok, t = pcall(f, id)
        if ok and t and not isSecret(t) then return t end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function logIndex(qid)
    local CQ = C_QuestLog
    local f = (CQ and CQ.GetLogIndexForQuestID) or GetQuestLogIndexByID
    if not f then return nil end
    local ok, i = pcall(f, qid)
    i = ok and num(i)
    return i and i > 0 and i or nil
end

-- the game's own quest item of a quest: item id or nil
function Q.SpecialItem(qid)
    if not GetQuestLogSpecialItemInfo then return nil end
    local i = logIndex(qid)
    if not i then return nil end
    local ok, link = pcall(GetQuestLogSpecialItemInfo, i)
    if not ok or type(link) ~= "string" or isSecret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function questOrder()
    local mine = OMQ.QTrack and OMQ.QTrack:Mine() or {}
    local ids = {}
    for qid in pairs(mine) do ids[#ids + 1] = qid end
    table.sort(ids, function(a, b) return (logIndex(a) or a) < (logIndex(b) or b) end)
    return ids, mine
end

-- every usable quest item in the bags, hidden ones too: { { item, qid } } in quest log order, then the rest
-- a quest of my log that is finished (all objectives done, not yet turned in)
function Q.QuestDone(qid)
    local CQ = C_QuestLog
    if CQ and CQ.IsComplete then
        local ok, v = pcall(CQ.IsComplete, qid)
        if ok and v == true and not isSecret(v) then return true end
    end
    local m = OMQ.QTrack and OMQ.QTrack:Mine()[qid]
    return m and OMQ.QTrack.Complete(m.counts) and true or false
end

-- every usable quest item in the bags, hidden ones too: { { item, qid } } in quest log order.
-- The items of a finished quest go (decision 355), unless an open quest needs the same item.
function Q.All()
    local out, seen = {}, {}
    local function add(id, qid, special)
        if id and not seen[id] and itemCount(id) > 0 and (special or itemSpell(id)) then
            seen[id] = true
            out[#out + 1] = { item = id, qid = qid }
        end
    end
    local ids = questOrder()
    for _, qid in ipairs(ids) do
        if not Q.QuestDone(qid) then
            add(Q.SpecialItem(qid), qid, true)
            for _, id in ipairs((OMQ.QuestItems or {})[qid] or {}) do add(id, qid) end
        end
    end
    return out
end

-- the quests whose card the tracker shows now
function Q.Active()
    local T, out = OMQ.QTrack, {}
    if not (T and T:Shown()) then return out end
    for _, qid in ipairs(T:Cards()) do out[qid] = true end
    return out
end

-- what the column should hold: the items of the given quests (default: the cards on screen)
function Q.Wanted(quests)
    if moveMode or not OMQ:Master("group") then return {} end
    quests = quests or Q.Active()
    local out = {}
    for _, e in ipairs(Q.All()) do
        if quests[e.qid] and not Q.IsHidden(e.item) and #out < MAX then out[#out + 1] = e end
    end
    return out
end

----------------------------------------------------------------------
-- The buttons
----------------------------------------------------------------------
local attrs = {}             -- [button index] = { type1, item1 }, for /omq questitem and the tests

local function setAttr(i, k, v)
    attrs[i] = attrs[i] or {}
    attrs[i][k] = v
    buttons[i]:SetAttribute(k, v)
end

local function questTitle(qid)
    local m = qid and OMQ.QTrack and OMQ.QTrack:Mine()[qid]
    return m and m.title
end

local function makeButton(i)
    local name = "OneMoreQuestQuestItemTracker" .. i
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:SetSize(SIZE, SIZE)
    b:SetFrameStrata("MEDIUM")
    if b.SetFrameLevel then b:SetFrameLevel(20) end
    -- the secure template fires on mouse down or up depending on ActionButtonUseKeyDown
    b:RegisterForClicks("AnyUp", "AnyDown")
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.89, 0.71, 0.29, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    pcall(function()
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints()
    end)
    b.index = i
    -- only the left button uses the item (type1); the right button hides it
    b:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down and vis[self.index] then Q:Dismiss(self.index) end
    end)
    b:SetScript("OnEnter", function(self)
        local e = list[self.index]
        if not (GameTooltip and e) or not vis[self.index] then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.item)
        else GameTooltip:SetHyperlink("item:" .. e.item) end
        local t = questTitle(e.qid)
        if t then GameTooltip:AddLine("Quest item for: " .. t, 0.72, 0.63, 0.42) end
        GameTooltip:AddLine("Left click: use - right click: hide until you use it again", 0.66, 0.69, 0.73)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:Hide()
    buttons[i] = b
    return b
end

-- the top right corner of the column: right of the widest card the group can have, at the card's top
local function origin()
    local card = OMQ.QTrackFrame and OMQ.QTrackFrame:Frame()
    local left, top = card and num(card:GetLeft()), card and num(card:GetTop())
    local n = OMQ.QTrack and #OMQ.QTrack:Columns() or 1
    if n > 5 then n = 5 end
    local width = math.max(CARD_MIN, CARD_BASE + n * CARD_COL)
    if left and top then return left + width + GAP, top end
    return nil
end

-- the column is there while the card is on screen
function Q.Layout()
    local card = OMQ.QTrackFrame and OMQ.QTrackFrame:Frame()
    if card and card:IsShown() then return "tracker" end
    return nil
end

local function place(b, i)
    b:ClearAllPoints()
    local x, top = origin()
    if x then b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top - (i - 1) * (SIZE + GAP))
    else b:SetPoint("TOPLEFT", UIParent, "LEFT", CARD_MIN + GAP, 165 - (i - 1) * (SIZE + GAP)) end
end

-- count, cooldown, dimming and whether a button is seen (alpha); allowed in combat
local alphas = {}            -- [button] = alpha set last, for the tests
local function refreshLooks()
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    local active = layout and Q.Active() or {}
    for i, e in ipairs(list) do
        local n = itemCount(e.item)
        local off = n == 0 or Q.IsHidden(e.item)
        local start, dur, enabled
        if f then
            local ok
            ok, start, dur, enabled = pcall(f, e.item)
            start, dur = ok and num(start), ok and num(dur)
        end
        local b = buttons[i]
        if b then
            b.count:SetText(n > 1 and tostring(n) or "")
            if b.icon.SetDesaturated then b.icon:SetDesaturated(off) end
            local seen = active[e.qid] == true
            local a = seen and (off and DIM or 1) or 0
            b:SetAlpha(a)
            alphas[b], vis[i] = a, seen or nil
            if b.cd and f then
                if start and dur and dur > 0 and enabled ~= 0 and enabled ~= false then b.cd:SetCooldown(start, dur)
                elseif b.cd.Clear then b.cd:Clear() end
            end
        end
    end
    for i = #list + 1, #buttons do vis[i] = nil end
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i].item ~= b[i].item then return false end end
    return true
end

-- the buttons hold exactly these items, in this order, at the column's places, shown
local function build(want)
    for i, e in ipairs(want) do
        if not buttons[i] then makeButton(i) end
        if not (list[i] and list[i].item == e.item) or not (attrs[i] and attrs[i].item1) then
            setAttr(i, "type1", "item")
            setAttr(i, "item1", "item:" .. e.item)
            buttons[i].icon:SetTexture(itemIcon(e.item))
        end
        place(buttons[i], i)
        buttons[i]:Show()
    end
    for i = #want + 1, #buttons do
        if attrs[i] and attrs[i].item1 then setAttr(i, "type1", nil); setAttr(i, "item1", nil) end
        buttons[i]:Hide()
    end
    list = want
end

-- every item of a list is in the other list
local function covers(have, want)
    local set = {}
    for _, e in ipairs(have) do set[e.item] = true end
    for _, e in ipairs(want) do if not set[e.item] then return false end end
    return true
end

function Q:Update()
    if inCombat() then
        -- nothing secure may change now: a button is seen or not by the alpha alone (the buttons of the
        -- quests around me are shown since the start of the fight), the list catches up after the combat
        layout = Q.Layout()
        local want = layout and Q.Wanted() or {}
        pending = not (armed and covers(list, want)) and not same(want, list)
        refreshLooks()
        return
    end
    pending, armed = false, false
    layout = Q.Layout()
    build(layout and Q.Wanted() or {})
    refreshLooks()
end

-- the fight starts (PLAYER_REGEN_DISABLED comes before the lockdown): every item of the quests around me
-- gets a shown button, seen only while its quest has a card on screen
function Q:Arm()
    if inCombat() then return end
    layout = Q.Layout()
    local quests = OMQ.QTrack and OMQ.QTrack.Around and OMQ.QTrack:Around() or {}
    for qid in pairs(Q.Active()) do quests[qid] = true end
    build(Q.Wanted(quests))
    armed = true
    refreshLooks()
end

-- the card opened or went: the place follows at once (only the alpha changes, also in combat)
function Q:Follow()
    self:Update()
end

-- right click: the item is hidden until it is used by hand the next time
function Q:Dismiss(i)
    local e = list[i]
    if not e then return end
    hiddenSet()[e.item] = true
    self:Update()
end

-- a cast of mine: a hidden item whose spell this is comes back
function Q:OnCast(spellID)
    spellID = num(spellID)
    if not spellID then return end
    local h = hiddenSet()
    for id in pairs(h) do
        local _, sid = itemSpell(id)
        if sid == spellID then h[id] = nil end
    end
end

function Q:IsMouseOver()
    for i, b in ipairs(buttons) do
        if vis[i] and b:IsShown() and b.IsMouseOver then
            local ok, v = pcall(b.IsMouseOver, b)
            if ok and v then return true end
        end
    end
    return false
end
function Q:List() return list end
function Q:Pending() return pending end
function Q:CurrentLayout() return layout end
-- buttons the player sees: shown and not invisible
function Q:Shown()
    local n = 0
    for i, b in ipairs(buttons) do if vis[i] and b:IsShown() then n = n + 1 end end
    return n
end
function Q:Armed() return armed end
function Q:Alpha(i) local b = buttons[i]; return b and alphas[b] end
function Q:Seen(i) return vis[i] == true end
function Q:Attr(i, k) return attrs[i] and attrs[i][k] end
function Q:Button(i) return buttons[i] end

local function update()
    local ok, err = pcall(Q.Update, Q)
    if not ok then OMQ:Error("questitem", err) end
end

----------------------------------------------------------------------
-- /omq questitem: what the game reports for the quest items; "/omq questitem reset" shows hidden ones again
----------------------------------------------------------------------
function Q.Report()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add("quest items: GetQuestLogSpecialItemInfo " .. tostring(GetQuestLogSpecialItemInfo ~= nil)
        .. ", C_Item.GetItemSpell " .. tostring(C_Item and C_Item.GetItemSpell ~= nil)
        .. ", C_Item.GetItemInfoInstant " .. tostring(C_Item and C_Item.GetItemInfoInstant ~= nil)
        .. ", combat " .. tostring(inCombat()))
    local ids, mine = questOrder()
    for _, qid in ipairs(ids) do
        local special = Q.SpecialItem(qid)
        local parts = {}
        for _, id in ipairs((OMQ.QuestItems or {})[qid] or {}) do
            parts[#parts + 1] = id .. " x" .. itemCount(id) .. (itemSpell(id) and " use" or "")
        end
        if special or #parts > 0 then
            add(string.format("%d %s: game item %s, data %s", qid, tostring(mine[qid].title or "?"),
                tostring(special or "none"), #parts > 0 and table.concat(parts, ", ") or "none"))
        end
    end
    local all, active = Q.All(), Q.Active()
    local names = {}
    for _, e in ipairs(all) do
        names[#names + 1] = e.item .. " (quest " .. e.qid .. (active[e.qid] and ", card" or "") .. ")" .. (Q.IsHidden(e.item) and " hidden" or "")
    end
    add("usable quest items: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    add("buttons seen " .. Q:Shown() .. " of " .. #list .. ", card on screen " .. tostring(layout ~= nil)
        .. ", ready for the fight " .. tostring(armed) .. ", waits for the end of combat " .. tostring(pending))
    for _, s in ipairs(lines) do OMQ:Print(s) end
    return lines
end
OMQ:RegisterCommand("questitem", function(arg)
    if arg == "reset" then
        if OMQ.db then OMQ.db.questItemHidden = {} end
        OMQ:Print("quest items: every hidden item is shown again")
        update()
        return
    end
    Q.Report()
end, "quest item bar: what the game reports; 'reset' shows hidden items again")

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        Q:OnCast(spellID)
    end
    update()
    if event == "PLAYER_REGEN_DISABLED" then
        local ok, err = pcall(Q.Arm, Q)
        if not ok then OMQ:Error("questitem", err) end
    end
end)

OMQ:On("READY", function()
    update()
    -- the card's own show and hide move the icons at once (the ticker below is the safety net)
    local card = OMQ.QTrackFrame and OMQ.QTrackFrame:Frame()
    if card and card.HookScript then
        local function follow()
            local ok, err = pcall(Q.Follow, Q)
            if not ok then OMQ:Error("questitem", err) end
        end
        pcall(card.HookScript, card, "OnShow", follow)
        pcall(card.HookScript, card, "OnHide", follow)
    end
    -- the card's place and the group size can change: follow them every second
    C_Timer.NewTicker(1, update)
end)
OMQ:On("QTRACK_CHANGED", update)
OMQ:On("SETTINGS_CHANGED", update)
OMQ:On("ROSTER_CHANGED", update)
OMQ:On("MOVE_MODE", function(on) moveMode = on and true or false; update() end)
