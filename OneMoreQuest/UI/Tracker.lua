-- One More Quest: hide the objective tracker (option "Hide Objective Tracker", on by default)
-- The game shows the tracker again at every login, reload, quest change and when Edit Mode closes.
-- So the frame is hidden at those moments, and a hook on its Show hides it again whenever the game
-- shows it. Edit Mode itself is left alone, otherwise the tracker could not be placed.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local T = {}
OMQ.Tracker = T

local hidByUs = false
local hooked = false

function T:Wanted()
    return not (OMQ.db and OMQ.db.options) or OMQ.db.options.hideTracker ~= false
end

local function editModeOpen()
    return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive()
end

-- Hides or shows the frame to match the option. Safe to call at any time.
function T:Apply()
    local f = _G.ObjectiveTrackerFrame
    if not f then return end
    if self:Wanted() then
        if not editModeOpen() and f.IsShown and f:IsShown() then
            pcall(f.Hide, f)
            hidByUs = true
        end
    elseif hidByUs then
        pcall(f.Show, f)             -- only what we hid ourselves is shown again
        hidByUs = false
    end
end

function T:SetHidden(v)
    OMQ.db.options.hideTracker = v and true or false
    self:Apply()
end

local function hook()
    if hooked then return end
    local f = _G.ObjectiveTrackerFrame
    if not f or not hooksecurefunc then return end
    hooked = true
    hooksecurefunc(f, "Show", function() T:Apply() end)
    if f.HookScript then f:HookScript("OnShow", function() T:Apply() end) end
    if EditModeManagerFrame and EditModeManagerFrame.ExitEditMode then
        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            if C_Timer and C_Timer.After then C_Timer.After(0.5, function() T:Apply() end) else T:Apply() end
        end)
    end
end

local function refresh()
    hook()
    T:Apply()
    if C_Timer and C_Timer.After then C_Timer.After(1, function() T:Apply() end) end   -- after the game's own setup
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "PLAYER_REGEN_ENABLED" }) do
    pcall(frame.RegisterEvent, frame, e)
end
frame:SetScript("OnEvent", function() if OMQ.db then refresh() end end)
OMQ:On("READY", refresh)

OMQ:RegisterCommand("tracker", function(arg)
    arg = (arg or ""):lower()
    if arg == "hide" then T:SetHidden(true)
    elseif arg == "show" then T:SetHidden(false) end
    OMQ:Print("objective tracker: " .. (T:Wanted() and "hidden" or "shown") .. " (/omq tracker hide | show)")
end, "hide or show the objective tracker")
