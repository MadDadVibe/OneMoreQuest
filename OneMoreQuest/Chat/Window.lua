-- One More Quest: window with the chat messages the filter hid.
-- Movable (drag), closed with the x, scrollable with the mouse wheel.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local W = {}
OMQ.ChatWindow = W

local GOLD = { 0.89, 0.71, 0.29 }
local frame, log, status
local moveMode, shownBeforeMove = false, false

-- The position is saved (point and offset to the screen) and used every time the window opens.
local function savePosition()
    if not frame then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    if not point then return end
    OMQDB.chatPos = { point = point, relPoint = relPoint or point, x = x or 0, y = y or 0 }
end

local function applyPosition()
    if not frame then return end
    frame:ClearAllPoints()
    local p = OMQDB and OMQDB.chatPos
    if p and p.point then
        frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -118, 96)   -- default layout (decision 190)
    end
end

function W:ResetPosition()
    OMQDB.chatPos = nil
    applyPosition()
end

local function line(entry)
    return string.format("|cff8a8f99[%s]|r |cffe3b54a[%s]|r %s: %s",
        date("%H:%M", entry.at), entry.channel or "?", entry.author or "?", entry.text or "")
end

local function updateStatus()
    if not status then return end
    local n = OMQ.ChatFilter:Count()
    local text = n .. " hidden message" .. (n == 1 and "" or "s")
    local u = OMQ.ChatFilter.unreadable or 0
    if u > 0 then text = text .. " - " .. u .. " could not be checked (the game hides their text)" end
    status:SetText(text)
end

local function fill()
    if not log then return end
    log:Clear()
    for _, e in ipairs(OMQ.ChatFilter:Messages()) do log:AddMessage(line(e)) end
    if moveMode and OMQ.ChatFilter:Count() == 0 then
        log:AddMessage("|cffe3b54aMove mode: drag this window to a new position.|r")
    end
    updateStatus()
end

local function build()
    frame = CreateFrame("Frame", "OneMoreQuestChatWindow", UIParent)
    frame:SetSize(520, 340)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.07, 0.08, 0.105, 0.97)
    frame.edge = frame:CreateTexture(nil, "BORDER")
    frame.edge:SetPoint("TOPLEFT"); frame.edge:SetPoint("TOPRIGHT"); frame.edge:SetHeight(3)
    frame.edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -18)
    title:SetText("Hidden chat messages")

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -6, -8)
    local cx = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cx:SetPoint("CENTER"); cx:SetText("x"); cx:SetTextColor(0.55, 0.58, 0.63)
    close:SetScript("OnClick", function() W:Hide() end)

    log = CreateFrame("ScrollingMessageFrame", nil, frame)
    log:SetPoint("TOPLEFT", 16, -48)
    log:SetPoint("BOTTOMRIGHT", -16, 40)
    log:SetFontObject("GameFontHighlightSmall")
    log:SetJustifyH("LEFT")
    log:SetFading(false)
    log:SetMaxLines(600)
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            for _ = 1, 3 do self:ScrollUp() end
        else
            for _ = 1, 3 do self:ScrollDown() end
        end
    end)

    status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 16, 16)
    status:SetTextColor(0.6, 0.63, 0.68)

    local clear = CreateFrame("Button", nil, frame)
    clear:SetSize(90, 22)
    clear:SetPoint("BOTTOMRIGHT", -16, 12)
    clear.bg = clear:CreateTexture(nil, "BACKGROUND")
    clear.bg:SetAllPoints()
    clear.bg:SetColorTexture(0.16, 0.18, 0.23, 1)
    clear.label = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clear.label:SetPoint("CENTER")
    clear.label:SetText("Clear list")
    clear:SetScript("OnClick", function() OMQ.ChatFilter:Clear() end)

    frame:Hide()
    W.frame, W.log = frame, log
    if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestChatWindow") end
end

function W:IsShown() return frame and frame:IsShown() or false end

function W:Show()
    if not frame then build() end
    applyPosition()
    fill()
    frame:Show()
end

function W:Hide() if frame then frame:Hide() end end
function W:Toggle() if self:IsShown() then self:Hide() else self:Show() end end

-- Move mode (shared with the arrow, the alerts and the icon bar): the window is shown so it
-- can be placed, and closed again afterwards if it was not open before.
OMQ:On("MOVE_MODE", function(on)
    on = on and true or false
    if on == moveMode then return end
    moveMode = on
    if on then
        shownBeforeMove = W:IsShown()
        W:Show()
    else
        if frame then savePosition() end
        if not shownBeforeMove then W:Hide() elseif frame then fill() end
    end
end)

OMQ:On("CHAT_FILTERED", function(entry)
    if frame and frame:IsShown() then
        log:AddMessage(line(entry))
        updateStatus()
    end
end)
OMQ:On("CHAT_FILTER_CLEARED", function() if frame then fill() end end)
