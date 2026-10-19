-- One More Quest: /omq uiprobe
-- Read-only. Finds out what this client allows for a shareable "Dad UI": Edit Mode layouts,
-- console variables, chat windows, action bars, damage meter / swing timer. Changes nothing.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function show(v)
    if v == nil then return "nil" end
    if isSecret(v) then return "SECRET" end
    if type(v) == "number" then
        if v == math.floor(v) then return tostring(v) end
        return string.format("%.3f", v)
    end
    return tostring(v)
end
local function exists(path)
    local t = _G
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return false end
        t = t[part]
        if t == nil then return false end
    end
    return true
end
local function reverse(enum)
    local r = {}
    if type(enum) == "table" then for k, v in pairs(enum) do r[v] = k end end
    return r
end

local CVARS = {
    "autoLootDefault", "cameraDistanceMaxZoomFactor", "cameraDistanceMax", "uiScale", "useUiScale",
    "useCompactPartyFrames", "raidFramesDisplayPowerBars", "raidOptionKeepGroupsTogether",
    "chatStyle", "chatClassColorOverride", "chatMouseScroll", "whisperMode", "autoSelfCast",
    "nameplateShowEnemies", "nameplateShowFriends", "floatingCombatTextCombatDamage",
    "lootUnderMouse", "showTargetOfTarget", "enableFloatingCombatText", "ActionButtonUseKeyDown",
}
local PATTERNS = { "swing", "damagemeter", "damage_meter", "autoloot", "zoom", "compact", "raidframe", "multibar",
                   "actionbar", "editmode", "chatscale", "castbar", "partyframe", "unitframe" }

local function run()
    local out = {}
    -- values from the game can hold "|" escapes or control characters; they would blank the window
    local function add(t) out[#out + 1] = (tostring(t):gsub("[%c|]", " ")) end
    local function try(label, fn)
        local res = { pcall(fn) }
        if not res[1] then add(label .. ": ERROR " .. tostring(res[2])); return end
        local parts = {}
        for i = 2, #res do parts[#parts + 1] = show(res[i]) end
        add(label .. ": " .. (#parts > 0 and table.concat(parts, "  ") or "(no result)"))
    end

    local function section(fn)
        local ok, e = pcall(fn)
        if not ok then add("SECTION ERROR: " .. tostring(e)) end
    end
    print("One More Quest: UI probe running...")
    add("One More Quest " .. OMQ.version .. " UI probe (read-only)")
    add("in combat: " .. tostring(InCombatLockdown and InCombatLockdown()))

    section(function()
    add("-- which functions and frames exist")
    local names = {
        "C_EditMode", "C_EditMode.GetLayouts", "C_EditMode.SaveLayouts", "C_EditMode.SetActiveLayout",
        "C_EditMode.OnLayoutAdded", "C_EditMode.OnLayoutDeleted", "C_EditMode.ConvertLayoutInfoToString",
        "C_EditMode.ConvertStringToLayoutInfo", "C_EditMode.IsValidLayoutName", "C_EditMode.GetAccountSettings",
        "C_EditMode.SetAccountSetting", "C_EditMode.OnEditModeExit",
        "EditModeManagerFrame", "EditModeManagerFrame.OpenLayoutImport", "EditModeManagerFrame.SelectLayout",
        "EditModeManagerFrame.GetActiveLayoutInfo",
        "Enum.EditModeSystem", "Enum.EditModeLayoutType", "Enum.EditModeAccountSetting",
        "C_DamageMeter", "DamageMeter", "C_CVar.GetCVar", "C_CVar.SetCVar", "C_CVar.GetCVarDefault",
        "C_CVar.GetCVarInfo", "ConsoleGetAllCommands", "SetCVar", "GetCVar", "GetCVarDefault",
        "C_ActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
        "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "MicroMenu", "BagsBar",
        "CompactPartyFrame", "CompactRaidFrameManager", "PartyFrame", "PartyFrame.SetUseRaidStylePartyFrames",
        "CompactRaidFrameContainer", "FCF_GetChatWindowInfo", "FCF_SetChatWindowFontSize", "GetChatWindowInfo",
        "SetChatWindowSize", "SetChatWindowLocked", "FCF_OpenNewWindow", "NUM_CHAT_WINDOWS",
        "C_UI", "C_UI.Reload", "ReloadUI", "C_Timer.After",
    }
    for _, n in ipairs(names) do add(string.format("  %-52s %s", n, exists(n) and "yes" or "NO")) end
    end)
    section(function()
    add("-- Edit Mode layouts")
    if C_EditMode and C_EditMode.GetLayouts then
        local ok, info = pcall(C_EditMode.GetLayouts)
        if not ok or type(info) ~= "table" then
            add("GetLayouts: " .. (ok and "no table" or "ERROR " .. tostring(info)))
        else
            local layoutTypes = reverse(Enum and Enum.EditModeLayoutType)
            local systemNames = reverse(Enum and Enum.EditModeSystem)
            add("activeLayout index: " .. show(info.activeLayout) .. ", saved layouts: " .. show(info.layouts and #info.layouts))
            for i, l in ipairs(info.layouts or {}) do
                local moved = 0
                for _, s in ipairs(l.systems or {}) do if s.isInDefaultPosition == false then moved = moved + 1 end end
                add(string.format("  layout %d: %s  type %s  systems %s  moved from default %d", i, show(l.layoutName),
                    show(layoutTypes[l.layoutType] or l.layoutType), show(l.systems and #l.systems), moved))
            end
            -- layouts 1 and 2 are the two presets (Modern, Classic) which the game does not list in layouts
            local active = info.activeLayout
            local layout
            if EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo then
                local okA, li = pcall(EditModeManagerFrame.GetActiveLayoutInfo, EditModeManagerFrame)
                if okA and type(li) == "table" then
                    layout = li
                    add("(active layout from EditModeManagerFrame: " .. show(li.layoutName) .. ", type " .. show(layoutTypes[li.layoutType] or li.layoutType) .. ")")
                end
            end
            if not layout and info.layouts and active then
                layout = info.layouts[active - 2] or info.layouts[active]
                add("(active layout guessed from list position " .. ((info.layouts[active - 2] and (active - 2)) or active) .. ")")
            end
            if layout and layout.systems then
                add("-- active layout: " .. show(layout.layoutName) .. " (one line per system)")
                for _, s in ipairs(layout.systems) do
                    local sname = systemNames[s.system] or tostring(s.system)
                    local settingNames = reverse(Enum and Enum["EditMode" .. sname .. "Setting"])
                    local parts = {}
                    for _, st in ipairs(s.settings or {}) do
                        parts[#parts + 1] = (settingNames[st.setting] or ("#" .. show(st.setting))) .. "=" .. show(st.value)
                    end
                    local a = s.anchorInfo
                    add(string.format("  %s idx %s default %s anchor %s | %s", sname, show(s.systemIndex),
                        show(s.isInDefaultPosition),
                        a and (show(a.point) .. "/" .. show(a.relativePoint) .. " " .. show(a.offsetX) .. "," .. show(a.offsetY)) or "-",
                        table.concat(parts, " ")))
                end
                try("export string of the active layout (length)", function()
                    local s = C_EditMode.ConvertLayoutInfoToString(layout)
                    return type(s) == "string" and #s or s
                end)
            else
                add("active layout not found in the list: a preset layout is active. Create your own layout in Edit Mode first.")
            end
        end
        try("GetAccountSettings", function()
            local t = C_EditMode.GetAccountSettings and C_EditMode.GetAccountSettings()
            local p = {}
            for _, st in ipairs(t or {}) do p[#p + 1] = show(st.setting) .. "=" .. show(st.value) end
            return table.concat(p, " ")
        end)
    else
        add("C_EditMode.GetLayouts is not available: Edit Mode cannot be read by a addon here")
    end
    end)
    section(function()
    add("-- console variables of interest (value / default)")
    for _, name in ipairs(CVARS) do
        local ok, v = pcall(GetCVar, name)
        local okd, d = pcall(GetCVarDefault, name)
        add(string.format("  %-34s %s / %s", name, ok and show(v) or "ERR", okd and show(d) or "ERR"))
    end
    if ConsoleGetAllCommands then
        add("-- console commands matching the topics")
        local ok, list = pcall(ConsoleGetAllCommands)
        if ok and type(list) == "table" then
            local found, count = {}, 0
            for _, c in ipairs(list) do
                local n = c.command or c.name
                if type(n) == "string" then
                    local low = n:lower()
                    for _, p in ipairs(PATTERNS) do
                        if low:find(p, 1, true) then
                            count = count + 1
                            if count <= 90 then
                                local okv, v = pcall(GetCVar, n)
                                found[#found + 1] = "  " .. n .. " = " .. (okv and show(v) or "?")
                            end
                            break
                        end
                    end
                end
            end
            add(string.format("%d matches (first 90)", count))
            for _, l in ipairs(found) do add(l) end
        else
            add("ConsoleGetAllCommands: " .. tostring(list))
        end
    else
        add("ConsoleGetAllCommands not available: no list of console variables")
    end
    end)
    section(function()
    add("-- global names matching damage meter / swing timer")
    local hits = {}
    for k, v in pairs(_G) do
        if type(k) == "string" then
            local low = k:lower()
            if (low:find("damagemeter", 1, true) or low:find("swingtimer", 1, true) or low:find("swing_timer", 1, true))
                and #hits < 40 then
                hits[#hits + 1] = "  " .. k .. " (" .. type(v) .. ")"
            end
        end
    end
    table.sort(hits)
    if #hits == 0 then add("  none") end
    for _, h in ipairs(hits) do add(h) end
    end)
    section(function()
    add("-- chat windows")
    local n = NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local frame = _G["ChatFrame" .. i]
        if frame then
            local ok, name, size, r, g, b, a, shown, locked, docked = pcall(FCF_GetChatWindowInfo or GetChatWindowInfo, i)
            if ok and (shown or docked or i == 1) then
                add(string.format("  ChatFrame%d: %s font %s shown %s locked %s docked %s scale %s w %s h %s", i,
                    show(name), show(size), show(shown), show(locked), show(docked),
                    show(frame.GetScale and frame:GetScale()),
                    show(frame.GetWidth and frame:GetWidth()), show(frame.GetHeight and frame:GetHeight())))
            end
        end
    end
    end)
    section(function()
    add("-- action bars (shown now)")
    for _, nm in ipairs({ "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
                          "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "MicroMenu", "BagsBar" }) do
        local f = _G[nm]
        if f then add(string.format("  %-20s shown %s", nm, show(f.IsShown and f:IsShown()))) end
    end
    end)
    section(function()
    add("-- group frames")
    try("GetCVar useCompactPartyFrames", function() return GetCVar("useCompactPartyFrames") end)
    try("PartyFrame.GetUseRaidStylePartyFrames", function()
        return PartyFrame and PartyFrame.ShouldShowRaidStyleFrames and PartyFrame:ShouldShowRaidStyleFrames() or "n/a"
    end)
    try("IsInGroup / raid", function() return IsInGroup and IsInGroup(), IsInRaid and IsInRaid() end)
    end)
    add("-- end. Please send this whole report (Ctrl+A, Ctrl+C in the window).")
    OMQ.debugReport = true
    local ok, e = pcall(OMQ.ShowReport, OMQ, out)
    OMQ.debugReport = nil
    if not ok then
        print("One More Quest: report window failed: " .. tostring(e))
        for _, l in ipairs(out) do print(l) end
    end
end

OMQ:RegisterCommand("uiprobe", run, "read-only report: what a shareable UI preset could use on this client")
