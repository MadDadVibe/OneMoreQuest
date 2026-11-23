-- One More Quest: Spell Preview next to the spellbook (decision 655)
-- A tab on the right edge of the spellbook (P) folds out a panel: for every coming level the spells and ranks the class
-- trainer teaches there and what each costs, from the class trainer data (Data/TrainerSpells.lua, the same list the
-- level-up card uses: own race and faction, talent ranks only with the talent). On top what the trainer has for you
-- right now. Hovering a spell shows its game tooltip. Closed by default: only a click on the tab opens it, and it
-- closes again with the spellbook. Names and ranks come from the game in the client's language.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local SP = {}
OMQ.SpellPreview = SP

SP.W = 300                       -- panel width
SP.TAB = 36                      -- tab button size
SP.TAB_Y = -60                   -- tab below the title bar
SP.LEVEL_UP = 6000               -- frame levels above the spellbook (its own parts go up to 5510)
SP.ROW_H, SP.HEAD_H = 18, 22
SP.MAX_LEVEL = 60
SP.ICON = "Interface\\Icons\\INV_Misc_Book_09"

local GOLD = { 0.95, 0.82, 0.48 }
local GREY = { 0.6, 0.6, 0.62 }
local WHITE = { 0.92, 0.9, 0.85 }
local GREEN = { 0.49, 0.78, 0.44 }
local RED = { 1, 0.35, 0.3 }

function SP.On() return not (OMQ.db and OMQ.db.options and OMQ.db.options.spellPreview == false) end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellInfo then return select(3, GetSpellInfo(id)) end
end
local function spellRank(id)
    local r = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    if type(r) == "string" and r ~= "" then return r end
end
function SP.Money(c)
    c = math.floor(c or 0)
    if GetCoinTextureString then
        local ok, s = pcall(GetCoinTextureString, c)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return OMQ.Alerts and OMQ.Alerts.Money and OMQ.Alerts.Money(c) or tostring(c)
end

----------------------------------------------------------------------
-- The list
----------------------------------------------------------------------
-- sections { label, level, now, cost, spells = { {id, cost, level} } }, the total of the coming levels, and the cost of now;
-- nil when the class has no trainer data
function SP.Plan(level)
    level = level or UnitLevel("player") or 1
    local A = OMQ.Alerts
    local list = A and A.NewAtTrainer and A.NewAtTrainer(SP.MAX_LEVEL)
    if not list then return nil end
    -- a higher rank of a talent spell (the data has no requirement for some, e.g. Mortal Strike 2): it shows only
    -- when the spell is in the book or the trainer teaches a lower rank of the same name
    local names, bookNames = {}, A.TrainerBook and A.TrainerBook() or {}
    local _, class = UnitClass("player")
    for lvl, entries in pairs(OMQ.TrainerSpells and OMQ.TrainerSpells[class] or {}) do
        for _, e in ipairs(entries) do
            local n = spellName(e[1])
            if n then names[n] = math.min(names[n] or 99, lvl) end
        end
    end
    local function talentRank(c)
        local n, r = spellName(c.id), spellRank(c.id)
        local rank = r and tonumber(r:match("%d+"))
        if not (n and rank and rank > 1) or bookNames[n] then return false end
        return not (names[n] and names[n] < c.level)
    end
    local now = { label = "Now at your trainer", now = true, cost = 0, spells = {} }
    local byLevel, levels = {}, {}
    local future = 0
    for _, c in ipairs(list) do
        if talentRank(c) then
            -- left out
        elseif c.level <= level then
            now.spells[#now.spells + 1] = c
            now.cost = now.cost + c.cost
        else
            local s = byLevel[c.level]
            if not s then
                s = { label = "Level " .. c.level, level = c.level, cost = 0, spells = {} }
                byLevel[c.level] = s
                levels[#levels + 1] = c.level
            end
            s.spells[#s.spells + 1] = c
            s.cost = s.cost + c.cost
            future = future + c.cost
        end
    end
    table.sort(levels)
    local out = {}
    if #now.spells > 0 then out[1] = now end
    for _, l in ipairs(levels) do out[#out + 1] = byLevel[l] end
    for _, s in ipairs(out) do
        table.sort(s.spells, function(a, b)
            local na, nb = spellName(a.id) or "", spellName(b.id) or ""
            if na ~= nb then return na < nb end
            return a.id < b.id
        end)
    end
    return out, future, now.cost
end

----------------------------------------------------------------------
-- The frames
----------------------------------------------------------------------
local tab, panel, scroll, content
local rows, heads = {}, {}
local pending = {}               -- spell ids whose data is still loading

local function host() return _G.PlayerSpellsFrame end
local function book()
    local pf = host()
    return pf and pf.SpellBookFrame
end

local function text(parent, font, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetTextColor(color[1], color[2], color[3])
    if justify then fs:SetJustifyH(justify) end
    return fs
end

local function row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetHeight(SP.ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(SP.ROW_H - 2, SP.ROW_H - 2)
    r.icon:SetPoint("LEFT", 6, 0)
    r.cost = text(r, "GameFontHighlightSmall", WHITE, "RIGHT")
    r.cost:SetPoint("RIGHT", -4, 0)
    r.name = text(r, "GameFontHighlightSmall", WHITE, "LEFT")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.name:SetPoint("RIGHT", r.cost, "LEFT", -6, 0)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    if r.SetHighlightTexture then r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
    r:SetScript("OnEnter", function(self) SP.ShowTip(self, self.spell) end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    rows[i] = r
    return r
end

local function head(i)
    local h = heads[i]
    if h then return h end
    h = CreateFrame("Frame", nil, content)
    h:SetHeight(SP.HEAD_H)
    h.line = h:CreateTexture(nil, "BACKGROUND")
    h.line:SetPoint("BOTTOMLEFT", 2, 1)
    h.line:SetPoint("BOTTOMRIGHT", -2, 1)
    h.line:SetHeight(1)
    h.line:SetColorTexture(0.42, 0.35, 0.23, 0.8)
    h.label = text(h, "GameFontNormal", GOLD, "LEFT")
    h.label:SetPoint("BOTTOMLEFT", 4, 4)
    h.cost = text(h, "GameFontHighlightSmall", WHITE, "RIGHT")
    h.cost:SetPoint("BOTTOMRIGHT", -4, 4)
    heads[i] = h
    return h
end

-- the game tooltip of the spell, plus when and for how much
function SP.ShowTip(owner, c)
    if not (GameTooltip and c) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(c.id) end
    local lvl = UnitLevel("player") or 1
    GameTooltip:AddLine(" ")
    if c.level <= lvl then
        GameTooltip:AddLine("Learn now at your class trainer: " .. SP.Money(c.cost), GREEN[1], GREEN[2], GREEN[3])
    else
        GameTooltip:AddLine("Class trainer from level " .. c.level .. ": " .. SP.Money(c.cost), GOLD[1], GOLD[2], GOLD[3])
    end
    GameTooltip:Show()
end

-- a spell's name and rank, asking the game for its data when it is not loaded yet
local function label(id)
    local n, r = spellName(id), spellRank(id)
    if not (n and r) and C_Spell and C_Spell.RequestLoadSpellData and not pending[id] then
        pending[id] = true
        pcall(C_Spell.RequestLoadSpellData, id)
    end
    n = n or ("Spell " .. id)
    if r then return n .. " |cff9a9a9e(" .. r .. ")|r" end
    return n
end

function SP.Refresh()
    if not (panel and panel:IsShown()) then return end
    local level = UnitLevel("player") or 1
    local plan, future, nowCost = SP.Plan(level)
    local y, ri, hi = -4, 0, 0
    local w = SP.W - 34
    for _, s in ipairs(plan or {}) do
        hi = hi + 1
        local h = head(hi)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, y)
        h:SetWidth(w)
        h.label:SetText(s.label)
        local c = WHITE
        if s.now then c = s.cost <= (GetMoney and GetMoney() or 0) and GREEN or RED end
        h.cost:SetText(SP.Money(s.cost))
        h.cost:SetTextColor(c[1], c[2], c[3])
        h:Show()
        y = y - SP.HEAD_H - 2
        for _, sp in ipairs(s.spells) do
            ri = ri + 1
            local r = row(ri)
            r.spell = sp
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, y)
            r:SetWidth(w)
            r.icon:SetTexture(spellIcon(sp.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.name:SetText(label(sp.id))
            r.cost:SetText(SP.Money(sp.cost))
            r:Show()
            y = y - SP.ROW_H
        end
        y = y - 6
    end
    for i = ri + 1, #rows do rows[i]:Hide() end
    for i = hi + 1, #heads do heads[i]:Hide() end
    content:SetHeight(math.max(1, -y))
    if not plan then
        panel.empty:SetText("No trainer data for your class.")
        panel.empty:Show()
    elseif #plan == 0 then
        panel.empty:SetText("Nothing left to learn at your class trainer.")
        panel.empty:Show()
    else
        panel.empty:Hide()
    end
    panel.sub:SetText(string.format("Level %d - %d", math.min(level + 1, SP.MAX_LEVEL), SP.MAX_LEVEL))
    panel.foot:SetText(plan and ("Up to level " .. SP.MAX_LEVEL .. ": " .. SP.Money(future or 0)) or "")
    return plan
end

-- right of the spellbook when the screen has room for it, otherwise over the right side of the open book
function SP.Place()
    local pf = host()
    if not (pf and tab and panel) then return end
    local right = pf.GetRight and pf:GetRight()
    local screen = UIParent and UIParent.GetRight and UIParent:GetRight()
    local outside = not (type(right) == "number" and type(screen) == "number") or right + SP.TAB + SP.W + 4 <= screen
    tab:ClearAllPoints()
    panel:ClearAllPoints()
    if outside then
        tab:SetPoint("TOPLEFT", pf, "TOPRIGHT", 0, SP.TAB_Y)
        panel:SetPoint("TOPLEFT", pf, "TOPRIGHT", SP.TAB + 4, 0)
        panel:SetPoint("BOTTOMLEFT", pf, "BOTTOMRIGHT", SP.TAB + 4, 0)
    else
        tab:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -8, SP.TAB_Y)
        panel:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SP.TAB - 12, SP.TAB_Y + 30)
        panel:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -SP.TAB - 12, 8)
    end
    panel.outside = outside
end

local function build(pf)
    local lvl = pf.GetFrameLevel and pf:GetFrameLevel()
    lvl = type(lvl) == "number" and lvl or 1

    tab = CreateFrame("Button", "OneMoreQuestSpellPreviewTab", pf)
    tab:SetSize(SP.TAB, SP.TAB)
    tab:SetFrameLevel(lvl + SP.LEVEL_UP + 20)
    tab.frame = tab:CreateTexture(nil, "BACKGROUND")
    tab.frame:SetSize(SP.TAB * 2, SP.TAB * 2)
    tab.frame:SetPoint("TOPLEFT", -SP.TAB * 3 / 32, SP.TAB * 11 / 32)
    tab.frame:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetAllPoints()
    tab.icon:SetTexture(SP.ICON)
    if tab.SetHighlightTexture then tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
    tab.lit = tab:CreateTexture(nil, "OVERLAY")
    tab.lit:SetAllPoints()
    tab.lit:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    if tab.lit.SetBlendMode then tab.lit:SetBlendMode("ADD") end
    tab.lit:Hide()
    tab:SetScript("OnClick", function() SP.Toggle() end)
    tab:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Spell Preview")
        GameTooltip:AddLine("Which spells and ranks your class trainer teaches at every coming level, and what they cost.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    panel = CreateFrame("Frame", "OneMoreQuestSpellPreview", pf)
    panel:SetWidth(SP.W)
    panel:SetFrameLevel(lvl + SP.LEVEL_UP)
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.045, 0.96)
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 } }) do
        local t = panel:CreateTexture(nil, "BORDER")
        t:SetPoint(e[1]); t:SetPoint(e[2]); t:SetHeight(e[4])
        t:SetColorTexture(0.42, 0.35, 0.23, 1)
    end
    for _, e in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = panel:CreateTexture(nil, "BORDER")
        t:SetPoint(e[1]); t:SetPoint(e[2]); t:SetWidth(1)
        t:SetColorTexture(0.42, 0.35, 0.23, 1)
    end
    panel.title = text(panel, "GameFontNormalLarge", GOLD, "LEFT")
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.title:SetText("Spell Preview")
    panel.sub = text(panel, "GameFontHighlightSmall", GREY, "RIGHT")
    panel.sub:SetPoint("TOPRIGHT", -26, -14)
    panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.close:SetPoint("TOPRIGHT", 2, 2)
    panel.close:SetScript("OnClick", function() SP.Close() end)
    panel.foot = text(panel, "GameFontNormal", GOLD, "LEFT")
    panel.foot:SetPoint("BOTTOMLEFT", 10, 10)
    panel.empty = text(panel, "GameFontDisable", GREY, "CENTER")
    panel.empty:SetPoint("TOP", 0, -60)
    panel.empty:SetWidth(SP.W - 20)
    panel.empty:Hide()
    scroll = CreateFrame("ScrollFrame", "OneMoreQuestSpellPreviewScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -34)
    scroll:SetPoint("BOTTOMRIGHT", -26, 32)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(SP.W - 30, 1)
    scroll:SetScrollChild(content)
    panel:SetScript("OnShow", function() if tab then tab.lit:Show() end end)
    panel:SetScript("OnHide", function() if tab then tab.lit:Hide() end end)
    panel:Hide()
    if pf.HookScript then pf:HookScript("OnSizeChanged", function() SP.Place() end) end
end

function SP.Open()
    if not panel then return end
    SP.Place()
    panel:Show()
    SP.Refresh()
    if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
end
function SP.Close() if panel then panel:Hide() end end
function SP.Toggle()
    if not panel then return end
    if panel:IsShown() then SP.Close() else SP.Open() end
end

-- the spellbook page opened or closed: the tab only with the spellbook (not the talents), the panel always closed
-- until clicked
function SP.Update()
    local pf, sb = host(), book()
    if not (pf and sb) then return end
    if not tab then build(pf) end
    if SP.On() and sb:IsShown() and pf:IsShown() then
        SP.Place()
        tab:Show()
    else
        tab:Hide()
        panel:Hide()
    end
end
function SP:Tab() return tab end
function SP:Panel() return panel end
function SP:Rows() return rows end
function SP:Heads() return heads end

local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then OMQ:Error("spell preview", err) end
end

local hooked = false
local function hook()
    local pf, sb = host(), book()
    if hooked or not (pf and sb) then return end
    hooked = true
    sb:HookScript("OnShow", function() safe(SP.Update) end)
    sb:HookScript("OnHide", function() safe(SP.Update) end)
    pf:HookScript("OnHide", function() safe(SP.Update) end)
    safe(SP.Update)
end
SP.Hook = hook

local frame = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "SPELL_DATA_LOAD_RESULT" }) do
    pcall(frame.RegisterEvent, frame, e)
end
local refreshSoon = false
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_PlayerSpells" then hook() end
        return
    end
    if not (panel and panel:IsShown()) then return end
    if event == "SPELL_DATA_LOAD_RESULT" then
        pending[name] = nil
        if refreshSoon then return end
        refreshSoon = true
        C_Timer.After(0.2, function() refreshSoon = false; safe(SP.Refresh) end)
        return
    end
    safe(SP.Refresh)
end)
OMQ:On("READY", function() hook() end)
