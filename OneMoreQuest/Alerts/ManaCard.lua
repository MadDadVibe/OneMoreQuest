-- One More Quest: the mana alert for clients where mana values are secret.
-- A secret number cannot be compared, but it may be handed to the interface.
-- So the card's transparency is driven by a step curve (UnitPowerPercent with a
-- curve): 100% visible below 30 percent mana, invisible above. Everything that
-- is readable (combat, drinking, mounted, snooze, switch) gates the card as usual.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local BELOW = 0.30
local MC = {}
OMQ.ManaCard = MC

local card, curve, curveError
local drinkName
local driven = false        -- the game's state driver hides the card in combat (a secure button, decision 219)

local function isSecret(v) return issecretvalue and issecretvalue(v) end

-- the card only reminds, it takes no clicks (decisions 303 and 304): its alpha comes from the game as a secret
-- number and WoW Forever gives it back secret too, so nobody can tell whether the card can be seen - an
-- invisible card must not drink or swallow clicks.

local function buildCurve()
    if not UnitPowerPercent then return nil, "UnitPowerPercent is missing" end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil, "C_CurveUtil.CreateCurve is missing" end
    local c = C_CurveUtil.CreateCurve()
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step and c.SetType then c:SetType(Enum.LuaCurveType.Step) end
    c:AddPoint(0, 1)
    c:AddPoint(BELOW, 0)
    c:AddPoint(1, 0)
    return c
end

local function build()
    local parent = _G.OneMoreQuestAlerts
    if not parent then return end
    -- a secure button: a click drinks the best drink in the bags (decision 219)
    card = CreateFrame("Button", "OneMoreQuestManaCard", UIParent, "SecureActionButtonTemplate")
    if card.RegisterForClicks then card:RegisterForClicks("AnyUp", "AnyDown") end
    card:SetSize(M.CARD_W or 330, M.CARD_H or 50)
    card:SetScale(1.2)
    card:SetFrameStrata("HIGH")
    card:SetPoint("BOTTOM", parent, "TOP", 0, 4)
    -- the same medallion look as every other card (decision 188)
    if M.MakeSkin then
        local skin = M.MakeSkin(card)
        skin:SetAllPoints()
        M.FillSkin(skin, { tag = "DRINK", title = "Drink", sub = "Mana is low", icon = "Interface\\Icons\\INV_Drink_07",
                           color = { 0.35, 0.65, 0.91 } })
        card.skin = skin
    end
    card:SetAlpha(0)
    if card.EnableMouse then card:EnableMouse(false) end
    card:Hide()
end

-- true when the mana card may be shown at all (all readable conditions)
local function allowed()
    if M:IsSnoozed() or not M:IsRuleEnabled("drink") then return false end
    if InCombatLockdown() or UnitIsDeadOrGhost("player") or (IsMounted and IsMounted()) then return false end
    if (UnitPowerType("player")) ~= (Enum and Enum.PowerType and Enum.PowerType.Mana or 0) then return false end
    local last = OMQ.Alerts.leftCombatAt and OMQ.Alerts.leftCombatAt() or 0
    if (GetTime() - last) < 3 then return false end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        drinkName = drinkName or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(430))
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            if not isSecret(a.name) and a.name == drinkName then return false end
        end
    end
    return true
end

local function stop()
    if not card or InCombatLockdown() then return end
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
    if InCombatLockdown() then return end          -- in combat the state driver keeps it hidden
    -- when mana is readable the normal rule does the work
    local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    local cur = UnitPower("player", mana)
    if not isSecret(cur) then stop(); return end
    if not allowed() then stop(); return end
    if not curve then
        if curveError then return end
        curve, curveError = buildCurve()
        if not curve then M.unavailable = M.unavailable or {}; M.unavailable.drink = curveError; return end
    end
    local ok, err = pcall(function()
        local best = OMQ.Ready and OMQ.Ready.BestDrink and OMQ.Ready.BestDrink()
        if best then
            card:SetAttribute("type1", "item")
            card:SetAttribute("item1", "item:" .. best)
        else
            card:SetAttribute("type1", nil)
        end
        local a = UnitPowerPercent("player", mana, false, curve)
        card:SetAlpha(a)
        if card.EnableMouse then card:EnableMouse(false) end
        if M.FillSkin and card.skin and best ~= MC._lastBest then
            MC._lastBest = best
            local sub = best and "Mana is low - drink something" or "Mana is low - no drinks in your bags"
            M.FillSkin(card.skin, { tag = "DRINK", title = "Drink", sub = sub,
                                    icon = "Interface\\Icons\\INV_Drink_07", color = { 0.35, 0.65, 0.91 } })
        end
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
        M.unavailable.drink = "mana card failed: " .. tostring(err)
        OMQ:Error("manacard", err)
    end
end
MC._update = function() elapsedSum = 1; update(nil, 0) end
function MC:Frame() return card end

function MC.Status()
    if curve then return "curve ready" end
    local c, e = buildCurve()
    return c and "curve can be built" or tostring(e)
end

OMQ:On("READY", function()
    build()
    local d = CreateFrame("Frame")
    d:SetScript("OnUpdate", update)
end)
