-- One More Quest: the window of the Chain Run (decision 595). A list of the chains (tab "For me": my faction, my
-- level, not done; tab "All": every chain, too low ones grey, done ones gold with a tick), a click shows the steps,
-- the way and the rewards, Start begins at the first open step. Chains of other classes are never listed (698). Asks before it ends another run (K5) and shows the
-- offer of a dad who starts a chain in the group (K6). The bar, the small arrow and the done card are the Quest Run's
-- in purple (UI/QuestRun.lua).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local UI = {}
OMQ.ChainRunUI = UI

UI.PURPLE = { 0.66, 0.33, 0.94 }       -- frame and arrow (K9)
UI.TEXT = { 0.77, 0.57, 1.00 }         -- writing on the dark ground
local PURPLE, TEXT = UI.PURPLE, UI.TEXT
local GREY = { 0.6, 0.63, 0.68 }
local GOLD = { 0.89, 0.71, 0.29 }
local GREEN = { 0.49, 0.78, 0.44 }
local W, ROWS, ROW_H = 380, 12, 30

local win, title, sub, rows, tabs, startBtn, backBtn, note, rewardLabel
local rewardBtns = {}
local REWARD_H = 24
local mode, tab, chosen = "list", "me", nil
UI._view = {}

local function C() return OMQ.ChainRun end
local function button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 90, h or 22)
    b:SetText(text)
    return b
end
local function confirm(key, text, go)
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs[key] = { text = text, button1 = YES or "Yes", button2 = NO or "No", OnAccept = go,
                                    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
        StaticPopup_Show(key)
        return
    end
    go()
end
UI._confirm = confirm

-- the reward names (the game knows them once the item was asked for)
function UI.ItemName(id)
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, id)
        if ok and type(n) == "string" and n ~= "" then return n end
        if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    if GetItemInfo then
        local ok, n = pcall(GetItemInfo, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return "item " .. tostring(id)
end
-- the spell a class chain teaches (698), in the language of the client
function UI.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return "spell " .. tostring(id)
end
-- the rewards as entries for the icon rows (fix 704): { kind = "spell"/"item", id, name, icon, color }
function UI.ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then
        local ok, t = pcall(C_Item.GetItemIconByID, id)
        if ok and t then return t end
    end
    if GetItemIcon then
        local ok, t = pcall(GetItemIcon, id)
        if ok and t then return t end
    end
    return 134400                                   -- the question mark
end
function UI.SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, id)
        if ok and t then return t end
    end
    return 134400
end
function UI.ItemColor(id)
    local q
    if C_Item and C_Item.GetItemQualityByID then
        local ok, r = pcall(C_Item.GetItemQualityByID, id)
        if ok and type(r) == "number" then q = r end
    end
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.r then return { c.r, c.g, c.b } end
    return { 1, 1, 1 }
end
function UI.RewardList(chain)
    local out = {}
    if chain.spell then
        out[#out + 1] = { kind = "spell", id = chain.spell, name = UI.SpellName(chain.spell), icon = UI.SpellIcon(chain.spell), color = TEXT }
    end
    for _, id in ipairs(chain.rewards or {}) do
        out[#out + 1] = { kind = "item", id = id, name = UI.ItemName(id), icon = UI.ItemIcon(id), color = UI.ItemColor(id) }
    end
    return out
end
-- the game's own tooltip of a reward
function UI.RewardTip(owner, r)
    local t = GameTooltip
    if not (t and r) then return false end
    t:SetOwner(owner, "ANCHOR_RIGHT")
    if r.kind == "spell" and t.SetSpellByID then t:SetSpellByID(r.id)
    elseif r.kind == "item" and t.SetItemByID then t:SetItemByID(r.id)
    else t:SetText(r.name) end
    t:Show()
    return true
end
function UI.Rewards(chain)
    local o = {}
    if chain.spell then o[1] = UI.SpellName(chain.spell) end
    for _, id in ipairs(chain.rewards or {}) do o[#o + 1] = UI.ItemName(id) end
    return table.concat(o, ", ")
end

-- the zone name of a place for the preview
function UI.ZoneName(map)
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, map)
        if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
    end
    return "map " .. tostring(map)
end
local function where(spot)
    if not spot then return "" end
    if type(spot[1]) == "table" then spot = spot[1] end
    return string.format("%s %.1f, %.1f", UI.ZoneName(spot[1]), spot[2], spot[3])
end

-- the chains a tab shows
function UI.ChainsFor(t)
    local out = {}
    for _, c in ipairs(C().Chains()) do
        local st = C().Status(c)
        if st ~= "class" and (t == "all" or st == "ready" or st == "running") then out[#out + 1] = c end
    end
    return out
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local function build()
    win = CreateFrame("Frame", "OneMoreQuestChainWindow", UIParent)
    win:SetSize(W, 160)
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
    border:SetColorTexture(PURPLE[1], PURPLE[2], PURPLE[3], 1)
    local bg = win:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.086, 0.114, 0.97)
    title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", 14, -36)
    sub:SetWidth(W - 28)
    sub:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() UI:Close() end)
    tabs = {}
    for i, t in ipairs({ { "me", "For me" }, { "all", "All" } }) do
        local b = button(win, t[2], 80, 20)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * 86, -58)
        b.tab = t[1]
        b:SetScript("OnClick", function(self) tab = self.tab; UI:Render() end)
        tabs[i] = b
    end
    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(W - 28, ROW_H)
        r:RegisterForClicks("LeftButtonUp")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(PURPLE[1], PURPLE[2], PURPLE[3], 0.14)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("TOPLEFT", 4, -2)
        r.name:SetWidth(W - 130)
        r.name:SetJustifyH("LEFT")
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.what = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.what:SetPoint("TOPLEFT", 18, -16)
        r.what:SetWidth(W - 60)
        r.what:SetJustifyH("LEFT")
        if r.what.SetWordWrap then r.what:SetWordWrap(false) end
        r.state = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.state:SetPoint("TOPRIGHT", -4, -4)
        r:SetScript("OnClick", function(self) if self.key then UI:Pick(self.key) end end)
        r:Hide()
        rows[i] = r
    end
    rewardLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rewardLabel:SetText("Rewards:")
    rewardLabel:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    rewardLabel:Hide()
    note = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetJustifyH("LEFT")
    note:SetWidth(W - 28)
    startBtn = button(win, "Start", 96, 24)
    startBtn:SetScript("OnClick", function() UI:StartChosen() end)
    backBtn = button(win, "Back", 96, 24)
    backBtn:SetScript("OnClick", function() mode = "list"; UI:Render() end)
    win:Hide()
end

function UI:Render()
    if not win then return end
    local view = { mode = mode, rows = {} }
    UI._view = view
    for _, r in ipairs(rows) do r:Hide() end
    startBtn:Hide(); backBtn:Hide(); note:Hide(); rewardLabel:Hide()
    for _, b in ipairs(rewardBtns) do b:Hide() end
    for _, b in ipairs(tabs) do b:Hide() end
    local y
    if mode == "list" then
        title:SetText("Chain Run")
        sub:SetText("Quest chains every dad should do. Click one to see its steps.")
        for _, b in ipairs(tabs) do
            b:Show()
            if b.SetAlpha then b:SetAlpha(b.tab == tab and 1 or 0.6) end
        end
        local list = UI.ChainsFor(tab)
        view.tab = tab
        for i, c in ipairs(list) do
            local r = rows[i]
            if not r then break end
            local st = C().Status(c)
            local done, n = C().Progress(c)
            r.key = c.key
            r.name:SetText(c.name)
            local col = (st == "low") and GREY or (st == "done") and GOLD or TEXT
            r.name:SetTextColor(col[1], col[2], col[3])
            r.what:SetText("Level " .. (c.minLevel or 1) .. "+ - " .. UI.Rewards(c))
            local text = st == "done" and "done" or st == "low" and ("needs level " .. c.minLevel) or st == "running" and "running"
                or (done > 0 and string.format("%d/%d steps", done, n) or (n == 1 and "1 step" or (n .. " steps")))
            r.state:SetText(text)
            local sc = st == "ready" and GREEN or st == "running" and TEXT or st == "done" and GOLD or GREY
            r.state:SetTextColor(sc[1], sc[2], sc[3])
            r:SetPoint("TOPLEFT", 14, -84 - (i - 1) * ROW_H)
            r:Show()
            view.rows[i] = { key = c.key, state = st, text = text }
        end
        if #list == 0 then
            sub:SetText("No chain left for you right now. The tab All shows every chain.")
        end
        y = 84 + math.max(1, #list) * ROW_H + 12
        C().MarkSeen()
    else
        local c = chosen and C().Get(chosen)
        if not c then mode = "list"; return self:Render() end
        title:SetText("Chain Run: " .. c.name)
        local _, n, first = C().Progress(c)
        sub:SetText(n == 1 and "One step:" or (n .. " steps, in this order:"))
        local faction = C().Faction()
        local states = C().States(c)
        for i, st in ipairs(c.steps) do
            local r = rows[i]
            if not r then break end
            local state = states[i]
            r.key = nil
            r.name:SetText(i .. ". " .. C().Title(st))
            local col = state == "done" and GREEN or TEXT
            r.name:SetTextColor(col[1], col[2], col[3])
            local spot = st.search and st.search[1] or C().Pick(st.from, faction)
            local what = st.search and (UI.ZoneName(spot[1]) .. " - " .. #st.search .. " places") or where(spot)
            r.what:SetText(what .. " - " .. (st.fromText or ""))
            r.state:SetText(state == "done" and "done" or state == "log" and "in your log" or "")
            r.state:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
            r:SetPoint("TOPLEFT", 14, -60 - (i - 1) * ROW_H)
            r:Show()
            view.rows[i] = { title = C().Title(st), state = state }
        end
        local lines = {}
        for i, st in ipairs(c.steps) do
            if st.enemyZone and C().Pick(st.enemyZone) then
                local spot = C().Pick(st.to)
                lines[#lines + 1] = "|cffff8a6a" .. (faction == "Horde" and "Alliance" or "Horde") .. " zone: " .. UI.ZoneName(spot[1]) .. " (step " .. i .. ")|r"
                break
            end
        end
        if c.steps[1] and c.steps[1].search then
            lines[#lines + 1] = "The body moves between these places: the arrow takes you to the nearest one you have not looked at yet."
        end
        local status = C().Status(c)
        if status == "low" then lines[#lines + 1] = "|cffff8a6aNeeds level " .. c.minLevel .. "|r" end
        y = 60 + #c.steps * ROW_H + 6
        local rewards = UI.RewardList(c)                -- one row per reward: icon, name, the game's tooltip (704)
        view.rewards = {}
        if #rewards > 0 then
            rewardLabel:ClearAllPoints(); rewardLabel:SetPoint("TOPLEFT", 14, -y); rewardLabel:Show()
            y = y + 18
            for i, r in ipairs(rewards) do
                local b = UI.RewardButton(i)
                b.reward = r
                b.icon:SetTexture(r.icon)
                b.name:SetText(r.name)
                b.name:SetTextColor(r.color[1], r.color[2], r.color[3])
                b:ClearAllPoints(); b:SetPoint("TOPLEFT", 14, -y); b:Show()
                y = y + REWARD_H
                view.rewards[i] = { kind = r.kind, id = r.id, name = r.name, icon = r.icon }
            end
            y = y + 4
        end
        note:SetText(table.concat(lines, "\n"))
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", 14, -y)
        if #lines > 0 then note:Show() end
        y = y + 16 * #lines + 10
        backBtn:ClearAllPoints(); backBtn:SetPoint("BOTTOMLEFT", 14, 12); backBtn:Show()
        startBtn:ClearAllPoints(); startBtn:SetPoint("BOTTOMRIGHT", -14, 12); startBtn:Show()
        local can = status == "ready"
        if startBtn.SetEnabled then startBtn:SetEnabled(can) end
        if startBtn.SetAlpha then startBtn:SetAlpha(can and 1 or 0.4) end
        startBtn.omqEnabled = can
        view.start, view.status, view.note, view.first = can, status, lines, first
        y = y + 40
    end
    win:SetHeight(y)
end

-- a reward row: icon + name, hover = the game's tooltip (704)
function UI.RewardButton(i)
    local b = rewardBtns[i]
    if b then return b end
    b = CreateFrame("Button", nil, win)
    b:SetSize(W - 28, REWARD_H - 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(PURPLE[1], PURPLE[2], PURPLE[3], 0.14)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(REWARD_H - 4, REWARD_H - 4)
    b.icon:SetPoint("LEFT", 2, 0)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.name:SetPoint("LEFT", REWARD_H + 2, 0)
    b.name:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self) UI.RewardTip(self, self.reward) end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    rewardBtns[i] = b
    return b
end

function UI:Pick(key) chosen = key; mode = "preview"; self:Render() end
function UI:Mode() return mode end
function UI:IsOpen() return win ~= nil and win:IsShown() end
function UI:Open()
    if not win then build() end
    mode = "list"
    win:Show()
    self:Render()
end
function UI:Close() if win then win:Hide() end end
function UI:Toggle() if self:IsOpen() then self:Close() else self:Open() end end

-- start a chain; another run is ended only after a yes (K5)
function UI:AskStart(key)
    local other = C().OtherRun()
    local go = function() if C():Start(key) then UI:Close() end end
    if other then
        confirm("OMQ_CHAIN_RUN_START", "End the " .. other .. " and start the Chain Run?", go)
    else go() end
end
function UI:StartChosen()
    if not (startBtn and startBtn.omqEnabled) or not chosen then return end
    self:AskStart(chosen)
end

-- the bar's right click and the small arrow's right click
function UI:AskEnd()
    confirm("OMQ_CHAIN_RUN_END", "End the Chain Run?", function() C():End() end)
end

-- a dad of the group starts a chain I can do too (K6)
OMQ:On("CHAIN_RUN_OFFER", function(who, chain)
    UI._offer = { who = who, key = chain.key }
    if C():Active() then return end
    confirm("OMQ_CHAIN_RUN_OFFER", who .. " starts the Chain Run: " .. chain.name .. ". Join?", function()
        if C().OtherRun() then C()._endOthers() end
        C():Start(chain.key, { quiet = true })
    end)
end)

-- item names and qualities arrive later than the first look: draw the open window again (704)
local itemWatch = CreateFrame("Frame")
if itemWatch.RegisterEvent then pcall(itemWatch.RegisterEvent, itemWatch, "GET_ITEM_INFO_RECEIVED") end
itemWatch:SetScript("OnEvent", function() if UI:IsOpen() then UI:Render() end end)
UI._itemWatch = itemWatch

OMQ:On("CHAIN_RUN_CHANGED", function()
    if UI:IsOpen() then UI:Render() end
    if OMQ.RunBar and OMQ.RunBar.Refresh then OMQ.RunBar:Refresh() end
end)

OMQ:On("CHAIN_RUN_DONE", function(chain, n, secs)
    if OMQ.QuestRunUI and OMQ.QuestRunUI.ShowCard then
        OMQ.QuestRunUI:ShowCard(n, secs, { kind = "chain", name = chain and chain.name, rewards = chain and UI.Rewards(chain) })
    end
end)
