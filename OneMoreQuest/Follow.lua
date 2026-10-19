-- One More Quest: follow the closest group member
-- Press the follow key (default "<"): the character follows the closest group
-- member who runs the addon (no need to select or hover anybody). The key is set with
-- /omq follow <key>. It is a secure macro button ("/follow party2" and so on),
-- because following is a protected action.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local DEFAULT_KEY = "<"
local BUTTON = "OneMoreQuestFollowButton"

local F = {}
OMQ.Follow = F

local button
local boundKey

local function isSecret(v) return issecretvalue and issecretvalue(v) end

-- The closest group member who runs the addon: returns unit token, name.
local function nearestMember()
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    local best, bestDist, bestUnit, bestName
    for _, unit in ipairs(units) do
        if UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
            local guid = UnitGUID(unit)
            local u = guid and not isSecret(guid) and OMQ.users[guid]
            if u and OMQ:IsOnline(u) and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
                and not (UnitIsConnected and not UnitIsConnected(unit)) then
                local d = OMQ.Arrow and OMQ.Arrow.DistanceTo and OMQ.Arrow:DistanceTo(guid)
                -- members with an unknown distance only count when nobody has a known one
                local rank = d or math.huge
                if not best or rank < bestDist then
                    best, bestDist, bestUnit = guid, rank, unit
                    bestName = UnitName(unit) or u.name
                end
            end
        end
    end
    return bestUnit, bestName
end

local function normalize(key)
    key = (key or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then return nil end
    local lower = key:lower()
    if lower == "less" or lower == "kleiner" then return "<" end
    return key:upper()
end

local function currentKey()
    local k = OMQ.db and OMQ.db.options and OMQ.db.options.followKey
    if k == nil then return DEFAULT_KEY end
    if k == false or k == "" then return nil end       -- switched off
    return k
end

-- (Re)applies the key binding. Bindings cannot change in combat.
function F:Apply()
    if not button then return false end
    if InCombatLockdown and InCombatLockdown() then
        F.pendingApply = true
        return false
    end
    F.pendingApply = false
    if ClearOverrideBindings then ClearOverrideBindings(button) end
    boundKey = nil
    local key = currentKey()
    if not key then return true end
    if SetOverrideBindingClick then
        SetOverrideBindingClick(button, true, key, BUTTON)
        boundKey = key
    end
    return true
end

local function build()
    button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
    button:SetSize(1, 1)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "")
    -- decide what the macro does right before the secure click is handled
    button:SetScript("PreClick", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        local unit = nearestMember()
        self:SetAttribute("macrotext", unit and ("/follow " .. unit) or "")
    end)
    button:SetScript("PostClick", function(_, _, down)
        if down then return end
        local unit, name = nearestMember()
        if unit then OMQ:Print("following " .. (name or unit))
        else OMQ:Print("follow: no group member with the addon found") end
    end)
    F:Apply()
end

OMQ:On("READY", build)
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function() if F.pendingApply then F:Apply() end end)
end

OMQ:RegisterCommand("follow", function(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then
        local k = currentKey()
        OMQ:Print(k and ("follow key: " .. k .. " (follows the closest group member with the addon)")
            or "follow key: off")
        print("  /omq follow <key> | off | default   e.g. /omq follow <  or  /omq follow SHIFT-F")
        return
    end
    local lower = arg:lower()
    if lower == "off" then
        OMQ.db.options.followKey = false
    elseif lower == "default" then
        OMQ.db.options.followKey = nil
    else
        local key = normalize(arg)
        if not key then OMQ:Print("follow: no key given"); return end
        OMQ.db.options.followKey = key
    end
    if F:Apply() then
        local k = currentKey()
        OMQ:Print(k and ("follow key set to " .. k) or "follow key switched off")
    else
        OMQ:Print("follow key saved - it takes effect when combat ends")
    end
end, "follow the closest group member with the addon, by key: /omq follow [key|off|default]")

-- test hooks
F._nearest = nearestMember
function F:BoundKey() return boundKey end
