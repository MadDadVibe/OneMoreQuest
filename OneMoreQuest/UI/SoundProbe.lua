-- One More Quest: /omq sounds (decision 181, step 1: listen first)
-- Plays sounds of the game itself, so soft ones can be picked for the alert cards, the quest
-- tracker, the stamps, milestones and bets. Nothing else uses them yet.
--   /omq sounds            the list, grouped by where they could go
--   /omq sounds <n>        plays number n
--   /omq sounds <group>    plays a group one after the other (in, update, done, announce)
--   /omq sounds all        plays everything, 1.6 s apart
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local SP = {}
OMQ.SoundProbe = SP

-- kit = name in the game's SOUNDKIT table, id = the number when the name is missing
SP.LIST = {
    { group = "in",       kit = "IG_MAINMENU_OPTION_CHECKBOX_ON", id = 856,   note = "tiny click" },
    { group = "in",       kit = "IG_QUEST_LIST_OPEN",              id = 875,   note = "quest log page" },
    { group = "in",       kit = "U_CHAT_SCROLL_BUTTON",            id = 1115,  note = "very soft tick" },
    { group = "in",       kit = "MAP_PING",                        id = 3175,  note = "map ping" },
    { group = "in",       kit = "TELL_MESSAGE",                    id = 3081,  note = "whisper" },
    { group = "in",       kit = "IG_MAINMENU_OPEN",                id = 850,   note = "menu open" },
    { group = "update",   kit = "IG_ABILITY_PAGE_TURN",            id = 836,   note = "page turn" },
    { group = "update",   kit = "IG_CHARACTER_INFO_TAB",           id = 841,   note = "tab click" },
    { group = "update",   kit = "IG_QUEST_LIST_SELECT",            id = 877,   note = "quest select" },
    { group = "update",   kit = "LOOT_WINDOW_COIN_SOUND",          id = 120,   note = "coins" },
    { group = "done",     kit = "IG_QUEST_LIST_COMPLETE",          id = 878,   note = "quest complete" },
    { group = "done",     kit = "LEVELUPSOUND",                    id = 888,   note = "level up" },
    { group = "done",     kit = "UI_BNET_TOAST",                   id = 18019, note = "friend toast" },
    { group = "announce", kit = "READY_CHECK",                     id = 8960,  note = "ready check" },
    { group = "announce", kit = "PVPTHROUGHQUEUE",                 id = 8458,  note = "queue pop" },
    { group = "announce", kit = "IG_PLAYER_INVITE",                id = 880,   note = "group invite" },
    { group = "announce", kit = "ALARM_CLOCK_WARNING_3",           id = 12889, note = "alarm clock" },
    { group = "announce", kit = "RAID_WARNING",                    id = 8959,  note = "raid warning (loud)" },
}
SP.GROUPS = {
    ["in"] = "a new alert card or popup",
    update = "quest tracker progress, a bet value",
    done = "stamp, milestone reached, bet won",
    announce = "bet starts now, vote",
}

function SP.Resolve(e)
    local kit = _G.SOUNDKIT and _G.SOUNDKIT[e.kit]
    return kit or e.id, kit and "SOUNDKIT" or "id"
end

function SP.Play(n)
    local e = SP.LIST[n]
    if not e then return false end
    local id = SP.Resolve(e)
    local ok, willPlay = pcall(PlaySound, id, "Master")
    local line = string.format("%d  %s  %s (%s)", n, e.kit, e.note, tostring(id))
    if not ok or willPlay == false then line = line .. "  - not available" end
    OMQ:Print("sound " .. line)
    return ok and willPlay ~= false
end

local function playMany(list)
    for i, n in ipairs(list) do
        C_Timer.After((i - 1) * 1.6, function() SP.Play(n) end)
    end
end

local function show()
    OMQ:Print("sounds: /omq sounds <number> | in | update | done | announce | all")
    for _, g in ipairs({ "in", "update", "done", "announce" }) do
        print("  " .. g .. " - " .. SP.GROUPS[g] .. ":")
        for n, e in ipairs(SP.LIST) do
            if e.group == g then print(string.format("    %d  %s", n, e.note)) end
        end
    end
end

OMQ:RegisterCommand("sounds", function(arg)
    arg = (arg or ""):lower():gsub("%s+", "")
    local n = tonumber(arg)
    if n then
        if not SP.Play(n) and not SP.LIST[n] then OMQ:Print("no sound " .. n) end
    elseif arg == "all" then
        local list = {}
        for i = 1, #SP.LIST do list[i] = i end
        playMany(list)
    elseif SP.GROUPS[arg] then
        local list = {}
        for i, e in ipairs(SP.LIST) do if e.group == arg then list[#list + 1] = i end end
        playMany(list)
    else
        show()
    end
end, "sound test: /omq sounds | <number> | in | update | done | announce | all")
