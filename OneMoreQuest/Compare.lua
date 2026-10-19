-- One More Quest: group item comparison
-- Hold ALT while hovering an item: every group member with the addon compares
-- the item with what he or she wears in that slot and answers. The answers are
-- added to the tooltip as they arrive.
--   IQ|proto|reqId|guid|itemLink                      (request)
--   IR|proto|reqId|guid|status|eqIlvl|eqName|stats|name|class   (answer)
-- status: U = usable, L<n> = needs level n, N = cannot use, ? = unknown item
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local CACHE_SECONDS = 30

local C = {}
OMQ.Compare = C

local function isSecret(v) return issecretvalue and issecretvalue(v) end

-- equip location -> inventory slots to compare with
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

C.SLOTS = SLOTS

local STAT_LABEL = {
    ITEM_MOD_STRENGTH_SHORT = "Str", ITEM_MOD_AGILITY_SHORT = "Agi", ITEM_MOD_STAMINA_SHORT = "Sta",
    ITEM_MOD_INTELLECT_SHORT = "Int", ITEM_MOD_SPIRIT_SHORT = "Spi", RESISTANCE0_NAME = "Armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS", ITEM_MOD_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP",
    ITEM_MOD_HEALING_DONE_SHORT = "Heal", ITEM_MOD_CRIT_RATING_SHORT = "Crit",
    ITEM_MOD_HIT_RATING_SHORT = "Hit", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Def",
    ITEM_MOD_DODGE_RATING_SHORT = "Dodge", ITEM_MOD_PARRY_RATING_SHORT = "Parry",
    ITEM_MOD_BLOCK_RATING_SHORT = "Block", ITEM_MOD_BLOCK_VALUE_SHORT = "BlkVal",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
    ITEM_MOD_MANA_SHORT = "Mana", ITEM_MOD_HEALTH_SHORT = "HP",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
}

local function itemInfoInstant(link)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(link) end
    if GetItemInfoInstant then return GetItemInfoInstant(link) end
end

local function itemInfo(link)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(link) end
    if GetItemInfo then return GetItemInfo(link) end
end

local function stats(link)
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not fn then return {} end
    local ok, t = pcall(fn, link)
    return (ok and type(t) == "table") and t or {}
end

local function ilvlOf(link)
    if not link then return nil end
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local v = C_Item.GetDetailedItemLevelInfo(link)
        if type(v) == "number" and v > 0 then return v end
    end
    local _, _, _, lvl = itemInfo(link)
    return lvl
end

local function shortName(link)
    local n = link and itemInfo(link)
    if type(n) == "string" then return n:sub(1, 28) end
end

-- Stat changes from worn to link: "Str+3 Sta-2" (the six biggest), "-" when nothing changes
function C.Deltas(link, worn)
    local mine = stats(link)
    local theirs = worn and stats(worn) or {}
    local deltas = {}
    local keys = {}
    for k in pairs(mine) do keys[k] = true end
    for k in pairs(theirs) do keys[k] = true end
    for k in pairs(keys) do
        local d = (mine[k] or 0) - (theirs[k] or 0)
        if math.abs(d) >= 0.05 then
            local label = STAT_LABEL[k] or tostring(k):gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):sub(1, 6)
            deltas[#deltas + 1] = { label = label, d = d }
        end
    end
    table.sort(deltas, function(a, b)
        if math.abs(a.d) ~= math.abs(b.d) then return math.abs(a.d) > math.abs(b.d) end
        return a.label < b.label
    end)
    local parts = {}
    for i = 1, math.min(#deltas, 6) do
        local d = deltas[i].d
        local txt = (d == math.floor(d)) and string.format("%d", d) or string.format("%.1f", d)
        parts[#parts + 1] = deltas[i].label .. (d >= 0 and "+" or "") .. txt
    end
    return #parts > 0 and table.concat(parts, " ") or "-"
end

-- Local evaluation for this player: status, eqIlvl, eqName, stats string.
-- Returns nil when the item data is not loaded yet.
-- wornOf(slot) gives the worn item for another wearer (the dad simulator, decision 194); level his level
function C.Evaluate(link, wornOf, level)
    local id, _, _, equipLoc = itemInfoInstant(link)
    if not id then return nil end
    local slots = SLOTS[equipLoc or ""]
    if not slots then return "-", "-", "-", "-" end        -- not equippable: nothing to compare
    local name, _, _, itemLevel, minLevel = itemInfo(link)
    if not name then return nil end

    local status = "U"
    if (minLevel or 0) > (level or UnitLevel("player") or 1) then
        status = "L" .. minLevel
    elseif not wornOf then
        local usable
        if C_Item and C_Item.IsUsableItem then usable = C_Item.IsUsableItem(link)
        elseif IsUsableItem then usable = IsUsableItem(link) end
        if usable == false then status = "N" end
    end

    -- the worn item of the slot (for rings and trinkets the weaker one)
    local worn, wornLvl
    for _, slot in ipairs(slots) do
        local l = wornOf and wornOf(slot) or (not wornOf and GetInventoryItemLink("player", slot)) or nil
        if not l then
            worn, wornLvl = nil, 0
            break
        end
        local lv = ilvlOf(l) or 0
        if not worn or lv < wornLvl then worn, wornLvl = l, lv end
    end

    local deltaText = C.Deltas(link, worn)
    local ilvl = worn and wornLvl or 0
    return status, tostring(ilvl), worn and shortName(worn) or "-", deltaText,
        itemLevel
end

----------------------------------------------------------------------
-- Messages
----------------------------------------------------------------------
local requests = {}      -- reqId -> link
local results = {}       -- link -> { at, byGuid = { guid = {name,class,status,...} }, order = {guid} }

local function answer(reqId, link, tries)
    local status, eqIlvl, eqName, st = C.Evaluate(link)
    if not status then
        if (tries or 0) < 2 then
            local id = itemInfoInstant(link)
            if id and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.7, function() answer(reqId, link, (tries or 0) + 1) end)
                return
            end
        end
        status, eqIlvl, eqName, st = "?", "-", "-", "-"
    end
    local me = OMQ:GetSelf()
    if me then OMQ:Send("IR", reqId, me.guid, status, eqIlvl, eqName, st, me.name or "?", me.class or "-") end
end

OMQ:RegisterMessage("IQ", function(f)
    if not OMQ:Master("group") then return end
    local reqId, guid, link = f[1], f[2], f[3]
    local me = OMQ:GetSelf()
    if not (reqId and guid and link) or (me and guid == me.guid) then return end
    answer(reqId, link, 0)
end)

OMQ:RegisterMessage("IR", function(f)
    local reqId, guid = f[1], f[2]
    local link = reqId and requests[reqId]
    local me = OMQ:GetSelf()
    if not (link and guid) or (me and guid == me.guid) then return end
    local r = results[link]
    if not r then return end
    local u = OMQ.users[guid]
    if not r.byGuid[guid] then r.order[#r.order + 1] = guid end
    local name = (f[7] and f[7] ~= "" and f[7]) or (u and u.name) or "?"
    local class = (f[8] and f[8] ~= "-" and f[8]) or (u and u.class)
    r.byGuid[guid] = { name = name, class = class, status = f[3] or "?",
                       eqIlvl = f[4] or "-", eqName = f[5] or "-", stats = f[6] or "-" }
    OMQ:Fire("COMPARE_ANSWER", link)
end)

function C:Request(link)
    if not link or not (OMQ:GetChannel()) then return nil end
    local r = results[link]
    if r and GetTime() - r.at < CACHE_SECONDS then return r end
    local reqId = tostring(math.random(1000000, 9999999))
    requests[reqId] = link
    r = { at = GetTime(), byGuid = {}, order = {}, reqId = reqId }
    results[link] = r
    local me = OMQ:GetSelf()
    if not me then return nil end
    OMQ:Send("IQ", reqId, me.guid, link)
    return r
end

----------------------------------------------------------------------
-- The dads' items next to the tooltip (decision 198)
----------------------------------------------------------------------
-- Hold Alt on an item: beside the item tooltip (and the game's own comparison) a column per dad
-- with the real tooltip of what he wears in that slot, a name plate on top and at the bottom
-- what the hovered item would change for him. Rings and trinkets: both items in the column.
-- Dads without gear data yet (older version) get a short text column from their answer.
local current = nil      -- { link }
local tips, plates = {}, {}
local shown = false
local PLATE_H = 22

local function classHex(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if c then return string.format("%02x%02x%02x", math.floor(c.r * 255 + .5), math.floor(c.g * 255 + .5), math.floor(c.b * 255 + .5)) end
    return "ffffff"
end

local function colorStats(s)
    if not s or s == "-" then return "|cff9aa0a6no change|r" end
    local out = {}
    for tok in s:gmatch("%S+") do
        local up = tok:find("%+") ~= nil
        out[#out + 1] = string.format("|cff%s%s|r", up and "40e060" or "ff5050", tok)
    end
    return table.concat(out, " ")
end
C.ColorStats = colorStats

local function idOf(link) return link and tonumber(link:match("item:(%d+)")) end

-- the dads to show, in group order: those with gear data or an answer to this item
function C.Dads(link)
    local me = OMQ:GetSelf()
    local r = link and results[link]
    local out = {}
    for guid, u in pairs(OMQ.users) do
        if (not me or guid ~= me.guid) and OMQ:IsOnline(u) and (u.gear or (r and r.byGuid[guid])) then
            out[#out + 1] = { guid = guid, name = u.name or "?", class = u.class, level = u.level, role = u.role,
                              gear = u.gear, answer = r and r.byGuid[guid], pos = OMQ:GroupPosition(guid) or 9 }
        end
    end
    -- answers from dads we have not heard a HELLO from (should not happen, but cost nothing)
    for guid, a in pairs(r and r.byGuid or {}) do
        if not OMQ.users[guid] and (not me or guid ~= me.guid) then
            out[#out + 1] = { guid = guid, name = a.name or "?", class = a.class, answer = a, pos = 9 }
        end
    end
    table.sort(out, function(a, b) if a.pos ~= b.pos then return a.pos < b.pos end return a.name < b.name end)
    return out
end

-- what to show: one column per dad, one entry per slot { link or nil, lines = { {text, r, g, b} } }
function C.Plan(link)
    local id, _, _, equipLoc = itemInfoInstant(link)
    local slots = id and SLOTS[equipLoc or ""]
    if not slots then return {} end
    local _, _, _, _, minLevel = itemInfo(link)
    local cols = {}
    for _, d in ipairs(C.Dads(link)) do
        local col = { guid = d.guid, name = d.name, class = d.class, hasGear = d.gear and true or false,
                      roleIcon = OMQ.Score and OMQ.Score.RoleIcon(d.class, d.role) or nil, title = string.format("|cff%s%s|r", classHex(d.class), d.name)
                          .. (d.level and ("  |cff9aa0a6level " .. d.level .. "|r") or ""), entries = {} }
        local a = d.answer
        local note
        -- armour and weapon types first (decision 214): the reason in red behind the score
        local can, why = true, nil
        if OMQ.Score and OMQ.Score.CanUse then can, why = OMQ.Score.CanUse(link, d.class, d.level) end
        if not can then
            note = { d.name .. " cannot use it: " .. why, 1, 0.31, 0.31, short = why, red = true }
        elseif minLevel and d.level and minLevel > d.level then
            note = { string.format("Needs level %d - %s is %d", minLevel, d.name, d.level), 1, 0.63, 0.25 }
        elseif a and a.status == "N" then
            note = { d.name .. " cannot use it", 1, 0.31, 0.31 }
        elseif a and a.status and a.status:sub(1, 1) == "L" then
            note = { "Needs level " .. a.status:sub(2), 1, 0.63, 0.25 }
        end
        col.note = note
        if d.gear then
            for _, slot in ipairs(slots) do
                local worn = d.gear[slot] or nil
                local e = { link = worn, lines = {} }
                if not worn then e.empty = true end
                if note then e.lines[#e.lines + 1] = note end
                if worn and idOf(worn) == id then
                    e.same = true
                    e.lines[#e.lines + 1] = { d.name .. " wears this item", 0.6, 0.63, 0.68 }
                else
                    -- the item score for his class and role (decision 200)
                    local sc = OMQ.Score
                    local twohand = sc and sc.OFFHAND and sc.OFFHAND[equipLoc or ""] and sc.IsTwoHand(d.gear[16])
                    if twohand then
                        -- next to a two-hander an off-hand cannot be used: no score (decision 285)
                        e.lines[#e.lines + 1] = { d.name .. " wields a two-hander - no off-hand", 0.6, 0.63, 0.68 }
                    elseif sc and sc.WeightsOf(d.class, d.role) then
                        e.score = sc.HandDelta and sc.HandDelta(link, equipLoc, worn, d.gear[16], d.gear[17], d.class, d.role)
                            or sc.Delta(link, worn, d.class, d.role)
                        -- the score is in the item tooltip itself (decision 213), not in the dad's column
                        e.lines[#e.lines + 1] = { "Score for " .. d.name .. ": " .. sc.Format(e.score), 1, 1, 1, score = true }
                    else
                        e.lines[#e.lines + 1] = { "For " .. d.name .. ": " .. colorStats(C.Deltas(link, worn)), 1, 1, 1 }
                    end
                end
                col.entries[#col.entries + 1] = e
            end
        else
            local e = { lines = {} }
            if note then e.lines[#e.lines + 1] = note end
            local worn = (a.eqName ~= "-") and (a.eqName .. " (item level " .. a.eqIlvl .. ")") or "empty slot"
            e.lines[#e.lines + 1] = { "Wears: " .. worn, 1, 1, 1 }
            e.lines[#e.lines + 1] = { "For " .. d.name .. ": " .. colorStats(a.stats), 1, 1, 1 }
            e.lines[#e.lines + 1] = { "(no gear sync yet - older addon version)", 0.6, 0.63, 0.68 }
            col.entries[#col.entries + 1] = e
        end
        cols[#cols + 1] = col
    end
    return cols
end

local function tipAt(i)
    if not tips[i] then
        tips[i] = CreateFrame("GameTooltip", "OneMoreQuestDadTip" .. i, UIParent, "GameTooltipTemplate")
        if tips[i].SetClampedToScreen then tips[i]:SetClampedToScreen(false) end
    end
    return tips[i]
end

-- the name tab above a dad's tooltip, in the style of the game's "Equipped" tab (decision 204):
-- a small tooltip frame with a gold edge and the name in gold
local function plateAt(i)
    if not plates[i] then
        local ok, p = pcall(CreateFrame, "Frame", nil, UIParent, "TooltipBackdropTemplate")
        if not ok or not p then p = CreateFrame("Frame", nil, UIParent) end
        p:SetFrameStrata("TOOLTIP")
        p:SetHeight(PLATE_H)
        local nine = rawget(p, "NineSlice")
        if nine and nine.SetBorderColor then
            pcall(nine.SetBorderColor, nine, 0.80, 0.64, 0.30, 1)
            if nine.SetCenterColor then pcall(nine.SetCenterColor, nine, 0.06, 0.06, 0.08, 0.95) end
        elseif p.SetBackdrop and BACKDROP_TOOLTIP_16_16_5555 then
            pcall(p.SetBackdrop, p, BACKDROP_TOOLTIP_16_16_5555)
            if p.SetBackdropBorderColor then pcall(p.SetBackdropBorderColor, p, 0.80, 0.64, 0.30, 1) end
        else
            local bg = p:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.06, 0.08, 0.95)
            for k = 1, 4 do
                local e = p:CreateTexture(nil, "BORDER")
                e:SetColorTexture(0.80, 0.64, 0.30, 1)
                if k == 1 then e:SetPoint("TOPLEFT"); e:SetPoint("TOPRIGHT"); e:SetHeight(1)
                elseif k == 2 then e:SetPoint("BOTTOMLEFT"); e:SetPoint("BOTTOMRIGHT"); e:SetHeight(1)
                elseif k == 3 then e:SetPoint("TOPLEFT"); e:SetPoint("BOTTOMLEFT"); e:SetWidth(1)
                else e:SetPoint("TOPRIGHT"); e:SetPoint("BOTTOMRIGHT"); e:SetWidth(1) end
            end
        end
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", 10, 0)
        -- the symbol of the dad's preferred role behind the name (decision 206)
        local ic = p:CreateTexture(nil, "OVERLAY")
        ic:SetSize(14, 14)
        ic:SetPoint("LEFT", fs, "RIGHT", 5, 0)
        if ic.SetTexCoord then ic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        plates[i] = { frame = p, text = fs, icon = ic }
    end
    return plates[i]
end

function C:HideDads()
    for _, t in ipairs(tips) do t:Hide() end
    for _, p in ipairs(plates) do p.frame:Hide() end
    shown = false
end

local function num(v, fallback) return type(v) == "number" and v or fallback end

-- edges of a frame in UIParent units
local function edges(fr)
    if not (fr and fr.IsShown and fr:IsShown()) then return nil end
    local l, r, t = fr:GetLeft(), fr:GetRight(), fr:GetTop()
    if type(l) ~= "number" or type(r) ~= "number" or type(t) ~= "number" then return nil end
    local k = num(fr:GetEffectiveScale(), 1) / num(UIParent:GetEffectiveScale(), 1)
    return l * k, r * k, t * k
end

function C:ShowDads(link)
    self:HideDads()
    local cols = C.Plan(link)
    if #cols == 0 then return 0 end
    -- fill the tooltips
    local n = 0
    local scale = num(GameTooltip.GetScale and GameTooltip:GetScale(), 1)
    for ci, col in ipairs(cols) do
        col.tips = {}
        local plate = plateAt(ci)
        plate.text:SetText(col.name or col.title)
        plate.frame:SetScale(scale)
        local tabW = num(plate.text:GetStringWidth(), 60) + 20
        if col.roleIcon then
            plate.icon:SetTexture(col.roleIcon); plate.icon:Show(); tabW = tabW + 19
        else
            plate.icon:Hide()
        end
        plate.frame:SetWidth(tabW)
        local width = tabW + 4
        for _, e in ipairs(col.entries) do
            n = n + 1
            local t = tipAt(n)
            t:SetOwner(UIParent, "ANCHOR_NONE")
            t:SetScale(scale)
            if e.link then
                t:SetHyperlink(e.link)
            elseif e.empty then
                t:SetText("Empty slot", 0.6, 0.63, 0.68)
            else
                t:SetText(col.title)
            end
            local shownLines = {}
            for _, l in ipairs(e.lines) do if not l.score then shownLines[#shownLines + 1] = l end end
            if #shownLines > 0 then t:AddLine(" ") end
            for _, l in ipairs(shownLines) do t:AddLine(l[1], l[2], l[3], l[4], true) end
            t:Show()
            width = math.max(width, num(t:GetWidth(), 200))
            col.tips[#col.tips + 1] = t
        end
        col.width = width
        for _, t in ipairs(col.tips) do
            if t.SetMinimumWidth then t:SetMinimumWidth(width - 20) end
            t:Show()
            col.width = math.max(col.width, num(t:GetWidth(), width))
        end
    end
    -- place the columns: right of the item tooltip and the game's comparison, then left of them.
    -- They hang on those tooltips, so they move along when the tooltip follows the mouse (decision 199).
    local left, right, leftFrame, rightFrame
    for _, fr in ipairs({ GameTooltip, _G.ShoppingTooltip1, _G.ShoppingTooltip2 }) do
        local l, r = edges(fr)
        if l then
            if not left or l < left then left, leftFrame = l, fr end
            if not right or r > right then right, rightFrame = r, fr end
        end
    end
    local screenW = num(UIParent:GetWidth(), 1920)
    leftFrame, rightFrame = leftFrame or GameTooltip, rightFrame or GameTooltip
    left, right = left or screenW / 2, right or screenW / 2
    -- all columns on one side if they fit there: right first, else left; only when neither side has
    -- room for all, the side with more room is filled first and the rest goes to the other (decision 204)
    local total = 0
    for _, col in ipairs(cols) do total = total + col.width * scale end
    local spaceR, spaceL = screenW - right, left
    local first = (total <= spaceR and "right") or (total <= spaceL and "left") or (spaceR >= spaceL and "right" or "left")
    local lastRight, lastLeft
    for ci, col in ipairs(cols) do
        local w = col.width * scale
        local side = first
        if side == "right" and w > spaceR and w <= spaceL then side = "left"
        elseif side == "left" and w > spaceL and w <= spaceR then side = "right" end
        local top = col.tips[1]
        top:ClearAllPoints()
        if side == "right" then
            spaceR = spaceR - w
            if lastRight then top:SetPoint("TOPLEFT", lastRight, "TOPRIGHT", 0, 0)
            else top:SetPoint("TOPLEFT", rightFrame, "TOPRIGHT", 0, 0) end
            lastRight = top
        else
            spaceL = spaceL - w
            if lastLeft then top:SetPoint("TOPRIGHT", lastLeft, "TOPLEFT", 0, 0)
            else top:SetPoint("TOPRIGHT", leftFrame, "TOPLEFT", 0, 0) end
            lastLeft = top
        end
        col.side = side
        -- the tooltip tops line up with the item tooltip; the name tab sits above, like "Equipped"
        local plate = plates[ci]
        plate.frame:ClearAllPoints()
        plate.frame:SetPoint("BOTTOMLEFT", top, "TOPLEFT", 4, -2)
        plate.frame:Show()
        for k = 2, #col.tips do
            col.tips[k]:ClearAllPoints()
            col.tips[k]:SetPoint("TOPLEFT", col.tips[k - 1], "BOTTOMLEFT", 0, 0)
        end
    end
    shown = true
    C._last = cols
    return #cols
end

local function linkOfTooltip(tt, data)
    local link = data and data.hyperlink
    if not link and tt and tt.GetItem then
        local ok, _, l = pcall(tt.GetItem, tt)
        if ok then link = l end
    end
    if type(link) ~= "string" or isSecret(link) then return nil end
    return link:match("item:[%-%d:]+") or link
end

local function altDown() return IsAltKeyDown and IsAltKeyDown() end

local function refresh()
    if current and altDown() and GameTooltip and GameTooltip:IsShown() then
        C:Request(current.link)
        C:ShowDads(current.link)
    elseif shown then
        C:HideDads()
    end
end
C.Refresh = refresh

-- The scores of all dads at a glance, in the item tooltip itself (decision 213): one line per dad
-- with gear data, his role symbol and name on the left, the score on the right (for rings and
-- trinkets the better of his two slots). Returns the lines { left, right }.
-- my own line, first (decision 294): the score against what I wear, like the dads' lines
function C.MySummary(link)
    local S, LP = OMQ.Score, OMQ.LootPreview
    if not (S and LP and LP.Gain and S.MyClass) then return nil end
    local id, _, _, equipLoc = itemInfoInstant(link)
    local slots = id and SLOTS[equipLoc or ""]
    if not slots then return nil end
    local class, role = S.MyClass(), S.MyRole and S.MyRole()
    if not S.WeightsOf(class, role) then return nil end
    local right
    for _, slot in ipairs(slots) do
        local worn = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if worn and not isSecret(worn) and idOf(worn) == id then right = "|cff9aa0a6wears it|r" end
    end
    if not right then
        local main = GetInventoryItemLink and GetInventoryItemLink("player", 16)
        if S.OFFHAND and S.OFFHAND[equipLoc or ""] and S.IsTwoHand and S.IsTwoHand(main) then
            right = "|cff9aa0a6two-hander - no off-hand|r"
        else
            local g = LP.Gain(link, equipLoc, class, role)
            if not g then return nil end
            right = S.Format(g)
            local level = UnitLevel and tonumber((UnitLevel("player"))) or 1
            local can, why = true, nil
            if S.CanUse then can, why = S.CanUse(link, class, level) end
            local minLevel = select(5, itemInfo(link))
            if not can then right = right .. "  |cffff5050(" .. (why or "cannot use") .. ")|r"
            elseif minLevel and minLevel > level then right = right .. "  |cffffa040(level " .. minLevel .. ")|r" end
        end
    end
    local icon = (S.RoleIcon and S.RoleIcon(class, role)) and ("|T" .. S.RoleIcon(class, role) .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
    local name = UnitName and UnitName("player") or "You"
    return { icon .. string.format("|cff%s%s|r", classHex(class), name) .. " |cff9aa0a6(you)|r", right }
end

function C.Summary(link)
    local out = {}
    local mine = C.MySummary(link)
    if mine then out[1] = mine end
    for _, col in ipairs(C.Plan(link)) do
        if col.hasGear then
            local best, same
            for _, e in ipairs(col.entries) do
                if e.same then same = true end
                if e.score and (not best or e.score > best) then best = e.score end
            end
            local right
            if same and not best then right = "|cff9aa0a6wears it|r"
            elseif best then right = OMQ.Score.Format(best) end
            if right then
                if col.note then
                    local n = col.note[1]
                    local lvl = n:match("Needs level (%d+)")
                    if col.note.red then right = right .. "  |cffff5050(" .. col.note.short .. ")|r"
                    elseif lvl then right = right .. "  |cffffa040(level " .. lvl .. ")|r"
                    else right = right .. "  |cffff5050(cannot use)|r" end
                end
                local icon = col.roleIcon and ("|T" .. col.roleIcon .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
                out[#out + 1] = { icon .. string.format("|cff%s%s|r", classHex(col.class), col.name), right }
            end
        end
    end
    return out
end

local function addSummary(tt, link)
    if not (tt and tt.AddDoubleLine) then return end
    local lines = C.Summary(link)
    if #lines == 0 then return end
    tt:AddLine(" ")
    tt:AddLine("Score", 0.89, 0.71, 0.29)
    for _, l in ipairs(lines) do tt:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 1, 1) end
    if tt.Show then tt:Show() end
end
C._addSummary = addSummary

local function onItemTooltip(tt, data)
    if tt ~= GameTooltip then return end
    if OMQ.db.options.compare == false or not OMQ:Master("group") then current = nil; C:HideDads(); return end
    local link = linkOfTooltip(tt, data)
    if not link then current = nil; C:HideDads(); return end
    local id, _, _, equipLoc = itemInfoInstant(link)
    if not (id and SLOTS[equipLoc or ""]) then current = nil; C:HideDads(); return end
    current = { link = link }
    local ok, err = pcall(addSummary, tt, link)
    if not ok then OMQ:Error("compare summary", err) end
    refresh()
end

function C:OnAlt() refresh() end

OMQ:On("COMPARE_ANSWER", function(link)
    if current and current.link == link then refresh() end
end)
OMQ:On("GEAR_UPDATED", function() if shown then refresh() end end)

OMQ:On("READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            local ok, err = pcall(onItemTooltip, tt, data)
            if not ok then OMQ:Error("compare tooltip", err) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local ok, err = pcall(onItemTooltip, tt, nil)
            if not ok then OMQ:Error("compare tooltip", err) end
        end)
    end
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnHide", function() current = nil; C:HideDads() end)
    end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("MODIFIER_STATE_CHANGED")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
local refreshSoon = false
ev:SetScript("OnEvent", function(_, event, key, state)
    if event == "GET_ITEM_INFO_RECEIVED" then
        -- a dad's item was not in the cache yet: draw again once it is
        if shown and not refreshSoon then
            refreshSoon = true
            C_Timer.After(0.2, function() refreshSoon = false; pcall(refresh) end)
        end
        return
    end
    if key == "LALT" or key == "RALT" then
        local ok, err = pcall(refresh)
        if not ok then OMQ:Error("compare alt", err) end
    end
end)

-- test hooks
C._onItemTooltip = onItemTooltip
function C:Shown() return shown end
