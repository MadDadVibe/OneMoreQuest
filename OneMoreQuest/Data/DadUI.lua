-- One More Quest: the Dad UI preset (decision 137), made with /omq dadui capture.
-- layout        Edit Mode layout as an export string (imported as the layout "Dad UI")
-- accountSettings  account wide Edit Mode settings { id, value }  (name as comment)
-- cvars         console variables { name, value }
-- chat          chat window font sizes { window, size }
local ADDON, OMQ = ...
OMQ = _G.OneMoreQuest

OMQ.DadUIPreset = {
    version = 1,
    layoutName = "Dad UI",
    layout = "5 0 59 0 0 0 7 7 UIParent 12.5 0.0 -1 ##$$%/&''%)$+#,# 0 1 0 7 7 UIParent 12.9 41.2 -1 ##$$%/&''%(#,# 0 2 0 7 7 UIParent 12.1 84.4 -1 ##$$%/&''%(#,# 0 3 1 5 5 UIParent -5.0 -77.0 -1 #$$$%/&('%(#,$ 0 4 1 5 5 UIParent -5.0 -77.0 -1 #$$$%/&('%(#,$ 0 5 1 1 4 UIParent 0.0 0.0 -1 ##$$%/&('%(#,$ 0 6 1 1 4 UIParent 0.0 -50.0 -1 ##$$%/&('%(#,$ 0 7 1 1 4 UIParent 0.0 -100.0 -1 ##$$%/&('%(#,$ 0 10 0 7 7 UIParent -226.5 129.6 -1 ##$$&&'% 0 11 0 7 7 UIParent 141.5 128.0 -1 ##$$&&'%,# 0 12 0 7 7 UIParent -418.5 41.6 -1 ##$$&('% 1 -1 0 4 4 UIParent 6.4 -231.9 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%(&( 3 0 0 0 0 UIParent -10.4 14.4 -1 $#3# 3 1 0 0 0 UIParent 196.4 15.2 -1 %#3# 3 2 0 8 8 UIParent -446.5 250.5 -1 %#&#3# 3 3 0 0 0 UIParent 736.8 -830.2 -1 '$(#)$-O.3/#1#3#5#6+7-7$8(9( 3 4 0 0 0 UIParent 222.2 -724.0 -1 ,#-A.#/#0#1#2(3#5#6(7-7$8(9( 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 1 5 5 UIParent 0.0 0.0 -1 -=.+/#4$5#6(7-7$8(9( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 7 7 UIParent -337.6 3.8 -1 # 5 -1 0 7 7 UIParent 446.4 127.8 -1 # 6 0 1 2 2 UIParent -255.0 -10.0 -1 ##$#%#&.(()( 6 1 1 2 2 UIParent -270.0 -155.0 -1 ##$#%#'+(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 1 7 7 UIParent 0.0 -4.0 -1 # 8 -1 0 6 6 UIParent 32.0 35.4 -1 #&$+$$%$&7 9 -1 0 7 7 UIParent -260.0 90.1 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 8 8 UIParent -119.4 86.6 -1 # 12 -1 1 2 2 UIParent -110.0 -275.0 -1 #K$#%# 13 -1 0 8 8 UIParent -9.8 41.0 -1 ##$#%$ 14 -1 0 7 7 UIParent 904.4 1.5 -1 ##$#%# 15 0 0 1 1 UIParent 1.1 -1.0 -1 &# 15 1 1 7 7 UIParent 0.0 17.0 -1 &- 16 -1 0 7 7 UIParent -326.0 252.4 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 1 5 5 UIParent 0.0 0.0 -1 #- 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 1 7 7 UIParent 0.0 310.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 1 7 7 UIParent 0.0 240.0 -1 ##$*%$&('%(-($)#+$,$-$ 20 2 1 7 7 UIParent 0.0 370.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 1 7 7 UIParent 420.0 430.0 -1 #$$$%#&('((-($)#*#+$,$-$.-.$ 21 -1 0 4 4 UIParent 5.2 -201.0 -1 ##%#&#'((()#*-*$+$,(-#.$/(0$1# 22 0 1 8 7 UIParent -457.0 336.0 -1 #$$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+% 23 -1 0 3 3 UIParent 2.8 -253.2 -1 ##$#%$&1'4($)U+$,$-#.'/# 24 -1 1 1 1 UIParent 0.0 -182.0 -1 # 25 -1 0 7 7 UIParent -335.3 84.4 -1 # 26 0 0 6 6 UIParent -26.0 -2.0 -1 #$ 26 1 1 3 5 BagsBar -30.0 5.0 -1 #$ 27 -1 1 4 4 Minimap -68.0 -68.0 -1 #- 28 -1 1 4 4 UIParent 0.0 0.0 -1 #( 29 0 0 7 7 UIParent 14.0 191.2 -1 #($U%$&s',($)$ 29 1 0 7 7 UIParent 14.8 167.6 -1 #($U%$&s'(($)$ 29 2 0 7 7 UIParent 14.8 219.6 -1 #($U%$&s'*($)$",
    accountSettings = {
        { 3, 1 },  -- ShowTargetAndFocus
        { 4, 1 },  -- ShowStanceBar
        { 5, 1 },  -- ShowPetActionBar
        { 6, 0 },  -- ShowPossessActionBar
        { 7, 1 },  -- ShowCastBar
        { 8, 0 },  -- ShowEncounterBar
        { 9, 1 },  -- ShowExtraAbilities
        { 10, 0 },  -- ShowBuffsAndDebuffs
        { 11, 0 },  -- DeprecatedShowDebuffFrame
        { 12, 1 },  -- ShowPartyFrames
        { 13, 1 },  -- ShowRaidFrames
        { 14, 0 },  -- ShowTalkingHeadFrame
        { 15, 0 },  -- ShowVehicleLeaveButton
        { 16, 0 },  -- ShowBossFrames
        { 17, 0 },  -- ShowArenaFrames
        { 18, 0 },  -- ShowLootFrame
        { 19, 1 },  -- ShowHudTooltip
        { 20, 0 },  -- ShowStatusTrackingBar2
        { 21, 0 },  -- ShowDurabilityFrame
        { 24, 0 },  -- ShowPetFrame
        { 25, 0 },  -- ShowTimerBars
        { 26, 0 },  -- ShowVehicleSeatIndicator
        { 27, 0 },  -- ShowArchaeologyBar
        { 28, 1 },  -- ShowCooldownViewer
        { 29, 1 },  -- ShowPersonalResourceDisplay
        { 30, 1 },  -- ShowEncounterEvents
        { 31, 1 },  -- ShowDamageMeter
        { 32, 1 },  -- ShowExternalDefensives
        { 33, 0 },  -- ShowRaidWarning
        { 34, 0 },  -- ShowTotemActionBar
        { 35, 0 },  -- ShowGroupFinder
        { 36, 0 },  -- ShowLossOfControl
        { 37, 0 },  -- ShowSwingTimer
        { 1, 14 },  -- General
        { 2, 18 },  -- Combat
        { 4, 16 },  -- Group
    },
    cvars = {
        { "autoLootDefault", "1" },
        { "cameraDistanceMaxZoomFactor", "4" },
        { "cameraSmoothStyle", "0" },
        { "combinedBags", "1" },
        { "deselectOnClick", "1" },
        { "damageMeterEnabled", "1" },
        { "damageMeterResetOnNewInstance", "1" },
        { "showSwingTimer", "1" },
        { "enableFloatingCombatText", "1" },
        { "enableMultiActionBars", "15" },
        { "ShowAllSpellRanks", "1" },
        { "showQuestLevel", "1" },
        { "showTimestamps", "%H:%M " },
        { "statusText", "1" },
        { "statusTextDisplay", "NUMERIC" },
        { "spellActivationOverlayOpacity", "1" },
        { "showPingsInChat", "0" },
        { "showPingsOnRaidFrames", "0" },
        { "nameplateShowEnemies", "1" },
        { "nameplateShowFriendlyPlayers", "1" },
        { "nameplateShowClassColor", "1" },
        { "nameplateShowOnlyNameForFriendlyPlayerUnits", "1" },
        { "nameplateUseClassColorForFriendlyPlayerUnitNames", "1" },
        { "nameplateCastBarDisplay", " _" },
        { "nameplateFriendlyPlayerAuraDisplay", " G" },
        { "nameplateThreatDisplay", " E" },
        { "nameplateShowSelf", "1" },
        { "raidFramesDisplayClassColor", "1" },
        { "raidFramesDisplayPowerBars", "1" },
        { "raidFramesDispelIndicatorAnimatedBorder", "1" },
        { "raidOptionDisplayPets", "1" },
    },
    chat = {
        { 1, 14 },
        { 2, 18 },
        { 4, 16 },
    },
}
