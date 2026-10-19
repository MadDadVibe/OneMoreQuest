-- One More Quest: data - the six major cities (map IDs confirmed on WoW Forever)
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

OMQ.cityMaps = {
    [1453] = "Stormwind City",
    [1454] = "Orgrimmar",
    [1455] = "Ironforge",
    [1456] = "Thunder Bluff",
    [1457] = "Darnassus",
    [1458] = "Undercity",
}

function OMQ:InMajorCity()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    return map ~= nil and self.cityMaps[map] ~= nil
end

-- in a town (decision 308): a major city, resting (inn), or a settlement - at least TOWN_PLACES known places
-- (innkeeper, vendor, repair, trainer, flight master ...) within TOWN_YARDS, or at least HUB_GIVERS quest
-- givers there (a quest hub). Worked out at most every TOWN_EVERY seconds.
OMQ.TOWN_YARDS, OMQ.TOWN_PLACES, OMQ.HUB_GIVERS, OMQ.TOWN_EVERY = 60, 2, 3, 5
local townAt, townWas = -100, false
function OMQ:InTown()
    if self:InMajorCity() then return true end
    if IsResting and IsResting() then return true end
    local now = GetTime and GetTime() or 0
    if now - townAt < OMQ.TOWN_EVERY then return townWas end
    townAt, townWas = now, false
    if not UnitPosition then return false end
    local a, b, _, inst = UnitPosition("player")
    if type(a) ~= "number" or type(b) ~= "number" or (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return false end
    local r2 = OMQ.TOWN_YARDS * OMQ.TOWN_YARDS
    local G = OMQ.Guide
    if G and G.WorldOf then
        local n = 0
        for _, p in ipairs(OMQ.fixedPlaces or {}) do
            local w = G.WorldOf(p)
            if w and w[3] == inst and (w[1] - a) ^ 2 + (w[2] - b) ^ 2 <= r2 then
                n = n + 1
                if n >= OMQ.TOWN_PLACES then townWas = true; return true end
            end
        end
    end
    local NQ = OMQ.NextQuest
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if NQ and NQ.World and map then
        local n = 0
        for _, d in pairs(OMQ.QuestPlaces or {}) do
            for _, s in ipairs(d[7] or {}) do
                if s[1] == map then
                    local w = NQ.World(s)
                    if w and w[3] == inst and (w[1] - a) ^ 2 + (w[2] - b) ^ 2 <= r2 then
                        n = n + 1
                        if n >= OMQ.HUB_GIVERS then townWas = true; return true end
                        break
                    end
                end
            end
        end
    end
    return false
end
