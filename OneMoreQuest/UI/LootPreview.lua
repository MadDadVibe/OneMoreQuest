-- One More Quest: the best boss loot of a dungeon for me, in the Group Check (decision 233)
-- Every boss item of the dungeon (Data/DungeonLoot.lua) is scored against what I wear, with the
-- item score of my class and preferred role (Score.lua, decision 200). Items my class cannot wear or
-- wield (decision 214) and items without a slot are left out. The three biggest upgrades are shown
-- as tiles: the real icon with a quality border, the name in its quality colour, the score and the
-- slot. Hover: the game's own item tooltip. Click: like any item (Shift links it, Ctrl tries it on).
-- Names, icons, slots and stats all come from the game, so they are in the client's language.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local LP = {}
OMQ.LootPreview = LP

LP.COUNT = 3
LP.MIN_W = 560                   -- the Group Check is at least this wide when the tiles are shown
local HEAD_H = 20

local function SC() return OMQ.Score end
local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function info(id)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(id) end
    if GetItemInfo then return GetItemInfo(id) end
end
local function instant(id)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end
local function request(id)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- all item IDs of a dungeon, each once, with the boss NPC that drops it
function LP.Items(key)
    local out, seen = {}, {}
    for _, boss in ipairs((OMQ.DungeonLoot or {})[key] or {}) do
        for i = 2, #boss do
            local id = boss[i]
            if not seen[id] then seen[id] = true; out[#out + 1] = { id = id, npc = boss[1] } end
        end
    end
    return out
end

-- the score of an item against my gear: the best slot it can go into (for rings and trinkets the
-- weaker one is replaced, an empty slot counts the full value); a two-hander replaces both hands
-- the gain and the slot of that gain (the upgrade card puts the item there, decision 432)
function LP.GainAt(link, equipLoc, class, role, wornOf)
    local S = SC()
    local slots = OMQ.Compare and OMQ.Compare.SLOTS and OMQ.Compare.SLOTS[equipLoc or ""]
    if not (S and slots) then return nil end
    -- without a class the score knows no weights and every item scored 0 (decision 294): mine by default
    class = class or (S.MyClass and S.MyClass())
    role = role or (S.MyRole and S.MyRole())
    wornOf = wornOf or function(slot) return GetInventoryItemLink and GetInventoryItemLink("player", slot) end
    -- two-hander against both hands, no off-hand next to a two-hander (decision 285)
    local best, at
    for _, slot in ipairs(slots) do
        local d = S.HandDelta(link, equipLoc, wornOf(slot), wornOf(16), wornOf(17), class, role)
        if d and (not best or d > best) then best, at = d, slot end
    end
    -- a one-hander for a dad who fights with two weapons (a weapon in the off hand) may replace the off-hand one too (decision 402)
    if equipLoc == "INVTYPE_WEAPON" then
        local oh = wornOf(17)
        local ohLoc = type(oh) == "string" and select(4, instant(oh))
        if ohLoc == "INVTYPE_WEAPON" or ohLoc == "INVTYPE_WEAPONOFFHAND" then
            local d = S.Delta(link, oh, class, role)
            if d and (not best or d > best) then best, at = d, 17 end
        end
    end
    return best, at
end
function LP.Gain(link, equipLoc, class, role, wornOf) return (LP.GainAt(link, equipLoc, class, role, wornOf)) end

-- the best upgrades: list of { id, link, gain, equipLoc, minLevel, quality, icon }, and how many
-- items are still loading
function LP.Best(key, n, class, level, role, wornOf)
    local S = SC()
    if not S then return {}, 0 end
    class = class or S.MyClass()
    level = level or (UnitLevel and UnitLevel("player")) or 1
    role = role or S.MyRole()
    local list, loading = {}, 0
    for _, it in ipairs(LP.Items(key)) do
        local _, _, _, equipLoc = instant(it.id)
        if equipLoc and equipLoc ~= "" and OMQ.Compare and OMQ.Compare.SLOTS[equipLoc] then
            local name, link, quality, ilvl, minLevel, _, _, _, _, icon = info(it.id)
            if not name or not link then
                loading = loading + 1
                request(it.id)
            elseif not isSecret(link) then
                local ok = S.CanUse(link, class, math.max(level, minLevel or 0))
                if ok then
                    local g = LP.Gain(link, equipLoc, class, role, wornOf)
                    if g and g > 0 then
                        list[#list + 1] = { id = it.id, link = link, gain = g, equipLoc = equipLoc, minLevel = minLevel or 0,
                                            quality = quality or 1, icon = icon, ilvl = ilvl or 0, name = name }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        return a.id < b.id
    end)
    local out = {}
    for i = 1, math.min(n or LP.COUNT, #list) do out[i] = list[i] end
    return out, loading
end

----------------------------------------------------------------------
-- Quest rewards in the quest tooltip of the Group Check (decision 279)
-- The item rewards of a dungeon quest (Data/QuestRewards.lua), scored like the boss loot: an upgrade
-- shows "+N", gear that is no upgrade "no upgrade", gear my class cannot use "not for you", the rest
-- (potions, bags, ...) nothing. Upgrades first.
----------------------------------------------------------------------
function LP.RewardIDs(q)
    local R = OMQ.QuestRewards or {}
    if not q then return nil end
    if R[q.id] then return R[q.id] end
    for _, id in ipairs(q.alt or {}) do if R[id] then return R[id] end end
    return nil
end

-- list of { id, name, link, quality, gain, equipLoc, state = "up" | "no" | "cannot" | "other" }, and how many still load
function LP.Rewards(q, class, level, role, wornOf)
    local ids = LP.RewardIDs(q)
    if not ids then return nil, 0 end
    return LP.ItemEntries(ids, class, level, role, wornOf)
end

-- decision 531: the other dads in the group for whom an item is an upgrade (their gear from the gear sync,
-- decision 198): list of { name, gain }, best first; nil when it is for none of them
function LP.DadUpgrades(link, equipLoc, minLevel)
    local S, C = SC(), OMQ.Compare
    if not (S and C and C.Dads) then return nil end
    local out = {}
    for _, d in ipairs(C.Dads()) do
        if d.gear and d.class and S.CanUse(link, d.class, math.max(d.level or 1, minLevel or 0)) then
            local worn = function(slot) return d.gear[slot] or nil end
            local g = LP.Gain(link, equipLoc, d.class, d.role or "damage", worn)
            if g and g > 0 then out[#out + 1] = { name = d.name, gain = g } end
        end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) return a.gain > b.gain end)
    return out
end

-- the same for any list of item ids (boss loot in the dungeon window, decision 530)
function LP.ItemEntries(ids, class, level, role, wornOf)
    local S = SC()
    class = class or (S and S.MyClass())
    level = level or (UnitLevel and UnitLevel("player")) or 1
    role = role or (S and S.MyRole())
    local list, loading, pend = {}, 0, {}
    for i, id in ipairs(ids) do
        local name, link, quality, _, minLevel = info(id)
        if not name or not link or isSecret(link) then
            loading = loading + 1
            pend[#pend + 1] = id
            request(id)
        else
            local _, _, _, equipLoc = instant(id)
            local e = { id = id, name = name, link = link, quality = quality or 1, equipLoc = equipLoc, order = i, minLevel = minLevel or 0 }
            local gear = equipLoc and equipLoc ~= "" and OMQ.Compare and OMQ.Compare.SLOTS and OMQ.Compare.SLOTS[equipLoc]
            if not (gear and S) then e.state = "other"
            elseif not S.CanUse(link, class, math.max(level, minLevel or 0)) then e.state = "cannot"
            else
                e.gain = LP.Gain(link, equipLoc, class, role, wornOf)
                e.state = (e.gain and e.gain > 0) and "up" or "no"
            end
            if gear and S then e.dads = LP.DadUpgrades(link, equipLoc, minLevel) end
            list[#list + 1] = e
        end
    end
    local rank = { up = 1, no = 2, other = 3, cannot = 4 }
    table.sort(list, function(a, b)
        if rank[a.state] ~= rank[b.state] then return rank[a.state] < rank[b.state] end
        if (a.gain or 0) ~= (b.gain or 0) then return (a.gain or 0) > (b.gain or 0) end
        return a.order < b.order
    end)
    return list, loading, pend
end

local function rewardColor(q)
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

----------------------------------------------------------------------
-- Reward icons in the quest rows of the Group Check (fix 490)
-- Every item reward of a dungeon quest as a small icon with its quality border; hover shows the
-- game's own item tooltip (stats, armor, level) with the item score below, an upgrade gets a green
-- "+", gear I cannot use a grey icon. Click like any item (Shift links it, Ctrl tries it on).
----------------------------------------------------------------------
LP.REWARD_ICON = 22
LP.REWARD_STEP = 24

-- the icons of a quest in their order: the loaded ones as Rewards sorts them, then the ones still loading
function LP.RewardIcons(q)
    return LP.IconEntries(LP.Rewards(q))
end

-- icon entries of an item list (LP.ItemEntries): loaded ones first, then the ones still loading
function LP.IconEntries(list, loading, pend)
    if not list then return {}, 0 end
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e end
    for _, id in ipairs(pend or {}) do
        local _, _, _, equipLoc, icon = instant(id)
        out[#out + 1] = { id = id, loading = true, icon = icon, equipLoc = equipLoc, state = "other" }
    end
    return out, loading
end

function LP.RewardScoreLine(tip, e)
    if not (tip and e) or e.loading then return end
    local S = SC()
    local role = S and S.MyRole and S.MyRole() or "damage"
    local label = (S and S.ROLE_LABEL and S.RoleOf and S.ROLE_LABEL[S.RoleOf(S.MyClass(), role) or role]) or role
    if e.state == "up" then
        tip:AddLine(" ")
        tip:AddLine("Item score (" .. label .. "): |cff40e060+" .. e.gain .. " upgrade|r")
    elseif e.state == "no" then
        tip:AddLine(" ")
        tip:AddLine("Item score (" .. label .. "): no upgrade", 0.6, 0.63, 0.68)
    elseif e.state == "cannot" then
        tip:AddLine(" ")
        tip:AddLine("Item score: not for you", 0.6, 0.63, 0.68)
    end
    for _, d in ipairs(e.dads or {}) do
        tip:AddLine("Upgrade for " .. d.name .. ": |cff5aa0ff+" .. d.gain .. "|r", 0.35, 0.63, 1)
    end
end

local function rewardEnter(self)
    local e = self.omqReward
    if not (GameTooltip and e) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, e.link or ("item:" .. e.id))   -- the game's own item tooltip
    LP.RewardScoreLine(GameTooltip, e)
    if e.loading then LP.tipOwner = self end    -- drawn again when the item arrives
    GameTooltip:Show()
end

function LP.MakeRewardIcon(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(LP.REWARD_ICON, LP.REWARD_ICON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.edges = {}
    for i = 1, 4 do b.edges[i] = b:CreateTexture(nil, "OVERLAY") end
    local e = b.edges
    e[1]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); e[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0); e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); e[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); e[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0); e[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); e[4]:SetWidth(1)
    -- decision 531: a small arrow up in the corner: green = an upgrade for me, blue = for another dad
    b.up = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.up:SetSize(12, 12)
    b.up:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3, 3)
    b.up:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
    if b.up.SetDesaturated then b.up:SetDesaturated(true) end
    b.up:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnEnter", rewardEnter)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self)
        local r = self.omqReward
        if r and HandleModifiedItemClick then HandleModifiedItemClick(r.link or select(2, info(r.id)) or ("item:" .. r.id)) end
    end)
    return b
end

function LP.SetRewardIcon(b, e)
    b.omqReward = e
    b.icon:SetTexture(e.icon or select(5, instant(e.id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
    if b.icon.SetDesaturated then b.icon:SetDesaturated(e.state == "cannot") end
    local r, g, bl = 0.4, 0.4, 0.4
    if not e.loading then r, g, bl = rewardColor(e.quality) end
    for _, edge in ipairs(b.edges) do edge:SetColorTexture(r, g, bl, 1) end
    local arrow = e.state == "up" and "me" or (e.dads and "dad") or nil
    if arrow == "me" then b.up:SetVertexColor(0.25, 0.95, 0.35); b.up:Show()
    elseif arrow == "dad" then b.up:SetVertexColor(0.30, 0.62, 1.00); b.up:Show()
    else b.up:Hide() end
    b.omqArrow = arrow
end

-- adds the reward lines to the GameTooltip; true when there were rewards
function LP:AddRewardLines(tip, q, owner)
    local list, loading = LP.Rewards(q)
    if not list then return false end
    local S = SC()
    local role = S and S.MyRole() or "damage"
    tip:AddLine(" ")
    tip:AddLine("Rewards  |cff9aa0aa(item score, " .. ((S and S.ROLE_LABEL and S.ROLE_LABEL[S.RoleOf(S.MyClass(), role) or role]) or role) .. ")|r")
    for _, e in ipairs(list) do
        local r, g, b = rewardColor(e.quality)
        local slot = (e.equipLoc and e.equipLoc ~= "" and _G[e.equipLoc]) or ""
        local right
        if e.state == "up" then right = "|cff40e060+" .. e.gain .. "|r"
        elseif e.state == "no" then right = "|cff9aa0aano upgrade|r"
        elseif e.state == "cannot" then right = "|cff9aa0aanot for you|r"
        else right = "" end
        if slot ~= "" then right = (right ~= "" and (right .. "  ") or "") .. "|cffc9ccd5" .. slot .. "|r" end
        tip:AddDoubleLine(e.name, right, r, g, b, 1, 1, 1)
    end
    if loading > 0 then
        tip:AddLine("Loading " .. loading .. " item" .. (loading == 1 and "" or "s") .. "...", 0.6, 0.63, 0.68)
        LP.tipOwner = owner                       -- shown again when the items arrive
    end
    return true
end

----------------------------------------------------------------------
-- Tiles
----------------------------------------------------------------------
local head, note, tiles = nil, nil, {}
LP._tiles = tiles

-- decision 531: the Group Check shows the bosses of the dungeon as a row of round icons (the icons of the dungeon
-- window); hover over one: all its loot beside the Group Check, the game's tooltip on each item. The best-upgrade
-- tiles (decision 233) are gone from the Group Check; LP.Best stays for other callers.
LP.BOSS_ICON = 36
LP.BOSS_GAP = 6
local bossIcons = {}
LP._bossIcons = bossIcons

function LP:Hide()
    if head then head:Hide(); note:Hide() end
    for _, t in ipairs(tiles) do t:Hide() end
    for _, b in ipairs(bossIcons) do b:Hide() end
end

-- draws the part into the Group Check at (x, -y) with the given width; returns its height
function LP:Render(parent, key, x, y, width)
    if not head then
        head = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        head:SetJustifyH("LEFT")
        note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetJustifyH("LEFT")
    end
    for _, t in ipairs(tiles) do t:Hide() end
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    head:SetWidth(width)
    head:SetText("Bosses  |cff9aa0aa(hover: their loot)|r")
    head:Show()
    local list = {}
    local W, UI = OMQ.DungeonWin, OMQ.DungeonWinUI
    if W and UI and (OMQ.DungeonLoot or {})[key] then
        local bosses, rares = W.Bosses(key)
        for _, e in ipairs(bosses) do list[#list + 1] = e end
        for _, e in ipairs(rares) do list[#list + 1] = e end
    end
    local step = LP.BOSS_ICON + LP.BOSS_GAP
    local cols = math.max(1, math.floor((width + LP.BOSS_GAP) / step))
    for i, e in ipairs(list) do
        local b = bossIcons[i]
        if not b then b = UI.MakeBossIcon(parent, LP.BOSS_ICON, parent); bossIcons[i] = b end
        local r, c = math.floor((i - 1) / cols), (i - 1) % cols
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + c * step, -(y + HEAD_H + r * step))
        UI.SetIcon(b, e, false)
    end
    for i = #list + 1, #bossIcons do bossIcons[i]:Hide() end
    LP.loading = 0
    if #list == 0 then
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + HEAD_H))
        note:SetWidth(width)
        note:SetText("No loot list for this dungeon yet")
        note:Show()
        return HEAD_H + 16
    end
    note:Hide()
    return HEAD_H + math.ceil(#list / cols) * step
end

-- items arrive from the server: draw again (the Group Check redraws everything, at most twice a second)
local pendingRedraw = false
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
pcall(ev.RegisterEvent, ev, "PLAYER_EQUIPMENT_CHANGED")
ev:SetScript("OnEvent", function(_, event)
    -- a quest tooltip waiting for its reward items (decision 279)
    local o = LP.tipOwner
    if event == "GET_ITEM_INFO_RECEIVED" and o and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(o) and o.GetScript then
        LP.tipOwner = nil
        local f = o:GetScript("OnEnter")
        if f then pcall(f, o) end
    end
    if event == "GET_ITEM_INFO_RECEIVED" and not (LP.loading and LP.loading > 0) and not (LP.rewardLoading and LP.rewardLoading > 0) then return end
    if pendingRedraw then return end
    pendingRedraw = true
    C_Timer.After(0.5, function()
        pendingRedraw = false
        local R = OMQ.Ready
        local f = R and R.Frame and R:Frame()
        if f and f:IsShown() and R.dungeon then R:Render() end
    end)
end)
