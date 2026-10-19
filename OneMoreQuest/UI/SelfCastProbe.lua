-- One More Quest: probe for click casting on the personal resource display (decision 248)
-- Goal: Shift-click heals (decision 226) also work solo by clicking the resource bar under the
-- character. Blizzard's click casting fires on every button made from SecureUnitButtonTemplate, so an
-- invisible one with unit "player" over that bar would do. On WoW Forever the display is the fixed frame
-- PersonalResourceDisplayFrame (first test, 0.45.4: no nameplate for the player). This probe:
--   /omq prd          report: is the bar there, where, can we read and anchor it, recycling seen
--   /omq prd on|off   attach / remove the invisible button (out of combat), only on this client
--   /omq prd show     show the button with a gold frame, to see where it sits and to test Shift-click
-- Since 0.45.6 (decision 250) it is on by default; the option in Group switches it off.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.SelfCastProbe = P

P.log = {}                       -- the last nameplate events of the player's plate
local button, outline, attachedTo
P.enabled, P.visible = false, false

-- decision 250: a fixed part of the addon now, on by default; option "Click casting on your resource
-- display" (Group) switches it off. /omq prd on|off still works for this session.
local function optionOn() return not (OMQ.db and OMQ.db.options and OMQ.db.options.selfCast == false) end
P.OptionOn = optionOn

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function note(t)
    P.log[#P.log + 1] = string.format("%.1f %s", GetTime(), t)
    if #P.log > 20 then table.remove(P.log, 1) end
end
local function cvar(name)
    if C_CVar and C_CVar.GetCVar then local ok, v = pcall(C_CVar.GetCVar, name); if ok then return v end end
    if GetCVar then local ok, v = pcall(GetCVar, name); if ok then return v end end
    return nil
end

-- WoW Forever's resource display is a fixed Edit Mode frame, not a nameplate (seen in the game and in
-- Blizzard's code: PersonalResourceDisplayFrame, parent UIParent, bars HealthBarsContainer and PowerBar)
function P.Display()
    local f = _G.PersonalResourceDisplayFrame
    if not f then return nil, "PersonalResourceDisplayFrame missing" end
    if f.IsForbidden and f:IsForbidden() then return nil, "PersonalResourceDisplayFrame is forbidden for addons" end
    return f
end

-- visibility of the display: "always", "combat" or "hidden"
function P.DisplayVisibility()
    local f = P.Display()
    if not f then return "hidden" end
    local ok, setting = pcall(function() return f:GetVisibleSetting() end)
    local E = Enum and Enum.PersonalResourceDisplayVisibleSetting
    local enabled = true
    if C_GameRules and C_GameRules.IsPersonalResourceDisplayEnabled then
        local ok2, on = pcall(C_GameRules.IsPersonalResourceDisplayEnabled)
        if ok2 then enabled = on and true or false end
    end
    if not enabled then return "hidden" end
    if ok and E and setting == E.InCombat then return "combat" end
    if ok and E and setting ~= nil and setting ~= E.Always then return "hidden" end
    return "always"
end

-- the player's own plate, if the game gives it to us (the first idea, kept for the report)
function P.Plate()
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil, "C_NamePlate.GetNamePlateForUnit missing" end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "player")
    if not ok then return nil, "error: " .. tostring(plate) end
    if not plate then
        local ok2, forbidden = pcall(C_NamePlate.GetNamePlateForUnit, "player", true)
        if ok2 and forbidden then return nil, "only as a forbidden frame (addons may not use it)" end
        return nil, "no plate for the player (resource display off or hidden)"
    end
    if plate.IsForbidden and plate:IsForbidden() then return nil, "the plate is forbidden for addons" end
    return plate
end

-- the part of the plate that shows the bars
local function barOf(plate)
    local uf = plate and (plate.UnitFrame or plate.unitFrame)
    local hb = uf and (uf.healthBar or uf.HealthBar or uf.HealthBarsContainer)
    return hb or uf or plate
end

local function build()
    if button then return end
    button = CreateFrame("Button", "OneMoreQuestSelfCast", UIParent, "SecureUnitButtonTemplate")
    button:SetSize(120, 14)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("unit", "player")
    button:SetAttribute("type1", "target")                 -- a plain click targets you, like a unit frame
    button:SetAttribute("type2", "togglemenu")
    outline = {}
    for i = 1, 4 do
        local t = button:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.89, 0.71, 0.29, 1)
        outline[i] = t
    end
    outline[1]:SetPoint("TOPLEFT"); outline[1]:SetPoint("TOPRIGHT"); outline[1]:SetHeight(2)
    outline[2]:SetPoint("BOTTOMLEFT"); outline[2]:SetPoint("BOTTOMRIGHT"); outline[2]:SetHeight(2)
    outline[3]:SetPoint("TOPLEFT"); outline[3]:SetPoint("BOTTOMLEFT"); outline[3]:SetWidth(2)
    outline[4]:SetPoint("TOPRIGHT"); outline[4]:SetPoint("BOTTOMRIGHT"); outline[4]:SetWidth(2)
    button:SetScript("PostClick", function(_, b) note("clicked " .. tostring(b)) end)
    button:Hide()
end

local function paintOutline()
    if not outline then return end
    for _, t in ipairs(outline) do t:SetShown(P.visible) end
end

-- the button shows exactly when the display shows: always, or only in combat (a state driver, so it
-- also works in combat); where the display is hidden there is no invisible button catching clicks
local function setVisibility(mode)
    if not button then return end
    if UnregisterStateDriver then pcall(UnregisterStateDriver, button, "visibility") end
    if mode == "always" then button:Show()
    elseif mode == "combat" and RegisterStateDriver then RegisterStateDriver(button, "visibility", "[combat] show; hide")
    else button:Hide() end
    P.mode = mode
end

-- attach over the resource display (out of combat only); returns true or the reason
function P.Attach()
    if InCombatLockdown and InCombatLockdown() then return false, "in combat" end
    build()
    local f, why = P.Display()
    if not f then button:Hide(); attachedTo = nil; return false, why end
    local top = f.HealthBarsContainer or f
    local bottom = (f.PowerBar and f.PowerBar.IsShown and f.PowerBar:IsShown()) and f.PowerBar or top
    local ok, err = pcall(function()
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", top, "TOPLEFT", -2, 2)
        button:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 2, -2)
        button:SetFrameStrata(f:GetFrameStrata() or "MEDIUM")
        button:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    end)
    if not ok then button:Hide(); attachedTo = nil; return false, "anchoring refused: " .. tostring(err) end
    attachedTo = f
    setVisibility(P.DisplayVisibility())
    paintOutline()
    return true, P.mode
end

function P.Detach()
    if InCombatLockdown and InCombatLockdown() then return false, "in combat" end
    if button then
        if UnregisterStateDriver then pcall(UnregisterStateDriver, button, "visibility") end
        button:ClearAllPoints(); button:Hide()
    end
    attachedTo = nil
    return true
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    local mine = unit and not isSecret(unit) and UnitIsUnit and UnitIsUnit(unit, "player")
    if event == "NAME_PLATE_UNIT_ADDED" and mine then
        note("player plate added (" .. tostring(unit) .. ")" .. ((InCombatLockdown and InCombatLockdown()) and " IN COMBAT" or ""))
    elseif event == "NAME_PLATE_UNIT_REMOVED" and mine then
        note("player plate removed" .. ((InCombatLockdown and InCombatLockdown()) and " IN COMBAT" or ""))
    elseif event == "PLAYER_REGEN_DISABLED" and P.enabled then
        note("combat starts, button " .. ((button and button:IsShown()) and "shown" or "hidden"))
    elseif event == "PLAYER_REGEN_ENABLED" and P.pending then
        P.pending = nil
        if P.Apply then P.Apply() end
    elseif event == "PLAYER_REGEN_ENABLED" and P.enabled then
        P.Attach()       -- the display may have been moved or its setting changed meanwhile
    end
end)

function P.Report()
    local out = {}
    local function add(s) out[#out + 1] = s end
    add("Self-cast probe (decision 248), version " .. tostring(OMQ.version))
    add("CVar nameplateShowSelf = " .. tostring(cvar("nameplateShowSelf")) .. ", nameplateShowAll = " .. tostring(cvar("nameplateShowAll")))
    add("C_ClickBindings: " .. tostring(C_ClickBindings ~= nil) .. ", SecureUnitButton_OnClick: " .. tostring(SecureUnitButton_OnClick ~= nil))
    local f, whyF = P.Display()
    if f then
        local l, b, w, h = (f:GetLeft()), (f:GetBottom()), (f:GetWidth()), (f:GetHeight())
        add(string.format("resource display: PersonalResourceDisplayFrame, shown %s, visibility %s, at %s,%s size %sx%s, health bars %s, power bar %s",
            tostring((f:IsShown())), P.DisplayVisibility(), tostring(l and math.floor(l)), tostring(b and math.floor(b)),
            tostring(w and math.floor(w)), tostring(h and math.floor(h)), tostring(f.HealthBarsContainer ~= nil), tostring(f.PowerBar ~= nil)))
    else
        add("resource display: none - " .. tostring(whyF))
    end
    local plate, why = P.Plate()
    if plate then
        local bar = barOf(plate)
        local l, b, w, h = (bar:GetLeft()), (bar:GetBottom()), (bar:GetWidth()), (bar:GetHeight())
        add(string.format("player plate: %s, shown %s, bar %s at %s,%s size %sx%s, unit token %s",
            tostring((plate:GetName())), tostring((plate:IsShown())), tostring(bar == plate and "plate itself" or (bar.GetName and (bar:GetName()) or "child")),
            tostring(l and math.floor(l)), tostring(b and math.floor(b)), tostring(w and math.floor(w)), tostring(h and math.floor(h)),
            tostring(plate.namePlateUnitToken)))
    else
        add("player plate: none - " .. tostring(why))
    end
    add("button: " .. (button and ((button:IsShown() and "shown" or "hidden") .. ", mode " .. tostring(P.mode)) or "not built") ..
        ", enabled " .. tostring(P.enabled) .. ", outline " .. tostring(P.visible))
    add("last events:")
    for _, l in ipairs(P.log) do add("  " .. l) end
    return out
end

OMQ:RegisterCommand("prd", function(arg)
    arg = (arg or ""):lower():match("^%s*(%S*)")
    if arg == "on" then
        P.enabled = true
        local ok, why = P.Attach()
        OMQ:Print("self-cast button " .. (ok and ("attached to your resource display (" .. tostring(why) .. ") - try Shift + click on it")
            or ("not attached: " .. tostring(why))))
    elseif arg == "off" then
        P.enabled = false
        local ok, why = P.Detach()
        OMQ:Print(ok and "self-cast button removed" or ("not now: " .. tostring(why)))
    elseif arg == "show" then
        P.visible = not P.visible
        paintOutline()
        OMQ:Print("self-cast button outline " .. (P.visible and "shown" or "hidden"))
    else
        local lines = P.Report()
        OMQ:Print(lines[1])
        for i = 2, #lines do print("  " .. lines[i]) end
        if OMQ.ShowReport then OMQ:ShowReport(lines) end
    end
end, "probe: click casting on your resource display (on, off, show)")

-- start with the addon, and follow the option
function P.Apply()
    local want = optionOn()
    if want == P.enabled and (not want or (button and attachedTo)) then return end
    if InCombatLockdown and InCombatLockdown() then P.pending = true; return end
    P.enabled = want
    if want then P.Attach() else P.Detach() end
end
OMQ:On("READY", function()
    if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(P.Apply) end) else pcall(P.Apply) end
end)
OMQ:On("SETTINGS_CHANGED", function() pcall(P.Apply) end)

