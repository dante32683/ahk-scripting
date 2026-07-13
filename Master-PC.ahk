#Requires AutoHotkey v2.0+
global g_PerfStartupTick := A_TickCount
#SingleInstance Force
#WinActivateForce

#Include custom/config.ahk

; PC defaults to monitor-based number keys; config.ahk can still override this.
if !IsSet(CFG_NumberKeys)
    global CFG_NumberKeys := "monitors"

#Include lib/Core.ahk
#Include *i custom/Core_custom.ahk

; PC doesn't use virtual desktops. Disable VDA to avoid unnecessary logic.
global VDA_IsLoaded := false
global GetCurrentDesktopNumber := 0
global GetWindowDesktopNumber := 0
global GoToDesktopNumber := 0
global MoveWindowToDesktopNumber := 0
#Include Remap.ahk
#Include lib/Autocorrect_Logic.ahk
#Include lib/Build_Autocorrect.ahk
#Include *i lib/Autocorrect.ahk

; ============================================================
; PC HYPER LAYER EXTENSIONS
; ============================================================
#HotIf GetKeyState("CapsLock", "P")

; CapsLock+Left/Right: focus prev/next monitor (cycles)
Left:: {
    monitorCount := MonitorGetCount()
    currentMonitorIndex := 1
    if WinExist("A") {
        WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "A")
        centerX := windowX + windowWidth // 2, centerY := windowY + windowHeight // 2
        loop monitorCount {
            MonitorGetWorkArea(A_Index, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom)
            if centerX >= monitorLeft && centerX < monitorRight && centerY >= monitorTop && centerY < monitorBottom {
                currentMonitorIndex := A_Index
                break
            }
        }
    }
    _FocusMonitor(Mod(currentMonitorIndex - 2 + monitorCount, monitorCount) + 1)
}

Right:: {
    monitorCount := MonitorGetCount()
    currentMonitorIndex := 1
    if WinExist("A") {
        WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "A")
        centerX := windowX + windowWidth // 2, centerY := windowY + windowHeight // 2
        loop monitorCount {
            MonitorGetWorkArea(A_Index, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom)
            if centerX >= monitorLeft && centerX < monitorRight && centerY >= monitorTop && centerY < monitorBottom {
                currentMonitorIndex := A_Index
                break
            }
        }
    }
    _FocusMonitor(Mod(currentMonitorIndex, monitorCount) + 1)
}

; Number keys (1–3) handled by Core.ahk via CFG_NumberKeys := "monitors".

#HotIf

#Include *i custom/Master-PC_custom.ahk

Perf_Log("init_complete", A_TickCount - g_PerfStartupTick)

if CFG_TestMode {
    ExitApp(0)
}
