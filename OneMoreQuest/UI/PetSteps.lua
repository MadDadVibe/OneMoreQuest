local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

local P = {}
OMQ.PetSteps = P

-- Mute pet sounds while the own pet is out (decision 718, taken over from PR #9 by PatrickMotz).
-- The sound setting from before is kept in OMQDB.petSoundWas, so it comes back also after a game crash
-- (like Sound_EnableMusic in Stats/Rhythm.lua).
local CVAR = "Sound_EnablePetSounds"

local function value(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, result = pcall(fn, ...)
    if not ok then return "error" end
    if issecretvalue and issecretvalue(result) then return "secret" end
    if result == nil then return "nil" end
    return tostring(result)
end

local function cvarValue()
    if type(GetCVar) ~= "function" then return nil end
    local ok, result = pcall(GetCVar, CVAR)
    if not ok or (issecretvalue and issecretvalue(result)) or result == nil then return nil end
    return tostring(result)
end

local function hasPet()
    if type(UnitExists) ~= "function" then return false end
    local ok, result = pcall(UnitExists, "pet")
    return ok and not (issecretvalue and issecretvalue(result)) and result == true
end

function P.Restore()
    local was = OMQ.db and OMQ.db.petSoundWas
    if not was then return end
    if cvarValue() == "0" and type(SetCVar) == "function" then pcall(SetCVar, CVAR, was) end
    OMQ.db.petSoundWas = nil
end

function P.Apply()
    if not OMQ.db then return end
    if not (OMQ.db.options and OMQ.db.options.petSteps == true and hasPet()) then
        P.Restore()
        return
    end
    local current = cvarValue()
    if not current or current == "0" or type(SetCVar) ~= "function" then return end
    OMQ.db.petSoundWas = current
    if not pcall(SetCVar, CVAR, "0") then OMQ.db.petSoundWas = nil end
end

function P.SetEnabled()
    P.Apply()
end

local function probe()
    local pet = value(UnitExists, "pet")
    local petName = pet == "true" and value(UnitName, "pet") or "none"
    OMQ:Print("petsteps probe: pet=" .. petName .. ", Sound_EnablePetSounds=" .. value(GetCVar, CVAR)
        .. ", FootstepSounds=" .. value(GetCVar, "FootstepSounds"))
    OMQ:Print("GetCVar=" .. (type(GetCVar) == "function" and "yes" or "no")
        .. ", SetCVar=" .. (type(SetCVar) == "function" and "yes" or "no")
        .. ", MuteSoundFile=" .. (type(MuteSoundFile) == "function" and "yes" or "no")
        .. ", UnmuteSoundFile=" .. (type(UnmuteSoundFile) == "function" and "yes" or "no"))
end

OMQ:RegisterCommand("petsteps", function(arg)
    if (arg or ""):lower():match("^%s*probe%s*$") then
        probe()
    else
        OMQ:Print("Use /omq petsteps probe to check pet sound controls.")
    end
end, "probe pet sound controls")

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_PET")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGOUT" then
        P.Restore()
    elseif event ~= "UNIT_PET" or unit == "player" then
        P.Apply()
    end
end)

OMQ:On("DB_READY", P.Apply)
