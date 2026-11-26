local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

-- Range tint on the action bars and distance bar to the target (decision 718, taken over from PR #9 by PatrickMotz).
-- Both are off by default. The buttons are read once into a cache when the bars change (events), the
-- 0.2 s check only runs while an option is on and a target exists or move mode is on. The red overlay is
-- our own texture on the button, made only out of combat; no field or method of Blizzard's buttons is written.
local R = {}
OMQ.Range = R

local BUTTON_PREFIXES = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button",
}
local TRACK_WIDTH = 204
local TRACK_HEIGHT = 8
local GRADIENT_STEPS = 12
local DEFAULT_SCALE = 40
local MAX_SCALE = 60
local MELEE_RANGE = 5
local COLORS = {
    red = { 0.88, 0.22, 0.19 },
    green = { 0.25, 0.70, 0.42 },
    amber = { 0.94, 0.70, 0.20 },
    neutral = { 0.38, 0.42, 0.45 },
    text = { 0.84, 0.87, 0.89 },
}

local rangeLib = LibStub and LibStub("LibRangeCheck-3.0", true)
local actionRangeFn = IsActionInRange or (C_ActionBar and C_ActionBar.IsActionInRange)
local actionHasRangeFn = ActionHasRange or (C_ActionBar and C_ActionBar.HasRangeRequirements)
local buttons, known, overlays = {}, {}, {}

local function secret(value)
    if not issecretvalue then return false end
    local ok, result = pcall(issecretvalue, value)
    return ok and result
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or secret(value) then return nil end
    return value
end

local function actionSlot(button)
    local slot = rawget(button, "action")
    if secret(slot) or type(slot) ~= "number" or slot <= 0 then return nil end
    return slot
end

local function actionSpell(slot)
    if type(GetActionInfo) ~= "function" then return nil end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or secret(kind) or secret(id) then return nil end
    if kind == "macro" and id and type(GetMacroSpell) == "function" then
        local macroOk, macroSpell = pcall(GetMacroSpell, id)
        if macroOk and not secret(macroSpell) and macroSpell then return macroSpell end
        return nil
    end
    if kind == "spell" then return id end
end

local function spellDetails(id)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = safe(C_Spell.GetSpellInfo, id)
        if type(info) == "table" then
            local ok, minRange, maxRange = pcall(function() return info.minRange, info.maxRange end)
            if ok then
                if secret(minRange) or type(minRange) ~= "number" then minRange = 0 end
                if secret(maxRange) or type(maxRange) ~= "number" then maxRange = nil end
                return minRange, maxRange
            end
        end
    end
    if type(GetSpellInfo) == "function" then
        local result = { pcall(GetSpellInfo, id) }
        if result[1] then
            local minRange, maxRange = result[6], result[7]
            if secret(minRange) or type(minRange) ~= "number" then minRange = 0 end
            if secret(maxRange) or type(maxRange) ~= "number" then maxRange = nil end
            return minRange, maxRange
        end
    end
end

local function needsRange(slot)
    if not actionHasRangeFn then return true end
    local hasRange = safe(actionHasRangeFn, slot)
    if hasRange == nil then return true end
    return hasRange == true or hasRange == 1
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

local function addButton(button)
    if type(button) ~= "table" or known[button] then return end
    if inCombat() then return end       -- the overlay is made after the fight (PLAYER_REGEN_ENABLED)
    known[button] = true
    buttons[#buttons + 1] = button

    local icon = rawget(button, "icon")
    if secret(icon) or type(icon) ~= "table" then icon = nil end
    if not icon then
        local name = safe(button.GetName, button)
        if type(name) == "string" then icon = _G[name .. "Icon"] end
    end
    if icon and type(button.CreateTexture) == "function" then
        local ok, overlay = pcall(button.CreateTexture, button, nil, "OVERLAY")
        if ok and overlay then
            overlay:SetAllPoints(icon)
            overlay:SetColorTexture(0.90, 0.10, 0.08, 0.34)
            overlay:Hide()
            overlays[button] = overlay
        end
    end
end

local function scanButtons()
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for index = 1, 12 do addButton(_G[prefix .. index]) end
    end
end

local function clearButtons()
    for _, button in ipairs(buttons) do
        local overlay = overlays[button]
        if overlay then overlay:Hide() end
    end
end

-- cache: per button its slot and whether it is a spell; rebuilt when the bars change
local cache, best = {}, { min = nil, max = nil }
local dirty = true

local function rebuild()
    dirty = false
    scanButtons()
    local bestMin, bestMax
    for i = 1, #buttons do
        local button = buttons[i]
        local entry = cache[i] or {}
        cache[i] = entry
        entry.button, entry.overlay = button, overlays[button]
        local slot = actionSlot(button)
        local id = slot and actionSpell(slot)
        entry.slot = id and slot or nil
        if id and safe(button.IsVisible, button) and needsRange(slot) then
            local minRange, maxRange = spellDetails(id)
            if maxRange then
                if maxRange <= 0 then minRange, maxRange = 0, MELEE_RANGE end
                minRange = minRange or 0
                if not bestMax or maxRange > bestMax or (maxRange == bestMax and minRange < bestMin) then
                    bestMin, bestMax = minRange, maxRange
                end
            end
        end
    end
    for i = #buttons + 1, #cache do cache[i] = nil end
    best.min, best.max = bestMin, bestMax
end

local function updateButtons()
    if not OMQ.db or OMQ.db.options.rangeButtons ~= true or not safe(UnitExists, "target") then
        clearButtons()
        return
    end
    for i = 1, #cache do
        local entry = cache[i]
        local overlay = entry.overlay
        if overlay then
            local red = false
            if entry.slot and actionRangeFn and entry.button:IsVisible() then
                local ok, inRange = pcall(actionRangeFn, entry.slot)
                red = ok and not secret(inRange) and (inRange == false or inRange == 0)
            end
            if red then overlay:Show() else overlay:Hide() end
        end
    end
end

local function actionBarRange()
    return best.min, best.max
end

function R.EvaluateBand(low, high, minRange, maxRange)
    if secret(low) or secret(high) or secret(minRange) or secret(maxRange)
        or type(low) ~= "number" or type(minRange) ~= "number" or type(maxRange) ~= "number" then
        return "unknown"
    end
    local upper = type(high) == "number" and high or low + 5
    if upper < minRange then return "too-close" end
    if low > maxRange then return "too-far" end
    if low >= minRange and upper <= maxRange then return "in-range" end
    return "edge"
end

local meter
local function setSegment(texture, left, right, color)
    texture:ClearAllPoints()
    if right <= left then
        texture:Hide()
        return
    end
    texture:SetPoint("BOTTOMLEFT", meter.track, "BOTTOMLEFT", left * TRACK_WIDTH, 0)
    texture:SetSize((right - left) * TRACK_WIDTH, TRACK_HEIGHT)
    if color then texture:SetColorTexture(color[1], color[2], color[3], 1) end
    texture:Show()
end

local function createMeter()
    meter = CreateFrame("Frame", "OneMoreQuestRangeMeter", UIParent)
    meter:SetSize(216, 32)
    meter:SetFrameStrata("HIGH")
    meter:SetClampedToScreen(true)
    meter:SetMovable(true)
    meter:EnableMouse(false)
    meter:RegisterForDrag("LeftButton")

    local background = meter:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(meter)
    background:SetColorTexture(0.055, 0.065, 0.075, 0.92)

    meter.label = meter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    meter.label:SetPoint("TOPLEFT", meter, "TOPLEFT", 6, -4)
    meter.label:SetPoint("TOPRIGHT", meter, "TOPRIGHT", -6, -4)
    meter.label:SetJustifyH("LEFT")

    meter.track = meter:CreateTexture(nil, "ARTWORK")
    meter.track:SetPoint("BOTTOMLEFT", meter, "BOTTOMLEFT", 6, 6)
    meter.track:SetSize(TRACK_WIDTH, TRACK_HEIGHT)
    meter.track:SetColorTexture(0.12, 0.13, 0.14, 1)

    meter.near = meter:CreateTexture(nil, "ARTWORK")
    meter.far = meter:CreateTexture(nil, "ARTWORK")
    meter.neutral = meter:CreateTexture(nil, "ARTWORK")
    meter.gradient = {}
    for index = 1, GRADIENT_STEPS do
        meter.gradient[index] = meter:CreateTexture(nil, "ARTWORK")
    end

    meter.marker = meter:CreateTexture(nil, "OVERLAY")
    meter.marker:SetSize(2, 12)
    meter.marker:SetColorTexture(0.98, 0.98, 0.94, 1)
    meter.marker:Hide()

    meter:SetScript("OnDragStart", function(self)
        if OMQ.Arrow and OMQ.Arrow.IsMoveMode and OMQ.Arrow:IsMoveMode() then self:StartMoving() end
    end)
    meter:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not (OMQ.db and self.GetCenter) then return end
        local x, y = self:GetCenter()
        local centerX, centerY = UIParent:GetCenter()
        if type(x) == "number" and type(y) == "number" and centerX and centerY then
            OMQ.db.options.rangePos = { x = x - centerX, y = y - centerY }
        end
    end)
    meter:Hide()
end

local function placeMeter()
    if not meter then return end
    meter:ClearAllPoints()
    local position = OMQ.db and OMQ.db.options.rangePos
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number" then
        meter:SetPoint("CENTER", UIParent, "CENTER", position.x, position.y)
    else
        meter:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

local function updateTrack(minRange, maxRange)
    if not maxRange then
        meter.near:Hide()
        meter.far:Hide()
        for _, texture in ipairs(meter.gradient) do texture:Hide() end
        setSegment(meter.neutral, 0, 1, COLORS.neutral)
        return DEFAULT_SCALE
    end

    meter.neutral:Hide()
    local scale = math.min(MAX_SCALE, math.max(DEFAULT_SCALE, maxRange + 8))
    local start = math.max(0, math.min(1, (minRange or 0) / scale))
    local finish = math.max(start, math.min(1, maxRange / scale))
    setSegment(meter.near, 0, start, COLORS.red)
    setSegment(meter.far, finish, 1, COLORS.red)

    for index, texture in ipairs(meter.gradient) do
        local left = start + (finish - start) * (index - 1) / GRADIENT_STEPS
        local right = start + (finish - start) * index / GRADIENT_STEPS
        local blend = (index - 1) / math.max(1, GRADIENT_STEPS - 1)
        local color = {
            COLORS.green[1] + (COLORS.amber[1] - COLORS.green[1]) * blend,
            COLORS.green[2] + (COLORS.amber[2] - COLORS.green[2]) * blend,
            COLORS.green[3] + (COLORS.amber[3] - COLORS.green[3]) * blend,
        }
        setSegment(texture, left, right, color)
    end
    return scale
end

local function distanceBand()
    if not rangeLib or not safe(UnitExists, "target") then return nil end
    local ok, low, high = pcall(rangeLib.GetRange, rangeLib, "target")
    if not ok or secret(low) or type(low) ~= "number" then return nil end
    if secret(high) or type(high) ~= "number" or high < low then high = nil end
    return low, high
end

local function distanceText(low, high)
    local first = math.max(0, math.floor(low))
    if not high then return first .. "+ yd" end
    local last = math.max(first, math.ceil(high))
    if first == last then return first .. " yd" end
    return first .. "-" .. last .. " yd"
end

local function moveMode()
    return OMQ.Arrow and OMQ.Arrow.IsMoveMode and OMQ.Arrow:IsMoveMode() or false
end

local function setMarker(distance, scale)
    local fraction = math.max(0, math.min(1, distance / scale))
    local x = fraction * TRACK_WIDTH - 1
    meter.marker:ClearAllPoints()
    meter.marker:SetPoint("TOPLEFT", meter.track, "TOPLEFT", x, 2)
    meter.marker:SetPoint("BOTTOMLEFT", meter.track, "BOTTOMLEFT", x, -2)
    meter.marker:Show()
end

local STATUS = {
    ["too-close"] = { "Too close", COLORS.red },
    ["too-far"] = { "Too far", COLORS.red },
    ["in-range"] = { "In range", COLORS.green },
    edge = { "At range edge", COLORS.amber },
}

local function updateDisplay()
    if not meter then return end
    if not OMQ.db or OMQ.db.options.rangeDisplay ~= true then
        meter:Hide()
        meter:EnableMouse(false)
        return
    end

    local moving = moveMode()
    meter:EnableMouse(moving)
    local target = safe(UnitExists, "target")
    if not target and not moving then
        meter:Hide()
        return
    end

    local minRange, maxRange = actionBarRange()
    local scale = updateTrack(minRange, maxRange)
    local low, high = distanceBand()
    if low then
        local distance = high and (low + high) / 2 or low + 5
        setMarker(distance, scale)
        local text = distanceText(low, high)
        local status, color
        if maxRange then
            local key = R.EvaluateBand(low, high, minRange or 0, maxRange)
            local entry = STATUS[key]
            status, color = entry[1], entry[2]
        else
            status, color = "Distance only", COLORS.text
        end
        meter.label:SetText(moving and ("Drag to move - " .. text .. " - " .. status) or (text .. " - " .. status))
        meter.label:SetTextColor(color[1], color[2], color[3])
    else
        meter.marker:Hide()
        meter.label:SetText(moving and "Distance to target - drag to move" or "Distance unavailable")
        meter.label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
    end
    meter:Show()
end

local function wanted()
    if not OMQ.db then return false end
    local o = OMQ.db.options
    if o.rangeButtons ~= true and o.rangeDisplay ~= true then return false end
    return safe(UnitExists, "target") == true or (o.rangeDisplay == true and moveMode())
end

createMeter()
local driver = CreateFrame("Frame")
local elapsed = 0
local function tick()
    if dirty then rebuild() end
    updateButtons()
    updateDisplay()
end
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.2 then return end
    elapsed = 0
    tick()
end)
driver:Hide()

-- start or stop the check: on target change, move mode, option change, bar change
function R.Wake()
    if wanted() then
        if not driver:IsShown() then elapsed = 0; driver:Show() end
        tick()
    else
        driver:Hide()
        clearButtons()
        if meter then meter:Hide(); meter:EnableMouse(false) end
    end
end

function R.SetButtonsEnabled()
    dirty = true
    R.Wake()
end

function R.SetDisplayEnabled()
    placeMeter()
    R.Wake()
end

function R.Refresh()
    placeMeter()
    dirty = true
    R.Wake()
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "UPDATE_MACROS",
    "LEARNED_SPELL_IN_TAB" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_TARGET_CHANGED" then dirty = true end
    R.Wake()
end)

OMQ:On("MOVE_MODE", function() R.Wake() end)
OMQ:On("DB_READY", function() R.Refresh() end)
