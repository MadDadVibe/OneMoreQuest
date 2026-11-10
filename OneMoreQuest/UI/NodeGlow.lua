-- One More Quest: ore and herb glow (decision 495)
-- The game's soft targeting picks one interactable object near me (the unit "softinteract") and can give it a
-- nameplate. When that object is an ore vein or a herb (read from its interact cursor: pick or flower) and I have
-- the profession, a light is hung on its nameplate. Three looks (options.nodeGlow): "glow" (a pulsing ring on the
-- ground), "sparkle" (stars rising), "beam" (a light column); "off" leaves the game alone.
-- Only one object at a time, the nearest within about 15 yards. Ore orange, herb green, gray when my skill is too
-- low. Only characters with Mining or Herbalism get the soft target settings changed; the old values are kept in
-- OMQDB.nodeGlowCVars and given back on "off" and at every logout. No chat line on its own.
-- /omq glow [glow|sparkle|beam|off] sets the look, /omq glow test shows it in the middle of the screen,
-- /omq glow probe prints the soft target settings and what the game says about the current target.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local N = {}
OMQ.NodeGlow = N

N.STYLES = { "glow", "sparkle", "beam", "off" }
N.LABELS = { "Glow", "Sparkle", "Beam", "Off" }
N.COLORS = { ore = { 1.00, 0.60, 0.18 }, herb = { 0.40, 1.00, 0.42 }, low = { 0.62, 0.62, 0.66 } }
N.RANGE = 15
N.SIZE = 120
N.OFFSET = -45
N.TICK = 0.15
N.TEST = 6

local SOFT = "softinteract"
local MEDIA = "Interface\\AddOns\\OneMoreQuest\\Media\\"
-- the profession's own finding spell tells that I gather: Find Herbs, Find Minerals
local FINDERS = { herb = { 2383, 8387 }, ore = { 2580, 8388 } }
N.CVARS = { "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetInteractArc", "SoftTargetInteractOnlyInRange",
    "SoftTargetInteractRangeIsHard", "SoftTargetNameplateInteract", "SoftTargetIconInteract",
    "SoftTargetIconGameObject", "nameplateGameObjectMaxDistance" }

local holder, probe, ticker
local layers = {}
local current = { plate = nil, kind = nil, low = false, test = nil }
local applied = false
local gateOpen
local pending

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok or secret(a) or secret(b) then return nil end
    return a, b
end
local function getCVar(name)
    return safe(C_CVar and C_CVar.GetCVar or GetCVar, name)
end
local function setCVar(name, value)
    if getCVar(name) == nil then return end
    pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, tostring(value))
end

function N.Style()
    local s = OMQ.db and OMQ.db.options and OMQ.db.options.nodeGlow or "glow"
    for _, k in ipairs(N.STYLES) do if k == s then return s end end
    return "glow"
end
function N.StyleIndex()
    local s = N.Style()
    for i, k in ipairs(N.STYLES) do if k == s then return i end end
    return 1
end

-- which gathering professions I have (finding spell learned with them)
function N.Knows(kind)
    if not IsPlayerSpell then return true end
    for _, id in ipairs(FINDERS[kind] or {}) do
        if safe(IsPlayerSpell, id) then return true end
    end
    return false
end
function N.Gatherer() return N.Knows("ore") or N.Knows("herb") end
function N.Wanted() return N.Style() ~= "off" and N.Gatherer() end

----------------------------------------------------------------------
-- the game's settings: taken over while wanted, given back on off and at logout
----------------------------------------------------------------------
local function store() OMQ.db.nodeGlowCVars = OMQ.db.nodeGlowCVars or {}; return OMQ.db.nodeGlowCVars end

local function setGate(open)
    if open == gateOpen then return end
    if InCombatLockdown() then pending = pending or "gate"; return end
    gateOpen = open
    local saved = store().values or {}
    setCVar("SoftTargetNameplateInteract", open and 1 or 0)
    setCVar("SoftTargetIconInteract", open and (saved.SoftTargetIconInteract or 1) or 0)
end

function N.Apply()
    if InCombatLockdown() then pending = "apply"; return end
    local st = store()
    -- given back at the last logout: what the client has now are the player's values, read them again
    if st.returned then st.values = nil; st.returned = nil end
    if not st.values then
        st.values = {}
        for _, name in ipairs(N.CVARS) do st.values[name] = getCVar(name) end
    end
    setCVar("SoftTargetInteract", 3)
    setCVar("SoftTargetInteractRange", N.RANGE)
    setCVar("SoftTargetInteractArc", 2)
    setCVar("SoftTargetInteractOnlyInRange", 0)
    setCVar("SoftTargetInteractRangeIsHard", 0)
    setCVar("SoftTargetIconGameObject", 1)
    local far = tonumber(st.values.nameplateGameObjectMaxDistance) or 0
    setCVar("nameplateGameObjectMaxDistance", math.max(far, N.RANGE + 5))
    applied, gateOpen = true, nil
    setGate(false)
end

local function giveBack(keep)
    local st = OMQ.db and OMQ.db.nodeGlowCVars
    if not st or not st.values then return end
    for name, v in pairs(st.values) do setCVar(name, v) end
    if keep then st.returned = true else st.values = nil end
    applied, gateOpen = false, nil
end

function N.Restore()
    if InCombatLockdown() then pending = "restore"; return end
    giveBack(false)
end

----------------------------------------------------------------------
-- what the soft target is: its interact cursor names it
----------------------------------------------------------------------
local function readName(s)
    if type(s) ~= "string" then return nil end
    s = s:lower()
    local low = s:find("unable", 1, true) ~= nil
    if s:find("gather", 1, true) or s:find("herb", 1, true) then return "herb", low end
    if s:find("mine", 1, true) then return "ore", low end
    return nil
end

local fileKinds
local function fileKind(id)
    if not fileKinds then
        fileKinds = {}
        if GetFileIDFromPath then
            for name, kind in pairs({ Mine = "ore", GatherHerbs = "herb" }) do
                for _, pre in ipairs({ "", "Unable" }) do
                    local fid = safe(GetFileIDFromPath, "Interface\\Cursor\\" .. pre .. name)
                    if fid then fileKinds[fid] = { kind, pre ~= "" } end
                end
            end
        end
    end
    local k = fileKinds[id]
    if k then return k[1], k[2] end
end

-- "ore" / "herb" / nil, and true when the game shows it grayed (skill too low)
function N.Classify(unit)
    if not SetUnitCursorTexture then return nil end
    if not probe then
        holder = holder or CreateFrame("Frame", nil, UIParent)
        probe = holder:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
    end
    if not safe(SetUnitCursorTexture, probe, unit or SOFT, nil, true) then return nil end
    local tex = safe(probe.GetTexture, probe)
    local atlas = probe.GetAtlas and safe(probe.GetAtlas, probe)
    local kind, low
    if type(tex) == "number" then kind, low = fileKind(tex) end
    if not kind then kind, low = readName(tex) end
    if not kind then kind, low = readName(atlas) end
    return kind, low or false
end

----------------------------------------------------------------------
-- the light: three looks drawn with the addon's own textures, tinted per kind
----------------------------------------------------------------------
local function tex(parent, file, blend)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(MEDIA .. file)
    t:SetBlendMode(blend or "ADD")
    return t
end

local function buildHolder()
    holder = holder or CreateFrame("Frame", nil, UIParent)
    holder:SetSize(N.SIZE, N.SIZE)
    holder:Hide()
    local s = N.SIZE
    -- glow: ground ring, a soft light over it and a ripple going out
    layers.glow = {
        base = tex(holder, "Glow_Soft.tga"), ring = tex(holder, "Glow_Ring.tga"),
        ripple = tex(holder, "Glow_Ring.tga"), core = tex(holder, "Glow_Soft.tga"),
    }
    -- sparkle: a faint ground light and eight stars that rise and fade
    layers.sparkle = { base = tex(holder, "Glow_Soft.tga"), stars = {} }
    for i = 1, 8 do
        layers.sparkle.stars[i] = { t = tex(holder, "Glow_Spark.tga"), age = (i - 1) / 8, x = 0 }
    end
    -- beam: a light column over a ground ring
    layers.beam = { base = tex(holder, "Glow_Soft.tga"), ring = tex(holder, "Glow_Ring.tga"),
        column = tex(holder, "Glow_Beam.tga"), inner = tex(holder, "Glow_Beam.tga") }
    for _, l in pairs(layers) do
        for _, t in pairs(l) do if type(t) == "table" and t.Hide then t:Hide() end end
    end
    for _, st in ipairs(layers.sparkle.stars) do st.t:Hide() end
    holder.clock = 0
    holder:SetScript("OnUpdate", function(_, dt) N.Animate(dt) end)
    return s
end

local function place(t, w, h, x, y, r, g, b, a)
    t:ClearAllPoints()
    t:SetPoint("CENTER", holder, "CENTER", x, y)
    t:SetSize(math.max(w, 0.01), math.max(h, 0.01))
    t:SetVertexColor(r, g, b, math.max(0, math.min(1, a)))
    t:Show()
end

local function hideAll()
    for _, l in pairs(layers) do
        for k, t in pairs(l) do if k ~= "stars" and t.Hide then t:Hide() end end
    end
    if layers.sparkle then for _, st in ipairs(layers.sparkle.stars) do st.t:Hide() end end
end

local FOOT = -0.12   -- the ground under the object, as a part of the size
local FLAT = 0.36    -- a circle on the ground seen from the usual camera angle

function N.Animate(dt)
    if not holder then return end
    holder.clock = (holder.clock or 0) + (dt or 0)
    local c = holder.clock
    local col = current.low and N.COLORS.low or N.COLORS[current.kind or "ore"] or N.COLORS.ore
    local r, g, b = col[1], col[2], col[3]
    local s, foot = N.SIZE, N.SIZE * FOOT
    local style = current.test or N.Style()
    local pulse = 0.5 + 0.5 * math.sin(c * 3)
    if style == "glow" then
        local l = layers.glow
        place(l.base, s * 1.1, s * 1.1 * FLAT, 0, foot, r, g, b, 0.35 + 0.2 * pulse)
        place(l.ring, s * (0.9 + 0.08 * pulse), s * (0.9 + 0.08 * pulse) * FLAT, 0, foot, r, g, b, 0.7 + 0.3 * pulse)
        local t = (c % 1.6) / 1.6
        place(l.ripple, s * (0.6 + 0.9 * t), s * (0.6 + 0.9 * t) * FLAT, 0, foot, r, g, b, 0.6 * (1 - t))
        place(l.core, s * 0.55, s * 0.55, 0, foot + s * 0.12, r, g, b, 0.25 + 0.25 * pulse)
    elseif style == "sparkle" then
        local l = layers.sparkle
        place(l.base, s * 0.9, s * 0.9 * FLAT, 0, foot, r, g, b, 0.3 + 0.15 * pulse)
        for i, st in ipairs(l.stars) do
            st.age = st.age + (dt or 0) / 1.4
            if st.age >= 1 or st.x == 0 then
                st.age = st.age % 1
                st.x = (math.random() - 0.5) * s * 0.6
                if st.x == 0 then st.x = 1 end
            end
            local a = math.sin(st.age * math.pi)
            local size = s * (0.12 + 0.12 * a) * (0.8 + 0.4 * ((i % 3) / 2))
            place(st.t, size, size, st.x * (1 - 0.3 * st.age), foot + s * 0.9 * st.age, r * 0.6 + 0.4, g * 0.6 + 0.4, b * 0.6 + 0.4, a)
            if st.t.SetRotation then st.t:SetRotation(st.age * 1.5 + i) end
        end
    elseif style == "beam" then
        local l = layers.beam
        local flicker = 0.85 + 0.15 * math.sin(c * 7.3) * math.sin(c * 2.1)
        place(l.base, s, s * FLAT, 0, foot, r, g, b, 0.45 + 0.2 * pulse)
        place(l.ring, s * 0.7, s * 0.7 * FLAT, 0, foot, r, g, b, 0.6 + 0.3 * pulse)
        local h = s * 2.6
        place(l.column, s * 0.42, h, 0, foot + h / 2, r, g, b, 0.75 * flicker)
        place(l.inner, s * 0.16, h * 0.95, 0, foot + h * 0.95 / 2, 1, 1, 1, 0.5 * flicker)
    end
end

local function show(anchor, kind, low)
    if not holder or not layers.glow then buildHolder() end
    if current.plate ~= anchor then
        pcall(holder.SetParent, holder, anchor)
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", anchor, "CENTER", 0, current.test and 0 or N.OFFSET)
        if holder.SetIgnoreParentAlpha then pcall(holder.SetIgnoreParentAlpha, holder, true) end
        local lvl = safe(anchor.GetFrameLevel, anchor)
        if type(lvl) == "number" and lvl > 0 then pcall(holder.SetFrameLevel, holder, lvl - 1) end
    end
    if current.style ~= (current.test or N.Style()) then hideAll() end
    current.plate, current.kind, current.low, current.style = anchor, kind, low, current.test or N.Style()
    holder:Show()
end

function N.Hide()
    current.plate, current.kind, current.style = nil, nil, nil
    if holder then hideAll(); holder:Hide(); pcall(holder.SetParent, holder, UIParent) end
end

function N.Shown() return holder ~= nil and holder:IsShown() and current.plate ~= nil end
function N.Current() return current.kind, current.low, current.style end

----------------------------------------------------------------------
-- looking at the soft target
----------------------------------------------------------------------
function N.Evaluate()
    if current.test then return end
    if not applied then N.Hide(); return end
    local isObj = safe(UnitIsGameObject, SOFT)
    local exists = isObj or safe(UnitExists, SOFT)
    local kind, low
    if exists then kind, low = N.Classify(SOFT) end
    if kind and not N.Knows(kind) then kind = nil end
    setGate(kind ~= nil)
    local plate = kind and C_NamePlate and safe(C_NamePlate.GetNamePlateForUnit, SOFT)
    if kind and plate then show(plate, kind, low) else N.Hide() end
end

local function startTicker()
    if ticker or not C_Timer then return end
    ticker = C_Timer.NewTicker(N.TICK, function() if applied then N.Evaluate() end end)
end

-- puts settings and light in line with the option and my professions
function N.Refresh()
    if N.Wanted() then
        if not applied then N.Apply() end
        startTicker()
        N.Evaluate()
    else
        if applied then N.Restore() end
        N.Hide()
    end
end

function N.SetStyle(i)
    local s = N.STYLES[i]
    if not s then return end
    OMQ.db.options.nodeGlow = s
    if current.style and current.style ~= s then hideAll() end
    N.Refresh()
end

-- a sample in the middle of the screen, N.TEST seconds, in the chosen look (or each look in turn)
function N.Test(kind)
    if not holder or not layers.glow then buildHolder() end
    local style = N.Style() == "off" and "glow" or N.Style()
    current.test = style
    current.plate = nil
    show(UIParent, kind or "herb", false)
    if C_Timer then
        C_Timer.After(N.TEST, function()
            if current.test == style then current.test = nil; N.Hide(); N.Evaluate() end
        end)
    end
    return style
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_REGEN_ENABLED", "PLAYER_SOFT_INTERACT_CHANGED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED", "SKILL_LINES_CHANGED" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event)
    if not OMQ.db then return end
    if event == "PLAYER_LOGOUT" then
        -- the client keeps the player's own values when the addon is switched off or removed
        if applied and not InCombatLockdown() then giveBack(true) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local p = pending; pending = nil
        if p == "restore" then N.Restore() elseif p == "apply" then N.Apply() end
        N.Refresh()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" or event == "SKILL_LINES_CHANGED" then
        N.Refresh()
    elseif applied then
        N.Evaluate()
    end
end)

OMQ:RegisterCommand("glow", function(arg)
    arg = (arg or ""):lower():match("^%s*(%S*)") or ""
    for i, s in ipairs(N.STYLES) do
        if arg == s then
            N.SetStyle(i)
            OMQ:Print("Ore and herb glow: " .. N.LABELS[i] .. (N.Gatherer() and "" or " (you have neither Mining nor Herbalism)"))
            OMQ:Fire("SETTINGS_CHANGED")
            return
        end
    end
    if arg == "test" then
        local s = N.Test()
        OMQ:Print("Ore and herb glow: sample of " .. s .. " for " .. N.TEST .. " seconds")
    elseif arg == "probe" then
        for _, name in ipairs(N.CVARS) do OMQ:Print(name .. " = " .. tostring(getCVar(name))) end
        local kind, low = N.Classify(SOFT)
        local plate = C_NamePlate and safe(C_NamePlate.GetNamePlateForUnit, SOFT)
        OMQ:Print(("style %s, mining %s, herbalism %s, active %s"):format(N.Style(), tostring(N.Knows("ore")),
            tostring(N.Knows("herb")), tostring(applied)))
        OMQ:Print(("soft target: object %s, kind %s, grayed %s, nameplate %s"):format(tostring(safe(UnitIsGameObject, SOFT)),
            tostring(kind), tostring(low), plate and "yes" or "no"))
    else
        OMQ:Print("/omq glow glow | sparkle | beam | off - the light on the nearest ore vein or herb (now: " .. N.Style() .. ")")
        OMQ:Print("/omq glow test - a sample in the middle of the screen; /omq glow probe - what the game says")
    end
end)
