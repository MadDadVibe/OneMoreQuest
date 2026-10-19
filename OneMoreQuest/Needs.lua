-- One More Quest: "who needs this material?"
-- Every character remembers the reagents of the recipes it has learned (read
-- from the profession window when it is opened) that make a rare (blue) or epic
-- (purple) item, plus enchanting recipes. Hovering a green or better material
-- asks the group; whoever needs it answers, and the answers are added to the
-- tooltip.
--   NQ|proto|reqId|guid|itemID                       (question)
--   NR|proto|reqId|guid|name|class|res1,res2,res3    (answer; only when needed)
-- A result is "i<itemID>" or "s<spellID>" (enchants), so every client resolves
-- the names in its own language.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local MIN_ITEM_QUALITY = 2        -- the hovered material: green or better
local MIN_RESULT_QUALITY = 3      -- the crafted item: blue or better
local MAX_RESULTS = 3
local CACHE_SECONDS = 60

local N = {}
OMQ.Needs = N

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function itemInfoInstant(x)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(x) end
    if GetItemInfoInstant then return GetItemInfoInstant(x) end
end

local function itemQuality(x)
    if C_Item and C_Item.GetItemQualityByID and type(x) == "number" then
        local q = C_Item.GetItemQualityByID(x)
        if q then return q end
    end
    if C_Item and C_Item.GetItemInfo then return select(3, C_Item.GetItemInfo(x)) end
    if GetItemInfo then return select(3, GetItemInfo(x)) end
end

local function requestLoad(id)
    if id and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end

local function idOfLink(link, kind)
    return link and tonumber(tostring(link):match(kind .. ":(%d+)"))
end

----------------------------------------------------------------------
-- Scanning the profession windows
----------------------------------------------------------------------
-- map: reagentItemID -> list of result tags
local function addReagent(map, reagentId, tag)
    if not reagentId then return end
    local list = map[reagentId]
    if not list then list = {}; map[reagentId] = list end
    if #list >= MAX_RESULTS then return end
    for _, t in ipairs(list) do if t == tag then return end end
    list[#list + 1] = tag
end

-- decides whether a crafted item counts; nil quality = not loaded yet
local function resultQualifies(itemId, state)
    local q = itemQuality(itemId)
    if q == nil then
        state.unknown = (state.unknown or 0) + 1
        requestLoad(itemId)
        return false
    end
    return q >= MIN_RESULT_QUALITY
end

local function scanModern(state)
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeSchematic and T.GetRecipeInfo) then return nil end
    local profName
    if T.GetBaseProfessionInfo then
        local info = T.GetBaseProfessionInfo()
        profName = info and info.professionName
    end
    local map, n = {}, 0
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local ri = T.GetRecipeInfo(id)
        if ri and ri.learned then
            local schem = T.GetRecipeSchematic(id, false)
            if schem then
                local tag
                local out = schem.outputItemID
                if out then
                    if resultQualifies(out, state) then tag = "i" .. out end
                elseif ri.isEnchantingRecipe or schem.recipeType == (Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Enchant) then
                    tag = "s" .. id                         -- enchants always count
                end
                if tag then
                    n = n + 1
                    for _, slot in ipairs(schem.reagentSlotSchematics or {}) do
                        if slot.reagentType == nil or slot.reagentType == 1 then
                            for _, r in ipairs(slot.reagents or {}) do addReagent(map, r.itemID, tag) end
                        end
                    end
                end
            end
        end
    end
    return profName, map, n
end

local function scanClassicTradeSkill(state)
    if not (GetNumTradeSkills and GetTradeSkillItemLink and GetTradeSkillNumReagents and GetTradeSkillReagentItemLink) then return nil end
    local profName = GetTradeSkillLine and GetTradeSkillLine()
    local map, n = {}, 0
    for i = 1, GetNumTradeSkills() do
        local _, skillType = GetTradeSkillInfo(i)
        if skillType ~= "header" then
            local out = idOfLink(GetTradeSkillItemLink(i), "item")
            if out and resultQualifies(out, state) then
                n = n + 1
                for j = 1, GetTradeSkillNumReagents(i) do
                    addReagent(map, idOfLink(GetTradeSkillReagentItemLink(i, j), "item"), "i" .. out)
                end
            end
        end
    end
    return profName, map, n
end

local function scanCraft()
    if not (GetNumCrafts and GetCraftItemLink and GetCraftNumReagents and GetCraftReagentItemLink) then return nil end
    local profName = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() or "Enchanting"
    local map, n = {}, 0
    for i = 1, GetNumCrafts() do
        local _, _, craftType = GetCraftInfo(i)
        if craftType ~= "header" then
            local spell = idOfLink(GetCraftItemLink(i), "enchant")
            if spell then
                n = n + 1
                for j = 1, GetCraftNumReagents(i) do
                    addReagent(map, idOfLink(GetCraftReagentItemLink(i, j), "item"), "s" .. spell)
                end
            end
        end
    end
    return profName, map, n
end

local function store(profName, map, n)
    local guid = UnitGUID("player")
    if not (guid and profName and OMQDB) then return end
    OMQDB.recipes = OMQDB.recipes or {}
    OMQDB.recipes[guid] = OMQDB.recipes[guid] or {}
    OMQDB.recipes[guid][profName] = { map = map, n = n, at = time() }
    OMQ:Fire("RECIPES_SCANNED", profName, n)
end

local scanTimer = {}
function N:Scan(kind, attempt)
    attempt = attempt or 0
    local state = {}
    local profName, map, n
    if kind == "craft" then
        profName, map, n = scanCraft()
    else
        profName, map, n = scanModern(state)
        if not map then profName, map, n = scanClassicTradeSkill(state) end
    end
    if not map then return false end
    store(profName, map, n)
    -- crafted items whose data was not loaded yet: look again shortly
    if (state.unknown or 0) > 0 and attempt < 3 and C_Timer and C_Timer.After then
        C_Timer.After(1.5, function() N:Scan(kind, attempt + 1) end)
    end
    return true
end

local function scheduleScan(kind)
    local now = GetTime()
    if now - (scanTimer[kind] or -1) < 0.5 then return end
    scanTimer[kind] = now
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() local ok, err = pcall(N.Scan, N, kind); if not ok then OMQ:Error("recipe scan", err) end end)
    else
        pcall(N.Scan, N, kind)
    end
end

local scanFrame = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
    pcall(scanFrame.RegisterEvent, scanFrame, e)
end
scanFrame:SetScript("OnEvent", function(_, event)
    if event:find("^CRAFT") then scheduleScan("craft") else scheduleScan("trade") end
end)

OMQ:On("DB_READY", function() OMQDB.recipes = OMQDB.recipes or {} end)

----------------------------------------------------------------------
-- Lookup: what does this character need the item for?
----------------------------------------------------------------------
function N:Lookup(itemId)
    local guid = UnitGUID("player")
    local mine = OMQDB and OMQDB.recipes and OMQDB.recipes[guid]
    if not mine then return nil end
    local out = {}
    for _, prof in pairs(mine) do
        local list = prof.map and prof.map[itemId]
        if list then
            for _, tag in ipairs(list) do
                local dup = false
                for _, t in ipairs(out) do if t == tag then dup = true end end
                if not dup and #out < MAX_RESULTS then out[#out + 1] = tag end
            end
        end
    end
    if #out == 0 then return nil end
    table.sort(out)
    return out
end

local function tagName(tag)
    local kind, id = tag:sub(1, 1), tonumber(tag:sub(2))
    if not id then return "?" end
    if kind == "s" then
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        return n or ("spell " .. id)
    end
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n then requestLoad(id) end
    return n or ("item " .. id)
end

----------------------------------------------------------------------
-- Messages
----------------------------------------------------------------------
local requests = {}      -- reqId -> itemId
local results = {}       -- itemId -> { at, order, byGuid }

OMQ:RegisterMessage("NQ", function(f)
    if not OMQ:Master("group") then return end
    local reqId, guid, itemId = f[1], f[2], tonumber(f[3])
    local me = OMQ:GetSelf()
    if not (reqId and guid and itemId) or (me and guid == me.guid) or not me then return end
    local list = N:Lookup(itemId)
    if not list then return end
    OMQ:Send("NR", reqId, me.guid, me.name or "?", me.class or "-", table.concat(list, ","))
end)

OMQ:RegisterMessage("NR", function(f)
    local reqId, guid = f[1], f[2]
    local itemId = reqId and requests[reqId]
    local me = OMQ:GetSelf()
    if not (itemId and guid) or (me and guid == me.guid) then return end
    local r = results[itemId]
    if not r then return end
    local tags = {}
    for tag in tostring(f[5] or ""):gmatch("[^,]+") do tags[#tags + 1] = tag end
    if #tags == 0 then return end
    if not r.byGuid[guid] then r.order[#r.order + 1] = guid end
    r.byGuid[guid] = { name = (f[3] and f[3] ~= "") and f[3] or "?", class = f[4] ~= "-" and f[4] or nil, tags = tags }
    OMQ:Fire("NEEDS_ANSWER", itemId)
end)

function N:Ask(itemId)
    local r = results[itemId]
    if r and GetTime() - r.at < CACHE_SECONDS then return r end
    r = { at = GetTime(), order = {}, byGuid = {} }
    results[itemId] = r
    -- my own needs first (no message needed)
    local me = OMQ:GetSelf()
    local mine = N:Lookup(itemId)
    if mine then
        local guid = (me and me.guid) or UnitGUID("player")
        r.order[1] = guid
        r.byGuid[guid] = { name = "You", class = select(2, UnitClass("player")), tags = mine, self = true }
    end
    if me and OMQ:GetChannel() then
        local reqId = tostring(math.random(1000000, 9999999))
        requests[reqId] = itemId
        OMQ:Send("NQ", reqId, me.guid, tostring(itemId))
    end
    return r
end

----------------------------------------------------------------------
-- Tooltip
----------------------------------------------------------------------
local current = nil      -- { itemId, shown = {}, header = false }

local function classHex(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if c then return string.format("%02x%02x%02x", math.floor(c.r * 255 + .5), math.floor(c.g * 255 + .5), math.floor(c.b * 255 + .5)) end
    return "ffffff"
end

local function render(tt)
    if not (current and tt and tt.AddLine) then return end
    local r = results[current.itemId]
    if not r then return end
    local added = false
    for _, guid in ipairs(r.order) do
        if not current.shown[guid] then
            if not current.header then
                tt:AddLine(" ")
                tt:AddLine("Needed for crafting", 0.45, 0.8, 1)
                current.header = true
            end
            local a = r.byGuid[guid]
            local names = {}
            for _, tag in ipairs(a.tags) do names[#names + 1] = tagName(tag) end
            tt:AddLine(string.format("|cff%s%s|r  %s", classHex(a.class), a.name, table.concat(names, ", ")), 1, 1, 1, true)
            current.shown[guid] = true
            added = true
        end
    end
    if added and tt.Show then tt:Show() end
end

local function linkOfTooltip(tt, data)
    local link = data and data.hyperlink
    if not link and tt and tt.GetItem then
        local ok, _, l = pcall(tt.GetItem, tt)
        if ok then link = l end
    end
    if type(link) ~= "string" or isSecret(link) then return nil end
    return link
end

-- green or better crafting material (or gem)
local function isMaterial(itemId, link)
    local _, _, _, _, _, classID = itemInfoInstant(link or itemId)
    if classID ~= 7 and classID ~= 3 then return false end
    local q = itemQuality(link or itemId)
    return q ~= nil and q >= MIN_ITEM_QUALITY
end

local function onItemTooltip(tt, data)
    if tt ~= GameTooltip then return end
    if OMQ.db.options.needs == false or not OMQ:Master("group") then current = nil; return end
    local link = linkOfTooltip(tt, data)
    local itemId = idOfLink(link, "item")
    if not itemId or not isMaterial(itemId, link) then current = nil; return end
    current = { itemId = itemId, shown = {}, header = false }
    N:Ask(itemId)
    render(tt)
end

OMQ:On("NEEDS_ANSWER", function(itemId)
    if current and current.itemId == itemId and GameTooltip and GameTooltip:IsShown() then render(GameTooltip) end
end)

OMQ:On("READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            local ok, err = pcall(onItemTooltip, tt, data)
            if not ok then OMQ:Error("needs tooltip", err) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local ok, err = pcall(onItemTooltip, tt, nil)
            if not ok then OMQ:Error("needs tooltip", err) end
        end)
    end
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipCleared", function() current = nil end)
        GameTooltip:HookScript("OnHide", function() current = nil end)
    end
end)

----------------------------------------------------------------------
-- Diagnostics
----------------------------------------------------------------------
OMQ:RegisterCommand("recipes", function(arg)
    local out = { "Recipe scan" }
    out[#out + 1] = "C_TradeSkillUI: " .. tostring(C_TradeSkillUI ~= nil)
        .. ", GetNumTradeSkills: " .. tostring(GetNumTradeSkills ~= nil)
        .. ", GetNumCrafts: " .. tostring(GetNumCrafts ~= nil)
    local mine = OMQDB.recipes and OMQDB.recipes[UnitGUID("player")]
    if not mine or next(mine) == nil then
        out[#out + 1] = "nothing scanned yet - open each of your profession windows once"
    else
        for prof, d in pairs(mine) do
            local reagents = 0
            for _ in pairs(d.map or {}) do reagents = reagents + 1 end
            out[#out + 1] = string.format("%s: %d recipes with a blue/purple result (or enchants), %d reagents", prof, d.n or 0, reagents)
        end
    end
    if arg == "clear" then OMQDB.recipes[UnitGUID("player")] = nil; out[#out + 1] = "cleared" end
    OMQ:ShowReport(out)
end, "recipes the addon knows for material tips (open your profession windows once)")

N._onItemTooltip = onItemTooltip
