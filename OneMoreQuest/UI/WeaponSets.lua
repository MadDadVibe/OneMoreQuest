-- One More Quest: two weapon set buttons right of the main action bar (decision 669)
-- Each button stands for one set of weapons (main hand + off hand). A left click or its key (game key bindings,
-- AddOns > One More Quest) puts the set on, also in a fight: the buttons are secure macro buttons with
-- "/equipslot 16 item:<id>" lines, the game's own secure command. The set shown on a button is the main hand's icon,
-- the set worn right now glows. Shift + left click stores the weapons worn now on that button.
-- Automatic sets: every weapon ever worn is remembered (per character). When the remembered weapons that are still
-- owned (bags + worn) give exactly two sets - the worn one and exactly one other - both buttons are filled from them.
-- That check runs again when a weapon is worn that was never worn before (it wins over sets stored by hand); when it
-- is not clear, the set that glowed before takes the new weapons. With only one set, other weapons put on fill set 2. A third key swaps to the other set.
-- In a fight the macros cannot change (secure attributes): a new set takes effect right after the fight; icon and glow
-- follow at once. The ranged slot is never touched; fishing poles are not weapons here.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local W = {}
OMQ.WeaponSets = W

W.MH, W.OH = 16, 17
W.SIZE = 54          -- fix 672: 50 % bigger than the first 36
W.KIND = {
    INVTYPE_2HWEAPON = "two", INVTYPE_WEAPON = "one", INVTYPE_WEAPONMAINHAND = "one",
    INVTYPE_WEAPONOFFHAND = "off", INVTYPE_SHIELD = "off", INVTYPE_HOLDABLE = "off",
}
W.QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- the key binding texts (game key bindings window, AddOns > One More Quest; see Bindings.xml)
BINDING_HEADER_ONEMOREQUEST = "One More Quest"
_G["BINDING_NAME_CLICK OneMoreQuestWeaponSet1:LeftButton"] = "Weapon set 1"
_G["BINDING_NAME_CLICK OneMoreQuestWeaponSet2:LeftButton"] = "Weapon set 2"
_G["BINDING_NAME_CLICK OneMoreQuestWeaponSwap:LeftButton"] = "Swap weapon sets"

local buttons, holder, header, swap = {}, nil, nil, nil
local pending = false        -- attributes or visibility wait for the end of the fight
local moveMode = false

local function combat() return InCombatLockdown and InCombatLockdown() end
local function charKey() return (UnitGUID and UnitGUID("player")) or "?" end

-- per character: { known = { [id] = true }, sets = { {mh, oh}, {mh, oh} }, active = n }
function W.Data()
    local db = OMQ.db
    if not db then return nil end
    db.wsets = db.wsets or {}
    local k = charKey()
    db.wsets[k] = db.wsets[k] or { known = {}, sets = {} }
    local d = db.wsets[k]
    d.known = d.known or {}
    d.combos = d.combos or {}      -- fix 672: every main + off hand pair worn together
    d.sets = d.sets or {}
    return d
end

function W.Enabled()
    local o = OMQ.db and OMQ.db.options
    return not o or o.weaponSets ~= false
end

local function instant(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not (f and id) then return nil end
    return f(id)
end

-- the icon of a set: the shield when the set has one (fix 672, MadDadVibe's choice), else the main hand
function W.SetIcon(set)
    if not (set and set.mh) then return nil end
    if set.oh then
        local _, _, _, loc = instant(set.oh)
        if loc == "INVTYPE_SHIELD" then return W.Icon(set.oh) end
    end
    return W.Icon(set.mh)
end

-- "two", "one", "off" or nil (not a weapon of the two hands, or a fishing pole)
function W.Kind(id)
    local _, _, _, equipLoc, _, classID, subclassID = instant(id)
    if classID == 2 and subclassID == 20 then return nil end     -- fishing pole
    return W.KIND[equipLoc or ""]
end

function W.Icon(id)
    local _, _, _, _, icon = instant(id)
    if icon then return icon end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id) or nil
end

local function wornId(slot)
    local id = GetInventoryItemID and GetInventoryItemID("player", slot)
    if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then return nil end
    return id
end

-- the weapons worn now: { mh = id, oh = id }
function W.Worn()
    local mh, oh = wornId(W.MH), wornId(W.OH)
    if mh and not W.Kind(mh) then mh = nil end
    if oh and not W.Kind(oh) then oh = nil end
    return { mh = mh, oh = oh }
end

-- how many of each item are in the bags
function W.BagCounts()
    local out = {}
    local Ct = C_Container
    if not (Ct and Ct.GetContainerNumSlots and Ct.GetContainerItemInfo) then return out end
    for bag = 0, (OMQ.LastBag and OMQ.LastBag() or 4) do
        for s = 1, Ct.GetContainerNumSlots(bag) or 0 do
            local it = Ct.GetContainerItemInfo(bag, s)
            local id = it and it.itemID
            if type(id) == "number" and not (issecretvalue and issecretvalue(id)) then
                out[id] = (out[id] or 0) + (it.stackCount or 1)
            end
        end
    end
    return out
end

local function same(a, b)
    if not (a and b) then return false end
    return a.mh == b.mh and a.oh == b.oh
end
W.Same = same

-- the one other set the remembered weapons in the bags give, or nil and why ("none" / "unclear")
-- the key of a worn pair in d.combos
function W.ComboKey(set) return (set.mh or 0) .. ":" .. (set.oh or 0) end

function W.OtherSet(worn, bags, known, dual, combos)
    if not (worn and worn.mh) then return nil, "unclear" end
    local items = {}
    for id, n in pairs(bags) do
        if known[id] and W.Kind(id) then
            for _ = 1, math.min(n, 2) do items[#items + 1] = id end
        end
    end
    table.sort(items)
    if #items == 0 then return nil, "none" end
    if #items == 1 then
        local id = items[1]
        local k = W.Kind(id)
        -- fix 672: a one-hander that was worn together with the worn main hand goes back to the off hand
        -- (two equal one-handers + shield: the second sword is the off hand of the other set)
        if k == "one" and dual and combos and W.Kind(worn.mh) == "one" then
            if combos[W.ComboKey({ mh = worn.mh, oh = id })] then return { mh = worn.mh, oh = id } end
            if combos[W.ComboKey({ mh = id, oh = worn.mh })] then return { mh = id, oh = worn.mh } end
        end
        if k == "two" or k == "one" then return { mh = id } end
        -- only an off-hand piece: the worn one-hander with it
        if k == "off" and W.Kind(worn.mh) == "one" then return { mh = worn.mh, oh = id } end
        return nil, "unclear"
    end
    if #items == 2 then
        local a, b = items[1], items[2]
        local ka, kb = W.Kind(a), W.Kind(b)
        if ka == "one" and kb == "off" then return { mh = a, oh = b } end
        if kb == "one" and ka == "off" then return { mh = b, oh = a } end
        -- two equal one-handers of a dual wielder: one in each hand
        if a == b and ka == "one" and dual then return { mh = a, oh = b } end
    end
    return nil, "unclear"
end

-- which set is worn: exact match first, then a set without an off hand whose main hand is worn
function W.ActiveIndex(sets, worn)
    for i = 1, 2 do if same(sets[i], worn) then return i end end
    for i = 1, 2 do
        local s = sets[i]
        if s and s.mh and s.mh == worn.mh and not s.oh and W.Kind(s.mh) ~= "two" then return i end
    end
    return nil
end

local function copy(s) return s and { mh = s.mh, oh = s.oh } or nil end

-- puts two sets on the buttons, keeping a set where it already is
function W.Place(sets, a, b)
    if same(sets[2], a) or same(sets[1], b) then sets[1], sets[2] = copy(b), copy(a)
    else sets[1], sets[2] = copy(a), copy(b) end
end

-- the automatic check. reason "new": a weapon worn for the first time, "lost": a set's weapon is gone.
-- "fill": weapons changed while there is only one set. Returns what it did: "auto", "single", "fill", "active", "kept".
function W.Auto(d, worn, bags, reason, dual)
    local sets = d.sets
    if not worn.mh then return "kept" end
    local other, why = W.OtherSet(worn, bags, d.known, dual, d.combos)
    if other and not same(other, worn) then
        W.Place(sets, worn, other)
        d.active = W.ActiveIndex(sets, worn)
        return "auto"
    end
    if why == "none" then
        sets[1], sets[2] = copy(worn), nil
        d.active = 1
        return "single"
    end
    -- only one set so far and other weapons worn now: they become the second set
    if reason == "fill" and sets[1] and not sets[2] and not same(sets[1], worn) then
        sets[2] = copy(worn)
        d.active = 2
        return "fill"
    end
    if reason == "new" then
        local i = d.active or (sets[1] and not sets[2] and 2) or 1
        sets[i] = copy(worn)
        d.active = i
        return "active"
    end
    return "kept"
end

-- true when an item of the set is neither worn nor in the bags
function W.Missing(set, bags, worn)
    if not set then return false end
    local function have(id)
        if not id then return true end
        return (bags[id] or 0) > 0 or worn.mh == id or worn.oh == id
    end
    return not (have(set.mh) and have(set.oh))
end

function W.Macro(set)
    if not (set and set.mh) then return nil end
    local m = "/equipslot " .. W.MH .. " item:" .. set.mh
    if set.oh and W.Kind(set.mh) ~= "two" then
        local o = "/equipslot " .. W.OH .. " item:" .. set.oh
        -- fix 672: the same weapon in both hands: off hand first, so the line of the main hand does not take
        -- the copy from the bag (that copy would be locked for the off-hand line)
        if set.oh == set.mh then m = o .. "\n" .. m else m = m .. "\n" .. o end
    end
    return m
end

-- both sets there and different: the buttons are shown
function W.Ready(d)
    d = d or W.Data()
    return d and d.sets[1] and d.sets[2] and not same(d.sets[1], d.sets[2]) and true or false
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------
-- the swap key: the restricted snippet picks the set that is not the current one (works in a fight)
W.SWAP_SNIPPET = [[
    if down then return end
    local cur = owner:GetAttribute("omq-cur") or 1
    local nxt = (cur == 1) and 2 or 1
    local m = owner:GetAttribute("omq-macro" .. nxt)
    if not m then return false end
    self:SetAttribute("macrotext1", m)
    owner:SetAttribute("omq-cur", nxt)
]]
-- a set button tells the header which set is on now (Shift + click stores and changes nothing here)
W.SET_SNIPPET = [[
    if down or button ~= "LeftButton" or IsShiftKeyDown() then return end
    owner:SetAttribute("omq-cur", self:GetID())
]]

W.DEFAULT_ANCHOR = { "BOTTOMLEFT", "BOTTOMRIGHT", 8, 0 }
local function anchorBar() return _G.MainActionBar or _G.MainMenuBar or _G.ActionButton12 end

function W.ApplyPosition()
    if not holder or combat() then return end
    holder:ClearAllPoints()
    local p = OMQ.db and OMQ.db.wsetPos
    local bar = anchorBar()
    if p and p[1] == "TOPLEFT" then
        holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p[3], p[4])
    elseif bar then
        local a = W.DEFAULT_ANCHOR
        holder:SetPoint(a[1], bar, a[2], a[3], a[4])
    else
        holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 300, 10)
    end
end

local function savePosition()
    if not holder then return end
    local left, top = holder:GetLeft(), holder:GetTop()
    if not (left and top) then return end
    local pl, pt = UIParent:GetLeft() or 0, UIParent:GetTop() or 0
    OMQ.db.wsetPos = { "TOPLEFT", "TOPLEFT", left - pl, top - pt }
end

local function tooltip(b)
    if not GameTooltip then return end
    local d = W.Data()
    local set = d and d.sets[b:GetID()]
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Weapon set " .. b:GetID())
    if set then
        -- fix 672: both hands named, an empty off hand too (it keeps what you wear there)
        local function name(id) return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or ("item " .. id) end
        GameTooltip:AddDoubleLine("Main hand", name(set.mh), 0.8, 0.8, 0.8, 1, 1, 1)
        if set.oh then GameTooltip:AddDoubleLine("Off hand", name(set.oh), 0.8, 0.8, 0.8, 1, 1, 1)
        elseif W.Kind(set.mh) ~= "two" then GameTooltip:AddDoubleLine("Off hand", "stays as it is", 0.8, 0.8, 0.8, 0.6, 0.6, 0.6) end
        if W.Missing(set, W.BagCounts(), W.Worn()) then GameTooltip:AddLine("A weapon of this set is not in your bags", 1, 0.3, 0.3) end
    else
        GameTooltip:AddLine("Empty", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Left click: put these weapons on (also in a fight)", 0.7, 0.85, 1)
    GameTooltip:AddLine("Shift + left click: store the weapons you wear now", 0.7, 0.85, 1)
    GameTooltip:AddLine("Keys: game key bindings, AddOns > One More Quest", 0.6, 0.6, 0.6)
    if combat() and pending then GameTooltip:AddLine("Changed sets take effect after the fight", 1, 0.8, 0.3) end
    GameTooltip:Show()
end

local function makeButton(i)
    local b = CreateFrame("Button", "OneMoreQuestWeaponSet" .. i, holder, "SecureActionButtonTemplate")
    b:SetID(i)
    b:SetSize(W.SIZE, W.SIZE)
    b:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, (i == 1) and (W.SIZE + 4) or 0)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type1", "macro")
    b:SetAttribute("shift-type1", ATTRIBUTE_NOOP or "")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon:SetTexture(W.QUESTION)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.64, 0.50, 0.21, 1)
    -- the light glow of the set worn now (textures may change in a fight)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(0.3, 1, 0.35)          -- fix 674: green (MadDadVibe), was yellow
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(W.SIZE * 1.85, W.SIZE * 1.85)
    b.glow:Hide()
    if b.CreateAnimationGroup then
        local g = b:CreateAnimationGroup()
        g:SetLooping("BOUNCE")
        local a = g:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0.45); a:SetDuration(1.2)
        a:SetTarget(b.glow)
        b.pulse = g
    end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:HookScript("OnClick", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then W.Store(self:GetID()) end
    end)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function() if moveMode and not combat() then holder:StartMoving() end end)
    b:SetScript("OnDragStop", function()
        if not holder then return end
        holder:StopMovingOrSizing()
        savePosition()
        W.ApplyPosition()
    end)
    if header and header.WrapScript then header:WrapScript(b, "OnClick", W.SET_SNIPPET) end
    return b
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "OneMoreQuestWeaponSets", UIParent)
    holder:SetSize(W.SIZE, W.SIZE * 2 + 4)
    holder:SetFrameStrata("MEDIUM")
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    if SecureHandlerWrapScript then
        header = CreateFrame("Frame", "OneMoreQuestWeaponSetsHeader", UIParent, "SecureHandlerBaseTemplate")
    end
    buttons[1], buttons[2] = makeButton(1), makeButton(2)
    swap = CreateFrame("Button", "OneMoreQuestWeaponSwap", UIParent, "SecureActionButtonTemplate")
    swap:SetSize(1, 1)
    swap:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    swap:SetAlpha(0)
    swap:EnableMouse(false)
    swap:RegisterForClicks("AnyUp")
    swap:SetAttribute("useOnKeyDown", false)
    swap:SetAttribute("type1", "macro")
    if header and header.WrapScript then header:WrapScript(swap, "OnClick", W.SWAP_SNIPPET) end
    W.ApplyPosition()
    holder:Hide()
end

-- icons and glow: allowed in a fight
function W.Paint()
    if not holder then return end
    local d = W.Data()
    if not d then return end
    local worn, bags = W.Worn(), W.BagCounts()
    local active = W.ActiveIndex(d.sets, worn)
    if active then d.active = active end
    for i = 1, 2 do
        local b, set = buttons[i], d.sets[i]
        b.icon:SetTexture(W.SetIcon(set) or W.QUESTION)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(W.Missing(set, bags, worn)) end
        if active == i then
            b.glow:Show()
            if b.pulse and not b.pulse:IsPlaying() then pcall(b.pulse.Play, b.pulse) end
        else
            b.glow:Hide()
            if b.pulse then pcall(b.pulse.Stop, b.pulse) end
        end
    end
    W.active = active
end

-- macros, header state and visibility: out of a fight only
function W.Apply()
    if not holder then return end
    if combat() then pending = true; W.Paint(); return end
    pending = false
    local d = W.Data()
    if not d then return end
    for i = 1, 2 do
        local m = W.Macro(d.sets[i])
        buttons[i]:SetAttribute("macrotext1", m or "")
        if header then header:SetAttribute("omq-macro" .. i, m) end
    end
    if header then header:SetAttribute("omq-cur", W.ActiveIndex(d.sets, W.Worn()) or d.active or 1) end
    swap:SetAttribute("macrotext1", W.Macro(d.sets[(W.ActiveIndex(d.sets, W.Worn()) == 1) and 2 or 1]) or "")
    W.ApplyPosition()
    if W.Enabled() and (W.Ready(d) or moveMode) then holder:Show() else holder:Hide() end
    for i = 1, 2 do buttons[i]:EnableMouse(true) end
    W.Paint()
end

function W.Shown() return holder and holder:IsShown() or false end
function W.Buttons() return buttons[1], buttons[2], swap, header end

-- Shift + left click: the weapons worn now on button i
function W.Store(i)
    local d = W.Data()
    if not d then return end
    local worn = W.Worn()
    if not worn.mh then return end
    d.known[worn.mh] = true
    if worn.oh then d.known[worn.oh] = true end
    d.sets[i] = copy(worn)
    d.combos[W.ComboKey(worn)] = true
    d.active = i
    W.Apply()
end

local function dual() return CanDualWield and CanDualWield() and true or false end

-- a weapon slot changed: remember new weapons, the automatic check when one was never worn before
function W.EquipChanged()
    local d = W.Data()
    if not d then return end
    local worn = W.Worn()
    local new = false
    for _, id in ipairs({ worn.mh, worn.oh }) do
        if id and not d.known[id] then d.known[id] = true; new = true end
    end
    -- fix 672: a pair worn for the first time completes a set that has this main hand but no off hand yet
    local key = worn.mh and W.ComboKey(worn)
    local newPair = key and not d.combos[key]
    if key then d.combos[key] = true end
    if new then W.Auto(d, worn, W.BagCounts(), "new", dual())
    elseif not W.Ready(d) then W.Auto(d, worn, W.BagCounts(), "fill", dual())
    elseif newPair and worn.oh then
        local i = W.ActiveIndex(d.sets, worn)
        local s = i and d.sets[i]
        if s and not s.oh and s.mh == worn.mh and not (d.sets[3 - i] and same(d.sets[3 - i], worn)) then
            s.oh = worn.oh
            d.active = i
        end
    end
    W.Apply()
    return new
end

-- bags changed: a set whose weapon is gone is checked again (only when the result is clear)
function W.BagsChanged()
    local d = W.Data()
    if not d then return end
    local worn, bags = W.Worn(), W.BagCounts()
    if W.Missing(d.sets[1], bags, worn) or W.Missing(d.sets[2], bags, worn) then
        local r = W.Auto(d, worn, bags, "lost", dual())
        if r ~= "kept" then W.Apply(); return r end
    end
    W.Paint()
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local driver = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }) do
    pcall(driver.RegisterEvent, driver, e)
end
local bagsDue = false
driver:SetScript("OnEvent", function(_, event, slot)
    if not holder then return end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        if slot == W.MH or slot == W.OH then W.EquipChanged() end
    elseif event == "BAG_UPDATE_DELAYED" then
        -- weapons move between bags and hands while a set goes on: look a moment later
        if not bagsDue and C_Timer then
            bagsDue = true
            C_Timer.After(1, function() bagsDue = false; pcall(W.BagsChanged) end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then W.Apply() end
    else
        W.EquipChanged()
    end
end)

OMQ:On("READY", function()
    build()
    W.EquipChanged()
end)

OMQ:On("MOVE_MODE", function(on)
    moveMode = on and true or false
    W.Apply()
end)

OMQ:RegisterCommand("wset", function(arg)
    local d = W.Data()
    if not d then return end
    if (arg or "") == "reset" then
        if OMQ.db then OMQ.db.wsetPos = nil end
        W.ApplyPosition()
        OMQ:Print("Weapon sets: position reset")
        return
    end
    local function line(s) return s and ((s.mh or "-") .. " + " .. (s.oh or "-")) or "empty" end
    local n = 0
    for _ in pairs(d.known) do n = n + 1 end
    OMQ:Print("Weapon sets: 1 = " .. line(d.sets[1]) .. ", 2 = " .. line(d.sets[2]) .. ", worn " .. line(W.Worn())
        .. ", " .. n .. " weapons remembered, " .. (W.Shown() and "shown" or "hidden"))
end, "weapon set buttons: state (reset = default position)")
