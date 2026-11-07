-- One More Quest: what the buy mode suggests to stock up (decision 431)
-- Small, cheap buffs at any time instead of only the newest, best item. Every group shows the strongest item
-- I can use whose live price per use stays under the group's limit; none under the limit: no row.
--   Weapon oil (casters: wizard oil, healers: mana oil) and weapon stones (melee, the kind that fits the weapon
--     in hand): at most 2s per use - an oil has 5 uses, so 10s per oil.
--   Scrolls: per category that fits the class, only the highest one under 3s.
--   Elixirs: per stat that makes sense for the class, the highest one under 3s, its rank does not matter.
--   Health and mana potions: at most 5s; a weaker one when needed, but none that needs 20 levels less than mine.
--   Buff food: the cheapest food with Well Fed (+5% XP on WoW Forever), and a food for the class under 3s.
--     When the class food costs at most 50% more than the cheapest one, only the class food is shown.
--   Armor kits and shield spikes stay, at most 15s each.
-- Pure functions: the buy mode (UI/AuctionBuy.lua) feeds them the live prices.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local R = {}
OMQ.BuyRules = R

R.CAP = { oil = 200, stone = 200, scroll = 300, elixir = 300, potion = 500, food = 300, kit = 1500, spike = 1500 }   -- copper per use
R.USES = { oil = 5 }                  -- uses per item; everything else 1
R.POTION_LEVELS = 20                  -- a potion that needs this many levels less than mine is not shown
R.FOOD_CLOSE = 1.5                    -- the class food costs at most this times the cheapest food: only the class food

-- what a class and role is: caster (spell damage), healer, melee (weapon stones), tank, strength, agility, mana
function R.Profile(class, role)
    local p = { class = class, role = role }
    p.healer = role == "heal"
    p.caster = not p.healer and (class == "MAGE" or class == "WARLOCK" or (class == "PRIEST") or role == "caster")
    p.tank = role == "tank"
    p.melee = not p.healer and not p.caster and (class == "WARRIOR" or class == "ROGUE" or class == "PALADIN" or class == "SHAMAN")
    p.str = not p.healer and not p.caster and (class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN" or (class == "DRUID" and p.tank))
    p.agi = not p.healer and not p.caster and (class == "ROGUE" or class == "HUNTER" or class == "WARRIOR" or class == "DRUID" or class == "SHAMAN")
    p.mana = class ~= "WARRIOR" and class ~= "ROGUE"
    return p
end

-- the groups for me: { key, line, kind, cap = copper per item, target } in the order of the list.
-- ctx: { stones = { "stone_sharp", ... } (the kinds my weapons take), kitSlots, spike = true, excluded = { line = true } }
function R.Groups(class, role, ctx)
    ctx = ctx or {}
    local p = R.Profile(class, role)
    local ex = ctx.excluded or {}
    local out = {}
    local function add(line, kind, target)
        if ex[line] or not (OMQ.BuyLines and OMQ.BuyLines[line]) then return end
        local uses = R.USES[kind] or 1
        out[#out + 1] = { key = line, line = line, kind = kind, cap = R.CAP[kind] * uses, target = target }
    end
    add("heal", "potion", 5)
    if p.mana then add("mana", "potion", 5) end
    if p.str then add("e_str", "elixir", 10) end
    if p.agi then add("e_agi", "elixir", 10) end
    if p.caster or p.healer then add("e_int", "elixir", 10); add("e_spell", "elixir", 10) end
    if p.tank then add("e_def", "elixir", 10); add("e_fort", "elixir", 10) end
    add("s_sta", "scroll", 5); add("s_prot", "scroll", 5)
    if p.str then add("s_str", "scroll", 5) end
    if p.agi then add("s_agi", "scroll", 5) end
    if p.caster or p.healer then add("s_int", "scroll", 5); add("s_spi", "scroll", 5) end
    if p.caster then add("oil_wiz", "oil", 2) end
    if p.healer then add("oil_mana", "oil", 2) end
    if p.melee then for _, l in ipairs(ctx.stones or {}) do add(l, "stone", 10) end end
    if (ctx.kitSlots or 0) > 0 then add("kit", "kit", ctx.kitSlots) end
    if ctx.spike then add("spike", "spike", 1) end
    return out, p
end

-- the food line that fits the class: strength, agility, mana per 5 seconds for casters and healers, else stamina
function R.FoodLine(p)
    if p.caster or p.healer then return "f_mp5" end
    if p.tank then return "f_std" end
    if p.agi and not p.str then return "f_agi" end
    if p.str then return "f_str" end
    return "f_std"
end

-- the level an item of a line needs (spikes go by their item level)
function R.Need(line, it)
    local L = OMQ.BuyLines and OMQ.BuyLines[line]
    if L and L[1] == "spike" then return math.max(it[2], it[3] - 5) end
    return it[2]
end

-- the items of a group I could buy, the strongest first: what my level allows, potions not too far below me
function R.Candidates(g, lvl)
    local L = OMQ.BuyLines and OMQ.BuyLines[g.line]
    local out = {}
    for i = #(L and L[2] or {}), 1, -1 do
        local it = L[2][i]
        local need = R.Need(g.line, it)
        local tooLow = g.kind == "potion" and need < lvl - R.POTION_LEVELS
        if need <= lvl and not tooLow then out[#out + 1] = it[1] end
    end
    return out
end

-- the item of a group to show. priceOf(id) -> the live price of one piece, false (nobody sells it) or nil (not known yet).
-- Returns the item and its price, or nil plus true while a stronger item is not priced yet.
function R.Pick(ids, cap, priceOf)
    for _, id in ipairs(ids) do
        local p = priceOf(id)
        if p == nil then return nil, true end
        if p and p <= cap then return id, p end
    end
    return nil, false
end

-- the two food rows: the cheapest food (any buff food I can eat) and the class food under the limit.
-- Returns xpId (or nil), classId (or nil)
function R.Foods(xpId, xpPrice, classId, classPrice)
    if xpId and classId and xpId == classId then return nil, classId end
    if xpId and classId and xpPrice and classPrice and classPrice <= xpPrice * R.FOOD_CLOSE then return nil, classId end
    return xpId, classId
end
