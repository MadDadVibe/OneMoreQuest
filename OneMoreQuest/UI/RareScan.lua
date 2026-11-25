-- One More Quest: rare scanner (decision 703)
-- Every mob whose nameplate shows up (or who is my target or under the mouse) and that the game classifies as
-- "rare" or "rareelite" gets a sound and a card at the top of the screen: "Rare nearby: Name (34 Rare Elite)" with
-- its 3D model. One card per rare at most every R.REPEAT seconds; dead rares are left out; quiet in major cities and
-- sanctuaries. UnitClassification is never secret on WoW Forever; name and GUID are checked like every value.
-- Left click on the card: target the rare and put the skull on it (secure button, armed out of combat only, like the
-- enemy warning of decision 524). Right click: close the card.
-- Vignettes: WoW Forever's client has C_VignetteInfo; whether the server sends vignettes for the old rares is not
-- known. Every vignette that comes is written to /omq rare log; one of a known rare (or with a rare atlas) warns too.
-- Group: a sighting goes to the dads with OMQ (message RX, same map only); they get the same card with "seen by".
-- World map: a skull button at the top right switches the known spawn places of the zone's rares on (Data/Rares.lua
-- from Factoruide, default off). Hover: name, level, rare or rare elite, respawn time, when I last saw or killed it.
-- Grey: more than R.GREY levels below me. Right click on a mark: gone until the map opens again.
-- Options: options.rareScan, options.rareSound, options.rareShare (on), guide.rareMap (off). /omq rare.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local R = {}
OMQ.RareScan = R

R.REPEAT = 600          -- seconds: the same rare warns again after this
R.SHOW = 15             -- seconds a card stays (longer while the mouse is on it), then it fades
R.FADE = 1
R.ROWS = 3
R.W, R.ROW_H, R.ROW_GAP, R.TOP = 420, 44, 46, -60     -- card size and place (above the enemy warning at -200)
R.SCAN = 1              -- seconds between nameplate scans
R.GREY = 5              -- map marks of rares this many levels below me are grey
R.LOG = 40              -- vignette log lines kept
R.KILL_GAP = 60         -- seconds: one kill of the same rare is counted once
R.SOUND = { kit = "RAID_WARNING", id = 8959 }
R.SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
R.CLASSES = { rare = "Rare", rareelite = "Rare Elite" }
R.SIZE = 18             -- a mark on the map
R.LEVEL = 1890          -- frame levels above the map canvas: under the quest givers (1900) and run markers (2000)

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok or secret(a) then return nil end
    if secret(b) then b = nil end
    return a, b
end
local function num(v) return type(v) == "number" and not secret(v) end
local function now() return GetTime and GetTime() or 0 end
local function clock() return (time and time()) or 0 end
local function opt(k)
    local o = OMQ.db and OMQ.db.options
    return not (o and o[k] == false)
end

function R.Enabled() return opt("rareScan") end
function R.SoundOn() return opt("rareSound") end
function R.ShareOn() return opt("rareShare") end

R.seen = {}             -- key -> { warnedAt }

----------------------------------------------------------------------
-- what I remember about each rare: OMQDB.rares[npcID or name] = { seen, killed, name }
----------------------------------------------------------------------
local function mem()
    if not OMQ.db then return {} end
    OMQ.db.rares = OMQ.db.rares or {}
    return OMQ.db.rares
end
function R.Memory(key)
    local m = mem()
    if key == nil then return nil end
    if not m[key] then m[key] = {} end
    return m[key]
end
-- what is known about a rare of the data: by its npc ID, else by its English name (English client, GUID secret)
function R.Known(npc)
    local m = mem()
    if m[npc] then return m[npc] end
    local d = OMQ.Rares and OMQ.Rares[npc]
    return d and m[d[1]] or nil
end

----------------------------------------------------------------------
-- reading a unit
----------------------------------------------------------------------
-- "Creature-0-1-2-3-3100-0000" -> 3100
function R.NpcID(guid)
    if type(guid) ~= "string" or secret(guid) then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

function R.MyLevel() return (plain(UnitLevel, "player")) or 0 end

-- { key, name, npc, level, cls } for a living rare, else nil (a dead one I may have killed is remembered)
function R.Read(unit)
    if not unit or plain(UnitExists, unit) ~= true then return nil end
    if plain(UnitIsPlayer, unit) == true then return nil end
    local cls = plain(UnitClassification, unit)
    if not R.CLASSES[cls] then return nil end
    if plain(UnitCanAttack, "player", unit) == false then return nil end
    local name = plain(UnitName, unit)
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    local npc = R.NpcID(plain(UnitGUID, unit))
    local key = npc or name
    if plain(UnitIsDead, unit) == true then
        if plain(UnitIsTapDenied, unit) ~= true then R.Killed(key, name) end
        return nil
    end
    local level = plain(UnitLevel, unit)
    if not num(level) then level = nil end
    return { key = key, name = name, npc = npc, level = level, cls = cls }
end

function R.Killed(key, name)
    local m = R.Memory(key)
    local t = clock()
    if m.killed and t - m.killed < R.KILL_GAP then return false end
    m.killed = t
    if name then m.name = name end
    return true
end

----------------------------------------------------------------------
-- texts
----------------------------------------------------------------------
function R.Who(e)
    local lvl = e.level == -1 and "??" or (e.level and tostring(e.level)) or nil
    local inner = (lvl and (lvl .. " ") or "") .. (R.CLASSES[e.cls] or "Rare")
    local col = e.cls == "rareelite" and "|cffffd100" or "|cffd0d0e0"
    return col .. e.name .. "|r (" .. inner .. ")"
end

function R.Text(e)
    local s = "Rare nearby: " .. R.Who(e)
    if e.by then s = s .. " |cffaaaaaa- seen by " .. e.by .. "|r" end
    return s
end

----------------------------------------------------------------------
-- the card: plain rows, a secure button over each (same pattern as UI/EnemyNear.lua, decisions 524/528)
----------------------------------------------------------------------
local holder, rows
local buttons, shields, armed = {}, {}, {}
R.slots = {}            -- per row: { text, cls, npc, at, key, full } or nil

local function locked() return InCombatLockdown and InCombatLockdown() and true or false end

R.MAX_NAME = 48
function R.SafeName(n)
    if type(n) ~= "string" or secret(n) then return false end
    if n == "" or #n > R.MAX_NAME or n:find("^%s") then return false end
    return n:find("[%c;/\\|]") == nil
end
function R.Macro(full)
    if not R.SafeName(full) then return nil end
    return "/cleartarget\n/targetexact " .. full .. "\n/tm [exists] 8"
end

local function makeButton(i)
    local b = CreateFrame("Button", "OneMoreQuestRareClick" .. i, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type1", "macro")
    b:SetSize(R.W, R.ROW_H)
    b:SetPoint("TOP", UIParent, "TOP", 0, R.TOP - (i - 1) * R.ROW_GAP)
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel(20)
    b.row = i
    b:SetScript("PostClick", function(self, button, down)
        if down then return end
        if button == "RightButton" then R.Dismiss(self.row) end
    end)
    b:SetScript("OnEnter", function(self)
        local c = R.slots[self.row]
        if not (c and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(c.full or "?")
        GameTooltip:AddLine("Left click: target it and put the skull on it.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Right click: close the card.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:Hide()
    buttons[i] = b
    local sh = CreateFrame("Frame", nil, UIParent)
    sh:SetFrameStrata("DIALOG")
    sh:SetAllPoints(b)
    sh:EnableMouse(true)
    sh.row = i
    sh:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then R.Dismiss(self.row) end end)
    sh:Hide()
    shields[i] = sh
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "OneMoreQuestRareScan", UIParent)
    holder:SetSize(R.W, R.ROWS * R.ROW_GAP)
    holder:SetPoint("TOP", UIParent, "TOP", 0, R.TOP)
    holder:SetFrameStrata("HIGH")
    rows = {}
    for i = 1, R.ROWS do
        local r = CreateFrame("Frame", nil, holder)
        r:SetSize(R.W, R.ROW_H)
        r:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * R.ROW_GAP)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0, 0, 0, 0.65)
        local edge = r:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT")
        edge:SetWidth(4)
        edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        r.edge = edge
        local model = CreateFrame("PlayerModel", nil, r)
        model:SetSize(R.ROW_H - 4, R.ROW_H - 4)
        model:SetPoint("LEFT", r, "LEFT", 8, 0)
        r.model = model
        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("CENTER", model, "CENTER", 0, 0)
        icon:SetTexture(R.SKULL)
        r.icon = icon
        local text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", model, "RIGHT", 8, 0)
        text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        text:SetJustifyH("LEFT")
        r.text = text
        r:Hide()
        rows[i] = r
    end
    R._rows = rows
    if not locked() then for i = 1, R.ROWS do makeButton(i) end end
end

function R.Clickable(i)
    local c = R.slots[i]
    return c ~= nil and c.full ~= nil and armed[i] == c.full and buttons[i] ~= nil and buttons[i]:IsShown() and true or false
end

function R.Arm()
    if locked() or not holder then return end
    for i = 1, R.ROWS do
        if not buttons[i] then makeButton(i) end
        local c, b = R.slots[i], buttons[i]
        local macro = c and c.full and R.Macro(c.full)
        if macro then
            b:SetAttribute("macrotext1", macro)
            armed[i] = c.full
            b:Show()
        else
            b:SetAttribute("macrotext1", "")
            armed[i] = nil
            b:Hide()
        end
        shields[i]:Hide()
    end
end

-- the 3D model of the rare (the skull when there is none)
function R.SetModel(r, npc)
    local shown = false
    if npc and r.model.SetCreature then
        local ok = pcall(r.model.SetCreature, r.model, npc)
        if ok then
            pcall(r.model.SetPortraitZoom, r.model, 0.7)
            shown = true
        end
    end
    if shown then r.model:Show(); r.icon:Hide() else r.model:Hide(); r.icon:Show() end
    return shown
end

local function paint()
    if not holder then return end
    local t = now()
    for i = 1, R.ROWS do
        local r, c = rows[i], R.slots[i]
        if c then
            local age = t - c.at
            local text = c.text
            if c.full and not R.Clickable(i) and locked() then text = text .. " |cff888888(click after combat)|r" end
            r.text:SetText(text)
            if c.cls == "rareelite" then r.edge:SetVertexColor(1, 0.82, 0) else r.edge:SetVertexColor(0.75, 0.75, 0.85) end
            if r.npc ~= c.npc or not r.modelSet then r.npc = c.npc; r.modelSet = true; R.SetModel(r, c.npc) end
            r:SetAlpha(age > R.SHOW and math.max(0, 1 - (age - R.SHOW) / R.FADE) or 1)
            r:Show()
        else
            r:Hide()
        end
        if shields[i] then
            local b = buttons[i]
            shields[i]:SetShown(b ~= nil and b:IsShown() and not R.Clickable(i))
        end
    end
end

local function freeRow()
    for i = 1, R.ROWS do if not R.slots[i] then return i end end
    local best
    for i = 1, R.ROWS do
        if not (locked() and R.Clickable(i)) and (not best or R.slots[i].at < R.slots[best].at) then best = i end
    end
    if best then return best end
    for i = 1, R.ROWS do
        if not best or R.slots[i].at < R.slots[best].at then best = i end
    end
    return best
end

function R.ShowCard(e)
    build()
    local i = freeRow()
    R.slots[i] = { text = R.Text(e), cls = e.cls, npc = e.npc, at = now(), key = e.key, full = e.name }
    rows[i].modelSet = nil
    holder:Show()
    R.Arm()
    paint()
    return i
end

function R.Dismiss(i)
    R.slots[i] = nil
    R.Arm()
    paint()
end

function R.Expire()
    local t = now()
    local changed = false
    for i = 1, R.ROWS do
        local c = R.slots[i]
        if c then
            if rows[i]:IsMouseOver() or (buttons[i] and buttons[i]:IsMouseOver()) then c.at = t end
            if t - c.at > R.SHOW + R.FADE then R.slots[i] = nil; changed = true end
        end
    end
    if changed then R.Arm() end
    paint()
end

function R.HasCards()
    for i = 1, R.ROWS do if R.slots[i] then return true end end
    return false
end

function R.ClearCards()
    for i = 1, R.ROWS do R.slots[i] = nil end
    R.Arm()
    paint()
end

function R.PlaySound()
    if not R.SoundOn() or not PlaySound then return false end
    local id = (_G.SOUNDKIT and _G.SOUNDKIT[R.SOUND.kit]) or R.SOUND.id
    return (pcall(PlaySound, id, "SFX"))
end

----------------------------------------------------------------------
-- sightings
----------------------------------------------------------------------
function R.Quiet()
    if OMQ.InMajorCity and OMQ:InMajorCity() then return true end
    return plain(GetZonePVPInfo) == "sanctuary"
end

-- e from R.Read (or a vignette, or a shared one with by); returns true when it warned
function R.Sighted(e, by)
    if not e or not R.Enabled() or R.Quiet() then return false end
    local m = R.Memory(e.key)
    m.seen = clock()
    m.name = e.name
    if e.npc and e.key ~= e.npc then R.Memory(e.npc).seen = m.seen end
    local t = now()
    local s = R.seen[e.key]
    if not s then s = {}; R.seen[e.key] = s end
    if s.warnedAt and t - s.warnedAt < R.REPEAT then return false end
    s.warnedAt = t
    R.ShowCard(e)
    R.PlaySound()
    if not by then R.Share(e) end
    return true
end

function R.Look(unit)
    if not R.Enabled() then return false end
    local e = R.Read(unit)
    if not e then return false end
    return R.Sighted(e)
end

local function plateUnits()
    local out = {}
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, p in ipairs(plates) do
                local u = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
                if type(u) == "string" and not secret(u) then out[#out + 1] = u end
            end
        end
    end
    return out
end

function R.Scan()
    if not R.Enabled() or R.Quiet() then return end
    for _, u in ipairs(plateUnits()) do R.Look(u) end
    R.Look("target")
    R.Look("mouseover")
end

----------------------------------------------------------------------
-- vignettes: logged, and a warning when one belongs to a rare
----------------------------------------------------------------------
R.vigSeen = {}
local function vlog()
    if not OMQ.db then return {} end
    OMQ.db.rareLog = OMQ.db.rareLog or {}
    return OMQ.db.rareLog
end
function R.Log(line)
    local l = vlog()
    l[#l + 1] = date and (date("%m-%d %H:%M ") .. line) or line
    while #l > R.LOG do table.remove(l, 1) end
end

local function isRareAtlas(a)
    if type(a) ~= "string" or secret(a) then return false end
    local s = a:lower()
    return s:find("rare") ~= nil or s:find("vignettekill") ~= nil
end

function R.Vignette(guid)
    if not (C_VignetteInfo and C_VignetteInfo.GetVignetteInfo) or guid == nil or secret(guid) then return false end
    local info = plain(C_VignetteInfo.GetVignetteInfo, guid)
    if type(info) ~= "table" then return false end
    local name = (type(info.name) == "string" and not secret(info.name)) and info.name or nil
    local npc = R.NpcID(info.objectGUID)
    if not R.vigSeen[guid] then
        R.vigSeen[guid] = true
        R.Log(string.format("vignette %s id %s atlas %s type %s npc %s%s", tostring(name), tostring(info.vignetteID),
            tostring(info.atlasName), tostring(info.type), tostring(npc), info.isDead == true and " dead" or ""))
    end
    if info.isDead == true or not name then return false end
    local d = npc and OMQ.Rares and OMQ.Rares[npc]
    if not d and not isRareAtlas(info.atlasName) then return false end
    local cls = (d and d[4] == 1 or (type(info.atlasName) == "string" and info.atlasName:lower():find("elite"))) and "rareelite" or "rare"
    return R.Sighted({ key = npc or name, name = name, npc = npc, level = d and d[3] or nil, cls = cls })
end

function R.Vignettes()
    if not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then return 0 end
    local list = plain(C_VignetteInfo.GetVignettes)
    local n = 0
    for _, g in ipairs(type(list) == "table" and list or {}) do
        n = n + 1
        R.Vignette(g)
    end
    return n
end

----------------------------------------------------------------------
-- the group: RX|protocol|key|name|level|cls|npc|mapID
----------------------------------------------------------------------
local function myMap()
    return C_Map and C_Map.GetBestMapForUnit and (plain(C_Map.GetBestMapForUnit, "player")) or 0
end

function R.Share(e)
    if not R.ShareOn() or not OMQ.GetChannel or not OMQ:GetChannel() then return false end
    return OMQ:Send("RX", tostring(e.key), e.name, e.level or "", e.cls, e.npc or "", myMap()) and true or false
end

OMQ:RegisterMessage("RX", function(f, sender)
    if not R.ShareOn() then return end
    local key, name, level, cls, npc, map = f[1], f[2], tonumber(f[3]), f[4], tonumber(f[5]), tonumber(f[6])
    if not R.CLASSES[cls] or not R.SafeName(name) then return end
    local who = tostring(sender or "?"):match("^[^-]+") or "?"
    local me = OMQ.GetSelf and OMQ:GetSelf()
    if me and me.name == who then return end
    local here = myMap()
    if map and map ~= 0 and here ~= 0 and map ~= here then return end
    R.Sighted({ key = npc or key, name = name, npc = npc, level = level, cls = cls, by = who }, who)
end)

----------------------------------------------------------------------
-- the world map: known spawn places of the zone's rares
----------------------------------------------------------------------
local layer, button, pins = nil, nil, {}
local list, hidden = {}, {}
local lastMap, lastScale, lastW, lastH

local function gdb() return OMQ.db and OMQ.db.guide or {} end
function R.MapOn() return gdb().rareMap == true end
function R.SetMap(on)
    if OMQ.db and OMQ.db.guide then OMQ.db.guide.rareMap = on and true or false end
    hidden = {}
    R.UpdateButton()
    R.Refresh()
end

-- { npc, x, y, key } for each place of a rare on this map
function R.Collect(map)
    local out = {}
    if not (R.MapOn() and num(map)) then return out end
    local s = OMQ.RareSpots and OMQ.RareSpots[map]
    if not s then return out end
    for i = 1, #s - 2, 3 do
        local npc = s[i]
        if OMQ.Rares and OMQ.Rares[npc] then
            out[#out + 1] = { npc = npc, x = s[i + 1] / 100, y = s[i + 2] / 100, key = npc .. ":" .. i }
        end
    end
    return out
end

function R.Grey(npc)
    local d = OMQ.Rares and OMQ.Rares[npc]
    return d ~= nil and d[3] < R.MyLevel() - R.GREY
end

-- "2 h", "45 min", "3 days"
function R.Span(sec)
    if not num(sec) or sec <= 0 then return nil end
    if sec >= 2 * 86400 then return string.format("%d days", math.floor(sec / 86400 + 0.5)) end
    if sec >= 5400 then return string.format("%d h", math.floor(sec / 3600 + 0.5)) end
    if sec >= 60 then return string.format("%d min", math.floor(sec / 60 + 0.5)) end
    return string.format("%d s", sec)
end
function R.Ago(t)
    if not num(t) then return "never" end
    local d = clock() - t
    if d < 60 then return "just now" end
    return R.Span(d) .. " ago"
end

-- the tooltip lines of a rare: { text, r, g, b }
function R.Lines(npc)
    local d = OMQ.Rares and OMQ.Rares[npc]
    if not d then return {} end
    local m = R.Known(npc) or {}
    local lvl = d[2] == d[3] and tostring(d[2]) or (d[2] .. "-" .. d[3])
    local out = {}
    out[#out + 1] = { (m.name or d[1]), d[4] == 1 and 1 or 0.82, d[4] == 1 and 0.82 or 0.82, d[4] == 1 and 0 or 0.88 }
    out[#out + 1] = { string.format("Level %s %s", lvl, d[4] == 1 and "Rare Elite" or "Rare"), 1, 1, 1 }
    out[#out + 1] = { "Respawn: " .. (R.Span(d[5]) and ("about " .. R.Span(d[5])) or "unknown"), 0.8, 0.8, 0.8 }
    out[#out + 1] = { "Last seen: " .. R.Ago(m.seen), 0.8, 0.8, 0.8 }
    out[#out + 1] = { "Last killed: " .. R.Ago(m.killed), 0.8, 0.8, 0.8 }
    return out
end

local function tip(pin)
    if not (pin and pin.m and GameTooltip) then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    for i, l in ipairs(R.Lines(pin.m.npc)) do
        if i == 1 then GameTooltip:SetText(l[1], l[2], l[3], l[4]) else GameTooltip:AddLine(l[1], l[2], l[3], l[4]) end
    end
    GameTooltip:AddLine("Right click: remove mark", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end
local function leave() if GameTooltip then GameTooltip:Hide() end end

local function newPin()
    local b = CreateFrame("Button", nil, layer)
    b:SetSize(R.SIZE, R.SIZE)
    b:RegisterForClicks("RightButtonUp")
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints()
    b.icon:SetTexture(R.SKULL)
    b:SetScript("OnClick", function(self) if self.m then hidden[self.m.key] = true; R.Place() end; leave() end)
    b:SetScript("OnEnter", tip)
    b:SetScript("OnLeave", leave)
    return b
end

function R.Place()
    local wm = _G.WorldMapFrame
    if not (layer and wm) then return 0 end
    local canvas = wm.GetCanvas and wm:GetCanvas()
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
                if pin.icon.SetDesaturated then pin.icon:SetDesaturated(R.Grey(m.npc)) end
                pin.icon:SetAlpha(R.Grey(m.npc) and 0.6 or 1)
                pin:Show()
            end
        end
    end
    for i = shown + 1, #pins do pins[i]:Hide(); pins[i].m = nil end
    lastScale, lastW, lastH = cs, w, h
    return shown
end

function R.Refresh()
    if not layer then return end
    local wm = _G.WorldMapFrame
    lastMap = wm and wm.GetMapID and wm:GetMapID()
    list = R.Collect(lastMap)
    R.Place()
end

function R.UpdateButton()
    if not button then return end
    local on = R.MapOn()
    if button.icon.SetDesaturated then button.icon:SetDesaturated(not on) end
    button.icon:SetAlpha(on and 1 or 0.6)
end

local function buttonTip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Rares: " .. (R.MapOn() and "on" or "off"), 1, 0.82, 0)
    GameTooltip:AddLine("Shows where the rare mobs of this zone spawn.", 1, 1, 1, true)
    GameTooltip:Show()
end

local function onUpdate()
    local wm = _G.WorldMapFrame
    if not (wm and wm.IsShown and wm:IsShown()) then return end
    local canvas = wm.GetCanvas and wm:GetCanvas()
    local map, cs = wm.GetMapID and wm:GetMapID(), wm.GetCanvasScale and wm:GetCanvasScale()
    local w, h = canvas and canvas:GetWidth(), canvas and canvas:GetHeight()
    if map ~= lastMap then R.Refresh()
    elseif cs ~= lastScale or w ~= lastW or h ~= lastH then R.Place() end
end

function R.Attach()
    if layer then return true end
    local wm = _G.WorldMapFrame
    local canvas = wm and wm.GetCanvas and wm:GetCanvas()
    if not canvas then return false end
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel((canvas:GetFrameLevel() or 1) + R.LEVEL)
    layer:SetScript("OnUpdate", onUpdate)
    local host = wm.ScrollContainer or wm
    button = CreateFrame("Button", "OMQRareMapButton", host)
    button:SetSize(26, 26)
    button:SetPoint("TOPRIGHT", host, "TOPRIGHT", -70, -4)
    button:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 1) + R.LEVEL + 30)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    button.bg:SetVertexColor(0.08, 0.086, 0.114, 0.85)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 4, -4); button.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    button.icon:SetTexture(R.SKULL)
    button:SetScript("OnClick", function(self) R.SetMap(not R.MapOn()); buttonTip(self) end)
    button:SetScript("OnEnter", buttonTip)
    button:SetScript("OnLeave", leave)
    R.UpdateButton()
    if wm.HookScript then wm:HookScript("OnShow", function() hidden = {}; R.Refresh() end) end
    R.Refresh()
    return true
end

function R.List() return list end
function R.Pins() return pins end
function R.Button() return button end

----------------------------------------------------------------------
-- driver
----------------------------------------------------------------------
local driver = CreateFrame("Frame")
local sinceScan = 0
driver:SetScript("OnUpdate", function(_, dt)
    if not OMQ.db then return end
    if R.HasCards() then R.Expire() end
    sinceScan = sinceScan + (dt or 0)
    if sinceScan < R.SCAN then return end
    sinceScan = 0
    R.Scan()
end)
for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_REGEN_ENABLED",
    "VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED", "ADDON_LOADED", "PLAYER_LEVEL_UP" }) do
    pcall(driver.RegisterEvent, driver, ev)
end
driver:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 == "Blizzard_WorldMap" then R.Attach() end
        return
    end
    if not OMQ.db then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        R.Look(a1)
    elseif event == "PLAYER_TARGET_CHANGED" then
        R.Look("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        R.Look("mouseover")
    elseif event == "VIGNETTE_MINIMAP_UPDATED" then
        if R.Enabled() then R.Vignette(a1) end
    elseif event == "VIGNETTES_UPDATED" then
        if R.Enabled() then R.Vignettes() end
    elseif event == "PLAYER_LEVEL_UP" then
        if layer then R.Place() end
    elseif R.HasCards() then
        R.Arm(); paint()
    end
end)
OMQ:On("READY", function() R.Attach() end)

function R.SetEnabled(on)
    OMQ.db.options.rareScan = on and true or false
    if not on then R.ClearCards() end
end

function R.Test()
    local lvl = R.MyLevel()
    R.seen["test1"], R.seen["test2"] = nil, nil
    R.ShowCard({ key = "test2", name = "Foe Reaper 4000", npc = 573, level = math.max(1, lvl), cls = "rareelite", by = "Willi" })
    R.ShowCard({ key = "test1", name = "Mother Fang", npc = 471, level = math.max(1, lvl), cls = "rare" })
    R.PlaySound()
end

OMQ:RegisterCommand("rare", function(arg)
    local a, b = (arg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    local function onoff(v) return v and "on" or "off" end
    if a == "on" or a == "off" then
        R.SetEnabled(a == "on")
        OMQ:Print("rare scanner: " .. a)
        OMQ:Fire("SETTINGS_CHANGED")
    elseif (a == "sound" or a == "share") and (b == "on" or b == "off") then
        OMQ.db.options[a == "sound" and "rareSound" or "rareShare"] = b == "on"
        OMQ:Print("rare scanner " .. a .. ": " .. b)
        OMQ:Fire("SETTINGS_CHANGED")
    elseif a == "map" and (b == "on" or b == "off") then
        R.Attach()
        R.SetMap(b == "on")
        OMQ:Print("rares on the world map: " .. b)
        OMQ:Fire("SETTINGS_CHANGED")
    elseif a == "test" then
        R.Test()
        OMQ:Print("rare scanner: two sample cards")
    elseif a == "log" then
        local n = R.Vignettes()
        local out = { string.format("Rare scanner: %d vignettes now (C_VignetteInfo %s)", n,
            C_VignetteInfo and "there" or "missing") }
        for _, l in ipairs(vlog()) do out[#out + 1] = l end
        if #vlog() == 0 then out[#out + 1] = "no vignette seen yet" end
        OMQ:ShowReport(out)
    elseif a == "list" then
        local map = C_Map and C_Map.GetBestMapForUnit and plain(C_Map.GetBestMapForUnit, "player")
        local s = OMQ.RareSpots and map and OMQ.RareSpots[map] or {}
        local out, done = { "Rares of map " .. tostring(map) }, {}
        for i = 1, #s - 2, 3 do
            local npc = s[i]
            if not done[npc] and OMQ.Rares[npc] then
                done[npc] = true
                local l = R.Lines(npc)
                out[#out + 1] = string.format("%s - %s, %s, seen %s", l[1][1], l[2][1], l[3][1], R.Ago((R.Known(npc) or {}).seen))
            end
        end
        if #out == 1 then out[#out + 1] = "no known rare on this map" end
        OMQ:ShowReport(out)
    else
        OMQ:Print(("/omq rare on | off - sound and card for rare mobs nearby (now: %s, sound %s, share %s, map %s)")
            :format(onoff(R.Enabled()), onoff(R.SoundOn()), onoff(R.ShareOn()), onoff(R.MapOn())))
        OMQ:Print("/omq rare sound on|off, share on|off, map on|off, test, list, log")
    end
end, "rare mob scanner: /omq rare [on|off|test|list|log|map on|off]")
