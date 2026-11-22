-- One More Quest: damage or healing per mana in the spell tooltip (decision 648)
-- Hovering a spell that costs mana (spellbook, action bars) adds "DPM:x.yy" and/or "HPM:x.yy" to its tooltip.
-- The base amount comes from the tooltip text (German and English clients): a range counts with its middle,
-- an effect over time with its whole amount, and both parts of a spell with a direct and an over-time part count.
-- Shields count as healing, health drains as damage. My spell power is added with the usual classic factors:
-- cast time / 3.5 (1.5 to 3.5 sec), over time duration / 15, both parts split by the hybrid rule, channeled
-- duration / 3.5, a fixed factor for area and special spells, and less for spells learned below level 20.
-- Mana cost from the game (any language). Rage, energy and focus spells get nothing.
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local F = {}
OMQ.SpellEff = F

local isSecret = function(v) return issecretvalue and issecretvalue(v) end

-- spell school index for GetSpellBonusDamage
F.SCHOOLS = {
    { 2, "holy", "heilig" }, { 3, "fire", "feuer" }, { 4, "nature", "natur" },
    { 5, "frost" }, { 6, "shadow", "schatten" }, { 7, "arcane", "arkan" },
}

-- fixed spell power factors (rank 1 spell id; the name in the client's language covers every rank).
-- d = direct part, o = over time part (whole amount). Area spells and spells with an extra effect get less.
F.FACTORS = {
    [133] = { d = 1.0, o = 0 },        -- Fireball (the burn does not grow)
    [116] = { d = 0.814 },             -- Frostbolt (slow)
    [17] = { d = 0.1 },                -- Power Word: Shield
    [11426] = { d = 0.1 },             -- Ice Barrier
    [1463] = { d = 0 },                -- Mana Shield
    [543] = { d = 0 }, [6143] = { d = 0 }, -- Fire Ward, Frost Ward
    [1449] = { d = 0.143 },            -- Arcane Explosion
    [122] = { d = 0.043 },             -- Frost Nova
    [120] = { d = 0.135 },             -- Cone of Cold
    [10] = { o = 0.333 },              -- Blizzard
    [2120] = { d = 0.176, o = 0.12 },  -- Flamestrike
    [11113] = { d = 0.129 },           -- Blast Wave
    [5740] = { o = 0.333 },            -- Rain of Fire
    [1949] = { o = 0.333 },            -- Hellfire
    [26573] = { o = 0.333 },           -- Consecration
    [15237] = { d = 0.107 },           -- Holy Nova (damage and healing)
    [16914] = { o = 0.333 },           -- Hurricane
    [740] = { o = 0.333 },             -- Tranquility
    [596] = { d = 0.286 },             -- Prayer of Healing
    [1064] = { d = 0.714 },            -- Chain Heal
    [421] = { d = 0.714 },             -- Chain Lightning
    [15407] = { o = 0.45 },            -- Mind Flay
    [689] = { o = 0.5 },               -- Drain Life
    [18265] = { o = 0.5 },             -- Siphon Life
    [5143] = { o = 1.2 },              -- Arcane Missiles
}

local function lower(s) return (s:lower()) end

-- amount tokens: a number that is not a time, distance, percent, mana cost, count or rank
local SKIP_AFTER = { "^%s*%%", "^%s*sek", "^%s*sec", "^%s*second", "^%s*min", "^%s*std", "^%s*hour", "^%s*yd", "^%s*yard",
    "^%s*meter", "^%s*m%f[^%a]", "^%s*mana", "^%s*wut", "^%s*rage", "^%s*energ", "^%s*ziel", "^%s*target", "^%s*stufe",
    "^%s*level", "^%s*mal%f[^%a]", "^%s*times", "^%s*charge", "^%s*aufladung", "^%s*stapel", "^%s*stack",
    "^%s*punkte? mana", "^%s*sekunde" }
local SKIP_BEFORE = { "rank%s*$", "rang%s*$", "level%s*$", "stufe%s*$" }

local function amounts(clause)
    local out, pos = {}, 1
    while true do
        local s, e, n = clause:find("(%d+)", pos)
        if not s then break end
        local a, b, last = tonumber(n), nil, e
        local _, e2, n2 = clause:find("^%s*to%s*(%d+)", e + 1)
        if not e2 then _, e2, n2 = clause:find("^%s*bis%s*(%d+)", e + 1) end
        if e2 then b = tonumber(n2); last = e2 end
        local rest, before = clause:sub(last + 1), clause:sub(1, s - 1)
        local skip = false
        for _, p in ipairs(SKIP_AFTER) do if rest:find(p) then skip = true; break end end
        if not skip then for _, p in ipairs(SKIP_BEFORE) do if before:find(p) then skip = true; break end end end
        -- a number right after "every"/"alle" is the tick ("every 2 seconds"), caught by the time words above
        if not skip then out[#out + 1] = b and (a + b) / 2 or a end
        pos = last + 1
    end
    return out
end

local function kindOf(clause)
    local c = clause:gsub("health", "hp")
    if c:find("absorb") then return "heal" end
    if c:find("heal") or c:find("heilt") or c:find("heilen") or c:find("heilung") or c:find("geheilt") then return "heal" end
    if c:find("damage") or c:find("schaden") then return "dmg" end
    if (c:find("transfer") or c:find("drain") or c:find("berträgt") or c:find("entzieht"))
        and (c:find("hp") or c:find("gesundheit")) then return "dmg" end
end

local function schoolOf(clause)
    for _, s in ipairs(F.SCHOOLS) do
        for i = 2, #s do if clause:find(s[i]) then return s[1] end end
    end
end

local function overTime(clause)
    return tonumber(clause:match("over (%d+) sec") or clause:match("im verlauf von (%d+) sek")
        or clause:match("ber (%d+) sek") or clause:match("innerhalb von (%d+) sek"))
end

local function period(clause)
    local p = clause:match("every (%d+) sec") or clause:match("every (%d+) second") or clause:match("alle (%d+) sek")
    if p then return tonumber(p) end
    if clause:find("each second") or clause:find("every second") or clause:find("per second") or clause:find("jede sekunde")
        or clause:find("pro sekunde") or clause:find("jede sek") then return 1 end
end

local function duration(s)
    return tonumber(s:match("for (%d+) sec") or s:match("(%d+) sek lang") or s:match("lasts (%d+) sec")
        or s:match("hält (%d+) sek") or s:match("over (%d+) sec") or s:match("im verlauf von (%d+) sek")
        or s:match("ber (%d+) sek") or s:match("von (%d+) sek"))
end

-- F.Parse(text) -> { dmg = { direct, ot, dur, school }, heal = { ... } } or nil; text is the tooltip text below the name
function F.Parse(text)
    if type(text) ~= "string" or isSecret(text) or text == "" then return nil end
    local t = lower(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    t = t:gsub("(%d)[,%.](%d%d%d)%f[%D]", "%1%2")
    t = t:gsub("sek%.", "sek"):gsub("sec%.", "sec"):gsub("min%.", "min"):gsub("std%.", "std")
    local whole = t:gsub("\n", " ")
    local res, any = {}, false
    for sentence in (t:gsub("\n", ".") .. "."):gmatch("([^%.;]+)[%.;]") do
        local inherit
        local s = " " .. sentence .. " "
        s = s:gsub(" and then ", " and "):gsub(" und dann ", " und ")
        local clauses, from = {}, 1
        while true do
            local a, b = s:find(" and ", from)
            local a2, b2 = s:find(" und ", from)
            if a2 and (not a or a2 < a) then a, b = a2, b2 end
            if not a then clauses[#clauses + 1] = s:sub(from); break end
            clauses[#clauses + 1] = s:sub(from, a - 1); from = b + 1
        end
        for _, clause in ipairs(clauses) do
            local list = amounts(clause)
            local kind = kindOf(clause)
            if kind then inherit = kind end
            kind = kind or (#list > 0 and inherit)
            if kind and #list > 0 then
                local r = res[kind] or { direct = 0, ot = 0, dur = 0 }
                res[kind] = r
                r.school = r.school or schoolOf(clause)
                local p, ot = period(clause), overTime(clause)
                for _, v in ipairs(list) do
                    if p then
                        local d = duration(clause) or duration(whole)
                        if d and d > p then
                            r.ot = r.ot + v * math.floor(d / p + 0.5); r.dur = math.max(r.dur, d)
                        else
                            r.direct = r.direct + v
                        end
                    elseif ot then
                        r.ot = r.ot + v; r.dur = math.max(r.dur, ot)
                    else
                        r.direct = r.direct + v
                    end
                    any = true
                end
            end
        end
    end
    return any and res or nil
end

-- spell power factors (direct, over time) for one kind
function F.Factors(part, castSec, channel, fixed)
    if fixed then return fixed.d or 0, fixed.o or 0 end
    local td = math.min(math.max(castSec or 0, 1.5), 3.5) / 3.5
    local dur = part.dur or 0
    if channel and part.ot > 0 then return 0, math.min(dur / 3.5, 1) end
    local to = math.min(dur / 15, 1)
    if part.direct > 0 and part.ot > 0 then
        return td * td / (td + to), to * to / (td + to)
    elseif part.ot > 0 then
        return 0, to
    end
    return td, 0
end

-- below level 20 a spell gets less spell power: 3.75 % less per level
function F.LowLevel(lvl)
    if type(lvl) ~= "number" or lvl >= 20 or lvl < 1 then return 1 end
    return 1 - (20 - lvl) * 0.0375
end

local learned
local function learnLevel(id)
    local v
    if C_Spell and C_Spell.GetSpellLevelLearned then v = C_Spell.GetSpellLevelLearned(id)
    elseif GetSpellLevelLearned then v = GetSpellLevelLearned(id) end
    if type(v) == "number" and not isSecret(v) and v > 0 then return v end
    if not learned then
        learned = {}
        for _, levels in pairs(OMQ.TrainerSpells or {}) do
            for lvl, list in pairs(levels) do
                for _, e in ipairs(list) do learned[e[1]] = learned[e[1]] or lvl end
            end
        end
    end
    return learned[id]
end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local fixedByName
local function fixedFor(id)
    if F.FACTORS[id] then return F.FACTORS[id] end
    local name = spellName(id)
    if not name or isSecret(name) then return nil end
    if not fixedByName then
        fixedByName = {}
        for fid, f in pairs(F.FACTORS) do
            local n = spellName(fid)
            if n and not isSecret(n) then fixedByName[n] = f end
        end
    end
    return fixedByName[name]
end

local function castSeconds(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if type(info) == "table" and type(info.castTime) == "number" and not isSecret(info.castTime) then return info.castTime / 1000 end
    elseif GetSpellInfo then
        local _, _, _, ct = GetSpellInfo(id)
        if type(ct) == "number" and not isSecret(ct) then return ct / 1000 end
    end
    return 0
end

-- mana cost of the spell, nil when it costs no mana (rage, energy, focus, nothing)
function F.ManaCost(id, dur)
    local get = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    if not get then return nil end
    local list = get(id)
    if type(list) ~= "table" then return nil end
    local mana = 0
    for _, c in ipairs(list) do
        if type(c) == "table" and not isSecret(c.type) and not isSecret(c.cost) and c.type == 0 then
            local v = tonumber(c.cost) or 0
            if v <= 0 and tonumber(c.costPercent) and c.costPercent > 0 and UnitPowerMax then
                local max = UnitPowerMax("player", 0)
                if type(max) == "number" and not isSecret(max) then v = max * c.costPercent / 100 end
            end
            if tonumber(c.costPerSec) and c.costPerSec > 0 and dur then v = v + c.costPerSec * dur end
            mana = mana + v
        end
    end
    if mana > 0 then return mana end
end

local function bonus(kind, school)
    local _, class = UnitClass("player")
    if class == "HUNTER" then return 0 end
    local v
    if kind == "heal" then
        v = GetSpellBonusHealing and GetSpellBonusHealing()
    elseif school and GetSpellBonusDamage then
        v = GetSpellBonusDamage(school)
    elseif GetSpellBonusDamage then
        for i = 2, 7 do
            local x = GetSpellBonusDamage(i)
            if type(x) == "number" and not isSecret(x) and (not v or x > v) then v = x end
        end
    end
    if type(v) ~= "number" or isSecret(v) then return 0 end
    return v
end

F.last = nil  -- the last calculation, for /omq hpm

-- F.Calc(id, text, channel) -> { { label = "DPM", value = n, ... }, ... } or nil
function F.Calc(id, text, channel)
    local parsed = F.Parse(text)
    if not parsed then return nil end
    local dur = 0
    for _, p in pairs(parsed) do dur = math.max(dur, p.dur or 0) end
    local mana = F.ManaCost(id, channel and dur > 0 and dur or nil)
    if not mana then return nil end
    local ct, fixed, low = castSeconds(id), fixedFor(id), F.LowLevel(learnLevel(id))
    local out = {}
    for _, kind in ipairs({ "dmg", "heal" }) do
        local p = parsed[kind]
        if p and p.direct + p.ot > 0 then
            local fd, fo = F.Factors(p, ct, channel, fixed)
            local sp = bonus(kind, p.school)
            local total = p.direct + p.ot + (fd + fo) * low * sp
            out[#out + 1] = { label = kind == "heal" and "HPM" or "DPM", value = total / mana, base = p.direct + p.ot,
                power = sp, factor = (fd + fo) * low, mana = mana, cast = ct, total = total }
        end
    end
    return #out > 0 and out or nil
end

F.COLORS = { DPM = { 1.0, 0.6, 0.25 }, HPM = { 0.3, 1.0, 0.4 } }

function F.OnSpell(tt, data)
    if OMQ.db and OMQ.db.options and OMQ.db.options.spellEff == false then return end
    if not tt or not data then return end
    local id = data.id
    if type(id) ~= "number" or isSecret(id) then return end
    local name = tt.GetName and tt:GetName()
    local parts, channel = {}, false
    local n = tt.NumLines and tt:NumLines() or 0
    for i = 2, n do
        local fs = name and _G[name .. "TextLeft" .. i]
        local s = fs and fs:GetText()
        if type(s) == "string" and not isSecret(s) then
            local l = s:lower()
            if l:find("^dpm:") or l:find("^hpm:") then return end  -- already added
            if l:find("channeled") or l:find("kanalisiert") then channel = true end
            parts[#parts + 1] = s
        end
    end
    if #parts == 0 and type(data.lines) == "table" then
        for i = 2, #data.lines do
            local s = data.lines[i] and data.lines[i].leftText
            if type(s) == "string" and not isSecret(s) then
                local l = s:lower()
                if l:find("channeled") or l:find("kanalisiert") then channel = true end
                parts[#parts + 1] = s
            end
        end
    end
    local res = F.Calc(id, table.concat(parts, "\n"), channel)
    F.last = { id = id, res = res, text = table.concat(parts, " | ") }
    if not res then return end
    for _, r in ipairs(res) do
        local c = F.COLORS[r.label]
        tt:AddLine(("%s:%.2f"):format(r.label, r.value), c[1], c[2], c[3])
    end
    tt:Show()
end

OMQ:RegisterCommand("hpm", function()
    local l = F.last
    if not l then OMQ:Print("no spell hovered yet"); return end
    OMQ:Print(("spell %s: %s"):format(tostring(l.id), tostring(spellName(l.id))))
    if not l.res then OMQ:Print("no damage or healing found, or no mana cost: " .. (l.text or "")); return end
    for _, r in ipairs(l.res) do
        OMQ:Print(("%s:%.2f = (%d base + %d spell power x %.3f) / %d mana (cast %.1f sec)"):format(
            r.label, r.value, r.base, r.power, r.factor, r.mana, r.cast))
    end
end, "hpm - how the HPM/DPM of the last hovered spell was worked out", true)

OMQ:On("READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
        and Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, data)
            local ok, err = pcall(F.OnSpell, tt, data)
            if not ok then OMQ:Error("spell tooltip", err) end
        end)
    end
end)
