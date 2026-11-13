-- One More Quest: use your buff items (decision 266)
-- A dad who carries elixirs, flasks, scrolls, buff food, weapon stones, weapon oils or juju (the buff
-- items of Data/BuyList.lua) and has not got their buff on gets a card: "Use Elixir of Ogre's
-- Strength" - a left click uses it, a right click hides that reminder for good.
-- Option "Consumable reminders": Never, Always (out in the world - not in a city or an inn - and in
-- dungeons) or Dungeons (only there; the default). In a dungeon the reminders count separately: a
-- card clicked away there stays away in every future dungeon, but still comes outside (and the other
-- way round). "Reset consumable reminders" under the option brings them all back.
-- Potions are left out (they are for emergencies), so are armor kits and shield spikes (they stay on).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local C = {}
OMQ.ConsumableAlert = C

C.KINDS = { elixir = true, flask = true, scroll = true, food = true, stone = true, oil = true, juju = true }
C.MAX = 3
C.WELL_FED = 19705                -- "Well Fed": its name in the client's language
C.FOOD_SILENCE = 10               -- seconds the food card stays away after a left click: no second click (fix 486)

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local COLOR = { 0.55, 0.85, 0.45 }

function C.Mode()
    local m = OMQ.db and OMQ.db.options and OMQ.db.options.consumeMode
    return (m == "never" or m == "always") and m or "dungeon"
end

local function inDungeon()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid") or false
end

-- names and spell IDs of my buffs; a secret entry is skipped, not the whole list (decision 282)
local function auraNames()
    local names, ids, any, readable, camp = {}, {}, false, 0, nil
    local get = (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex)
    if get then
        for i = 1, 40 do
            local a, hidden = OMQ.ReadAura("player", i, "HELPFUL")
            if hidden then return nil end                 -- hidden in a dungeon fight: cannot tell
            if not a then break end
            any = true
            if type(a.name) == "string" and not isSecret(a.name) then names[a.name] = true; readable = readable + 1 end
            if type(a.spellId) == "number" and not isSecret(a.spellId) then ids[a.spellId] = true end
            if C.IsCamp(a) then camp = a; pcall(function() a.omqIndex = i end) end
        end
    elseif UnitBuff then
        for i = 1, 40 do
            local okb, name, _, _, _, _, _, _, _, _, sid = pcall(UnitBuff, "player", i)
            if not okb then return nil end
            if not name then break end
            any = true
            if type(name) == "string" and not isSecret(name) then names[name] = true; readable = readable + 1 end
            if type(sid) == "number" and not isSecret(sid) then ids[sid] = true end
        end
    else
        return nil
    end
    if any and readable == 0 then return nil end           -- nothing readable: cannot tell
    names.__ids = ids
    names.__camp = camp and C.CampStats(camp) or nil
    return names
end

-- Forever camp buff "Camp Benefits" (German "Lagervorteile", fix 547): ONE aura that holds the perks of the camp
-- objects at the fire (Incense Candle Intellect, First Aid Kit Stamina, Faction Banner Spirit, Sharpening Wheel
-- Strength, ...). They do not stack with the class buff of the same stat, so a scroll or an Intellect elixir of that
-- stat is not needed either. Which perks it holds is only in its tooltip: read once out of combat, kept while the
-- same aura is on. Stat names come from the client (SPELL_STAT1-5_NAME), so German and English both work.
C.CAMP_SPELL = 1229741
C.CAMP_NAMES = { ["Camp Benefits"] = true, ["Lagervorteile"] = true }
C.STAT_OF = { s_str = 1, s_sta = 3, s_int = 4, e_int = 4, s_spi = 5 }
C.STAT_EN = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local campCache = nil                 -- { id = auraInstanceID, stats = { [stat] = amount }, lines = {...} }
function C.IsCamp(a)
    if type(a) ~= "table" then return false end
    local sid, name = a.spellId, a.name
    if type(sid) == "number" and not isSecret(sid) and sid == C.CAMP_SPELL then return true end
    if type(name) == "string" and not isSecret(name) then
        if C.CAMP_NAMES[name] then return true end
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(C.CAMP_SPELL)
        if type(n) == "string" and not isSecret(n) and n == name then return true end
    end
    return false
end
-- the text lines of a buff's tooltip, nil when they cannot be read (secret, no API)
function C.AuraLines(a)
    local T = C_TooltipInfo
    if not T then return nil end
    local ok, data
    local inst = a and a.auraInstanceID
    if type(inst) == "number" and not isSecret(inst) and T.GetUnitBuffByAuraInstanceID then
        ok, data = pcall(T.GetUnitBuffByAuraInstanceID, "player", inst, "HELPFUL")
    end
    if not (ok and type(data) == "table") and a and a.omqIndex and T.GetUnitAura then
        ok, data = pcall(T.GetUnitAura, "player", a.omqIndex, "HELPFUL")
    end
    if not (ok and type(data) == "table" and type(data.lines) == "table") then return nil end
    local out = {}
    for _, line in ipairs(data.lines) do
        for _, k in ipairs({ "leftText", "rightText" }) do
            local t = line and line[k]
            if type(t) == "string" and not isSecret(t) and t ~= "" then out[#out + 1] = t end
        end
    end
    return #out > 0 and out or nil
end
local function statNames(i)
    local out = { C.STAT_EN[i] }
    local g = _G["SPELL_STAT" .. i .. "_NAME"]
    if type(g) == "string" and g ~= "" then out[#out + 1] = g end
    return out
end
-- { [stat index] = amount } from tooltip lines: the number nearest to the stat name in its line (no percent values)
function C.ParseCamp(lines)
    local stats = {}
    for _, line in ipairs(lines or {}) do
        local low = line:lower()
        local nums = {}
        local pos = 1
        while true do
            local a, b = low:find("%d+", pos)
            if not a then break end
            if low:sub(b + 1, b + 1) ~= "%" and low:sub(b + 1, b + 2) ~= " %" then
                nums[#nums + 1] = { a = a, b = b, v = tonumber(low:sub(a, b)) }
            end
            pos = b + 1
        end
        if #nums > 0 then
            for i = 1, 5 do
                for _, nm in ipairs(statNames(i)) do
                    local a, b = low:find(nm:lower(), 1, true)
                    if a then
                        local best, dist
                        for _, n in ipairs(nums) do
                            local d = (n.b < a) and (a - n.b) or (n.a > b and n.a - b) or 0
                            if not dist or d < dist then best, dist = n.v, d end
                        end
                        if best and best > (stats[i] or 0) then stats[i] = best end
                        break
                    end
                end
            end
        end
    end
    return stats
end
-- the perks of the camp buff: { [stat index] = amount }; the last reading while the same aura is still on
function C.CampStats(a)
    local inst = a and a.auraInstanceID
    if type(inst) == "number" and isSecret(inst) then inst = nil end
    if campCache and inst and campCache.id == inst and next(campCache.stats) then return campCache.stats end
    local lines = C.AuraLines(a)
    if lines then
        campCache = { id = inst, stats = C.ParseCamp(lines), lines = lines }
        return campCache.stats
    end
    if campCache and (not inst or campCache.id == inst) then return campCache.stats end
    return {}
end
function C.CampCache() return campCache end

local function spellOf(id)
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not f then return nil end
    local name, sid = f(id)
    if isSecret(name) then return nil end
    return type(name) == "string" and name or nil, (type(sid) == "number" and not isSecret(sid)) and sid or nil
end
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function info(id)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(id) end
    if GetItemInfo then return GetItemInfo(id) end
end

-- a weapon in this hand? true, false (empty, a shield or a held item), nil when it cannot be read
local function weaponIn(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if link == nil then return false end
    if isSecret(link) then return nil end
    local f = C_Item and C_Item.GetItemInfoInstant
    if not f then return nil end
    local _, _, _, _, _, classID = f(link)
    if isSecret(classID) or classID == nil then return nil end
    return classID == 2
end
-- the hands a stone or an oil still has to go on: { [16] = true, [17] = true } for a weapon without
-- an enchantment that the item fits (a sharpening stone a blade, a weightstone a blunt weapon), both
-- hands of a dual wielder (fix 454). nil when it cannot be told. No weapon readable: the main hand as before.
function C.WeaponNeed(id, kind)
    if not GetWeaponEnchantInfo then return nil end
    local hasMain, _, _, _, hasOff = GetWeaponEnchantInfo()
    if isSecret(hasMain) or isSecret(hasOff) then return nil end
    local B = OMQ.AuctionBuy
    local line
    if kind == "stone" and B and B.StoneLine then
        for _, key in ipairs({ "stone_sharp", "stone_weight" }) do
            local l = OMQ.BuyLines and OMQ.BuyLines[key]
            for _, e in ipairs(l and l[2] or {}) do if e[1] == id then line = key end end
        end
    end
    local need, any = {}, false
    for _, slot in ipairs({ 16, 17 }) do
        if weaponIn(slot) then
            any = true
            local wl = line and B.StoneLine(slot)
            local has = (slot == 16 and hasMain) or (slot == 17 and hasOff)
            if not has and (not wl or wl == line) then need[slot] = true end
        end
    end
    if not any then
        if hasMain then return {} end
        return { [16] = true }
    end
    return need
end

-- is the buff of this item on? nil when it cannot be told
function C.Active(id, kind, auras)
    if kind == "stone" or kind == "oil" then
        local need = C.WeaponNeed(id, kind)
        if not need then return nil end
        return next(need) == nil
    end
    if not auras then return nil end
    if kind == "food" then
        local wf = spellName(C.WELL_FED)
        if not wf then return nil end
        local eat = spellOf(id)                       -- the eating buff ("Food") while I still eat (fix 486)
        return (auras[wf] or (eat and auras[eat])) and true or false
    end
    local s, sid = spellOf(id)
    if not s then return nil end
    if sid and auras.__ids and auras.__ids[sid] then return true end
    if sid and not OMQ.AurasHidden() and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and a then return true end
    end
    return auras[s] and true or false
end

-- a scroll does not stack with the class buff of the same stat (Arcane Intellect, Power Word:
-- Fortitude, Divine Spirit), and neither do the pure Intellect elixirs (Elixir of Wisdom, Elixir of
-- Greater Intellect) with Arcane Intellect: no reminder while such a buff is on that is as strong or
-- stronger, whoever cast it. Spell ID = the stat it gives; items by their place in the buy line (weakest
-- first). Elixir of the Sages (Intellect and Spirit) has no amount here: it keeps its reminder.
C.CLASS_BUFF = {
    s_int = { [1459] = 2, [1460] = 7, [1461] = 15, [10156] = 22, [10157] = 31, [23028] = 31 },    -- Arcane Intellect, Brilliance
    s_sta = { [1243] = 3, [1244] = 8, [1245] = 20, [2791] = 32, [10937] = 43, [10938] = 54,         -- Power Word: Fortitude
              [21562] = 43, [21564] = 54 },                                                        -- Prayer of Fortitude
    s_spi = { [14752] = 17, [14818] = 23, [14819] = 33, [27841] = 40, [27681] = 40 },              -- Divine Spirit, Prayer of Spirit
}
C.CLASS_BUFF.e_int = C.CLASS_BUFF.s_int
C.SCROLL_STAT = { s_int = { 4, 8, 12, 16 }, s_sta = { 4, 8, 12, 16 }, s_spi = { 3, 7, 11, 15 },
                  s_str = { 5, 9, 13, 17 },                        -- only against the camp buff (no class buff here)
                  e_int = { 6, 6, 10, 25 } }     -- Elixir of Wisdom, WoW Forever's Lesser Intellect and Intellect, Greater Intellect
-- the pure Intellect elixirs do not help with any rank of Arcane Intellect on (fix 487, seen in game):
-- no reminder whatever rank the mage cast, also a weaker one
C.ANY_RANK = { e_int = true }
local scrollOf
local function scrollLine(id)
    if not scrollOf then
        scrollOf = {}
        for key in pairs(C.SCROLL_STAT) do
            local L = OMQ.BuyLines and OMQ.BuyLines[key]
            for i, it in ipairs(L and L[2] or {}) do scrollOf[it[1]] = { key, i } end
        end
    end
    local s = scrollOf[id]
    if s then return s[1], s[2] end
end
-- the name of the class buff that makes this scroll or elixir useless, or nil
function C.BetterBuff(id, auras)
    local key, tier = scrollLine(id)
    if not key or not auras then return nil end
    local need = C.SCROLL_STAT[key][tier]
    if not need then return nil end                  -- no amount known (Elixir of the Sages): keep the reminder
    local ids = auras.__ids or {}
    local found = false
    local class = C.CLASS_BUFF[key] or {}
    for sid, amount in pairs(class) do
        if ids[sid] then
            found = true
            if amount >= need or C.ANY_RANK[key] then return spellName(sid) or "a class buff" end
        end
    end
    -- the camp buff with a perk of the same stat (fix 547): same rule as a class buff rank
    local camp = auras.__camp and C.STAT_OF[key] and auras.__camp[C.STAT_OF[key]]
    if camp and (camp >= need or C.ANY_RANK[key]) then
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(C.CAMP_SPELL)
        return (type(n) == "string" and not isSecret(n)) and n or "Camp Benefits"
    end
    if found then return nil end                     -- only a weaker rank is on: the scroll still helps
    -- by name, when the buff's spell ID cannot be read: the rank is unknown, it counts as strong enough
    for sid in pairs(class) do
        local n = spellName(sid)
        if type(n) == "string" and not isSecret(n) and auras[n] then return n end
    end
    return nil
end

-- elixirs of one buy line do not stack (Minor, Lesser, Arcane and Greater Arcane Elixir, seen in game, fix 503):
-- one card for the strongest one I can use, none while the buff of any of them is on
C.ONE_PER_LINE = { e_spell = true }
local lineOf
local function bagSet()
    local have, Ct = {}, C_Container
    for bag = 0, OMQ.LastBag() do
        for slot = 1, (Ct and Ct.GetContainerNumSlots and Ct.GetContainerNumSlots(bag)) or 0 do
            local it = Ct.GetContainerItemInfo(bag, slot)
            if it and it.itemID then have[it.itemID] = true end
        end
    end
    return have
end
-- why this item gets no card because of another one of its line, or nil
function C.SameLine(id, auras, have, level)
    if not lineOf then
        lineOf = {}
        for key in pairs(C.ONE_PER_LINE) do
            local L = OMQ.BuyLines and OMQ.BuyLines[key]
            for i, it in ipairs(L and L[2] or {}) do lineOf[it[1]] = { key, i } end
        end
    end
    local me = lineOf[id]
    if not me then return nil end
    local L = OMQ.BuyLines[me[1]]
    for j, it in ipairs(L[2]) do
        local other = it[1]
        if other ~= id then
            local name = info(other) or "a stronger elixir"
            if j > me[2] and have and have[other] and (it[2] or 0) <= (level or 1) then
                return name .. " is stronger (does not stack)"
            end
            if C.Active(other, L[1], auras) == true then return name .. " is on (does not stack)" end
        end
    end
    return nil
end

function C.Check()
    local mode = C.Mode()
    if mode == "never" or not OMQ.BuyKnown then return nil end
    -- buff foods the list does not know count too (decision 278, UI/AuctionBuy.lua)
    local kindOf = OMQ.BuyKind or function(i) return OMQ.BuyKnown[i] end
    local dungeon = inDungeon()
    if mode == "dungeon" and not dungeon then return nil end
    if not dungeon and OMQ:InTown() then return nil end                     -- in a city, a town, an inn or a quest hub (decision 308)
    if InCombatLockdown and InCombatLockdown() then return "keep" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
    if (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player")) then return nil end
    local Ct = C_Container
    if not (Ct and Ct.GetContainerNumSlots and Ct.GetContainerItemInfo) then return nil end
    local auras = auraNames()
    local level = UnitLevel and tonumber((UnitLevel("player"))) or 1
    local out, seen, spells = {}, {}, {}
    local have = bagSet()
    local prefix = dungeon and "consd:" or "cons:"
    for bag = 0, OMQ.LastBag() do
        for slot = 1, Ct.GetContainerNumSlots(bag) or 0 do
            local it = Ct.GetContainerItemInfo(bag, slot)
            local id = it and it.itemID
            local kind = id and kindOf(id)
            if kind and C.KINDS[kind] and not seen[id] then
                seen[id] = true
                local name, _, _, _, minLevel, _, _, _, _, icon = info(id)
                local s = (kind == "stone" or kind == "oil") and "weapon" or (kind == "food" and "food") or spellOf(id)
                local fits = kind ~= "stone" or not OMQ.AuctionBuy or not OMQ.AuctionBuy.StoneFits
                    or OMQ.AuctionBuy.StoneFits(id) ~= false                      -- weightstone not on a blade (decision 426)
                if name and fits and (minLevel or 0) <= level and s and not spells[s] and C.Active(id, kind, auras) == false
                    and not ((kind == "scroll" or kind == "elixir") and C.BetterBuff(id, auras))
                    and not C.SameLine(id, auras, have, level) then
                    spells[s] = true
                    local wpn = (kind == "stone" or kind == "oil") and C.WeaponNeed(id, kind) or nil
                    local how = "left click uses it"
                    if wpn then
                        how = (wpn[16] and wpn[17] and "left click, then click a weapon")
                            or (wpn[17] and "left click, then click your off hand weapon")
                            or "left click, then click your main hand weapon"
                    end
                    out[#out + 1] = {
                        key = prefix .. id, title = "Use " .. name, text = "Use " .. name, tag = "BUFF",
                        sub = how .. " - right click: never remind",
                        icon = icon or it.iconFileID, color = COLOR, useItem = "item:" .. id,
                        weapon = (kind == "stone" or kind == "oil") or nil, weaponSlots = wpn,
                        silence = (kind == "food") and C.FOOD_SILENCE or nil,   -- gone at once after the click (fix 486)
                    }
                    if #out >= C.MAX then return out end
                end
            end
        end
    end
    return out
end

-- /omq consumables: why a buff item gets a reminder or not (decision 282)
function C.Explain()
    local out = {}
    local mode = C.Mode()
    local dungeon = inDungeon()
    local resting = OMQ:InTown() and true or false
    out[#out + 1] = string.format("consumable reminders: mode %s, in a dungeon %s, in a town (city, town, inn or quest hub) %s, alerts %s",
        mode, tostring(dungeon), tostring(resting), tostring(M:IsRuleEnabled("consumable")))
    if mode == "never" then out[#out + 1] = "  mode Never: no reminders"
    elseif mode == "dungeon" and not dungeon then out[#out + 1] = "  mode Dungeons and not in a dungeon: no reminders"
    elseif not dungeon and resting then out[#out + 1] = "  in a city, a town, an inn or a quest hub: no reminders here" end
    local Ct = C_Container
    local auras = auraNames()
    local level = UnitLevel and tonumber((UnitLevel("player"))) or 1
    local kindOf = OMQ.BuyKind or function(i) return OMQ.BuyKnown and OMQ.BuyKnown[i] end
    local seen = {}
    local have = bagSet()
    for bag = 0, OMQ.LastBag() do
        for slot = 1, (Ct and Ct.GetContainerNumSlots and Ct.GetContainerNumSlots(bag)) or 0 do
            local it = Ct.GetContainerItemInfo(bag, slot)
            local id = it and it.itemID
            local kind = id and kindOf(id)
            if kind and not seen[id] then
                seen[id] = true
                local name, _, _, _, minLevel = info(id)
                local s = (kind == "stone" or kind == "oil") and "weapon enchant" or (kind == "food" and "Well Fed") or spellOf(id)
                local why
                if not C.KINDS[kind] then why = "not reminded (" .. kind .. ")"
                elseif not name then why = "item data not loaded yet"
                elseif (minLevel or 0) > level then why = "needs level " .. minLevel
                elseif kind == "stone" and OMQ.AuctionBuy and OMQ.AuctionBuy.StoneFits
                    and OMQ.AuctionBuy.StoneFits(id) == false then why = "does not fit your weapon (blade: sharpening stone, blunt: weightstone)"
                elseif not s then why = "its buff spell is not known yet"
                elseif (kind == "scroll" or kind == "elixir") and C.BetterBuff(id, auras) then
                    why = "not needed: " .. C.BetterBuff(id, auras) .. " is on (does not stack)"
                elseif C.SameLine(id, auras, have, level) then
                    why = "not needed: " .. C.SameLine(id, auras, have, level)
                else
                    local a = C.Active(id, kind, auras)
                    why = (a == true and "buff is on") or (a == false and "buff missing -> reminder") or "buff cannot be read"
                end
                local dkey = (dungeon and "consd:" or "cons:") .. id
                if M.DismissedForGood and M:DismissedForGood(dkey) then why = why .. " (clicked away for good)" end
                out[#out + 1] = string.format("  %s [%s]: %s", name or ("item " .. id), kind, why)
            end
        end
    end
    if not next(seen) then out[#out + 1] = "  no buff items in the bags" end
    return out
end
OMQ:RegisterCommand("consumables", function()
    for _, l in ipairs(C.Explain()) do print(l) end
end, "why a buff item in your bags gets a reminder or not")

-- /omq camp: what OMQ reads from the camp buff (fix 547)
function C.CampExplain()
    local out = {}
    if OMQ.AurasHidden and OMQ.AurasHidden() then
        out[#out + 1] = "camp buff: buffs cannot be read right now (dungeon fight), try again out of combat"
        return out
    end
    local found
    for i = 1, 40 do
        local a, hidden = OMQ.ReadAura("player", i, "HELPFUL")
        if hidden or not a then break end
        if C.IsCamp(a) then found = a; pcall(function() a.omqIndex = i end); break end
    end
    if not found then
        out[#out + 1] = "camp buff: not on (rest at a campfire for a minute)"
        return out
    end
    local sid = found.spellId
    out[#out + 1] = string.format("camp buff: %s (spell %s)", (type(found.name) == "string" and not isSecret(found.name)) and found.name or "?",
        (type(sid) == "number" and not isSecret(sid)) and tostring(sid) or "secret")
    if type(found.points) == "table" then
        local p = {}
        for _, v in ipairs(found.points) do p[#p + 1] = isSecret(v) and "secret" or tostring(v) end
        out[#out + 1] = "  aura values: " .. (#p > 0 and table.concat(p, ", ") or "none")
    end
    local lines = C.AuraLines(found)
    if lines then
        for _, l in ipairs(lines) do out[#out + 1] = "  tooltip: " .. l end
    else
        out[#out + 1] = "  tooltip: cannot be read"
    end
    local stats = C.CampStats(found)
    local p = {}
    for i = 1, 5 do if stats[i] then p[#p + 1] = C.STAT_EN[i] .. " +" .. stats[i] end end
    out[#out + 1] = "  stats found: " .. (#p > 0 and table.concat(p, ", ") or "none (no Strength, Stamina, Intellect or Spirit perk)")
    return out
end
OMQ:RegisterCommand("camp", function()
    for _, l in ipairs(C.CampExplain()) do print(l) end
end, "what One More Quest reads from the camp buff")

M:Register({ id = "consumable", name = "Use your buff items (elixirs, scrolls, food, stones, oils)", check = function()
    local r = C.Check()
    if type(r) == "table" and #r == 0 then return nil end
    return r
end })
