-- One More Quest: Shadow Word: Death kill glow (decision 520)
-- A priest who knows Shadow Word: Death sees the target's nameplate glow purple, with the spell's icon over it,
-- when the spell would kill the target. Nothing else on screen changes (no target frame, no chat line).
--
-- How it works without reading the target's life: on WoW Forever UnitHealth("target") is a secret value in combat,
-- Lua cannot compare it with anything. A StatusBar still takes it as its maximum and does the comparison itself:
--   * a very long invisible StatusBar (K.BAR px) has max = target life and value = the spell's damage, so its fill
--     only reaches the bar's right end when damage >= life;
--   * the glow hangs on the right end of the fill, inside a window at the bar's right end that clips its children,
--     so it is on screen only when the spell is lethal. The addon itself never learns the answer.
-- The damage is the low end of the spell tooltip ("X to Y Shadow damage"), read whenever the tooltip can be read,
-- times K.SHADOWFORM_BONUS while Shadowform is on. Low end, so the glow never lies; it may come a bit late.
-- Option: options.killGlow (default on). /omq swd test | debug | on | off.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local K = {}
OMQ.KillGlow = K

K.IDS = { 32379, 32996, 48157, 48158 }  -- Shadow Word: Death ranks; the name lookup adds what Forever uses
K.NAMES = { ["shadow word: death"] = true, ["schattenwort: tod"] = true }
K.NAME = "Shadow Word: Death"
K.ICON_ID = 136149                       -- spell_shadow_demonicfortitude, the spell's icon in every language
K.ICON = "Interface\\Icons\\Spell_Shadow_DemonicFortitude"
K.SHADOWFORM = 15473
K.SHADOWFORM_FORM = 28                   -- GetShapeshiftFormID() in Shadowform
K.SHADOWFORM_BONUS = 1.15
K.BAR = 100000                           -- px; longer = the glow starts closer to exactly lethal
K.PAD = 10                               -- glow room around the nameplate's health bar
K.ICON_SIZE = 22
K.COLOR = { 0.75, 0.35, 1.0 }
K.TICK = 0.05
K.REFRESH = 2
K.TEST = 5
K.FALLBACK_WIDTH = 140

local MEDIA = "Interface\\AddOns\\OneMoreQuest\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok and not secret(v) then return v end
end

function K.Enabled()
    return not (OMQ.db and OMQ.db.options and OMQ.db.options.killGlow == false)
end

----------------------------------------------------------------------
-- the spell: highest known rank and its damage, kept from the last readable tooltip
----------------------------------------------------------------------
local spell = {}       -- id, lo, hi, desc
local formSeen = false -- last readable Shadowform state
local bookKnown = {}    -- spell ids found in the spell book

function K.ParseDamage(desc)
    if type(desc) ~= "string" then return nil end
    desc = desc:gsub("(%d),(%d)", "%1%2")
    local lo, hi = desc:match("(%d+) to (%d+)[%a ]-[Ss]hadow damage")
    if not lo then lo = desc:match("(%d+)[%a ]-[Ss]hadow damage"); hi = lo end
    if not lo then lo, hi = desc:match("(%d+) bis (%d+)") end
    if not lo then lo, hi = desc:match("(%d+)%s*%-%s*(%d+)") end
    lo, hi = tonumber(lo), tonumber(hi)
    if not lo then return nil end
    return lo, math.max(hi or lo, lo)
end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local n = plain(C_Spell.GetSpellName, id)
        if n then return n end
    end
    return plain(GetSpellInfo, id)
end

local function description(id)
    if C_Spell and C_Spell.GetSpellDescription then
        local d = plain(C_Spell.GetSpellDescription, id)
        if d then return d end
    end
    return plain(GetSpellDescription, id)
end

local function known(id)
    return bookKnown[id] == true or plain(IsPlayerSpell, id) == true or plain(IsSpellKnown, id) == true
end

-- WoW Forever has its own spell ids: the spell book is searched by name (English, German) or by the icon
local function bookMatch(name, icon)
    if type(name) == "string" and not secret(name) and K.NAMES[name:lower()] then return true end
    if icon == K.ICON_ID then return true end
    return type(icon) == "string" and not secret(icon) and icon:lower():find("demonicfortitude", 1, true) ~= nil
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

local function candidates()
    local ids, seen = {}, {}
    local function add(id)
        if type(id) == "number" and not secret(id) and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    for _, id in ipairs(K.IDS) do add(id) end
    for _, id in ipairs(K.BookIds()) do add(id) end
    local name = spellName(K.IDS[1]) or K.NAME
    if C_Spell and C_Spell.GetSpellInfo then
        local info = plain(C_Spell.GetSpellInfo, name)
        if type(info) == "table" then add(info.spellID) end
    end
    if GetSpellInfo then
        local ok, _, _, _, _, _, _, id = pcall(GetSpellInfo, name)
        if ok then add(id) end
    end
    return ids
end

function K.Refresh()
    local best, any, unread = nil, false, false
    for _, id in ipairs(candidates()) do
        if known(id) then
            any = true
            local desc = description(id)
            local lo, hi = K.ParseDamage(desc)
            if lo and (not best or lo > best.lo) then best = { id = id, lo = lo, hi = hi, desc = desc } end
            if not lo then unread = true end
        end
    end
    -- a known rank whose tooltip cannot be read now (combat): keep a stronger rank read before
    if best and unread and spell.lo and spell.lo > best.lo then best = nil end
    if best then
        spell = best
    elseif not any and not InCombatLockdown() then
        spell = {}   -- out of combat nothing is hidden: really not known (other class, too low, respec)
    end
end

function K.Shadowform()
    if not OMQ.AurasHidden() and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, K.SHADOWFORM)
        if ok and not secret(a) then formSeen = a ~= nil; return formSeen end
    end
    local form = plain(GetShapeshiftFormID)
    if type(form) == "number" then formSeen = form == K.SHADOWFORM_FORM; return formSeen end
    return formSeen
end

function K.Spell() return spell end

-- the damage the glow is based on, or nil
function K.Estimate()
    if not spell.lo then return nil end
    local d = spell.lo * (K.Shadowform() and K.SHADOWFORM_BONUS or 1)
    if d <= 0 then return nil end
    return d
end

----------------------------------------------------------------------
-- the lethal window on the target's nameplate
----------------------------------------------------------------------
local window, bar, content, glow, halo, icon
local width = K.FALLBACK_WIDTH
local anchoredTo
local clock = 0
local testUntil

local function build()
    if window then return end
    window = CreateFrame("Frame", nil, UIParent)
    window:SetClipsChildren(true)
    window:SetSize(K.FALLBACK_WIDTH, 40)
    window:Hide()

    bar = CreateFrame("StatusBar", nil, window)
    bar:SetPoint("TOPRIGHT")
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetWidth(K.BAR)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local fill = bar:GetStatusBarTexture()
    content = CreateFrame("Frame", nil, bar)
    content:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    content:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    content:SetWidth(K.FALLBACK_WIDTH)

    local r, g, b = K.COLOR[1], K.COLOR[2], K.COLOR[3]
    glow = content:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(MEDIA .. "Glow_Soft.tga")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(r, g, b, 0.9)
    glow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -K.ICON_SIZE)
    glow:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    halo = content:CreateTexture(nil, "BORDER")
    halo:SetTexture(MEDIA .. "Glow_Soft.tga")
    halo:SetBlendMode("ADD")
    halo:SetVertexColor(r, g, b, 1)
    halo:SetSize(K.ICON_SIZE * 1.9, K.ICON_SIZE * 1.9)
    halo:SetPoint("CENTER", content, "TOP", 0, -K.ICON_SIZE / 2)

    icon = content:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(K.ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(K.ICON_SIZE - 4, K.ICON_SIZE - 4)
    icon:SetPoint("CENTER", content, "TOP", 0, -K.ICON_SIZE / 2)

    window:SetScript("OnSizeChanged", function()
        local w = plain(window.GetWidth, window)
        if type(w) ~= "number" or w <= 0 then w = K.FALLBACK_WIDTH end
        width = w
        content:SetWidth(w)
    end)
end

-- the health bar of a nameplate (Blizzard's plates), else the plate itself
local function healthBar(plate)
    local ok, hb = pcall(function()
        local uf = plate.UnitFrame
        if not uf then return nil end
        return uf.healthBar or uf.HealthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar) or uf
    end)
    if ok and type(hb) == "table" then return hb end
    return plate
end

local function anchor(plate)
    if anchoredTo == plate then return true end
    local hb = healthBar(plate)
    local ok = pcall(function()
        window:SetParent(plate)
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", hb, "TOPLEFT", -K.PAD, K.PAD + K.ICON_SIZE)
        window:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", K.PAD, -K.PAD)
    end)
    if not ok then return false end
    if window.SetIgnoreParentAlpha then pcall(window.SetIgnoreParentAlpha, window, true) end
    local lvl = plain(plate.GetFrameLevel, plate)
    if type(lvl) == "number" then pcall(window.SetFrameLevel, window, lvl + 5) end
    anchoredTo = plate
    local w = plain(window.GetWidth, window)
    if type(w) == "number" and w > 0 then width = w; content:SetWidth(w) end
    return true
end

function K.Hide()
    if window then window:Hide() end
end

-- the comparison happens inside the StatusBar: max = life (secret), value = damage scaled so that any part of the
-- content inside the window means damage >= life
local function feed(damage)
    bar:SetMinMaxValues(0, UnitHealth("target"))
    bar:SetValue(damage * (1 - width / K.BAR))
end

local function targetOk()
    return UnitExists("target") and plain(UnitIsDead, "target") ~= true
        and plain(UnitCanAttack, "player", "target") ~= false
end

function K.Update()
    if not window then return end
    local testing = testUntil ~= nil and GetTime() < testUntil
    if not testing then testUntil = nil end
    local damage = K.Enabled() and K.Estimate()
    if not testing and (not damage or not targetOk()) then return K.Hide() end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and plain(C_NamePlate.GetNamePlateForUnit, "target")
    if not plate then
        anchoredTo = nil
        if not testing then return K.Hide() end
        window:SetParent(UIParent)
        window:ClearAllPoints()
        window:SetSize(K.FALLBACK_WIDTH, 40)
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        width = K.FALLBACK_WIDTH
        content:SetWidth(width)
    elseif not anchor(plate) then
        return K.Hide()
    end
    if testing then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        window:Show()
    else
        window:SetShown((pcall(feed, damage)))
    end
end

function K.Animate(dt)
    clock = clock + (dt or 0)
    if content then content:SetAlpha(0.75 + 0.25 * math.sin(clock * 4)) end
end

function K.Test()
    build()
    testUntil = GetTime() + K.TEST
    anchoredTo = nil
    K.Update()
end

-- for tests and /omq swd debug
function K.Parts() return window, bar, content end
function K.Width() return width end

----------------------------------------------------------------------
-- driver: only priests who know the spell run the update
----------------------------------------------------------------------
local active = false
local driver = CreateFrame("Frame")
local sinceUpdate, sinceRefresh = 0, 0

local function isPriest()
    local _, cls = UnitClass("player")
    return cls == "PRIEST"
end

function K.Active() return active end

function K.Check()
    if not isPriest() then active = false; K.Hide(); return end
    K.Refresh()
    active = K.Enabled() and spell.lo ~= nil
    if active then build() else K.Hide() end
end

driver:SetScript("OnUpdate", function(_, dt)
    if not active and not testUntil then return end
    sinceRefresh = sinceRefresh + dt
    if sinceRefresh >= K.REFRESH then sinceRefresh = 0; K.Refresh() end
    sinceUpdate = sinceUpdate + dt
    K.Animate(dt)
    if sinceUpdate >= K.TICK then sinceUpdate = 0; K.Update() end
end)

for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_REGEN_ENABLED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "UPDATE_SHAPESHIFT_FORM" }) do
    pcall(driver.RegisterEvent, driver, e)
end
driver:SetScript("OnEvent", function(_, event)
    if not OMQ.db then return end
    if event == "PLAYER_TARGET_CHANGED" or event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        anchoredTo = nil
        if active or testUntil then K.Update() end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        if active then K.Update() end
    else
        K.Check()
    end
end)

function K.SetEnabled(on)
    OMQ.db.options.killGlow = on and true or false
    K.Check()
end

OMQ:RegisterCommand("swd", function(arg)
    arg = (arg or ""):lower():match("^%s*(%S*)") or ""
    if arg == "on" or arg == "off" then
        K.SetEnabled(arg == "on")
        OMQ:Print("Shadow Word: Death kill glow: " .. arg)
        OMQ:Fire("SETTINGS_CHANGED")
    elseif arg == "test" then
        K.Test()
        OMQ:Print("Shadow Word: Death kill glow: sample on the target's nameplate for " .. K.TEST .. " seconds")
    elseif arg == "debug" then
        K.Refresh()
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and plain(C_NamePlate.GetNamePlateForUnit, "target")
        OMQ:Print(("spell %s, damage %s-%s, shadowform %s, used %s, option %s, active %s"):format(tostring(spell.id),
            tostring(spell.lo), tostring(spell.hi), tostring(K.Shadowform()), tostring(K.Estimate()),
            K.Enabled() and "on" or "off", tostring(active)))
        local found = {}
        for _, id in ipairs(candidates()) do if known(id) then found[#found + 1] = id .. " (" .. tostring(spellName(id)) .. ")" end end
        OMQ:Print("known ranks: " .. (#found > 0 and table.concat(found, ", ") or "none") .. "; tooltip: " .. tostring(spell.desc or (#found > 0 and description(tonumber(found[1]:match("%d+"))))))
        OMQ:Print(("target nameplate %s (enemy nameplates must be switched on), window width %s"):format(
            plate and "yes" or "no", tostring(width)))
    else
        OMQ:Print("/omq swd on | off - the target's nameplate glows when Shadow Word: Death would kill it (now: "
            .. (K.Enabled() and "on" or "off") .. ")")
        OMQ:Print("/omq swd test - a sample for " .. K.TEST .. " seconds; /omq swd debug - rank, tooltip and damage used")
    end
end)
