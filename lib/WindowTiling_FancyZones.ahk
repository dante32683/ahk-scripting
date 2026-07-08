#Requires AutoHotkey v2.0+

; ============================================================
; POWERTOYS FANCYZONES TILING HOTKEYS
; ============================================================

#HotIf GetKeyState("CapsLock", "P") && g_TilingMode = "FancyZones"

; --- System snap (Alt+CapsLock → Win+Arrow) ---
; In Native mode these are replaced by tile functions in WindowTiling_Native.ahk.
!w:: Send("#{Up}")
!a:: Send("#{Left}")
!s:: Send("#{Down}")
!d:: Send("#{Right}")

; --- FancyZones zone assignments ---
*z:: Send("^!#" . CFG_FZ_Z)
*x:: Send("^!#" . CFG_FZ_X)
*p:: Send("^!#" . CFG_FZ_P)
*o:: Send("^!#" . CFG_FZ_O)
*f:: ToggleMaximize()
*g:: FloatCenter()

; --- Focus ---
*h:: FocusDirection("left")
*j:: FocusDirection("down")
*k:: FocusDirection("up")
*l:: FocusDirection("right")
Backspace:: FocusJumpBack()

; --- Layout cycle (Win+Right for next zone) ---
Tab:: Send("#{Right}")

#HotIf
