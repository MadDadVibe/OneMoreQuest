-- One More Quest: BiS Check (decision 657). A check bar icon (always shown) opens a window with the pre-raid BiS list of
-- my class and spec on WoW Forever: one row per slot with the item (icon, name, real tooltip on hover), where it comes
-- from (boss and dungeon, quest, craft, vendor, reputation, battleground) and whether I wear it, carry it or still
-- need it. On top the spec (found from my talents, any spec of my class can be chosen) and "Pre-Raid BiS" or
-- "Realistic". Horde players see the Horde twin of Alliance items (Darkspear Islands, Arathi Basin, Warsong Gulch).
-- Left click on an item: an item that binds when equipped goes onto the shopping list "BiS Check" (Auction Helper);
-- any other leads the arrow to its boss's dungeon, quest giver or vendor. Shift click links it in the chat.
-- At the bottom "Where next?": below level 60 first the dungeons and quests I can already do at my level with the
-- most missing items, then the other sources I can use now, then the rest from the lowest level; at 60 the most
-- missing items first. A click on a line starts the arrow. No chat lines: the window says what happened.
-- Lists: Data/BisLists.lua (tests/bis_gen.py).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local BC = {}
OMQ.BisCheck = BC

local GOLD = { 0.89, 0.71, 0.29 }
local W, ROW_H, MAX_ROWS, NEXT_ROWS = 600, 22, 17, 4
BC.MAX_ROWS = MAX_ROWS

BC.SLOT_LABEL = { head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist",
    hands = "Hands", waist = "Waist", legs = "Legs", feet = "Feet", ring1 = "Ring", ring2 = "Ring", trinket1 = "Trinket",
    trinket2 = "Trinket", mh = "Main hand", oh = "Off hand", ["2h"] = "Two-hand", ranged = "Ranged", relic = "Relic" }
BC.KIND_LABEL = { drop = "Drop", quest = "Quest", craft = "Craft", vendor = "Vendor", rep = "Reputation",
    t05 = "Quest", pvp = "PvP", world = "World drop" }

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function myLevel() return UnitLevel and tonumber((UnitLevel("player"))) or 1 end
local function myClass() local _, c = UnitClass("player"); return c end
local function horde() return UnitFactionGroup and UnitFactionGroup("player") == "Horde" end

local function store()
    OMQDB = OMQDB or {}
    OMQDB.bis = OMQDB.bis or {}
    local guid = UnitGUID and UnitGUID("player") or "?"
    OMQDB.bis[guid] = OMQDB.bis[guid] or {}
    return OMQDB.bis[guid]
end

----------------------------------------------------------------------
-- Items
----------------------------------------------------------------------
local function itemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, name, link, quality, _, minLevel, _, _, _, _, icon, _, _, _, bind = pcall(f, id)
    if not ok or not name or isSecret(name) then return nil end
    return { name = name, link = link, quality = quality, minLevel = minLevel, icon = icon, bind = bind }
end
BC.ItemInfo = itemInfo
local function iconOf(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if f then local ok, ic = pcall(f, id); if ok and ic then return ic end end
    local i = itemInfo(id)
    return i and i.icon or 134400
end
local requested = {}
local function request(id)
    if requested[id] then return end
    requested[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- the twin of my faction: Alliance item -> Horde item and back
local reverse
function BC.ForFaction(id, isHorde)
    local T = OMQ.BisTwins or {}
    if not reverse then reverse = {}; for a, h in pairs(T) do reverse[h] = a end end
    if isHorde then return T[id] or id end
    return reverse[id] or id
end

-- the level an item needs: the data's, else the game's
function BC.ItemLevel(id)
    local d = OMQ.BisItems and OMQ.BisItems[id]
    if d and d[4] and d[4] > 0 then return d[4] end
    local i = itemInfo(id)
    return i and tonumber(i.minLevel) or 0
end

local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local function worn(id)
    if not GetInventoryItemID then return false end
    for _, s in ipairs(EQUIP_SLOTS) do
        local ok, x = pcall(GetInventoryItemID, "player", s)
        if ok and x == id then return true end
    end
    return false
end
local function carried(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return false end
    local ok, n = pcall(f, id)
    return ok and tonumber(n) and tonumber(n) > 0 or false
end
-- "worn", "bags" or "missing"
function BC.Status(id)
    if worn(id) then return "worn" end
    if carried(id) then return "bags" end
    return "missing"
end

----------------------------------------------------------------------
-- Spec
----------------------------------------------------------------------
function BC.Specs(class) return (OMQ.BisSpecs or {})[class or myClass() or ""] or {} end
function BC.SpecByKey(key, class)
    for _, s in ipairs(BC.Specs(class)) do if s.key == key then return s end end
end

-- points in a talent tree: Classic Era (id, name, description, icon, points) or old (name, icon, points)
function BC.TabPoints(i)
    if not GetTalentTabInfo then return nil end
    local r = { pcall(GetTalentTabInfo, i) }
    if not r[1] then return nil end
    local v = (type(r[2]) == "string") and r[4] or r[6]
    return tonumber(v)
end

-- my spec from the talents (the tree with the most points); without points the preferred role decides
function BC.Detect()
    local specs = BC.Specs()
    if #specs == 0 then return nil end
    local best, bp = nil, 0
    for t = 1, 3 do
        local p = BC.TabPoints(t)
        if p and p > bp then best, bp = t, p end
    end
    if not best and GetSpecialization then
        local ok, s = pcall(GetSpecialization)
        if ok and tonumber(s) then best = tonumber(s) end
    end
    local role = OMQ.Score and OMQ.Score.MyRole and OMQ.Score.MyRole() or nil
    if best then
        local first, same
        for _, s in ipairs(specs) do
            if s.tab == best then
                first = first or s
                if s.role == role then same = same or s end
            end
        end
        if same or first then return same or first end      -- a feral druid in tank role gets the bear list
    end
    for _, s in ipairs(specs) do if s.role == role and s.tab > 0 then return s end end
    return specs[1]
end
function BC.Current()
    local st = store()
    return (st.spec and BC.SpecByKey(st.spec)) or BC.Detect()
end
function BC.SetSpec(key) store().spec = key; BC:Render() end
function BC.ListKind() return store().list or "B" end
function BC.SetList(k) store().list = k; BC:Render() end

----------------------------------------------------------------------
-- Rows and "Where next?"
----------------------------------------------------------------------
-- the rows of a spec: { slot, label, id, kind, source, dungeon, level, status, place, group }
function BC.Rows(spec, kind, isHorde)
    local out = {}
    if not spec then return out end
    for _, e in ipairs(spec[kind or "B"] or {}) do
        local id = BC.ForFaction(e[2], isHorde)
        local d = OMQ.BisItems and OMQ.BisItems[id] or {}
        out[#out + 1] = { slot = e[1], label = BC.SLOT_LABEL[e[1]] or e[1], id = id, source = d[1] or "?",
            kind = d[2] or "world", dungeon = d[3] or nil, level = BC.ItemLevel(id), qlevel = d[5] or 0,
            place = d[6] or nil, group = d[7] or "w", status = BC.Status(id) }
    end
    return out
end

local function groupLabel(g, r)
    local k, v = g:match("^(%a+):?(.*)$")
    if k == "d" then
        local d = OMQ.DungeonByKey and OMQ:DungeonByKey(v)
        return d and d.name or v
    elseif k == "q" then return (r.source:match("^[^,]+") or r.source)
    elseif k == "n" then return r.place and r.place[4] or (r.source:match("^[^,]+") or r.source)
    elseif k == "t05" then return "Tier 0.5 questline"
    elseif k == "c" then return v .. " (craft)"
    elseif k == "p" then return v
    elseif k == "r" then return v
    end
    return "World drops"
end
-- the level a source can be done at: a dungeon's lowest level, a quest's level, else the items' level
local function groupLevel(g, r)
    local k, v = g:match("^(%a+):?(.*)$")
    if k == "d" then
        local d = OMQ.DungeonByKey and OMQ:DungeonByKey(v)
        if d and d.min then return d.min end
    end
    if r.qlevel and r.qlevel > 0 then return r.qlevel end
    return r.level or 0
end

-- missing items grouped by where they come from, in the order of decision 657
function BC.WhereNext(rows, level)
    local by, list = {}, {}
    for _, r in ipairs(rows) do
        if r.status == "missing" then
            local g = by[r.group]
            if not g then
                local k = r.group:match("^(%a+)")
                g = { key = r.group, label = groupLabel(r.group, r), n = 0, ids = {}, row = r,
                      level = groupLevel(r.group, r), place = (k == "d" or k == "q") }
                by[r.group] = g
                list[#list + 1] = g
            else
                g.level = math.min(g.level, groupLevel(r.group, r))
            end
            if not g.ids[r.id] then g.ids[r.id] = true; g.n = g.n + 1 end
        end
    end
    for _, g in ipairs(list) do
        g.now = g.level <= level
        if level >= 60 then g.rank = 0
        elseif g.now and g.place then g.rank = 0
        elseif g.now then g.rank = 1
        else g.rank = 2 end
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.rank == 2 and a.level ~= b.level then return a.level < b.level end
        if a.n ~= b.n then return a.n > b.n end
        if a.place ~= b.place then return a.place end
        return a.label < b.label
    end)
    return list
end

----------------------------------------------------------------------
-- Clicks: shopping list or arrow
----------------------------------------------------------------------
local function myWorld()
    if not UnitPosition then return nil end
    local a, b, _, inst = UnitPosition("player")
    if type(a) ~= "number" or isSecret(a) or isSecret(b) then return nil end
    return a, b, inst
end
local function zoneName(map)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or ("map " .. tostring(map))
end

-- where the arrow should lead for a row: { map, x, y, name } or nil
function BC.PlaceOf(r)
    if r.kind == "t05" then
        local p = OMQ.BisT05 and OMQ.BisT05[horde() and "H" or "A"]
        if p then return p end
    end
    if r.place then return r.place end
    if r.dungeon and r.kind ~= "craft" then
        local list = OMQ.DungeonEntrances and OMQ.DungeonEntrances[r.dungeon]
        if list and list[1] then
            local best = list[1]
            local a, b, inst = myWorld()
            if a and OMQ.Guide and OMQ.Guide.WorldOf then
                local bd
                for _, e in ipairs(list) do
                    local w = OMQ.Guide.WorldOf({ nil, nil, e[1], e[2], e[3] })
                    if w and w[3] == inst then
                        local dd = (w[1] - a) ^ 2 + (w[2] - b) ^ 2
                        if not bd or dd < bd then best, bd = e, dd end
                    end
                end
            end
            local d = OMQ.DungeonByKey and OMQ:DungeonByKey(r.dungeon)
            return { best[1], best[2], best[3], d and d.name or r.dungeon }
        end
    end
    return nil
end

local note = ""
local function setNote(s) note = s or ""; BC:Render() end
BC.SetNote = setNote

function BC.Guide(p, label)
    if not p then return false, "none" end
    local w = OMQ.Guide and OMQ.Guide.WorldOf and OMQ.Guide.WorldOf({ nil, nil, p[1], p[2], p[3] })
    if not w then return false, "nopos" end
    local a, _, inst = myWorld()
    if a and w[3] ~= inst then return false, "continent" end
    OMQ.Guide:StartAt(label or p[4] or "BiS", w[1], w[2], w[3], "bis", nil, { name = p[4] })
    return true
end

-- the shopping list "BiS Check": every click adds the item once (never twice)
function BC.AddToShopping(id)
    local S = OMQ.Shopping
    if not S then return false end
    local l = S.Find("bis") or S.Add({ key = "bis", title = "BiS Check", source = "bis", items = {} })
    for _, it in ipairs(l.items) do if it.itemID == id then return false, "already" end end
    l.items[#l.items + 1] = { itemID = id, n = 1, bought = 0 }
    S.Select("bis")
    return true
end

function BC.Click(r, button)
    if not r then return end
    local info = itemInfo(r.id)
    if IsShiftKeyDown and IsShiftKeyDown() and info and info.link and HandleModifiedItemClick then
        HandleModifiedItemClick(info.link)
        return "link"
    end
    local name = info and info.name or ("item " .. r.id)
    if info and info.bind == 2 then                       -- binds when equipped: buy it (decision 657, point 3)
        local ok, why = BC.AddToShopping(r.id)
        setNote(ok and (name .. " is on the shopping list \"BiS Check\" (Auction Helper).")
            or (why == "already" and (name .. " is already on the shopping list \"BiS Check\".") or "No shopping list available."))
        return ok and "shop" or why
    end
    local p = BC.PlaceOf(r)
    if not p then
        if r.kind == "craft" then setNote(name .. ": craft it - " .. r.source .. ".")
        else setNote(name .. ": " .. r.source .. ".") end
        return "none"
    end
    local ok, why = BC.Guide(p, "BiS: " .. name)
    if ok then setNote("Arrow to " .. (p[4] or "the place") .. " (" .. zoneName(p[1]) .. ").")
    elseif why == "continent" then setNote((p[4] or "The place") .. " is on another continent (" .. zoneName(p[1]) .. ").")
    else setNote("No position for " .. (p[4] or "the place") .. ".") end
    return ok and "arrow" or why
end

function BC.ClickNext(g)
    if not g then return end
    local p = BC.PlaceOf(g.row)
    if not p then setNote(g.label .. ": " .. g.row.source .. "."); return "none" end
    local ok, why = BC.Guide(p, "BiS: " .. g.label)
    if ok then setNote("Arrow to " .. (p[4] or g.label) .. " (" .. zoneName(p[1]) .. ").")
    elseif why == "continent" then setNote((p[4] or g.label) .. " is on another continent (" .. zoneName(p[1]) .. ").")
    else setNote("No position for " .. (p[4] or g.label) .. ".") end
    return ok and "arrow" or why
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local win, title, sub, rows, specBtns, listBtns, nextHead, nextRows, noteFs
local view = {}

local function tip(self)
    if not self.r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.r.id)
    else GameTooltip:SetHyperlink("item:" .. self.r.id) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("BiS Check: " .. (BC.KIND_LABEL[self.r.kind] or "") .. " - " .. self.r.source, 1, 0.82, 0, true)
    local info = itemInfo(self.r.id)
    if info and info.bind == 2 then GameTooltip:AddLine("Click: put it on the shopping list (Auction Helper)", 0.6, 0.8, 1)
    else GameTooltip:AddLine("Click: arrow to where it comes from", 0.6, 0.8, 1) end
    GameTooltip:AddLine("Shift+click: link it in the chat", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
local function untip() if GameTooltip then GameTooltip:Hide() end end

local function smallButton(parent, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetScript("OnClick", onClick)
    return b
end

local function build()
    win = CreateFrame("Frame", "OneMoreQuestBisWindow", UIParent)
    win:SetSize(W, 200)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
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
    title:SetText("BiS Check")
    sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 120, -16)
    sub:SetWidth(W - 160)
    sub:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() BC:Close() end)
    specBtns = {}
    for i = 1, 4 do
        local b = smallButton(win, 112, function(self) if self.key then BC.SetSpec(self.key) end end)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * 116, -38)
        specBtns[i] = b
    end
    listBtns = {
        smallButton(win, 104, function() BC.SetList("B") end),
        smallButton(win, 84, function() BC.SetList("R") end),
    }
    listBtns[1]:SetText("Pre-Raid BiS"); listBtns[2]:SetText("Realistic")
    listBtns[2]:SetPoint("TOPRIGHT", -14, -38)
    listBtns[1]:SetPoint("RIGHT", listBtns[2], "LEFT", -4, 0)
    rows = {}
    BC._rows = rows
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(W - 28, ROW_H)
        r:SetPoint("TOPLEFT", 14, -66 - (i - 1) * ROW_H)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.08)
        r.slot = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.slot:SetPoint("LEFT", 0, 0); r.slot:SetWidth(62); r.slot:SetJustifyH("LEFT")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 64, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 88, 0); r.name:SetWidth(190); r.name:SetJustifyH("LEFT")
        r.src = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.src:SetPoint("LEFT", 282, 0); r.src:SetWidth(220); r.src:SetJustifyH("LEFT")
        r.state = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.state:SetPoint("RIGHT", -2, 0); r.state:SetWidth(66); r.state:SetJustifyH("RIGHT")
        for _, fs in ipairs({ r.name, r.src }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
        r:RegisterForClicks("LeftButtonUp")
        r:SetScript("OnClick", function(self, btn) BC.Click(self.r, btn) end)
        r:SetScript("OnEnter", tip)
        r:SetScript("OnLeave", untip)
        rows[i] = r
    end
    nextHead = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextHead:SetText("Where next?")
    nextRows = {}
    BC._nextRows = nextRows
    for i = 1, NEXT_ROWS do
        local b = CreateFrame("Button", nil, win)
        b:SetSize(W - 28, 18)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.08)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 4, 0); b.text:SetWidth(W - 40); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self) BC.ClickNext(self.g) end)
        nextRows[i] = b
    end
    noteFs = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noteFs:SetWidth(W - 28); noteFs:SetJustifyH("LEFT")
    noteFs:SetTextColor(0.5, 0.9, 0.5)
    win:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    win:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    win:RegisterEvent("BAG_UPDATE_DELAYED")
    win:RegisterEvent("PLAYER_LEVEL_UP")
    local pending = false
    win:SetScript("OnEvent", function()
        if not win:IsShown() or pending then return end
        pending = true
        C_Timer.After(0.3, function() pending = false; if win:IsShown() then BC:Render() end end)
    end)
    win:Hide()
end

local STATE = {
    worn = { "worn", 0.25, 0.88, 0.38 },
    bags = { "in bags", 1, 0.82, 0 },
}
local function qualityColor(q)
    local c = ITEM_QUALITY_COLORS and q and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 0.4, 0.6, 1
end

function BC:Render()
    if not win then return end
    local class = myClass()
    local specs = BC.Specs(class)
    local cur = BC.Current()
    local kind = BC.ListKind()
    local level = myLevel()
    local isHorde = horde()
    local list = BC.Rows(cur, kind, isHorde)
    view = { spec = cur and cur.key, list = kind, rows = {}, next = {}, note = note }
    BC._view = view
    local detected = BC.Detect()
    for i, b in ipairs(specBtns) do
        local s = specs[i]
        if s then
            b.key = s.key
            local txt = s.name .. ((detected and detected.key == s.key) and " *" or "")
            b:SetText(txt)
            if s.key == (cur and cur.key) then b:LockHighlight() else b:UnlockHighlight() end
            b:Show()
        else
            b.key = nil
            b:Hide()
        end
    end
    if kind == "B" then listBtns[1]:LockHighlight(); listBtns[2]:UnlockHighlight()
    else listBtns[2]:LockHighlight(); listBtns[1]:UnlockHighlight() end
    local have = 0
    for i = 1, MAX_ROWS do
        local f, r = rows[i], list[i]
        if r then
            f.r = r
            local info = itemInfo(r.id)
            if not info then request(r.id) end
            f.slot:SetText(r.label)
            f.icon:SetTexture(iconOf(r.id))
            f.name:SetText(info and info.name or "...")
            f.name:SetTextColor(qualityColor(info and info.quality or 3))
            f.src:SetText(r.source)
            f.src:SetTextColor(0.62, 0.62, 0.62)
            local st = STATE[r.status]
            local stText
            if st then
                stText = st[1]; f.state:SetTextColor(st[2], st[3], st[4]); have = have + 1
            elseif r.level and r.level > level then
                stText = "level " .. r.level; f.state:SetTextColor(0.75, 0.45, 0.3)
            else
                stText = ""; f.state:SetTextColor(1, 1, 1)
            end
            f.state:SetText(stText)
            f:Show()
            view.rows[#view.rows + 1] = { slot = r.slot, id = r.id, name = info and info.name, source = r.source,
                status = r.status, state = stText }
        else
            f.r = nil
            f:Hide()
        end
    end
    local n = math.min(#list, MAX_ROWS)
    view.have, view.total = have, n
    view.sub = cur and string.format("%s %s - %d of %d items", cur.name, (kind == "B") and "Pre-Raid BiS" or "Realistic", have, n)
        or "No BiS list for your class."
    sub:SetText(view.sub)
    local y = -66 - n * ROW_H - 8
    nextHead:ClearAllPoints()
    nextHead:SetPoint("TOPLEFT", 14, y)
    y = y - 18
    local groups = BC.WhereNext(list, level)
    BC._groups = groups
    local shown = 0
    for i = 1, NEXT_ROWS do
        local b, g = nextRows[i], groups[i]
        if g then
            b.g = g
            local when = g.now and "|cff40e060now|r" or ("|cffc07050from level " .. g.level .. "|r")
            local txt = string.format("%s - %d item%s (%s)", g.label, g.n, g.n == 1 and "" or "s", when)
            b.text:SetText(txt)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 14, y)
            y = y - 18
            b:Show()
            shown = shown + 1
            view.next[#view.next + 1] = txt
        else
            b.g = nil
            b:Hide()
        end
    end
    if shown == 0 then
        nextHead:SetText("Where next? |cff40e060Nothing missing - well done!|r")
    else
        nextHead:SetText("Where next?")
    end
    noteFs:ClearAllPoints()
    noteFs:SetPoint("TOPLEFT", 14, y - 4)
    noteFs:SetText(note)
    if note ~= "" then y = y - 20 end
    win:SetHeight(-y + 14)
end

function BC:Open()
    if not win then build() end
    note = ""
    win:Show()
    BC:Render()
end
function BC:Close() if win then win:Hide() end end
function BC:IsOpen() return win and win:IsShown() and true or false end
function BC:Toggle() if BC:IsOpen() then BC:Close() else BC:Open() end end

OMQ:RegisterCommand("bis", function() BC:Toggle() end, "BiS Check: the pre-raid BiS items of your spec and where to get them")
