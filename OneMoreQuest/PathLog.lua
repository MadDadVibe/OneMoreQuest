-- One More Quest: recording where the dads really walk (decision 469)
-- Every TICK seconds the place where I stand, and the places the other dads of the group send (message "P"),
-- go into a grid of CELL yards per continent: OMQDB.pathLog.cells[continent][key] = times seen (at most 255).
-- Only on the ground: not on a flight, not dead, not in a dungeon, not faster than MAX_SPEED (a flight or a
-- boat). Where my map changes between two samples on foot, the crossing is kept too:
-- OMQDB.pathLog.cross["from>to"] = { continent, x, y, times }. Nothing is sent anywhere; the data stays in the
-- saved variables and later versions build better ways from it. At most MAX_CELLS cells per continent.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local L = {}
OMQ.PathLog = L

L.TICK = 2
L.CELL = 20
L.MAX_SPEED = 16            -- yards per second; a fast mount runs about 14
L.MAX_CELLS = 60000
L.MAX_CROSS = 2000
L.STALE = 4                 -- a position message older than this is not recorded

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not isSecret(v) end

function L:Store()
    if not OMQDB then return nil end
    local s = OMQDB.pathLog
    if type(s) ~= "table" or s.v ~= 1 then
        s = { v = 1, cells = {}, count = {}, cross = {}, ncross = 0, samples = 0 }
        OMQDB.pathLog = s
    end
    return s
end

function L.Key(a, b)
    return (math.floor(a / L.CELL) + 5000) * 10000 + (math.floor(b / L.CELL) + 5000)
end

-- one sample at a, b on that continent; true when it was kept
function L:Add(inst, a, b)
    local s = self:Store()
    if not (s and num(inst) and num(a) and num(b)) then return false end
    local cells = s.cells[inst]
    if not cells then cells = {}; s.cells[inst] = cells; s.count[inst] = 0 end
    local k = L.Key(a, b)
    local n = cells[k]
    if n == nil then
        if (s.count[inst] or 0) >= L.MAX_CELLS then return false end
        s.count[inst] = (s.count[inst] or 0) + 1
        n = 0
    end
    if n < 255 then cells[k] = n + 1 end
    s.samples = (s.samples or 0) + 1
    return true
end

function L:Cross(from, to, inst, a, b)
    local s = self:Store()
    if not (s and num(from) and num(to) and from ~= to) then return end
    local key = from .. ">" .. to
    local c = s.cross[key]
    if not c then
        if (s.ncross or 0) >= L.MAX_CROSS then return end
        s.ncross = (s.ncross or 0) + 1
        c = { inst, math.floor(a + 0.5), math.floor(b + 0.5), 0 }
        s.cross[key] = c
    end
    c[4] = c[4] + 1
end

local last = {}             -- guid or "me" -> { a, b, inst, map, at }

-- a sample of who (me or a guid): kept when it is on the ground and not too fast since the last one
function L:Sample(who, a, b, inst, map, now, onGround)
    local prev = last[who]
    if prev and now - prev.at < L.TICK / 2 then return false end      -- a second sample at the same moment
    last[who] = { a = a, b = b, inst = inst, map = map, at = now }
    if not onGround then return false end
    if prev and prev.inst == inst then
        local dt = now - prev.at
        local d = math.sqrt((a - prev.a) ^ 2 + (b - prev.b) ^ 2)
        if d / dt > L.MAX_SPEED then return false end
        if who == "me" and num(map) and num(prev.map) and map ~= prev.map and dt <= L.TICK * 2 + 1 then
            self:Cross(prev.map, map, inst, (a + prev.a) / 2, (b + prev.b) / 2)
        end
        if L.Key(a, b) == L.Key(prev.a, prev.b) then return false end   -- counted once per cell entered
    end
    return self:Add(inst, a, b)
end

local function inDungeon()
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    return inside and kind ~= "none"
end

function L:Tick()
    if OMQDB and OMQDB.pathLogOff then return end
    local now = GetTime()
    if UnitPosition and not inDungeon() then
        local a, b, _, inst = UnitPosition("player")
        if num(a) and num(b) then
            local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local ground = not (UnitOnTaxi and UnitOnTaxi("player")) and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
            self:Sample("me", a, b, inst, num(map) and map or nil, now, ground)
        end
    end
    local me = OMQ.GetSelf and OMQ:GetSelf()
    for guid, u in pairs(OMQ.users or {}) do
        local p = type(u) == "table" and u.pos
        if p and guid ~= (me and me.guid) and now - (p.at or 0) <= L.STALE and (not last[guid] or last[guid].at ~= p.at) then
            local prev = last[guid]
            if not prev or prev.a ~= p.a or prev.b ~= p.b then
                self:Sample(guid, p.a, p.b, p.inst, p.map, p.at, not p.taxi and not p.dead)
            else
                last[guid].at = p.at
            end
        end
    end
end

function L:Summary()
    local s = self:Store()
    if not s then return "recorded ways: none" end
    local parts = {}
    for inst, n in pairs(s.count or {}) do parts[#parts + 1] = string.format("continent %s: %d cells", tostring(inst), n) end
    table.sort(parts)
    return string.format("recorded ways: %d samples, %s, %d zone crossings", s.samples or 0,
        #parts > 0 and table.concat(parts, ", ") or "no cells", s.ncross or 0)
end

function L._Reset() last = {} end

OMQ:On("READY", function()
    C_Timer.NewTicker(L.TICK, function()
        local ok, err = pcall(L.Tick, L)
        if not ok then OMQ:Error("pathlog", err) end
    end)
end)
