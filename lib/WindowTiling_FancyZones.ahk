; ============================================================
; POWERTOYS FANCYZONES TILING HOTKEYS
; ============================================================

#HotIf GetKeyState("CapsLock", "P") && g_TilingMode = "FancyZones"

; --- FancyZones mappings ---
*z:: Send("^!#1")
*x:: Send("^!#2")
*p:: Send("^!#0")
*o:: Send("^!#4")
*f:: ToggleMaximize()
*g:: FloatCenter()

; --- Apps ---
*y:: _ActivateOrRunOnCurrentDesktop("ahk_exe AppleMusic.exe", "AppleMusic.exe")

; --- Focus ---
*h:: FocusDirection("left")
*j:: FocusDirection("down")
*k:: FocusDirection("up")
*l:: FocusDirection("right")
Backspace:: FocusJumpBack()

; --- Layout cycle (Win+Right for next zone) ---
Tab:: Send("#{Right}")

#HotIf
