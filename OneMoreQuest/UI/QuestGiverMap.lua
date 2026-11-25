-- One More Quest: quest givers on the world map (decision 697)
--   A small "!" button at the top right of the world map switches it on and off (default off; also in the
--   options, Guidance, and /omq givers [on|off]). While on, every quest giver of the zone shown on the map gets
--   a yellow "!" - but only for quests I can take now: required level, faction, race, class, pre-quests done,
--   not done, not in the log, no excluding quest done, the giver talks to me. Left out: grey quests, repeatable
--   quests, quests for a profession or reputation and quests that start from an item (no giver).
--   Continent and world maps get no marks (too many). Quests at the same giver share one mark.
--   Hover: every quest of the giver with its level, the XP (lowered like the game does when I am far above the
--   quest) and the item rewards (choices marked); Shift shows the game's tooltips of the first reward items.
--   Left click: the arrow points to the giver. Right click: the mark goes until the map is opened again.
--   No taint: own plain buttons on an own layer over the map canvas, like UI/MapMarkers.lua (decision 596).
--   Rewards: Data/QuestRewardInfo.lua (Factoruide). Quest names: the client's language when the game knows the
--   quest (it is asked to load it), else the English name of the data.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local Q = {}
OMQ.QuestGiverMap = Q

Q.SIZE = 20                 -- a mark on the map
Q.LEVEL = 1900              -- frame levels above the canvas: over Blizzard's pins, under the run markers (2000)
Q.GROUP = 0.6               -- map %: givers this close share one mark (the same NPC)
Q.REFRESH = 1               -- seconds between two looks at the log while the map is open and something changed
Q.ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
Q.SHOP = 2                  -- Shift: the game tooltips of this many reward items
-- XP when I am above the quest: 6 levels 80 %, 7: 60 %, 8: 40 %, 9: 20 %, 10 and more 10 % (the classic rule)
Q.XP_CUT = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }

local isSecret = function(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not isSecret(v) end
local function has(flags, b) return flags ~= nil and math.floor(flags / b) % 2 == 1 end
local function data(id) return OMQ.QuestPlaces and OMQ.QuestPlaces[id] end
local function NQ() return OMQ.NextQuest end
local function now() return GetTime and GetTime() or 0 end

local layer, button, pins = nil, nil, {}
local list = {}             -- the marks of the shown map: { key, x, y, quests = { id } }
local hidden = {}           -- [key] = true: right clicked away until the map opens again
local lastMap, lastScale, lastW, lastH = nil, nil, nil, nil
local dirty, lastLook = true, -1
local tipPin = nil          -- the mark whose tooltip is open (names and items load later)

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
local function gdb() return OMQ.db and OMQ.db.guide or {} end
function Q.Enabled() return gdb().questGivers == true end
function Q.SetEnabled(on)
    if OMQ.db and OMQ.db.guide then OMQ.db.guide.questGivers = on and true or false end
    hidden = {}
    Q.Update()
    Q.Refresh(true)
end
function Q.Toggle() Q.SetEnabled(not Q.Enabled()) end

----------------------------------------------------------------------
-- Which quests
----------------------------------------------------------------------
local function contains(l, v)
    for _, x in ipairs(l or {}) do if x == v then return true end end
    return false
end
local function everDone(id) return NQ() and NQ().EverDone and NQ().EverDone(id) or false end
local function myLog()
    if OMQ.QuestSync and OMQ.QuestSync.ReadLog then
        local ok, log = pcall(OMQ.QuestSync.ReadLog, OMQ.QuestSync)
        if ok and type(log) == "table" then return log end
    end
    return {}
end
function Q.Me() return NQ().Me() end

-- may I take this quest now, from its giver? (who = NextQuest.Me(), log = { [id] = true })
function Q.Takeable(id, who, log)
    local d = data(id)
    if not (d and d[7]) then return false end
    if has(d[13], 1) or has(d[13], 2) or has(d[13], 4) then return false end
    if (log and log[id]) or everDone(id) then return false end
    if (d[2] or 0) > who.level then return false end
    local ql = d[3] or 0
    if ql > 0 and ql < NQ().GreyBelow(who.level) then return false end                -- grey (MadDadVibe: left out)
    if d[4] and who.fac and d[4] ~= who.fac then return false end
    if d[5] and who.race and not contains(d[5], who.race) then return false end
    if d[6] and who.class and not contains(d[6], who.class) then return false end
    for _, p in ipairs(d[10] or {}) do if not everDone(p) then return false end end
    if d[11] and #d[11] > 0 then
        local any = false
        for _, p in ipairs(d[11]) do if everDone(p) then any = true; break end end
        if not any then return false end
    end
    for _, p in ipairs(d[12] or {}) do if everDone(p) or (log and log[p]) then return false end end
    local A = OMQ.AreaRun
    if A and A.Unfriendly and A.Unfriendly(id) == "giver" then return false end     -- will not talk to me (649)
    return true
end

-- a zone, a city or a dungeon map (no continent, no world)
function Q.MapOK(map)
    if not num(map) then return false end
    if not (C_Map and C_Map.GetMapInfo) then return true end
    local ok, info = pcall(C_Map.GetMapInfo, map)
    if not (ok and type(info) == "table" and num(info.mapType)) then return true end
    return info.mapType >= 3
end

local function level(id) local d = data(id); return d and d[3] or 0 end

-- the marks of a map: givers of takeable quests whose place lies on it
function Q.Collect(map)
    local out = {}
    if not (Q.Enabled() and OMQ:Master("guidance") and Q.MapOK(map)) then return out end
    local who, log = Q.Me(), myLog()
    local byKey = {}
    for id, d in pairs(OMQ.QuestPlaces or {}) do
        if d[7] then
            local can
            for _, s in ipairs(d[7]) do
                if s[1] == map then
                    if can == nil then can = Q.Takeable(id, who, log) end
                    if not can then break end
                    local key = string.format("%d:%d", math.floor(s[2] / Q.GROUP + 0.5), math.floor(s[3] / Q.GROUP + 0.5))
                    local m = byKey[key]
                    if not m then
                        m = { key = key, x = s[2] / 100, y = s[3] / 100, spot = s, quests = {} }
                        byKey[key] = m
                        out[#out + 1] = m
                    end
                    if not contains(m.quests, id) then m.quests[#m.quests + 1] = id end
                end
            end
        end
    end
    for _, m in ipairs(out) do
        table.sort(m.quests, function(a, b)
            if level(a) ~= level(b) then return level(a) < level(b) end
            return a < b
        end)
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

----------------------------------------------------------------------
-- Names and rewards
----------------------------------------------------------------------
local asked = {}
function Q.Title(id)
    local CQ = C_QuestLog
    if CQ and CQ.GetTitleForQuestID then
        local ok, t = pcall(CQ.GetTitleForQuestID, id)
        if ok and type(t) == "string" and t ~= "" and not isSecret(t) then return t end
        if CQ.RequestLoadQuestByID and not asked[id] then
            asked[id] = true
            pcall(CQ.RequestLoadQuestByID, id)
        end
    end
    local d = data(id)
    return d and d[1] or ("quest " .. id)
end

-- the XP I get: lowered when I am 6 or more levels above the quest, none at the highest level
function Q.XP(full, ql, lvl)
    if not (num(full) and full > 0) then return nil end
    local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if not num(max) then max = 60 end
    if lvl >= max then return nil end
    local diff = lvl - (ql or 0)
    local f = 1
    if diff >= 10 then f = 0.1 elseif Q.XP_CUT[diff] then f = Q.XP_CUT[diff] end
    local v = full * f
    if f < 1 then v = math.floor(v / 5 + 0.5) * 5 end
    return math.floor(v + 0.5)
end

-- { xp, fixed = { { id, n } }, choice = { { id, n } } }
function Q.Rewards(id)
    local r = OMQ.QuestRewardInfo and OMQ.QuestRewardInfo[id]
    local out = { fixed = {}, choice = {} }
    if not r then return out end
    out.full = r[1]
    local who = Q.Me()
    out.xp = Q.XP(r[1], level(id), who.level)
    for i, key in ipairs({ "fixed", "choice" }) do
        for _, it in ipairs(r[i + 1] or {}) do
            if type(it) == "table" then out[key][#out[key] + 1] = { it[1], it[2] }
            else out[key][#out[key] + 1] = { it, 1 } end
        end
    end
    return out
end

-- name, quality, icon of an item; asks the game to load it when it does not know it yet
function Q.Item(id)
    local name, q, icon
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if info then
        local ok, n, _, qq, _, _, _, _, _, _, ic = pcall(info, id)
        if ok and type(n) == "string" and not isSecret(n) then name, q, icon = n, qq, ic end
    end
    if not icon and C_Item and C_Item.GetItemIconByID then
        local ok, ic = pcall(C_Item.GetItemIconByID, id)
        if ok then icon = ic end
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return name, q, icon
end

local function itemLine(it)
    local name, q, icon = Q.Item(it[1])
    local c = { 1, 1, 1 }
    if num(q) and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local qc = ITEM_QUALITY_COLORS[q]
        c = { qc.r or 1, qc.g or 1, qc.b or 1 }
    end
    local text = (icon and ("|T" .. tostring(icon) .. ":14:14|t ") or "") .. (name or ("item " .. it[1]))
    if it[2] and it[2] > 1 then text = text .. " x" .. it[2] end
    return text, c
end

-- the tooltip lines of one mark: { text, r, g, b }
function Q.Lines(m)
    local out = {}
    local who = Q.Me()
    for i, id in ipairs(m.quests) do
        if i > 1 then out[#out + 1] = { " " } end
        local ql = level(id)
        local qc = (GetQuestDifficultyColor and ql > 0) and GetQuestDifficultyColor(ql) or nil
        local r, g, b = 1, 0.82, 0
        if type(qc) == "table" and num(qc.r) then r, g, b = qc.r, qc.g, qc.b end
        out[#out + 1] = { string.format("[%d] %s", ql, Q.Title(id)), r, g, b }
        local rw = Q.Rewards(id)
        if rw.xp then out[#out + 1] = { string.format("%d XP", rw.xp), 0.6, 0.6, 1 } end
        for _, it in ipairs(rw.fixed) do
            local t, c = itemLine(it)
            out[#out + 1] = { "  " .. t, c[1], c[2], c[3] }
        end
        if #rw.choice > 0 then
            out[#out + 1] = { "  Choose one:", 0.8, 0.8, 0.8 }
            for _, it in ipairs(rw.choice) do
                local t, c = itemLine(it)
                out[#out + 1] = { "    " .. t, c[1], c[2], c[3] }
            end
        end
        if not rw.xp and #rw.fixed == 0 and #rw.choice == 0 then
            out[#out + 1] = { (rw.full and who.level >= ((GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60))
                and "  no XP at your level" or "  no item reward known", 0.6, 0.6, 0.6 }
        end
    end
    return out
end

-- the first reward items of a mark (for the Shift tooltips)
function Q.FirstItems(m, n)
    local out = {}
    for _, id in ipairs(m.quests) do
        local rw = Q.Rewards(id)
        for _, key in ipairs({ "fixed", "choice" }) do
            for _, it in ipairs(rw[key]) do
                if #out >= n then return out end
                out[#out + 1] = it[1]
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Clicks and tooltip
----------------------------------------------------------------------
function Q.Go(m)
    local G = OMQ.Guide
    if not (m and G and G.StartAt) then return false end
    local w = NQ().World(m.spot)
    if not w then return false end
    G:StartAt("Quest giver: " .. Q.Title(m.quests[1]), w[1], w[2], w[3], "giver", nil, { radius = 10 })
    return true
end
function Q.Remove(m)
    if not m then return end
    hidden[m.key] = true
    Q.Place()
end

local function hideShop()
    for i = 1, Q.SHOP do
        local t = _G["ShoppingTooltip" .. i]
        if t and t.Hide then t:Hide() end
    end
end
local function showShop(owner)
    hideShop()
    if not (IsShiftKeyDown and IsShiftKeyDown()) then return 0 end
    local prev, n = owner, 0
    for i, id in ipairs(Q.FirstItems(tipPin.m, Q.SHOP)) do
        local t = _G["ShoppingTooltip" .. i]
        if t and t.SetOwner and t.SetItemByID then
            t:SetOwner(owner, "ANCHOR_NONE")
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", prev, "TOPRIGHT", 2, 0)
            t:SetItemByID(id)
            t:Show()
            prev, n = t, n + 1
        end
    end
    return n
end

function Q.Tooltip(pin)
    local m = pin and pin.m
    if not (m and GameTooltip) then return end
    tipPin = pin
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(#m.quests > 1 and string.format("Quest giver (%d quests)", #m.quests) or "Quest giver", 1, 0.82, 0)
    for _, l in ipairs(Q.Lines(m)) do GameTooltip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1) end
    GameTooltip:AddLine("Left click: arrow there  -  Right click: remove mark  -  Shift: item tooltips", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
    showShop(GameTooltip)
end
local function leave()
    tipPin = nil
    hideShop()
    if GameTooltip then GameTooltip:Hide() end
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------
local function mapFrame() return _G.WorldMapFrame end

local function newPin()
    local b = CreateFrame("Button", nil, layer)
    b:SetSize(Q.SIZE, Q.SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints()
    b.icon:SetTexture(Q.ICON)
    b:SetScript("OnClick", function(self, which)
        if which == "RightButton" then Q.Remove(self.m) else Q.Go(self.m) end
        leave()
    end)
    b:SetScript("OnEnter", Q.Tooltip)
    b:SetScript("OnLeave", leave)
    return b
end

function Q.Place()
    local wm = mapFrame()
    if not (layer and wm) then return 0 end
    local canvas = wm.GetCanvas and wm:GetCanvas()
    local map = wm.GetMapID and wm:GetMapID()
    local cs = wm.GetCanvasScale and wm:GetCanvasScale()
    local w, h = canvas and canvas:GetWidth(), canvas and canvas:GetHeight()
    local shown = 0
    if canvas and num(w) and num(h) and w > 0 and h > 0 then
        local scale = 1 / ((num(cs) and cs > 0) and cs or 1)
        for _, m in ipairs(list) do
            if not hidden[m.key] then
                shown = shown + 1
                local pin = pins[shown] or newPin()
                pins[shown] = pin
                pin.m = m
                pin:SetFrameLevel((layer:GetFrameLevel() or 1) + 1)
                pin:SetScale(scale)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", w * m.x / scale, -h * m.y / scale)
                pin:Show()
            end
        end
    end
    for i = shown + 1, #pins do pins[i]:Hide(); pins[i].m = nil end
    lastMap, lastScale, lastW, lastH = map, cs, w, h
    return shown
end

-- a new look (force: at once; else only when something changed, at most every Q.REFRESH seconds)
function Q.Refresh(force)
    if not layer then return end
    local t = now()
    if not force and (not dirty or t - lastLook < Q.REFRESH) then return end
    lastLook, dirty = t, false
    local wm = mapFrame()
    list = Q.Collect(wm and wm.GetMapID and wm:GetMapID())
    Q.Place()
end

-- the button's look: bright when on
function Q.Update()
    if not button then return end
    local on = Q.Enabled()
    if button.icon.SetDesaturated then button.icon:SetDesaturated(not on) end
    button.icon:SetAlpha(on and 1 or 0.6)
end

local function onUpdate()
    local wm = mapFrame()
    if not (wm and wm.IsShown and wm:IsShown()) then return end
    local canvas = wm.GetCanvas and wm:GetCanvas()
    local map, cs = wm.GetMapID and wm:GetMapID(), wm.GetCanvasScale and wm:GetCanvasScale()
    local w, h = canvas and canvas:GetWidth(), canvas and canvas:GetHeight()
    if map ~= lastMap then Q.Refresh(true)
    elseif cs ~= lastScale or w ~= lastW or h ~= lastH then Q.Place()
    else Q.Refresh(false) end
end

local function buttonTip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Quest givers: " .. (Q.Enabled() and "on" or "off"), 1, 0.82, 0)
    GameTooltip:AddLine("Shows the quest givers of this zone with quests you can take now.", 1, 1, 1, true)
    GameTooltip:Show()
end

function Q.Attach()
    if layer then return true end
    local wm = mapFrame()
    local canvas = wm and wm.GetCanvas and wm:GetCanvas()
    if not canvas then return false end
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel((canvas:GetFrameLevel() or 1) + Q.LEVEL)
    layer:SetScript("OnUpdate", onUpdate)
    local host = wm.ScrollContainer or wm
    button = CreateFrame("Button", "OMQQuestGiverMapButton", host)
    button:SetSize(26, 26)
    button:SetPoint("TOPRIGHT", host, "TOPRIGHT", -40, -4)
    button:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 1) + Q.LEVEL + 20)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    button.bg:SetVertexColor(0.08, 0.086, 0.114, 0.85)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3); button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexture(Q.ICON)
    button:SetScript("OnClick", function(self) Q.Toggle(); buttonTip(self) end)
    button:SetScript("OnEnter", buttonTip)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Q.Update()
    if wm.HookScript then
        wm:HookScript("OnShow", function() hidden = {}; Q.Refresh(true) end)
    end
    Q.Refresh(true)
    return true
end

function Q.List() return list end
function Q.Pins() return pins end
function Q.Button() return button end
function Q.MarkDirty() dirty = true end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE",
                     "QUEST_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "MODIFIER_STATE_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, name)
    if e == "ADDON_LOADED" then
        if name == "Blizzard_WorldMap" then Q.Attach() end
    elseif e == "QUEST_DATA_LOAD_RESULT" or e == "GET_ITEM_INFO_RECEIVED" or e == "MODIFIER_STATE_CHANGED" then
        if tipPin and tipPin.IsShown and tipPin:IsShown() then Q.Tooltip(tipPin) end   -- a name came in, Shift
    else
        dirty = true
    end
end)
OMQ:On("READY", function() Q.Attach() end)

OMQ:RegisterCommand("givers", function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        Q.SetEnabled(arg == "on")
        OMQ:Print("quest givers on the map " .. arg)
        return
    end
    Q.Attach()
    local wm = mapFrame()
    local map = wm and wm.GetMapID and wm:GetMapID()
    if not num(map) and C_Map and C_Map.GetBestMapForUnit then map = C_Map.GetBestMapForUnit("player") end
    local was = OMQ.db and OMQ.db.guide and OMQ.db.guide.questGivers
    if OMQ.db and OMQ.db.guide then OMQ.db.guide.questGivers = true end
    local l = Q.Collect(map)
    if OMQ.db and OMQ.db.guide then OMQ.db.guide.questGivers = was end
    local out = { "Quest givers on the map: " .. (Q.Enabled() and "on" or "off") .. ", map " .. tostring(map) ..
                  (Q.MapOK(map) and "" or " (continent/world: no marks)") }
    for _, m in ipairs(l) do
        local names = {}
        for _, id in ipairs(m.quests) do names[#names + 1] = string.format("%s (%d)", Q.Title(id), id) end
        out[#out + 1] = string.format("%.1f %.1f  %s", m.x * 100, m.y * 100, table.concat(names, ", "))
    end
    if #l == 0 then out[#out + 1] = "no quest you can take on this map" end
    OMQ:ShowReport(out)
end, "quest givers of the zone on the world map: /omq givers [on|off]")
