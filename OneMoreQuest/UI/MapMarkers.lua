-- One More Quest: own markers on the world map (decision 596)
--   Runs (Quest Run, Dungeon Run, Area Run, Chain Run, Grind Run): every open stop gets a round marker in the run's
--   colour with its number 1, 2, 3 in the order of the way (the first one a bit bigger). Done stops go away, the
--   numbers move up. A search from the guide bar (auction house, trainer, ...) gets one symbol on the place the arrow
--   points at; the symbol can be chosen in the options (three to choose from). It stays when the arrow is clicked
--   away and goes when I arrive there.
--   Left click on a marker: the big arrow points there (the run's order stays). Right click: only the marker goes;
--   a new run brings the run's markers back, a new search a new symbol. Hover: number, quest, what to do, yards.
--   The map pin, the corpse and the group arrow get no marker (the game shows them).
--   An Area Run shows only its next M.AREA_SHOW (5) markers of the way; when a quest is done its stop goes and the
--   next one comes in (decision 614). Stops sharing one marker count once, a right clicked marker lets the next in.
--   No taint: the markers are own plain buttons on an own layer laid over the world map's canvas. Blizzard's pin
--   pools and data providers are not touched; the map frame only gets a HookScript for OnShow/OnHide.
--   Switch and symbol: options, Guidance (OMQDB.guide.mapMarkers, OMQDB.guide.markerIcon); /omq markers [on|off|diag].
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = {}
OMQ.MapMarkers = M

M.SIZE = 22               -- a run marker (the first stop 26)
M.FIRST = 26
M.ICON = 24               -- the search symbol
M.MAX = 40                -- markers at most
M.AREA_SHOW = 5           -- an Area Run: only the next 5 markers of the way (MadDadVibe); a done quest lets the next one in
M.MERGE = 15              -- yards: stops this close share one marker ("1-2"), fix 598
M.ARRIVE = 12             -- yards: the search symbol goes away there
M.REFRESH = 0.5           -- seconds between two looks at the runs while the map is open
M.LEVEL = 2000            -- frame levels above the canvas (over Blizzard's pins)

M.COLORS = {
    quest   = { 0.89, 0.71, 0.29 },     -- gold, the Quest Run (465)
    dungeon = { 0.30, 0.62, 1.00 },     -- blue (476)
    area    = { 0.33, 0.84, 0.40 },     -- green (491)
    chain   = { 0.66, 0.33, 0.94 },     -- purple (595)
    grind   = { 0.86, 0.26, 0.22 },     -- red, as the Grind Run window (518)
}
M.RUN_NAMES = { quest = "Quest Run", dungeon = "Dungeon Run", area = "Area Run", chain = "Chain Run", grind = "Grind Run" }
-- the three symbols for a search (MadDadVibe: three to choose from in the options)
M.ICONS = {
    { label = "Star",    icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
    { label = "Diamond", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
    { label = "Circle",  icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
}
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHAT = { p = "pick up the quest", t = "turn in", o = "objectives", w = "follow the quest in your log" }

local isSecret = function(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not isSecret(v) end
local function now() return GetTime and GetTime() or 0 end

local hidden = {}         -- [marker key] = true: right clicked away
local hiddenFor = nil     -- the run the hidden keys belong to
local layer, pins = nil, {}
local mapInst = {}        -- [uiMapID] = continent (false: none)
local list = {}           -- the markers of the last look
local lastLook, lastMap, lastScale, lastW, lastH = -1, nil, nil, nil, nil

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
local function gdb() return OMQ.db and OMQ.db.guide or {} end
function M.Enabled() return gdb().mapMarkers ~= false end
function M.SetEnabled(on)
    if OMQ.db and OMQ.db.guide then OMQ.db.guide.mapMarkers = on and true or false end
    M.Refresh(true)
end
function M.IconIndex()
    local i = tonumber(gdb().markerIcon) or 1
    return (i >= 1 and i <= #M.ICONS) and math.floor(i) or 1
end
function M.SetIcon(i)
    i = tonumber(i)
    if not (i and M.ICONS[i]) then return end
    if OMQ.db and OMQ.db.guide then OMQ.db.guide.markerIcon = i end
    M.Refresh(true)
end
function M.IconChoices()
    local out = {}
    for i, c in ipairs(M.ICONS) do out[i] = { label = c.label, icon = c.icon } end
    return out
end

----------------------------------------------------------------------
-- What to mark
----------------------------------------------------------------------
local function myPos()
    if not UnitPosition then return nil end
    local a, b, _, inst = UnitPosition("player")
    if not (num(a) and num(b)) then return nil end
    return { a = a, b = b, inst = inst }
end
local function straight(p, pos)
    if not (p and pos) or p.inst ~= pos.inst then return nil end
    return math.sqrt((p.a - pos.a) ^ 2 + (p.b - pos.b) ^ 2)
end
local function placeKey(p) return string.format("%d:%d", math.floor(p.a + 0.5), math.floor(p.b + 0.5)) end

-- the run that goes now: a source id (new id = hidden markers come back) and its markers
local function chainMarkers(out)
    local C = OMQ.ChainRun
    if not (C and C.Active and C:Active()) then return nil end
    local chain = C:Chain()
    if not chain then return nil end
    local r = C:Run() or {}
    local _, _, first = C.Progress(chain)
    if not first then return nil end
    for i = first, #chain.steps do
        local st = chain.steps[i]
        local state = C.StepState(st)
        if state ~= "done" then
            local p, what
            if st.search then                             -- the dead guard: only the next place to look at
                if i == first then p = C.SearchSpot(st, myPos()) end
                what = state == "log" and st.toText or st.fromText
            elseif state == "log" then p, what = C.Place(C.Pick(st.to)), st.toText
            else p, what = C.Place(C.Pick(st.from)), st.fromText end
            if p then
                out[#out + 1] = { run = "chain", place = p, title = C.Title(st), what = what,
                                  key = "c" .. i, radius = st.search and C.SEARCH_RADIUS or C.PICK_RADIUS }
            end
        end
    end
    return "chain:" .. tostring(r.key) .. ":" .. tostring(r.started or r.startedAt or "")
end

local function questMarkers(out)
    local R = OMQ.QuestRun
    if not (R and R.Active and R:Active()) then return nil end
    local run = R:Run()
    local kind = (run.kind == "dungeon" or run.kind == "area") and run.kind or "quest"
    for i, s in ipairs(run.stops or {}) do
        local p, what = s.place, WHAT[s.kind] or "objectives"
        if s.kind == "w" then                             -- the game's own point is known only for the next stop
            local t = (i == 1) and R.FollowTarget(s, myPos()) or nil
            p, what = t and t.place, t and t.what or what
        elseif s.kind == "t" and i == 1 and R.Target then
            -- a turn-in while objectives are still open: the marker stands where the arrow points (decision 709)
            local t = R:Target()
            if t and t.open and t.place then p, what = t.place, t.what or what end
        elseif s.kind == "o" then
            what = (R.StopWhat and R.StopWhat(s)) or what           -- a part stop: its own objectives (663)
        elseif s.kind == "p" and R.Hunt and R.Hunt(s.qid) then
            what = R.Hunt(s.qid)                          -- a named mob drops it (508)
        end
        if p and p.a and p.b then
            out[#out + 1] = { run = kind, place = p, qid = s.qid, kind = s.kind, title = R.Title(s.qid), what = what,
                              key = "q" .. tostring(s.qid) .. s.kind .. ":" .. placeKey(p),
                              radius = s.kind == "o" and R.OBJ_RADIUS or R.PICK_RADIUS }
        end
    end
    return "quest:" .. tostring(run.id)
end

local function grindMarkers(out)
    local G = OMQ.Grind
    if not G then return nil end
    local r = G.Active and G:Active() and G:Run()
    local spot = r and r.spot or G.target
    if not spot then return nil end
    local w = G.World(spot.map, spot.x, spot.y)
    if not w then return nil end
    out[#out + 1] = { run = "grind", place = w, title = spot.name or "Grind spot", what = "kill mobs here",
                      key = "g" .. tostring(spot.key), radius = G.ARRIVE }
    return "grind:" .. tostring(r and r.id or ("to:" .. tostring(spot.key)))
end

-- every marker that is to be shown now: { run | search, n, place, title, what, key, ... }
function M.Collect()
    local out = {}
    if not (M.Enabled() and OMQ:Master("guidance")) then return out end
    local runs = {}
    local src = chainMarkers(runs) or questMarkers(runs) or grindMarkers(runs)
    if src ~= hiddenFor then hidden, hiddenFor = {}, src end
    local n = 0
    local limit = M.MAX
    if runs[1] and runs[1].run == "area" then limit = math.min(M.MAX, M.AREA_SHOW) end
    for _, m in ipairs(runs) do
        n = n + 1                                         -- a hidden marker keeps its number: the order stays
        m.n = n
        if not hidden[m.key] then
            -- fix 598: stops at (nearly) the same place share one marker, else the later one covers the earlier
            local host
            for _, o in ipairs(out) do
                if o.place.inst == m.place.inst and math.abs(o.place.a - m.place.a) <= M.MERGE
                   and math.abs(o.place.b - m.place.b) <= M.MERGE then host = o; break end
            end
            if host then
                host.also = host.also or {}
                host.also[#host.also + 1] = m
            elseif #out < limit then out[#out + 1] = m end
        end
    end
    local G = OMQ.Guide
    local s = G and G.SearchMark and G:SearchMark()
    if s then
        local d = straight(s, myPos())
        if d and d <= M.ARRIVE then G:ForgetSearchMark()            -- arrived: the symbol goes
        else
            out[#out + 1] = { search = true, place = s, title = s.name or s.label, label = s.label, spec = s.spec, key = "search" }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Clicks
----------------------------------------------------------------------
function M.Go(m)
    local G = OMQ.Guide
    if not (m and G) then return false end
    local p = m.place
    if m.search then return G:StartSearchAt(m.spec, p.a, p.b, p.inst) end
    if m.run == "grind" then
        G:StartAt("Grind Run", p.a, p.b, p.inst, "grind", nil, { name = m.title, radius = m.radius })
        return true
    end
    local label = (m.run == "chain") and "Chain Run: " or "Quest Run: "
    G:StartAt(label .. tostring(m.title), p.a, p.b, p.inst, "run", nil,
        { name = m.what, radius = m.radius, qid = m.qid, area = m.kind == "o" or nil })
    return true
end

function M.Remove(m)
    if not m then return end
    if m.search then
        if OMQ.Guide and OMQ.Guide.ForgetSearchMark then OMQ.Guide:ForgetSearchMark() end
    else
        hidden[m.key] = true
        for _, o in ipairs(m.also or {}) do hidden[o.key] = true end
    end
    M.Refresh(true)
end
function M.IsHidden(key) return hidden[key] == true end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------
local function mapFrame() return _G.WorldMapFrame end

-- the continent of a map (the world position of its middle)
local function instOf(map)
    local v = mapInst[map]
    if v ~= nil then return v or nil end
    v = false
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, inst = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0.5, 0.5))
        if ok and num(inst) then v = inst end
    end
    mapInst[map] = v
    return v or nil
end

-- world position -> 0..1 on the shown map, nil when it is not on that map
function M.MapXY(map, p)
    if not (map and p and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local inst = instOf(map)
    if inst and p.inst and inst ~= p.inst then return nil end
    local ok, _, vec = pcall(C_Map.GetMapPosFromWorldPos, p.inst or inst or 0, CreateVector2D(p.a, p.b), map)
    if not (ok and vec) then return nil end
    local x, y
    if vec.GetXY then x, y = vec:GetXY() else x, y = vec.x, vec.y end
    if not (num(x) and num(y)) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function tooltip(pin)
    local m = pin.m
    if not (m and GameTooltip) then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    if m.search then
        GameTooltip:SetText(m.title or "Destination", 1, 0.82, 0)
        if m.label and m.label ~= m.title then GameTooltip:AddLine(m.label, 0.8, 0.8, 0.8) end
    else
        local c = M.COLORS[m.run] or M.COLORS.quest
        GameTooltip:SetText(string.format("%d. %s", m.n or 0, tostring(m.title)), c[1], c[2], c[3])
        GameTooltip:AddLine(M.RUN_NAMES[m.run] or "Run", 0.6, 0.63, 0.68)
        if m.what then GameTooltip:AddLine(m.what, 1, 1, 1, true) end
        for _, o in ipairs(m.also or {}) do
            GameTooltip:AddLine(string.format("%d. %s", o.n or 0, tostring(o.title)), c[1], c[2], c[3])
            if o.what then GameTooltip:AddLine(o.what, 1, 1, 1, true) end
        end
    end
    local d = straight(m.place, myPos())
    GameTooltip:AddLine(d and string.format("%d yards", math.floor(d + 0.5)) or "other continent", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Left click: arrow there  -  Right click: remove marker", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function newPin()
    local b = CreateFrame("Button", nil, layer)
    b:SetSize(M.SIZE, M.SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.ring = b:CreateTexture(nil, "ARTWORK")
    b.ring:SetAllPoints()
    b.ring:SetTexture(MASK)                               -- a white disc (fix 598: masks on colour textures were square)
    b.inner = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.inner:SetPoint("TOPLEFT", 2, -2); b.inner:SetPoint("BOTTOMRIGHT", -2, 2)
    b.inner:SetTexture(MASK)
    b.inner:SetVertexColor(0.08, 0.086, 0.114, 0.95)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints()
    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.num:SetPoint("CENTER", 0, 0)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then M.Remove(self.m) else M.Go(self.m) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local function style(pin, m)
    pin.m = m
    if m.search then
        pin.ring:Hide(); pin.inner:Hide(); pin.num:Hide()
        pin.icon:SetTexture(M.ICONS[M.IconIndex()].icon); pin.icon:Show()
        pin.size = M.ICON
    else
        local c = M.COLORS[m.run] or M.COLORS.quest
        pin.icon:Hide()
        pin.ring:SetVertexColor(c[1], c[2], c[3], 1); pin.ring:Show(); pin.inner:Show()
        pin.num:SetText(M.Label(m)); pin.num:SetTextColor(c[1], c[2], c[3]); pin.num:Show()
        pin.size = (m.n == 1 or m.also) and M.FIRST or M.SIZE
    end
    pin:SetSize(pin.size, pin.size)
end

-- the number on a marker: "2", or "1-2" / "1+" when stops share it (fix 598)
function M.Label(m)
    if not m.also then return tostring(m.n) end
    local last, row = m.n, true
    for _, o in ipairs(m.also) do
        if o.n == last + 1 then last = o.n else row = false end
    end
    return row and (m.n .. "-" .. last) or (m.n .. "+")
end

-- puts the markers on the shown map
function M.Place()
    local wm = mapFrame()
    if not (layer and wm) then return 0 end
    local canvas = wm.GetCanvas and wm:GetCanvas()
    local map = wm.GetMapID and wm:GetMapID()
    local cs = wm.GetCanvasScale and wm:GetCanvasScale()
    local w, h = canvas and canvas:GetWidth(), canvas and canvas:GetHeight()
    local shown = 0
    if canvas and num(map) and num(w) and num(h) and w > 0 and h > 0 then
        local scale = 1 / ((num(cs) and cs > 0) and cs or 1)
        for _, m in ipairs(list) do
            local x, y = M.MapXY(map, m.place)
            if x then
                shown = shown + 1
                local pin = pins[shown] or newPin()
                pins[shown] = pin
                style(pin, m)
                pin:SetFrameLevel((layer:GetFrameLevel() or 1) + (m.search and M.MAX + 2 or math.max(1, M.MAX + 1 - (m.n or M.MAX))))
                pin:SetScale(scale)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", w * x / scale, -h * y / scale)
                pin:Show()
            end
        end
    end
    for i = shown + 1, #pins do pins[i]:Hide(); pins[i].m = nil end
    lastMap, lastScale, lastW, lastH = map, cs, w, h
    return shown
end

-- a new look at the runs (force: at once, else at most every M.REFRESH seconds while the map is open)
function M.Refresh(force)
    if not layer then return end
    local t = now()
    if not force and t - lastLook < M.REFRESH then return end
    lastLook = t
    list = M.Collect()
    M.Place()
end

local function onUpdate()
    local wm = mapFrame()
    if not (wm and wm.IsShown and wm:IsShown()) then return end
    local canvas = wm.GetCanvas and wm:GetCanvas()
    local map, cs = wm.GetMapID and wm:GetMapID(), wm.GetCanvasScale and wm:GetCanvasScale()
    local w, h = canvas and canvas:GetWidth(), canvas and canvas:GetHeight()
    if map ~= lastMap or cs ~= lastScale or w ~= lastW or h ~= lastH then M.Place() end
    M.Refresh(false)
end

-- the own layer on the map's canvas; the world map may load later than OMQ
function M.Attach()
    if layer then return true end
    local wm = mapFrame()
    local canvas = wm and wm.GetCanvas and wm:GetCanvas()
    if not canvas then return false end
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel((canvas:GetFrameLevel() or 1) + M.LEVEL)
    layer:SetScript("OnUpdate", onUpdate)
    if wm.HookScript then
        wm:HookScript("OnShow", function() M.Refresh(true) end)
    end
    M.Refresh(true)
    return true
end

function M.Count() return #list end
function M.List() return list end
function M.Pins() return pins end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, _, name) if name == "Blizzard_WorldMap" then M.Attach() end end)
OMQ:On("READY", function() M.Attach() end)
for _, e in ipairs({ "GUIDE_CHANGED", "QUEST_RUN_CHANGED", "CHAIN_RUN_CHANGED", "GRIND_CHANGED" }) do
    OMQ:On(e, function() M.Refresh(true) end)
end

OMQ:RegisterCommand("markers", function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        M.SetEnabled(arg == "on")
        OMQ:Print("map markers " .. (arg == "on" and "on" or "off"))
        return
    end
    M.Attach()
    M.Refresh(true)
    local wm = mapFrame()
    local map = wm and wm.GetMapID and wm:GetMapID()
    local out = { "Map markers: " .. (M.Enabled() and "on" or "off") .. ", symbol " .. M.ICONS[M.IconIndex()].label,
                  "map layer: " .. (layer and "yes" or "no") .. ", map " .. tostring(map) }
    for _, m in ipairs(list) do
        local x, y = M.MapXY(map, m.place)
        out[#out + 1] = string.format("%s %s  %s  %s", m.search and "search" or (m.run .. " " .. tostring(m.n)),
            tostring(m.title), x and string.format("%.1f %.1f", x * 100, y * 100) or "not on this map",
            string.format("(%.0f, %.0f, %s)", m.place.a, m.place.b, tostring(m.place.inst)))
    end
    if #list == 0 then out[#out + 1] = "no markers (no run, no search)" end
    OMQ:ShowReport(out)
end, "map markers of the runs and the guide bar search: /omq markers [on|off]")
