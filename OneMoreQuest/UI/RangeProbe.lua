local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local function secret(value)
    return issecretvalue and issecretvalue(value)
end

local function display(value)
    if secret(value) then return "secret" end
    if value == nil then return "nil" end
    return tostring(value)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, value = pcall(fn, ...)
    if not ok then return "error" end
    return display(value)
end

local function spellDetails(id)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and not secret(info) then
            return display(info.name), display(info.minRange), display(info.maxRange)
        end
    end
    if type(GetSpellInfo) == "function" then
        local result = { pcall(GetSpellInfo, id) }
        if result[1] then return display(result[2]), display(result[6]), display(result[7]) end
    end
    return "unknown", "unknown", "unknown"
end

local function actionSpell(slot)
    if type(GetActionInfo) ~= "function" then return nil end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or secret(kind) or secret(id) then return nil end
    if kind == "macro" and id and type(GetMacroSpell) == "function" then
        local macroOk, spellId = pcall(GetMacroSpell, id)
        if macroOk and not secret(spellId) and spellId then kind, id = "spell", spellId end
    end
    if kind == "spell" and id then return id end
end

local function probe()
    local _, class = UnitClass and UnitClass("player")
    local target = "none"
    if UnitExists and UnitExists("target") then target = display(UnitName and UnitName("target")) end
    OMQ:Print("range probe: class=" .. display(class) .. ", target=" .. target)

    local actionRange = IsActionInRange or (C_ActionBar and C_ActionBar.IsActionInRange)
    local actionHasRange = ActionHasRange or (C_ActionBar and C_ActionBar.HasRangeRequirements)
    local count = 0
    for slot = 1, 120 do
        local id = actionSpell(slot)
        if id then
            local name, minRange, maxRange = spellDetails(id)
            local action = call(actionRange, slot)
            local hasRange = call(actionHasRange, slot)
            local modern = call(C_Spell and C_Spell.IsSpellInRange, id, "target")
            local legacy = call(IsSpellInRange, name, "target")
            count = count + 1
            if count <= 30 then
                print(string.format("  slot %d %s: min=%s max=%s action=%s hasRange=%s C_Spell=%s legacy=%s",
                    slot, name, minRange, maxRange, action, hasRange, modern, legacy))
            end
        end
    end
    if count == 0 then OMQ:Print("No spell actions found in slots 1-120.") end
    if count > 30 then OMQ:Print((count - 30) .. " more spell actions omitted.") end
end

OMQ:RegisterCommand("range", function(arg)
    if (arg or ""):lower():match("^%s*probe%s*$") then
        probe()
    else
        OMQ:Print("Use /omq range probe with a target and action-bar spells.")
    end
end, "probe action bar range APIs")