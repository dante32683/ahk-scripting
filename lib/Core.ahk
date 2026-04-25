#Requires AutoHotkey v2.0+

; Shared core: everything both machines use.
; Entry points must include:
;   - config.ahk
;   - lib/Eye202020.ahk (laptop) OR define _202020_* stubs (PC)
; before including this file.

; ============================================================
; OPTIMIZATION: PERFORMANCE & MEMORY
; ============================================================
ListLines 0
KeyHistory 0
ProcessSetPriority "AboveNormal"
SetTitleMatchMode 2
InstallKeybdHook
#UseHook True

; ============================================================
; AUTOMATIC ADMIN RIGHTS
; ============================================================
if not A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

; ============================================================
; VIRTUAL DESKTOP ACCESSOR (VDA)
; ============================================================
global GoToDesktopNumber        := 0
global MoveWindowToDesktopNumber := 0
global GetCurrentDesktopNumber   := 0
global GetWindowDesktopNumber    := 0
global VDA_IsLoaded              := false

VDA_DLL := A_ScriptDir "\VirtualDesktopAccessor.dll"
if !FileExist(VDA_DLL) {
    ShowOSD("VDA DLL not found at:`n" VDA_DLL "`nWorkspace 1-9 keys disabled.", 5000)
} else {
    hVDA := DllCall("LoadLibrary", "Str", VDA_DLL, "Ptr")
    if !hVDA {
        ShowOSD("VDA DLL failed to load! Bitness mismatch?`nNeed x64 DLL for 64-bit AHK.", 6000)
    } else {
        GoToDesktopNumber        := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GoToDesktopNumber",        "Ptr")
        MoveWindowToDesktopNumber := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "MoveWindowToDesktopNumber", "Ptr")
        GetCurrentDesktopNumber   := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetCurrentDesktopNumber",   "Ptr")
        GetWindowDesktopNumber    := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetWindowDesktopNumber",    "Ptr")

        if (GoToDesktopNumber && MoveWindowToDesktopNumber && GetCurrentDesktopNumber) {
            VDA_IsLoaded := true
        } else {
            ShowOSD("VDA loaded but functions missing.`nGet the latest release.", 6000)
        }
    }
}

; ============================================================
; FAILSAFE: SMART MODIFIER RELEASE
; ============================================================
OnExit ReleaseModifiers

ReleaseModifiers(ExitReason := "", ExitCode := "") {
    for mod in ["CapsLock", "Ctrl", "Shift", "Alt", "LWin", "RWin"]
        if !GetKeyState(mod, "P") && GetKeyState(mod)
            Send "{" mod " up}"
}

; ============================================================
; CAMERA TOGGLE — VARIABLES (entry point does WMI init)
; ============================================================
global PnPUtilPath := (A_Is64bitOS && A_PtrSize = 4)
    ? A_WinDir "\Sysnative\pnputil.exe"
    : A_WinDir "\System32\pnputil.exe"

ShowOSD("Script started!")

; ============================================================
; FOCUS EVENT HOOK (Zero-CPU Focus Tracking)
; ============================================================
global g_FocusCallbackPtr := CallbackCreate(TrackFocusHistory, "F")
global hFocusHook := DllCall("SetWinEventHook"
    , "UInt", 0x0003 ; EVENT_SYSTEM_FOREGROUND
    , "UInt", 0x0003
    , "Ptr", 0
    , "Ptr", g_FocusCallbackPtr
    , "UInt", 0
    , "UInt", 0
    , "UInt", 0)

global g_MoveStartCbPtr := CallbackCreate(_OnMoveStart, , 7)
global g_MoveStartHook  := DllCall("SetWinEventHook"
    , "UInt", 0x000A ; EVENT_SYSTEM_MOVESIZESTART
    , "UInt", 0x000A
    , "Ptr", 0
    , "Ptr", g_MoveStartCbPtr
    , "UInt", 0
    , "UInt", 0
    , "UInt", 0)
global g_MoveEndCbPtr := CallbackCreate(_OnMoveEnd, , 7)
global g_MoveEndHook  := DllCall("SetWinEventHook"
    , "UInt", 0x000B ; EVENT_SYSTEM_MOVESIZEEND
    , "UInt", 0x000B
    , "Ptr", 0
    , "Ptr", g_MoveEndCbPtr
    , "UInt", 0
    , "UInt", 0
    , "UInt", 0)

OnExit((*) => DllCall("UnhookWinEvent", "Ptr", hFocusHook))
OnExit((*) => DllCall("UnhookWinEvent", "Ptr", g_MoveStartHook))
OnExit((*) => DllCall("UnhookWinEvent", "Ptr", g_MoveEndHook))
OnExit(SaveDesktopMemory)
OnExit(_SaveLayouts)
OnExit(_202020_SaveState)
OnMessage(0x001A, _OnSettingChange)  ; WM_SETTINGCHANGE — work area resize (AppBar dock/undock)
OnMessage(0x0218, _OnPowerBroadcast) ; WM_POWERBROADCAST — wake from sleep
OnMessage(0x007E, _OnDisplayChange)  ; WM_DISPLAYCHANGE  — resolution change (fullscreen game exit)

SaveDesktopMemory(*) {
    for desk, hwnd in DesktopLastWindow {
        if hwnd && WinExist("ahk_id " hwnd)
            IniWrite(hwnd, DesktopMemoryFile, "DesktopLastWindow", "d" desk)
    }
}

_SaveLayouts(*) {
    global g_Layouts, g_LayoutFile
    try FileDelete(g_LayoutFile)
    for hwnd, layout in g_Layouts
        if _IsLiveWindow(hwnd) {
            IniWrite(layout[1], g_LayoutFile, hwnd, "xf")
            IniWrite(layout[2], g_LayoutFile, hwnd, "yf")
            IniWrite(layout[3], g_LayoutFile, hwnd, "wf")
            IniWrite(layout[4], g_LayoutFile, hwnd, "hf")
        }
}

_PersistLayout(hwnd) {
    global g_Layouts, g_LayoutFile
    if !g_Layouts.Has(hwnd)
        return
    layout := g_Layouts[hwnd]
    IniWrite(layout[1], g_LayoutFile, hwnd, "xf")
    IniWrite(layout[2], g_LayoutFile, hwnd, "yf")
    IniWrite(layout[3], g_LayoutFile, hwnd, "wf")
    IniWrite(layout[4], g_LayoutFile, hwnd, "hf")
}

_DeletePersistedLayout(hwnd) {
    global g_LayoutFile
    try IniDelete(g_LayoutFile, hwnd)
}

; ============================================================
; TILING GAP, BORDER & WINDOW HISTORY
; ============================================================
global TileGap        := 0
global FocusHistory   := []
global LayoutCycleIdx := Map()
global g_KeyLockActive := false
global g_UnlockBuf     := ""
global g_ScriptPaused  := false
global g_CapsN_LastHiddenHwnd := 0

global g_Layouts    := Map()   ; hwnd → [xf, yf, wf, hf]
global g_LayoutFile := A_Temp "\ahk_layouts.ini"
global g_LastDesktop := 0
global g_MoveSuppressUntil := Map()
global g_UserMoveActive    := Map()
global g_AutoRestoreTimers := Map()
global g_DebugRestore := false
global g_DebugLogFile := A_Temp "\ahk_restore_debug.log"

; ============================================================
; PER-DESKTOP FOCUS MEMORY
; ============================================================
global DesktopLastWindow := Map()
global DesktopMemoryFile := A_Temp "\ahk_desktop_memory.ini"

loop 9 {
    try {
        val := IniRead(DesktopMemoryFile, "DesktopLastWindow", "d" A_Index, "")
        if val != ""
            DesktopLastWindow[A_Index] := Integer(val)
    }
}

_LoadLayoutsFrom(file) {
    global g_Layouts
    try {
        sections := IniRead(file)
        loop parse, sections, "`n" {
            s := Trim(A_LoopField)
            if !s
                continue
            hwnd := Integer(s)
            if !_IsLiveWindow(hwnd)
                continue
            xf := IniRead(file, s, "xf", "")
            yf := IniRead(file, s, "yf", "")
            wf := IniRead(file, s, "wf", "")
            hf := IniRead(file, s, "hf", "")
            if xf != "" && Integer(wf) > 0
                g_Layouts[hwnd] := [Integer(xf), Integer(yf), Integer(wf), Integer(hf)]
        }
    }
}
_LoadLayoutsFrom(g_LayoutFile)
if !g_Layouts.Count
    _LoadLayoutsFrom(A_Temp "\ahk_window_layouts.ini")

if VDA_IsLoaded && GetCurrentDesktopNumber {
    g_LastDesktop := DllCall(GetCurrentDesktopNumber) + 1
}

SetTimer(_CheckLayoutRestores, 2000)

if g_DebugRestore
    try FileDelete(g_DebugLogFile)
_Dbg("script-start lastDesk=" g_LastDesktop " layouts=" g_Layouts.Count)

_Dbg(msg) {
    global g_DebugRestore, g_DebugLogFile
    if !g_DebugRestore
        return
    ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    ms := Mod(A_TickCount, 1000000)
    FileAppend(ts "." Format("{:06}", ms) " " msg "`n", g_DebugLogFile, "UTF-8")
}

_WinSig(hwnd) {
    title := ""
    proc := ""
    try title := WinGetTitle("ahk_id " hwnd)
    try proc := WinGetProcessName("ahk_id " hwnd)
    return "hwnd=" hwnd " proc=" proc " title=" StrReplace(title, "`n", " ")
}

_IsLiveWindow(hwnd) {
    return hwnd && DllCall("user32\IsWindow", "Ptr", hwnd, "Int")
}

_GetWindowState(hwnd, default := -2) {
    try return WinGetMinMax("ahk_id " hwnd)
    catch
        return default
}

_GetExpectedOuterPos(hwnd, x_factor, y_factor, w_factor, h_factor, &expX, &expY) {
    _GetMonitorForHwnd(hwnd, &L, &T, &R, &B)
    G  := TileGap
    MW := R - L
    MH := B - T

    slotL := L + (MW * x_factor // 100)
    slotR := L + (MW * (x_factor + w_factor) // 100)
    slotT := T + (MH * y_factor // 100)
    slotB := T + (MH * (y_factor + h_factor) // 100)

    visL := slotL + (x_factor = 0 ? G : G // 2)
    visR := slotR - (x_factor + w_factor >= 100 ? G : G // 2)
    visT := slotT + (y_factor = 0 ? G : G // 2)

    rect := Buffer(16)
    DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rect)
    actualL := NumGet(rect, 0, "Int"), actualT := NumGet(rect, 4, "Int")
    actualR := NumGet(rect, 8, "Int"), actualB := NumGet(rect, 12, "Int")

    dwmRect := Buffer(16)
    dwmOk := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", dwmRect, "UInt", 16) = 0
    visibleL := NumGet(dwmRect, 0, "Int"), visibleT := NumGet(dwmRect, 4, "Int")
    visibleR := NumGet(dwmRect, 8, "Int"), visibleB := NumGet(dwmRect, 12, "Int")

    if (dwmOk && visibleL >= actualL && visibleR <= actualR
              && visibleT >= actualT && visibleB <= actualB
              && (visibleR - visibleL) > 0 && (visibleB - visibleT) > 0) {
        offL := visibleL - actualL, offT := visibleT - actualT
        offR := actualR - visibleR
    } else {
        offL := 0, offT := 0, offR := 0
    }

    expX := visL - offL
    expY := visT - offT

    reqW := visR - visL
    curVisibleW := visibleR - visibleL
    if (curVisibleW > reqW) {
        if (x_factor = 0 && x_factor + w_factor = 50)
            expX := (visR - curVisibleW) - offL
        else if (x_factor = 50 && x_factor + w_factor = 100)
            expX := visL - offL
    }
}

_NeedsAutoRestore(hwnd, layout) {
    if !_IsLiveWindow(hwnd)
        return false
    WinGetPos(&wx, &wy, , , "ahk_id " hwnd)
    _GetExpectedOuterPos(hwnd, layout[1], layout[2], layout[3], layout[4], &expX, &expY)
    return Abs(wx - expX) > 12 || Abs(wy - expY) > 12
}

_AutoRestoreWindow(hwnd) {
    global g_Layouts, g_MoveSuppressUntil, g_UserMoveActive
    global g_ScriptPaused
    if g_ScriptPaused
        return
    if !g_Layouts.Has(hwnd) || !_IsLiveWindow(hwnd)
        return
    if g_UserMoveActive.Has(hwnd)
        return
    if g_MoveSuppressUntil.Has(hwnd) && g_MoveSuppressUntil[hwnd] > A_TickCount
        return
    if _GetWindowState(hwnd) != 0
        return
    layout := g_Layouts[hwnd]
    if !_NeedsAutoRestore(hwnd, layout)
        return
    _Dbg("auto-restore " _WinSig(hwnd))
    _ApplyLayout(layout[1], layout[2], layout[3], layout[4], hwnd, false)
}

_ScheduleAutoRestore(hwnd, delay := 120) {
    global g_AutoRestoreTimers
    if !g_AutoRestoreTimers.Has(hwnd)
        g_AutoRestoreTimers[hwnd] := () => _AutoRestoreWindow(hwnd)
    SetTimer(g_AutoRestoreTimers[hwnd], -delay)
}

; ============================================================
; OSD HELPER
; ============================================================
ShowOSD(text, ms := 1500) {
    ToolTip(text)
    if ms > 0
        SetTimer(() => ToolTip(), -ms)
}

ToggleScriptPaused() {
    global g_ScriptPaused
    if !IsSet(g_ScriptPaused)
        g_ScriptPaused := false
    g_ScriptPaused := !g_ScriptPaused
    Suspend(g_ScriptPaused)
    ShowOSD(g_ScriptPaused ? "Script Paused" : "Script Resumed", 1500)
}

_SendWinShift(key) {
    Send "{LWin down}{Shift down}"
    Send key
    Send "{Shift up}{LWin up}"
}

; ============================================================
; WINDOW MANAGEMENT HELPERS
; ============================================================
RunAsUser(target, args := "", workdir := "") {
    try {
        ComObject("Shell.Application").Windows().Item().Document.Application.ShellExecute(target, args, workdir)
    } catch {
        Run(target . (args ? " " . args : ""), workdir)
    }
}

_HwndOnCurrentDesktop(winSelector) {
    if !WinExist(winSelector)
        return 0
    if !(GetCurrentDesktopNumber && GetWindowDesktopNumber)
        return WinGetID(winSelector)
    curDesk := DllCall(GetCurrentDesktopNumber)
    for hwnd in WinGetList(winSelector) {
        try {
            if DllCall(GetWindowDesktopNumber, "Ptr", hwnd) = curDesk
                return hwnd
        }
    }
    return 0
}

_ActivateOrRunOnCurrentDesktop(winSelector, target, args := "", workdir := "") {
    if (hwnd := _HwndOnCurrentDesktop(winSelector)) {
        WinActivate("ahk_id " hwnd)
        return true
    }

    RunAsUser(target, args, workdir)

    deadline := A_TickCount + 8000
    while A_TickCount < deadline {
        if (hwnd := _HwndOnCurrentDesktop(winSelector)) {
            WinActivate("ahk_id " hwnd)
            return true
        }
        Sleep(50)
    }
    return false
}

; ============================================================
; KEYBOARD LOCK HELPERS
; ============================================================
_KL_On() {
    global g_KeyLockActive, g_UnlockBuf
    g_KeyLockActive := true
    g_UnlockBuf     := ""
    BlockInput "On"
    ShowOSD("Keyboard Locked", 0)
}

_KL_Off() {
    global g_KeyLockActive, g_UnlockBuf
    g_KeyLockActive := false
    g_UnlockBuf     := ""
    BlockInput "Off"
    ShowOSD("Keyboard Unlocked", 1500)
}

_KL_CheckUnlock(ch) {
    global g_KeyLockActive, g_UnlockBuf
    if !g_KeyLockActive
        return
    g_UnlockBuf .= ch
    if (StrLen(g_UnlockBuf) > 6)
        g_UnlockBuf := SubStr(g_UnlockBuf, 2)
    if (g_UnlockBuf = "unlock")
        _KL_Off()
}

SoftReset() {
    global g_KeyLockActive
    global g_CapsN_LastHiddenHwnd
    ReleaseModifiers()
    ToolTip()
    if g_KeyLockActive
        _KL_Off()

    if g_CapsN_LastHiddenHwnd && WinExist("ahk_id " g_CapsN_LastHiddenHwnd) {
        if !DllCall("IsWindowVisible", "Ptr", g_CapsN_LastHiddenHwnd) {
            WinShow(g_CapsN_LastHiddenHwnd)
            WinActivate(g_CapsN_LastHiddenHwnd)
        }
    }
    g_CapsN_LastHiddenHwnd := 0
}

GetActiveMonitorWorkArea(&L, &T, &R, &B) {
    try {
        WinGetPos(&wx, &wy, &ww, &wh, "A")
        cx := wx + ww // 2
        cy := wy + wh // 2
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
            if (cx >= ml && cx < mr && cy >= mt && cy < mb) {
                L := ml, T := mt, R := mr, B := mb
                return
            }
        }
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &L, &T, &R, &B)
}

_GetMonitorForHwnd(hwnd, &L, &T, &R, &B) {
    try {
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        cx := wx + ww // 2
        cy := wy + wh // 2
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
            if (cx >= ml && cx < mr && cy >= mt && cy < mb) {
                L := ml, T := mt, R := mr, B := mb
                return
            }
        }
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &L, &T, &R, &B)
}

PrepareWindow() {
    state := WinGetMinMax("A")
    if (state = 1 || state = -1)
        WinRestore("A")
}

_ApplyLayout(x_factor, y_factor, w_factor, h_factor, overrideHwnd := 0, persist := true) {
    global g_MoveSuppressUntil
    if overrideHwnd {
        hwnd := overrideHwnd
        if !_IsLiveWindow(hwnd)
            return
        state := _GetWindowState(hwnd)
        if (state = 1 || state = -1)
            WinRestore("ahk_id " hwnd)
        _GetMonitorForHwnd(hwnd, &L, &T, &R, &B)
    } else {
        if !WinExist("A")
            return
        hwnd := WinGetID("A")
        PrepareWindow()
        GetActiveMonitorWorkArea(&L, &T, &R, &B)
    }

    mode := persist ? "store" : "restore"
    g_MoveSuppressUntil[hwnd] := A_TickCount + 1500
    G   := TileGap
    MW  := R - L
    MH  := B - T

    slotL := L + (MW * x_factor // 100)
    slotR := L + (MW * (x_factor + w_factor) // 100)
    slotT := T + (MH * y_factor // 100)
    slotB := T + (MH * (y_factor + h_factor) // 100)

    visL := slotL + (x_factor = 0 ? G : G // 2)
    visR := slotR - (x_factor + w_factor >= 100 ? G : G // 2)
    visT := slotT + (y_factor = 0 ? G : G // 2)
    visB := slotB - (y_factor + h_factor >= 100 ? G : G // 2)

    rect := Buffer(16)
    DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rect)
    actualL := NumGet(rect, 0, "Int"), actualT := NumGet(rect, 4, "Int")
    actualR := NumGet(rect, 8, "Int"), actualB := NumGet(rect, 12, "Int")

    dwmRect := Buffer(16)
    dwmOk := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", dwmRect, "UInt", 16) = 0
    visibleL := NumGet(dwmRect, 0, "Int"), visibleT := NumGet(dwmRect, 4, "Int")
    visibleR := NumGet(dwmRect, 8, "Int"), visibleB := NumGet(dwmRect, 12, "Int")

    if (dwmOk && visibleL >= actualL && visibleR <= actualR
              && visibleT >= actualT && visibleB <= actualB
              && (visibleR - visibleL) > 0 && (visibleB - visibleT) > 0) {
        offL := visibleL - actualL, offT := visibleT - actualT
        offR := actualR - visibleR, offB := actualB - visibleB
    } else {
        offL := 0, offT := 0, offR := 0, offB := 0
    }

    WinMove(visL - offL, visT - offT, (visR - visL) + offL + offR, (visB - visT) + offT + offB, "ahk_id " hwnd)

    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", dwmRect, "UInt", 16)
    vW := NumGet(dwmRect, 8, "Int") - NumGet(dwmRect, 0, "Int")
    reqW := visR - visL
    if (vW > reqW) {
        if (x_factor = 0 && x_factor + w_factor = 50) {
            newVisL := visR - vW
            WinMove(newVisL - offL, visT - offT, , , "ahk_id " hwnd)
        }
        else if (x_factor = 50 && x_factor + w_factor = 100) {
            WinMove(visL - offL, visT - offT, , , "ahk_id " hwnd)
        }
    }

    _Dbg("apply mode=" mode " " _WinSig(hwnd) " desk?=" (GetWindowDesktopNumber ? DllCall(GetWindowDesktopNumber, "Ptr", hwnd) + 1 : 0)
        " mon=[" L "," T "," R "," B "] target=[" visL "," visT "," visR "," visB "] offs=[" offL "," offT "," offR "," offB "]"
        " pct=[" x_factor "," y_factor "," w_factor "," h_factor "]")
    g_Layouts[hwnd] := [x_factor, y_factor, w_factor, h_factor]
    if persist
        _PersistLayout(hwnd)
}

_RestoreDesktop(n) {
    global g_Layouts
    global g_ScriptPaused
    if g_ScriptPaused
        return
    if !VDA_IsLoaded || !GetWindowDesktopNumber
        return
    _Dbg("restore-desktop-start desk=" n " tracked=" g_Layouts.Count)
    for hwnd, layout in g_Layouts.Clone() {
        if !_IsLiveWindow(hwnd) {
            _Dbg("restore-desktop-drop dead " hwnd)
            g_Layouts.Delete(hwnd)
            continue
        }
        try {
            winDesk := DllCall(GetWindowDesktopNumber, "Ptr", hwnd) + 1
            if winDesk != n {
                _Dbg("restore-desktop-skip desk-mismatch want=" n " got=" winDesk " " _WinSig(hwnd))
                continue
            }
        }
        state := _GetWindowState(hwnd)
        if state != 0
            continue
        _ApplyLayout(layout[1], layout[2], layout[3], layout[4], hwnd, false)
    }
    _Dbg("restore-desktop-end desk=" n)
}

_RestoreAllDesktops() {
    global g_Layouts
    global g_ScriptPaused
    if g_ScriptPaused
        return
    for hwnd, layout in g_Layouts.Clone() {
        if !_IsLiveWindow(hwnd) {
            g_Layouts.Delete(hwnd)
            continue
        }
        state := _GetWindowState(hwnd)
        if state != 0
            continue
        try _ApplyLayout(layout[1], layout[2], layout[3], layout[4], hwnd, false)
    }
}

_RestoreCurrentDesktop() {
    if !VDA_IsLoaded || !GetCurrentDesktopNumber
        return
    _RestoreDesktop(DllCall(GetCurrentDesktopNumber) + 1)
}

_ScheduleDesktopRestore(n) {
    _Dbg("schedule-desktop-restore desk=" n)
    SetTimer(() => _RestoreDesktop(n), -400)
    SetTimer(() => _RestoreDesktop(n), -900)
    SetTimer(() => _RestoreDesktop(n), -1600)
    SetTimer(() => _RestoreDesktop(n), -2500)
}

_ScheduleRestoreCurrentDesktop(delay := 600) {
    _Dbg("schedule-current-desktop delay=" delay)
    SetTimer(() => _ScheduleDesktopRestore(DllCall(GetCurrentDesktopNumber) + 1), -delay)
}

_OnSettingChange(wParam, *) {
    global g_ScriptPaused
    if g_ScriptPaused
        return
    if wParam = 0x2F {
        _Dbg("wm-settingchange SPI_SETWORKAREA")
        SetTimer(_RestoreAllDesktops, -300)
        _ScheduleRestoreCurrentDesktop(1200)
    }
}

_OnPowerBroadcast(wParam, lParam, *) {
    global g_ScriptPaused
    if g_ScriptPaused
        return
    if wParam = 0x4 {
        _202020_Reset("sleep")
        return
    }
    if wParam = 0x8013 {
        try {
            setting := lParam
            if setting {
                guidBuf := Buffer(16)
                DllCall("RtlMoveMemory", "Ptr", guidBuf, "Ptr", setting, "UPtr", 16)
                data := NumGet(setting + 20, "UChar")
                guidStr := ""
                try {
                    guidStr := Format("{{{:08X}-{:04X}-{:04X}-{:02X}{:02X}-{:02X}{:02X}{:02X}{:02X}{:02X}{:02X}}}"
                        , NumGet(guidBuf, 0, "UInt")
                        , NumGet(guidBuf, 4, "UShort")
                        , NumGet(guidBuf, 6, "UShort")
                        , NumGet(guidBuf, 8, "UChar"), NumGet(guidBuf, 9, "UChar")
                        , NumGet(guidBuf, 10, "UChar"), NumGet(guidBuf, 11, "UChar"), NumGet(guidBuf, 12, "UChar")
                        , NumGet(guidBuf, 13, "UChar"), NumGet(guidBuf, 14, "UChar"), NumGet(guidBuf, 15, "UChar"))
                }
                if (StrUpper(guidStr) = StrUpper("{6FE69556-704A-47A0-8F24-C28D936FDA47}")) {
                    if (data = 0)
                        _202020_Reset("display-off")
                }
            }
        }
        return
    }
    if wParam = 0x12 || wParam = 0x7 {
        SetTimer(_RestoreAllDesktops, -5000)
        _ScheduleRestoreCurrentDesktop(6200)
    }
}

_OnDisplayChange(*) {
    global g_ScriptPaused
    if g_ScriptPaused
        return
    SetTimer(_RestoreAllDesktops, -1000)
    _ScheduleRestoreCurrentDesktop(1800)
}

_OnMoveStart(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    global g_UserMoveActive
    if idObject != 0 || !g_Layouts.Has(hwnd)
        return
    g_UserMoveActive[hwnd] := true
}

_OnMoveEnd(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    global g_UserMoveActive
    if idObject != 0
        return
    if !g_Layouts.Has(hwnd)
        return
    try {
        g_UserMoveActive.Delete(hwnd)
        if _GetWindowState(hwnd) != 0
            return
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        _GetMonitorForHwnd(hwnd, &L, &T, &R, &B)
        MW := R - L, MH := B - T
        if !MW || !MH
            return
        g_Layouts[hwnd] := [
            Round((wx - L) * 100 / MW),
            Round((wy - T) * 100 / MH),
            Round(ww       * 100 / MW),
            Round(wh       * 100 / MH)
        ]
        _PersistLayout(hwnd)
    }
}

_CheckLayoutRestores() {
    global g_Layouts, g_MoveSuppressUntil, g_UserMoveActive
    global g_ScriptPaused
    if g_ScriptPaused
        return
    for hwnd, layout in g_Layouts {
        if !_IsLiveWindow(hwnd)
            continue
        if g_UserMoveActive.Has(hwnd)
            continue
        if g_MoveSuppressUntil.Has(hwnd) && g_MoveSuppressUntil[hwnd] > A_TickCount
            continue
        if _GetWindowState(hwnd) != 0
            continue
        if _NeedsAutoRestore(hwnd, layout)
            _ScheduleAutoRestore(hwnd)
    }
}

_HandleDesktopChange() {
    global g_LastDesktop
    global g_ScriptPaused
    if g_ScriptPaused
        return
    if !VDA_IsLoaded || !GetCurrentDesktopNumber
        return
    try currentDesk := DllCall(GetCurrentDesktopNumber) + 1
    catch
        return
    if !currentDesk || currentDesk = g_LastDesktop
        return
    g_LastDesktop := currentDesk
    SetTimer(() => RestoreFocusOnDesktop(currentDesk), -150)
    _ScheduleDesktopRestore(currentDesk)
}

TileLeft()        => _ApplyLayout(0, 0, 50, 100)
TileRight()       => _ApplyLayout(50, 0, 50, 100)
TileTopLeft()     => _ApplyLayout(0, 0, 50, 50)
TileTopRight()    => _ApplyLayout(50, 0, 50, 50)
TileBottomLeft()  => _ApplyLayout(0, 50, 50, 50)
TileBottomRight() => _ApplyLayout(50, 50, 50, 50)
TileLeftThird()   => _ApplyLayout(0, 0, 33, 100)
TileCenterThird() => _ApplyLayout(33, 0, 34, 100)
TileRightThird()  => _ApplyLayout(67, 0, 33, 100)
TileLeft60()      => _ApplyLayout(0, 0, 60, 100)
TileRight40()     => _ApplyLayout(60, 0, 40, 100)
FloatCenter()     => _ApplyLayout(12, 12, 75, 75)

ToggleMaximize() {
    if !WinExist("A")
        return
    if WinGetMinMax("A") = 1
        WinRestore("A")
    else
        WinMaximize("A")
}

TogglePin() {
    if !WinExist("A")
        return
    WinSetAlwaysOnTop(-1, "A")
    isPinned := WinGetExStyle("A") & 0x8
    ShowOSD(isPinned ? "Pinned (Always on Top)" : "Unpinned")
}

GotoDesktop(n) {
    global g_LastDesktop
    if !VDA_IsLoaded {
        ShowOSD("VDA not loaded — install the DLL first!")
        return
    }
    currentDesk := DllCall(GetCurrentDesktopNumber) + 1
    if WinExist("A")
        DesktopLastWindow[currentDesk] := WinGetID("A")

    g_LastDesktop := n
    DllCall(GoToDesktopNumber, "Int", n - 1)

    SetTimer(() => RestoreFocusOnDesktop(n), -150)
    _ScheduleDesktopRestore(n)
}

RestoreFocusOnDesktop(n) {
    if DesktopLastWindow.Has(n) {
        hwnd := DesktopLastWindow[n]
        if WinExist("ahk_id " hwnd) {
            if WinGetMinMax("ahk_id " hwnd) = -1
                WinRestore("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
            return
        }
        DesktopLastWindow.Delete(n)
    }
}

MoveToDesktop(n) {
    if !WinExist("A")
        return
    if VDA_IsLoaded {
        hwnd := WinGetID("A")
        DllCall(MoveWindowToDesktopNumber, "Ptr", hwnd, "Int", n - 1)
        DesktopLastWindow[n] := hwnd
        GotoDesktop(n)
    } else {
        ShowOSD("VDA not loaded — install the DLL first!")
    }
}

FocusDirection(dir) {
    if !WinExist("A")
        return
    curHwnd := WinGetID("A")
    WinGetPos(&cx, &cy, &cw, &ch, "ahk_id " curHwnd)
    curX := cx + cw // 2
    curY := cy + ch // 2

    bestHwnd := 0
    bestScore := 0x7FFFFFFF

    list := WinGetList()
    for index, hwnd in list {
        if hwnd = curHwnd
            continue
        if WinGetMinMax("ahk_id " hwnd) = -1
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        if WinGetExStyle("ahk_id " hwnd) & 0x80
            continue
        cloaked := 0
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
        if cloaked
            continue

        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        wX := wx + ww // 2
        wY := wy + wh // 2

        valid := false
        dist := 0
        if dir = "left" && wX < curX {
            dist := curX - wX, valid := true
        } else if dir = "right" && wX > curX {
            dist := wX - curX, valid := true
        } else if dir = "up" && wY < curY {
            dist := curY - wY, valid := true
        } else if dir = "down" && wY > curY {
            dist := wY - curY, valid := true
        }

        if valid {
            score := dist + (index * 50)
            if score < bestScore {
                bestScore := score
                bestHwnd := hwnd
            }
        }
    }

    if bestHwnd {
        WinActivate("ahk_id " bestHwnd)
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " bestHwnd)
        DllCall("SetCursorPos", "Int", wx + ww // 2, "Int", wy + wh // 2)
    }
}

TrackFocusHistory(hHook, event, hwnd, *) {
    global g_ScriptPaused
    try {
        if g_ScriptPaused
            return
        _HandleDesktopChange()
        if hwnd = 0
            return
        if FocusHistory.Length > 0 && FocusHistory[FocusHistory.Length] = hwnd
            return
        FocusHistory.Push(hwnd)
        if FocusHistory.Length > 30
            FocusHistory.RemoveAt(1)
    }
}

FocusJumpBack() {
    curHwnd := WinExist("A") ? WinGetID("A") : 0
    loop {
        if FocusHistory.Length = 0
            return
        hwnd := FocusHistory.Pop()
        if hwnd != curHwnd && WinExist("ahk_id " hwnd) {
            WinActivate("ahk_id " hwnd)
            return
        }
    }
}

CycleLayout() {
    if !WinExist("A")
        return
    static layouts := [TileLeft, TileRight, TileLeft60, TileRight40, TileLeftThird, TileRightThird, TileCenterThird, FloatCenter]
    static names   := ["Left Half", "Right Half", "Left 60%", "Right 40%", "Left Third", "Right Third", "Center Third", "Float Center"]
    hwnd := WinGetID("A")
    idx := LayoutCycleIdx.Has(hwnd) ? Mod(LayoutCycleIdx[hwnd] + 1, layouts.Length) : 0
    LayoutCycleIdx[hwnd] := idx
    layouts[idx + 1]()
    ShowOSD(names[idx + 1])
}

; ============================================================
; EMERGENCY KILL SWITCH
; ============================================================
^Esc:: {
    ReleaseModifiers()
    ExitApp()
}

; ============================================================
; PAUSE / RESUME
; ============================================================
#SuspendExempt
#HotIf GetKeyState("CapsLock", "P")
+Space:: ToggleScriptPaused()
#HotIf
#SuspendExempt False

; ============================================================
; CAPSLOCK CONFIGURATION
; ============================================================
*CapsLock:: return

!+CapsLock:: {
    if GetKeyState("CapsLock", "T")
        SetCapsLockState "Off"
    else
        SetCapsLockState "On"
}

; ============================================================
; SECTION 1: TEXT EXPANSION
; ============================================================
; ::@@:: SendText(CFG_Email)
::#ph:: SendText(CFG_Phone)
::\deg::°
::\delta::Δ
::\pi::π
::\approx::≈
::\theta::θ
::\sigma::σ

; ============================================================
; SECTION 2: THE "HYPER" LAYER  (CapsLock held = Hyper)
; (Desktop switching/moving is machine-specific and lives in entry points.)
; ============================================================
#HotIf GetKeyState("CapsLock", "P")

; --- Arrow navigation ---
w::Up
a::Left
s::Down
d::Right

; --- Tiling: halves & quadrants ---
*z:: TileLeft()
*x:: TileRight()
*F1:: TileTopLeft()
*F2:: TileTopRight()
*F3:: TileBottomLeft()
*F4:: TileBottomRight()

; --- Tiling: thirds & splits ---
*y:: TileLeft60()
*u:: TileLeftThird()
*i:: TileCenterThird()
*o:: TileRightThird()
*p:: TileRight40()

; --- Layout cycle ---
Tab:: CycleLayout()

; --- Focus ---
*h:: FocusDirection("left")
*j:: FocusDirection("down")
*k:: FocusDirection("up")
*l:: FocusDirection("right")
Backspace:: FocusJumpBack()

; --- Window control ---
*b:: {
    static _minimized := false
    if _minimized {
        WinMinimizeAllUndo()
        _minimized := false
    } else {
        WinMinimizeAll()
        _minimized := true
    }
}
*+b:: _202020_TogglePrompt()
*f:: ToggleMaximize()
*g:: FloatCenter()
*`:: TogglePin()
*q:: {
    if WinExist("A")
        WinClose("A")
}
Delete:: {
    hwnd := WinExist("A") ? WinGetID("A") : 0
    if hwnd && g_Layouts.Has(hwnd) {
        g_Layouts.Delete(hwnd)
        _DeletePersistedLayout(hwnd)
        ShowOSD("Layout cleared")
    }
}

; --- Media ---
[::Media_Prev
]::Media_Next
Space::Media_Play_Pause
*c:: _SendWinShift("c")
*!l:: {
    static _lastToggle := 0
    if (A_TickCount - _lastToggle < 400)
        return
    _lastToggle := A_TickCount
    g_KeyLockActive ? _KL_Off() : _KL_On()
}

; --- Apps ---
*v:: {
    codePath := EnvGet("LocalAppData") "\Programs\Microsoft VS Code\Code.exe"
    if FileExist(codePath) {
        _ActivateOrRunOnCurrentDesktop("ahk_exe Code.exe", codePath, "--new-window")
    } else {
        try _ActivateOrRunOnCurrentDesktop("ahk_exe Code.exe", "Code.exe", "--new-window")
    }
}

*n:: {
    global g_CapsN_LastHiddenHwnd
    prevDetect := A_DetectHiddenWindows
    DetectHiddenWindows True
    if g_CapsN_LastHiddenHwnd
        && WinExist("ahk_id " g_CapsN_LastHiddenHwnd)
        && !DllCall("IsWindowVisible", "Ptr", g_CapsN_LastHiddenHwnd) {
        WinShow(g_CapsN_LastHiddenHwnd)
        WinActivate("ahk_id " g_CapsN_LastHiddenHwnd)
    } else {
        activeHwnd := WinActive("A")
        if activeHwnd {
            g_CapsN_LastHiddenHwnd := activeHwnd
            WinHide(activeHwnd)
        }
    }
    DetectHiddenWindows prevDetect
}

*m:: _ActivateOrRunOnCurrentDesktop("ahk_exe Taskmgr.exe", "taskmgr.exe")

*e:: {
    existing := Map()
    for hwnd in WinGetList("ahk_exe explorer.exe ahk_class CabinetWClass")
        existing[hwnd] := true

    Run "explorer.exe"

    deadline := A_TickCount + 5000
    while A_TickCount < deadline {
        for hwnd in WinGetList("ahk_exe explorer.exe ahk_class CabinetWClass") {
            if !existing.Has(hwnd) {
                WinActivate("ahk_id " hwnd)
                return
            }
        }
        Sleep(50)
    }
}

*t:: {
    if GetKeyState("Shift", "P") {
        Run 'wt.exe -w new', EnvGet("USERPROFILE")
        return
    }

    _QuakeTerminal() {
        WinActivate("ahk_exe WindowsTerminal.exe")
        _ApplyLayout(0, 0, 100, 40)
    }

    if WinActive("ahk_exe Code.exe") {
        Send "^``"
        return
    }

    if WinExist("ahk_exe WindowsTerminal.exe") {
        wtHwnd := WinGetID("ahk_exe WindowsTerminal.exe")
        onCurrentDesk := true
        if GetCurrentDesktopNumber && GetWindowDesktopNumber {
            curDesk := DllCall(GetCurrentDesktopNumber)
            wtDesk  := DllCall(GetWindowDesktopNumber, "Ptr", wtHwnd)
            onCurrentDesk := (curDesk = wtDesk)
        }
        if onCurrentDesk {
            if WinActive("ahk_exe WindowsTerminal.exe") && WinGetMinMax("ahk_exe WindowsTerminal.exe") != -1
                WinMinimize("ahk_exe WindowsTerminal.exe")
            else
                _QuakeTerminal()
        } else {
            Run 'wt.exe', EnvGet("USERPROFILE")
            if WinWait("ahk_exe WindowsTerminal.exe", , 10)
                _QuakeTerminal()
        }
    } else {
        Run 'wt.exe', EnvGet("USERPROFILE")
        if WinWait("ahk_exe WindowsTerminal.exe", , 10)
            _QuakeTerminal()
    }
}

*r:: SoftReset()

*+r:: {
    RunWait "taskkill.exe /F /IM explorer.exe", , "Hide"
    Sleep(300)
    Run A_WinDir "\explorer.exe"
}

Esc:: {
    ToolTip("Reloading script...")
    ReleaseModifiers()
    Sleep(200)
    Run('cmd.exe /c taskkill /F /PID ' DllCall("GetCurrentProcessId") ' & start \"\" \"' A_ScriptFullPath '\"', , "Hide")
    ExitApp()
}

#HotIf

; ============================================================
; KEYBOARD LOCK — intercept keys while locked
; ============================================================
#HotIf g_KeyLockActive
u:: _KL_CheckUnlock("u")
n:: _KL_CheckUnlock("n")
l:: _KL_CheckUnlock("l")
o:: _KL_CheckUnlock("o")
c:: _KL_CheckUnlock("c")
k:: _KL_CheckUnlock("k")
*!l:: _KL_Off()
#HotIf

