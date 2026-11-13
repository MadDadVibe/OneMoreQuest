-- One More Quest: cheapest skill-up plan (decision 592)
-- For every skill point from the current skill on, the recipe with the lowest expected cost per skill-up: the
-- material cost of one craft divided by the chance at that skill (1 below yellow, then linear down to 0 at gray).
-- Recipes: the ones the player knows, plus the ones a trainer teaches from their trainer skill on (Data/ProfSkillUp.lua,
-- SkillUp Forever). Vendor and drop recipes only when known. The trainer fee does not count in the choice; the plan
-- names it. The plan stops at the rank cap (max skill) or the target. A recipe with a material nobody prices is left
-- out. Material costs: the cheaper of the known price (OMQ.ProfCheck.Price) and making it with a recipe of the same
-- profession from priced materials (3 deep); a made intermediate goes into the shopping list as its raw materials.
-- Shopping lists from the plan buy more than the expected crafts: +40% for crafts at a green skill, +20% at yellow.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local SP = {}
OMQ.SkillPlan = SP

SP.DEPTH = 3
SP.BUY_GREEN, SP.BUY_YELLOW = 1.4, 1.2
SP.MAJORS = { 75, 150, 225, 300 }

local function chance(s, t)
    if s < t[2] then return 1 end
    if s >= t[4] then return 0 end
    return (t[4] - s) / (t[4] - t[2])
end
SP.Chance = chance

-- the recipes of a skill line: { spell, ... } (cached)
local byLine
function SP.Recipes(line)
    if not byLine then
        byLine = {}
        local ids = {}
        for id in pairs(OMQ.ProfSkillUp or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local r = OMQ.ProfSkillUp[id]
            byLine[r[1]] = byLine[r[1]] or {}
            table.insert(byLine[r[1]], id)
        end
    end
    return byLine[line] or {}
end

-- price of one piece: the known price, else the vendor price of the data
local function price(item)
    local p = OMQ.ProfCheck and OMQ.ProfCheck.Price(item)
    if p then return p end
    local v = (OMQ.ProfSkillUpVendor or {})[item]
    if v and v > 0 then return v end
end

-- a cost context for one plan: cost(item) = cheapest of buying and making; make(item) = recipe that makes it cheaper
local function context(line)
    local makers = {}
    for _, id in ipairs(SP.Recipes(line)) do
        local r = OMQ.ProfSkillUp[id]
        if r[2] > 0 and not makers[r[2]] then makers[r[2]] = id end
    end
    local memo, how = {}, {}
    local cost
    local function recipeCost(id, depth)
        local r = OMQ.ProfSkillUp[id]
        if not r then return nil end
        local sum = 0
        for k = 1, #r[4], 2 do
            local c = cost(r[4][k], depth + 1)
            if not c then return nil end
            sum = sum + c * r[4][k + 1]
        end
        return sum
    end
    cost = function(item, depth)
        depth = depth or 0
        if memo[item] ~= nil and depth <= 1 then return memo[item] or nil end
        local best = price(item)
        local m = makers[item]
        if m and depth < SP.DEPTH then
            local c = recipeCost(m, depth)
            local y = OMQ.ProfSkillUp[m][3] or 1
            if c and (not best or c / y < best) then best = c / y; how[item] = m end
        end
        if depth <= 1 then memo[item] = best or false end
        return best
    end
    return { cost = cost, recipeCost = function(id) return recipeCost(id, 0) end, how = how }
end
SP.Context = context

-- the plan from skill to target (stops at max): { steps = { { from, to, spell, crafts, buy, learn = { fee, skill } } },
-- reached, total (expected cost), missing (recipes left out for a missing price), stop ("cap", "none", nil) }
function SP.Plan(line, skill, target, max, learned)
    learned = learned or function(id) return OMQ.SkillRoute and OMQ.SkillRoute.Learned(id) end
    local ctx = context(line)
    local T = OMQ.SkillThresholds or {}
    local cands, missing = {}, 0
    for _, id in ipairs(SP.Recipes(line)) do
        local r, t = OMQ.ProfSkillUp[id], T[id]
        if t and t[4] and t[4] > skill then
            local known = learned(id) == true
            if known or r[5] then
                local c = ctx.recipeCost(id)
                if c then cands[#cands + 1] = { id = id, t = t, cost = c, known = known, from = known and 0 or (r[6] or t[1]) }
                else missing = missing + 1 end
            end
        end
    end
    local plan = { steps = {}, total = 0, missing = missing }
    local stopAt = target
    if max and max > 0 and max < 300 and max <= stopAt then stopAt = max; plan.stop = "cap" end
    local s = skill
    while s < stopAt do
        local best, bestPer
        for _, c in ipairs(cands) do
            if s >= c.from and s >= (c.t[1] or 0) then
                local ch = chance(s, c.t)
                if ch > 0 then
                    local per = c.cost / ch
                    if not bestPer or per < bestPer - 1e-9 then best, bestPer = c, per end
                end
            end
        end
        if not best then plan.stop = "none"; break end
        local ch = chance(s, best.t)
        local buy = (s >= best.t[3] and SP.BUY_GREEN) or (s >= best.t[2] and SP.BUY_YELLOW) or 1
        local last = plan.steps[#plan.steps]
        if last and last[3] == best.id and last[2] == s then
            last[2] = s + 1; last[4] = last[4] + 1 / ch; last[5] = last[5] + buy / ch
        else
            plan.steps[#plan.steps + 1] = { s, s + 1, best.id, 1 / ch, buy / ch,
                learn = (not best.known) and { OMQ.ProfSkillUp[best.id][5], best.from } or nil }
        end
        plan.total = plan.total + bestPer
        s = s + 1
    end
    plan.reached = s
    plan.ctx = ctx
    return plan
end

-- the materials to buy for a plan: { [item] = pieces } (intermediates made cheaper go in as their materials)
function SP.Materials(plan)
    local ctx, out = plan.ctx, {}
    local function add(item, n, depth)
        local m = ctx.how[item]
        if m and depth < SP.DEPTH then
            local r = OMQ.ProfSkillUp[m]
            local crafts = n / (r[3] or 1)
            for k = 1, #r[4], 2 do add(r[4][k], r[4][k + 1] * crafts, depth + 1) end
        else
            out[item] = (out[item] or 0) + n
        end
    end
    for _, st in ipairs(plan.steps) do
        local r = OMQ.ProfSkillUp[st[3]]
        local crafts = math.ceil(st[5] - 1e-6)
        for k = 1, #r[4], 2 do
            ctx.cost(r[4][k])
            add(r[4][k], r[4][k + 1] * crafts, 0)
        end
    end
    return out
end

-- the next major step above a skill, capped by the max skill
function SP.NextMajor(skill, max)
    local m = 300
    for _, x in ipairs(SP.MAJORS) do if x > skill then m = x; break end end
    if max and max > skill and max < m then m = max end
    return m
end

-- the shopping list of the cheapest plan for n points (n = "major": to the next major step)
function SP.ShoppingList(route, skill, max, n)
    local target = n == "major" and SP.NextMajor(skill, max) or math.min(300, skill + n)
    local plan = SP.Plan(route.id, skill, target, max)
    local mats = SP.Materials(plan)
    local items = {}
    for item, cnt in pairs(mats) do
        local p, from = OMQ.ProfCheck.Price(item)
        if not p then p = (OMQ.ProfSkillUpVendor or {})[item]; from = p and "vendor" or nil end
        local c = math.ceil(cnt - 1e-6)
        if c > 0 then items[#items + 1] = { itemID = item, n = c, plan = p, vendor = (from == "vendor") or nil } end
    end
    table.sort(items, function(a, c)
        local va, vc = (a.plan or 0) * a.n, (c.plan or 0) * c.n
        if va ~= vc then return va > vc end
        return a.itemID < c.itemID
    end)
    local title = string.format("%s %d-%d cheapest", OMQ.ProfCheck.ProfName(route), skill, plan.reached)
    return { key = "cheap:" .. route.id, title = title, source = "prof", items = items }, plan
end
