-- One More Quest: Share
-- Sends the player's own session values to the group and stores the values of
-- the others. Each client measures only itself (design principle).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local SEND_INTERVAL = 10
local KEYS = { "xph", "lvlp", "lvl", "yards", "gold", "curgold", "dmg", "kb", "hit", "deaths", "near", "food" }
OMQ.statKeys = KEYS
-- the rows added by decision 120 go in a second message (255 byte limit)
local KEYS2 = { "ptime", "xp", "xpkill", "xpquest", "xpdisc", "quests", "fights", "heal",
                "fallx", "falld", "drownd", "lava", "aucp", "aucb", "need", "greed", "gamble", "betswon", "nextlvl" }

local function encodeValue(v)
    if type(v) ~= "number" then return "" end
    if v ~= v or v == math.huge or v == -math.huge then return "" end
    return string.format("%.3f", v)
end

function OMQ:SendStats()
    local me = self:GetSelf()
    if not me or not self:GetChannel() then return end
    local v = self.Measure:GetValues()
    local fields = { me.guid }
    for i, key in ipairs(KEYS) do fields[i + 1] = encodeValue(v[key]) end
    fields[#KEYS + 2] = v.hitApprox and "1" or "0"
    self:Send("S", unpack(fields))
    local g = { me.guid }
    for i, key in ipairs(KEYS2) do
        local x = v[key]
        g[i + 1] = type(x) == "number" and x == x and string.format("%.0f", x) or ""
    end
    self:Send("S2", unpack(g))
end

local function handleStats(fields)
    local guid = fields[1]
    if not guid or guid == "" then return end
    local me = OMQ:GetSelf()
    if me and guid == me.guid then return end
    local u = OMQ.users[guid]
    if not u then return end                 -- values only from users we know via HELLO
    local values = {}
    for i, key in ipairs(KEYS) do
        values[key] = tonumber(fields[i + 1])    -- "" becomes nil
    end
    values.hitApprox = fields[#KEYS + 2] == "1"
    for _, key in ipairs(KEYS2) do values[key] = u.values and u.values[key] or nil end   -- from the second message
    u.values = values
    u.lastSeen = GetTime()
    OMQ:Fire("USER_UPDATED", guid)
end

OMQ:RegisterMessage("S", handleStats)

local function handleStats2(fields)
    local guid = fields[1]
    if not guid or guid == "" then return end
    local me = OMQ:GetSelf()
    if me and guid == me.guid then return end
    local u = OMQ.users[guid]
    if not u then return end
    u.values = u.values or {}
    for i, key in ipairs(KEYS2) do u.values[key] = tonumber(fields[i + 1]) end
    OMQ:Fire("USER_UPDATED", guid)
end
OMQ:RegisterMessage("S2", handleStats2)

-- Session view (decision 135). Me first. Other dads: the members of this session. Those in my
-- group come in group order, those who left follow, flagged away (greyed out by the UI).
-- Without another dad in my group only I am shown.
function OMQ:GetSessionTable()
    local me = self:GetSelf()
    local list = {}
    if me then
        list[1] = { guid = me.guid, name = me.name, class = me.class, version = me.version,
                    isSelf = true, online = true, values = self.Measure:GetValues() }
    end
    local inGroup = {}
    for guid, u in pairs(self.users) do
        if (not me or guid ~= me.guid) and self:IsOnline(u) then
            inGroup[#inGroup + 1] = { guid = guid, name = u.name, class = u.class, version = u.version,
                                      online = true, values = u.values or {}, pos = self:GroupPosition(guid) or 9 }
        end
    end
    table.sort(inGroup, function(a, b)
        if a.pos ~= b.pos then return a.pos < b.pos end
        return (a.name or "") < (b.name or "")
    end)
    local members, fresh = self.Measure:SessionMembers(#inGroup > 0)
    for _, p in ipairs(inGroup) do list[#list + 1] = p end
    if #inGroup == 0 then return list end
    if not fresh then
        local away = {}
        local seen = {}
        for _, p in ipairs(inGroup) do seen[p.guid] = true end
        for guid, m in pairs(members) do
            if not seen[guid] and (not me or guid ~= me.guid) then
                local u = self.users[guid]
                away[#away + 1] = { guid = guid, name = m.name or (u and u.name), class = m.class or (u and u.class),
                                    online = false, away = true, values = u and u.values or {} }
            end
        end
        table.sort(away, function(a, b) return (a.name or "") < (b.name or "") end)
        for _, p in ipairs(away) do list[#list + 1] = p end
    end
    return list
end

OMQ:On("READY", function()
    C_Timer.NewTicker(SEND_INTERVAL, function() OMQ:SendStats() end)
end)
-- A newcomer should see our numbers at once, not after the next interval.
OMQ:On("USER_JOINED", function() OMQ:SendStats() end)
