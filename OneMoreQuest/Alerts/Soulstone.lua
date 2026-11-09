-- One More Quest: a healer in a dungeon asks the warlock for a Soulstone (decision 488)
-- Healer (options role or group role), a warlock of level 18 or more in the group, inside a dungeon:
-- a card "Ask <Name> for a Soulstone". A left click whispers the warlock and the card stays away
-- for a minute. With the Soulstone on me the card rests; it comes back when the stone is gone, or
-- 30 minutes after I got it, as long as we are still in the dungeon. A right click puts it away as usual.
-- Auras are read through OMQ.ReadAura; while they are hidden the 30 minute timer decides.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local S = {}
OMQ.Soulstone = S

S.SPELLS = { 20707, 20762, 20763, 20764, 20765 }   -- Soulstone Resurrection, ranks 1-5
S.COOLDOWN = 60                   -- seconds after a click
S.KEEP = 30 * 60                  -- a Soulstone lasts 30 minutes
S.MIN_LEVEL = 18                  -- a warlock creates his first Soulstone at 18
S.KEY = "soulstone"
S.gotAt = nil                     -- GetTime() I got the stone (nil: none seen)
local COLOR = { 0.58, 0.51, 0.79 }
local ICON = "Interface\\Icons\\Spell_Shadow_SoulGem"

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function plain(v) return v ~= nil and not isSecret(v) end
local function now() return GetTime and GetTime() or 0 end
local function short(name) return type(name) == "string" and (name:match("^([^%-]+)") or name) or "?" end

local names
local function stoneNames()
    if names and next(names) then return names end
    names = {}
    for _, id in ipairs(S.SPELLS) do
        local n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and (GetSpellInfo(id)))
        if type(n) == "string" and not isSecret(n) then names[n] = true end
    end
    return names
end
local IDS = {}
for _, id in ipairs(S.SPELLS) do IDS[id] = true end

function S.InDungeon()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid") or false
end

function S.IsHealer()
    local H = OMQ.HealCall
    if H and H.IsHealer then return H.IsHealer() and true or false end
    local o = OMQ.db and OMQ.db.options
    if o and o.role == "heal" then return true end
    if UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, "player")
        if ok and plain(r) and r == "HEALER" then return true end
    end
    return false
end

-- the warlocks of the group who can make a Soulstone: list of { unit, name, full }
function S.Warlocks()
    local out = {}
    local raid = IsInRaid and IsInRaid()
    local n = raid and 40 or 4
    for i = 1, n do
        local u = (raid and "raid" or "party") .. i
        if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            local _, cls = UnitClass(u)
            local lvl = UnitLevel and UnitLevel(u)
            local online = not UnitIsConnected or UnitIsConnected(u)
            if plain(cls) and cls == "WARLOCK" and online
                and not (plain(lvl) and type(lvl) == "number" and lvl > 0 and lvl < S.MIN_LEVEL) then
                local name, name2 = UnitName(u)
                if plain(name) and type(name) == "string" then
                    -- Forever names have two parts ("Vorname Nachname"): a whisper needs both (see fix row 439)
                    local full = name
                    if plain(name2) and type(name2) == "string" and name2 ~= "" then full = name .. " " .. name2 end
                    out[#out + 1] = { unit = u, name = short(name), full = full }
                end
            end
        end
    end
    return out
end

-- is the Soulstone on me? true / false, or nil when the auras cannot be read
function S.HasStone()
    local sn = stoneNames()
    for i = 1, 40 do
        local a, hidden = OMQ.ReadAura("player", i, "HELPFUL")
        if hidden then return nil end
        if not a then break end
        local id, nm = a.spellId, a.name
        if (plain(id) and IDS[id]) or (plain(nm) and sn[nm]) then
            if not S.gotAt then
                local exp, dur = a.expirationTime, a.duration
                if plain(exp) and plain(dur) and type(exp) == "number" and type(dur) == "number" and exp > 0 and dur > 0 then
                    S.gotAt = exp - dur
                else
                    S.gotAt = now()
                end
            end
            return true
        end
    end
    return false
end

-- the card rests while the stone is on (or the auras are hidden) and less than 30 minutes old
function S.Resting()
    local has = S.HasStone()
    if has == false then S.gotAt = nil; return false end
    return S.gotAt ~= nil and now() - S.gotAt < S.KEEP
end

S.TEXT = "Could you put a Soulstone on me, please? :)"

-- the click: whisper every warlock of the group, then the card rests for a minute
function S.Ask()
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, w in ipairs(S.Warlocks()) do
        local ok, err = false, "no chat"
        if send then ok, err = pcall(send, S.TEXT, "WHISPER", nil, w.full) end
        if not ok then OMQ:Print("could not whisper " .. w.name .. " for a Soulstone: " .. tostring(err)) end
    end
    M:Silence(S.KEY, S.COOLDOWN)
    return "keep"
end

function S.Card()
    if not S.InDungeon() or not S.IsHealer() then return nil end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
    local list = S.Warlocks()
    if #list == 0 then return nil end
    if S.Resting() then return nil end
    local who = list[1].name
    if #list > 1 then who = "a warlock" end
    return {
        key = S.KEY,
        text = "Ask " .. who .. " for a Soulstone",
        title = "Ask " .. who .. " for a Soulstone",
        sub = "Left click: whisper " .. (#list > 1 and "the warlocks" or who),
        tag = "SOULSTONE", icon = ICON, color = COLOR,
        open = S.Ask,
    }
end

M:Register({
    id = "soulstone", name = "Healer: ask the warlock for a Soulstone",
    check = function()
        local c = S.Card()
        return c and { c } or nil
    end,
})
