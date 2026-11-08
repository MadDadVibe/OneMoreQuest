-- One More Quest: the pet basics (decision 241, improvement 18 "the basics every class forgets")
-- Out of combat, alive, not mounted and not on a flight:
--   hunter:  no pet out           -> "Call your pet"   (click casts Call Pet)
--            pet dead             -> "Revive your pet" (click casts Revive Pet); a dead hunter pet is gone from
--                                    the "pet" unit, so its death is remembered per character (seen dead, Call Pet
--                                    failed) until it is back alive or Revive Pet went through
--            pet not happy        -> "Feed your pet"   (from "content" on; the click feeds the cheapest food in the
--                                    bags that the pet eats: a macro /cast Feed Pet + /use bag slot; no such food:
--                                    the click casts Feed Pet, then click the food) (v1.3.67)
--   warlock: no demon out         -> up to three cards "Summon <demon>": the last three demons he summoned
--                                    (kept per character), filled up with Imp, Voidwalker, Succubus; only learned ones
--                                    (decision 340)
-- Only spells the character knows are asked for. Paladin auras and the shaman's Lightning Shield are
-- buff groups in Data/Buffs.lua; aspects, armors, imbues and poisons were there already.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local P = {}
OMQ.PetBasics = P

P.CALL, P.REVIVE, P.FEED = 883, 982, 6991
P.DEMONS = { 688, 697, 712 }     -- the defaults when nothing was summoned yet: Imp, Voidwalker, Succubus (Incubus)
P.ALL_DEMONS = { 688, 697, 712, 691, 30146 }        -- also Felhunter and Felguard count as used demons
P.KEEP = 3
local ALL = {}
for _, id in ipairs(P.ALL_DEMONS) do ALL[id] = true end

local function knows(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function icon(id)
    return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or "Interface\\Icons\\Ability_Hunter_BeastCall"
end
local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function flag(fn, ...)
    if not fn then return false end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then return nil end
    return v and true or false
end

-- the last demons summoned by this character, most recent first (saved with the alerts, per GUID)
local function recentList(create)
    local guid = UnitGUID and UnitGUID("player")
    if not (guid and OMQ.db) then return nil end
    OMQ.db.alerts = OMQ.db.alerts or {}
    local a = OMQ.db.alerts
    a.demons = a.demons or {}
    if create and not a.demons[guid] then a.demons[guid] = {} end
    return a.demons[guid]
end

function P.Remember(id)
    if not ALL[id] then return false end
    local list = recentList(true)
    if not list then return false end
    for i = #list, 1, -1 do if list[i] == id then table.remove(list, i) end end
    table.insert(list, 1, id)
    while #list > P.KEEP do table.remove(list) end
    return true
end

-- the demons to offer: the recent ones, then the defaults, only the learned, at most three
function P.Offer()
    local out, seen = {}, {}
    local function add(id)
        if #out < P.KEEP and not seen[id] and knows(id) then seen[id] = true; out[#out + 1] = id end
    end
    for _, id in ipairs(recentList(false) or {}) do add(id) end
    for _, id in ipairs(P.DEMONS) do add(id) end
    return out
end

-- the hunter pet's death, kept per character (a dead pet is not the "pet" unit any more, also not after a relog)
function P.IsDead()
    local guid = UnitGUID and UnitGUID("player")
    local a = OMQ.db and OMQ.db.alerts
    return (guid and a and a.petDead and a.petDead[guid]) and true or false
end
function P.SetDead(v)
    local guid = UnitGUID and UnitGUID("player")
    if not (guid and OMQ.db) then return end
    OMQ.db.alerts = OMQ.db.alerts or {}
    local a = OMQ.db.alerts
    a.petDead = a.petDead or {}
    a.petDead[guid] = v and true or nil
end

-- 1 unhappy, 2 content, 3 happy; Forever has it in C_PetInfo, older clients as a global
function P.Happiness()
    local fn = (C_PetInfo and C_PetInfo.GetPetHappiness) or GetPetHappiness
    if not fn then return nil end
    local ok, happy = pcall(fn)
    if not ok or isSecret(happy) or type(happy) ~= "number" then return nil end
    return happy
end

-- ---- feeding (v1.3.67): the cheapest food in the bags that the pet eats
-- diet names as the game gives them (GetPetFoodTypes), English and German, -> food types of Data/PetFood.lua
P.DIET = { meat = { 1, 7 }, fish = { 2, 8 }, cheese = { 3 }, bread = { 4 }, fungus = { 5 }, fruit = { 6 },
           ["raw meat"] = { 7 }, ["raw fish"] = { 8 },
           fleisch = { 1, 7 }, fisch = { 2, 8 }, ["käse"] = { 3 }, brot = { 4 }, pilz = { 5 }, pilze = { 5 }, obst = { 6 },
           ["frucht"] = { 6 }, ["früchte"] = { 6 }, ["rohes fleisch"] = { 7 }, ["roher fisch"] = { 8 } }
P.LEVEL_GAP = 30           -- food this many levels below the pet is not eaten
P.EAT_TIME = 30            -- after a feed the card waits this long for the mood to rise
P.refused = {}             -- item id -> true: the pet refused it (wrong food or too low), until the next pet

function P.Diet()
    local fn = (C_PetInfo and C_PetInfo.GetPetFoodTypes) or GetPetFoodTypes
    if not fn then return nil end
    local ok, a, b, c, d, e, f = pcall(fn)
    if not ok then return nil end
    local list = type(a) == "table" and a or { a, b, c, d, e, f }
    local set, any = {}, false
    for _, n in pairs(list) do
        if type(n) == "string" and not isSecret(n) then
            local t = P.DIET[n:lower()]
            if t then for _, ft in ipairs(t) do set[ft] = true; any = true end end
        end
    end
    return any and set or nil, list
end

local function bagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function bagItem(bag, slot)
    if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
    return GetContainerItemID and GetContainerItemID(bag, slot)
end
local function itemInfo(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return nil end
    local ok, name, _, _, _, _, _, _, _, _, tex, sell = pcall(fn, id)
    if not ok then return nil end
    return name, tex, sell
end

-- the food to give: in the diet (unknown diet: any food), not too low for the pet, not refused, cheapest vendor price,
-- then the lower item level; nil when there is none
function P.Food()
    local foods = OMQ.PetFood
    if not foods then return nil end
    local diet = P.Diet()
    local petLevel = UnitLevel and UnitLevel("pet")
    if isSecret(petLevel) or type(petLevel) ~= "number" then petLevel = nil end
    local best
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, bagSlots(bag) do
            local id = bagItem(bag, slot)
            local f = id and not isSecret(id) and foods[id]
            if f and not P.refused[id] and (not diet or diet[f[1]])
               and not (petLevel and f[2] > 0 and f[2] <= petLevel - P.LEVEL_GAP) then
                local name, tex, sell = itemInfo(id)
                local price = type(sell) == "number" and sell or math.huge
                if not best or price < best.price or (price == best.price and f[2] < best.level) then
                    best = { id = id, bag = bag, slot = slot, name = name, icon = tex, price = price, level = f[2] }
                end
            end
        end
    end
    return best
end

function P.Eating()
    return P.fedAt and GetTime and (GetTime() - P.fedAt) < P.EAT_TIME or false
end

-- the game's "your pet does not eat that" messages
local REFUSE_TEXTS = { "SPELL_FAILED_WRONG_PET_FOOD", "SPELL_FAILED_FOOD_LOWLEVEL" }

-- the game's "your pet is dead" messages (localized globals; the ones this client lacks are skipped)
local DEAD_TEXTS = { "ERR_PET_SPELL_DEAD", "SPELL_FAILED_TARGETS_DEAD", "PETTAME_DEAD" }
local function isText(msg, names)
    if type(msg) ~= "string" or isSecret(msg) then return false end
    for _, g in ipairs(names) do
        local t = _G[g]
        if type(t) == "string" and t ~= "" and msg == t then return true end
    end
    return false
end

-- events that tell the pet's state
function P.OnEvent(event, a1, a2, a3)
    local _, class = UnitClass("player")
    if class ~= "HUNTER" then return end
    if event == "UNIT_PET" or event == "UNIT_HEALTH" then
        if event == "UNIT_PET" and a1 ~= "player" then return end
        if event == "UNIT_PET" then
            local g = UnitGUID and UnitGUID("pet")
            if g and not isSecret(g) and g ~= P.petGuid then P.petGuid = g; P.refused = {} end
        end
        if event == "UNIT_HEALTH" and a1 ~= "pet" then return end
        if flag(UnitExists, "pet") then
            local dead = flag(UnitIsDead, "pet")
            if dead ~= nil then P.SetDead(dead) end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" and a3 == P.REVIVE then P.SetDead(false) end
        if a1 == "player" and a3 == P.FEED and GetTime then P.fedAt = GetTime() end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        -- Call Pet fails with no pet out: the pet is dead (the other reason, no pet at all, has no card anyway)
        if a1 == "player" and a3 == P.CALL and flag(UnitExists, "pet") == false then P.SetDead(true) end
    elseif event == "UI_ERROR_MESSAGE" then
        if isText(a2, DEAD_TEXTS) or isText(a1, DEAD_TEXTS) then P.SetDead(true) end
        if P.offered and (isText(a2, REFUSE_TEXTS) or isText(a1, REFUSE_TEXTS)) then
            P.refused[P.offered] = true; P.offered = nil; P.fedAt = nil
        end
    end
end

local COLOR = { 0.6, 0.8, 0.4 }
local function card(key, title, sub, spell)
    local n = spellName(spell)
    if not n then return nil end
    return { key = key, title = title, sub = sub, text = title, tag = "PET", cast = n, unit = "player",
             icon = icon(spell), color = COLOR }
end

function P.Check()
    if InCombatLockdown and InCombatLockdown() then return "keep" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
    if (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player")) then return nil end
    local _, class = UnitClass("player")
    local exists = flag(UnitExists, "pet")
    if exists == nil then return nil end               -- not readable: say nothing
    if class == "HUNTER" and knows(P.CALL) then
        local dead = exists and flag(UnitIsDead, "pet")
        if dead then P.SetDead(true) elseif exists and dead == false then P.SetDead(false) end
        if (dead or (not exists and P.IsDead())) and knows(P.REVIVE) then
            return { card("pet:revive", "Revive your pet", "Your pet is dead", P.REVIVE) }
        end
        if not exists then
            return { card("pet:call", "Call your pet", "Your pet is not with you", P.CALL) }
        end
        if knows(P.FEED) then
            local happy = P.Happiness()
            if happy and happy < 3 and not P.Eating() then
                local sub = happy == 1 and "It is unhappy and fights badly" or "It is not happy any more"
                local f = P.Food()
                local c = card("pet:feed", "Feed your pet", sub .. " - click, then the food", P.FEED)
                P.offered = nil
                if c and f then
                    c.sub = sub .. " - click feeds " .. (f.name or "food")
                    c.macro = "/cast " .. c.cast .. "\n/use " .. f.bag .. " " .. f.slot
                    c.icon = f.icon or c.icon
                    P.offered = f.id
                end
                return { c }
            end
        end
    elseif class == "WARLOCK" and not exists then
        local out = {}
        for _, id in ipairs(P.Offer()) do
            local c = card("pet:demon:" .. id, spellName(id) or "Summon your demon", "No demon at your side", id)
            if c then out[#out + 1] = c end
        end
        if #out > 0 then return out end
    end
    return nil
end

M:Register({ id = "pet", name = "Pet basics: call, revive, feed, summon", check = function()
    local r = P.Check()
    if type(r) == "table" and #r == 0 then return nil end
    return r
end })

-- every demon the warlock summons is remembered (also from the action bar)
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
for _, e in ipairs({ "UNIT_PET", "UNIT_HEALTH", "UNIT_SPELLCAST_FAILED", "UI_ERROR_MESSAGE" }) do pcall(watcher.RegisterEvent, watcher, e) end
watcher:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if isSecret(a1) or isSecret(a3) then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" and type(a3) == "number" then P.Remember(a3) end
    P.OnEvent(event, a1, a2, a3)
end)

-- /omq pet: what the pet card sees (mood, diet as the game names it, the food it would give)
function P.Explain()
    local out = {}
    local happy = P.Happiness()
    out[#out + 1] = "pet: exists " .. tostring(flag(UnitExists, "pet")) .. ", dead " .. tostring(flag(UnitIsDead, "pet"))
        .. ", kept dead " .. tostring(P.IsDead()) .. ", mood " .. tostring(happy) .. " (1 unhappy, 2 content, 3 happy)"
    local set, list = P.Diet()
    local names = {}
    for _, n in pairs(list or {}) do names[#names + 1] = tostring(n) end
    out[#out + 1] = "  diet: " .. (#names > 0 and table.concat(names, ", ") or "not readable")
        .. (set and "" or " (not matched: any food is tried)")
    local f = P.Food()
    out[#out + 1] = "  food: " .. (f and ((f.name or ("item " .. f.id)) .. " in bag " .. f.bag .. " slot " .. f.slot) or "none in the bags")
    return out
end
OMQ:RegisterCommand("pet", function()
    for _, l in ipairs(P.Explain()) do print(l) end
end, "what the hunter pet card sees: mood, diet and the food a click gives")
