-- One More Quest: Disenchant, the third way to get rid of gear (decision 675)
-- Next to "vendor" and "auction house" there is "disenchant". It exists only when a character of the account on the
-- same realm and faction has Enchanting (read at every login, UI/Alts.lua: OMQDB.alts[guid].ench and .faction), or
-- when I have it myself. On WoW Forever every enchanter can disenchant every item (no skill or level needed).
-- An item goes this way when its disenchant value (UI/DisenchantValue.lua, scanned auction prices) is higher than the
-- vendor price and not 10 silver or more below the item's auction price (fix 683). The vendor helper and the automatic
-- sale leave it; the auction house list still offers it unless disenchanting brings more than 5 silver over the
-- auction price (then it stays in the bags, "disenchant").
--   * I am no enchanter: only items that are not bound. Within 60 yards of a mailbox OMQ knows (UI places: every
--     mailbox I or a dad opened once) a card says to send them to the enchanter. At the open mailbox a window lists
--     them: left click puts the item into a new letter to the enchanter (name and subject filled in, not sent),
--     "Send all" sends all of them at once, in several letters when they do not fit into one.
--   * I am an enchanter: the card comes at once, wherever I am (not in a fight), "Disenchant <item>"; a left click
--     disenchants it, then the next one. Bound items too, but only those the vendor helper would sell (worse than
--     what I wear, or my class cannot use them).
-- Never: upgrades for me that I can wear now (one I cannot wear yet goes too, fix 685), items of an equipment set, items kept with a right click in the vendor helper, items
-- bought back. Right click on a card: away until the items are gone; Shift + right click: 5 minutes.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local DS = {}
OMQ.DESell = DS

DS.SPELL = 13262                 -- Disenchant
DS.MIN_LEAD = 500                -- 5 silver over the second best way
DS.MAIL_YARDS = 60
DS.PER_MAIL = 12
DS.SUBJECT = "Disenchant"
DS.ROWS = 10
DS.KEY_SELF, DS.KEY_MAIL = "de:self", "de:mail"
local PURPLE = { 0.64, 0.45, 0.95 }
local GOLD = { 0.89, 0.71, 0.29 }
local ICON = "Interface\\Icons\\INV_Enchant_Disenchant"

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok or isSecret(a) then return nil end
    return a, b, c, d
end
local function money(c)
    local AH = OMQ.AuctionHelper
    if AH and AH.Money then return AH.Money(c) end
    return tostring(c)
end
local function instant(id)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end
local function info(x)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(x) end
    if GetItemInfo then return GetItemInfo(x) end
end

-- the switch: the alert rule "disenchant" (alerts tab); off = no third way at all
function DS.On()
    local M = OMQ.Alerts
    if M and M.IsRuleSet then return M:IsRuleSet("disenchant") end
    return true
end

----------------------------------------------------------------------
-- Who disenchants
----------------------------------------------------------------------
-- my Enchanting skill, or nil (0 counts too: learned, on Forever every enchanter can disenchant everything)
function DS.MyEnchanting()
    local M = OMQ.Alerts
    local lines = M and M.ProfessionLines and M.ProfessionLines()
    for _, l in ipairs(lines or {}) do
        if l.key == "Enchanting" then return type(l.rank) == "number" and l.rank or 0 end
    end
    return nil
end
function DS.KnowsSpell()
    if IsPlayerSpell and call(IsPlayerSpell, DS.SPELL) then return true end
    if IsSpellKnown and call(IsSpellKnown, DS.SPELL) then return true end
    return false
end
-- my own row of the characters table (UI/Alts.lua)
local function myRow()
    local A = OMQ.Alts
    local store = A and A.Store and A.Store()
    local me = UnitGUID and call(UnitGUID, "player")
    return store and me and store[me] or nil
end
-- fix 686: the skill stored at an earlier login counts too (the profession list is not always readable)
function DS.MeEnchanter()
    if DS.MyEnchanting() ~= nil or DS.KnowsSpell() then return true end
    local r = myRow()
    return r ~= nil and type(r.ench) == "number"
end
-- my realm: the game can answer with an empty name (fix 687, seen on WoW Forever); then my own row, else unknown
function DS.MyRealm()
    for _, fn in ipairs({ GetRealmName, GetNormalizedRealmName }) do
        local r = call(fn)
        if type(r) == "string" and r ~= "" then
            -- the normalized name has no spaces: only take it when it matches my row that way
            if fn == GetRealmName then return r end
            local row = myRow()
            if row and type(row.realm) == "string" and row.realm:gsub("[%s%-']", "") == r then return row.realm end
        end
    end
    local row = myRow()
    return row and type(row.realm) == "string" and row.realm ~= "" and row.realm or nil
end
function DS.MyFaction()
    local A = OMQ.Alts
    local f = A and A.Faction and A.Faction()
    if f then return f end
    local r = myRow()
    return r and r.faction or nil
end

function DS.SpellName()
    local n = (C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, DS.SPELL))
        or (GetSpellInfo and call(GetSpellInfo, DS.SPELL))
    return type(n) == "string" and n ~= "" and n or nil
end

-- the enchanter to send to: another character of mine on the same realm and faction with Enchanting,
-- the highest skill first. { guid, name, ench, class } or nil
function DS.Twink()
    local A = OMQ.Alts
    local store = A and A.Store and A.Store()
    if not store then return nil end
    local me = UnitGUID and call(UnitGUID, "player")
    local realm = DS.MyRealm()
    local faction = DS.MyFaction()
    local best
    for guid, e in pairs(store) do
        -- fix 686: an unknown faction (mine or the row's) does not rule a character out
        if guid ~= me and type(e) == "table" and type(e.ench) == "number" and type(e.name) == "string"
            and (not realm or not e.realm or e.realm == realm)
            and (not faction or not e.faction or e.faction == faction) then
            local name = e.name:match("^(%S+)")
            if name and (not best or e.ench > best.ench or (e.ench == best.ench and (e.level or 0) > (best.level or 0))
                or (e.ench == best.ench and (e.level or 0) == (best.level or 0) and name < best.name)) then
                -- the mail goes to the whole name: WoW Forever names have two parts (fix 686)
                best = { guid = guid, name = name, full = e.name, ench = e.ench, class = e.class, level = e.level }
            end
        end
    end
    return best
end

-- "self" (I disenchant), "mail" (I send to the enchanter) or nil (no third way)
function DS.Mode()
    if not DS.On() then return nil end
    if DS.MeEnchanter() then return "self" end
    if DS.Twink() then return "mail" end
    return nil
end

----------------------------------------------------------------------
-- Which items
----------------------------------------------------------------------
-- the disenchant value when the item goes the third way (fix 683, MadDadVibe): more than the vendor price and not
-- 10 silver or more below the auction price of the item (the auction house has fees and does not always sell, the
-- materials sell without them); no auction price: more than the vendor price is enough. Also the higher of the
-- other two values and the auction price.
DS.AH_SLACK = 1000               -- disenchant still wins up to 9s99 below the auction price
DS.AH_SHOW = 500                 -- the auction house list still offers it unless disenchanting brings more than 5s over its price
function DS.Verdict(id, vendor)
    local D = OMQ.Disenchant
    if not (D and D.Value) then return nil end
    local v, _, _, priced = D.Value(id)
    if not v or not priced or priced == 0 or v <= 0 then return nil end
    local P = OMQ.Prices
    local p = P and P.Auction and P.Auction(id)
    if type(p) ~= "number" or isSecret(p) or p <= 0 then p = nil end
    vendor = tonumber(vendor) or 0
    if v <= vendor then return nil end
    if p and v <= p - DS.AH_SLACK then return nil end
    return v, math.max(vendor, p or 0), p
end
-- the auction house list keeps the item in the bags only when disenchanting brings more than 5 silver over its price
function DS.HideFromAH(v, _, p)          -- the three values of DS.Takes
    if not v then return false end
    return not p or v > p + DS.AH_SHOW
end

-- the context of the vendor helper (equipment sets, professions...), built once per scan
local function context()
    local V = OMQ.Vendor
    return V and V.BaseContext and V.BaseContext() or {}
end

-- an upgrade for me that I cannot put on yet (level, armor type at my level, red tooltip line): disenchanted anyway
-- (fix 685: MadDadVibe wants it flagged; when I can wear it, it stays an upgrade)
function DS.UpgradeNotYet(link, equipLoc)
    local AH, B = OMQ.AuctionHelper, OMQ.AuctionBuy
    if not (link and AH and AH.UpgradeForMe and B and B.CanEquipNow) then return false end
    if not AH.UpgradeForMe(link, equipLoc) then return false end
    local ok, can = pcall(B.CanEquipNow, link)
    return ok and can == false
end

-- it: bag slot info; extra: { vendor, equipLoc, classID, link }; mode: DS.Mode() (asked when nil)
-- returns the disenchant value and the other value when this item goes the third way
function DS.Takes(it, extra, ctx, mode)
    if mode == nil then mode = DS.Mode() end
    if not mode or not it then return nil end
    local id, q = it.itemID, it.quality
    if not id or isSecret(id) or isSecret(q) or type(q) ~= "number" or q < 2 or q > 4 then return nil end
    local D = OMQ.Disenchant
    if not (D and D.ItemFacts and D.ItemFacts(id)) then return nil end
    extra = extra or {}
    local V, AH = OMQ.Vendor, OMQ.AuctionHelper
    if V and V.BoughtBack and V.BoughtBack(id) then return nil end
    if OMQ.Flip and OMQ.Flip.Owns(id) then return nil end        -- a bought flip is sold again (decision 721)
    if OMQ.Flip and OMQ.Flip.Gone and OMQ.Flip.Gone(id) then         -- decision 745: a done flip worth more disenchanted
        if OMQ.Flip.ExitWay(id) ~= "disenchant" then return nil end
        local v = D.Value(id)
        local vend = extra.vendor
        if vend == nil then vend = select(11, info(extra.link or it.hyperlink or id)) end
        return v, tonumber(vend) or 0, nil
    end
    if V and V.Kept and V.Kept(id) then return nil end
    local link = extra.link or it.hyperlink
    local equipLoc = extra.equipLoc
    if not equipLoc then equipLoc = select(4, instant(id)) end
    if it.isBound then
        if mode ~= "self" or not (V and V.Reason) then return nil end
        ctx = ctx or context()
        local ok, why = pcall(V.Reason, it, { vendor = extra.vendor, equipLoc = equipLoc, classID = extra.classID, link = link }, ctx)
        if not ok or (why ~= "worse" and why ~= "unusable") then
            -- an upgrade I cannot wear yet goes too (fix 685, MadDadVibe)
            if (ctx.sets or {})[id] or not DS.UpgradeNotYet(link, equipLoc) then return nil end
        end
    else
        ctx = ctx or context()
        if (ctx.sets or {})[id] then return nil end
        if AH and AH.UpgradeForMe and link and AH.UpgradeForMe(link, equipLoc) and not DS.UpgradeNotYet(link, equipLoc) then return nil end
    end
    local vendor = extra.vendor
    if vendor == nil then vendor = select(11, info(link or id)) end
    return DS.Verdict(id, vendor)
end

-- every item of the bags that goes the third way, the most valuable first
function DS.Scan(mode)
    local out = {}
    if mode == nil then mode = DS.Mode() end
    local C = C_Container
    if not mode or not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return out end
    local ctx = context()
    for bag = 0, OMQ.LastBag() do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local it = C.GetContainerItemInfo(bag, slot)
            if it and it.itemID and not isSecret(it.itemID) and not isSecret(it.quality) and (it.quality or 0) >= 2 then
                local link = it.hyperlink
                local name, _, quality, _, _, _, _, _, _, icon, vendor = info(link or it.itemID)
                local _, _, _, equipLoc, icon2, classID = instant(it.itemID)
                local v, other = DS.Takes(it, { vendor = vendor, equipLoc = equipLoc, classID = classID, link = link }, ctx, mode)
                if v then
                    out[#out + 1] = { bag = bag, slot = slot, itemID = it.itemID, link = link,
                                      name = name or it.itemName or ("item " .. it.itemID), icon = it.iconFileID or icon or icon2,
                                      quality = quality or it.quality, value = v, other = other, bound = it.isBound and true or false,
                                      locked = it.isLocked and true or false }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return out
end

local function total(list)
    local t = 0
    for _, e in ipairs(list) do t = t + (e.value or 0) end
    return t
end

----------------------------------------------------------------------
-- The mailbox nearby
----------------------------------------------------------------------
-- yards to the nearest mailbox OMQ knows on this map, or nil
function DS.MailboxDistance()
    local Pl = OMQ.Places
    if not (Pl and Pl.All and UnitPosition) then return nil end
    local a, b, _, inst = UnitPosition("player")
    if type(a) ~= "number" or type(b) ~= "number" or isSecret(a) or isSecret(b) then return nil end
    local best
    for _, p in ipairs(Pl:All("mailbox")) do
        if p.inst == inst and type(p.a) == "number" and type(p.b) == "number" then
            local d = math.sqrt((p.a - a) ^ 2 + (p.b - b) ^ 2)
            if not best or d < best then best = d end
        end
    end
    return best
end

----------------------------------------------------------------------
-- The card
----------------------------------------------------------------------
function DS.Card()
    local mode = DS.Mode()
    if not mode then return nil end
    if mode == "self" then
        local spell = DS.SpellName()
        if not spell or not DS.KnowsSpell() then return nil end
        local list = DS.Scan(mode)
        local e
        for _, x in ipairs(list) do if not x.locked then e = x; break end end
        if not e then return nil end
        local rest = #list - 1
        return {
            key = DS.KEY_SELF, tag = "DISENCHANT", icon = e.icon or ICON, color = PURPLE,
            title = spell .. ": " .. e.name,
            text = spell .. ": " .. e.name,
            sub = "~" .. money(e.value) .. " - left click: " .. spell .. (rest > 0 and string.format(" (%d more)", rest) or ""),
            macro = "/cast " .. spell .. "\n/use " .. e.bag .. " " .. e.slot,
            tipLink = e.link or false,
            tipLines = { string.format("Disenchant value ~%s; vendor / auction house %s.", money(e.value), money(e.other or 0)) },
        }
    end
    if DS.mailOpen then return nil end
    local d = DS.MailboxDistance()
    if not d or d > DS.MAIL_YARDS then return nil end
    local tw = DS.Twink()
    local list = DS.Scan(mode)
    if not tw or #list == 0 then return nil end
    return {
        key = DS.KEY_MAIL, tag = "DISENCHANT", icon = ICON, color = PURPLE,
        title = string.format("Send %d item%s to %s", #list, #list == 1 and "" or "s", tw.name),
        text = string.format("Send %d item%s to %s", #list, #list == 1 and "" or "s", tw.name),
        sub = string.format("~%s to disenchant - open the mailbox", money(total(list))),
        tipLines = { tw.name .. " has Enchanting: these items are worth more disenchanted than at the vendor or the auction house.",
                     "At the open mailbox a window lists them." },
        open = function() return "keep" end,
    }
end

function DS.Check()
    if InCombatLockdown and InCombatLockdown() then return "keep" end
    local c = DS.Card()
    return { c }
end

if OMQ.Alerts and OMQ.Alerts.Register then
    OMQ.Alerts:Register({ id = "disenchant", name = "Disenchant: items worth more disenchanted", check = DS.Check })
end

----------------------------------------------------------------------
-- The mailbox window (not an enchanter)
----------------------------------------------------------------------
local list = {}
DS.list = list
local panel, rows

local function stillThere(e)
    local it = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(e.bag, e.slot)
    return it and it.itemID == e.itemID
end

local function editText(name)
    local b = _G[name]
    if b and b.GetText then
        local ok, t = pcall(b.GetText, b)
        if ok and type(t) == "string" and not isSecret(t) then return t end
    end
    return nil
end
local function setEdit(name, text)
    local b = _G[name]
    if b and b.SetText then pcall(b.SetText, b, text) end
end

-- the send tab of the mailbox, with the enchanter and the subject filled in
local function sendTab(tw)
    if _G.MailFrameTab_OnClick then pcall(_G.MailFrameTab_OnClick, nil, 2) end
    local to = editText("SendMailNameEditBox")
    local full = tw.full or tw.name
    if to ~= full then setEdit("SendMailNameEditBox", full) end
    setEdit("SendMailSubjectEditBox", DS.SUBJECT)
end

local function attached(i)
    if not GetSendMailItem then return false end
    local ok, name = pcall(GetSendMailItem, i)
    return ok and name ~= nil
end
local function freeAttach()
    for i = 1, DS.PER_MAIL do if not attached(i) then return i end end
    return nil
end

-- puts one item into the letter; true when it went in
local function attach(e)
    local C = C_Container
    if not (C and C.PickupContainerItem and ClickSendMailItemButton) then return false end
    if not stillThere(e) then return false end
    local i = freeAttach()
    if not i then return false end
    if ClearCursor then ClearCursor() end
    C.PickupContainerItem(e.bag, e.slot)
    ClickSendMailItemButton(i)
    if ClearCursor then ClearCursor() end
    return true
end

-- left click on a row: into a new letter to the enchanter, not sent
function DS.Attach(e)
    if not (e and DS.mailOpen) then return false end
    local tw = DS.Twink()
    if not tw then return false end
    sendTab(tw)
    if not freeAttach() then
        OMQ:Print("disenchant: the letter is full (" .. DS.PER_MAIL .. " items) - send it first")
        return false
    end
    local ok = attach(e)
    if not ok then DS.Refresh() end
    return ok
end

-- "Send all": every listed item to the enchanter, several letters when needed
DS.sending = nil
local function sendNext()
    local s = DS.sending
    if not s then return end
    if not DS.mailOpen then DS.sending = nil; return end
    if ClearSendMail then pcall(ClearSendMail) end
    local n = 0
    while #s.queue > 0 and n < DS.PER_MAIL do
        local e = table.remove(s.queue, 1)
        if stillThere(e) and attach(e) then n = n + 1 end
    end
    if n == 0 then
        if s.letters > 0 then
            OMQ:Print(string.format("disenchant: sent %d item%s to %s in %d letter%s", s.items, s.items == 1 and "" or "s",
                s.to, s.letters, s.letters == 1 and "" or "s"))
        end
        DS.sending = nil
        DS.Reload()
        return
    end
    s.letters, s.items, s.waiting = s.letters + 1, s.items + n, true
    local subject = DS.SUBJECT
    if s.parts > 1 then subject = string.format("%s %d/%d", DS.SUBJECT, s.letters, s.parts) end
    local ok = SendMail and pcall(SendMail, s.to, subject, "")
    if not ok then
        OMQ:Print("disenchant: the letter could not be sent")
        DS.sending = nil
    end
end
DS.SendNext = sendNext

-- the list read again from the bags, now and once more when the game has moved the sent items (fix 689: sent items stayed listed)
function DS.Reload()
    local function again() if DS.open then DS.Fill(); DS.Refresh() end end
    again()
    if C_Timer and C_Timer.After then C_Timer.After(0.5, again); C_Timer.After(1.5, again) end
end

function DS.SendAll()
    if not DS.mailOpen or DS.sending then return 0 end
    local tw = DS.Twink()
    if not tw or #list == 0 then return 0 end
    local q = {}
    for _, e in ipairs(list) do q[#q + 1] = e end
    DS.sending = { to = tw.full or tw.name, queue = q, letters = 0, items = 0, parts = math.ceil(#q / DS.PER_MAIL) }
    sendTab(tw)
    sendNext()
    return #q
end

local function onSent(ok)
    local s = DS.sending
    if not s or not s.waiting then return end
    s.waiting = false
    if not ok then
        OMQ:Print("disenchant: the mailbox refused the letter - stopped")
        DS.sending = nil
        return
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, sendNext) else sendNext() end
end
DS.OnSent = onSent

local function fs(parent, font, r, g, b)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    t:SetJustifyH("LEFT")
    if r then t:SetTextColor(r, g, b) end
    return t
end
local function qColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 2]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function build()
    rows = {}
    panel = CreateFrame("Frame", "OneMoreQuestDisenchantMail", UIParent)
    panel:SetSize(380, 200)
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.086, 0.094, 0.122, 0.97)
    local edge = panel:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(2)
    edge:SetColorTexture(PURPLE[1], PURPLE[2], PURPLE[3], 1)
    local tag = fs(panel, "GameFontNormalSmall", PURPLE[1], PURPLE[2], PURPLE[3])
    tag:SetPoint("TOPLEFT", 16, -14); tag:SetText("DISENCHANT")
    local head = CreateFrame("Button", nil, panel)
    head:SetSize(250, 30); head:SetPoint("TOPLEFT", 0, 0)
    head:RegisterForClicks("RightButtonUp")
    head:SetScript("OnClick", function(_, button) if button == "RightButton" then DS.Close() end end)
    head:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Right click: close until the next visit"); GameTooltip:Show() end
    end)
    head:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.head = fs(panel, "GameFontHighlight", 0.79, 0.8, 0.84); panel.head:SetPoint("TOPLEFT", 16, -36); panel.head:SetWidth(348)
    panel.offset = 0
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, d)
        panel.offset = math.max(0, math.min(math.max(0, #list - DS.ROWS), panel.offset - d))
        DS.Refresh()
    end)
    for i = 1, DS.ROWS do
        local r = CreateFrame("Button", nil, panel)
        r:SetSize(348, 38)
        r:RegisterForClicks("LeftButtonUp")
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.11, 0.122, 0.153, 1)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(30, 30); r.icon:SetPoint("LEFT", 4, 0)
        r.name = fs(r, "GameFontHighlight"); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1); r.name:SetWidth(230)
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.sub = fs(r, "GameFontDisableSmall"); r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1); r.sub:SetWidth(230)
        if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
        r.price = fs(r, "GameFontNormal", PURPLE[1], PURPLE[2], PURPLE[3]); r.price:SetPoint("RIGHT", -8, 0); r.price:SetJustifyH("RIGHT")
        r:SetScript("OnClick", function(self) if self.e then DS.Attach(self.e) end end)
        r:SetScript("OnEnter", function(self)
            if GameTooltip and self.e then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetBagItem then GameTooltip:SetBagItem(self.e.bag, self.e.slot)
                elseif self.e.link then GameTooltip:SetHyperlink(self.e.link) end
                GameTooltip:AddLine("Left click: into the letter (not sent yet)", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        rows[i] = r
    end
    local all = CreateFrame("Button", "OneMoreQuestDisenchantSendAll", panel)
    all:SetSize(348, 44)
    all.bg = all:CreateTexture(nil, "BACKGROUND"); all.bg:SetAllPoints(); all.bg:SetColorTexture(0.165, 0.141, 0.086, 1)
    all.hl = all:CreateTexture(nil, "HIGHLIGHT"); all.hl:SetAllPoints(); all.hl:SetColorTexture(1, 1, 1, 0.06)
    all.price = fs(all, "GameFontNormal", GOLD[1], GOLD[2], GOLD[3]); all.price:SetPoint("RIGHT", -10, 0); all.price:SetJustifyH("RIGHT")
    all.title = fs(all, "GameFontNormalLarge", GOLD[1], GOLD[2], GOLD[3])
    all.title:SetPoint("LEFT", 10, 0); all.title:SetPoint("RIGHT", all.price, "LEFT", -8, 0)
    all:SetScript("OnClick", function() DS.SendAll() end)
    panel.all = all
    panel.more = fs(panel, "GameFontDisableSmall")
    panel.hint = fs(panel, "GameFontDisableSmall"); panel.hint:SetWidth(348)
    panel.hint:SetText("Left click: into the letter - Send all: everything, in as many letters as needed")
    panel:Hide()
end

local function anchor()
    panel:ClearAllPoints()
    local mf = _G.MailFrame
    if mf then panel:SetPoint("TOPLEFT", mf, "TOPRIGHT", 6, 0) else panel:SetPoint("LEFT", UIParent, "CENTER", 200, 0) end
end

function DS.Fill()
    for i = #list, 1, -1 do list[i] = nil end
    if DS.Mode() ~= "mail" then return list end
    for _, e in ipairs(DS.Scan("mail")) do list[#list + 1] = e end
    return list
end

function DS.Refresh()
    if not panel or not DS.open then return end
    local tw = DS.Twink()
    panel.offset = math.min(panel.offset, math.max(0, #list - DS.ROWS))
    local y = 36
    if #list == 0 then panel.head:SetText("Nothing to send to the enchanter")
    else panel.head:SetText(string.format("%d item%s for %s to disenchant", #list, #list == 1 and "" or "s", tw and tw.name or "?")) end
    y = y + 22
    for i, r in ipairs(rows) do
        local e = list[i + panel.offset]
        r.e = e
        r:SetShown(e ~= nil)
        if e then
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 16, -y)
            r.icon:SetTexture(e.icon)
            r.name:SetText(e.name); r.name:SetTextColor(qColor(e.quality))
            r.sub:SetText("vendor / auction house: " .. money(e.other or 0))
            r.price:SetText("~" .. money(e.value))
            y = y + 40
        end
    end
    if #list > DS.ROWS then
        panel.more:ClearAllPoints(); panel.more:SetPoint("TOPLEFT", 16, -y)
        panel.more:SetText(string.format("Mouse wheel: %d more", #list - DS.ROWS)); panel.more:Show()
        y = y + 16
    else panel.more:Hide() end
    panel.all:SetShown(#list > 0)
    if #list > 0 then
        y = y + 6
        local letters = math.ceil(#list / DS.PER_MAIL)
        panel.all:ClearAllPoints(); panel.all:SetPoint("TOPLEFT", 16, -y)
        panel.all.title:SetText(string.format("Send all - %d item%s%s", #list, #list == 1 and "" or "s",
            letters > 1 and string.format(" (%d letters)", letters) or ""))
        panel.all.price:SetText("")                -- no sum here: it read like the cost of sending (fix 689, MadDadVibe)
        y = y + 48
    end
    panel.hint:ClearAllPoints(); panel.hint:SetPoint("TOPLEFT", 16, -(y + 4))
    panel.hint:SetShown(#list > 0)
    if #list > 0 then y = y + 20 end
    panel:SetHeight(y + 12)
end

function DS.Open()
    if DS.Mode() ~= "mail" then return end
    DS.Fill()
    if #list == 0 then return end
    if not panel then build() end
    DS.open = true
    panel.offset = 0
    anchor()
    -- fix 689: closes together with the mailbox window (MAIL_CLOSED alone did not always come on WoW Forever)
    local mf = _G.MailFrame
    if mf and mf.HookScript and not DS.hookedMail then
        DS.hookedMail = true
        mf:HookScript("OnHide", function()
            DS.mailOpen = false
            DS.sending = nil
            DS.Close()
        end)
    end
    panel:Show()
    DS.Refresh()
end
function DS.Close()
    DS.open = false
    if panel then panel:Hide() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "BAG_UPDATE_DELAYED",
                    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local pending = false
ev:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
        if event == "MAIL_SHOW" then
            DS.mailOpen = true
            DS.Open()
        elseif event == "MAIL_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and DS.mailOpen
                and (not _G.MailFrame or not _G.MailFrame:IsShown())) then
            DS.mailOpen = false
            DS.sending = nil
            DS.Close()
        elseif event == "MAIL_SEND_SUCCESS" then
            if DS.sending then onSent(true) else DS.Reload() end        -- a letter sent by hand (fix 689)
        elseif event == "MAIL_FAILED" then onSent(false)
        elseif DS.open and not pending and not DS.sending then
            pending = true
            local function again() pending = false; if DS.open then DS.Fill(); DS.Refresh() end end
            if C_Timer and C_Timer.After then C_Timer.After(0.2, again) else again() end
        end
    end)
    if not ok then OMQ:Error("disenchant mail", err) end
end)

OMQ:RegisterCommand("desell", function()
    local mode = DS.Mode()
    local tw = DS.Twink()
    OMQ:Print("desell: " .. (mode == "self" and "you have Enchanting - you disenchant yourself"
        or mode == "mail" and ("enchanter " .. tw.name .. " (skill " .. tw.ench .. ")")
        or (DS.On() and "no enchanter on this realm and faction (log in with the enchanter once)" or "switched off")))
    OMQ:Print(string.format("desell: you: %s, %s", tostring(DS.MyRealm() or "realm unknown"), tostring(DS.MyFaction() or "faction unknown")))
    -- what every character of the account wrote (fix 676)
    local A = OMQ.Alts
    for _, e in pairs(A and A.Store and A.Store() or {}) do
        if type(e) == "table" and e.name then
            OMQ:Print(string.format("  %s: %s, %s, Enchanting %s", e.name, tostring(e.realm), tostring(e.faction or "faction unknown - log in once"),
                type(e.ench) == "number" and tostring(e.ench) or "no"))
        end
    end
    if not mode then return end
    local l = DS.Scan(mode)
    local d = DS.MailboxDistance()
    if mode == "mail" then OMQ:Print("desell: nearest known mailbox " .. (d and string.format("%.0f yards", d) or "unknown")) end
    OMQ:Print(string.format("desell: %d item%s, ~%s", #l, #l == 1 and "" or "s", money(total(l))))
    for i = 1, math.min(#l, 10) do
        local e = l[i]
        OMQ:Print(string.format("  %s: ~%s (vendor/auction %s)%s", e.link or e.name, money(e.value), money(e.other or 0), e.bound and " bound" or ""))
    end
end, "desell - which items go to disenchanting, and to whom", true)
