-- One More Quest: statistics tooltip (section 7.2)
-- Grid: members as columns, statistics as rows, rank number in each cell.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local LABEL_W, COL_W, ROW_H, HEAD_H, PAD = 150, 108, 22, 20, 12
local GOLD = { 0.89, 0.71, 0.29 }
local MEDAL = { { 0.89, 0.71, 0.29 }, { 0.76, 0.79, 0.82 }, { 0.79, 0.51, 0.31 } }
local MEDAL_OTHER = { 0.42, 0.45, 0.51 }
local GREY = { 0.6, 0.63, 0.68 }

local frame, pool, used = nil, {}, 0
local anchorButton

local function newText(parent, font)
    used = used + 1
    local fs = pool[used]
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
        pool[used] = fs
    end
    fs:SetFontObject(font or "GameFontHighlight")
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

local texPool, texUsed = {}, 0
local function newTex(parent, layer)
    texUsed = texUsed + 1
    local t = texPool[texUsed]
    if not t then
        t = parent:CreateTexture(nil, layer or "BACKGROUND")
        texPool[texUsed] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function classColor(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function formatDuration(seconds)
    local m = math.floor(seconds / 60)
    if m >= 60 then return string.format("%dh %dm", math.floor(m / 60), m % 60) end
    return string.format("%dm", m)
end

local function build()
    frame = CreateFrame("Frame", "OneMoreQuestTooltip", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Opaque background and a thin gold border
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.07, 0.08, 0.105, 1)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.48, 0.39, 0.2, 1)

    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 1 then acc = 0; OMQ.Tooltip:Render() end
    end)
end

local Tooltip = {}
OMQ.Tooltip = Tooltip

function Tooltip:Render()
    if not frame then return end
    used, texUsed = 0, 0
    for _, fs in ipairs(pool) do fs:Hide() end
    for _, t in ipairs(texPool) do t:Hide() end

    -- session members; those who left the group are greyed out (decision 135)
    local people = OMQ:GetSessionTable()

    local width = PAD * 2 + LABEL_W + #people * COL_W
    local y = -PAD

    -- header: session time and level range
    local info = OMQ.Measure:GetSessionInfo()
    local head = newText(frame, "GameFontNormalLarge")
    head:SetPoint("TOP", frame, "TOP", 0, y)
    if info then
        head:SetText(string.format("Session %s  |  Levels %d-%d",
            formatDuration(info.elapsed), info.startLevel, info.level))
    else
        head:SetText("Session")
    end
    head:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    y = y - 26

    -- status lines (decision 115): paused, vote, other versions, dads in the group
    local st = OMQ.Minimap and OMQ.Minimap.State and OMQ.Minimap:State()
    if st then
        local function line(text, r, g, b)
            local t = newText(frame, "GameFontHighlightSmall")
            t:SetPoint("TOP", frame, "TOP", 0, y + 4)
            t:SetText(text)
            t:SetTextColor(r, g, b)
            y = y - 15
        end
        if st.paused then line(st.pausedText, 0.89, 0.71, 0.29) end
        if st.voting then line("A vote is waiting for you: /omq", 0.49, 0.78, 0.44) end
        -- other versions by name (decision 202): who is behind and who is ahead of me
        for _, v in ipairs(st.versions or {}) do
            if v.newer then
                line(string.format("%s has %s, newer than your %s - update!", v.name, v.version, OMQ.version), 1, 0.55, 0.3)
            else
                line(string.format("%s has %s, older than your %s - send the new zip", v.name, v.version, OMQ.version), 0.89, 0.71, 0.29)
            end
        end
        if st.dads > 0 then line(st.dads == 1 and "1 dad in your group" or (st.dads .. " dads in your group"), GREY[1], GREY[2], GREY[3]) end
        if st.paused or st.voting or #st.differs > 0 or st.dads > 0 then y = y - 4 end
    end

    -- member names
    for i, p in ipairs(people) do
        local x = PAD + LABEL_W + (i - 1) * COL_W
        if p.isSelf then
            local t = newTex(frame)
            t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y + 2)
            t:SetSize(COL_W - 4, 34)
            t:SetColorTexture(0.89, 0.71, 0.29, 0.18)
        end
        local n = newText(frame, "GameFontNormal")
        n:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        n:SetWidth(COL_W - 4)
        n:SetText(p.name or "?")
        if p.away then n:SetTextColor(0.45, 0.47, 0.5) else n:SetTextColor(classColor(p.class)) end
        local title = OMQ.Titles and OMQ.Titles:Get(p.guid)
        if p.away then
            local tag = newText(frame, "GameFontHighlightSmall")
            tag:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - 15)
            tag:SetText("left the group")
            tag:SetTextColor(0.45, 0.47, 0.5)
        elseif title or p.isSelf then
            local tag = newText(frame, "GameFontHighlightSmall")
            tag:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - 15)
            tag:SetWidth(COL_W - 4)
            if tag.SetWordWrap then tag:SetWordWrap(false) end
            tag:SetText(title or "YOU")
            if title then tag:SetTextColor(0.89, 0.71, 0.29) else tag:SetTextColor(GREY[1], GREY[2], GREY[3]) end
        end
    end
    y = y - 38

    -- rows
    for _, def in ipairs(OMQ.Ranking.sessionStats) do
        if def.heading then
            y = y - 4
            local h = newText(frame, "GameFontNormalSmall")
            h:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
            h:SetText(string.upper(def.heading))
            h:SetTextColor(0.72, 0.63, 0.42)
            local line = newTex(frame)
            line:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 90, y - 6)
            line:SetSize(width - PAD * 2 - 90, 1)
            line:SetColorTexture(0.17, 0.18, 0.23, 1)
            y = y - HEAD_H
        else
            local entries = {}
            for _, p in ipairs(people) do
                entries[#entries + 1] = { id = p.guid, value = p.values[def.key] }
            end
            local places = OMQ.Ranking.Rank(entries, def.best)

            local label = newText(frame, "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y - 4)
            label:SetText(def.label)
            label:SetTextColor(0.79, 0.8, 0.84)

            for i, p in ipairs(people) do
                local x = PAD + LABEL_W + (i - 1) * COL_W
                local cell = newTex(frame)
                cell:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
                cell:SetSize(COL_W - 4, ROW_H - 2)
                if p.isSelf then cell:SetColorTexture(0.89, 0.71, 0.29, 0.18)
                elseif p.away then cell:SetColorTexture(1, 1, 1, 0.015)
                else cell:SetColorTexture(1, 1, 1, 0.04) end

                local v = p.values[def.key]
                local approx = def.approx or (def.key == "hit" and p.values.hitApprox)
                local txt = newText(frame, "GameFontHighlight")
                txt:SetPoint("LEFT", frame, "TOPLEFT", x + 6, y - (ROW_H - 2) / 2)
                txt:SetText(OMQ.Ranking.Format(def, v, approx))
                if p.away or type(v) ~= "number" then txt:SetTextColor(0.45, 0.47, 0.5)
                else txt:SetTextColor(0.93, 0.92, 0.89) end

                local place = places[p.guid]
                if place then
                    local rk = newText(frame, "GameFontNormalSmall")
                    rk:SetPoint("RIGHT", frame, "TOPLEFT", x + COL_W - 10, y - (ROW_H - 2) / 2)
                    rk:SetText(tostring(place))
                    local c = MEDAL[place] or MEDAL_OTHER
                    rk:SetTextColor(c[1], c[2], c[3])
                end
            end
            y = y - ROW_H
        end
    end

    -- footer
    y = y - 10
    local foot = newText(frame, "GameFontHighlightSmall")
    foot:SetPoint("TOP", frame, "TOP", 0, y)
    foot:SetText("Left click: lifetime stats  -  Right click: quick options")
    foot:SetTextColor(GREY[1], GREY[2], GREY[3])
    y = y - 15
    local foot2 = newText(frame, "GameFontHighlightSmall")
    foot2:SetPoint("TOP", frame, "TOP", 0, y)
    foot2:SetText("Shift + left click: move mode  -  Shift + right click: all options")
    y = y - 15
    local foot3 = newText(frame, "GameFontHighlightSmall")
    foot3:SetPoint("TOP", frame, "TOP", 0, y)
    foot3:SetText("Ctrl + left click: start a new session")
    foot3:SetTextColor(GREY[1], GREY[2], GREY[3])
    foot2:SetTextColor(GREY[1], GREY[2], GREY[3])
    y = y - 16 - PAD

    frame:SetSize(math.max(width, 340), -y)
end

function Tooltip:Show(button)
    if not frame then build() end
    anchorButton = button
    frame:ClearAllPoints()
    local _, by = button:GetCenter()
    local low = by and by < (UIParent:GetHeight() / 2)
    if low then
        frame:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 6)
    else
        frame:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -6)
    end
    self:Render()
    frame:Show()
end

function Tooltip:Hide()
    if frame then frame:Hide() end
end

function Tooltip:IsShownFor(button)
    return frame and frame:IsShown() and anchorButton == button
end

OMQ:On("USER_UPDATED", function()
    if frame and frame:IsShown() then Tooltip:Render() end
end)
