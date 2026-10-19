-- One More Quest: /omq layout (decision 180, step 1)
-- Reads where every movable window and bar is, so that one layout can become the default
-- for every dad. Changes nothing. For each frame: the saved point, the size, the centre as a share
-- of the screen and the anchor to the nearest screen corner or edge (that is how the default will be
-- stored, so it fits other screen sizes too).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local LP = {}
OMQ.LayoutProbe = LP

-- name, global frame, where the addon keeps the saved point
LP.FRAMES = {
    { key = "arrow",    label = "Distance arrow",          frame = "OneMoreQuestArrow",        saved = function() return OMQ.db.arrow.point end },
    { key = "alerts",   label = "Alert cards",             frame = "OneMoreQuestAlerts",       saved = function() return OMQ.db.alerts.point end },
    { key = "bar",      label = "Guidance bar",            frame = "OneMoreQuestGuideBar",     saved = function() return OMQ.db.guide.point end },
    { key = "checkbar", label = "Check bar (follows the guidance bar)", frame = "OneMoreQuestCheckBar", saved = function() return nil end },
    { key = "qtrack",   label = "Quest tracker",           frame = "OneMoreQuestQuestTracker", saved = function() return OMQ.db.qtrack and OMQ.db.qtrack.point end },
    { key = "chat",     label = "Hidden chat messages",    frame = "OneMoreQuestChatWindow",   saved = function() local p = OMQDB.chatPos; return p and { p.point, p.relPoint, p.x, p.y } end },
    { key = "lifetime", label = "Lifetime statistics",     frame = "OneMoreQuestLifetime",     saved = function() return OMQ.db.lifetimeWindow end },
    { key = "betstrip", label = "Running bets (follows the check bar)", frame = "OneMoreQuestBetStrip", saved = function() return nil end },
}

local function num(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end
local function f1(v) return num(v) and string.format("%.1f", v) or tostring(v) end

-- the anchor to the nearest of the nine screen regions, in UIParent units
function LP.Anchor(left, bottom, w, h, W, H)
    local cx, cy = left + w / 2, bottom + h / 2
    local hz = (cx < W / 3) and "LEFT" or ((cx > W * 2 / 3) and "RIGHT" or "")
    local vt = (cy < H / 3) and "BOTTOM" or ((cy > H * 2 / 3) and "TOP" or "")
    local point = (vt .. hz)
    if point == "" then point = "CENTER" end
    local x
    if hz == "LEFT" then x = left elseif hz == "RIGHT" then x = left + w - W else x = cx - W / 2 end
    local y
    if vt == "BOTTOM" then y = bottom elseif vt == "TOP" then y = bottom + h - H else y = cy - H / 2 end
    return point, math.floor(x + 0.5), math.floor(y + 0.5)
end

function LP.Report()
    local out = {}
    local function add(t) out[#out + 1] = t end
    local W = UIParent:GetWidth() or 0
    local H = UIParent:GetHeight() or 0
    add("One More Quest " .. OMQ.version .. " layout probe")
    add(string.format("screen (UI units): %s x %s, UI scale %s, effective scale %s", f1(W), f1(H),
        tostring(GetCVar and GetCVar("uiScale")), f1(UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())))
    add(string.format("useUiScale %s, resolution %s / %s, physical %s x %s",
        tostring(GetCVar and GetCVar("useUiScale")), tostring(GetCVar and GetCVar("gxWindowedResolution")),
        tostring(GetCVar and GetCVar("gxFullscreenResolution")),
        tostring(GetPhysicalScreenSize and select(1, GetPhysicalScreenSize())), tostring(GetPhysicalScreenSize and select(2, GetPhysicalScreenSize()))))
    add("minimap icon angle: " .. tostring(OMQ.db.minimap.angle))
    for _, d in ipairs(LP.FRAMES) do
        add("-- " .. d.label .. " (" .. d.key .. ")")
        local ok, s = pcall(d.saved)
        s = ok and s or nil
        add("saved: " .. (s and table.concat({ tostring(s[1]), tostring(s[2]), f1(s[3]), f1(s[4]) }, " ") or "none (default spot)"))
        local f = _G[d.frame]
        if not f then
            add("frame: not built yet (open it once and run /omq layout again)")
        else
            local left, bottom, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
            if num(left) and num(bottom) and num(w) and num(h) and W > 0 and H > 0 then
                local p, x, y = LP.Anchor(left, bottom, w, h, W, H)
                add(string.format("shown %s, size %s x %s, centre at %d%% / %d%% of the screen", tostring(f:IsShown()),
                    f1(w), f1(h), math.floor((left + w / 2) / W * 100 + 0.5), math.floor((bottom + h / 2) / H * 100 + 0.5)))
                add(string.format("anchor: %s %d %d", p, x, y))
            else
                add("frame: no position yet (shown " .. tostring(f:IsShown()) .. ")")
            end
        end
    end
    add("-- end. Please send this whole report (Ctrl+A, Ctrl+C in the window).")
    return out
end

OMQ:RegisterCommand("layout", function()
    local out = LP.Report()
    if OMQDB then OMQDB.layoutReport = table.concat(out, "\n") end
    local ok = pcall(OMQ.ShowReport, OMQ, out)
    if not ok then for _, l in ipairs(out) do print(l) end end
end, "layout probe: where your windows and bars are (for the default layout)")
