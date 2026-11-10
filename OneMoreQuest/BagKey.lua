-- One More Quest: the bag key opens the reagent bag too (decision 515)
-- The default key B is bound to "Toggle Backpack": with combined bags it opens the backpack and the four
-- bags, but not the reagent bag. Shift-B ("Open All Bags", ToggleAllBags) opens the reagent bag as well.
-- Every key bound to Toggle Backpack gets an override binding to OPENALLBAGS, so B does what Shift-B does.
-- An override binding runs Blizzard's own binding code: no OMQ code runs when the key is pressed, nothing
-- in the bag frames is touched by the addon (no taint). Overrides are not saved: switched off, B is the
-- normal key again at once. Bindings cannot change in combat; the change waits until the fight is over.
-- Switch: /omq qol bags or the options window.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local B = {}
OMQ.BagKey = B

local owner = CreateFrame("Frame", "OneMoreQuestBagKeyOwner")
local applied = {}          -- keys that carry our override right now
local busy = false          -- our own UPDATE_BINDINGS while we set them
B.pending = false

function B.Enabled()
    local o = OMQ.db and OMQ.db.options and OMQ.db.options.qol
    return not o or o.reagentBag ~= false
end

-- the keys of Toggle Backpack in the normal bindings (not our overrides)
local function backpackKeys()
    local out = {}
    if not GetBindingKey then return out end
    local keys = { GetBindingKey("TOGGLEBACKPACK") }
    for _, k in ipairs(keys) do
        if type(k) == "string" and k ~= "" then out[#out + 1] = k end
    end
    -- a key we already override stays as long as its action is not something else: should the game ever
    -- report the override instead of the normal binding, the key must not flip off and on again
    local seen = {}
    for _, k in ipairs(out) do seen[k] = true end
    for _, k in ipairs(applied) do
        local action = GetBindingAction and GetBindingAction(k)
        if not seen[k] and (action == "TOGGLEBACKPACK" or action == "OPENALLBAGS") then
            out[#out + 1] = k
            seen[k] = true
        end
    end
    table.sort(out)
    return out
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- (Re)applies the overrides; returns false when it has to wait for the end of the fight
function B.Apply()
    if InCombatLockdown and InCombatLockdown() then
        B.pending = true
        return false
    end
    B.pending = false
    local want = B.Enabled() and backpackKeys() or {}
    if same(want, applied) then return true end
    busy = true
    if ClearOverrideBindings then ClearOverrideBindings(owner) end
    applied = {}
    if SetOverrideBinding then
        for _, k in ipairs(want) do
            SetOverrideBinding(owner, false, k, "OPENALLBAGS")
            applied[#applied + 1] = k
        end
    end
    busy = false
    return true
end

function B.Applied() return applied end

owner:RegisterEvent("PLAYER_LOGIN")
owner:RegisterEvent("UPDATE_BINDINGS")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_BINDINGS" and busy then return end
    if event == "PLAYER_REGEN_ENABLED" and not B.pending then return end
    local ok, err = pcall(B.Apply)
    if not ok then OMQ:Error("bagkey", err) end
end)
