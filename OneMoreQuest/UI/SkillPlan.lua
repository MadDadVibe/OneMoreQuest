-- One More Quest: cheapest skill-up plan (decision 592)
-- For every skill point from the current skill on, the recipe with the lowest expected cost per skill-up: the
-- material cost of one craft divided by the chance at that skill (1 below yellow, then linear down to 0 at gray).
-- Recipes: the ones the player knows, plus the ones a trainer teaches from their trainer skill on (Data/ProfSkillUp.lua,
-- SkillUp Forever). Vendor and drop recipes only when known. The trainer fee does not count in the choice; the plan
-- names it. The plan stops at the rank cap (max skill) or the target. A recipe with a material nobody prices is left
-- out. Material costs: the known price of the finished material (OMQ.ProfCheck.Price, else the Forever vendor price).
-- Decision 673 (replaces 639): an intermediate (Medium Leather, bolts, cured hides ...) is never made from its raw
-- materials for the plan; it is bought finished and goes into the shopping list as itself.
-- Decision 677: the choice counts the net cost per skill-up: materials minus what the crafted item brings back
-- (the higher of its vendor price and its disenchant value, OMQ.Disenchant.Value; unknown = 0), plus the trainer fee
-- of a recipe not known yet, spread over the skill points it can still give up to gray and paid once (a recipe the plan
-- has chosen is free after that). A profit (return above the materials) counts once per skill-up, not per craft, so the
-- plan does not chase recipes that are nearly gray. The auction house return is only shown, not chosen by.
-- Shopping lists from the plan buy more than the expected crafts: decision 660, the average plus 1.28 times the
-- spread of the step's skill-up chances (enough in about 9 of 10 cases; before: +40% green, +20% yellow).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local SP = {}
OMQ.SkillPlan = SP

-- decision 660: the list buys the average crafts plus 1.28 times their spread (OMQ.ProfCheck.SAFE_Z), like the cells
function SP.SAFE_Z() return (OMQ.ProfCheck and OMQ.ProfCheck.SAFE_Z) or 1.28 end
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

-- a cost context for one plan: cost(item) = the price of the finished item (decision 673: never made)
local function context(line)
    local function recipeCost(id)
        local r = OMQ.ProfSkillUp[id]
        if not r then return nil end
        local sum = 0
        for k = 1, #r[4], 2 do
            local c = price(r[4][k])
            if not c then return nil end
            sum = sum + c * r[4][k + 1]
        end
        return sum
    end
    return { cost = price, recipeCost = recipeCost }
end
SP.Context = context

-- what one craft of a recipe brings back: pieces times the higher of vendor price and disenchant value (copper)
function SP.Return(id)
    local r = OMQ.ProfSkillUp[id]
    if not (r and r[2] and r[2] > 0) then return 0 end
    local PC, D = OMQ.ProfCheck, OMQ.Disenchant
    local v = PC and PC.SellPrice and PC.SellPrice(r[2]) or 0
    local de = D and D.Value and D.Value(r[2]) or 0
    return (r[3] or 1) * math.max(v or 0, de or 0)
end

-- the plan from skill to target (stops at max): { steps = { { from, to, spell, crafts, buy, learn = { fee, skill } } },
-- reached, total (expected net cost: mats + fees - ret, decision 677), mats, ret, fees, missing (recipes left out for a missing price), stop ("cap", "none", nil) }
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
                if c then cands[#cands + 1] = { id = id, t = t, cost = c, ret = SP.Return(id), known = known,
                    fee = (not known) and (r[5] or 0) or 0, from = known and 0 or (r[6] or t[1]) } 
                else missing = missing + 1 end
            end
        end
    end
    local plan = { steps = {}, total = 0, mats = 0, ret = 0, fees = 0, missing = missing }
    local stopAt = target
    if max and max > 0 and max < 300 and max <= stopAt then stopAt = max; plan.stop = "cap" end
    local s = skill
    while s < stopAt do
        local best, bestPer
        for _, c in ipairs(cands) do
            if s >= c.from and s >= (c.t[1] or 0) then
                local ch = chance(s, c.t)
                if ch > 0 then
                    local net = c.cost - c.ret
                    local per = math.max(net, 0) / ch + math.min(net, 0)
                    if not c.paid and c.fee > 0 then per = per + c.fee / math.max(1, c.t[4] - s) end
                    if not bestPer or per < bestPer - 1e-9 then best, bestPer = c, per end
                end
            end
        end
        if not best then plan.stop = "none"; break end
        local ch = chance(s, best.t)
        local var = (1 - ch) / (ch * ch)
        local last = plan.steps[#plan.steps]
        if last and last[3] == best.id and last[2] == s then
            last[2] = s + 1; last[4] = last[4] + 1 / ch; last.var = last.var + var
        else
            last = { s, s + 1, best.id, 1 / ch, 0, var = var,
                learn = (not best.known and not best.paid) and { OMQ.ProfSkillUp[best.id][5], best.from } or nil }
            plan.steps[#plan.steps + 1] = last
        end
        last[5] = last[4] + SP.SAFE_Z() * math.sqrt(last.var)
        plan.mats = plan.mats + best.cost / ch
        plan.ret = plan.ret + best.ret / ch
        if not best.paid then best.paid = true; plan.fees = plan.fees + best.fee end
        s = s + 1
    end
    plan.total = plan.mats + plan.fees - plan.ret
    plan.reached = s
    plan.ctx = ctx
    return plan
end

-- the materials to buy for a plan: { [item] = pieces }, intermediates as themselves (decision 673)
function SP.Materials(plan)
    local out = {}
    for _, st in ipairs(plan.steps) do
        local r = OMQ.ProfSkillUp[st[3]]
        local crafts = math.ceil(st[5] - 1e-6)
        for k = 1, #r[4], 2 do out[r[4][k]] = (out[r[4][k]] or 0) + r[4][k + 1] * crafts end
    end
    return out
end

-- what the plan's expected crafts make, to sell (decision 673): { [item] = pieces }; for OMQ.ProfCheck.Returns
function SP.Products(plan)
    local out = {}
    for _, st in ipairs(plan and plan.steps or {}) do
        local r = OMQ.ProfSkillUp[st[3]]
        if r and r[2] and r[2] > 0 then out[r[2]] = (out[r[2]] or 0) + (r[3] or 1) * st[4] end
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
