-- Run from the repository root: lua5.1 tests/quest_locations.lua
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function rejected(message, ok, reason)
    equal(ok, false, message)
    assert(type(reason) == "string" and reason ~= "", message .. " explains its failure")
end

local frames, methods = {}, {}
local function frame(kind, name, parent)
    local value = setmetatable({ kind = kind, name = name, parent = parent, shown = true, scripts = {}, hooks = {} }, { __index = methods })
    frames[#frames + 1] = value
    return value
end
function methods:SetAllPoints(value) self.allPoints = value end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetSize() return self.width, self.height end
function methods:SetScale(value) self.scale = value end
function methods:GetScale() return self.scale or 1 end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:SetFrameLevel(value) self.frameLevel = value end
function methods:SetPoint(...) self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:HookScript(event, fn)
    self.hooks[event] = self.hooks[event] or {}
    table.insert(self.hooks[event], fn)
end
local function event(self, name)
    if self.scripts[name] then self.scripts[name](self) end
    for _, fn in ipairs(self.hooks[name] or {}) do fn(self) end
end
function methods:Show() self.shown = true; event(self, "OnShow") end
function methods:Hide() self.shown = false; event(self, "OnHide") end
function methods:IsShown() return self.shown and (not self.parent or self.parent:IsShown()) end
function methods:SetShown(value) self.shown = value end
function methods:CreateTexture() return frame("Texture", nil, self) end
for _, method in ipairs({ "SetTexture", "SetAtlas", "SetTexCoord", "SetVertexColor", "SetColorTexture",
    "SetNormalTexture", "SetHighlightTexture", "SetFrameStrata", "EnableMouse" }) do
    methods[method] = function() end
end
CreateFrame = frame
GetLocale = function() return "enUS" end
local channel, raid, chat = nil, false, {}
local OMQ = { GetChannel = function() return channel end }
_G.OneMoreQuest = OMQ
IsInRaid = function() return raid end
local function send(message, destination) chat[#chat + 1] = { message = message, channel = destination } end
local map = frame("Frame", "TestWorldMap")
map.mapID, map.zoom = 1413, 1
local canvas = frame("Frame", nil, map)
canvas.width, canvas.height = 1000, 600
local nativePin = frame("Button", "NativeMapPin", canvas)
function map:GetCanvas() return canvas end
function map:GetCanvasScale() return self.zoom end
function map:GetMapID() return self.mapID end
local nativeCalls = 0
for _, name in ipairs({ "OnMapChanged", "OnCanvasSizeChanged", "OnCanvasScaleChanged" }) do
    map[name] = function() nativeCalls = nativeCalls + 1 end
end
function map:SetMapID(id) self.mapID = id; self:OnMapChanged() end
hooksecurefunc = function(object, method, hook)
    local original = assert(object[method], "hooked native method exists")
    object[method] = function(...)
        local result = { original(...) }
        hook(...)
        return unpack(result)
    end
end
WorldMapFrame = map
ShowUIPanel = function(value) value:Show() end
C_ChatInfo = { SendChatMessage = send }
C_Map = {
    OpenWorldMap = function(id) map:SetMapID(id); map:Show() end,
    GetMapInfo = function(id) return { name = id == 1413 and "The Barrens" or "Westfall" } end,
    SetUserWaypoint = function() error("must not set or auto-share native waypoints") end,
}
assert(loadfile("OneMoreQuest/Guide/QuestLocations.lua"))("OneMoreQuest", OMQ)
local L = assert(OMQ.QuestLocations)
local function visiblePins()
    local result = {}
    for _, value in ipairs(frames) do
        if value.kind == "Button" and value.name ~= "NativeMapPin" and value:IsShown() then result[#result + 1] = value end
    end
    return result
end
local function checkNoUpdates()
    for _, value in ipairs(frames) do equal(value.scripts.OnUpdate, nil, "no per-frame map updater") end
end

local targets = {
    { map = 1413, x = 25, y = 40, label = "Sunscale Scytheclaw" },
    { map = 1413, x = 60, y = 70, label = "Raptor Horns" },
    { map = 1436, x = 50, y = 30, label = "Defias" },
}
rejected("empty targets", L:Show({}))
for _, invalid in ipairs({
    { map = 0, x = 1, y = 1 }, { map = 1413.5, x = 1, y = 1 },
    { map = 1413, x = -1, y = 1 }, { map = 1413, x = 1, y = 101 },
    { map = 1413, x = 0 / 0, y = 1 }, { map = 1413, x = math.huge, y = 1 },
    { map = 1413, x = "25", y = 1 },
}) do rejected("invalid coordinate", L:Show({ invalid })) end
rejected("selected map without targets", L:Show(targets, 1429))
equal(#chat, 0, "invalid map requests do not send messages")
local ok, count = L:Show(targets, 1413)
equal(ok, true, "opens native map")
equal(count, 2, "reports targets in selected region")
equal(map:GetMapID(), 1413, "opens selected map ID")
local pins = visiblePins()
equal(#pins, 2, "renders both mob locations")
equal(pins[1].parent:GetFrameLevel() > canvas:GetFrameLevel(), true, "marker overlay stays above map art")
equal(pins[1].point[4] * pins[1]:GetScale(), 250, "first pin normalized x")
equal(pins[1].point[5] * pins[1]:GetScale(), -240, "first pin normalized y")
equal(pins[2].point[4] * pins[2]:GetScale(), 600, "second pin normalized x")
equal(pins[2].point[5] * pins[2]:GetScale(), -420, "second pin normalized y")
equal(#chat, 0, "opening markers never sends a party message")
for _, value in ipairs(frames) do
    if value.parent and value.parent.parent == canvas then equal(value.parent.allPoints, canvas, "overlay follows canvas") end
end

-- Caller mutations do not move already-selected markers.
targets[1].x = 90
L:Refresh()
equal(visiblePins()[1].point[4] * visiblePins()[1]:GetScale(), 250, "target inputs are copied")
targets[1].x = 25
map.zoom = 2
local beforeHook = nativeCalls
map:OnCanvasScaleChanged()
equal(nativeCalls, beforeHook + 1, "zoom hook preserves the native method")
pins = visiblePins()
equal(pins[1]:GetScale(), 0.5, "pin compensates canvas zoom")
equal(pins[1].point[4] * pins[1]:GetScale(), 250, "zoom preserves normalized x")
equal(pins[1].point[5] * pins[1]:GetScale(), -240, "zoom preserves normalized y")
canvas.width, canvas.height = 800, 400
map:OnCanvasSizeChanged()
equal(visiblePins()[1].point[4] * visiblePins()[1]:GetScale(), 200, "resize follows canvas x")
map:SetMapID(1436)
equal(#visiblePins(), 1, "map change hides targets from other regions")
equal(visiblePins()[1].point[4] * visiblePins()[1]:GetScale(), 400, "other region uses its own coordinates")
map:SetMapID(1429)
equal(#visiblePins(), 0, "unrelated map contains no stale markers")
map:SetMapID(1413)
equal(#visiblePins(), 2, "returning to region restores its markers")
map:Hide()
equal(#visiblePins(), 0, "hiding world map hides journal markers")
map:Show()
equal(#visiblePins(), 2, "showing world map restores journal markers")
local previousCount = #visiblePins()
rejected("bad replacement target", L:Show({ { map = 1413, x = -1, y = 20 } }))
equal(#visiblePins(), previousCount, "invalid request preserves previous valid selection")
L:Clear()
equal(#visiblePins(), 0, "Clear removes only journal markers")
equal(map:IsShown(), true, "Clear leaves the native map open")
equal(nativePin:IsShown(), true, "Clear preserves unrelated native map pins")
map:OnMapChanged()
equal(#visiblePins(), 0, "cleared targets do not reappear on map change")
equal(#chat, 0, "map hooks and cleanup never broadcast destinations")
checkNoUpdates()

local function showUnavailable()
    local open = C_Map.OpenWorldMap
    C_Map.OpenWorldMap = function() error("blocked map API") end
    rejected("blocked map API", L:Show(targets, 1413))
    C_Map.OpenWorldMap = nil
    local show = ShowUIPanel
    ShowUIPanel = function() error("blocked panel API") end
    rejected("blocked fallback map API", L:Show(targets, 1413))
    ShowUIPanel, C_Map.OpenWorldMap = show, open
end
showUnavailable()
local open = C_Map.OpenWorldMap
C_Map.OpenWorldMap = nil
equal(L:Show(targets, 1413), true, "older supported world-map fallback works")
WorldMapFrame = nil
rejected("missing map and loader", L:Show(targets, 1413))
local loads = 0
C_AddOns = { LoadAddOn = function(name)
    equal(name, "Blizzard_WorldMap", "lazy load requests native map addon only")
    loads = loads + 1
    WorldMapFrame = map
end }
equal(L:Show(targets, 1413), true, "native map can be loaded lazily")
equal(loads, 1, "lazy load runs once when needed")
C_AddOns, C_Map.OpenWorldMap = nil, open
canvas.width = 0
rejected("zero-size canvas", L:Show(targets, 1413))
equal(#visiblePins(), 0, "zero-size canvas cannot claim visible markers")
canvas.width = 800
equal(L:Show({ { map = 1413, x = 0, y = 100 } }), true, "valid map-edge coordinates are accepted")
equal(visiblePins()[1].point[4], 0, "western edge marker has zero x")
equal(visiblePins()[1].point[5] * visiblePins()[1]:GetScale(), -400, "southern edge marker keeps map height")
InCombatLockdown = function() return true end
rejected("combat UI restriction", L:Show(targets, 1413))
InCombatLockdown = nil
L:Clear()
equal(#chat, 0, "all map availability and fallback checks stay local")

local target = { map = 1413, x = 62.4, y = 37.6, label = "Raptor Horns" }
rejected("solo has no destination recipient", L:Share(target))
channel = "SIM"
rejected("simulation never sends live chat", L:Share(target))
channel = "RAID"
rejected("raid channel is not used", L:Share(target))
channel, raid = "PARTY", true
rejected("raid membership is refused even with party channel", L:Share(target))
raid = false
equal(#chat, 0, "refused shares never transmit")
equal(L:Share(target), true, "explicit party share succeeds")
equal(#chat, 1, "explicit share sends exactly one message")
equal(chat[1].channel, "PARTY", "uses existing party choice")
assert(chat[1].message:find("Raptor Horns", 1, true) and chat[1].message:find("The Barrens", 1, true), "destination and region are readable")
assert(chat[1].message:find("62.4", 1, true) and chat[1].message:find("37.6", 1, true), "message includes destination coordinates")
channel = "INSTANCE_CHAT"
equal(L:Share(target), true, "instance group share succeeds")
equal(chat[2].channel, "INSTANCE_CHAT", "honors instance channel")
local before = #chat
rejected("invalid target cannot be shared", L:Share({ map = 1413, x = 200, y = 1 }))
rejected("overlong Unicode message is rejected", L:Share({ map = 1413, x = 1, y = 1, label = string.rep("ü", 200) }))
equal(#chat, before, "validation failures do not transmit partial messages")
local dangerous = { map = 1413, x = 1, y = 1, label = "Quest|cffff0000\nlocation\r" }
equal(L:Share(dangerous), true, "share sanitizes formatting/control characters")
assert(not chat[#chat].message:find("|", 1, true) and not chat[#chat].message:find("[\r\n]"), "no chat formatting injection")
local chatAPI = C_ChatInfo.SendChatMessage
C_ChatInfo.SendChatMessage = function() error("chat blocked") end
rejected("blocked chat API", L:Share(target))
C_ChatInfo.SendChatMessage = function() return false end
rejected("refused chat API", L:Share(target))
C_ChatInfo.SendChatMessage, SendChatMessage = nil, send
equal(L:Share(target), true, "legacy chat API fallback works")
SendChatMessage = nil
rejected("missing chat API", L:Share(target))
C_ChatInfo.SendChatMessage = chatAPI
GetLocale = function() return "deDE" end
equal(L:Share(target), true, "German client shares readable localized text")
assert(chat[#chat].message:find("Ich gehe hierhin:", 1, true), "German destination message is localized")

print("Quest locations: " .. checks .. " checks passed")
