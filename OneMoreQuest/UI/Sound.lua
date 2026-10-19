-- One More Quest: soft sounds (decisions 181 and 185)
-- Four short sounds of the game itself underline changes. Off by default; the option "Sounds"
-- (Interface) switches them on. They play on the effects channel, so the game's own sound
-- settings apply. The same kind plays at most once per GAP seconds.
--   in        a new alert card or popup (bet invite, vote)
--   update    quest tracker progress
--   done      stamp, milestone reached, bet won
--   announce  bet starts now, vote started
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local S = {}
OMQ.Sound = S

-- picked with /omq sounds (numbers 3, 7, 13 and 17 of the list)
S.KINDS = {
    ["in"]   = { kit = "U_CHAT_SCROLL_BUTTON",  id = 1115 },
    update   = { kit = "IG_ABILITY_PAGE_TURN",  id = 836 },
    done     = { kit = "UI_BNET_TOAST",         id = 18019 },
    announce = { kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
}
local GAP = 1.0
local last = {}

function S:Enabled()
    return OMQ.db and OMQ.db.options and OMQ.db.options.sound == true or false
end

function S:SetEnabled(on)
    OMQ.db.options.sound = on and true or false
end

-- returns true when a sound was played
function S:Play(kind)
    if not self:Enabled() then return false end
    local k = self.KINDS[kind]
    if not k or not PlaySound then return false end
    local t = GetTime()
    if last[kind] and t - last[kind] < GAP then return false end
    last[kind] = t
    local id = (_G.SOUNDKIT and _G.SOUNDKIT[k.kit]) or k.id
    local ok = pcall(PlaySound, id, "SFX")
    return ok
end

function S:_Reset() last = {} end
