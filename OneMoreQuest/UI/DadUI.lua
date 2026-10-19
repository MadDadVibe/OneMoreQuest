-- One More Quest: Dad UI (planned in decision 137)
-- /omq dadui capture reads the player's current UI (Edit Mode layout, account settings,
-- console variables that differ from the default, chat font sizes) and shows it as a Lua block.
-- The block is pasted into Data/DadUI.lua and shipped with the addon. Read-only.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function reverse(enum)
    local r = {}
    if type(enum) == "table" then for k, v in pairs(enum) do r[v] = k end end
    return r
end
local function q(s) return (string.format("%q", tostring(s)):gsub("\\\n", "\\n")) end

-- Settings that are different on every computer or have nothing to do with the interface.
-- The player trims the list anyway; this only keeps the obvious noise out.
local SKIP_PREFIX = {
    "gx", "graphics", "render", "sound", "music", "ambience", "master", "voice", "screen", "resolution",
    "windowed", "fullscreen", "vsync", "msaa", "lod", "shadow", "texture", "particle", "ssao", "water",
    "terrain", "horizon", "viewdistance", "ffx", "projected", "gamma", "brightness", "contrast", "display",
    "monitor", "refresh", "triplebuffer", "maxfps", "physics", "hdr", "raytrac", "weather", "outline",
    "account", "locale", "portal", "realm", "region", "lastcharacter", "gamesvc", "bnet", "checkaddon",
    "movie", "tutorial", "seen", "lastvault", "flashed", "closedinfo", "wowsubscription", "launcher",
    "graphicsquality", "cvarsynced", "videomem", "hardwarecursor", "usesound", "enablesound", "audio",
    "mouse", "gamepad", "joystick", "bindmode", "reduced", "preload", "synccursor", "nvidia", "amd",
    "dx", "d3d", "metal", "vulkan", "upscal", "fsr", "dlss", "xess", "sharpen", "gpu", "cpu", "threaded",
    "hwdetect", "last", "latest", "version", "wowaccount", "savedaccount", "playerstatus",
}
local function skipped(name)
    local low = name:lower()
    for _, p in ipairs(SKIP_PREFIX) do
        if low:sub(1, #p) == p then return true end
    end
    return false
end

local function sameValue(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and y ~= nil and math.abs(x - y) < 1e-6
end

local function capture()
    local lines = {}
    local function add(t) lines[#lines + 1] = t end
    local notes = {}
    local function note(t) notes[#notes + 1] = t end

    if InCombatLockdown and InCombatLockdown() then
        OMQ:Print("not in combat, please")
        return
    end

    -- 1. the active Edit Mode layout as an export string
    local layoutName, layoutString
    local ok, err = pcall(function()
        local info = EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo
            and EditModeManagerFrame:GetActiveLayoutInfo()
        if type(info) ~= "table" then error("no active layout") end
        layoutName = info.layoutName
        layoutString = C_EditMode.ConvertLayoutInfoToString(info)
    end)
    if not ok then note("layout: " .. tostring(err)) end
    if layoutString and layoutString:find("|", 1, true) then
        note("layout string contains a pipe character; the window may not show it")
    end

    -- 2. account wide Edit Mode settings
    local accounts = {}
    pcall(function()
        local names = reverse(Enum and Enum.EditModeAccountSetting)
        for _, st in ipairs(C_EditMode.GetAccountSettings() or {}) do
            accounts[#accounts + 1] = { st.setting, st.value, names[st.setting] or "?" }
        end
    end)

    -- 3. console variables that differ from their default
    local cvars, skippedCount, locked = {}, 0, 0
    local okC, listOrErr = pcall(ConsoleGetAllCommands)
    if okC and type(listOrErr) == "table" then
        local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar
        for _, c in ipairs(listOrErr) do
            local name = c.command or c.name
            if type(name) == "string" and (cvarType == nil or c.commandType == nil or c.commandType == cvarType) then
                local okV, v = pcall(GetCVar, name)
                local okD, d = pcall(GetCVarDefault, name)
                if okV and okD and v ~= nil and d ~= nil and not isSecret(v) and not sameValue(v, d) then
                    if skipped(name) then
                        skippedCount = skippedCount + 1
                    else
                        local scope = "?"
                        local readOnly, secure = false, false
                        pcall(function()
                            local _, _, acct, char, locked_, sec, ro = C_CVar.GetCVarInfo(name)
                            scope = acct and "account" or (char and "character" or "other")
                            readOnly = ro and true or false
                            secure = sec and true or false
                        end)
                        if readOnly or secure then
                            locked = locked + 1
                        else
                            cvars[#cvars + 1] = { name, tostring(v), tostring(d), scope }
                        end
                    end
                end
            end
        end
        table.sort(cvars, function(a, b) return a[1]:lower() < b[1]:lower() end)
    else
        note("console variables: " .. tostring(listOrErr))
    end

    -- 4. chat windows (font size, shown)
    local chat = {}
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        pcall(function()
            local name, size, _, _, _, _, shown, _, docked = (FCF_GetChatWindowInfo or GetChatWindowInfo)(i)
            if name and name ~= "" and (shown or docked) then chat[#chat + 1] = { i, name, size } end
        end)
    end

    add("-- One More Quest " .. OMQ.version .. " Dad UI capture. Copy this whole text.")
    add("-- Layout: " .. tostring(layoutName) .. ", " .. #cvars .. " settings differ from the default (" .. skippedCount ..
        " left out as graphics, sound, account or similar, " .. locked .. " read-only), " .. #chat .. " chat windows")
    for _, n in ipairs(notes) do add("-- NOTE: " .. n) end
    add("OMQ.DadUIPreset = {")
    add("    version = 1,")
    add("    layoutName = " .. q(layoutName or "Dad UI") .. ",")
    add("    layout = " .. q(layoutString or "") .. ",")
    add("    accountSettings = {   -- { setting, value }  name")
    for _, a in ipairs(accounts) do add(string.format("        { %s, %s },  -- %s", tostring(a[1]), tostring(a[2]), a[3])) end
    add("    },")
    add("    cvars = {   -- { name, value }  default, scope")
    for _, c in ipairs(cvars) do
        add(string.format("        { %s, %s },  -- default %s, %s", q(c[1]), q(c[2]), c[3], c[4]))
    end
    add("    },")
    add("    chat = {   -- { window, font size }  name")
    for _, c in ipairs(chat) do add(string.format("        { %d, %s },  -- %s", c[1], tostring(c[3]), tostring(c[2]))) end
    add("    },")
    add("}")

    -- A pipe character starts an escape code in text boxes and can blank the whole window.
    -- It is written as <P> (to be turned back when the preset file is made).
    local pipes = 0
    for i, l in ipairs(lines) do
        local fixed, n = l:gsub("|", "<P>")
        pipes = pipes + n
        lines[i] = (fixed:gsub("[%c]", " "))
    end
    if pipes > 0 then table.insert(lines, 2, "-- NOTE: " .. pipes .. " pipe characters were written as <P>") end
    OMQDB.dadUICapture = table.concat(lines, "\n")        -- also kept in the saved variables
    print(string.format("One More Quest: Dad UI capture: %d lines, %d characters, %d pipes replaced",
        #lines, #OMQDB.dadUICapture, pipes))
    OMQ.debugReport = true
    local okS, e = pcall(OMQ.ShowReport, OMQ, lines)
    OMQ.debugReport = nil
    if not okS then
        print("One More Quest: report window failed: " .. tostring(e))
    end
end

----------------------------------------------------------------------
-- Apply and restore. The preset (Data/DadUI.lua) is applied on a button press. Before the first
-- apply the player's own state is saved; restoring puts everything back and removes the layout.
----------------------------------------------------------------------
local D = {}
OMQ.DadUI = D

local function state()
    OMQDB.dadUI = OMQDB.dadUI or {}
    return OMQDB.dadUI
end

local function accountType() return Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or 1 end
local MAX_ACCOUNT_LAYOUTS = 5

-- The game numbers the preset layouts first; the saved layouts follow. Work out how many presets
-- there are from the position of the active layout in the list.
local function presetCount(info)
    local active = EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo
        and EditModeManagerFrame:GetActiveLayoutInfo()
    if type(active) == "table" then
        for i, l in ipairs(info.layouts or {}) do
            if l.layoutName == active.layoutName and l.layoutType == active.layoutType then
                return (info.activeLayout or i) - i
            end
        end
    end
    local n = 0
    if Enum and type(Enum.EditModePresetLayouts) == "table" then
        for _ in pairs(Enum.EditModePresetLayouts) do n = n + 1 end
    end
    return n > 0 and n or 2
end

local function isDadLayout(l, P)
    return l.layoutName == P.layoutName and l.layoutType == accountType()
end

local function getInfo()
    local ok, info = pcall(C_EditMode.GetLayouts)
    if ok and type(info) == "table" and type(info.layouts) == "table" then return info end
    return nil
end

local function makeBackup(P, info)
    local b = { cvars = {}, account = {}, chat = {}, layoutAbs = info and info.activeLayout }
    local active = EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo
        and EditModeManagerFrame:GetActiveLayoutInfo()
    if type(active) == "table" then b.layoutName, b.layoutType = active.layoutName, active.layoutType end
    for _, c in ipairs(P.cvars) do
        local ok, v = pcall(GetCVar, c[1])
        if ok and v ~= nil then b.cvars[c[1]] = tostring(v) end
    end
    pcall(function()
        for _, st in ipairs(C_EditMode.GetAccountSettings() or {}) do b.account[st.setting] = st.value end
    end)
    for _, c in ipairs(P.chat) do
        pcall(function()
            local _, size = (FCF_GetChatWindowInfo or GetChatWindowInfo)(c[1])
            if size then b.chat[c[1]] = size end
        end)
    end
    return b
end

local function setChatSize(i, size)
    local f = _G["ChatFrame" .. i]
    if f and FCF_SetChatWindowFontSize then pcall(FCF_SetChatWindowFontSize, nil, f, size) end
end

local function blocked()
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then
        OMQ:Print("Dad UI: Edit Mode is not available in this client")
        return true
    end
    if InCombatLockdown and InCombatLockdown() then
        OMQ:Print("Dad UI: not in combat, please")
        return true
    end
    if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
        OMQ:Print("Dad UI: close Edit Mode first")
        return true
    end
    return false
end

function D:IsApplied() return state().applied == true end

-- SaveLayouts stores the list but does not switch layouts; that needs SetActiveLayout. It is tried again
-- a second later in case the game was not ready the first time.
local function activate(abs)
    local ok = pcall(C_EditMode.SetActiveLayout, abs)
    if not ok and EditModeManagerFrame and EditModeManagerFrame.SelectLayout then
        pcall(EditModeManagerFrame.SelectLayout, EditModeManagerFrame, abs)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
            local i = getInfo()
            if i and i.activeLayout ~= abs then pcall(C_EditMode.SetActiveLayout, abs) end
        end)
    end
end

-- Puts the layout in the saved list (or updates it) and makes it the active one.
local function installLayout(P)
    local info = getInfo()
    if not info then return false, "Edit Mode layouts cannot be read" end
    local ok, parsed = pcall(C_EditMode.ConvertStringToLayoutInfo, P.layout)
    if not ok or type(parsed) ~= "table" or type(parsed.systems) ~= "table" then
        return false, "the Dad UI layout could not be read"
    end
    local presets = presetCount(info)
    local pos
    for i, l in ipairs(info.layouts) do if isDadLayout(l, P) then pos = i end end
    if pos then
        info.layouts[pos].systems = parsed.systems
    else
        local accounts, lastAccount = 0, 0
        for i, l in ipairs(info.layouts) do
            if l.layoutType == accountType() then accounts = accounts + 1; lastAccount = i end
        end
        if accounts >= MAX_ACCOUNT_LAYOUTS then
            return false, "you already have the maximum number of layouts; delete one in Edit Mode first"
        end
        pos = lastAccount + 1
        table.insert(info.layouts, pos, { layoutName = P.layoutName, layoutType = accountType(), systems = parsed.systems })
    end
    info.activeLayout = presets + pos
    local okS, err = pcall(C_EditMode.SaveLayouts, info)
    if not okS then return false, "saving the layout failed: " .. tostring(err) end
    activate(info.activeLayout)
    return true
end

function D:Apply()
    local P = OMQ.DadUIPreset
    if not P or not P.layout or P.layout == "" then OMQ:Print("Dad UI: no preset in this version"); return false end
    if blocked() then return false end
    local st = state()
    local info = getInfo()
    local fresh = false
    if not st.backup then st.backup = makeBackup(P, info); fresh = true end
    local ok, err = installLayout(P)
    if not ok then
        if fresh then st.backup = nil end
        OMQ:Print("Dad UI: " .. tostring(err) .. ". Nothing was changed.")
        return false
    end
    pcall(function()
        for _, a in ipairs(P.accountSettings or {}) do pcall(C_EditMode.SetAccountSetting, a[1], a[2]) end
    end)
    local failed = {}
    for _, c in ipairs(P.cvars) do
        local okC = pcall(SetCVar, c[1], c[2])
        if not okC then failed[#failed + 1] = c[1] end
    end
    for _, c in ipairs(P.chat) do setChatSize(c[1], c[2]) end
    st.applied = true
    st.appliedVersion = P.version
    OMQ:Print("Dad UI is on. Your old UI is saved; Options > Interface (or /omq dadui restore) brings it back.")
    if #failed > 0 then OMQ:Print("Dad UI: could not set " .. table.concat(failed, ", ")) end
    D:AskReload()
    return true
end

function D:Restore()
    local P = OMQ.DadUIPreset or {}
    local st = state()
    local b = st.backup
    if not b then OMQ:Print("Dad UI: there is nothing to restore"); return false end
    if blocked() then return false end
    for name, v in pairs(b.cvars or {}) do pcall(SetCVar, name, v) end
    pcall(function()
        for id, v in pairs(b.account or {}) do pcall(C_EditMode.SetAccountSetting, id, v) end
    end)
    for i, size in pairs(b.chat or {}) do setChatSize(i, size) end
    -- layouts: drop "Dad UI" and activate the old one again
    local info = getInfo()
    if info then
        local presets = presetCount(info)
        for i = #info.layouts, 1, -1 do
            if P.layoutName and isDadLayout(info.layouts[i], P) then table.remove(info.layouts, i) end
        end
        local target
        if b.layoutType ~= accountType() and b.layoutType ~= (Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character)
            and b.layoutAbs and b.layoutAbs <= presets then
            target = b.layoutAbs                          -- a preset layout
        else
            for i, l in ipairs(info.layouts) do
                if l.layoutName == b.layoutName and l.layoutType == b.layoutType then target = presets + i end
            end
        end
        info.activeLayout = target or 1
        local okS, err = pcall(C_EditMode.SaveLayouts, info)
        if not okS then OMQ:Print("Dad UI: restoring the layout failed: " .. tostring(err))
        else activate(info.activeLayout) end
    end
    st.backup, st.applied = nil, false
    OMQ:Print("Dad UI is off. Your old UI is back.")
    D:AskReload()
    return true
end

----------------------------------------------------------------------
-- Questions to the player
----------------------------------------------------------------------
local function popup(key, text, yes, onAccept)
    if StaticPopupDialogs then
        StaticPopupDialogs[key] = {
            text = text, button1 = yes, button2 = CANCEL or "Cancel",
            OnAccept = onAccept, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    if StaticPopup_Show then StaticPopup_Show(key); return true end
    return false
end

function D:AskApply()
    if not popup("OMQ_DADUI_APPLY",
        "Switch to the Dad UI?\n\nYour current UI is saved first. You can bring it back at any time in the One More Quest options.",
        "Switch", function() D:Apply() end) then D:Apply() end
end

function D:AskRestore()
    if not popup("OMQ_DADUI_RESTORE", "Bring back your old UI?\n\nThe Dad UI layout is removed.", "Restore",
        function() D:Restore() end) then D:Restore() end
end

function D:AskReload()
    local function ask() popup("OMQ_DADUI_RELOAD", "The UI needs a reload to finish.", "Reload now", function() ReloadUI() end) end
    if C_Timer and C_Timer.After then C_Timer.After(1.5, ask) else ask() end     -- after the layout retry
end

function D:Toggle()
    if D:IsApplied() then D:AskRestore() else D:AskApply() end
end

OMQ:RegisterCommand("dadui", function(arg)
    arg = (arg or ""):lower()
    if arg == "capture" then
        capture()
    elseif arg == "apply" then
        D:AskApply()
    elseif arg == "restore" then
        D:AskRestore()
    else
        OMQ:Print("Dad UI is " .. (D:IsApplied() and "ON" or "off") .. ". /omq dadui apply | restore | capture")
    end
end, "Dad UI: apply, restore, capture (/omq dadui)")
