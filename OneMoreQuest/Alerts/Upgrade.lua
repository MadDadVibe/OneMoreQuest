-- One More Quest: put on an upgrade from the bags (decision 432)
-- A piece of gear in the bags that I can put on right now and that is better for me than what I wear
-- (the item score of Score.lua, the same gain as the quest reward hint and the auction helper, LootPreview.Gain)
-- gets a card: "Put on Ironforge Breastplate  +6". A left click puts it on, into the slot where it gains the
-- most; a right click never reminds of this item again (per character, "Bring back dismissed alerts" resets).
-- "Right now" is decided like the auction helper's weapons (decision 431, AuctionBuy.CanEquipNow): my level,
-- my class's armor and weapon types, and no red line in the game's own tooltip (weapon skill, class).
-- Like the other cards: not in a fight (the card frame is hidden there), not while dead.
-- /omq upgrades says for every piece of gear in the bags why it gets a card or not.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local M = OMQ.Alerts
local U = {}
OMQ.UpgradeAlert = U

U.MAX = 2                         -- at most two cards at a time, the biggest gains
U.KEEP = 10                       -- seconds a verdict is reused while nothing worn changes
local COLOR = { 0.25, 0.88, 0.38 }
-- a second ring or trinket of the same kind is often unique: never offered next to the worn one
local PAIRED = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return GetTime and GetTime() or 0 end
local function instant(x)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(x) end
    if GetItemInfoInstant then return GetItemInfoInstant(x) end
end
local function info(x)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(x) end
    if GetItemInfo then return GetItemInfo(x) end
end
local function worn(slot)
    local l = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if isSecret(l) then return nil end
    return l
end
local function idOf(link) return type(link) == "string" and tonumber(link:match("item:(%-?%d+)")) or nil end

-- the verdicts are kept per item link; a change of the worn gear, the level or the role starts over
local cache, sig = {}, nil
local function signature()
    local parts = { tostring(UnitLevel and UnitLevel("player")), tostring(OMQ.Score and OMQ.Score.MyRole and OMQ.Score.MyRole()) }
    for _, s in ipairs(OMQ.Gear and OMQ.Gear.SLOTS or {}) do parts[#parts + 1] = worn(s) or "" end
    return table.concat(parts, "|")
end
function U.Reset() cache, sig = {}, nil end

-- can I put it on now? true, false, or nil while the game has not loaded the item
local function canEquip(link)
    local B = OMQ.AuctionBuy
    if B and B.CanEquipNow then return B.CanEquipNow(link) end
    local SC = OMQ.Score
    if SC and SC.CanUse and not SC.CanUse(link, SC.MyClass(), UnitLevel and UnitLevel("player")) then return false end
    return true
end

-- the verdict for one item of the bags: gain (or nil), the reason, the slot it goes into, true while loading
function U.Judge(link)
    local _, _, _, equipLoc = instant(link)
    local slots = OMQ.Compare and OMQ.Compare.SLOTS and OMQ.Compare.SLOTS[equipLoc or ""]
    if not slots then return nil, "not gear" end
    if PAIRED[equipLoc] then
        local id = idOf(link)
        for _, s in ipairs(slots) do
            if id and idOf(worn(s)) == id then return nil, "you wear one already" end
        end
    end
    local can = canEquip(link)
    if can == nil then return nil, "item data not loaded yet", nil, true end
    if can == false then return nil, "you cannot put it on now (level, armor or weapon type, skill)" end
    local LP = OMQ.LootPreview
    if not (LP and LP.GainAt) then return nil, "no item score" end
    local g, slot = LP.GainAt(link, equipLoc)
    if not g then return nil, "no score here (an off-hand next to a two-hander)" end
    if g <= 0 then return nil, "not better than what you wear (" .. g .. ")" end
    return g, "upgrade +" .. g, slot or slots[1]
end

local function judged(link)
    local c = cache[link]
    if c and now() - c.t < U.KEEP then return c.g, c.why, c.slot end
    local g, why, slot, loading = U.Judge(link)
    if not loading then cache[link] = { g = g, why = why, slot = slot, t = now() } end
    return g, why, slot
end

-- puts the item on, into the slot of the biggest gain; a bind-on-equip item asks the game's own question first
function U.Equip(link, slot)
    if InCombatLockdown and InCombatLockdown() then return false end
    local f = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if not f then return false end
    local ok = pcall(f, link, slot)
    return ok
end

-- every piece of gear in the bags: { bag, slot, id, link }
local function bagGear()
    local Ct = C_Container
    local out = {}
    if not (Ct and Ct.GetContainerNumSlots and Ct.GetContainerItemInfo) then return out end
    for bag = 0, OMQ.LastBag() do
        for s = 1, Ct.GetContainerNumSlots(bag) or 0 do
            local it = Ct.GetContainerItemInfo(bag, s)
            local id = it and it.itemID
            local link = it and it.hyperlink
            if (not link) and Ct.GetContainerItemLink then link = Ct.GetContainerItemLink(bag, s) end
            if id and link and not isSecret(id) and not isSecret(link) then
                local _, _, _, equipLoc = instant(link)
                if equipLoc and equipLoc ~= "" and OMQ.Compare and OMQ.Compare.SLOTS[equipLoc] then
                    out[#out + 1] = { bag = bag, slot = s, id = id, link = link, icon = it.iconFileID }
                end
            end
        end
    end
    return out
end

function U.Check()
    if InCombatLockdown and InCombatLockdown() then return "keep" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return nil end
    local s = signature()
    if s ~= sig then cache, sig = {}, s end
    local found, seen = {}, {}
    for _, e in ipairs(bagGear()) do
        if not seen[e.link] then
            seen[e.link] = true
            local g, _, slot = judged(e.link)
            if g and not (M.DismissedForGood and M:DismissedForGood("upg:" .. e.id)) then
                e.gain, e.to = g, slot
                found[#found + 1] = e
            end
        end
    end
    -- the biggest gain per slot, then the biggest gains overall
    table.sort(found, function(a, b) if a.gain ~= b.gain then return a.gain > b.gain end return a.id < b.id end)
    local out, slotTaken = {}, {}
    for _, e in ipairs(found) do
        if not slotTaken[e.to] then
            slotTaken[e.to] = true
            local name, _, _, _, _, _, _, _, _, icon = info(e.link)
            name = (type(name) == "string" and not isSecret(name)) and name or ("item " .. e.id)
            local link, to = e.link, e.to
            out[#out + 1] = {
                key = "upg:" .. e.id, title = "Put on " .. name, text = "Put on " .. name .. "  +" .. e.gain, tag = "UPGRADE",
                sub = "+" .. e.gain .. " for you - left click puts it on - right click: never remind",
                icon = icon or e.icon, color = COLOR, tipLink = link,
                open = function() U.Equip(link, to); return "keep" end,
            }
            if #out >= U.MAX then break end
        end
    end
    return out
end

-- /omq upgrades: why a piece of gear in the bags gets a card or not
function U.Explain()
    local out = { string.format("upgrade reminders: alerts %s, in a fight %s",
        tostring(M:IsRuleEnabled("upgrade")), tostring(InCombatLockdown and InCombatLockdown() and true or false)) }
    U.Reset()
    local seen = {}
    for _, e in ipairs(bagGear()) do
        if not seen[e.link] then
            seen[e.link] = true
            local g, why = U.Judge(e.link)
            if g and M.DismissedForGood and M:DismissedForGood("upg:" .. e.id) then why = why .. " (clicked away for good)" end
            local name = info(e.link)
            out[#out + 1] = string.format("  %s: %s", (type(name) == "string" and not isSecret(name)) and name or ("item " .. e.id), why)
        end
    end
    if not next(seen) then out[#out + 1] = "  no gear in the bags" end
    return out
end
OMQ:RegisterCommand("upgrades", function()
    for _, l in ipairs(U.Explain()) do print(l) end
end, "why a piece of gear in your bags gets an upgrade card or not")

M:Register({ id = "upgrade", name = "Upgrade in your bags: put it on", check = function()
    local r = U.Check()
    if type(r) == "table" and #r == 0 then return nil end
    return r
end })
