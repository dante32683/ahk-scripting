#Requires AutoHotkey v2.0+
#SingleInstance Force
#WinActivateForce

#Include config.ahk

; Stubs: no 20-20-20 on PC (must exist for Core hotkeys/handlers)
_202020_Reset(*) => 0
_202020_IsEnabled() => false
_202020_TogglePrompt() => 0
_202020_SaveState(*) => 0

#Include lib/Core.ahk

; PC doesn't use virtual desktops. Disable VDA to avoid unnecessary logic.
global VDA_IsLoaded := false
global GetCurrentDesktopNumber := 0
global GetWindowDesktopNumber := 0
global GoToDesktopNumber := 0
global MoveWindowToDesktopNumber := 0
#Include Remap.ahk
#Include lib/Build_Autocorrect.ahk
#Include lib/Autocorrect_Logic.ahk
#Include lib/Autocorrect.ahk

; ============================================================
; MULTI-MONITOR HELPERS (PC-specific)
; ============================================================

MoveWindowToMonitor(n) {
    if !WinExist("A")
        return
    monCount := MonitorGetCount()
    if n < 1 || n > monCount {
        ShowOSD("Monitor " n " doesn't exist (have " monCount ")")
        return
    }
    hwnd := WinGetID("A")
    MonitorGetWorkArea(n, &L, &T, &R, &B)
    if g_Layouts.Has(hwnd) {
        layout := g_Layouts[hwnd]
        xf := layout[1], yf := layout[2], wf := layout[3], hf := layout[4]
    } else {
        xf := 12, yf := 12, wf := 75, hf := 75
    }
    MW := R - L, MH := B - T
    x := L + (MW * xf // 100)
    y := T + (MH * yf // 100)
    w := MW * wf // 100
    h := MH * hf // 100
    if WinGetMinMax("ahk_id " hwnd) != 0
        WinRestore("ahk_id " hwnd)
    WinMove(x, y, w, h, "ahk_id " hwnd)
    g_Layouts[hwnd] := [xf, yf, wf, hf]
    _PersistLayout(hwnd)
    ShowOSD("→ Monitor " n)
}

FocusMonitor(n) {
    monCount := MonitorGetCount()
    if n < 1 || n > monCount
        return
    MonitorGetWorkArea(n, &L, &T, &R, &B)
    i := FocusHistory.Length
    while i > 0 {
        hwnd := FocusHistory[i]
        if WinExist("ahk_id " hwnd) && WinGetMinMax("ahk_id " hwnd) != -1 {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            cx := wx + ww // 2
            cy := wy + wh // 2
            if cx >= L && cx < R && cy >= T && cy < B {
                WinActivate("ahk_id " hwnd)
                DllCall("SetCursorPos", "Int", cx, "Int", cy)
                return
            }
        }
        i--
    }
    for hwnd in WinGetList() {
        if WinGetMinMax("ahk_id " hwnd) = -1
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        cx := wx + ww // 2, cy := wy + wh // 2
        if cx >= L && cx < R && cy >= T && cy < B {
            WinActivate("ahk_id " hwnd)
            return
        }
    }
}

; ============================================================
; PC HYPER LAYER EXTENSIONS
; ============================================================
#HotIf GetKeyState("CapsLock", "P")

; CapsLock+Left/Right: focus prev/next monitor (cycles)
Left:: {
    monCount := MonitorGetCount()
    curMon := 1
    if WinExist("A") {
        WinGetPos(&wx, &wy, &ww, &wh, "A")
        cx := wx + ww // 2, cy := wy + wh // 2
        loop monCount {
            MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
            if cx >= L && cx < R && cy >= T && cy < B {
                curMon := A_Index
                break
            }
        }
    }
    FocusMonitor(Mod(curMon - 2 + monCount, monCount) + 1)
}

Right:: {
    monCount := MonitorGetCount()
    curMon := 1
    if WinExist("A") {
        WinGetPos(&wx, &wy, &ww, &wh, "A")
        cx := wx + ww // 2, cy := wy + wh // 2
        loop monCount {
            MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
            if cx >= L && cx < R && cy >= T && cy < B {
                curMon := A_Index
                break
            }
        }
    }
    FocusMonitor(Mod(curMon, monCount) + 1)
}

1:: FocusMonitor(1)
2:: FocusMonitor(2)
3:: FocusMonitor(3)

*!1:: MoveWindowToMonitor(1)
*!2:: MoveWindowToMonitor(2)
*!3:: MoveWindowToMonitor(3)

#HotIf

