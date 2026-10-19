-- One More Quest: gear sync (decision 198)
-- Every dad sends what he wears, so Alt on an item can show the real items of the other dads
-- next to the item tooltip (Compare.lua). Sent when a dad joins, when the gear changes and on a
-- level up. Only item strings travel, nothing else.
--   EQ|proto|guid|level|slot=item;slot=item;...|role   (one or more messages; an empty value = empty
--                                                   slot; role for the item score, decision 200)
-- An item is packed as the first 8 fields of the item string (id, enchant, 4 gems, suffix, unique),
-- zeros left out and trailing empties cut: "item:4385:0:0:0:0:0:0:0" becomes "4385".
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local G = {}
OMQ.Gear = G

G.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }   -- no shirt, no tabard
G.MAX_DATA = 200                 -- characters of slot data per message (the limit is 255 in all)
local CHANGE_DELAY = 1.5         -- gear changes are collected for a moment and sent together
local JOIN_DELAY = 2
local FULL_GAP = 5               -- never two full sends closer than this

function G.Pack(link)
    if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return "" end
    local s = link:match("item:([%-%d:]*)")
    if not s then return "" end
    local f, i = {}, 0
    for v in (s .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if i > 8 then break end
        f[i] = (v == "0") and "" or v
    end
    while #f > 0 and f[#f] == "" do f[#f] = nil end
    return table.concat(f, ":")
end

function G.Unpack(p)
    if type(p) ~= "string" or p == "" then return nil end
    local f = {}
    for v in (p .. ":"):gmatch("([^:]*):") do f[#f + 1] = (v == "") and "0" or v end
    if not tonumber(f[1]) then return nil end
    while #f < 8 do f[#f + 1] = "0" end
    return "item:" .. table.concat(f, ":")
end

-- the data strings for a list of slots, cut into messages
function G.Chunks(slots, linkOf)
    local out, cur = {}, {}
    local len = 0
    for _, slot in ipairs(slots) do
        local part = slot .. "=" .. G.Pack(linkOf(slot))
        if len + #part + 1 > G.MAX_DATA and #cur > 0 then
            out[#out + 1] = table.concat(cur, ";")
            cur, len = {}, 0
        end
        cur[#cur + 1] = part
        len = len + #part + 1
    end
    if #cur > 0 or #out == 0 then out[#out + 1] = table.concat(cur, ";") end
    return out
end

-- reads a data string into a gear table: slot -> item string, false for an empty slot
function G.Apply(gear, data)
    for slot, v in (data or ""):gmatch("(%d+)=([^;]*)") do
        gear[tonumber(slot)] = G.Unpack(v) or false
    end
    return gear
end

local function myLink(slot) return GetInventoryItemLink and GetInventoryItemLink("player", slot) or nil end

function G:Send(slots)
    local me = OMQ:GetSelf()
    if not me or not OMQ:GetChannel() then return false end
    local level = UnitLevel and UnitLevel("player") or 0
    for _, data in ipairs(G.Chunks(slots, myLink)) do
        OMQ:SendBulk("EQ", me.guid, tostring(level), data, OMQ.Score and OMQ.Score.MyRole() or "")
    end
    return true
end

local lastFull = -100
function G:SendAll(force)
    local now = GetTime()
    if not force and now - lastFull < FULL_GAP then return false end
    if self:Send(G.SLOTS) then lastFull = now; return true end
    return false
end

-- the gear of another dad (slot -> item string or false), his level
function G:Of(guid)
    local u = guid and OMQ.users[guid]
    if not u then return nil end
    return u.gear, u.level, u.role
end

local function preload(link)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

OMQ:RegisterMessage("EQ", function(f)
    local guid, level, data = f[1], f[2], f[3]
    local me = OMQ:GetSelf()
    if not guid or guid == "" or (me and guid == me.guid) then return end
    local u = OMQ.users[guid]
    if not u then return end                    -- gear only from dads we know via HELLO
    u.gear = G.Apply(u.gear or {}, data)
    u.level = tonumber(level) or u.level
    if f[4] and f[4] ~= "" then u.role = f[4] end
    u.gearAt = GetTime()
    for _, l in pairs(u.gear) do if l then preload(l) end end
    OMQ:Fire("GEAR_UPDATED", guid)
end)

-- a new dad: everybody sends his gear once (collected for a moment)
local joinPending = false
OMQ:On("USER_JOINED", function()
    if joinPending then return end
    joinPending = true
    C_Timer.After(JOIN_DELAY, function() joinPending = false; G:SendAll() end)
end)

local pending, pendingTimer = {}, false
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_EQUIPMENT_CHANGED")
pcall(ev.RegisterEvent, ev, "PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, event, slot)
    if event == "PLAYER_LEVEL_UP" then
        C_Timer.After(1, function() G:Send({}) end)        -- only the new level
        return
    end
    slot = tonumber(slot)
    if not slot or slot == 4 or slot == 19 or slot > 18 then return end
    pending[slot] = true
    if pendingTimer then return end
    pendingTimer = true
    C_Timer.After(CHANGE_DELAY, function()
        pendingTimer = false
        local list = {}
        for _, s in ipairs(G.SLOTS) do if pending[s] then list[#list + 1] = s end end
        pending = {}
        if #list > 0 then G:Send(list) end
    end)
end)

OMQ:On("READY", function()
    C_Timer.After(5, function() G:SendAll() end)
end)
