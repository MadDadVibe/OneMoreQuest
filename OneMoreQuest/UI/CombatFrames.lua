-- One More Quest: the player frame only when it is needed (decision 479, changed in decision 480)
-- The game's player frame (PlayerFrame) stays at its place (Edit Mode). With the option on it is see-through
-- (alpha 0):
--   - in a fight, always;
--   - out of a fight while my life is full and my mana (if I have mana) is above 80 %.
-- It is shown out of a fight when my life is below 100 % or my mana is at or below 80 %.
-- Alpha is no protected change, so it may change at any moment, also in the combat lockdown. Nothing is moved,
-- shown or hidden. The see-through frame still takes clicks (EnableMouse would be protected).
-- The game may set the alpha itself; a look every 0.25 s puts ours back. Unreadable (secret) values: shown.
-- /omq frames on|off, /omq frames shows the values it reads (to check in the game).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local CF = {}
OMQ.CombatFrames = CF

CF.MANA = 0.8           -- out of a fight the frame is shown while the mana is at or below this share
CF.TICK = 0.25          -- seconds between two looks at the alpha

local function locked() return InCombatLockdown and InCombatLockdown() and true or false end
local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

-- the option: OMQDB.combatFrames.hideFull (the name from decision 479 is kept, it was set in the game)
function CF.On()
    local d = OMQ.db and OMQ.db.combatFrames
    return d ~= nil and d.hideFull == true
end
function CF.Set(on)
    OMQ.db.combatFrames = OMQ.db.combatFrames or {}
    local d = OMQ.db.combatFrames
    d.hideFull = on and true or false
    d.player, d.target = nil, nil   -- the fight places of decision 479 are gone
    CF.Fade()
end

local fight = false
function CF.InFight()
    return fight or locked() or (UnitAffectingCombat and UnitAffectingCombat("player") == true) or false
end

-- the values and why: full (true/false), reason text
function CF.Read()
    if not (UnitHealth and UnitHealthMax) then return false, "no health API" end
    local hp, max = UnitHealth("player"), UnitHealthMax("player")
    if isSecret(hp) or isSecret(max) then return false, "life secret" end
    if type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then return false, "life unreadable" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false, "dead" end
    local life = string.format("life %d/%d", hp, max)
    if hp < max then return false, life end
    local mana = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
    local mp, mmax = UnitPower and UnitPower("player", mana), UnitPowerMax and UnitPowerMax("player", mana)
    if isSecret(mp) or isSecret(mmax) then return false, life .. ", mana secret" end
    if type(mmax) == "number" and mmax > 0 then
        if type(mp) ~= "number" then return false, life .. ", mana unreadable" end
        local m = string.format("mana %d/%d", mp, mmax)
        if mp / mmax <= CF.MANA then return false, life .. ", " .. m end
        return true, life .. ", " .. m
    end
    return true, life .. ", no mana"
end
function CF.Full() return (CF.Read()) end

-- the alpha we want: nil = leave the frame alone (option off)
function CF.Want()
    if not CF.On() then return nil, "off" end
    if CF.InFight() then return 0, "in a fight" end
    local full, why = CF.Read()
    return full and 0 or 1, why
end

local touched = false   -- we changed the alpha: when the option goes off, it is set back to 1 once
function CF.Fade()
    local f = _G.PlayerFrame
    if not (f and f.SetAlpha) then return end
    local a, why = CF.Want()
    CF.why = why
    if a == nil then
        if touched then f:SetAlpha(1); touched = false end
        CF.hidden = false
        return
    end
    local now = f.GetAlpha and f:GetAlpha()
    if now ~= a or isSecret(now) then f:SetAlpha(a) end
    touched = true
    CF.hidden = a == 0
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_UNGHOST",
    "UNIT_FLAGS" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if type(unit) == "string" and event:find("^UNIT_") and unit ~= "player" then return end
    if event == "PLAYER_REGEN_DISABLED" then fight = true
    elseif event == "PLAYER_REGEN_ENABLED" then fight = false end
    local ok, err = pcall(CF.Fade)
    if not ok then OMQ:Error("frames " .. event, err) end
end)
local acc = 0
ev:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < CF.TICK then return end
    acc = 0
    local ok, err = pcall(CF.Fade)
    if not ok then OMQ:Error("frames tick", err) end
end)

OMQ:On("READY", function()
    local d = OMQ.db and OMQ.db.combatFrames
    if d then d.player, d.target = nil, nil end
    CF.Fade()
end)

-- /omq frames: status with the values read | on | off
OMQ:RegisterCommand("frames", function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "hide on" then CF.Set(true)
    elseif arg == "off" or arg == "hide off" then CF.Set(false) end
    CF.Fade()
    local f = _G.PlayerFrame
    local a = f and f.GetAlpha and f:GetAlpha()
    OMQ:Print(string.format("player frame only when needed: %s; now %s (%s), alpha %s%s",
        CF.On() and "on" or "off", CF.hidden and "hidden" or "shown", tostring(CF.why),
        isSecret(a) and "secret" or tostring(a), f and (f.IsShown and not f:IsShown() and ", frame not shown" or "") or ", no PlayerFrame"))
    print("  /omq frames on | off")
end, "player frame only when needed: hidden in a fight and at full life and mana")
