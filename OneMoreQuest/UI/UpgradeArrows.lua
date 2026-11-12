-- One More Quest: upgrade arrows on the game's own item buttons (decision 533)
-- Green arrow up = an upgrade for me, blue = not for me but for another dad of the group (OMQ.LootPreview.ArrowOf,
-- his gear from the gear sync). On: the bags and the bank (the game's own bag windows, also the combined bag),
-- the loot window, the need/greed roll frames, the merchant (items for sale, not the buyback list) and the quest
-- rewards in the game's quest window (accepting and turning in, also the quest log). Every place reads the item
-- link from the game and draws again on its events; hooks are hooksecurefunc only and nothing is written onto the
-- game's buttons (the arrow textures live in a side table of OMQ.LootPreview). Option "Upgrade arrows on items"
-- (options.upgradeArrows).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local A = {}
OMQ.UpgradeArrows = A

local function LP() return OMQ.LootPreview end
local function call(f, ...)
    if not f then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    return unpack(r, 2)
end
local function plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

function A.On() return not (OMQ.db and OMQ.db.options and OMQ.db.options.upgradeArrows == false) end

-- one button: the arrow of its link (nil link or arrows off: none)
function A.Mark(btn, link)
    if not (btn and LP()) then return nil end
    local kind = (A.On() and plain(link) and link) and LP().ArrowOf(link) or nil
    LP().Arrow(btn, kind, 37)
    return kind
end

local function shown(f) return f and f.IsShown and f:IsShown() end

----------------------------------------------------------------------
-- Bags and bank
----------------------------------------------------------------------
local function containerLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then return call(C_Container.GetContainerItemLink, bag, slot) end
    return call(GetContainerItemLink, bag, slot)
end

-- bag and slot of a bag button: the modern GetBagID, else the id of its bag frame
local function bagSlot(btn)
    local slot = call(btn.GetID, btn)
    local bag = btn.GetBagID and call(btn.GetBagID, btn)
    if bag == nil then
        local parent = call(btn.GetParent, btn)
        bag = parent and call(parent.GetID, parent)
    end
    return bag, slot
end

local function markBagButton(btn)
    if not shown(btn) then return end
    local bag, slot = bagSlot(btn)
    if type(bag) ~= "number" or type(slot) ~= "number" then return end
    A.Mark(btn, containerLink(bag, slot))
end

-- the item buttons of a modern bag frame (EnumerateValidItems); false when the frame has none
local function each(f, fn)
    if not (f and f.EnumerateValidItems) then return false end
    local iter, st, init = call(f.EnumerateValidItems, f)
    if type(iter) ~= "function" then return false end
    for _, btn in iter, st, init do fn(btn) end
    return true
end

function A.Bags()
    local n = 0
    local function mark(btn) markBagButton(btn); n = n + 1 end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if shown(f) then
            if not each(f, mark) then
                for j = 1, 36 do
                    local btn = _G["ContainerFrame" .. i .. "Item" .. j]
                    if not btn then break end
                    markBagButton(btn); n = n + 1
                end
            end
        end
    end
    local c = _G.ContainerFrameCombinedBags
    if shown(c) then each(c, mark) end
    -- the bank: the old BankFrameItemN buttons (bag -1), or the new bank panel
    if shown(_G.BankFrame) then
        for j = 1, (NUM_BANKGENERIC_SLOTS or 28) do
            local btn = _G["BankFrameItem" .. j]
            if btn and shown(btn) then
                A.Mark(btn, containerLink(BANK_CONTAINER or -1, call(btn.GetID, btn) or j)); n = n + 1
            end
        end
    end
    local bp = _G.BankPanel
    if shown(bp) then each(bp, mark) end
    return n
end

----------------------------------------------------------------------
-- Loot window and roll frames
----------------------------------------------------------------------
function A.Loot()
    local n = 0
    local lf = _G.LootFrame
    if lf and lf.ScrollBox and lf.ScrollBox.ForEachFrame then
        lf.ScrollBox:ForEachFrame(function(frame)
            local slot = frame.GetSlotIndex and call(frame.GetSlotIndex, frame)
            local btn = frame.Item or frame
            if slot then A.Mark(btn, call(GetLootSlotLink, slot)); n = n + 1 end
        end)
    end
    for i = 1, (LOOTFRAME_NUMBUTTONS or 4) do
        local btn = _G["LootButton" .. i]
        if btn and shown(btn) then
            local slot = btn.slot
            if type(slot) == "number" then A.Mark(btn, call(GetLootSlotLink, slot)); n = n + 1 else A.Mark(btn, nil) end
        end
    end
    return n
end

function A.Rolls()
    local n = 0
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local f = _G["GroupLootFrame" .. i]
        if shown(f) then
            local btn = f.IconFrame or _G["GroupLootFrame" .. i .. "IconFrame"]
            local id = f.rollID
            if btn and type(id) == "number" then A.Mark(btn, call(GetLootRollItemLink, id)); n = n + 1 end
        end
    end
    return n
end

----------------------------------------------------------------------
-- Merchant
----------------------------------------------------------------------
function A.Merchant()
    local n = 0
    local mf = _G.MerchantFrame
    if not shown(mf) then return 0 end
    local buyback = mf.selectedTab == 2
    for i = 1, (MERCHANT_ITEMS_PER_PAGE or 10) do
        local btn = _G["MerchantItem" .. i .. "ItemButton"]
        if btn then
            local index = call(btn.GetID, btn)
            local link = (not buyback and shown(btn) and type(index) == "number") and call(GetMerchantItemLink, index) or nil
            A.Mark(btn, link)
            if link then n = n + 1 end
        end
    end
    return n
end

----------------------------------------------------------------------
-- Quest rewards
----------------------------------------------------------------------
function A.Quest()
    local n = 0
    local log = _G.QuestInfoFrame and _G.QuestInfoFrame.questLog
    for i = 1, 10 do
        local btn = _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
        if not btn then break end
        local link
        if shown(btn) then
            local kind, id = btn.type, call(btn.GetID, btn)
            if kind and type(id) == "number" then
                if log then link = call(GetQuestLogItemLink, kind, id) else link = call(GetQuestItemLink, kind, id) end
            end
        end
        A.Mark(btn, link)
        if link then n = n + 1 end
    end
    return n
end

----------------------------------------------------------------------
-- Drawing: after the game drew (a short delay), at most once per batch of events
----------------------------------------------------------------------
local pending = {}
local function run(what)
    local fn = A[what]
    if not fn then return end
    local ok, err = pcall(fn)
    if not ok then OMQ:Error("upgrade arrows " .. what, err) end
end

function A.Soon(what, delay)
    if pending[what] then return end
    pending[what] = true
    C_Timer.After(delay or 0.05, function()
        pending[what] = nil
        run(what)
    end)
end

function A.All()
    if LP() and LP().ArrowReset then LP().ArrowReset() end
    for _, w in ipairs({ "Bags", "Loot", "Rolls", "Merchant", "Quest" }) do run(w) end
end

local EVENTS = {
    BAG_UPDATE_DELAYED = "Bags", BAG_OPEN = "Bags", ITEM_LOCK_CHANGED = "Bags", BANKFRAME_OPENED = "Bags",
    PLAYERBANKSLOTS_CHANGED = "Bags",
    LOOT_OPENED = "Loot", LOOT_SLOT_CLEARED = "Loot",
    START_LOOT_ROLL = "Rolls",
    MERCHANT_SHOW = "Merchant", MERCHANT_UPDATE = "Merchant",
    QUEST_DETAIL = "Quest", QUEST_COMPLETE = "Quest", QUEST_LOG_UPDATE = "Quest",
}
local frame = CreateFrame("Frame")
for e in pairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
pcall(frame.RegisterEvent, frame, "PLAYER_EQUIPMENT_CHANGED")
pcall(frame.RegisterEvent, frame, "PLAYER_LEVEL_UP")
pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" then
        if LP() and LP().ArrowReset then LP().ArrowReset() end
        A.Soon("Bags", 0.3); A.Soon("Merchant", 0.3)
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        A.Soon("Bags", 0.5); A.Soon("Loot", 0.5); A.Soon("Rolls", 0.5); A.Soon("Merchant", 0.5); A.Soon("Quest", 0.5)
        return
    end
    local w = EVENTS[event]
    if w then A.Soon(w, w == "Rolls" and 0.2 or 0.05) end
end)

-- the game's own draw functions (whichever exist on this client): draw again right after them
local HOOKS = {
    ContainerFrame_Update = "Bags", ContainerFrame_UpdateAll = "Bags", BankFrame_UpdateItems = "Bags",
    LootFrame_Update = "Loot", MerchantFrame_UpdateMerchantInfo = "Merchant", MerchantFrame_Update = "Merchant",
    QuestInfo_Display = "Quest", QuestInfo_ShowRewards = "Quest", GroupLootFrame_OnShow = "Rolls",
}
OMQ:On("READY", function()
    for fn, w in pairs(HOOKS) do
        if type(_G[fn]) == "function" and hooksecurefunc then
            pcall(hooksecurefunc, fn, function() A.Soon(w) end)
        end
    end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f and f.HookScript then pcall(f.HookScript, f, "OnShow", function() A.Soon("Bags") end) end
    end
    local c = _G.ContainerFrameCombinedBags
    if c and c.HookScript then pcall(c.HookScript, c, "OnShow", function() A.Soon("Bags") end) end
    -- the gear of a dad came in: blue arrows may change
    OMQ:On("GEAR_UPDATED", function() if LP() then LP().ArrowReset() end; A.Soon("Bags", 0.5) end)
end)
