-- One More Quest: Progress Check, the milestone timeline (decision 184)
-- Only for the player himself, nothing is sent to the group. Opens in the middle of the screen
-- from the Progress Check icon in the check bar (or /omq progress). A window of 16 levels, 5 back
-- and 10 ahead, opens on the own level; it scrolls with the mouse wheel and the arrows.
-- Class milestones above the line, dungeons (their lowest level) below it.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local MS = {}
OMQ.Milestones = MS

local VIEW = 16                       -- levels in the window
local MAX_OFF = 60 - VIEW
local W = 62.5                        -- pixels per level
local VIEW_W = VIEW * W               -- 1000
local VIEW_H = 214
local AXIS_Y = -104                   -- the line, from the top of the track
local LABEL_W = 120                   -- two levels apart the labels of both rows do not touch
-- quest zones below the dungeons (decision 296): one bar per zone from its lowest to its highest level
local ZONE_Y = -214                   -- top of the zone band, from the top of the track
local ZONE_ROW, ZONE_BAR = 17, 14
MS.VIEW, MS.MAX_OFF, MS.W = VIEW, MAX_OFF, W
MS.DUNGEON_SHIFT = 3

local GOLD = { 0.89, 0.71, 0.29 }
local GOLD_LIGHT = { 0.95, 0.82, 0.48 }
local GREY = { 0.54, 0.56, 0.61 }

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
-- the name of one entry: from the game in the language of the client when there is a spell id
function MS.ItemName(m)
    local name = m[2]
    if m.spell and GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, m.spell)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    if m.rank then name = name .. " (rank " .. m.rank .. ")" end
    if m.quest then name = name .. " (class quest)" end
    return name
end

-- the label on the track: at most two names, the rest as "+n"
function MS.Short(names)
    if #names <= 1 then return names[1] or "" end
    if #names == 2 then return names[1] .. ", " .. names[2] end
    return names[1] .. ", " .. names[2] .. " +" .. (#names - 2)
end

-- milestones of a class, sorted; several on one level become one pin (class entries first)
function MS.ForClass(class)
    local data = OMQ.MilestoneData or {}
    local byLevel = {}
    local function add(list)
        for _, m in ipairs(list or {}) do
            local l, icon = m[1], m[3]
            local item = { name = MS.ItemName(m), tip = m.tip }
            local e = byLevel[l]
            if not e then byLevel[l] = { level = l, names = { item.name }, items = { item }, icon = icon }
            else
                e.names[#e.names + 1] = item.name
                e.items[#e.items + 1] = item
            end
        end
    end
    add(data[class])
    add(data.ALL)
    local out = {}
    for _, e in pairs(byLevel) do
        e.name = table.concat(e.names, ", ")
        e.short = MS.Short(e.names)
        out[#out + 1] = e
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end

-- the longest wait between two milestones up to a level (decision 196: below 10 up to 40)
function MS.LongestGap(list, upTo)
    local prev, gap = 1, 0
    for _, m in ipairs(list) do
        if m.level > upTo then break end
        gap = math.max(gap, m.level - prev)
        prev = m.level
    end
    return gap
end

function MS.Dungeons()
    local out = {}
    -- shown 3 levels above the lowest level of the dungeon finder: then a dungeon is really doable (decision 188)
    for _, d in ipairs(OMQ.Dungeons or {}) do out[#out + 1] = { level = math.min(60, d.min + MS.DUNGEON_SHIFT), abbr = d.abbr, name = d.name } end
    table.sort(out, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.abbr < b.abbr end)
    return out
end

function MS.Next(list, level)
    for _, m in ipairs(list) do if m.level > level then return m end end
end

-- the window: 5 levels back, 10 ahead
function MS.HomeOffset(level)
    return math.max(0, math.min(MAX_OFF, (level or 1) - 6))
end

function MS.X(level) return (level - 1) * W + W / 2 end

-- the quest zones are hidden until the dad shows them (decision 302)
function MS.ZonesShown()
    local o = OMQ.db and OMQ.db.options
    return (o and o.journeyZones) and true or false
end
function MS.SetZonesShown(v)
    if OMQ.db and OMQ.db.options then OMQ.db.options.journeyZones = v and true or false end
end

-- zone bars in rows: the first row whose last bar ends before this one starts
function MS.ZoneRows(zones)
    local sorted = {}
    for i, z in ipairs(zones) do sorted[i] = z end
    table.sort(sorted, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[3] < b[3] end)
    local lastEnd, rowOf, n = {}, {}, 0
    for _, z in ipairs(sorted) do
        local row
        for r = 1, n do if lastEnd[r] < z[2] then row = r; break end end
        if not row then n = n + 1; row = n end
        lastEnd[row] = z[3]
        rowOf[z] = row
    end
    return sorted, rowOf, n
end

-- labels in two rows above the line (dungeons: four rows below), the first row that is free
function MS.Rows(xs, width, rows)
    local lastRight, out = {}, {}
    for i, x in ipairs(xs) do
        local row = rows
        for r = 1, rows do
            if not lastRight[r] or x - width / 2 >= lastRight[r] + 4 then row = r; break end
        end
        lastRight[row] = x + width / 2
        out[i] = row
    end
    return out
end

local function levelAndXP()
    local level = UnitLevel and UnitLevel("player") or 1
    local cur, max = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 1
    local pct = (type(cur) == "number" and type(max) == "number" and max > 0) and math.floor(cur / max * 100) or 0
    return level, pct
end
MS.LevelAndXP = levelAndXP

----------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------
local f, view, track
local offset, scroll = 0, 0
local list, built
local pool, kindOf = {}, {}      -- the regions on the track, reused on every opening
local tipOf = {}                 -- medallion -> its milestone, for the tooltip

local function edge(parent, c, inset)
    for i = 1, 4 do
        local e = parent:CreateTexture(nil, "BORDER")
        e:SetColorTexture(c[1], c[2], c[3], 1)
        if i == 1 then e:SetPoint("TOPLEFT", inset, -inset); e:SetPoint("TOPRIGHT", -inset, -inset); e:SetHeight(1)
        elseif i == 2 then e:SetPoint("BOTTOMLEFT", inset, inset); e:SetPoint("BOTTOMRIGHT", -inset, inset); e:SetHeight(1)
        elseif i == 3 then e:SetPoint("TOPLEFT", inset, -inset); e:SetPoint("BOTTOMLEFT", inset, inset); e:SetWidth(1)
        else e:SetPoint("TOPRIGHT", -inset, -inset); e:SetPoint("BOTTOMRIGHT", -inset, inset); e:SetWidth(1) end
    end
end

local function text(parent, template, c, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function medallion(parent, size)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(size, size)
    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    m.bg:SetSize(size * 0.72, size * 0.72)
    m.bg:SetPoint("TOPLEFT", size * 0.17, -size * 0.14)
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetSize(size * 0.66, size * 0.66)
    m.icon:SetPoint("TOPLEFT", size * 0.19, -size * 0.17)
    if m.icon.SetMask then pcall(m.icon.SetMask, m.icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    m.ring = m:CreateTexture(nil, "OVERLAY")
    m.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    m.ring:SetSize(size * 1.72, size * 1.72)
    m.ring:SetPoint("TOPLEFT", 0, 0)
    m.glow = m:CreateTexture(nil, "OVERLAY")
    m.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    if m.glow.SetBlendMode then m.glow:SetBlendMode("ADD") end
    m.glow:SetSize(size * 2, size * 2)
    m.glow:SetPoint("CENTER", m, "CENTER", 1, -1)
    m.glow:Hide()
    -- the tooltip lists everything of the level with a short text
    m:EnableMouse(true)
    m:SetScript("OnEnter", function(self)
        local ms = tipOf[self]
        if not ms or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Level " .. ms.level, GOLD[1], GOLD[2], GOLD[3])
        for _, it in ipairs(ms.items or {}) do
            GameTooltip:AddLine(it.name, 1, 1, 1)
            if it.tip then GameTooltip:AddLine(it.tip, 0.66, 0.69, 0.73, true) end
        end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return m
end

local function setOffset(o)
    offset = math.max(0, math.min(MAX_OFF, math.floor((o or 0) + 0.5)))
    if f then f.range:SetText(string.format("Levels %d to %d of 60 - mouse wheel or arrows to scroll", offset + 1, offset + VIEW)) end
end
MS.SetOffset = function(_, o) setOffset(o) end
function MS:Offset() return offset end

local function buildTrack()
    for _, it in ipairs(pool) do it:Hide() end
    local used = 0
    local function region(kind, make)
        used = used + 1
        local r = pool[used]
        if not r or kindOf[r] ~= kind then r = make(); kindOf[r] = kind; pool[used] = r end
        r:Show()
        return r
    end
    local level, pct = levelAndXP()
    local pos = (level >= 60) and MS.X(60) or (MS.X(level) + pct / 100 * W)

    -- the line and how far I am
    local line = region("line", function() local t = track:CreateTexture(nil, "BACKGROUND"); return t end)
    line:SetColorTexture(0.15, 0.16, 0.2, 1)
    line:ClearAllPoints(); line:SetPoint("TOPLEFT", 0, AXIS_Y + 3); line:SetSize(60 * W, 6)
    local done = region("line", function() local t = track:CreateTexture(nil, "BORDER"); return t end)
    done:SetColorTexture(0.79, 0.64, 0.29, 1)
    done:ClearAllPoints(); done:SetPoint("TOPLEFT", 0, AXIS_Y + 3); done:SetSize(math.max(1, pos), 6)

    -- level ticks
    for n = 1, 60 do
        local big = (n % 10 == 0) or n == 1
        local reached = n <= level
        local t = region("tick", function() return track:CreateTexture(nil, "ARTWORK") end)
        local c = reached and { 0.79, 0.64, 0.29 } or (big and { 0.66, 0.69, 0.73 } or { 0.35, 0.38, 0.42 })
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", MS.X(n), AXIS_Y + (big and 10 or 7)); t:SetSize(1, big and 20 or 14)
        local lbl = region("num", function() return text(track, "GameFontHighlightSmall", nil, "CENTER") end)
        lbl:SetFontObject(big and "GameFontNormal" or "GameFontHighlightSmall")
        lbl:SetTextColor(c[1], c[2], c[3])
        lbl:ClearAllPoints(); lbl:SetPoint("TOP", track, "TOPLEFT", MS.X(n), AXIS_Y - 14)
        lbl:SetText(n)
    end

    -- milestones above the line
    local _, class = UnitClass("player")
    list = MS.ForClass(class)
    local nextM = MS.Next(list, level)
    local xs = {}
    for i, m in ipairs(list) do xs[i] = MS.X(m.level) end
    local rows = MS.Rows(xs, LABEL_W, 2)
    for i, m in ipairs(list) do
        local x = MS.X(m.level)
        local reached = m.level <= level
        local isNext = (m == nextM)
        local med = region("medal", function() return medallion(track, 30) end)
        med:ClearAllPoints(); med:SetPoint("CENTER", track, "TOPLEFT", x, AXIS_Y)
        med.icon:SetTexture(m.icon)
        if med.icon.SetDesaturated then med.icon:SetDesaturated(reached) end
        med:SetAlpha(reached and 0.65 or 1)
        if isNext then med.glow:Show() else med.glow:Hide() end
        local stemTop = (rows[i] == 1) and -46 or -80
        local stem = region("stem", function() return track:CreateTexture(nil, "BACKGROUND") end)
        stem:SetColorTexture(reached and 0.55 or 0.23, reached and 0.43 or 0.25, reached and 0.17 or 0.29, 1)
        stem:ClearAllPoints(); stem:SetPoint("TOPLEFT", x - 1, stemTop); stem:SetSize(2, -(AXIS_Y + 15) + stemTop)
        local head = region("head", function() return text(track, "GameFontNormalSmall", nil, "CENTER") end)
        head:ClearAllPoints(); head:SetPoint("TOP", track, "TOPLEFT", x, (rows[i] == 1) and -4 or -38)
        head:SetText("LEVEL " .. m.level .. (reached and "  |cff7dd070done|r" or ""))
        head:SetTextColor((reached and GREY or GOLD)[1], (reached and GREY or GOLD)[2], (reached and GREY or GOLD)[3])
        local name = region("name", function()
            local fs = text(track, "GameFontHighlightSmall", nil, "CENTER"); fs:SetWidth(LABEL_W)
            if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, 2) end
            return fs
        end)
        name:ClearAllPoints(); name:SetPoint("TOP", head, "BOTTOM", 0, -2)
        name:SetText(m.short or m.name)
        tipOf[med] = m
        local c = reached and GREY or (isNext and GOLD_LIGHT or { 0.93, 0.92, 0.89 })
        name:SetTextColor(c[1], c[2], c[3])
    end

    -- dungeons below the line
    local dl = MS.Dungeons()
    local dxs = {}
    for i, d in ipairs(dl) do dxs[i] = MS.X(d.level) end
    local drows = MS.Rows(dxs, 44, 4)
    for i, d in ipairs(dl) do
        local lbl = region("dun", function() return text(track, "GameFontHighlightSmall", nil, "CENTER") end)
        lbl:ClearAllPoints(); lbl:SetPoint("TOP", track, "TOPLEFT", dxs[i], AXIS_Y - 34 - (drows[i] - 1) * 16)
        local open = d.level <= level
        lbl:SetText(d.abbr)
        if open then lbl:SetTextColor(0.62, 0.8, 0.95) else lbl:SetTextColor(0.45, 0.5, 0.58) end
    end

    -- quest zones below the dungeons (decision 296): my faction and the contested ones; a click sends me there.
    -- Hidden by default, the button at the bottom shows them (decision 302).
    local NQ = OMQ.NextQuest
    local showZones = MS.ZonesShown()
    if f.zonesBtn then f.zonesBtn:SetText(showZones and "Hide quest zones" or "Show quest zones") end
    local zones = (showZones and NQ) and NQ.Zones() or {}
    local sorted, rowOf, nRows = MS.ZoneRows(zones)
    local sep = region("line", function() local t = track:CreateTexture(nil, "BACKGROUND"); return t end)
    sep:SetColorTexture(0.2, 0.21, 0.26, 1)
    sep:ClearAllPoints(); sep:SetPoint("TOPLEFT", 0, ZONE_Y + 6); sep:SetSize(60 * W, 1)
    for _, z in ipairs(sorted) do
        local bar = region("zone", function()
            local b = CreateFrame("Button", nil, track)
            b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
            b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.12)
            b.text = text(b, "GameFontHighlightSmall", nil, "CENTER"); b.text:SetPoint("LEFT", 4, 0); b.text:SetPoint("RIGHT", -4, 0)
            if b.text.SetWordWrap then b.text:SetWordWrap(false) end
            b:SetScript("OnClick", function(self) if self.zone and NQ then NQ.GoZone(self.zone) end end)
            b:SetScript("OnEnter", function(self)
                local zz = self.zone
                if not (zz and GameTooltip and NQ) then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(NQ.ZoneName(zz), GOLD[1], GOLD[2], GOLD[3])
                GameTooltip:AddLine(string.format("Level %d-%d%s", zz[2], zz[3], zz[4] == "C" and " - contested" or ""), 1, 1, 1)
                local ok, n = pcall(NQ.ZoneCount, zz)
                if ok then GameTooltip:AddLine(string.format("%d quest%s you can take there now", n, n == 1 and "" or "s"), 0.8, 0.8, 0.8) end
                GameTooltip:AddLine("Click: the arrow to its quest hub", 0.66, 0.69, 0.73)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            return b
        end)
        bar.zone = z
        local x1, x2 = MS.X(z[2]) - W / 2 + 2, MS.X(z[3]) + W / 2 - 2
        bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", track, "TOPLEFT", x1, ZONE_Y - (rowOf[z] - 1) * ZONE_ROW)
        bar:SetSize(x2 - x1, ZONE_BAR)
        local now = z[2] <= level and level <= z[3]
        local past = z[3] < level
        if now then bar.bg:SetColorTexture(0.55, 0.43, 0.17, 0.9); bar.text:SetTextColor(1, 0.92, 0.7)
        elseif past then bar.bg:SetColorTexture(0.16, 0.17, 0.2, 0.9); bar.text:SetTextColor(0.5, 0.52, 0.56)
        else bar.bg:SetColorTexture(0.14, 0.2, 0.28, 0.9); bar.text:SetTextColor(0.62, 0.8, 0.95) end
        bar.text:SetText(NQ.ZoneName(z))
    end
    sep:SetShown(showZones)
    local h = showZones and (-ZONE_Y + nRows * ZONE_ROW + 8) or VIEW_H
    track:SetHeight(h); view:SetHeight(h)
    f:SetHeight(352 + (h - VIEW_H))
    MS._zones = { list = sorted, rows = nRows }

    -- me
    local me = region("me", function() local t = track:CreateTexture(nil, "OVERLAY"); return t end)
    me:SetColorTexture(0.95, 0.82, 0.48, 1)
    me:ClearAllPoints(); me:SetPoint("CENTER", track, "TOPLEFT", pos, AXIS_Y); me:SetSize(13, 13)
    if me.SetRotation then pcall(me.SetRotation, me, math.pi / 4) end
    local you = region("you", function() return text(track, "GameFontNormalSmall", GOLD_LIGHT, "CENTER") end)
    you:ClearAllPoints(); you:SetPoint("BOTTOM", track, "TOPLEFT", pos, AXIS_Y + 10)
    you:SetText("YOU")

    -- header
    local className = UnitClass("player") or "?"
    f.tag:SetText(string.upper(className) .. " - YOUR JOURNEY")
    f.level:SetText(string.format("Level %d  |cffa9afba%d%%|r", level, pct))
    if nextM then
        local d = nextM.level - level
        f.next:SetText(string.format("Level %d: %s (in %d level%s)", nextM.level, nextM.short or nextM.name, d, d == 1 and "" or "s"))
    else
        f.next:SetText("You made it!")
    end
    MS._view = { level = level, pct = pct, next = nextM, list = list, pos = pos }
end

local function build()
    f = CreateFrame("Frame", "OneMoreQuestMilestones", UIParent)
    f:SetSize(VIEW_W + 60, 352)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.075, 0.082, 0.11, 0.97)
    edge(f, { 0.63, 0.50, 0.21 }, 0)
    edge(f, { 0.29, 0.23, 0.10 }, 3)

    f.tag = text(f, "GameFontNormalSmall", { 0.72, 0.63, 0.42 })
    f.tag:SetPoint("TOPLEFT", 30, -18)
    f.level = text(f, "GameFontNormalHuge", GOLD_LIGHT)
    f.level:SetPoint("TOPLEFT", 30, -32)
    f.nextHead = text(f, "GameFontNormalSmall", { 0.72, 0.63, 0.42 }, "RIGHT")
    f.nextHead:SetPoint("TOPRIGHT", -44, -18)
    f.nextHead:SetText("NEXT MILESTONE")
    f.next = text(f, "GameFontHighlight", nil, "RIGHT")
    f.next:SetPoint("TOPRIGHT", -44, -36)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    view = CreateFrame("ScrollFrame", nil, f)
    view:SetSize(VIEW_W, VIEW_H)
    view:SetPoint("TOPLEFT", 30, -68)
    local vbg = view:CreateTexture(nil, "BACKGROUND")
    vbg:SetAllPoints()
    vbg:SetColorTexture(0.06, 0.067, 0.09, 1)
    track = CreateFrame("Frame", nil, view)
    track:SetSize(60 * W, VIEW_H)
    view:SetScrollChild(track)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta) setOffset(offset - (delta or 0) * 2) end)

    -- arrows and the mouse wheel scroll (decision 188: no "Back to me", no bar to drag)
    local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prev:SetSize(36, 24)
    prev:SetPoint("BOTTOMLEFT", 30, 18)
    prev:SetText("<")
    prev:SetScript("OnClick", function() setOffset(offset - 5) end)
    local nxt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nxt:SetSize(36, 24)
    nxt:SetPoint("BOTTOMRIGHT", -30, 18)
    nxt:SetText(">")
    nxt:SetScript("OnClick", function() setOffset(offset + 5) end)
    -- the quest zones on and off (decision 302)
    local zb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    zb:SetSize(130, 24)
    zb:SetPoint("BOTTOMLEFT", 72, 18)
    zb:SetText("Show quest zones")
    zb:SetScript("OnClick", function() MS.SetZonesShown(not MS.ZonesShown()); buildTrack() end)
    f.zonesBtn = zb
    f.range = text(f, "GameFontDisableSmall", GREY, "CENTER")
    f.range:SetPoint("BOTTOM", f, "BOTTOM", 0, 24)

    -- smooth scrolling to the chosen window
    f:SetScript("OnUpdate", function(_, elapsed)
        local target = offset * W
        if math.abs(scroll - target) > 0.5 then
            scroll = scroll + (target - scroll) * math.min(1, (elapsed or 0.016) * 12)
        else
            scroll = target
        end
        if view.SetHorizontalScroll then view:SetHorizontalScroll(scroll) end
    end)
    f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestMilestones") end
    built = true
end

function MS:Show()
    if not built then build() end
    buildTrack()
    local level = levelAndXP()
    setOffset(MS.HomeOffset(level))
    scroll = offset * W
    if view.SetHorizontalScroll then view:SetHorizontalScroll(scroll) end
    f:Show()
end

function MS:Toggle()
    if f and f:IsShown() then f:Hide() else self:Show() end
end
function MS:Frame() return f end
function MS:View() return MS._view end

-- a milestone is reached: a line in the chat and the "done" sound
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, _, newLevel)
    newLevel = tonumber(newLevel)
    if not newLevel then return end
    local _, class = UnitClass("player")
    for _, m in ipairs(MS.ForClass(class)) do
        if m.level == newLevel then
            OMQ:Print("|cffe3b54aMilestone reached:|r " .. m.name)
            if OMQ.Sound then OMQ.Sound:Play("done") end
        end
    end
    if f and f:IsShown() then C_Timer.After(0.5, function() buildTrack() end) end
end)

OMQ:RegisterCommand("progress", function() MS:Toggle() end, "Progress Check: your milestone timeline")
