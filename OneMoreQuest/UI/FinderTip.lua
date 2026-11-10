-- One More Quest: gathering list in the Find Herbs / Find Minerals tooltip (decision 512)
-- Hovering the buff of Find Herbs or Find Minerals adds a list of every herb or ore with the skill it needs.
-- Names and icons come from the game by item id, so they follow the client's language. Each line is colored by
-- my own skill like the profession window: red = cannot gather yet, orange/yellow/green = still gives skill
-- points, gray = gives nothing any more. The first line says my skill ("Mining 142/150").
-- Left out on purpose: ooze covered variants, Indurium and the Obsidian chunks (special or raid only).
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local F = {}
OMQ.FinderTip = F

-- { item id, required skill, English fallback name, suffix }
F.LISTS = {
    herb = {
        prof = "Herbalism",
        { 2447, 1, "Peacebloom" }, { 765, 1, "Silverleaf" }, { 2449, 15, "Earthroot" },
        { 785, 50, "Mageroyal" }, { 2450, 70, "Briarthorn" }, { 3820, 85, "Stranglekelp" },
        { 2453, 100, "Bruiseweed" }, { 3355, 115, "Wild Steelbloom" }, { 3369, 120, "Grave Moss" },
        { 3356, 125, "Kingsblood" }, { 3357, 150, "Liferoot" }, { 3818, 160, "Fadeleaf" },
        { 3821, 170, "Goldthorn" }, { 3358, 185, "Khadgar's Whisker" }, { 3819, 195, "Wintersbite" },
        { 4625, 205, "Firebloom" }, { 8831, 210, "Purple Lotus" }, { 8836, 220, "Arthas' Tears" },
        { 8838, 230, "Sungrass" }, { 8839, 235, "Blindweed" }, { 8845, 245, "Ghost Mushroom" },
        { 8846, 250, "Gromsblood" }, { 13464, 260, "Golden Sansam" }, { 13463, 270, "Dreamfoil" },
        { 13465, 280, "Mountain Silversage" }, { 13466, 285, "Plaguebloom" }, { 13467, 290, "Icecap" },
        { 13468, 300, "Black Lotus" },
    },
    ore = {
        prof = "Mining",
        { 2770, 1, "Copper Ore" }, { 2771, 65, "Tin Ore" }, { 3340, 65, "Incendicite Ore" },
        { 4278, 75, "Lesser Bloodstone Ore" }, { 2775, 75, "Silver Ore" }, { 2772, 125, "Iron Ore" },
        { 2776, 155, "Gold Ore" }, { 3858, 175, "Mithril Ore" }, { 7911, 230, "Truesilver Ore" },
        { 11370, 230, "Dark Iron Ore" }, { 10620, 245, "Thorium Ore" }, { 10620, 275, "Thorium Ore", " (rich vein)" },
    },
}
-- the buff's spell id -> list
F.SPELLS = { [2383] = "herb", [8387] = "herb", [2580] = "ore", [8388] = "ore" }

F.COLORS = {
    red = { 1.00, 0.10, 0.10 }, orange = { 1.00, 0.50, 0.25 }, yellow = { 1.00, 1.00, 0.00 },
    green = { 0.25, 0.75, 0.25 }, gray = { 0.50, 0.50, 0.50 },
}

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- gathering colors: orange up to +24, yellow up to +49, green up to +99, then gray
function F.Color(skill, need)
    if type(skill) ~= "number" then return "yellow" end
    if skill < need then return "red" end
    if skill < need + 25 then return "orange" end
    if skill < need + 50 then return "yellow" end
    if skill < need + 100 then return "green" end
    return "gray"
end

-- my skill in the profession: rank, max (nil when the game does not tell)
function F.Skill(prof)
    local lines = OMQ.Alerts and OMQ.Alerts.ProfessionLines and OMQ.Alerts.ProfessionLines()
    for _, l in ipairs(lines or {}) do
        if l.key == prof and not secret(l.rank) and not secret(l.max) then return l.rank, l.max, l.name end
    end
end

local function itemName(id, fallback)
    local n
    if C_Item and C_Item.GetItemNameByID then
        local ok, v = pcall(C_Item.GetItemNameByID, id)
        if ok and type(v) == "string" and not secret(v) and v ~= "" then n = v end
    end
    if not n and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return n or fallback
end

local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then
        local ok, ic = pcall(C_Item.GetItemIconByID, id)
        if ok and ic and not secret(ic) then return ic end
    end
end

-- the lines for one list: { text, skill text, color name }
function F.Lines(kind, skill)
    local list = F.LISTS[kind]
    if not list then return nil end
    local out = {}
    for _, e in ipairs(list) do
        local icon = itemIcon(e[1])
        local text = itemName(e[1], e[3]) .. (e[4] or "")
        if icon then text = "|T" .. icon .. ":14:14:0:0|t " .. text end
        out[#out + 1] = { text, tostring(e[2]), F.Color(skill, e[2]) }
    end
    return out
end

function F.Add(tt, kind)
    local list = F.LISTS[kind]
    if not (tt and list and tt.AddLine) then return false end
    local rank, max, name = F.Skill(list.prof)
    tt:AddLine(" ")
    if rank then
        tt:AddDoubleLine((name or list.prof), rank .. "/" .. (max or "?"), 1, 0.82, 0, 1, 1, 1)
    else
        tt:AddLine(list.prof .. ": skill needed to gather", 1, 0.82, 0)
    end
    for _, l in ipairs(F.Lines(kind, rank)) do
        local c = F.COLORS[l[3]]
        tt:AddDoubleLine(l[1], l[2], c[1], c[2], c[3], c[1], c[2], c[3])
    end
    if tt.Show then tt:Show() end
    return true
end

function F.OnAura(tt, data)
    if type(data) ~= "table" then return end
    local id = data.id
    if id == nil or secret(id) then return end
    local kind = F.SPELLS[id]
    if kind then F.Add(tt, kind) end
end

OMQ:On("READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
        and Enum.TooltipDataType.UnitAura then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, function(tt, data)
            local ok, err = pcall(F.OnAura, tt, data)
            if not ok then OMQ:Error("finder tooltip", err) end
        end)
    end
end)
