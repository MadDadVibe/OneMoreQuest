-- One More Quest: who brings the group into combat (decision 215), the stat "Fights initiated"
-- One client of the group is the judge: the addon user with the lowest GUID (version 0.40.4 or
-- newer). Ten times a second he looks at who of the group is in combat (UnitAffectingCombat on
-- player and party1-4). When the group goes from "nobody in combat" to "somebody in combat", the
-- ones in combat at that moment brought it in: a pull, running in, an accident, a hunter's pet
-- (it puts its hunter in combat). Two at the same moment: both. Each of them counts the fight
-- himself (every client measures only its own values). Alone, out of a group, each own fight counts.
--   FI|proto|guid,guid       (the judge: these dads started the fight)
--   FS|proto|guid            (fallback when the combat state of others is secret: my combat began)
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.Pull = P

P.MIN_VERSION = "0.40.4"
local TICK = 0.1
local QUIET = 8          -- fallback: a new fight when nobody reported a combat start for this long
local TIE = 0.3          -- fallback: reports this close to the first count as the same moment

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function grouped()
    if OMQ.Sim and OMQ.Sim.active then return false end
    return IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) or false
end

-- the group: me and party1 to party4 -> { unit, guid }
local function members()
    local out = { { unit = "player", guid = UnitGUID("player") } }
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists and UnitExists(unit) then
            local g = UnitGUID(unit)
            if g and not isSecret(g) then out[#out + 1] = { unit = unit, guid = g } end
        end
    end
    return out
end
P.Members = members

local function supports(version)
    if not version or version == "" then return false end
    if version == OMQ.version or not OMQ.VersionNewer then return true end
    return not OMQ.VersionNewer(P.MIN_VERSION, version)          -- the same or newer
end

-- the judge: the lowest GUID among me and the online addon users that know this
function P.Judge()
    local me = OMQ:GetSelf()
    local best = me and me.guid
    for guid, u in pairs(OMQ.users) do
        if OMQ:IsOnline(u) and supports(u.version) and (not best or guid < best) then best = guid end
    end
    return best
end
function P.IAmJudge()
    local me = OMQ:GetSelf()
    return me ~= nil and P.Judge() == me.guid
end

-- the fight goes to these dads: my own count, a message for the others
local function award(guids)
    local me = OMQ:GetSelf()
    local others = {}
    for _, g in ipairs(guids) do
        if me and g == me.guid then
            if OMQ.Measure and OMQ.Measure.CountFight then OMQ.Measure:CountFight() end
        elseif OMQ.users[g] then
            others[#others + 1] = g
        end
    end
    if #others > 0 then OMQ:Send("FI", table.concat(others, ",")) end
    P.last = guids
    OMQ:Fire("FIGHT_STARTED_BY", guids)
end
P._award = award

OMQ:RegisterMessage("FI", function(f)
    local me = OMQ:GetSelf()
    if not me then return end
    for g in (f[1] or ""):gmatch("[^,]+") do
        if g == me.guid then
            if OMQ.Measure and OMQ.Measure.CountFight then OMQ.Measure:CountFight() end
        end
    end
end)

----------------------------------------------------------------------
-- The judge looks at the combat state of the group
----------------------------------------------------------------------
local idle = true
P.secret = nil           -- true when UnitAffectingCombat of the group is not readable

function P.Tick()
    if not grouped() then idle = true; return end
    -- every client checks whether the combat state can be read (non-judges need it for the fallback)
    local inCombat = {}
    for _, m in ipairs(members()) do
        local c = UnitAffectingCombat and UnitAffectingCombat(m.unit)
        if isSecret(c) then P.secret = true; idle = true; return end
        if c then inCombat[#inCombat + 1] = m.guid end
    end
    P.secret = false
    if not P.IAmJudge() then idle = true; return end
    if idle and #inCombat > 0 then award(inCombat) end
    idle = (#inCombat == 0)
end

----------------------------------------------------------------------
-- Fallback for a secret combat state, and fights alone
----------------------------------------------------------------------
local lastReport, firstAt, firstList = -100, -100, nil
local function onReport(guid)
    local now = GetTime()
    if now - lastReport >= QUIET then
        firstAt, firstList = now, { guid }
        lastReport = now
        C_Timer.After(TIE + 0.05, function()
            if firstList then award(firstList); firstList = nil end
        end)
        return
    end
    lastReport = now
    if firstList and now - firstAt <= TIE then firstList[#firstList + 1] = guid end
end
P._onReport = onReport

OMQ:RegisterMessage("FS", function(f)
    if not P.secret or not P.IAmJudge() then return end
    if f[1] and f[1] ~= "" then onReport(f[1]) end
end)

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function()
    local ok, err = pcall(function()
        local me = OMQ:GetSelf()
        if not me then return end
        if not grouped() then
            -- alone every own fight is mine (decision 215)
            if OMQ.Measure and OMQ.Measure.CountFight then OMQ.Measure:CountFight() end
            return
        end
        if P.secret then
            if P.IAmJudge() then onReport(me.guid) else OMQ:Send("FS", me.guid) end
        end
    end)
    if not ok then OMQ:Error("pull", err) end
end)

local acc = 0
ev:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < TICK then return end
    acc = 0
    local ok, err = pcall(P.Tick)
    if not ok then OMQ:Error("pull tick", err) end
end)

-- what the game lets us read, for /omq diag
function P.Diag()
    local parts = {}
    for _, m in ipairs(members()) do
        local c = UnitAffectingCombat and UnitAffectingCombat(m.unit)
        parts[#parts + 1] = m.unit .. "=" .. (isSecret(c) and "SECRET" or tostring(c))
    end
    return "fights: judge " .. tostring(P.IAmJudge()) .. ", combat " .. table.concat(parts, " ") ..
        ", fallback " .. tostring(P.secret)
end
