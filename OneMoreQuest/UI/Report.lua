-- One More Quest: copyable report window (for bug reports)
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local frame

function OMQ:ShowReport(lines)
    local text = type(lines) == "table" and table.concat(lines, "\n") or tostring(lines)
    if not frame then
        local ok, f = pcall(CreateFrame, "Frame", "OneMoreQuestReport", UIParent, "BasicFrameTemplateWithInset")
        if not ok then
            for line in text:gmatch("[^\n]+") do print(line) end
            return
        end
        frame = f
        f:SetSize(700, 460)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetFrameStrata("DIALOG")
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -5)
        title:SetText("One More Quest report - Ctrl+A, Ctrl+C to copy")
        local sf = CreateFrame("ScrollFrame", "OneMoreQuestReportScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -30)
        sf:SetPoint("BOTTOMRIGHT", -32, 12)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        eb:SetWidth(640)
        eb:SetAutoFocus(false)
        if eb.SetMaxLetters then eb:SetMaxLetters(200000) end
        if eb.SetTextColor then eb:SetTextColor(1, 1, 1, 1) end
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.edit = eb
        if UISpecialFrames then table.insert(UISpecialFrames, "OneMoreQuestReport") end
    end
    local _, lines = text:gsub("\n", "\n")
    frame.edit:SetHeight(math.max(420, (lines + 2) * 15))     -- a scroll child needs a height, or nothing shows
    frame.edit:SetText(text)
    if OMQ.debugReport then
        print(string.format("One More Quest: report text %d characters, %d lines; box holds %d characters, height %s",
            #text, lines + 1, #(frame.edit:GetText() or ""), tostring(frame.edit:GetHeight())))
    end
    frame:Show()
    frame.edit:SetFocus()
    frame.edit:HighlightText()
end
