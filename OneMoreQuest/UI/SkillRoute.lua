-- One More Quest: Skill Route next to the profession window (decision 558; intermediates decision 566)
-- A gold button right above the top profession tab, outside the window (inside it the frame art covered it; fix 565) folds out a panel with the route of the open profession: the
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
SR.TAB_W, SR.TAB_H = 40, 40      -- as big as the profession tab icons (fix 567)
SR.ICON = "Interface\\Icons\\INV_Scroll_03"
SR.TAB_X, SR.TAB_Y = 0, 0         -- the button: at the right edge of the window, level with the top of the route panel (fix 568)
SR.TAB_LEVEL = 30                -- frame levels above the window, so its border and children do not cover it
SR.GAP = 70                      -- the panel: right of the profession tabs on the window's right edge (fix 565)
SR.ROW_H, SR.SUB_H, SR.HEAD_H = 16, 14, 20
SR.NOTE_TIME = 4
SR.CHEAP_N = { 5, 10, 20, "major" }   -- decision 592
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

-- intermediates (decision 566): what a step makes that later steps of the route use. A later step's need of an item
-- goes to the last step before it that makes the item. { [step index] = { item, yield, need (pieces later), extra
-- (crafts beyond the skill crafts), uses = { { step index, pieces } } } }
function SR.Later(route)
    local R, out = OMQ.ProfRecipes or {}, {}
    for j, st in ipairs(route.steps) do
        local r = R[st[3]]
        if r and (st[4] or 0) > 0 then
            for k = 1, #r[3], 2 do
                local item, q = r[3][k], r[3][k + 1]
                for i = j - 1, 1, -1 do
                    local m = R[route.steps[i][3]]
                    if m and m[1] == item then
                        local e = out[i] or { item = item, yield = m[2] or 1, need = 0, uses = {} }
                        out[i] = e
                        local pieces = math.ceil(q * st[4] - 1e-6)
                        e.need = e.need + pieces
                        e.uses[#e.uses + 1] = { j, pieces }
                        break
                    end
                end
            end
        end
    end
    for i, e in pairs(out) do
        local made = (route.steps[i][4] or 0) * e.yield
        e.extra = math.max(0, math.ceil((e.need - made) / e.yield - 1e-6))
    end
    return out
end
-- the step of the route that makes an item, before step index j: index, spell, yield
local function makerBefore(route, item, j)
    local R = OMQ.ProfRecipes or {}
    for i = j - 1, 1, -1 do
        local m = R[route.steps[i][3]]
        if m and m[1] == item then return i, route.steps[i][3], m[2] or 1 end
    end
end

-- the lines of the panel for a route at a skill:
--   { kind = "head", col, from, to, done }
--   { kind = "step", st, state = "done" | "cur" | "todo", left (crafts, cur only), learn ("T"/"V"/"Q" when not learned) }
--   { kind = "mat", item, need, have, vendor }       (under the current step)
function SR.Lines(route, skill)
    local out, cur = {}, nil
    local B = OMQ.ProfCheck and OMQ.ProfCheck.BRACKETS or {}
    local lastCol
    local later = SR.Later(route)
    for idx, st in ipairs(route.steps) do
        local col = bracketOf(st[1])
        if col ~= lastCol then
            lastCol = col
            local b = B[col] or { st[1], st[2] }
            out[#out + 1] = { kind = "head", col = col, from = b[1], to = b[2], done = skill >= b[2] }
        end
        local line = { kind = "step", st = st, idx = idx, later = later[idx] }
        if skill >= st[2] then line.state = "done"
        elseif not cur then line.state = "cur"; cur = line
        else line.state = "todo" end
        if line.state ~= "done" and st[5] ~= "D" and SR.Learned(st[3]) == false then line.learn = st[5] end
        out[#out + 1] = line
        if line == cur then
            line.left = SR.Remaining(st, skill)
            local r = (OMQ.ProfRecipes or {})[st[3]]
            local lt = line.later
            if lt and r then
                -- the pieces later steps need, minus what the remaining skill crafts make and what is in the bags
                local short = lt.need - math.ceil(line.left - 1e-6) * lt.yield - bagCount(lt.item)
                line.skillLeft = line.left
                line.extraNow = math.max(0, math.ceil(short / lt.yield - 1e-6))
                line.left = line.left + line.extraNow
            end
            local n = math.ceil(line.left - 1e-6)
            if r and n > 0 then
                for k = 1, #r[3], 2 do
                    local item = r[3][k]
                    local _, from = OMQ.ProfCheck.Price(item)
                    local m = { kind = "mat", item = item, need = r[3][k + 1] * n, have = bagCount(item),
                                vendor = (from == "vendor") or nil }
                    local mi, mspell, my = makerBefore(route, item, idx)
                    if mi and m.have < m.need then
                        m.make, m.makeSpell = math.ceil((m.need - m.have) / my - 1e-6), mspell
                    end
                    out[#out + 1] = m
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
    return "Click the gold step to craft it. Next trainer visit: at " .. (nextAt or 300) .. "."
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
    b.name:SetPoint("RIGHT", -100, 0)
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
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnClick", function(self, button) SR.Click(self.line, button) end)
    b:SetScript("OnEnter", function(self) SR.RowTooltip(self) end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
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
        b.range:SetText(l.label or string.format("%d - %d", l.from, l.to))
        b.range:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        if l.label then b.range:SetWidth(200); b.count:SetText(l.right or "")
        elseif l.done then b.count:SetText("done"); b.count:SetTextColor(GREY[1], GREY[2], GREY[3])
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
            local t = st[5] == "D" and ("until " .. st[2]) or string.format("~%dx left", math.ceil((l.left or 0) - 1e-6))
            if (l.extraNow or 0) > 0 then t = t .. string.format(" (+%d later)", l.extraNow) end
            b.count:SetText(t)
        elseif st[5] ~= "D" then
            local t = string.format("%dx", math.max(1, math.floor(st[4] + 0.5)))
            if l.later and l.later.extra > 0 and l.state ~= "done" then t = t .. string.format(" +%d later", l.later.extra) end
            b.count:SetText(t)
        end
    elseif l.kind == "learn" then
        b:SetHeight(SR.SUB_H)
        b.name:SetText(l.text or ("Learn: " .. (SR.LEARN[l.how] or "trainer")))
        b.name:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    elseif l.kind == "mat" then
        b:SetHeight(SR.SUB_H)
        b.name:SetText(l.need .. " " .. OMQ.ProfCheck.ItemName(l.item))
        b.name:SetTextColor(GREY[1], GREY[2], GREY[3])
        local enough = l.have >= l.need
        b.count:SetText(l.have .. " in bags" .. (l.vendor and " - vendor" or ""))
        if enough then b.count:SetTextColor(0.5, 0.82, 0.42) else b.count:SetTextColor(0.9, 0.35, 0.3) end
        if l.make then
            b.count:SetText(l.have .. " in bags - make " .. l.make)
            b.count:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
        end
    end
end

-- the lines with the learn lines put under their step
local function display(lines)
    local out = {}
    for _, l in ipairs(lines) do
        out[#out + 1] = l
        if l.kind == "step" and l.learn then out[#out + 1] = { kind = "learn", how = l.learn, text = l.learnText } end
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
    local cheap = SR.Mode() == "cheap" and OMQ.SkillPlan
    SR.PaintModes(cheap)
    local lines = display(cheap and SR.CheapLines(route, skill, max) or (SR.Lines(route, skill)))
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
    if not current.noteUntil or GetTime() >= current.noteUntil then
        panel.foot:SetText(cheap and SR.CheapFooter(current.plan) or SR.Footer(skill, max))
    end
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

-- a short green note in the footer, 4 seconds
function SR.Note(msg)
    if not panel then return end
    panel.foot:SetText("|cff66e07a" .. msg .. "|r")
    current.noteUntil = GetTime() + SR.NOTE_TIME
    C_Timer.After(SR.NOTE_TIME, function()
        if current.noteUntil and GetTime() >= current.noteUntil - 1e-6 then current.noteUntil = nil; SR.Refresh() end
    end)
end

-- how many the bags allow now (the game's count), nil when unknown
function SR.Craftable(spell)
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeInfo) then return nil end
    local ok, info = pcall(T.GetRecipeInfo, spell)
    return ok and type(info) == "table" and num(info.numAvailable) or nil
end

-- the count field of the profession window (fix 562): set the number the player sees next to Create
local function setCount(n)
    local pf = host()
    local page = pf and pf.CraftingPage
    local box = page and (page.CreateMultipleInputBox or (page.SchematicForm and page.SchematicForm.CreateMultipleInputBox))
    if box and box.SetValue then pcall(box.SetValue, box, n) elseif box and box.SetText then pcall(box.SetText, box, tostring(n)) end
end

-- fix 562: a left click on the current step selects the recipe, fills in the crafts still left (at most what the
-- materials allow) and starts crafting; a right click, and a click on any other step, only selects the recipe
-- the tooltip of a step that makes something for later steps, or of a material to make (decision 566)
function SR.RowTooltip(b)
    local l, route = b.line, current.route
    if not (GameTooltip and l and route) then return nil end
    local lines = {}
    if l.kind == "step" and l.later then
        lines[1] = string.format("Also makes %s for later steps:", OMQ.ProfCheck.ItemName(l.later.item))
        for _, u in ipairs(l.later.uses) do
            local st = route.steps[u[1]]
            lines[#lines + 1] = string.format("%d-%d %s: %d", st[1], st[2], OMQ.ProfCheck.RecipeName(st[3]), u[2])
        end
        if l.later.extra > 0 then lines[#lines + 1] = string.format("Make %d more than the skill needs.", l.later.extra) end
    elseif l.kind == "mat" and l.make then
        lines[1] = string.format("Click: make %d %s", l.make, OMQ.ProfCheck.ItemName(l.item))
        lines[2] = "Right click: only select the recipe"
    end
    if #lines == 0 then return nil end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    for i, t in ipairs(lines) do GameTooltip:AddLine(t, i == 1 and 1 or 0.9, i == 1 and 0.82 or 0.9, i == 1 and 0.4 or 0.9, true) end
    GameTooltip:Show()
    return lines
end

-- crafts n of a recipe now (at most what the materials allow); the count field shows it
function SR.Craft(spell, n)
    local can = SR.Craftable(spell)
    if can then n = math.min(n, can) end
    if n <= 0 then SR.Note("|cffff6655Not enough materials for one craft.|r"); return "none" end
    setCount(n)
    if C_Timer and C_Timer.After then C_Timer.After(0.1, function() setCount(n) end) end
    local T = C_TradeSkillUI
    if not (T and T.CraftRecipe) then return "select" end
    local ok, err = pcall(T.CraftRecipe, spell, n)
    if not ok then OMQ:Error("skill route craft", err); return "select" end
    SR.Note(string.format("Crafting %dx %s", n, OMQ.ProfCheck.RecipeName(spell)))
    return n
end

function SR.Click(l, button)
    -- decision 566: a material the route makes itself and that is missing: the click makes it
    if l and l.kind == "mat" and l.make then
        SR.Select(l.makeSpell)
        if button == "RightButton" or SR.Learned(l.makeSpell) == false then return "select" end
        return SR.Craft(l.makeSpell, l.make)
    end
    if not (l and l.kind == "step" and l.st[5] ~= "D") then return nil end
    local spell = l.st[3]
    SR.Select(spell)
    if button == "RightButton" or l.state ~= "cur" or l.learn then return "select" end
    return SR.Craft(spell, math.ceil((l.left or 0) - 1e-6))
end

function SR.MakeList(col)
    local PC = OMQ.ProfCheck
    local route = current.route
    if not (PC and route and OMQ.Shopping) then return nil end
    local list = PC.MakeList(route, col)
    if list then SR.Note("Shopping list created: " .. list.title) end
    return list
end

local function build(pf)
    tab = CreateFrame("Button", "OneMoreQuestSkillRouteTab", pf, BackdropTemplateMixin and "BackdropTemplate" or nil)
    tab:SetSize(SR.TAB_W, SR.TAB_H)
    tab:SetPoint("TOPLEFT", pf, "TOPRIGHT", SR.TAB_X, SR.TAB_Y)
    local lvl = pf.GetFrameLevel and pf:GetFrameLevel()
    if type(lvl) == "number" then tab:SetFrameLevel(lvl + SR.TAB_LEVEL) end
    if tab.SetToplevel then tab:SetToplevel(true) end
    -- the look of the profession tabs next to it (fix 567): the spellbook skill line tab art around a full icon
    tab.frame = tab:CreateTexture(nil, "BACKGROUND")
    tab.frame:SetSize(SR.TAB_W * 2, SR.TAB_H * 2)
    tab.frame:SetPoint("TOPLEFT", -SR.TAB_W * 3 / 32, SR.TAB_H * 11 / 32)
    tab.frame:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetAllPoints()
    tab.icon:SetTexture(SR.ICON)
    if tab.SetHighlightTexture then tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
    tab.lit = tab:CreateTexture(nil, "OVERLAY")
    tab.lit:SetAllPoints()
    tab.lit:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    if tab.lit.SetBlendMode then tab.lit:SetBlendMode("ADD") end
    tab.lit:Hide()
    tab:SetScript("OnClick", function() SR.Toggle() end)
    tab:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Skill Route")
        GameTooltip:AddLine("Which recipe to make how often, from your skill to 300 (the route of the Profession Check).", 1, 1, 1, true)
        GameTooltip:AddLine("Left click on the gold step: crafts what is still needed. Right click: only selects the recipe.", 0.6, 0.8, 1, true)
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
    -- decision 592: Route | Cheapest, and in Cheapest the shopping list buttons
    panel.modes = {}
    local function small(label, w, x, fn)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(w, 18)
        b:SetPoint("TOPLEFT", x, -30)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    panel.modes.route = small("Route", 56, 8, function() SR.SetMode("route") end)
    panel.modes.cheap = small("Cheapest", 70, 66, function() SR.SetMode("cheap") end)
    panel.buy = {}
    for i, n in ipairs(SR.CHEAP_N) do
        local b = small(n == "major" and "to 150" or ("+" .. n), n == "major" and 52 or 36, 146 + (i - 1) * 38, function() SR.MakeCheapList(n) end)
        b.n = n
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Shopping list: cheapest " .. (self.n == "major" and ("skill-ups to " .. (self.to or "")) or (self.n .. " skill-ups")))
            GameTooltip:AddLine("Materials of the cheapest plan, +40% for green and +20% for yellow crafts so one trip to the auction house is enough.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        panel.buy[i] = b
    end
    scroll:SetPoint("TOPLEFT", 4, -52)
    scroll:SetPoint("BOTTOMRIGHT", -26, 34)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(SR.W - 30, 1)
    scroll:SetScrollChild(content)
    panel:SetScript("OnShow", function() if tab then tab.lit:Show() end end)
    panel:SetScript("OnHide", function() if tab then tab.lit:Hide() end; SR.Reanchor() end)
    panel:Hide()
end

----------------------------------------------------------------------
-- Cheapest plan (decision 592, UI/SkillPlan.lua)
----------------------------------------------------------------------
local function modeStore()
    OMQDB = OMQDB or {}
    OMQDB.skillRouteMode = OMQDB.skillRouteMode or {}
    return OMQDB.skillRouteMode
end
function SR.Mode() return modeStore()[me()] == "cheap" and "cheap" or "route" end
function SR.SetMode(m)
    modeStore()[me()] = (m == "cheap") and "cheap" or nil
    current.scrolled = nil
    SR.Refresh()
    if C_Timer and C_Timer.After then C_Timer.After(0, SR.ScrollToCurrent) end
end
function SR.PaintModes(cheap)
    if not panel.modes then return end
    panel.modes.route:SetEnabled(cheap and true or false)
    panel.modes.cheap:SetEnabled(not cheap)
    local to = OMQ.SkillPlan and OMQ.SkillPlan.NextMajor(current.skill or 0, current.max)
    for _, b in ipairs(panel.buy) do
        if cheap then b:Show() else b:Hide() end
        if b.n == "major" and to then b.to = to; b:SetText("to " .. to) end
    end
end

-- the plan to the next major step as panel lines
function SR.CheapLines(route, skill, max)
    local SP = OMQ.SkillPlan
    local to = SP.NextMajor(skill, max)
    local plan = SP.Plan(route.id, skill, to, max)
    current.plan = plan
    local out = { { kind = "head", label = string.format("Cheapest %d - %d", skill, to),
                    right = plan.total > 0 and ("~" .. OMQ.ProfCheck.Money(plan.total)) or "" } }
    for i, ps in ipairs(plan.steps) do
        local st = { ps[1], ps[2], ps[3], ps[4], "T" }
        local line = { kind = "step", st = st, state = i == 1 and "cur" or "todo", cheap = true }
        if ps.learn then
            line.learn = "T"
            line.learnText = string.format("Learn at the trainer at %d%s", ps.learn[2],
                ps.learn[1] and (" (" .. OMQ.ProfCheck.Money(ps.learn[1]) .. ")") or "")
        end
        out[#out + 1] = line
        if i == 1 then
            line.left = ps[4]
            local r = (OMQ.ProfSkillUp or {})[ps[3]]
            local n = math.ceil(ps[4] - 1e-6)
            if r then
                for k = 1, #r[4], 2 do
                    local item = r[4][k]
                    local _, from = OMQ.ProfCheck.Price(item)
                    out[#out + 1] = { kind = "mat", item = item, need = r[4][k + 1] * n, have = bagCount(item),
                                      vendor = (from == "vendor") or nil }
                end
            end
        end
    end
    if #plan.steps == 0 then out[#out + 1] = { kind = "learn", text = "No priced recipe for the next skill-up." } end
    return out
end
function SR.CheapFooter(plan)
    if not plan then return "" end
    local t = {}
    if plan.stop == "cap" then t[#t + 1] = "|cffff9933Rank up at the trainer at " .. plan.reached .. ".|r" end
    if plan.missing > 0 then t[#t + 1] = plan.missing .. " recipes without a price left out." end
    t[#t + 1] = "Prices: auction scan and vendors. Click the gold step to craft it."
    return table.concat(t, " ")
end
function SR.MakeCheapList(n)
    local route, S = current.route, OMQ.Shopping
    if not (route and S and OMQ.SkillPlan) then return nil end
    local list = OMQ.SkillPlan.ShoppingList(route, current.skill or 0, current.max, n)
    local l = S.Add(list)
    SR.Note("Shopping list created: " .. l.title)
    return l
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
