-- One More Quest: the Battle Shout card for clients where rage is secret (decision 212)
-- On WoW Forever power values are secret like mana, so "at least 15 rage" cannot be compared.
-- Like the mana card, the card's transparency follows a step curve on the rage percentage
-- (UnitPowerPercent with a curve): invisible below 15 percent (15 of 100 rage), visible above.
-- Everything readable gates the card: Battle Shout learned, not on the warrior (auras are readable
-- out of combat), not in combat, buff alerts on, no snooze. A click casts Battle Shout.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local MIN_PCT = 0.15
local RC = {}
OMQ.RageCard = RC

local card, curve, curveError
local driven = false

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function rageType() return Enum and Enum.PowerType and Enum.PowerType.Rage or 1 end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function knows(id)
    if IsPlayerSpell then return IsPlayerSpell(id) end
    if IsSpellKnown then return IsSpellKnown(id) end
    return false
end

local function group()
    for _, g in ipairs(OMQ.buffGroups and OMQ.buffGroups.WARRIOR or {}) do
        if g.id == "battleshout" then return g end
    end
end

local function buildCurve()
    if not UnitPowerPercent then return nil, "UnitPowerPercent is missing" end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil, "C_CurveUtil.CreateCurve is missing" end
    local c = C_CurveUtil.CreateCurve()
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step and c.SetType then c:SetType(Enum.LuaCurveType.Step) end
    c:AddPoint(0, 0)
    c:AddPoint(MIN_PCT, 1)
    c:AddPoint(1, 1)
    return c
end
RC._buildCurve = buildCurve

local function build()
    local parent = _G.OneMoreQuestAlerts
    if not parent then return end
    card = CreateFrame("Button", "OneMoreQuestRageCard", UIParent, "SecureActionButtonTemplate")
    card:SetSize(M.CARD_W or 330, M.CARD_H or 50)
    card:SetScale(1.2)
    card:SetFrameStrata("HIGH")
    card:SetPoint("BOTTOM", parent, "TOP", 0, 4)
    card:RegisterForClicks("AnyUp", "AnyDown")
    if M.MakeSkin then
        local skin = M.MakeSkin(card)
        skin:SetAllPoints()
        card.skin = skin
    end
    -- the same click logic as every card (decision 328): left casts, right goes away, shift + right snoozes 5 minutes
    card:SetScript("PostClick", function(_, button, down)
        if down or button ~= "RightButton" then return end
        M:Dismiss("ragecard", true, IsShiftKeyDown and IsShiftKeyDown() or false)
    end)
    card:SetAlpha(0)
    card:Hide()
end

-- the spell to cast when the card is wanted, else nil (only readable conditions)
function RC.Wanted()
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" then return nil end
    if M:IsSnoozed() or not M:IsRuleEnabled("buff") then return nil end
    if UnitIsDeadOrGhost("player") or (IsMounted and IsMounted()) then return nil end
    local g = group()
    if not g then return nil end
    local castId
    for _, id in ipairs(g.cast) do if knows(id) then castId = id; break end end
    if not castId then return nil end
    -- the buff on me? (auras are readable out of combat)
    local names = {}
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            if isSecret(a.name) then return nil end
            if type(a.name) == "string" then names[a.name] = true end
        end
    end
    for _, id in ipairs(g.spells) do
        local n = spellName(id)
        if n and names[n] then M:ClearAway("ragecard"); return nil end
    end
    if M:IsAway("ragecard") then return nil end
    return spellName(castId)
end

local function stop()
    if not card then return end
    if InCombatLockdown() then return end          -- the state driver keeps it hidden in combat
    if driven and UnregisterStateDriver then UnregisterStateDriver(card, "visibility") end
    driven = false
    card:Hide()
end

local elapsedSum, failed = 0, false
local function update(_, elapsed)
    if failed or not card then return end
    elapsedSum = elapsedSum + (elapsed or 0)
    if elapsedSum < 0.25 then return end
    elapsedSum = 0
    if InCombatLockdown() then return end
    -- when rage is readable the normal buff rule does the work
    local cur = UnitPower("player", rageType())
    if not isSecret(cur) then stop(); return end
    local spell = RC.Wanted()
    if not spell then stop(); return end
    if not curve then
        if curveError then return end
        curve, curveError = buildCurve()
        if not curve then M.unavailable = M.unavailable or {}; M.unavailable.buff = curveError; return end
    end
    local ok, err = pcall(function()
        card:SetAttribute("type1", "spell")
        card:SetAttribute("spell1", spell)
        card:SetAttribute("unit1", "player")
        if M.FillSkin and card.skin then
            M.FillSkin(card.skin, { tag = "BUFF", title = "Battle Shout", sub = "You are missing " .. spell,
                                    icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(6673)) or "Interface\\Icons\\Ability_Warrior_BattleShout",
                                    color = { 0.85, 0.45, 0.75 } })
        end
        card:SetAlpha(UnitPowerPercent("player", rageType(), false, curve))
        if not driven and RegisterStateDriver then
            RegisterStateDriver(card, "visibility", "[combat] hide; show")
            driven = true
        elseif not RegisterStateDriver then
            card:Show()
        end
    end)
    if not ok then
        failed = true
        stop()
        M.unavailable = M.unavailable or {}
        M.unavailable.buff = "rage card failed: " .. tostring(err)
        OMQ:Error("ragecard", err)
    end
end
RC._update = function() elapsedSum = 1; update(nil, 0) end
function RC:Frame() return card end

OMQ:On("READY", function()
    build()
    local d = CreateFrame("Frame")
    d:SetScript("OnUpdate", update)
end)
