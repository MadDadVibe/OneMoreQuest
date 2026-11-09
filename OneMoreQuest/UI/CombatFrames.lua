-- One More Quest: a second place for the player and target frame in a fight (decision 479)
-- The player frame (PlayerFrame) and the target frame (TargetFrame) of the game can stand at a place of their own
-- while I am in a fight. Out of the fight they stand where the game (Edit Mode) puts them.
-- Combat: both are protected frames; an addon may not move them while the combat lockdown is on. So the move
-- into the fight is done by the game itself: a state driver "[combat] fight; rest" on a secure handler frame
-- runs a secure snippet that anchors each frame to the handler at its fight place. The way back is plain Lua
-- at PLAYER_REGEN_ENABLED (the lockdown is over then): the points the frame had before the fight are set again.
-- Optional: out of a fight the player frame is see-through (alpha 0) while my life is full and my mana (if I
-- have mana) is above 80 %. Alpha is no protected change, so it may come back at any moment, also in a fight.
-- /omq frames setup shows two frames to drag (player and target in a fight), /omq frames off ends all of it.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local CF = {}
OMQ.CombatFrames = CF

CF.UNITS = { { key = "player", frame = "PlayerFrame", label = "Player frame in a fight" },
             { key = "target", frame = "TargetFrame", label = "Target frame in a fight" } }
CF.MANA = 0.8           -- the player frame stays visible while the mana is at or below this share
CF.WATCH = 2            -- seconds between two looks at the frames' own places out of a fight

local header            -- the secure handler with the state driver
local ghosts = {}       -- key -> the drag frame of the setup
local panel             -- the small setup window with the hide option and Done
local saved = {}        -- key -> the points of the frame out of a fight { {p, rel, rp, x, y}, ... }
local moved = {}        -- key -> true: the snippet may have moved this frame (a fight since the last way back)
local setupOn = false
CF._saved, CF._moved, CF._ghosts = saved, moved, ghosts

local function locked() return InCombatLockdown and InCombatLockdown() and true or false end
local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function db()
    OMQ.db.combatFrames = OMQ.db.combatFrames or {}
    return OMQ.db.combatFrames
end
local function frameOf(key)
    for _, u in ipairs(CF.UNITS) do if u.key == key then return _G[u.frame] end end
end
local function scaleOf(f)
    local s = f and f.GetEffectiveScale and f:GetEffectiveScale()
    if type(s) ~= "number" or s <= 0 or isSecret(s) then return 1 end
    return s
end

function CF.Active()
    local d = OMQ.db and OMQ.db.combatFrames
    return d ~= nil and (d.player ~= nil or d.target ~= nil)
end

----------------------------------------------------------------------
-- The place out of a fight (the game's own) and the way back
----------------------------------------------------------------------
-- the frame hangs at the handler: the snippet moved it, these points are not the game's
local function ours(f)
    if not (f and f.GetNumPoints and f.GetPoint) then return false end
    local n = f:GetNumPoints()
    for i = 1, (type(n) == "number" and n or 0) do
        local _, rel = f:GetPoint(i)
        if header and rel == header then return true end
    end
    return false
end

-- remembers where the game puts the frame (only when it is not at its fight place)
function CF.Capture()
    for _, u in ipairs(CF.UNITS) do
        local f = _G[u.frame]
        if f and f.GetNumPoints and not ours(f) and not moved[u.key] then
            local pts, n = {}, f:GetNumPoints()
            for i = 1, (type(n) == "number" and n or 0) do
                local p, rel, rp, x, y = f:GetPoint(i)
                if p then pts[#pts + 1] = { p, rel, rp, x, y } end
            end
            if #pts > 0 then saved[u.key] = pts end
        end
    end
end

-- after the fight: the points from before the fight again
function CF.Restore()
    if locked() then return end
    for _, u in ipairs(CF.UNITS) do
        local f, pts = _G[u.frame], saved[u.key]
        if f and pts and (moved[u.key] or ours(f)) then
            f:ClearAllPoints()
            for _, pt in ipairs(pts) do
                f:SetPoint(pt[1], pt[2] or UIParent, pt[3] or pt[1], pt[4] or 0, pt[5] or 0)
            end
        end
        moved[u.key] = nil
    end
end

----------------------------------------------------------------------
-- The fight place: the secure handler
----------------------------------------------------------------------
-- the snippet: on "fight" every frame with a place goes there; "rest" does nothing (Lua takes them back)
CF.SNIPPET = [[
    if newstate ~= "fight" then return end
    local f = self:GetFrameRef("player")
    local x, y = self:GetAttribute("player-x"), self:GetAttribute("player-y")
    if f and x and y then
        f:ClearAllPoints()
        f:SetPoint("CENTER", self, "BOTTOMLEFT", x, y)
    end
    f = self:GetFrameRef("target")
    x, y = self:GetAttribute("target-x"), self:GetAttribute("target-y")
    if f and x and y then
        f:ClearAllPoints()
        f:SetPoint("CENTER", self, "BOTTOMLEFT", x, y)
    end
]]

local function build()
    if header or locked() then return end
    header = CreateFrame("Frame", "OneMoreQuestCombatFrames", UIParent, "SecureHandlerStateTemplate")
    header:SetSize(1, 1)
    header:ClearAllPoints()
    header:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    header:SetAttribute("_onstate-omqfight", CF.SNIPPET)
    CF._header = header
end

-- the offsets of the fight place in the frame's own scale (SetPoint offsets are in the scale of the frame)
function CF.Offsets(key)
    local p = OMQ.db and OMQ.db.combatFrames and OMQ.db.combatFrames[key]
    local f = frameOf(key)
    if not (p and f) then return nil end
    local k = scaleOf(UIParent) / scaleOf(f)
    return p[1] * k, p[2] * k
end

-- the attributes of the handler, out of combat only
function CF.Apply()
    if locked() then return end
    if not CF.Active() then
        if header then
            if UnregisterStateDriver then UnregisterStateDriver(header, "omqfight") end
            for _, u in ipairs(CF.UNITS) do
                header:SetAttribute(u.key .. "-x", nil); header:SetAttribute(u.key .. "-y", nil)
            end
        end
        return
    end
    build()
    for _, u in ipairs(CF.UNITS) do
        local f = _G[u.frame]
        local x, y = CF.Offsets(u.key)
        if f and x then
            if header.SetFrameRef then header:SetFrameRef(u.key, f) end
            header:SetAttribute(u.key .. "-x", x); header:SetAttribute(u.key .. "-y", y)
        else
            header:SetAttribute(u.key .. "-x", nil); header:SetAttribute(u.key .. "-y", nil)
        end
    end
    if RegisterStateDriver then RegisterStateDriver(header, "omqfight", "[combat] fight; rest") end
end

----------------------------------------------------------------------
-- See-through player frame at full life
----------------------------------------------------------------------
function CF.HideOn()
    local d = OMQ.db and OMQ.db.combatFrames
    return d ~= nil and d.hideFull == true
end

-- full life and (no mana or more than 80 % mana); unreadable values count as "not full"
function CF.Full()
    if not (UnitHealth and UnitHealthMax) then return false end
    local hp, max = UnitHealth("player"), UnitHealthMax("player")
    if isSecret(hp) or isSecret(max) or type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then return false end
    if hp < max then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
    local mana = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
    local mp, mmax = UnitPower and UnitPower("player", mana), UnitPowerMax and UnitPowerMax("player", mana)
    if isSecret(mp) or isSecret(mmax) then return false end
    if type(mmax) == "number" and mmax > 0 then
        if type(mp) ~= "number" or mp / mmax <= CF.MANA then return false end
    end
    return true
end

local fight = false
function CF.Fade()
    local f = _G.PlayerFrame
    if not (f and f.SetAlpha) then return end
    local inFight = fight or locked() or (UnitAffectingCombat and UnitAffectingCombat("player") == true)
    local hide = CF.HideOn() and not inFight and not setupOn and CF.Full()
    f:SetAlpha(hide and 0 or 1)
    CF.hidden = hide
end

----------------------------------------------------------------------
-- Setup: two frames to drag
----------------------------------------------------------------------
local function ghost(u)
    local g = ghosts[u.key]
    if g then return g end
    g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("DIALOG")
    g:SetMovable(true)
    g:SetClampedToScreen(true)
    g:EnableMouse(true)
    g:RegisterForDrag("LeftButton")
    g:SetScript("OnDragStart", function(self) self:StartMoving() end)
    g:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    g.bg = g:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints()
    g.bg:SetColorTexture(0.85, 0.65, 0.2, 0.35)
    g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g.text:SetPoint("CENTER")
    g.text:SetText(u.label)
    g:Hide()
    ghosts[u.key] = g
    return g
end

-- the drag frame has the size of the game's frame; it starts at the saved fight place or below the frame
local function placeGhost(u, g, i)
    local f = _G[u.frame]
    local k = scaleOf(f) / scaleOf(UIParent)
    local w = (f and f.GetWidth and f:GetWidth()) or 232
    local h = (f and f.GetHeight and f:GetHeight()) or 100
    if type(w) ~= "number" or w <= 0 then w = 232 end
    if type(h) ~= "number" or h <= 0 then h = 100 end
    g:SetSize(w * k, h * k)
    g:ClearAllPoints()
    local p = db()[u.key]
    if p then
        g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        local cx, cy
        if f and f.GetCenter then cx, cy = f:GetCenter() end
        if type(cx) == "number" and type(cy) == "number" then
            g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * k, cy * k - h * k - 20)
        else
            g:SetPoint("CENTER", UIParent, "CENTER", (i - 1.5) * 300, -150)
        end
    end
end

local function buildPanel()
    if panel then return panel end
    panel = CreateFrame("Frame", "OneMoreQuestCombatFramesSetup", UIParent, "BackdropTemplate")
    panel:SetSize(300, 96)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
    panel:SetFrameStrata("DIALOG")
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints()
    panel.bg:SetColorTexture(0, 0, 0, 0.8)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOP", 0, -8)
    panel.title:SetText("Drag the two frames to their places in a fight")
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 10, -26)
    cb.label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText("Hide my frame out of a fight at full life and mana over 80%")
    cb:SetScript("OnClick", function(self) db().hideFull = self:GetChecked() and true or false end)
    panel.check = cb
    local done = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    done:SetSize(90, 22)
    done:SetPoint("BOTTOMRIGHT", -10, 8)
    done:SetText("Done")
    done:SetScript("OnClick", function() CF.Done() end)
    panel.done = done
    local cancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22)
    cancel:SetPoint("RIGHT", done, "LEFT", -6, 0)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() CF.Cancel() end)
    panel.cancel = cancel
    panel:Hide()
    CF._panel = panel
    return panel
end

function CF.Setup()
    if locked() then OMQ:Print("not in combat, please"); return false end
    setupOn = true
    for i, u in ipairs(CF.UNITS) do
        local g = ghost(u)
        placeGhost(u, g, i)
        g:Show()
    end
    local p = buildPanel()
    if p.check.SetChecked then p.check:SetChecked(CF.HideOn()) end
    p:Show()
    CF.Fade()
    return true
end

local function closeSetup()
    setupOn = false
    for _, g in pairs(ghosts) do g:Hide() end
    if panel then panel:Hide() end
    CF.Fade()
end

-- Done: the centers of the drag frames are the fight places (in UIParent's scale)
function CF.Done()
    if locked() then OMQ:Print("not in combat, please"); return false end
    local d = db()
    for _, u in ipairs(CF.UNITS) do
        local g = ghosts[u.key]
        local x, y
        if g and g.GetCenter then x, y = g:GetCenter() end
        if type(x) == "number" and type(y) == "number" then d[u.key] = { x, y } end
    end
    closeSetup()
    CF.Apply()
    OMQ:Print("frames: player and target frame have their places in a fight")
    return true
end

function CF.Cancel() closeSetup() end

function CF.Off()
    if locked() then OMQ:Print("not in combat, please"); return false end
    CF.Restore()
    OMQ.db.combatFrames = nil
    closeSetup()
    CF.Apply()
    CF.Fade()
    return true
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_UNGHOST",
    "EDIT_MODE_LAYOUTS_UPDATED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if unit and type(unit) == "string" and event:find("^UNIT_") and unit ~= "player" then return end
    local ok, err = pcall(function()
        if event == "PLAYER_REGEN_DISABLED" then
            -- before the lockdown: the game's places are kept, the frame comes back, the fight places are set
            fight = true
            CF.Capture()
            CF.Apply()
            if CF.Active() then for _, u in ipairs(CF.UNITS) do if db()[u.key] then moved[u.key] = true end end end
            CF.Fade()
        elseif event == "PLAYER_REGEN_ENABLED" then
            fight = false
            CF.Restore()
            CF.Fade()
        else
            if event == "EDIT_MODE_LAYOUTS_UPDATED" and not locked() then CF.Capture() end
            CF.Fade()
        end
    end)
    if not ok then OMQ:Error("frames " .. event, err) end
end)

-- the game's places change in Edit Mode; out of a fight they are looked at every few seconds
local acc = 0
ev:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < CF.WATCH then return end
    acc = 0
    if locked() or fight then return end
    local ok, err = pcall(function() CF.Capture(); CF.Fade() end)
    if not ok then OMQ:Error("frames watch", err) end
end)

OMQ:On("READY", function()
    CF.Capture()
    CF.Apply()
    CF.Fade()
end)

-- /omq frames: status | setup | done | hide on|off | off
OMQ:RegisterCommand("frames", function(arg)
    arg = (arg or ""):lower()
    if arg == "setup" then CF.Setup(); return end
    if arg == "done" then CF.Done(); return end
    if arg == "off" then
        if CF.Off() then OMQ:Print("frames: back to the game's places, nothing hidden") end
        return
    end
    if arg == "hide on" or arg == "hide off" then
        db().hideFull = arg == "hide on"
        CF.Fade()
        OMQ:Print("frames: hide at full life " .. (CF.HideOn() and "on" or "off"))
        return
    end
    local d = OMQ.db.combatFrames or {}
    local function pl(p) return p and string.format("%d, %d", p[1], p[2]) or "none" end
    OMQ:Print(string.format("frames: fight place player %s, target %s; hide at full life %s%s",
        pl(d.player), pl(d.target), CF.HideOn() and "on" or "off", CF.hidden and " (hidden now)" or ""))
    print("  /omq frames setup | hide on | hide off | off")
end, "player and target frame at another place in a fight, hidden at full life")
