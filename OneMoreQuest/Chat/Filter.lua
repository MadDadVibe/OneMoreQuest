-- One More Quest: chat filter
-- Hides every chat message (all channels) that contains one of the words the player
-- listed, ignoring capital letters. The listed word may be a part of a longer word in
-- the message: "asmo" hides "I like asmodan", but "I like asm" is shown (the message has
-- to contain the whole listed word). Hidden messages are kept in
-- memory for the window (Chat/Window.lua) and are gone after a reload or logout.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local C = {}
OMQ.ChatFilter = C

local MAX_STORED = 500
local MAX_LINES_SEEN = 200

-- player messages of every kind; system and loot lines are not chat
local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_WHISPER",
}

local LABELS = {
    SAY = "Say", YELL = "Yell", EMOTE = "Emote", TEXT_EMOTE = "Emote", WHISPER = "Whisper",
    BN_WHISPER = "Whisper", PARTY = "Party", PARTY_LEADER = "Party", RAID = "Raid",
    RAID_LEADER = "Raid", RAID_WARNING = "Raid warning", INSTANCE_CHAT = "Instance",
    INSTANCE_CHAT_LEADER = "Instance", GUILD = "Guild", OFFICER = "Officer",
    COMMUNITIES_CHANNEL = "Community", MONSTER_SAY = "Say", MONSTER_YELL = "Yell",
    MONSTER_EMOTE = "Emote", MONSTER_WHISPER = "Whisper",
}

local words = {}             -- lower case pieces
local stored = {}            -- hidden messages, oldest first (memory only)
local seen, seenOrder = {}, {}
C.unreadable = 0             -- messages the game did not let us read

local function isSecret(x) return issecretvalue and issecretvalue(x) or false end

-- lower case for ASCII and the Latin-1 letters (umlauts and accents are two bytes in UTF-8)
local function lower(s)
    s = s:lower()
    s = s:gsub("\195([\128-\158])", function(b)
        if b == "\151" then return nil end          -- the multiplication sign
        return "\195" .. string.char(b:byte() + 32)
    end)
    return s
end
C.Lower = lower

-- the text as shown: colours and hyperlink data removed, only the visible name stays
local function visible(msg)
    msg = msg:gsub("|H.-|h(.-)|h", "%1")
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "")
    msg = msg:gsub("|r", "")
    msg = msg:gsub("|T.-|t", "")
    return msg
end

local function parse(text)
    local list = {}
    for piece in tostring(text or ""):gmatch("[^,]+") do
        piece = piece:match("^%s*(.-)%s*$")
        if piece ~= "" then list[#list + 1] = lower(piece) end
    end
    return list
end

function C:GetWordsText() return OMQ.db and OMQ.db.options and OMQ.db.options.chatWords or "" end

function C:SetWordsText(text)
    OMQ.db.options.chatWords = tostring(text or "")
    words = parse(OMQ.db.options.chatWords)
end

function C:Words() return words end

-- returns the matching word or nil
function C:Matches(msg)
    if #words == 0 or type(msg) ~= "string" then return nil end
    local text = lower(visible(msg))
    for _, w in ipairs(words) do
        if text:find(w, 1, true) then return w end
    end
end

function C:Messages() return stored end
function C:Count() return #stored end
function C:Clear()
    stored = {}
    OMQ:Fire("CHAT_FILTER_CLEARED")
end

local function remember(entry)
    stored[#stored + 1] = entry
    if #stored > MAX_STORED then table.remove(stored, 1) end
    OMQ:Fire("CHAT_FILTERED", entry)
end

-- The game calls the filter once per chat window for the same line: count a line once.
local function alreadySeen(lineID)
    if type(lineID) ~= "number" or isSecret(lineID) then return false end
    if seen[lineID] then return true end
    seen[lineID] = true
    seenOrder[#seenOrder + 1] = lineID
    if #seenOrder > MAX_LINES_SEEN then seen[table.remove(seenOrder, 1)] = nil end
    return false
end

local function filter(_, event, msg, author, ...)
    if #words == 0 or not OMQ:Master("chat") then return false end
    if isSecret(msg) then C.unreadable = C.unreadable + 1; return false end
    if type(msg) ~= "string" then return false end
    local match = C:Matches(msg)
    if not match then return false end
    -- never hide what I wrote myself
    -- after the author: language, channel name, target, flags, zone channel, channel index,
    -- channel base name, language id, line id, guid
    local guid = select(10, ...)
    if not isSecret(guid) and guid ~= nil and guid == UnitGUID("player") then return false end
    local lineID = select(9, ...)
    if not alreadySeen(lineID) then
        local kind = event:gsub("^CHAT_MSG_", "")
        local label = LABELS[kind] or kind
        if kind == "CHANNEL" then
            local base = select(7, ...)
            local name = select(2, ...)
            label = (type(base) == "string" and not isSecret(base) and base ~= "" and base)
                or (type(name) == "string" and not isSecret(name) and name) or "Channel"
        end
        remember({ at = time(), channel = label,
                   author = (type(author) == "string" and not isSecret(author)) and author or "?",
                   text = msg, word = match })
    end
    return true
end

local registered = false
local function register()
    if registered or not ChatFrame_AddMessageEventFilter then return end
    registered = true
    for _, e in ipairs(EVENTS) do pcall(ChatFrame_AddMessageEventFilter, e, filter) end
end
C.Filter = filter

OMQ:On("READY", function()
    words = parse(C:GetWordsText())
    register()
end)

OMQ:RegisterCommand("chat", function(arg)
    if arg == "clear" then C:Clear(); OMQ:Print("hidden messages cleared"); return end
    if arg == "position" then
        if OMQ.ChatWindow then OMQ.ChatWindow:ResetPosition() end
        OMQ:Print("hidden messages window position reset")
        return
    end
    if OMQ.ChatWindow then OMQ.ChatWindow:Toggle() end
end, "open the list of hidden chat messages (/omq chat clear empties it)")
