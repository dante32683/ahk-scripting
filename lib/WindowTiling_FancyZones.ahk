; ============================================================
; POWERTOYS FANCYZONES TILING HOTKEYS
; ============================================================

#HotIf GetKeyState("CapsLock", "P") && g_TilingMode = "FancyZones"

; --- FancyZones mappings ---
*z:: Send("^!#" . CFG_FZ_Z)
*x:: Send("^!#" . CFG_FZ_X)
*p:: Send("^!#" . CFG_FZ_P)
*o:: Send("^!#" . CFG_FZ_O)
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
