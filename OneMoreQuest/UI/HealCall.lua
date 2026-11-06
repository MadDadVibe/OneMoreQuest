-- One More Quest: low life call to the healer (decision 423)
-- A dad whose screen shows the game's low life flash (LowHealthFrame) tells the group ("LW" message: guid,
-- name, 1 = low, 0 = over; repeated every few seconds while it lasts). A dad marked as healer (preferred role
-- Healer in the options, or the healer role in the group) gets a small red card "LOW LIFE / HEAL" right under
-- the dad's party frame (decision 424, the raid-style party frames of the Dad UI) and a warning sound, also in a
-- fight. A left click targets that dad and casts the emergency heal of the Shift-click heals (ClickHeals.lua, the
-- Shift + left click spell) on him. The tooltip names the dad.
-- Combat: a button that casts a spell must be a secure button, and the game forbids an addon to show, hide,
-- move or change a secure button while the combat lockdown is on. So every party place (party1 to party4)
-- has its own secure button (row N = partyN) under the party frame of that unit, holding "/target partyN" and the heal. At the
-- start of a fight (PLAYER_REGEN_DISABLED, before the lockdown) the rows of the dads in the group are shown,
-- fully transparent. What the healer sees is a plain frame (the card), which may come and go in combat. Over
-- every row without a call lies a plain "shield" frame that takes the clicks, so a click there never heals
-- by accident. Out of combat only the rows with a call are shown, nothing else catches the mouse.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local H = {}
OMQ.HealCall = H

H.ROWS = 5              -- rows 1 to 4: party1 to party4, row 5: my own character (decision 425)
H.SELF = 5
function H.Unit(i) return i == H.SELF and "player" or ("party" .. i) end
H.SAMPLE = 0.2          -- seconds between two looks at the low life flash
H.REPEAT = 3            -- while low, the call is sent again this often
H.EXPIRE = 8            -- a call without news for this long is over
H.SOUND_GAP = 2         -- the warning sound plays at most this often per dad
H.SOUND = { kit = "RAID_WARNING", id = 8959 }
local RED = { 0.95, 0.25, 0.22 }

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
-- a small card right under the party frame of the dad (the raid-style party frames of the Dad UI,
-- CompactPartyFrameMemberN with its unit); without such a frame the rows stack at a place of their own
H.W, H.H = 144, 30
local GAP = 3

local function rowY(i) return -((i - 1) * (H.H + GAP)) end

local function savePosition()
    local p, _, rp, x, y = holder:GetPoint()
    OMQ.db.healCallPoint = { p or "TOPLEFT", rp or "TOPLEFT", x or 0, y or 0 }
end
local function applyPosition()
    if locked() then return end
    local p = (OMQ.db and OMQ.db.healCallPoint) or { "TOPLEFT", "TOPLEFT", 190, -200 }
    holder:ClearAllPoints()
    holder:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end
H.ApplyPosition = applyPosition

function H.Macro(i, spell)
    local unit = H.Unit(i)
    return "/target " .. unit .. "\n/cast [@" .. unit .. "] " .. tostring(spell)
end

-- the party frame that shows this unit right now, nil when there is none
function H.PartyFrame(unit)
    local list = {}
    local cpf = _G.CompactPartyFrame
    if cpf and type(rawget(cpf, "memberUnitFrames")) == "table" then
        for _, f in ipairs(cpf.memberUnitFrames) do list[#list + 1] = f end
    end
    for n = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. n]
        if f then list[#list + 1] = f end
    end
    for _, f in ipairs(list) do
        local u = rawget(f, "unit") or rawget(f, "displayedUnit")
        if u == unit and f.IsShown and f:IsShown() then return f end
    end
    return nil
end

-- out of combat: every row under the frame of its dad, or in the stack
local function place(i)
    local b, f = buttons[i], H.PartyFrame(H.Unit(i))
    b:ClearAllPoints()
    if f then
        b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
        b:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
        b:SetHeight(H.H)
        b.under = f
    else
        b:SetSize(H.W, H.H)
        b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, rowY(i))
        b.under = nil
    end
end

local function makeCard(b)
    local s = CreateFrame("Frame", nil, UIParent)
    s:SetFrameStrata("HIGH")
    s:SetAllPoints(b)
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetAllPoints()
    s.bg:SetColorTexture(0.32, 0.03, 0.03, 0.92)
    s.edge = s:CreateTexture(nil, "BORDER")
    s.edge:SetPoint("TOPLEFT", -1, 1); s.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    s.edge:SetColorTexture(RED[1], RED[2], RED[3], 1)
    s.top = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.top:SetPoint("TOP", s, "TOP", 0, -3)
    s.top:SetTextColor(1, 0.3, 0.25)
    s.low = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.low:SetPoint("BOTTOM", s, "BOTTOM", 0, 3)
    if s.EnableMouse then s:EnableMouse(false) end
    s:Hide()
    return s
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "OneMoreQuestHealCall", UIParent)
    holder:SetSize(H.W, H.ROWS * (H.H + GAP))
    holder:SetFrameStrata("HIGH")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    applyPosition()
    for i = 1, H.ROWS do
        local b = CreateFrame("Button", "OneMoreQuestHealCall" .. i, holder, "SecureActionButtonTemplate")
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
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Low Life warning " .. tostring(c.name))
            GameTooltip:AddLine("Left click: target him and cast " .. tostring(H.Spell() or "your emergency heal") .. ".", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Right click: close the card.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        buttons[i] = b
        place(i)
        b:Hide()
        -- the card the healer sees: a plain frame over the button, free to come and go in combat
        skins[i] = makeCard(b)
        -- the shield: takes the clicks of a row without a call while its secure button waits for the fight
        local sh = CreateFrame("Frame", nil, UIParent)
        sh:SetFrameStrata("DIALOG")
        sh:SetAllPoints(b)
        sh:EnableMouse(true)
        sh:Hide()
        shields[i] = sh
    end
    -- move mode (only for the stack without party frames): a plain frame over all rows drags the holder
    mover = CreateFrame("Frame", nil, UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetAllPoints(holder)
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
    if i == H.SELF then return true end
    local g = UnitGUID and UnitGUID("party" .. i)
    if not g or isSecret(g) then return false end
    local u = OMQ.users and OMQ.users[g]
    return u ~= nil
end

----------------------------------------------------------------------
-- Showing
----------------------------------------------------------------------
local function fillCard(i, c)
    local s = skins[i]
    -- clickable: LOW LIFE / HEAL; a row that is not ready in this fight points to the Shift-click heal
    local top, low = "LOW LIFE", (armed[i] or moveMode) and "HEAL" or "SHIFT-CLICK"
    s.top:SetText(top)
    s.low:SetText(low)
    s.callTitle, s.callSub = top, low
end

-- brings every frame in line with the calls; secure parts only when allowed
function H.Render()
    if not holder then return end
    local lock = locked()
    local stacked = false
    for i = 1, H.ROWS do
        local c = calls[i]
        local want = moveMode or (c ~= nil)
        if not lock then
            place(i)
            if not buttons[i].under then stacked = true end
            -- out of combat: a secure button only where a call is (or in the move mode)
            if (want and not moveMode) or (fight[i] and not moveMode) then buttons[i]:Show(); armed[i] = true
            else buttons[i]:Hide(); armed[i] = nil end
        end
        if want then
            fillCard(i, c)
            skins[i]:Show()
            skins[i]:SetAlpha((armed[i] or moveMode) and 1 or 0.75)
        else
            skins[i]:Hide()
        end
        -- a shown secure button without a call (armed for the fight) gets the shield
        if armed[i] and not c then shields[i]:Show() else shields[i]:Hide() end
    end
    if mover then if moveMode and stacked and not lock then mover:Show() else mover:Hide() end end
end

-- the fight starts (before the lockdown): the rows of the dads in the group are shown, transparent and shielded
function H.Arm()
    if not holder or locked() then return end
    setAttributes()
    local active = H.Active()
    local grouped = OMQ:GetChannel() ~= nil
    for i = 1, H.ROWS do
        fight[i] = (active and (calls[i] or (i == H.SELF) or (grouped and isDad(i)))) and true or nil
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
    if not row or row >= H.SELF then return end
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
        local gone = now() - c.at > H.EXPIRE or (i ~= H.SELF and OMQ:GroupPosition(c.guid) ~= i)
        if not gone and UnitIsDeadOrGhost then
            local ok, dead = pcall(UnitIsDeadOrGhost, H.Unit(i))
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
-- my own low life: the healer gets the card under his own frame as well (decision 425)
function H.Own(shown, me)
    local c = calls[H.SELF]
    if shown and H.Active() then
        if c then c.at = now(); return end
        calls[H.SELF] = { guid = me.guid, name = me.name or "?", at = now(), since = now() }
        if not locked() then setAttributes() end
        H.Render()
        H.PlaySound(me.guid)
    elseif c and not shown and not c.test then
        calls[H.SELF] = nil
        H.Render()
    end
end

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
    H.Own(shown, me)
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
        elseif not locked() then
            setAttributes(); H.Render()
            -- the party frames take their new units a moment later
            C_Timer.After(0.5, function() if not locked() then pcall(H.Render) end end)
        end
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
        for i = 1, H.SELF - 1 do
            local g = UnitGUID and UnitGUID("party" .. i)
            if g and not isSecret(g) then
                local n = UnitName and UnitName("party" .. i)
                H.Receive(g, n or ("party" .. i), true)
                return
            end
        end
        -- alone: the card under my own frame (a click heals and targets me)
        local me = OMQ:GetSelf()
        if me then
            calls[H.SELF] = { guid = me.guid, name = me.name or "?", at = now(), since = now(), test = true }
            setAttributes(); H.Render(); H.PlaySound(me.guid)
        end
        return
    end
    OMQ:Print(string.format("heal call: %s, healer %s, spell %s, open calls %d",
        enabled() and "on" or "off", H.IsHealer() and "yes" or "no", tostring(H.Spell() or "none"),
        (function() local n = 0; for _ in pairs(calls) do n = n + 1 end; return n end)()))
    print("  /omq healcall test | reset (position; move it in the move mode)")
end, "low life calls to the healer: status, test, reset")
