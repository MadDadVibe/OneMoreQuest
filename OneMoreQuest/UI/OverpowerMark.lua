-- One More Quest: Overpower mark (decision 692)
-- A warrior's Overpower can only be used on the mob that dodged. With three or more mobs it is hard to tell which one
-- it was, so the nameplate of that mob glows yellow, with the Overpower icon left of its health bar and a 5 second
-- sweep. Looks like the Shadow Word: Death kill glow of the priest (UI/KillGlow.lua).
--
-- How the dodge is found without the combat log (registering it brings the game's "blocked" popup on WoW Forever):
--   * UNIT_COMBAT(unit, "DODGE") says that this unit dodged an attack. It comes for the target, and for nameplate units
--     when the game sends it for them (Cleave / Whirlwind on side mobs; /omq op debug shows what arrived);
--   * the mark sticks to that unit's nameplate frame, so it stays when the target changes;
--   * a dodge only counts as mine when Overpower turns usable right after it (another warrior's dodge does not light up
--     my Overpower). Where the usability cannot be read, or outside Battle Stance (there the game never says usable),
--     the dodge counts as it is.
-- The mark ends after K.WINDOW seconds, when Overpower is cast, or when the nameplate goes away (mob dead / out of range).
-- The icon cannot cast (nameplates take no secure buttons); a click on the plate targets the mob, then press Overpower.
-- Option: options.overpowerMark (default on). /omq op on | off | test | debug.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local K = {}
OMQ.OverpowerMark = K

K.IDS = { 7384, 7887, 11584, 11585 }      -- Overpower ranks; the spell book lookup adds what Forever uses
-- string.lower leaves the German capital Ü as it is: both spellings
K.NAMES = { ["overpower"] = true, ["überwältigen"] = true, ["Überwältigen"] = true }
K.NAME = "Overpower"
K.ICON_ID = 132223                        -- ability_meleedamage, the spell's icon in every language
K.ICON = "Interface\\Icons\\Ability_MeleeDamage"
K.WINDOW = 5                              -- seconds Overpower stays usable after the dodge
K.CONFIRM = 0.5                           -- seconds a dodge waits for Overpower to turn usable
K.PAD = 10
K.ICON_SIZE = 22
K.COLOR = { 1.0, 0.82, 0.1 }
K.TICK = 0.05
K.LOG = 15
K.FALLBACK_WIDTH = 140

local MEDIA = "Interface\\AddOns\\OneMoreQuest\\Media\\"

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok and not secret(v) then return v end
end

function K.Enabled()
    return not (OMQ.db and OMQ.db.options and OMQ.db.options.overpowerMark == false)
end

----------------------------------------------------------------------
-- the spell
----------------------------------------------------------------------
local bookKnown = {}
local spellId

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local n = plain(C_Spell.GetSpellName, id)
        if n then return n end
    end
    return plain(GetSpellInfo, id)
end

local function bookMatch(name, icon)
    if type(name) == "string" and not secret(name) and K.NAMES[name:lower()] then return true end
    if icon == K.ICON_ID then return true end
    return type(icon) == "string" and not secret(icon) and icon:lower():find("ability_meleedamage", 1, true) ~= nil
end

function K.BookIds()
    local out = {}
    local SB = C_SpellBook
    if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local ok = pcall(function()
            for line = 1, SB.GetNumSpellBookSkillLines() do
                local info = SB.GetSpellBookSkillLineInfo(line)
                for i = 1, (info and info.numSpellBookItems) or 0 do
                    local item = SB.GetSpellBookItemInfo((info.itemIndexOffset or 0) + i, bank)
                    if item and item.spellID and not item.isPassive and not item.isOffSpec
                        and bookMatch(item.name or spellName(item.spellID), item.iconID) then
                        out[#out + 1] = item.spellID
                    end
                end
            end
        end)
        if not ok then out = {} end
    elseif GetSpellBookItemName and GetNumSpellTabs and GetSpellTabInfo then
        pcall(function()
            local _, _, offset, num = GetSpellTabInfo(GetNumSpellTabs())
            for i = 1, (offset or 0) + (num or 0) do
                local name = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
                local _, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
                local icon = GetSpellBookItemTexture and GetSpellBookItemTexture(i, BOOKTYPE_SPELL or "spell")
                if type(id) == "number" and bookMatch(name, icon) then out[#out + 1] = id end
            end
        end)
    end
    bookKnown = {}
    for _, id in ipairs(out) do bookKnown[id] = true end
    return out
end

local function known(id)
    return bookKnown[id] == true or plain(IsPlayerSpell, id) == true or plain(IsSpellKnown, id) == true
end

local isOverpower = {}
function K.Refresh()
    local ids, seen = {}, {}
    local function add(id)
        if type(id) == "number" and not secret(id) and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    for _, id in ipairs(K.IDS) do add(id) end
    for _, id in ipairs(K.BookIds()) do add(id) end
    local best
    for _, id in ipairs(ids) do
        isOverpower[id] = true
        if known(id) then best = id end
    end
    if best or not InCombatLockdown() then spellId = best end
    return spellId
end

function K.SpellId() return spellId end

-- true / false when the game says it, nil when it cannot be read
function K.Usable()
    if not spellId then return nil end
    local v
    if C_Spell and C_Spell.IsSpellUsable then v = plain(C_Spell.IsSpellUsable, spellId) end
    if v == nil and IsUsableSpell then v = plain(IsUsableSpell, spellId) end
    if type(v) ~= "boolean" then return nil end
    return v
end

-- Battle Stance is the first stance of a warrior
function K.BattleStance()
    local f = plain(GetShapeshiftForm)
    if type(f) ~= "number" then return nil end
    return f == 1
end

----------------------------------------------------------------------
-- dodges and marks
----------------------------------------------------------------------
local pending = {}   -- { plate, unit, at }
local marks = {}     -- plate -> { at, unit, frame }
local log = {}
local testUntil
local clock = 0

local function note(text)
    table.insert(log, 1, ("%.1f %s"):format(GetTime(), text))
    while #log > K.LOG do table.remove(log) end
end
function K.Log() return log end

local function plateOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    return plain(C_NamePlate.GetNamePlateForUnit, unit)
end

-- the plate's own unit token (nameplateN), so that a recycled plate is let go when its unit is removed
local function tokenOf(plate, unit)
    if type(unit) == "string" and unit:find("^nameplate") then return unit end
    local ok, t = pcall(function() return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit) end)
    if ok and type(t) == "string" and not secret(t) then return t end
end

function K.OnDodge(unit)
    if not (spellId and K.Enabled()) then return end
    local plate = plateOf(unit)
    note(("DODGE %s, plate %s"):format(tostring(unit), plate and "yes" or "no"))
    if not plate then return end
    local now = GetTime()
    for _, p in ipairs(pending) do
        if p.plate == plate then p.at = now; return end
    end
    pending[#pending + 1] = { plate = plate, unit = tokenOf(plate, unit), at = now }
end

-- the mark frame: yellow glow around the health bar, icon with a sweep right of it
local pool = {}
local function healthBar(plate)
    local ok, hb = pcall(function()
        local uf = plate.UnitFrame
        if not uf then return nil end
        return uf.healthBar or uf.HealthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar) or uf
    end)
    if ok and type(hb) == "table" then return hb end
    return plate
end

local function newFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(K.FALLBACK_WIDTH, 30)
    f:Hide()
    local r, g, b = K.COLOR[1], K.COLOR[2], K.COLOR[3]
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture(MEDIA .. "Glow_Soft.tga")
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(r, g, b, 0.9)
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", K.ICON_SIZE, 0)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.halo = f:CreateTexture(nil, "BORDER")
    f.halo:SetTexture(MEDIA .. "Glow_Soft.tga")
    f.halo:SetBlendMode("ADD")
    f.halo:SetVertexColor(r, g, b, 1)
    f.halo:SetSize(K.ICON_SIZE * 1.9, K.ICON_SIZE * 1.9)
    f.halo:SetPoint("CENTER", f, "LEFT", K.ICON_SIZE / 2, 0)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexture(K.ICON)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon:SetSize(K.ICON_SIZE - 4, K.ICON_SIZE - 4)
    f.icon:SetPoint("CENTER", f, "LEFT", K.ICON_SIZE / 2, 0)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
    if ok and cd then
        f.cd = cd
        pcall(function()
            cd:SetAllPoints(f.icon)
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
            if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        end)
    end
    return f
end

local function release(f)
    if not f then return end
    f:Hide()
    pcall(f.SetParent, f, UIParent)
    pool[#pool + 1] = f
end

local function place(f, plate, at)
    local ok = pcall(function()
        f:SetParent(plate or UIParent)
        f:ClearAllPoints()
        if plate then
            local hb = healthBar(plate)
            -- the icon sits left of the health bar like the Shadow Word: Death icon (MadDadVibe, fix 694), the glow around the bar
            f:SetPoint("TOPLEFT", hb, "TOPLEFT", -K.PAD - K.ICON_SIZE, K.PAD)
            f:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", K.PAD, -K.PAD)
        else
            f:SetSize(K.FALLBACK_WIDTH, 30)
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        end
    end)
    if not ok then return false end
    if f.SetIgnoreParentAlpha then pcall(f.SetIgnoreParentAlpha, f, true) end
    if plate then
        local lvl = plain(plate.GetFrameLevel, plate)
        if type(lvl) == "number" then pcall(f.SetFrameLevel, f, lvl + 5) end
    end
    if f.cd then pcall(f.cd.SetCooldown, f.cd, at, K.WINDOW) end
    f:Show()
    return true
end

local function addMark(plate, unit, at)
    local m = marks[plate]
    if not m then
        m = { frame = table.remove(pool) or newFrame() }
        marks[plate] = m
    end
    m.at, m.unit = at, unit or m.unit
    if not place(m.frame, plate, at) then release(m.frame); marks[plate] = nil; return end
    note(("mark on %s"):format(tostring(m.unit or "plate")))
end

function K.Clear(plate)
    if plate then
        if marks[plate] then release(marks[plate].frame); marks[plate] = nil end
        return
    end
    for p, m in pairs(marks) do release(m.frame); marks[p] = nil end
    pending = {}
end

function K.Marks()
    local n = 0
    for _ in pairs(marks) do n = n + 1 end
    return n
end
function K.MarkOn(plate) return marks[plate] ~= nil and marks[plate].frame or nil end

-- a dodge waits up to K.CONFIRM s for Overpower to turn usable; usability unreadable or outside Battle Stance: counts
function K.Update()
    local now = GetTime()
    if #pending > 0 then
        local usable, battle = K.Usable(), K.BattleStance()
        local keep = {}
        for _, p in ipairs(pending) do
            if usable == true or usable == nil or battle == false then
                addMark(p.plate, p.unit, p.at)
            elseif now - p.at < K.CONFIRM then
                keep[#keep + 1] = p
            else
                note("dodge dropped: Overpower did not turn usable (someone else's attack)")
            end
        end
        pending = keep
    end
    for plate, m in pairs(marks) do
        local over = now - m.at >= K.WINDOW
        if not over and m.unit and plain(UnitIsDead, m.unit) == true then over = true end
        if over then K.Clear(plate) end
    end
    if testUntil and now >= testUntil then testUntil = nil end
end

function K.Animate(dt)
    clock = clock + (dt or 0)
    local a = 0.75 + 0.25 * math.sin(clock * 5)
    for _, m in pairs(marks) do m.frame.glow:SetAlpha(a); m.frame.halo:SetAlpha(a) end
end

function K.Test()
    local plate = plateOf("target")
    testUntil = GetTime() + K.WINDOW
    if plate then
        addMark(plate, tokenOf(plate, "target"), GetTime())
    else
        local key = K.TEST_KEY or {}
        K.TEST_KEY = key
        local m = marks[key] or { frame = table.remove(pool) or newFrame() }
        marks[key] = m
        m.at = GetTime()
        place(m.frame, nil, m.at)
    end
end

----------------------------------------------------------------------
-- driver: only warriors who know Overpower listen
----------------------------------------------------------------------
local active = false
local driver = CreateFrame("Frame")
local sinceUpdate = 0

local function isWarrior()
    local _, cls = UnitClass("player")
    return cls == "WARRIOR"
end

function K.Active() return active end

function K.Check()
    if not isWarrior() then active = false; K.Clear(); return end
    K.Refresh()
    active = K.Enabled() and spellId ~= nil
    if not active then K.Clear() end
end

driver:SetScript("OnUpdate", function(_, dt)
    if not active and not testUntil then return end
    if next(marks) == nil and #pending == 0 then return end
    K.Animate(dt)
    sinceUpdate = sinceUpdate + dt
    if sinceUpdate >= K.TICK then sinceUpdate = 0; K.Update() end
end)

for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_REGEN_ENABLED",
    "UNIT_COMBAT", "NAME_PLATE_UNIT_REMOVED", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(driver.RegisterEvent, driver, e)
end

driver:SetScript("OnEvent", function(_, event, unit, a2, a3)
    if not OMQ.db then return end
    if event == "UNIT_COMBAT" then
        if active and not secret(a2) and a2 == "DODGE" and type(unit) == "string" and not secret(unit) then
            K.OnDodge(unit)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if next(marks) == nil then return end
        local plate = plateOf(unit)
        for p, m in pairs(marks) do
            if p == plate or (m.unit ~= nil and m.unit == unit) then K.Clear(p) end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Overpower used: the proc is gone
        if unit == "player" and next(marks) ~= nil and not secret(a3) and isOverpower[a3] then
            note("Overpower cast")
            K.Clear()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        K.Check()
    else
        K.Check()
    end
end)

function K.SetEnabled(on)
    OMQ.db.options.overpowerMark = on and true or false
    K.Check()
end

OMQ:RegisterCommand("op", function(arg)
    arg = (arg or ""):lower():match("^%s*(%S*)") or ""
    if arg == "on" or arg == "off" then
        K.SetEnabled(arg == "on")
        OMQ:Print("Overpower mark: " .. arg)
        OMQ:Fire("SETTINGS_CHANGED")
    elseif arg == "test" then
        K.Test()
        OMQ:Print("Overpower mark: sample on the target's nameplate for " .. K.WINDOW .. " seconds")
    elseif arg == "debug" then
        K.Refresh()
        OMQ:Print(("spell %s (%s), usable %s, battle stance %s, option %s, active %s, marks %d, target nameplate %s"):format(
            tostring(spellId), tostring(spellId and spellName(spellId)), tostring(K.Usable()), tostring(K.BattleStance()),
            K.Enabled() and "on" or "off", tostring(active), K.Marks(), plateOf("target") and "yes" or "no"))
        if #log == 0 then
            OMQ:Print("no dodge seen yet (enemy nameplates must be switched on)")
        else
            for i = #log, 1, -1 do OMQ:Print(log[i]) end
        end
    else
        OMQ:Print("/omq op on | off - the nameplate of the mob that dodged glows yellow with the Overpower icon (now: "
            .. (K.Enabled() and "on" or "off") .. ")")
        OMQ:Print("/omq op test - a sample for " .. K.WINDOW .. " seconds; /omq op debug - spell, usability and the last dodges")
    end
end)
