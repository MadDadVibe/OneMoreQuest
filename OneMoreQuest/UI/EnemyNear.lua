-- One More Quest: players of the other faction nearby (decision 523)
-- Every enemy player whose nameplate shows up (or who is my target, under the mouse, or a group member's target)
-- gets a warning card at the top of the screen: "Horde nearby: Name (34 Rogue)" in class colors, red with a skull
-- when he is 5 or more levels above me (or "??"). One card and one sound per player at most every E.REPEAT seconds.
-- A red number on the minimap icon counts the enemies seen in the last E.SIGHT seconds; its tooltip names them.
-- Sightings go to the group (message EN); a sighting of a group member counts like my own, with "seen by X".
-- Off in major cities, sanctuaries, dungeons, raids and battlegrounds.
-- Readable on WoW Forever: UnitIsPlayer, UnitFactionGroup, UnitLevel are never secret; UnitName/UnitClass/UnitGUID
-- are secret only for units that are not player controlled - enemy players are. Every value is still checked.
-- Nameplates of enemies must be on: OMQ switches the game's "nameplateShowEnemies" on outside combat and gives
-- the old value back when the warning is switched off.
-- Options: options.enemyWarn, options.enemySound, options.enemyShare (all on by default). /omq enemy.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local E = {}
OMQ.EnemyNear = E

E.REPEAT = 300          -- seconds: the same player warns again after this
E.SIGHT = 10            -- seconds: an enemy counts as nearby this long after he was last seen
E.SHARED_SIGHT = 30     -- seconds: the same for a sighting of a group member
E.SHOW = 10             -- seconds a warning row stays (longer while the mouse is on it), then it fades
E.FADE = 1
E.ROWS = 3
E.DANGER = 5            -- levels above mine: red with a skull
E.SCAN = 1              -- seconds between nameplate scans
E.CVAR = "nameplateShowEnemies"
E.SOUND = { kit = "RAID_WARNING", id = 8959 }
E.SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
E.ICONS = { Horde = "Interface\\PVPFrame\\PVP-Currency-Horde", Alliance = "Interface\\PVPFrame\\PVP-Currency-Alliance" }
E.FACTIONS = { Horde = true, Alliance = true }

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok or secret(a) then return nil end
    if secret(b) then b = nil end
    return a, b
end
local function now() return GetTime and GetTime() or 0 end
local function opt(k)
    local o = OMQ.db and OMQ.db.options
    return not (o and o[k] == false)
end

function E.Enabled() return opt("enemyWarn") end
function E.SoundOn() return opt("enemySound") end
function E.ShareOn() return opt("enemyShare") end

E.seen = {}             -- key -> { key, name, level, class, faction, at, warnedAt, by, shared }

----------------------------------------------------------------------
-- where the warning is quiet
----------------------------------------------------------------------
function E.Quiet()
    if IsInInstance then
        local inside, kind = plain(IsInInstance)
        if inside and kind ~= "none" then return true end
    end
    if OMQ.InMajorCity and OMQ:InMajorCity() then return true end
    local pvp = plain(GetZonePVPInfo)
    if pvp == "sanctuary" then return true end
    return false
end

----------------------------------------------------------------------
-- reading a unit
----------------------------------------------------------------------
function E.MyFaction() return (plain(UnitFactionGroup, "player")) end
function E.MyLevel() return (plain(UnitLevel, "player")) or 0 end

-- { key, name, level, class, faction } for a living enemy player, else nil
function E.Read(unit)
    if not unit or plain(UnitExists, unit) ~= true then return nil end
    if plain(UnitIsPlayer, unit) ~= true then return nil end
    local faction = plain(UnitFactionGroup, unit)
    local mine = E.MyFaction()
    if not E.FACTIONS[faction] or not E.FACTIONS[mine] or faction == mine then return nil end
    if plain(UnitIsDeadOrGhost, unit) == true then return nil end
    local name, second = plain(UnitName, unit)
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    -- Forever names have two parts; a realm name may come as the second value too
    local key = name
    if type(second) == "string" and second ~= "" then key = name .. " " .. second end
    local _, class = plain(UnitClass, unit)
    local level = plain(UnitLevel, unit)
    if type(level) ~= "number" then level = nil end
    return { key = key, name = name, level = level, class = type(class) == "string" and class or nil, faction = faction }
end

----------------------------------------------------------------------
-- texts
----------------------------------------------------------------------
function E.Danger(level)
    if level == -1 then return true end
    return type(level) == "number" and level >= E.MyLevel() + E.DANGER
end

function E.ClassName(class)
    if not class then return nil end
    local t = LOCALIZED_CLASS_NAMES_MALE
    if t and t[class] then return t[class] end
    return class:sub(1, 1) .. class:sub(2):lower()
end

local function hex(r, g, b) return string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255) end
function E.ClassHex(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if c then return c.colorStr or hex(c.r, c.g, c.b) end
    return "ffffffff"
end

-- "Name (34 Rogue)", the name in class colors
function E.Who(e)
    local lvl = e.level == -1 and "??" or (e.level and tostring(e.level)) or nil
    local cls = E.ClassName(e.class)
    local inner = table.concat({ lvl, cls }, " ")
    local s = "|c" .. E.ClassHex(e.class) .. e.name .. "|r"
    if inner ~= "" then s = s .. " (" .. inner .. ")" end
    return s
end

function E.Text(e)
    local s = e.faction .. " nearby: " .. E.Who(e)
    if e.by then s = s .. " |cffaaaaaa- seen by " .. e.by .. "|r" end
    return s
end

----------------------------------------------------------------------
-- the warning card (decision 524: a left click targets the enemy and puts the skull on him)
-- The visible rows are plain frames: they may come and go in combat. Over each row lies a secure button whose macro
-- ("/targetexact Name" + "/tm 8") can only be set out of combat. A card that appears in combat is not clickable
-- (hint "click after combat"); after the fight its button is armed. A plain shield over a row eats the clicks of a
-- button whose macro does not belong to the card shown there. Cards keep their row (no shifting), so an armed
-- button never ends up under another enemy.
----------------------------------------------------------------------
local holder, rows
local buttons, shields, armed = {}, {}, {}   -- per row: secure button, plain shield, full name of the macro
E.slots = {}                                   -- per row: { text, faction, danger, at, key, full } or nil

local function locked() return InCombatLockdown and InCombatLockdown() and true or false end

function E.Macro(full)
    return "/cleartarget\n/targetexact " .. full .. "\n/tm [exists] 8"
end

local function makeButton(i)
    local b = CreateFrame("Button", "OneMoreQuestEnemyNearClick" .. i, UIParent, "SecureActionButtonTemplate")
    -- the secure template fires on mouse down or up depending on the game setting (ActionButtonUseKeyDown)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type1", "macro")
    b:SetAllPoints(rows[i])
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel(20)
    b.row = i
    b:SetScript("PostClick", function(self, button, down)
        if down then return end
        if button == "RightButton" then E.Dismiss(self.row) end
    end)
    b:SetScript("OnEnter", function(self)
        local c = E.slots[self.row]
        if not (c and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(c.full or "?")
        GameTooltip:AddLine("Left click: target him and mark him with the skull.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Right click: close the card.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:Hide()
    buttons[i] = b
    local sh = CreateFrame("Frame", nil, UIParent)
    sh:SetFrameStrata("DIALOG")
    sh:SetAllPoints(rows[i])
    sh:EnableMouse(true)
    sh.row = i
    sh:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then E.Dismiss(self.row) end end)
    sh:Hide()
    shields[i] = sh
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "OneMoreQuestEnemyNear", UIParent)
    holder:SetSize(420, E.ROWS * 30)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -200)
    holder:SetFrameStrata("HIGH")
    rows = {}
    for i = 1, E.ROWS do
        local r = CreateFrame("Frame", nil, holder)
        r:SetSize(420, 28)
        r:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * 30)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0, 0, 0, 0.6)
        r.bg = bg
        local edge = r:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT")
        edge:SetWidth(4)
        edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        r.edge = edge
        local icon = r:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", r, "LEFT", 10, 0)
        r.icon = icon
        local skull = r:CreateTexture(nil, "ARTWORK")
        skull:SetSize(18, 18)
        skull:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        skull:SetTexture(E.SKULL)
        r.skull = skull
        local text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        text:SetPoint("RIGHT", skull, "LEFT", -6, 0)
        text:SetJustifyH("LEFT")
        r.text = text
        r:Hide()
        rows[i] = r
    end
    E._rows = rows
    if not locked() then for i = 1, E.ROWS do makeButton(i) end end
end

-- can the card in row i be clicked right now?
function E.Clickable(i)
    local c = E.slots[i]
    return c ~= nil and c.full ~= nil and armed[i] == c.full and buttons[i] ~= nil and buttons[i]:IsShown() and true or false
end

-- out of combat: every row's button gets the macro of its card, rows without a card lose theirs
function E.Arm()
    if locked() or not holder then return end
    for i = 1, E.ROWS do
        if not buttons[i] then makeButton(i) end
        local c, b = E.slots[i], buttons[i]
        if c and c.full then
            b:SetAttribute("macrotext1", E.Macro(c.full))
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

local function paint()
    if not holder then return end
    local t = now()
    for i = 1, E.ROWS do
        local r, c = rows[i], E.slots[i]
        if c then
            local age = t - c.at
            local danger = c.danger
            local text = c.text
            if c.full and not E.Clickable(i) and locked() then text = text .. " |cff888888(click after combat)|r" end
            r.text:SetText(text)
            if danger then r.text:SetTextColor(1, 0.25, 0.2) else r.text:SetTextColor(1, 0.82, 0) end
            if danger then r.edge:SetVertexColor(1, 0.1, 0.1) else r.edge:SetVertexColor(1, 0.6, 0.1) end
            r.icon:SetTexture(E.ICONS[c.faction] or E.SKULL)
            r.skull:SetShown(danger and true or false)
            r:SetAlpha(age > E.SHOW and math.max(0, 1 - (age - E.SHOW) / E.FADE) or 1)
            r:Show()
        else
            r:Hide()
        end
        -- a shown button whose macro is not the card's: the shield takes its clicks (plain frame, fine in combat)
        if shields[i] then
            local b = buttons[i]
            shields[i]:SetShown(b ~= nil and b:IsShown() and not E.Clickable(i))
        end
    end
end

-- the row for a new card: a free one, else the oldest card whose button does not hold it
local function freeRow()
    for i = 1, E.ROWS do if not E.slots[i] then return i end end
    local best
    for i = 1, E.ROWS do
        if not (locked() and E.Clickable(i)) and (not best or E.slots[i].at < E.slots[best].at) then best = i end
    end
    if best then return best end
    for i = 1, E.ROWS do
        if not best or E.slots[i].at < E.slots[best].at then best = i end
    end
    return best
end

function E.ShowCard(e)
    build()
    local i = freeRow()
    E.slots[i] = { text = E.Text(e), faction = e.faction, danger = E.Danger(e.level), at = now(), key = e.key,
        full = e.full or e.key }
    holder:Show()
    E.Arm()
    paint()
    return i
end

function E.Dismiss(i)
    E.slots[i] = nil
    E.Arm()
    paint()
end

function E.Expire()
    local t = now()
    local changed = false
    for i = 1, E.ROWS do
        local c = E.slots[i]
        if c then
            -- the mouse on a card holds it
            if rows[i]:IsMouseOver() or (buttons[i] and buttons[i]:IsMouseOver()) then c.at = t end
            if t - c.at > E.SHOW + E.FADE then E.slots[i] = nil; changed = true end
        end
    end
    if changed then E.Arm() end
    paint()
end

function E.HasCards()
    for i = 1, E.ROWS do if E.slots[i] then return true end end
    return false
end

function E.ClearCards()
    for i = 1, E.ROWS do E.slots[i] = nil end
    E.Arm()
    paint()
end

function E.PlaySound()
    if not E.SoundOn() or not PlaySound then return false end
    local id = (_G.SOUNDKIT and _G.SOUNDKIT[E.SOUND.kit]) or E.SOUND.id
    return (pcall(PlaySound, id, "SFX"))
end

----------------------------------------------------------------------
-- sightings
----------------------------------------------------------------------
-- e from E.Read (or a shared one with e.by); returns true when it warned
function E.Sighted(e, by)
    if not e or not E.Enabled() or E.Quiet() then return false end
    local t = now()
    local s = E.seen[e.key]
    if not s then s = { key = e.key }; E.seen[e.key] = s end
    s.name, s.faction = e.name, e.faction
    s.level = e.level or s.level
    s.class = e.class or s.class
    if by then
        -- my own sighting keeps counting longer than a shared one
        if not s.at or s.shared then s.at, s.shared, s.by = t, true, by end
    else
        s.at, s.shared, s.by = t, false, nil
    end
    if s.warnedAt and t - s.warnedAt < E.REPEAT then return false end
    s.warnedAt = t
    E.ShowCard({ key = s.key, name = s.name, level = s.level, class = s.class, faction = s.faction, by = by })
    E.PlaySound()
    if not by then E.Share(s) end
    E.UpdateBadge()
    return true
end

function E.Look(unit)
    if not E.Enabled() then return false end
    local e = E.Read(unit)
    if not e then return false end
    return E.Sighted(e)
end

-- the enemies seen lately: list sorted by name
function E.Nearby()
    local t, out = now(), {}
    for _, s in pairs(E.seen) do
        local keep = s.shared and E.SHARED_SIGHT or E.SIGHT
        if s.at and t - s.at <= keep then out[#out + 1] = s end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
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

function E.Scan()
    if not E.Enabled() or E.Quiet() then return end
    for _, u in ipairs(plateUnits()) do E.Look(u) end
    E.Look("target")
    E.Look("mouseover")
    for i = 1, 4 do E.Look("party" .. i .. "target") end
end

----------------------------------------------------------------------
-- the group: EN|protocol|key|name|level|class|faction|mapID
----------------------------------------------------------------------
local function myMap()
    return C_Map and C_Map.GetBestMapForUnit and (plain(C_Map.GetBestMapForUnit, "player")) or 0
end

function E.Share(s)
    if not E.ShareOn() or not OMQ.GetChannel or not OMQ:GetChannel() then return false end
    return OMQ:Send("EN", s.key, s.name, s.level or "", s.class or "", s.faction, myMap()) and true or false
end

OMQ:RegisterMessage("EN", function(f, sender)
    if not E.ShareOn() then return end
    local key, name, level, class, faction, map = f[1], f[2], tonumber(f[3]), f[4], f[5], tonumber(f[6])
    if not key or key == "" or not name or not E.FACTIONS[faction] or faction == E.MyFaction() then return end
    local who = tostring(sender or "?"):match("^[^-]+") or "?"
    local me = OMQ.GetSelf and OMQ:GetSelf()
    if me and me.name == who then return end
    local here = myMap()
    if map and map ~= 0 and here ~= 0 and map ~= here then return end
    E.Sighted({ key = key, name = name, level = level, class = class ~= "" and class or nil, faction = faction }, who)
end)

----------------------------------------------------------------------
-- the red number on the minimap icon
----------------------------------------------------------------------
local badge
local function buildBadge()
    if badge then return badge end
    local button = _G.OneMoreQuestMinimapButton
    if not button then return nil end
    badge = CreateFrame("Frame", nil, button)
    badge:SetSize(16, 16)
    badge:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    badge:SetFrameLevel((plain(button.GetFrameLevel, button) or 8) + 3)
    local dot = badge:CreateTexture(nil, "ARTWORK")
    dot:SetAllPoints()
    dot:SetTexture("Interface\\COMMON\\Indicator-Red")
    local num = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    num:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge.num = num
    if badge.EnableMouse then badge:EnableMouse(true) end
    badge:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Enemies nearby", 1, 0.25, 0.2)
        for _, s in ipairs(E.Nearby()) do
            local line = E.Who(s)
            if s.by then line = line .. " |cffaaaaaa- seen by " .. s.by .. "|r" end
            GameTooltip:AddLine(line, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    badge:Hide()
    return badge
end

E.testUntil = nil
function E.UpdateBadge()
    local n = #E.Nearby()
    if E.testUntil and now() < E.testUntil then n = math.max(n, 2) else E.testUntil = nil end
    local b = buildBadge()
    E.count = n
    if not b then return n end
    if n > 0 and E.Enabled() then
        b.num:SetText(tostring(n))
        b:Show()
    else
        b:Hide()
    end
    return n
end

----------------------------------------------------------------------
-- the game's enemy nameplates: switched on outside combat, old value kept
----------------------------------------------------------------------
local function getCVar(k)
    if C_CVar and C_CVar.GetCVar then return (plain(C_CVar.GetCVar, k)) end
    return (plain(GetCVar, k))
end
local function setCVar(k, v)
    if InCombatLockdown and InCombatLockdown() then return false end
    if C_CVar and C_CVar.SetCVar then return (pcall(C_CVar.SetCVar, k, v)) end
    if SetCVar then return (pcall(SetCVar, k, v)) end
    return false
end

function E.ApplyCVar()
    if not OMQ.db then return end
    if E.Enabled() then
        local cur = getCVar(E.CVAR)
        if cur ~= nil and tostring(cur) ~= "1" then
            if setCVar(E.CVAR, "1") and OMQ.db.enemyCVar == nil then OMQ.db.enemyCVar = tostring(cur) end
        end
    elseif OMQ.db.enemyCVar ~= nil then
        if setCVar(E.CVAR, OMQ.db.enemyCVar) then OMQ.db.enemyCVar = nil end
    end
end

function E.SetEnabled(on)
    OMQ.db.options.enemyWarn = on and true or false
    if not on then E.ClearCards() end
    E.ApplyCVar()
    E.UpdateBadge()
end

----------------------------------------------------------------------
-- driver
----------------------------------------------------------------------
local driver = CreateFrame("Frame")
local sinceScan = 0
driver:SetScript("OnUpdate", function(_, dt)
    if not OMQ.db then return end
    if E.HasCards() then E.Expire() end
    sinceScan = sinceScan + (dt or 0)
    if sinceScan < E.SCAN then return end
    sinceScan = 0
    E.Scan()
    E.UpdateBadge()
end)
for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
    pcall(driver.RegisterEvent, driver, ev)
end
driver:SetScript("OnEvent", function(_, event, unit)
    if not OMQ.db then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        E.Look(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        E.Look("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        E.Look("mouseover")
    else
        E.ApplyCVar()
        if E.HasCards() then E.Arm(); paint() end
    end
end)

function E.Test()
    local lvl = E.MyLevel()
    local mine = E.MyFaction()
    local other = mine == "Horde" and "Alliance" or "Horde"
    E.ShowCard({ key = "test2", name = "Grimgor", level = lvl + 6, class = "WARRIOR", faction = other, by = "Willi" })
    E.ShowCard({ key = "test1", name = "Testname", level = math.max(1, lvl), class = "ROGUE", faction = other })
    E.PlaySound()
    E.testUntil = now() + E.SHOW
    E.UpdateBadge()
end

OMQ:RegisterCommand("enemy", function(arg)
    local a, b = (arg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    local function onoff(v) return v and "on" or "off" end
    if a == "on" or a == "off" then
        E.SetEnabled(a == "on")
        OMQ:Print("enemy player warning: " .. a)
        OMQ:Fire("SETTINGS_CHANGED")
    elseif (a == "sound" or a == "share") and (b == "on" or b == "off") then
        OMQ.db.options[a == "sound" and "enemySound" or "enemyShare"] = b == "on"
        OMQ:Print("enemy player warning " .. a .. ": " .. b)
        OMQ:Fire("SETTINGS_CHANGED")
    elseif a == "test" then
        E.Test()
        OMQ:Print("enemy player warning: two sample cards and the number on the minimap icon")
    elseif a == "list" then
        local list = E.Nearby()
        if #list == 0 then OMQ:Print("no enemy players seen in the last " .. E.SIGHT .. " seconds") end
        for _, s in ipairs(list) do OMQ:Print(s.faction .. ": " .. E.Who(s) .. (s.by and (" - seen by " .. s.by) or "")) end
    else
        OMQ:Print(("/omq enemy on | off - warn about players of the other faction nearby (now: %s, sound %s, share %s)")
            :format(onoff(E.Enabled()), onoff(E.SoundOn()), onoff(E.ShareOn())))
        OMQ:Print("/omq enemy sound on|off, share on|off, test, list; enemy nameplates: " .. tostring(getCVar(E.CVAR)))
    end
end)
