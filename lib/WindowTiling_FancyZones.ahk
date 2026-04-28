; ============================================================
; POWERTOYS FANCYZONES TILING HOTKEYS
; ============================================================

; Disable the automatic retiler timer
SetTimer(_CheckLayoutRestores, 0)

; Set the mode to disable restoration functions
g_TilingMode := "FancyZones"

#HotIf GetKeyState("CapsLock", "P")

; --- FancyZones mappings ---
*z:: Send("^!#1")
*x:: Send("^!#2")
*g:: Send("^!#3")
*f:: Send("^!#0")

; --- Apps ---
*y:: _ActivateOrRunOnCurrentDesktop("ahk_exe AppleMusic.exe", "AppleMusic.exe")

; --- Layout cycle (Win+Right for next zone) ---
Tab:: Send("#{Right}")

#HotIf
