-- One More Quest: low life call to the healer (decision 423)
-- A dad whose screen shows the game's low life flash (LowHealthFrame) tells the group ("LW" message: guid,
-- name, 1 = low, 0 = over; repeated every few seconds while it lasts). A dad marked as healer (preferred role
-- Healer in the options, or the healer role in the group) gets a red card "Low Life warning <Name> - Left
-- click for emergency heal" and a warning sound, also in a fight. A left click targets that dad and casts the
-- emergency heal of the Shift-click heals (ClickHeals.lua, the Shift + left click spell) on him.
-- Combat: a button that casts a spell must be a secure button, and the game forbids an addon to show, hide,
-- move or change a secure button while the combat lockdown is on. So every party place (party1 to party4)
-- has its own secure button in a fixed row (row N = partyN), holding "/target partyN" and the heal. At the
-- start of a fight (PLAYER_REGEN_DISABLED, before the lockdown) the rows of the dads in the group are shown,
-- fully transparent. What the healer sees is a plain frame (the card), which may come and go in combat. Over
-- every row without a call lies a plain "shield" frame that takes the clicks, so a click there never heals
-- by accident. Out of combat only the rows with a call are shown, nothing else catches the mouse.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local H = {}
OMQ.HealCall = H

H.ROWS = 4
H.SAMPLE = 0.2          -- seconds between two looks at the low life flash
H.REPEAT = 3            -- while low, the call is sent again this often
H.EXPIRE = 8            -- a call without news for this long is over
H.SOUND_GAP = 2         -- the warning sound plays at most this often per dad
H.SOUND = { kit = "RAID_WARNING", id = 8959 }
local RED = { 0.95, 0.25, 0.22 }
local GAP = 6
local SCALE = 1.2

local calls = {}        -- row -> { guid, name, at (last news), since }
local buttons, skins, shields = {}, {}, {}
local holder, mover
local armed = {}        -- row -> true: the secure button is shown (for the fight or for a call)
local fight = {}        -- row -> true: armed at the start of the fight (until it ends)
local moveMode = false
local lastSound = {}     -- guid -> time of the last warning sound for that dad
local setup              -- defined at the end (wiring)
H._calls, H._armed = calls, armed

local function locked() return InCombatLockdown and InCombatLockdown() and true or false end
local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function enabled() return OMQ.db and OMQ.db.options and OMQ.db.options.healCall ~= false end
local function now() return GetTime() end

----------------------------------------------------------------------
-- Who is a healer, which heal
----------------------------------------------------------------------
-- the emergency heal: the spell of the Shift + left click (best known spell and rank of the class)
function H.Spell()
    local CH = OMQ.ClickHeals
    local id = CH and CH.Wanted and CH.Wanted("LeftButton")
    if not id then return nil end
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and (GetSpellInfo(id)))
    return name, id
end

-- marked as healer: the preferred role Healer (options), or the healer role in the group
function H.IsHealer()
    local o = OMQ.db and OMQ.db.options
    if o and o.role == "heal" then return true end
    if UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, "player")
        if ok and not isSecret(r) and r == "HEALER" then return true end
    end
    return false
end

function H.Active() return enabled() and H.IsHealer() and H.Spell() ~= nil end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------
local CARD_W = (OMQ.Alerts and OMQ.Alerts.CARD_W) or 330
local CARD_H = (OMQ.Alerts and OMQ.Alerts.CARD_H) or 50

local function rowY(i) return -((i - 1) * (CARD_H + GAP)) end

local function savePosition()
    local p, _, rp, x, y = holder:GetPoint()
    OMQ.db.healCallPoint = { p or "TOPLEFT", rp or "TOPLEFT", x or 0, y or 0 }
end
local function applyPosition()
    if locked() then return end
    -- default: right of the party frames on the left side of the screen (row N next to party member N)
    local p = (OMQ.db and OMQ.db.healCallPoint) or { "TOPLEFT", "TOPLEFT", 190, -200 }
    holder:ClearAllPoints()
    holder:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end
H.ApplyPosition = applyPosition

function H.Macro(i, spell)
    local unit = "party" .. i
    return "/target " .. unit .. "\n/cast [@" .. unit .. "] " .. tostring(spell)
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "OneMoreQuestHealCall", UIParent)
    holder:SetSize(CARD_W, H.ROWS * (CARD_H + GAP))
    holder:SetFrameStrata("HIGH")
    holder:SetScale(SCALE)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    applyPosition()
    for i = 1, H.ROWS do
        local b = CreateFrame("Button", "OneMoreQuestHealCall" .. i, holder, "SecureActionButtonTemplate")
        b:SetSize(CARD_W, CARD_H)
        b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, rowY(i))
        -- the secure template fires on mouse down or up depending on the game setting (ActionButtonUseKeyDown)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type1", "macro")
        b.row = i
        b:SetScript("PostClick", function(self, button, down)
            if down then return end
            if button == "RightButton" then H.Dismiss(self.row) end
        end)
        b:SetScript("OnEnter", function(self)
            local c = calls[self.row]
            if not (c and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Low Life warning " .. tostring(c.name))
            GameTooltip:AddLine("Left click: target him and cast " .. tostring(H.Spell() or "your emergency heal") .. ".", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Right click: close the card.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:Hide()
        buttons[i] = b
        -- the card the healer sees: a plain frame over the button, free to come and go in combat
        local s
        if OMQ.Alerts and OMQ.Alerts.MakeSkin then
            s = OMQ.Alerts.MakeSkin(UIParent)
        else
            s = CreateFrame("Frame", nil, UIParent)
        end
        s:SetFrameStrata("HIGH")
        s:SetScale(SCALE)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        if s.EnableMouse then s:EnableMouse(false) end
        s:Hide()
        skins[i] = s
        -- the shield: takes the clicks of a row without a call while its secure button waits for the fight
        local sh = CreateFrame("Frame", nil, UIParent)
        sh:SetFrameStrata("DIALOG")
        sh:SetScale(SCALE)
        sh:SetSize(CARD_W, CARD_H)
        sh:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        sh:EnableMouse(true)
        sh:Hide()
        shields[i] = sh
    end
    -- move mode: a plain frame over all rows drags the holder (out of combat)
    mover = CreateFrame("Frame", nil, UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetScale(SCALE)
    mover:SetSize(CARD_W, H.ROWS * (CARD_H + GAP))
    mover:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function() if not locked() then holder:StartMoving() end end)
    mover:SetScript("OnDragStop", function() holder:StopMovingOrSizing(); savePosition() end)
    mover:Hide()
    H._buttons, H._skins, H._shields, H._holder = buttons, skins, shields, holder
end

-- the secure attributes: only out of combat
local function setAttributes()
    if locked() or not holder then return end
    local spell = H.Spell()
    for i = 1, H.ROWS do
        buttons[i]:SetAttribute("macrotext1", spell and H.Macro(i, spell) or "")
    end
end
H.SetAttributes = setAttributes

local function isDad(i)
    local g = UnitGUID and UnitGUID("party" .. i)
    if not g or isSecret(g) then return false end
    local u = OMQ.users and OMQ.users[g]
    return u ~= nil
end

----------------------------------------------------------------------
-- Showing
----------------------------------------------------------------------
local function fillSkin(i, c)
    local s = skins[i]
    local _, id = H.Spell()
    local icon = id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    local data = { title = "Low Life warning " .. tostring(c and c.name or ("Dad " .. i)),
                   sub = armed[i] and "Left click for emergency heal" or "Shift + left click his party frame to heal",
                   tag = "LOW LIFE", color = RED,
                   icon = icon or "Interface\\Icons\\Spell_Holy_FlashHeal" }
    if OMQ.Alerts and OMQ.Alerts.FillSkin and s.tag then OMQ.Alerts.FillSkin(s, data) end
    s.callTitle, s.callSub = data.title, data.sub
end

-- brings every frame in line with the calls; secure parts only when allowed
function H.Render()
    if not holder then return end
    local lock = locked()
    for i = 1, H.ROWS do
        local c = calls[i]
        local want = moveMode or (c ~= nil)
        if not lock then
            -- out of combat: a secure button only where a call is (or in the move mode)
            if (want and not moveMode) or (fight[i] and not moveMode) then buttons[i]:Show(); armed[i] = true
            else buttons[i]:Hide(); armed[i] = nil end
        end
        if want then
            fillSkin(i, c)
            skins[i]:Show()
            skins[i]:SetAlpha(armed[i] and 1 or (moveMode and 1 or 0.75))
        else
            skins[i]:Hide()
        end
        -- a shown secure button without a call (armed for the fight) gets the shield
        if armed[i] and not c then shields[i]:Show() else shields[i]:Hide() end
    end
    if mover then if moveMode and not lock then mover:Show() else mover:Hide() end end
end

-- the fight starts (before the lockdown): the rows of the dads in the group are shown, transparent and shielded
function H.Arm()
    if not holder or locked() then return end
    setAttributes()
    local active = H.Active() and OMQ:GetChannel() ~= nil
    for i = 1, H.ROWS do
        fight[i] = (active and (calls[i] or isDad(i))) and true or nil
    end
    H.Render()
end

-- the fight is over: only the rows with a call keep their button
function H.Disarm()
    for i = 1, H.ROWS do fight[i] = nil end
    H.Render()
end

function H.PlaySound(guid)
    if not PlaySound then return false end
    local t = now()
    guid = guid or "?"
    if t - (lastSound[guid] or -100) < H.SOUND_GAP then return false end
    lastSound[guid] = t
    local id = (_G.SOUNDKIT and _G.SOUNDKIT[H.SOUND.kit]) or H.SOUND.id
    local ok = pcall(PlaySound, id, "Master")
    return ok
end

function H.Dismiss(i)
    calls[i] = nil
    H.Render()
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
function H.Receive(guid, name, on)
    if not guid or guid == "" or isSecret(guid) then return end
    local me = OMQ:GetSelf()
    if me and guid == me.guid then return end
    local row = OMQ:GroupPosition(guid)
    if not row or row > H.ROWS then return end
    if not on then
        if calls[row] and calls[row].guid == guid then calls[row] = nil; H.Render() end
        return
    end
    if not H.Active() then return end
    local c = calls[row]
    if c and c.guid == guid then
        c.at = now()
        return
    end
    calls[row] = { guid = guid, name = (name and name ~= "") and name or "?", at = now(), since = now() }
    if not locked() then setAttributes() end
    H.Render()
    H.PlaySound(guid)
end

OMQ:RegisterMessage("LW", function(fields)
    H.Receive(fields[1], fields[2], fields[3] == "1")
end)

-- calls without news end; a dad who died or left needs no heal any more
function H.Expire()
    local changed = false
    for i, c in pairs(calls) do
        local gone = now() - c.at > H.EXPIRE or OMQ:GroupPosition(c.guid) ~= i
        if not gone and UnitIsDeadOrGhost then
            local ok, dead = pcall(UnitIsDeadOrGhost, "party" .. i)
            if ok and not isSecret(dead) and dead then gone = true end
        end
        if gone then calls[i] = nil; changed = true end
    end
    if changed then H.Render() end
end

----------------------------------------------------------------------
-- Sending: my own low life flash
----------------------------------------------------------------------
local low, lastSent = false, -100
function H.Sample()
    local f = _G.LowHealthFrame
    if not f then return end
    local shown = f:IsShown() and true or false
    -- safety: a frame that stays shown (another client, another UI) never calls while the health is fine
    if shown and UnitHealth and UnitHealthMax then
        local ok, hp, max = pcall(function() return UnitHealth("player"), UnitHealthMax("player") end)
        if ok and type(hp) == "number" and type(max) == "number" and not isSecret(hp) and not isSecret(max)
            and max > 0 and hp / max > 0.5 then
            shown = false
        end
    end
    local me = OMQ:GetSelf()
    if not me then return end
    if shown then
        if not low or now() - lastSent >= H.REPEAT then
            if OMQ:Send("LW", me.guid, me.name, "1") then lastSent = now() end
        end
        low = true
    elseif low then
        low = false
        OMQ:Send("LW", me.guid, me.name, "0")
    end
end
function H._ResetSender() low, lastSent = false, -100 end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
        if event == "PLAYER_REGEN_DISABLED" then H.Arm()
        elseif event == "PLAYER_REGEN_ENABLED" then setup(); setAttributes(); H.Disarm()
        elseif not locked() then setAttributes(); H.Render() end
    end)
    if not ok then OMQ:Error("healcall " .. event, err) end
end)
local acc = 0
ev:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < H.SAMPLE then return end
    acc = 0
    local ok, err = pcall(H.Sample)
    if not ok then OMQ:Error("healcall sample", err) end
    ok, err = pcall(H.Expire)
    if not ok then OMQ:Error("healcall expire", err) end
end)

-- the secure buttons are built out of combat only (after a /reload in a fight: at the end of the fight)
function setup()
    if holder or locked() then return end
    build()
    setAttributes()
    H.Render()
end
H.Setup = setup
OMQ:On("READY", setup)

OMQ:On("MOVE_MODE", function(on)
    moveMode = on and true or false
    H.Render()
end)

-- /omq healcall test: a call of party member 1 (or the first dad in the group), to see card, sound and click
OMQ:RegisterCommand("healcall", function(arg)
    if arg == "reset" then
        OMQ.db.healCallPoint = nil
        applyPosition()
        OMQ:Print("heal call position reset")
        return
    end
    if arg == "test" then
        if not H.Active() then
            OMQ:Print("heal call: only for healers (preferred role Healer or the healer role in the group) with a heal spell")
            return
        end
        for i = 1, H.ROWS do
            local g = UnitGUID and UnitGUID("party" .. i)
            if g and not isSecret(g) then
                local n = UnitName and UnitName("party" .. i)
                H.Receive(g, n or ("party" .. i), true)
                return
            end
        end
        OMQ:Print("heal call test: join a group first, the card belongs to a party member")
        return
    end
    OMQ:Print(string.format("heal call: %s, healer %s, spell %s, open calls %d",
        enabled() and "on" or "off", H.IsHealer() and "yes" or "no", tostring(H.Spell() or "none"),
        (function() local n = 0; for _ in pairs(calls) do n = n + 1 end; return n end)()))
    print("  /omq healcall test | reset (position; move it in the move mode)")
end, "low life calls to the healer: status, test, reset")
