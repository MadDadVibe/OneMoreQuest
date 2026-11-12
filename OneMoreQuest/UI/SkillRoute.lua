-- One More Quest: Skill Route next to the profession window (decision 558)
-- A gold button at the top left of the profession window (right of its portrait; fix 560) folds out a panel with the route of the open profession: the
-- same route the Profession Check and its shopping lists use (Data/ProfRoutes.lua), 1 to 300 in the four sections
-- 1-75, 75-150, 150-225, 225-300. Done steps are green with a check, the step for the current skill has a gold frame,
-- the crafts still left (from the Forever skill-up thresholds, Data/SkillThresholds.lua) and the materials for them
-- with the count in the bags (the bank does not count). A recipe not learned yet is orange with where to learn it.
-- A click on a step selects its recipe in the profession window; the basket of a section makes the same shopping list
-- as a click on that cell of the Profession Check. Open or closed is kept per character. Only the 8 professions with a
-- route get the tab. No sound, no chat line.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local SR = {}
OMQ.SkillRoute = SR

SR.W = 330                     -- panel width
SR.TAB_W, SR.TAB_H = 26, 26
SR.TAB_X, SR.TAB_Y = 100, -54    -- the button: between the portrait and the skill bar
SR.GAP = 44                      -- the panel: right of the profession tabs on the window's right edge
SR.ROW_H, SR.SUB_H, SR.HEAD_H = 16, 14, 20
SR.NOTE_TIME = 4
SR.DISENCHANT = 13262          -- the Disenchant spell: its name in the client's language for the enchanting step 2-20
SR.LEARN = { T = "trainer", V = "vendor recipe", Q = "special trainer (quest)" }

local GOLD = { 0.95, 0.82, 0.48 }
local GREY = { 0.54, 0.56, 0.61 }
local DONE = { 0.45, 0.68, 0.38 }
local WHITE = { 0.92, 0.9, 0.85 }
local ORANGE = { 0.95, 0.6, 0.25 }
local MEDIA = "Interface\\AddOns\\OneMoreQuest\\Media\\"

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
function SR.On() return not (OMQ.db and OMQ.db.options and OMQ.db.options.skillRoute == false) end

----------------------------------------------------------------------
-- The open profession
----------------------------------------------------------------------
function SR.RouteFor(id)
    if not id then return nil end
    for _, r in ipairs(OMQ.ProfRoutes or {}) do if r.id == id then return r end end
end

-- the profession in the window: route, skill, max skill; nil when it has no route or is someone else's (a link)
function SR.Current()
    local T = C_TradeSkillUI
    if T then
        for _, fn in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
            if T[fn] then
                local ok, v = pcall(T[fn])
                if ok and v == true then return nil end
            end
        end
    end
    local id, parent, name, skill, max
    if T and T.GetBaseProfessionInfo then
        local ok, p = pcall(T.GetBaseProfessionInfo)
        if ok and type(p) == "table" then
            id, parent = num(p.professionID), num(p.parentProfessionID)
            name = type(p.professionName) == "string" and not isSecret(p.professionName) and p.professionName or nil
            skill, max = num(p.skillLevel), num(p.maxSkillLevel)
        end
    end
    if not (name or id) and GetTradeSkillLine then
        local ok, n, rank, m = pcall(GetTradeSkillLine)
        if ok and type(n) == "string" then name, skill, max = n, num(rank), num(m) end
    end
    local NL = OMQ.ProfCheck and OMQ.ProfCheck.NAME_LINE or {}
    local route = SR.RouteFor(id) or SR.RouteFor(parent) or (name and SR.RouteFor(NL[name:lower()]))
    if not route then return nil end
    if not skill then skill = (OMQ.ProfCheck and OMQ.ProfCheck.Mine()[route.id]) end
    return route, skill or 0, max
end

----------------------------------------------------------------------
-- The numbers
----------------------------------------------------------------------
-- the chance of a skill-up at a skill: 1 below yellow, then linear down to 0 at gray
local function chance(s, t)
    if s < t[2] then return 1 end
    if s >= t[4] then return 0 end
    return (t[4] - s) / (t[4] - t[2])
end
-- the crafts a step still needs from this skill on: the sum of 1/chance per point from the thresholds, else the
-- route's count for the share of the step that is left
function SR.Remaining(st, skill)
    if skill >= st[2] or st[5] == "D" or (st[4] or 0) <= 0 then return 0 end
    local from = math.max(skill, st[1])
    local span = st[2] - st[1]
    local share = span > 0 and st[4] * (st[2] - from) / span or st[4]
    local t = (OMQ.SkillThresholds or {})[st[3]]
    if not (t and t[2] and t[4]) then return share end
    local sum = 0
    for s = from, st[2] - 1 do
        local c = chance(s, t)
        if c <= 0 then return share end
        sum = sum + 1 / c
    end
    return sum
end

function SR.Learned(spell)
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeInfo) then return nil end
    local ok, info = pcall(T.GetRecipeInfo, spell)
    if ok and type(info) == "table" then return info.learned ~= false end
    return false
end

local function bagCount(id)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, id, false)
        if ok and num(n) then return n end
    end
    if GetItemCount then
        local ok, n = pcall(GetItemCount, id, false)
        if ok and num(n) then return n end
    end
    return 0
end

local function bracketOf(from)
    local B = OMQ.ProfCheck and OMQ.ProfCheck.BRACKETS or {}
    for i, b in ipairs(B) do if from < b[2] then return i end end
    return #B
end

-- the lines of the panel for a route at a skill:
--   { kind = "head", col, from, to, done }
--   { kind = "step", st, state = "done" | "cur" | "todo", left (crafts, cur only), learn ("T"/"V"/"Q" when not learned) }
--   { kind = "mat", item, need, have, vendor }       (under the current step)
function SR.Lines(route, skill)
    local out, cur = {}, nil
    local B = OMQ.ProfCheck and OMQ.ProfCheck.BRACKETS or {}
    local lastCol
    for _, st in ipairs(route.steps) do
        local col = bracketOf(st[1])
        if col ~= lastCol then
            lastCol = col
            local b = B[col] or { st[1], st[2] }
            out[#out + 1] = { kind = "head", col = col, from = b[1], to = b[2], done = skill >= b[2] }
        end
        local line = { kind = "step", st = st }
        if skill >= st[2] then line.state = "done"
        elseif not cur then line.state = "cur"; cur = line
        else line.state = "todo" end
        if line.state ~= "done" and st[5] ~= "D" and SR.Learned(st[3]) == false then line.learn = st[5] end
        out[#out + 1] = line
        if line == cur then
            line.left = SR.Remaining(st, skill)
            local r = (OMQ.ProfRecipes or {})[st[3]]
            local n = math.ceil(line.left - 1e-6)
            if r and n > 0 then
                for k = 1, #r[3], 2 do
                    local item = r[3][k]
                    local _, from = OMQ.ProfCheck.Price(item)
                    out[#out + 1] = { kind = "mat", item = item, need = r[3][k + 1] * n, have = bagCount(item),
                                      vendor = (from == "vendor") or nil }
                end
            end
        end
    end
    return out, cur
end

-- the footer: when to go to the trainer
function SR.Footer(skill, max)
    if skill >= 300 then return "Route done." end
    if max and max > 0 and skill >= max then return "|cffff9933Rank up at the trainer now - you are at " .. max .. ".|r" end
    local nextAt = max and max > skill and max or nil
    if not nextAt then
        for _, b in ipairs(OMQ.ProfCheck.BRACKETS) do if b[2] > skill then nextAt = b[2]; break end end
    end
    return "Click a step to select its recipe. Next trainer visit: at " .. (nextAt or 300) .. "."
end

----------------------------------------------------------------------
-- The tab and the panel
----------------------------------------------------------------------
local tab, panel, scroll, content
local rows = {}
local current = {}

local function host() return _G.ProfessionsFrame end

local function store()
    OMQDB = OMQDB or {}
    OMQDB.skillRoute = OMQDB.skillRoute or {}
    return OMQDB.skillRoute
end
local function me() return UnitGUID and UnitGUID("player") or "?" end
function SR.WantOpen() return store()[me()] == true end
function SR.SetOpen(v) store()[me()] = v and true or nil end

local function text(parent, template, c, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end
local function edge(parent, c)
    for i = 1, 4 do
        local e = parent:CreateTexture(nil, "BORDER")
        e:SetColorTexture(c[1], c[2], c[3], 1)
        if i == 1 then e:SetPoint("TOPLEFT"); e:SetPoint("TOPRIGHT"); e:SetHeight(1)
        elseif i == 2 then e:SetPoint("BOTTOMLEFT"); e:SetPoint("BOTTOMRIGHT"); e:SetHeight(1)
        elseif i == 3 then e:SetPoint("TOPLEFT"); e:SetPoint("BOTTOMLEFT"); e:SetWidth(1)
        else e:SetPoint("TOPRIGHT"); e:SetPoint("BOTTOMRIGHT"); e:SetWidth(1) end
    end
end

-- selects a recipe in the profession window (the player only presses Create)
function SR.Select(spell)
    local pf = host()
    local list = pf and pf.CraftingPage and pf.CraftingPage.RecipeList
    local T = C_TradeSkillUI
    local info = T and T.GetRecipeInfo and select(2, pcall(T.GetRecipeInfo, spell))
    if type(info) ~= "table" then return false end
    if list and list.SelectRecipe and pcall(list.SelectRecipe, list, info, true) then return true end
    if T.OpenRecipe and pcall(T.OpenRecipe, spell) then return true end
    return false
end

local function row(i)
    if rows[i] then return rows[i] end
    local b = CreateFrame("Button", nil, content)
    b:SetHeight(SR.ROW_H)
    b:SetPoint("LEFT", content, "LEFT", 0, 0)
    b:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.range = text(b, "GameFontHighlightSmall", GREY)
    b.range:SetPoint("LEFT", 8, 0)
    b.range:SetWidth(52)
    b.name = text(b, "GameFontHighlightSmall", WHITE)
    b.name:SetPoint("LEFT", 62, 0)
    b.name:SetPoint("RIGHT", -64, 0)
    b.count = text(b, "GameFontHighlightSmall", WHITE, "RIGHT")
    b.count:SetPoint("RIGHT", -8, 0)
    b.cart = CreateFrame("Button", nil, b)
    b.cart:SetSize(52, 16)
    b.cart:SetPoint("RIGHT", -6, 0)
    b.cart.icon = b.cart:CreateTexture(nil, "ARTWORK")
    b.cart.icon:SetSize(14, 14)
    b.cart.icon:SetPoint("LEFT", 2, 0)
    b.cart.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    b.cart.label = text(b.cart, "GameFontHighlightSmall", WHITE)
    b.cart.label:SetPoint("LEFT", b.cart.icon, "RIGHT", 4, 0)
    b.cart.label:SetText("List")
    b.cart:SetScript("OnClick", function(self) SR.MakeList(self.col) end)
    b.cart:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Shopping list for this section")
        GameTooltip:AddLine("The same list as a click on this cell of the Profession Check; the auction house buys it in its Shopping tab.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b.cart:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self)
        local l = self.line
        if l and l.kind == "step" and l.st[5] ~= "D" then SR.Select(l.st[3]) end
    end)
    rows[i] = b
    return b
end

local function paintRow(b, l, route)
    b.line = l
    b.cart:Hide()
    b.bg:SetColorTexture(0, 0, 0, 0)
    b.range:SetText(""); b.count:SetText(""); b.name:SetText("")
    b.range:SetTextColor(GREY[1], GREY[2], GREY[3])
    b.name:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
    b.count:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
    if l.kind == "head" then
        b:SetHeight(SR.HEAD_H)
        b.range:SetWidth(120)
        b.range:SetText(string.format("%d - %d", l.from, l.to))
        b.range:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        if l.done then b.count:SetText("done"); b.count:SetTextColor(GREY[1], GREY[2], GREY[3])
        else b.cart.col = l.col; b.cart:Show() end
    elseif l.kind == "step" then
        local st = l.st
        b:SetHeight(SR.ROW_H)
        b.range:SetWidth(52)
        b.range:SetText(string.format("%d-%d", st[1], st[2]))
        local name = st[5] == "D" and (OMQ.ProfCheck.RecipeName(SR.DISENCHANT) .. " (no recipe)") or OMQ.ProfCheck.RecipeName(st[3])
        if l.state == "done" then
            b.name:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " .. name)
            b.name:SetTextColor(DONE[1], DONE[2], DONE[3])
            b.range:SetTextColor(DONE[1], DONE[2], DONE[3])
            b.count:SetTextColor(DONE[1], DONE[2], DONE[3])
        else
            b.name:SetText(name)
        end
        if l.state == "cur" then
            b.bg:SetColorTexture(0.42, 0.33, 0.13, 0.55)
            b.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            b.count:SetText(st[5] == "D" and ("until " .. st[2]) or string.format("~%dx left", math.ceil((l.left or 0) - 1e-6)))
        elseif st[5] ~= "D" then
            b.count:SetText(string.format("%dx", math.floor(st[4] + 0.5)))
        end
    elseif l.kind == "learn" then
        b:SetHeight(SR.SUB_H)
        b.name:SetText("Learn: " .. (SR.LEARN[l.how] or "trainer"))
        b.name:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif l.kind == "mat" then
        b:SetHeight(SR.SUB_H)
        b.name:SetText(l.need .. " " .. OMQ.ProfCheck.ItemName(l.item))
        b.name:SetTextColor(GREY[1], GREY[2], GREY[3])
        local enough = l.have >= l.need
        b.count:SetText(l.have .. " in bags" .. (l.vendor and " - vendor" or ""))
        if enough then b.count:SetTextColor(0.5, 0.82, 0.42) else b.count:SetTextColor(0.9, 0.35, 0.3) end
    end
end

-- the lines with the learn lines put under their step
local function display(lines)
    local out = {}
    for _, l in ipairs(lines) do
        out[#out + 1] = l
        if l.kind == "step" and l.learn then out[#out + 1] = { kind = "learn", how = l.learn } end
    end
    return out
end

function SR.Refresh()
    if not (panel and panel:IsShown()) then return end
    local route, skill, max = SR.Current()
    if not route then panel:Hide(); return end
    current.route, current.skill, current.max = route, skill, max
    panel.title:SetText("Skill Route - " .. OMQ.ProfCheck.ProfName(route))
    panel.skill:SetText(skill .. " / 300")
    local lines = display((SR.Lines(route, skill)))
    current.lines = lines
    local y, curY = 0, nil
    for i, l in ipairs(lines) do
        local b = row(i)
        paintRow(b, l, route)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        b:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        b:Show()
        if l.kind == "step" and l.state == "cur" then curY = y end
        y = y + (l.kind == "head" and SR.HEAD_H or ((l.kind == "step") and SR.ROW_H or SR.SUB_H))
    end
    for i = #lines + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, y))
    current.curY = curY
    if not current.noteUntil or GetTime() >= current.noteUntil then panel.foot:SetText(SR.Footer(skill, max)) end
    return lines
end

-- scrolls the current step into view (once per opening)
function SR.ScrollToCurrent()
    if not (scroll and current.curY) then return end
    local target = math.max(0, current.curY - 3 * SR.ROW_H)
    local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()
    if type(range) == "number" then target = math.min(target, range) end
    scroll:SetVerticalScroll(target)
    current.scrolled = target
end

function SR.MakeList(col)
    local PC = OMQ.ProfCheck
    local route = current.route
    if not (PC and route and OMQ.Shopping) then return nil end
    local list = PC.MakeList(route, col)
    if list and panel then
        panel.foot:SetText("|cff66e07aShopping list created: " .. list.title .. "|r")
        current.noteUntil = GetTime() + SR.NOTE_TIME
        C_Timer.After(SR.NOTE_TIME, function()
            if current.noteUntil and GetTime() >= current.noteUntil - 1e-6 then current.noteUntil = nil; SR.Refresh() end
        end)
    end
    return list
end

local function build(pf)
    tab = CreateFrame("Button", "OneMoreQuestSkillRouteTab", pf, BackdropTemplateMixin and "BackdropTemplate" or nil)
    tab:SetSize(SR.TAB_W, SR.TAB_H)
    tab:SetPoint("TOPLEFT", pf, "TOPLEFT", SR.TAB_X, SR.TAB_Y)
    local tbg = tab:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints()
    tbg:SetColorTexture(0.23, 0.18, 0.11, 0.95)
    edge(tab, { 0.85, 0.7, 0.3 })
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetSize(20, 20)
    tab.icon:SetPoint("CENTER", 0, 0)
    tab.icon:SetTexture(MEDIA .. "Icon_Profession")
    tab.lit = tab:CreateTexture(nil, "OVERLAY")
    tab.lit:SetAllPoints()
    tab.lit:SetColorTexture(1, 0.85, 0.35, 0.25)
    tab.lit:Hide()
    tab:SetScript("OnClick", function() SR.Toggle() end)
    tab:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Skill Route")
        GameTooltip:AddLine("Which recipe to make how often, from your skill to 300 (the route of the Profession Check).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    panel = CreateFrame("Frame", "OneMoreQuestSkillRoute", pf)
    panel:SetWidth(SR.W)
    panel:SetPoint("TOPLEFT", pf, "TOPRIGHT", SR.GAP, 0)
    panel:SetPoint("BOTTOMLEFT", pf, "BOTTOMRIGHT", SR.GAP, 0)
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.045, 0.96)
    edge(panel, { 0.42, 0.35, 0.23 })
    panel.title = text(panel, "GameFontNormal", GOLD)
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.skill = text(panel, "GameFontHighlightSmall", GREY, "RIGHT")
    panel.skill:SetPoint("TOPRIGHT", -10, -12)
    panel.foot = text(panel, "GameFontDisableSmall", GREY)
    panel.foot:SetPoint("BOTTOMLEFT", 10, 10)
    panel.foot:SetPoint("RIGHT", -10, 0)
    panel.foot:SetWordWrap(true)
    scroll = CreateFrame("ScrollFrame", "OneMoreQuestSkillRouteScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -30)
    scroll:SetPoint("BOTTOMRIGHT", -26, 34)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(SR.W - 30, 1)
    scroll:SetScrollChild(content)
    panel:SetScript("OnShow", function() if tab then tab.lit:Show() end end)
    panel:SetScript("OnHide", function() if tab then tab.lit:Hide() end; SR.Reanchor() end)
    panel:Hide()
end

-- the "who has the materials" panel moves right of the route while it is open
function SR.Reanchor()
    local A = OMQ.RecipeAsk
    if A and A.Reanchor then pcall(A.Reanchor, A) end
end
function SR.RightOf()
    if panel and panel:IsShown() then return panel end
    return host()
end

function SR.Open()
    if not panel then return end
    panel:Show()
    current.scrolled = nil
    SR.Refresh()
    if C_Timer and C_Timer.After then C_Timer.After(0, SR.ScrollToCurrent) else SR.ScrollToCurrent() end
    SR.Reanchor()
end
function SR.Toggle()
    if not panel then return end
    if panel:IsShown() then panel:Hide(); SR.SetOpen(false)
    else SR.SetOpen(true); SR.Open() end
end

-- the profession window opened or changed profession: the tab only for a profession with a route
function SR.Update()
    local pf = host()
    if not pf then return end
    if not tab then build(pf) end
    local route = SR.On() and SR.Current()
    if not route then tab:Hide(); panel:Hide(); return end
    tab:Show()
    if OMQ.ProfCheck.Prefetch then OMQ.ProfCheck.Prefetch() end
    if panel:IsShown() then
        if current.route ~= route then current.route = nil; SR.Open() else SR.Refresh() end
    elseif SR.WantOpen() then SR.Open() end
end
function SR:Tab() return tab end
function SR:Panel() return panel end
function SR:Rows() return rows end
function SR:State() return current end

local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then OMQ:Error("skill route", err) end
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED",
                     "BAG_UPDATE_DELAYED", "NEW_RECIPE_LEARNED" }) do pcall(frame.RegisterEvent, frame, e) end
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_Professions" then return end
    local pf = host()
    if not (pf and pf:IsShown()) and event ~= "ADDON_LOADED" then return end
    if event == "BAG_UPDATE_DELAYED" then safe(SR.Refresh) else safe(SR.Update) end
end)
OMQ:On("READY", function() if host() and host():IsShown() then safe(SR.Update) end end)
