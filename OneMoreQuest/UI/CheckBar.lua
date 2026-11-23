-- One More Quest: check bar. A second small icon bar that hangs above the guidance bar (it moves with
-- it and is shown with it). Collapsed it shows only the Group Check button; hovering it slides out
-- the others (the group vote of /omq). Same behaviour as the guidance bar: it grows to the right and
-- only when it would leave the screen it grows to the left (mirrored), so the Group Check icon stays
-- above the meeting point icon on the screen edge. The check bar decides this on its own width.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local SIZE, GAP, PAD = 34, 3, 4        -- 20 % larger than before (decision 193)

local CB = {}
OMQ.CheckBar = CB
CB.HEIGHT = SIZE + PAD * 2              -- the run bar sits on top of it (decision 602)
CB.COLLAPSED = 1                       -- only the Group Check is always shown (decision 302: no One more quest icon)

local frame, buttons = nil, {}       -- buttons[id] = button (created once)
local items = {}                      -- the items shown now (the runs and dungeons are in the run bar, 602)
local expanded, suppressed = false, false
local flipped = false

-- icons in the "engraved stone" style (decision 192), rendered into Media
local MEDIA = "Interface\\AddOns\\OneMoreQuest\\Media\\"
local ITEMS = {
    { id = "ready", label = "Group Check", tip = "Click: durability, bags, drinks and class items of the group",
      icon = MEDIA .. "Icon_Check" },
    { id = "vote", label = "Group vote (/omq)", tip = "Click: start a vote - One more quest! (the arrow then leads the group to the next quest) or Bed time",
      icon = MEDIA .. "Icon_Vote" },
    { id = "old", label = "Old Quest Check", tip = "Click: the grey quests in your log - abandon them with one click",   -- decision 601
      icon = MEDIA .. "Icon_Old" },
    { id = "bis", label = "BiS Check", tip = "Click: the pre-raid BiS items of your spec and where you get them",   -- decision 657
      icon = MEDIA .. "Icon_Bis" },
    { id = "bet", label = "Bet Check", tip = "Click: start a bet with the dads",          -- decision 170, from level 5
      icon = MEDIA .. "Icon_Bet", show = function() return not OMQ.Unlock or OMQ.Unlock:Has("bets") end },
    { id = "prof", label = "Profession Check", tip = "Click: what each crafting profession costs to skill to 75, 150, 225 and 300, with the auction prices",   -- decision 535
      icon = MEDIA .. "Icon_Profession" },
    { id = "progress", label = "Progress Check", tip = "Click: your milestone timeline, from level 1 to 60",   -- decision 184
      icon = MEDIA .. "Icon_Progress" },
    { id = "duel", label = "Dad Duel", tip = "Click: challenge the dads in your group - 5 rounds with the foes of your journey",   -- from level 15
      icon = MEDIA .. "Icon_Duel", show = function() return OMQ.Match and OMQ.Match:Unlocked() end },
    { id = "rhythm", label = "Spell Rhythm", tip = "Click: press your spell keys to the beat of a song",   -- decision 381, from level 20
      icon = MEDIA .. "Icon_Rhythm", show = function() return OMQ.Rhythm and OMQ.Rhythm:Unlocked() end },
}

local badges = {}                     -- small numbers on an icon: badges.old = grey quests in the log (601)
local function currentItems()
    local list = {}
    for _, it in ipairs(ITEMS) do if not it.show or it.show() then list[#list + 1] = it end end
    -- the runs and the dungeon buttons live in the run bar above (UI/RunBar.lua, decision 602)
    return list
end

local makeButton

-- the grey quest number also sits on the always shown Group Check icon while the bar is collapsed, so the
-- dad sees from outside that the Old Quest Check has something to do (decision 650)
local function showCounts()
    local n = badges.old and badges.old > 0 and tostring(badges.old) or ""
    local old, ready = buttons.old, buttons.ready
    if old and old.count then old.count:SetText(n) end
    if ready and ready.count then ready.count:SetText(expanded and "" or n) end
end

local function layout()
    if not frame then return end
    items = currentItems()
    local n = expanded and #items or CB.COLLAPSED
    local width = PAD * 2 + n * (SIZE + GAP) - GAP
    local GB = OMQ.GuideBar
    local guide = GB and GB:Frame()
    local anchorBtn = GB and GB.AnchorButton and GB:AnchorButton()
    local left = GB and GB.AnchorLeft and GB:AnchorLeft()
    local screenW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1920
    flipped = left and (left + width > screenW) and true or false
    frame:ClearAllPoints()
    if anchorBtn then            -- hangs above the meeting point icon, the guide bar's padding (4) around it
        if flipped then frame:SetPoint("BOTTOMRIGHT", anchorBtn, "TOPRIGHT", 4, 6)
        else frame:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", -4, 6) end
    elseif guide then
        frame:SetPoint("BOTTOMLEFT", guide, "TOPLEFT", 0, 2)
    end
    frame:SetSize(width, SIZE + PAD * 2)
    local used = {}
    for i, it in ipairs(items) do
        local b = buttons[it.id] or makeButton(it)
        used[it.id] = true
        if i <= n then
            local slot = flipped and (n - i) or (i - 1)
            b:ClearAllPoints()
            b:SetPoint("LEFT", frame, "LEFT", PAD + slot * (SIZE + GAP), 0)
            b:Show()
        else
            b:Hide()
        end
    end
    for id, b in pairs(buttons) do if not used[id] then b:Hide() end end
    showCounts()
end

local function click(item)
    if item.id == "ready" then
        OMQ.Ready:Toggle()
    elseif item.id == "vote" then
        if OMQ.Vote then OMQ.Vote:Start() end
    elseif item.id == "old" then
        if OMQ.OldQuests then OMQ.OldQuests:Toggle() end
    elseif item.id == "bis" then
        if OMQ.BisCheck then OMQ.BisCheck:Toggle() end
    elseif item.id == "bet" then
        if OMQ.BetUI then OMQ.BetUI:ToggleCreate() end
    elseif item.id == "duel" then
        if OMQ.Match then
            local fine, why = OMQ.Match:Challenge()
            if not fine then OMQ:Print("duel: " .. tostring(why)) end
        end
    elseif item.id == "prof" then
        if OMQ.ProfCheck then OMQ.ProfCheck:Toggle() end
    elseif item.id == "progress" then
        if OMQ.Milestones then OMQ.Milestones:Toggle() end
    elseif item.id == "rhythm" then
        if OMQ.Rhythm then
            local _, why = OMQ.Rhythm:Open("bar")
            if why == "combat" then OMQ:Print("Spell Rhythm: not in combat.") end
        end
    end
    suppressed = true
    expanded = false
    layout()
end

local function mouseOver()
    if frame.IsMouseOver then
        local ok, v = pcall(frame.IsMouseOver, frame)
        if ok then return v and true or false end
    end
    return MouseIsOver and MouseIsOver(frame) and true or false
end

function makeButton(item)
    local b = CreateFrame("Button", nil, frame)
    buttons[item.id] = b
    b:SetSize(SIZE, SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    if item.icon then
        b.icon:SetTexture(item.icon)
    else
        b.icon:SetTexture(MEDIA .. "Icon_Dungeon")             -- dungeon buttons: the short name engraved on stone
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.label:SetPoint("CENTER", 0, -1)
        if b.label.SetFont then pcall(b.label.SetFont, b.label, "Fonts\\MORPHEUS.TTF", 13, "OUTLINE") end
        b.label:SetText(item.text or "?")
        b.label:SetTextColor(0.94, 0.78, 0.38)
    end
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    if item.id == "old" or item.id == "ready" then             -- the number of grey quests (decision 601, 650)
        b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        b.count:SetTextColor(1, 1, 1)
        b.count:SetText("")
    end
    b.item = item
    b:SetScript("OnClick", function(self) click(self.item) end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.item.label)
        GameTooltip:AddLine(self.item.tip, 0.8, 0.8, 0.8)
        if self.item.id == "ready" and (badges.old or 0) > 0 then   -- decision 650
            GameTooltip:AddLine(badges.old == 1 and "1 grey quest - the Old Quest Check in this bar abandons it"
                or (badges.old .. " grey quests - the Old Quest Check in this bar abandons them"), 1, 0.82, 0)
        end
        if self.item.id == "bet" and OMQ.Bets and OMQ.Bets.FillTooltip then pcall(OMQ.Bets.FillTooltip, OMQ.Bets, GameTooltip) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local function build()
    frame = CreateFrame("Frame", "OneMoreQuestCheckBar", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    local plate = frame:CreateTexture(nil, "BACKGROUND")
    plate:SetAllPoints()
    plate:SetColorTexture(0.07, 0.08, 0.105, 0.92)
    local t = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        t = t + (elapsed or 0)
        if t < 0.05 then return end
        t = 0
        local over = mouseOver()
        if not over then suppressed = false end
        local want = CB.tourOpen or (over and not suppressed)          -- tourOpen: the guided tour (decision 244)
        if want ~= expanded then expanded = want; layout() end
    end)
    layout()
end

-- follows the guidance bar: same visibility, same screen edge
local function follow(guide)
    if not frame then return end
    if guide and guide:IsShown() then frame:Show() else frame:Hide() end
    layout()
    if OMQ.RunBar and OMQ.RunBar.Follow then OMQ.RunBar:Follow(guide) end   -- the run bar on top (602)
end

function CB:IsExpanded() return expanded end
function CB:IsFlipped() return flipped end
function CB:Count()                    -- the fixed items available now (bets from 5, duel from 15, Spell Rhythm from 20)
    local n = 0
    for _, it in ipairs(ITEMS) do if not it.show or it.show() then n = n + 1 end end
    return n
end
function CB:Items() return items end
function CB:Refresh() layout() end
function CB:Button(id) return buttons[id] end
function CB:SetBadge(id, n)
    badges[id] = n
    showCounts()
end
function CB:Badge(id) return badges[id] end

local lvl = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do pcall(lvl.RegisterEvent, lvl, e) end
lvl:SetScript("OnEvent", function(_, e, newLevel)
    if frame then layout() end
end)

OMQ:On("UNLOCK", function() if frame then layout() end end)

OMQ:On("READY", function()
    build()
    if OMQ.GuideBar then
        OMQ.GuideBar.onLayout = follow
        local g = OMQ.GuideBar:Frame()
        if g then follow(g) end
    end
end)
