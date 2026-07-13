#Requires AutoHotkey v2.0+
global g_PerfStartupTick := A_TickCount
#SingleInstance Force
#WinActivateForce

A_MaxHotkeysPerInterval := 500
A_HotkeyInterval := 1000

#Include custom/config.ahk
#Include lib/Core.ahk
#Include *i custom/Core_custom.ahk
#Include Remap.ahk
#Include lib/Autocorrect_Logic.ahk
#Include lib/Build_Autocorrect.ahk
#Include *i lib/Autocorrect.ahk
#UseHook true

; ============================================================
; LAPTOP-SPECIFIC HYPER LAYER EXTENSIONS
; ============================================================
#HotIf GetKeyState("CapsLock", "P")

; Virtual desktop switching
Left:: {
    if GetCurrentDesktopNumber
        GotoDesktop(Max(1, DllCall(GetCurrentDesktopNumber)))
    else
        Send "^#{Left}"
}
Right:: {
    if GetCurrentDesktopNumber
        GotoDesktop(Min(9, DllCall(GetCurrentDesktopNumber) + 2))
    else
        Send "^#{Right}"
}

; Number keys (1–9) are handled by Core.ahk via CFG_NumberKeys.
; Set CFG_NumberKeys := "desktops" in config.ahk (the default) to keep this behavior.

#HotIf

#Include *i custom/Master_custom.ahk

Perf_Log("init_complete", A_TickCount - g_PerfStartupTick)

if CFG_TestMode {
    ExitApp(0)
}

