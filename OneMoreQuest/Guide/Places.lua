-- One More Quest: places the player has used (learned points for the guide arrow)
-- Every time a vendor, trainer, mailbox, bank, auction house, flight master or
-- innkeeper window opens, the position is remembered. Positions are saved both
-- as world coordinates (what the arrow needs) and as map coordinates.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local MERGE_YARDS = 25

local P = {}
OMQ.Places = P

local TYPES = { "vendor", "repair", "trainer", "mailbox", "bank", "auction", "flight", "inn" }
P.types = TYPES

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function xyOf(v)
    if type(v) ~= "table" then return nil end
    if v.GetXY then local ok, x, y = pcall(v.GetXY, v); if ok then return x, y end end
    return v.x, v.y
end

local function here()
    if not UnitPosition then return nil end
    local a, b, _, inst = UnitPosition("player")
    if type(a) ~= "number" or type(b) ~= "number" or isSecret(a) or isSecret(b) then return nil end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local x, y
    if map and C_Map.GetPlayerMapPosition then
        local ok, v = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if ok then x, y = xyOf(v) end
    end
    if type(x) ~= "number" or isSecret(x) then x, y = nil, nil end
    return { a = a, b = b, inst = inst, map = map, x = x, y = y }
end

local function npcName()
    for _, unit in ipairs({ "npc", "target" }) do
        if UnitExists and UnitExists(unit) then
            local n = UnitName(unit)
            if n and not isSecret(n) then return n end
        end
    end
end

local function findNear(list, pos)
    for _, p in ipairs(list) do
        if p.map == pos.map and p.inst == pos.inst
            and math.sqrt((p.a - pos.a) ^ 2 + (p.b - pos.b) ^ 2) <= MERGE_YARDS then
            return p
        end
    end
end

function P:Record(kind, name)
    local pos = here()
    if not pos or not pos.map then return end
    OMQDB.places = OMQDB.places or {}
    local list = OMQDB.places[kind] or {}
    OMQDB.places[kind] = list
    do
        local p = findNear(list, pos)
        if p then
            p.n = (p.n or 1) + 1
            p.seen = time()
            if name and not p.name then p.name = name end
            return p, false
        end
    end
    local rec = { name = name, map = pos.map, inst = pos.inst, a = pos.a, b = pos.b, x = pos.x, y = pos.y, n = 1, seen = time() }
    list[#list + 1] = rec
    OMQ:Fire("PLACE_LEARNED", kind, rec)
    return rec, true
end

function P:All(kind) return (OMQDB.places and OMQDB.places[kind]) or {} end

-- The subtitle of the NPC whose window is open ("Magierlehrer", "Mage Trainer"), or nil
function P.NpcTitle()
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, "npc")
        local line = ok and type(data) == "table" and data.lines and data.lines[2]
        local t = line and line.leftText
        if type(t) == "string" and not isSecret(t) then return t end
    end
    return nil
end

-- Is the open trainer my class trainer? (decision 218) Not a profession trainer, and his title names
-- my class in the language of the client; nil when his title cannot be read (then we do not know).
function P.IsMyClassTrainer()
    if IsTradeskillTrainer and IsTradeskillTrainer() then return false end
    local title = P.NpcTitle()
    if not title then return nil end
    local _, class = UnitClass("player")
    local low = title:lower()
    for _, n in ipairs({ LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class],
                         LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[class],
                         (UnitClass("player")), class }) do
        if type(n) == "string" and n ~= "" and low:find(n:lower(), 1, true) then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
local EVENTS = {
    TRAINER_SHOW = function() return "trainer" end,
    MERCHANT_SHOW = function()
        P:Record("vendor", npcName())
        if CanMerchantRepair and CanMerchantRepair() then return "repair" end
    end,
    MAIL_SHOW = function() return "mailbox" end,
    BANKFRAME_OPENED = function() return "bank" end,
    AUCTION_HOUSE_SHOW = function() return "auction" end,
    TAXIMAP_OPENED = function() return "flight" end,
    CONFIRM_BINDER = function() return "inn" end,
}
for e in pairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
frame:SetScript("OnEvent", function(_, event)
    local ok, kind = pcall(EVENTS[event])
    if ok and kind then
        local ok2, rec = pcall(P.Record, P, kind, npcName())
        if not ok2 then OMQ:Error("places " .. kind, rec)
        elseif kind == "trainer" and type(rec) == "table" then
            -- remember whose class trainer it is: trainers missing from the data still count (decision 218)
            local okc, mine = pcall(P.IsMyClassTrainer)
            if okc and mine then rec.cls = select(2, UnitClass("player")) end
        end
    elseif not ok then
        OMQ:Error("places " .. event, kind)
    end
end)

OMQ:On("DB_READY", function() OMQDB.places = OMQDB.places or {} end)

OMQ:RegisterCommand("places", function(arg)
    if arg == "clear" then
        OMQDB.places = {}
        OMQ:Print("learned places cleared")
        return
    end
    local out = { "Learned places (an entry is merged within " .. MERGE_YARDS .. " yards)" }
    for _, kind in ipairs(TYPES) do
        local list = P:All(kind)
        out[#out + 1] = string.format("%s (%d)", kind, #list)
        for _, p in ipairs(list) do
            out[#out + 1] = string.format("  %s  map %s  world %.1f, %.1f  map %s, %s  x%d",
                p.name or "?", tostring(p.map), p.a, p.b,
                p.x and string.format("%.1f", p.x * 100) or "?", p.y and string.format("%.1f", p.y * 100) or "?", p.n or 1)
        end
    end
    OMQ:ShowReport(out)
end, "list the places the addon has learned; /omq places clear")

----------------------------------------------------------------------
-- Sharing (decision 122): learned places travel to the group members who run the
-- addon, so a vendor one dad found is known to all of them. A new place is sent at
-- once; when someone joins, the whole list is sent (one message per second). Received
-- places are merged like own ones (same spot within MERGE_YARDS = the same place).
----------------------------------------------------------------------
local MAX_PER_KIND = 200
local MAX_MSG = 220            -- bytes of entries per message (the limit is 255 with the header)
local queue = {}
local lastFull = -math.huge

local function shareOn()
    return OMQ:Master("group") and OMQ.db and OMQ.db.guide and OMQ.db.guide.sharePlaces ~= false
end

local KIND_SET = {}
for _, k in ipairs(TYPES) do KIND_SET[k] = true end

-- the name cut to a few bytes, never in the middle of a UTF-8 letter, without separators
local function cleanName(name)
    if type(name) ~= "string" then return "" end
    name = name:gsub("[|,:]", " "):sub(1, 22)
    while #name > 0 do
        local b = name:byte(#name)
        if b >= 128 and b < 192 then name = name:sub(1, #name - 1)           -- half a letter
        elseif b >= 192 then name = name:sub(1, #name - 1); break             -- the start of a cut letter
        else break end
    end
    return name
end

local function encodePlace(p)
    return string.format("%d,%s,%.1f,%.1f,%s,%s,%s", p.map, tostring(p.inst or 0), p.a, p.b,
        p.x and string.format("%.4f", p.x) or "", p.y and string.format("%.4f", p.y) or "", cleanName(p.name))
end

local function decodePlace(s)
    local map, inst, a, b, x, y, name = s:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),?(.*)$")
    map, inst, a, b = tonumber(map), tonumber(inst), tonumber(a), tonumber(b)
    if not (map and inst and a and b) then return nil end
    return { map = map, inst = inst, a = a, b = b, x = tonumber(x), y = tonumber(y),
             name = name ~= "" and name or nil }
end

-- adds a received place unless the same spot is already known; true when it was new
function P:Merge(kind, rec)
    if not KIND_SET[kind] then return false end
    OMQDB.places = OMQDB.places or {}
    local list = OMQDB.places[kind] or {}
    OMQDB.places[kind] = list
    local near = findNear(list, rec)
    if near then
        if rec.name and not near.name then near.name = rec.name end
        if rec.x and not near.x then near.x, near.y = rec.x, rec.y end
        return false
    end
    if #list >= MAX_PER_KIND then return false end
    list[#list + 1] = { name = rec.name, map = rec.map, inst = rec.inst, a = rec.a, b = rec.b,
                        x = rec.x, y = rec.y, n = 0, seen = time(), shared = true }
    return true
end

local function enqueueKind(kind, places)
    local fields, size = { kind }, #kind
    for _, p in ipairs(places) do
        local e = encodePlace(p)
        if size + #e + 1 > MAX_MSG and #fields > 1 then
            queue[#queue + 1] = fields
            fields, size = { kind }, #kind
        end
        fields[#fields + 1] = e
        size = size + #e + 1
    end
    if #fields > 1 then queue[#queue + 1] = fields end
end

function P:ShareAll()
    if not shareOn() then return end
    if GetTime() - lastFull < 30 then return end
    lastFull = GetTime()
    for _, kind in ipairs(TYPES) do
        local list = self:All(kind)
        if #list > 0 then enqueueKind(kind, list) end
    end
end

function P:QueueLength() return #queue end

OMQ:On("PLACE_LEARNED", function(kind, rec)
    if shareOn() and rec and rec.map then enqueueKind(kind, { rec }) end
end)

OMQ:On("USER_JOINED", function() pcall(P.ShareAll, P) end)

OMQ:On("READY", function()
    C_Timer.NewTicker(1, function()
        if #queue == 0 then return end
        if not shareOn() or not OMQ:GetChannel() then queue = {}; return end
        local m = table.remove(queue, 1)
        OMQ:SendBulk("PL", unpack(m))
    end)
end)

OMQ:RegisterMessage("PL", function(fields)
    if not shareOn() then return end
    local kind = fields[1]
    if not KIND_SET[kind] then return end
    local added = 0
    for i = 2, #fields do
        local rec = decodePlace(fields[i])
        if rec and P:Merge(kind, rec) then added = added + 1 end
    end
    if added > 0 then OMQ:Fire("PLACES_SHARED", kind, added) end
end)
