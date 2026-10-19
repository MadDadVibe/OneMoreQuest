-- One More Quest: "Karle is drinking" for the other dads (decision 238)
-- When a dad sits down to drink, every other dad's client shows a quiet card "Karle is drinking"
-- with the time the drink can last, and drops it when he stands up. Melee dads learn to wait for
-- the casters' mana without anybody having to ask. The drink buff is readable out of combat.
--   DK|proto|guid|1|seconds     (started drinking, seconds the buff can still last)
--   DK|proto|guid|0             (stopped)
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local GD = {}
OMQ.GroupDrink = GD

-- drink buffs of the classic waters and mana drinks; only their names are compared
GD.DRINK_SPELLS = { 430, 431, 432, 1133, 1135, 1137, 22734, 24355, 25696, 26475, 29007 }
GD.drinking = {}                 -- guid -> GetTime() the buff ends at the latest
local names
local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function drinkNames()
    if names and next(names) then return names end
    names = {}
    for _, id in ipairs(GD.DRINK_SPELLS) do
        local n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
        if type(n) == "string" and not isSecret(n) then names[n] = true end
    end
    return names
end

-- am I drinking? true and the seconds left, or false
function GD.MyDrink()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
    local dn = drinkNames()
    for i = 1, 40 do
        local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then break end
        if isSecret(a.name) then return false end
        if type(a.name) == "string" and dn[a.name] then
            local left = 0
            if type(a.expirationTime) == "number" and not isSecret(a.expirationTime) and a.expirationTime > 0 then
                left = math.max(0, a.expirationTime - GetTime())
            end
            return true, left
        end
    end
    return false
end

local was = false
function GD.Tick()
    if InCombatLockdown and InCombatLockdown() then return end
    local now, left = GD.MyDrink()
    if now == was then return end
    was = now
    local me = OMQ:GetSelf()
    if not me or not OMQ:GetChannel() then return end
    if now then OMQ:Send("DK", me.guid, "1", string.format("%.0f", left or 0))
    else OMQ:Send("DK", me.guid, "0") end
end

OMQ:RegisterMessage("DK", function(f)
    local guid = f[1]
    local me = OMQ:GetSelf()
    if not guid or (me and guid == me.guid) then return end
    if f[2] == "1" then
        local secs = tonumber(f[3]) or 0
        GD.drinking[guid] = GetTime() + (secs > 0 and secs or 30)
        GD.seconds = GD.seconds or {}
        GD.seconds[guid] = secs
    else
        GD.drinking[guid] = nil
    end
    if OMQ.Alerts then OMQ.Alerts:Evaluate() end
end)

local acc = 0
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.5 then return end
    acc = 0
    local ok, err = pcall(GD.Tick)
    if not ok then OMQ:Error("groupdrink", err) end
end)

-- the alert rule: one quiet card per drinking dad
local M = OMQ.Alerts
M:Register({
    id = "groupdrink", name = "A dad is drinking",
    check = function()
        local out = {}
        local t = GetTime()
        for guid, untilAt in pairs(GD.drinking) do
            local u = OMQ.users[guid]
            if t > untilAt or not (u and OMQ:IsOnline(u)) then
                GD.drinking[guid] = nil
            else
                local secs = GD.seconds and GD.seconds[guid] or 0
                local sub = secs > 0 and string.format("Mana break - up to %d s, wait a moment", math.ceil(untilAt - t))
                    or "Mana break - wait a moment"
                out[#out + 1] = {
                    key = "drinking:" .. guid,
                    text = (u.name or "A dad") .. " is drinking",
                    title = (u.name or "A dad") .. " is drinking", sub = sub, tag = "MANA BREAK",
                    icon = "Interface\\Icons\\INV_Drink_07", color = { 0.35, 0.65, 0.91 }, quiet = true,
                }
            end
        end
        return out
    end,
})
