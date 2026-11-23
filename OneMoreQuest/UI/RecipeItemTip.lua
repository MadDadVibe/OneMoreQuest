-- One More Quest: the crafted item next to a trainer recipe (decision 661)
-- Hovering a recipe in the trainer window (GameTooltip:SetTrainerService) shows a second tooltip beside the game's
-- recipe tooltip with the item that recipe makes. It is a normal item tooltip, so every item line of the addon
-- (auction house and vendor price, the price of the whole batch when a craft makes several, who needs it ...) is
-- there too. The item comes from the game (GetTrainerServiceItemLink) or from the recipe spell of the service via
-- Data/ProfSkillUp.lua (product and pieces per craft), else from C_TradeSkillUI.GetRecipeOutputItemData.
-- Only a hook after the game's call and an own tooltip frame: no secure frame is touched.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local R = {}
OMQ.RecipeItemTip = R

local isSecret = function(v) return issecretvalue and issecretvalue(v) end
local tip

local function itemOfLink(link)
    if type(link) ~= "string" or isSecret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- the recipe spell of a trainer service: the tooltip data of the service, else the spell the tooltip shows
function R.SpellOf(index, tt)
    local T = C_TooltipInfo
    if T and T.GetTrainerService then
        local ok, data = pcall(T.GetTrainerService, index)
        local id = ok and type(data) == "table" and data.id
        if type(id) == "number" and not isSecret(id) then return id end
    end
    if tt and tt.GetSpell then
        local ok, _, id = pcall(tt.GetSpell, tt)
        if ok and type(id) == "number" and not isSecret(id) then return id end
    end
    return nil
end

-- item id and pieces per craft of a trainer service, or nil (class spells, enchantments without an item)
function R.Output(index, tt)
    if type(index) ~= "number" or isSecret(index) then return nil end
    local spell = R.SpellOf(index, tt)
    local data = spell and OMQ.ProfSkillUp and OMQ.ProfSkillUp[spell]
    local count = data and tonumber(data[3]) or 1
    if GetTrainerServiceItemLink then
        local ok, link = pcall(GetTrainerServiceItemLink, index)
        local id = ok and itemOfLink(link)
        if id then return id, count, "game", spell end
    end
    if data and tonumber(data[2]) and data[2] > 0 then return data[2], count, "data", spell end
    local TS = C_TradeSkillUI
    if spell and TS and TS.GetRecipeOutputItemData then
        local ok, out = pcall(TS.GetRecipeOutputItemData, spell)
        local id = ok and type(out) == "table" and out.itemID
        if type(id) == "number" and not isSecret(id) and id > 0 then return id, count, "recipe", spell end
    end
    return nil, nil, nil, spell
end

local function getTip()
    if not tip then
        tip = CreateFrame("GameTooltip", "OneMoreQuestRecipeItemTip", UIParent, "GameTooltipTemplate")
        if tip.SetFrameStrata then tip:SetFrameStrata("TOOLTIP") end
    end
    return tip
end

function R.Hide()
    if tip then tip.omqCount = nil; tip:Hide() end
end

-- right of the game's tooltip, left of it when the screen ends there
local function place(t, owner)
    t:ClearAllPoints()
    local right = owner.GetRight and owner:GetRight()
    local sw = UIParent.GetWidth and UIParent:GetWidth()
    local k = (owner.GetEffectiveScale and owner:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local w = (t.GetWidth and t:GetWidth() or 250) * ((t.GetEffectiveScale and t:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1))
    if type(right) == "number" and type(sw) == "number" and right * k + w > sw then
        t:SetPoint("TOPRIGHT", owner, "TOPLEFT", 0, 0)
    else
        t:SetPoint("TOPLEFT", owner, "TOPRIGHT", 0, 0)
    end
end

function R.OnService(tt, index)
    R.Hide()
    if OMQ.db and OMQ.db.options and OMQ.db.options.recipeItemTip == false then return end
    if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
    local id, count, how, spell = R.Output(index, tt)
    R.last = { index = index, id = id, count = count, how = how, spell = spell }
    if not id then return end
    local t = getTip()
    t:SetOwner(UIParent, "ANCHOR_NONE")
    if tt.GetScale and t.SetScale then t:SetScale(tt:GetScale() or 1) end
    t.omqCount = (count and count > 1) and count or nil   -- the price lines take the whole batch (UI/CraftPrices.lua)
    t:SetItemByID(id)
    if count and count > 1 then t:AddLine("Made " .. count .. " at a time", 0.6, 0.6, 0.6) end
    t:Show()
    place(t, tt)
end

OMQ:RegisterCommand("recipetip", function()
    local l = R.last
    if not l then OMQ:Print("no trainer recipe hovered yet"); return end
    OMQ:Print(("service %s: spell %s, item %s x%s (%s)"):format(tostring(l.index), tostring(l.spell),
        tostring(l.id), tostring(l.count), tostring(l.how or "none found")))
end, "recipetip - the item found for the last hovered trainer recipe", true)

OMQ:On("READY", function()
    if not (GameTooltip and hooksecurefunc) then return end
    if GameTooltip.SetTrainerService then
        hooksecurefunc(GameTooltip, "SetTrainerService", function(tt, index)
            local ok, err = pcall(R.OnService, tt, index)
            if not ok then OMQ:Error("recipe item tooltip", err) end
        end)
    end
    if GameTooltip.HookScript then
        GameTooltip:HookScript("OnHide", function() R.Hide() end)
        GameTooltip:HookScript("OnTooltipCleared", function() R.Hide() end)
    end
end)
