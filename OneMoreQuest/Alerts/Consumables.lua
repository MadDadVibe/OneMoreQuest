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
    local names, ids, any, readable = {}, {}, false, 0
    local get = (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex)
    if get then
        for i = 1, 40 do
            local a = get("player", i, "HELPFUL")
            if not a then break end
            any = true
            if type(a.name) == "string" and not isSecret(a.name) then names[a.name] = true; readable = readable + 1 end
            if type(a.spellId) == "number" and not isSecret(a.spellId) then ids[a.spellId] = true end
        end
    elseif UnitBuff then
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, sid = UnitBuff("player", i)
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
    return names
end

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

-- is the buff of this item on? nil when it cannot be told
function C.Active(id, kind, auras)
    if kind == "stone" or kind == "oil" then
        if not GetWeaponEnchantInfo then return nil end
        local has = GetWeaponEnchantInfo()
        if isSecret(has) then return nil end
        return has and true or false
    end
    if not auras then return nil end
    if kind == "food" then
        local wf = spellName(C.WELL_FED)
        if not wf then return nil end
        return auras[wf] and true or false
    end
    local s, sid = spellOf(id)
    if not s then return nil end
    if sid and auras.__ids and auras.__ids[sid] then return true end
    if sid and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and a then return true end
    end
    return auras[s] and true or false
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
                if name and (minLevel or 0) <= level and s and not spells[s] and C.Active(id, kind, auras) == false then
                    spells[s] = true
                    local how = (kind == "stone" or kind == "oil") and "left click, then click your weapon" or "left click uses it"
                    out[#out + 1] = {
                        key = prefix .. id, title = "Use " .. name, text = "Use " .. name, tag = "BUFF",
                        sub = how .. " - right click: never remind",
                        icon = icon or it.iconFileID, color = COLOR, useItem = "item:" .. id,
                        weapon = (kind == "stone" or kind == "oil") or nil,
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
                elseif not s then why = "its buff spell is not known yet"
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

M:Register({ id = "consumable", name = "Use your buff items (elixirs, scrolls, food, stones, oils)", check = function()
    local r = C.Check()
    if type(r) == "table" and #r == 0 then return nil end
    return r
end })
