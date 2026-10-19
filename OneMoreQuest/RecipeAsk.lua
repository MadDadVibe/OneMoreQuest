-- One More Quest: "does the group have what this recipe needs?"
-- A button next to the favorite star of the selected recipe in the profession window asks
-- every addon user which of the recipe's materials they carry (bags, and bank separately).
-- The answers appear in a small panel next to the profession window.
--   RQ|proto|reqId|guid|id1,id2,...              (question: the material item ids)
--   RR|proto|reqId|guid|name|class|id:bags:total,...   (answer; only items the player has)
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local MAX_IDS = 12                -- item ids per question (message size)
local WAIT_SECONDS = 3            -- until "nobody has any" is shown

local A = {}
OMQ.RecipeAsk = A

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function itemCount(id, bank)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, bank and true or false) or 0 end
    if GetItemCount then return GetItemCount(id, bank and true or false) or 0 end
    return 0
end

local function itemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return n or ("item " .. id)
end

local function classHex(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if c then return string.format("%02x%02x%02x", math.floor(c.r * 255 + .5), math.floor(c.g * 255 + .5), math.floor(c.b * 255 + .5)) end
    return "ffffff"
end

----------------------------------------------------------------------
-- The materials of a recipe schematic: { { ids = {itemID, ...}, qty = n }, ... }
----------------------------------------------------------------------
function A.SlotsOf(schematic)
    local slots = {}
    if type(schematic) ~= "table" then return slots end
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        if slot.reagentType == nil or slot.reagentType == 1 then
            local ids = {}
            for _, r in ipairs(slot.reagents or {}) do
                if r.itemID then ids[#ids + 1] = r.itemID end
            end
            if #ids > 0 then slots[#slots + 1] = { ids = ids, qty = slot.quantityRequired or 1 } end
        end
    end
    return slots
end

local function allIds(slots)
    local ids, seen = {}, {}
    for _, s in ipairs(slots) do
        for _, id in ipairs(s.ids) do
            if not seen[id] and #ids < MAX_IDS then seen[id] = true; ids[#ids + 1] = id end
        end
    end
    return ids
end

----------------------------------------------------------------------
-- Answering a question
----------------------------------------------------------------------
OMQ:RegisterMessage("RQ", function(f)
    if not OMQ:Master("group") then return end
    local reqId, guid, list = f[1], f[2], f[3]
    local me = OMQ:GetSelf()
    if not (reqId and guid and list) or not me or guid == me.guid then return end
    local parts, n = {}, 0
    for id in tostring(list):gmatch("%d+") do
        n = n + 1
        if n > MAX_IDS then break end
        id = tonumber(id)
        local bags, total = itemCount(id, false), itemCount(id, true)
        if total > 0 then parts[#parts + 1] = id .. ":" .. bags .. ":" .. total end
    end
    if #parts == 0 then return end
    OMQ:Send("RR", reqId, me.guid, me.name or "?", me.class or "-", table.concat(parts, ","))
end)

----------------------------------------------------------------------
-- Asking, collecting
----------------------------------------------------------------------
local current            -- { reqId, name, slots, at, order, byGuid }

OMQ:RegisterMessage("RR", function(f)
    local reqId, guid = f[1], f[2]
    if not (current and reqId and current.reqId == reqId and guid) then return end
    local me = OMQ:GetSelf()
    if me and guid == me.guid then return end
    local counts = {}
    for id, bags, total in tostring(f[5] or ""):gmatch("(%d+):(%d+):(%d+)") do
        counts[tonumber(id)] = { bags = tonumber(bags), total = tonumber(total) }
    end
    if next(counts) == nil then return end
    if not current.byGuid[guid] then current.order[#current.order + 1] = guid end
    current.byGuid[guid] = { name = (f[3] and f[3] ~= "") and f[3] or "?", class = f[4] ~= "-" and f[4] or nil, counts = counts }
    OMQ:Fire("RECIPEASK_ANSWER")
end)

-- Starts a question for a list of slots. Returns the state, or nil and a reason.
function A:Ask(name, slots)
    if not OMQ:Master("group") then return nil, "Group features are switched off." end
    local me = OMQ:GetSelf()
    if not (me and OMQ:GetChannel()) then return nil, "You are not in a group." end
    local ids = allIds(slots)
    if #ids == 0 then return nil, "This recipe has no materials." end
    current = { reqId = tostring(math.random(1000000, 9999999)), name = name or "?", slots = slots,
                at = GetTime(), order = {}, byGuid = {} }
    OMQ:Send("RQ", current.reqId, me.guid, table.concat(ids, ","))
    return current
end

-- Lines of the answer panel.
function A:Lines()
    local c = current
    if not c then return {} end
    local lines = { "|cffffd100" .. c.name .. "|r" }
    if #c.order == 0 then
        if GetTime() - c.at < WAIT_SECONDS then
            lines[#lines + 1] = "Asking the group ..."
        else
            lines[#lines + 1] = "Nobody in the group has any of these materials."
        end
        return lines
    end
    for _, slot in ipairs(c.slots) do
        local names = {}
        for _, id in ipairs(slot.ids) do names[#names + 1] = itemName(id) end
        local rows = {}
        for _, guid in ipairs(c.order) do
            local a = c.byGuid[guid]
            local parts = {}
            for _, id in ipairs(slot.ids) do
                local k = a.counts[id]
                if k then
                    local text = tostring(k.total)
                    if k.total > k.bags then text = k.bags .. " (+" .. (k.total - k.bags) .. " in bank)" end
                    if #slot.ids > 1 then text = itemName(id) .. " " .. text end
                    parts[#parts + 1] = text
                end
            end
            if #parts > 0 then
                rows[#rows + 1] = string.format("   |cff%s%s|r: %s", classHex(a.class), a.name, table.concat(parts, ", "))
            end
        end
        if #rows > 0 then
            lines[#lines + 1] = string.format("%s x%d", table.concat(names, " / "), slot.qty)
            for _, r in ipairs(rows) do lines[#lines + 1] = r end
        end
    end
    if #lines == 1 then lines[#lines + 1] = "Nobody in the group has any of these materials." end
    return lines
end

----------------------------------------------------------------------
-- The button and the panel
----------------------------------------------------------------------
local button, panel, text

local function professionsFrame() return _G.ProfessionsFrame end

local function schematicForm()
    local pf = professionsFrame()
    return pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
end

-- The favorite star of the recipe: by its usual key, else the first member whose key says so.
local function findStar(form)
    if not form then return nil end
    if form.FavoriteButton then return form.FavoriteButton end
    for k, v in pairs(form) do
        if type(k) == "string" and k:lower():find("favorite") and type(v) == "table" and v.SetPoint then return v end
    end
    return nil
end

-- the "Reagents" heading of the recipe (decision 194): the button sits right of it
local REAGENT_WORDS = { reagents = true, reagenzien = true }
local function textIsReagents(fs)
    local ok, t = pcall(fs.GetText, fs)
    if not ok or type(t) ~= "string" then return false end
    t = t:lower():gsub("[:%s]+$", "")
    local g = _G.PROFESSIONS_COLUMN_HEADER_REAGENTS or _G.SPELL_REAGENTS_OPTIONAL
    return REAGENT_WORDS[t] or (type(g) == "string" and t == g:lower():gsub("[:%s]+$", "")) or false
end
local function findInRegions(f, depth)
    if not f or depth > 3 then return nil end
    if f.GetRegions then
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and textIsReagents(r) then return r end
        end
    end
    if f.GetChildren then
        for _, c in ipairs({ f:GetChildren() }) do
            local hit = findInRegions(c, depth + 1)
            if hit then return hit end
        end
    end
end
function A.FindReagentLabel(form)
    if not form then return nil end
    local r = form.Reagents
    if type(r) == "table" and type(r.Label) == "table" and r.Label.GetText then return r.Label end
    return findInRegions(form, 0)
end

local function currentRecipe()
    local form = schematicForm()
    if not form then return nil end
    local info = form.GetRecipeInfo and form:GetRecipeInfo() or form.recipeInfo
    local schematic = form.recipeSchematic
    if not schematic and info and info.recipeID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        schematic = C_TradeSkillUI.GetRecipeSchematic(info.recipeID, false)
    end
    return info and info.name, schematic
end

local function refresh()
    if not (panel and panel:IsShown() and text) then return end
    text:SetText(table.concat(A:Lines(), "\n"))
    if text.GetStringHeight and panel.SetHeight then panel:SetHeight((text:GetStringHeight() or 20) + 24) end
end

local function buildPanel()
    if panel then return end
    panel = CreateFrame("Frame", "OneMoreQuestRecipePanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(300, 60)
    panel:SetFrameStrata("DIALOG")
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        panel:SetBackdropColor(0, 0, 0, 0.92)
    end
    text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 10, -10)
    text:SetWidth(280)
    text:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() panel:Hide() end)
    panel:Hide()
end

local function showPanel()
    buildPanel()
    panel:ClearAllPoints()
    local pf = professionsFrame()
    if pf then panel:SetPoint("TOPLEFT", pf, "TOPRIGHT", 4, 0) else panel:SetPoint("CENTER", UIParent, "CENTER", 300, 0) end
    panel:Show()
    refresh()
    if C_Timer and C_Timer.After then C_Timer.After(WAIT_SECONDS + 0.2, refresh) end
end

function A:Click()
    local name, schematic = currentRecipe()
    local slots = A.SlotsOf(schematic)
    local state, why = A:Ask(name, slots)
    if not state then
        buildPanel()
        current = { name = name or "?", slots = {}, at = 0, order = {}, byGuid = {} }
        showPanel()
        if text then text:SetText("|cffffd100" .. (name or "?") .. "|r\n" .. tostring(why)) end
        return
    end
    showPanel()
end

function A:EnsureButton()
    local form = schematicForm()
    if not form then return false end
    if not button then
        button = CreateFrame("Button", "OneMoreQuestRecipeButton", form)
        button:SetSize(22, 22)
        button:SetFrameLevel((form.GetFrameLevel and form:GetFrameLevel() or 1) + 10)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
        button.icon = icon
        button:SetScript("OnClick", function() local ok, err = pcall(A.Click, A); if not ok then OMQ:Error("recipe ask", err) end end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Ask the group")
            GameTooltip:AddLine("Which of these materials do the other addon users carry?", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local star = findStar(form)
    local label = A.FindReagentLabel(form)
    button:ClearAllPoints()
    if label then
        local w = (label.GetStringWidth and label:GetStringWidth()) or 70
        button:SetPoint("LEFT", label, "LEFT", w + 8, 0)
    elseif star then button:SetPoint("LEFT", star, "RIGHT", 4, 0)
    else button:SetPoint("TOPRIGHT", form, "TOPRIGHT", -12, -12) end
    button.onLabel = label and true or false
    button.hasStar = star and true or false
    button:Show()
    return true
end

local function ensureLater()
    local function go() local ok, err = pcall(A.EnsureButton, A); if not ok then OMQ:Error("recipe button", err) end end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, go) else go() end
end

local hooked
local function hookForm()
    local form = schematicForm()
    if not form or hooked then return end
    hooked = true
    if hooksecurefunc and form.Init then
        hooksecurefunc(form, "Init", function()
            if panel and panel:IsShown() then panel:Hide() end      -- another recipe: the answer is stale
            ensureLater()
        end)
    end
    local pf = professionsFrame()
    if pf and pf.HookScript then pf:HookScript("OnHide", function() if panel then panel:Hide() end end) end
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "ADDON_LOADED" }) do pcall(frame.RegisterEvent, frame, e) end
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_Professions" then return end
    pcall(hookForm)
    ensureLater()
end)

OMQ:On("RECIPEASK_ANSWER", function() pcall(refresh) end)
OMQ:On("READY", function() pcall(hookForm); pcall(A.EnsureButton, A) end)

OMQ:RegisterCommand("recipeask", function()
    local form = schematicForm()
    local out = { "Recipe ask button" }
    out[#out + 1] = "ProfessionsFrame: " .. tostring(professionsFrame() ~= nil)
    out[#out + 1] = "SchematicForm: " .. tostring(form ~= nil)
    out[#out + 1] = "star found: " .. tostring(findStar(form) ~= nil)
    out[#out + 1] = "button anchored next to the star: " .. tostring(button and button.hasStar or false)
    local name, schematic = currentRecipe()
    local slots = A.SlotsOf(schematic)
    out[#out + 1] = string.format("selected recipe: %s, %d material slots", tostring(name), #slots)
    OMQ:ShowReport(out)
end, "diagnose the profession window button")
