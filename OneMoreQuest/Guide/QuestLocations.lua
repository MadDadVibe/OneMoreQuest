-- Quest destination pins are a private overlay; never replace or broadcast the player's map pin.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local L = {}
OMQ.QuestLocations = L
local map, overlay
local pins, targets = {}, {}

local function text(en, de) return GetLocale and GetLocale() == "deDE" and de or en end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function number(v) return not secret(v) and type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function mapID(v) return number(v) and v > 0 and v % 1 == 0 end
local function copySpot(s)
    if secret(s) or type(s) ~= "table" or not mapID(s.map) or not number(s.x) or not number(s.y)
        or s.x < 0 or s.x > 100 or s.y < 0 or s.y > 100 then return nil end
    local label = not secret(s.label) and type(s.label) == "string" and s.label or text("Quest destination", "Questziel")
    return { map = s.map, x = s.x, y = s.y, label = label }
end

function L:Clear()
    targets = {}
    for _, pin in ipairs(pins) do pin:Hide() end
    if overlay then overlay:Hide() end
end

function L:Refresh()
    if not (map and overlay) then return false end
    local current = map:GetMapID()
    if not map:IsShown() or not mapID(current) then overlay:Hide(); return false end
    local canvas = map:GetCanvas()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local zoom = map.GetCanvasScale and map:GetCanvasScale() or 1
    if not number(width) or not number(height) or not number(zoom) or width <= 0 or height <= 0 or zoom <= 0 then
        overlay:Hide()
        return false
    end
    local n = 0
    for _, target in ipairs(targets) do
        if target.map == current then
            n = n + 1
            local pin = pins[n]
            if not pin then
                pin = CreateFrame("Button", nil, overlay)
                pin:SetSize(20, 20)
                pin.icon = pin:CreateTexture(nil, "ARTWORK")
                pin.icon:SetAllPoints()
                pin.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
                pin:SetScript("OnEnter", function(self)
                    if not GameTooltip then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.label)
                    GameTooltip:Show()
                end)
                pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                pins[n] = pin
            end
            local scale = 1 / zoom
            pin:SetScale(scale)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", width * target.x / 100 / scale, -height * target.y / 100 / scale)
            pin.label = string.format("%s (%.1f, %.1f)", target.label, target.x, target.y)
            pin:Show()
        end
    end
    for i = n + 1, #pins do pins[i]:Hide() end
    overlay:SetShown(n > 0)
    return true, n
end

local function attach(worldMap)
    if map == worldMap and overlay then return end
    assert(worldMap and worldMap.GetCanvas and worldMap.GetMapID and worldMap.IsShown and worldMap.HookScript
        and worldMap.OnMapChanged and worldMap.OnCanvasSizeChanged and worldMap.OnCanvasScaleChanged and hooksecurefunc)
    local canvas = worldMap:GetCanvas()
    assert(canvas and canvas.GetWidth and canvas.GetHeight)
    if overlay then L:Clear() end
    map = worldMap
    pins = {}
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    if canvas.GetFrameLevel then overlay:SetFrameLevel(canvas:GetFrameLevel() + 10) end
    local function refresh() L:Refresh() end
    hooksecurefunc(map, "OnMapChanged", refresh)
    hooksecurefunc(map, "OnCanvasSizeChanged", refresh)
    hooksecurefunc(map, "OnCanvasScaleChanged", refresh)
    map:HookScript("OnShow", refresh)
    map:HookScript("OnHide", function() overlay:Hide() end)
end

function L:Show(spots, chosenMap)
    if type(spots) ~= "table" or #spots == 0 then return false, text("No known target positions", "Keine bekannten Zielpositionen") end
    local nextTargets = {}
    for _, spot in ipairs(spots) do
        local target = copySpot(spot)
        if not target then return false, text("Invalid target position", "Ungültige Zielposition") end
        nextTargets[#nextTargets + 1] = target
    end
    chosenMap = chosenMap or nextTargets[1].map
    if not mapID(chosenMap) then return false, text("Invalid target region", "Ungültige Zielregion") end
    local count = 0
    for _, target in ipairs(nextTargets) do if target.map == chosenMap then count = count + 1 end end
    if count == 0 then return false, text("No targets in this region", "Keine Ziele in dieser Region") end
    if InCombatLockdown and InCombatLockdown() then return false, text("Open the map outside combat", "Karte außerhalb des Kampfes öffnen") end
    local ok = pcall(function()
        if C_Map and C_Map.OpenWorldMap then
            C_Map.OpenWorldMap(chosenMap)
        else
            if not WorldMapFrame then
                if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_WorldMap")
                elseif UIParentLoadAddOn then UIParentLoadAddOn("Blizzard_WorldMap") end
            end
            assert(WorldMapFrame and WorldMapFrame.SetMapID and ShowUIPanel)
            ShowUIPanel(WorldMapFrame)
            WorldMapFrame:SetMapID(chosenMap)
        end
        attach(WorldMapFrame)
        assert(map:IsShown() and map:GetMapID() == chosenMap)
    end)
    if not ok then return false, text("The client could not open the target map", "Der Client konnte die Zielkarte nicht öffnen") end
    targets = nextTargets
    local rendered, visible, renderedCount = pcall(self.Refresh, self)
    if not rendered or not visible or renderedCount == 0 then
        self:Clear()
        return false, text("The client could not show quest markers", "Der Client konnte die Questmarkierungen nicht anzeigen")
    end
    return true, count
end

function L:Share(spot)
    local target = copySpot(spot)
    if not target then return false, text("Invalid target position", "Ungültige Zielposition") end
    local channel = OMQ.GetChannel and OMQ:GetChannel()
    if (channel ~= "PARTY" and channel ~= "INSTANCE_CHAT") or (IsInRaid and IsInRaid()) then
        return false, text("Join a party to share this destination", "Zum Teilen dieses Ziels einer Gruppe beitreten")
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false, text("Party chat is unavailable", "Gruppenchat ist nicht verfügbar") end
    local zone = text("map ", "Karte ") .. target.map
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, target.map)
        if ok and type(info) == "table" and not secret(info.name) and type(info.name) == "string" then zone = info.name end
    end
    local function clean(s) return (s:gsub("[|%c]", " ")) end
    local message = string.format(text("I'm heading to: %s — %s (%.1f, %.1f)", "Ich gehe hierhin: %s — %s (%.1f, %.1f)"), clean(target.label), clean(zone), target.x, target.y)
    if #message > 255 then return false, text("Destination text is too long for party chat", "Zieltext ist zu lang für den Gruppenchat") end
    local ok, result = pcall(send, message, channel)
    if not ok or result == false then return false, text("The client could not send the destination", "Der Client konnte das Ziel nicht senden") end
    return true
end
