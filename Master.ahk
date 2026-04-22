#Requires AutoHotkey v2.0+
#SingleInstance Force
#WinActivateForce
#Include config.ahk
#Include Remap.ahk

; ============================================================
; OPTIMIZATION: PERFORMANCE & MEMORY
; ============================================================
ListLines 0
KeyHistory 0
ProcessSetPriority "BelowNormal"
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
; CAMERA TOGGLE — VARIABLES
; ============================================================
global PnPUtilPath := (A_Is64bitOS && A_PtrSize = 4)
    ? A_WinDir "\Sysnative\pnputil.exe"
    : A_WinDir "\System32\pnputil.exe"

; Pre-initialize WMI connection for fast camera toggling
global WMI_Service := 0
try {
    WMI_Service := ComObjGet("winmgmts:")
} catch {
    ShowOSD("Warning: Failed to initialize WMI service.`nCamera toggle may not work.", 3000)
}

ShowOSD("Script started!")

; ============================================================
; FOCUS EVENT HOOK (Zero-CPU Focus Tracking)
; ============================================================
; Store the callback pointer so AHK's GC cannot free the underlying
; ref-counted object while SetWinEventHook is still calling it.
; Losing this pointer lets the callback be freed mid-session, causing
; memory corruption that silently breaks hotkeys over time.
global g_FocusCallbackPtr := CallbackCreate(TrackFocusHistory, "F")
global hFocusHook := DllCall("SetWinEventHook"
    , "UInt", 0x0003 ; EVENT_SYSTEM_FOREGROUND
    , "UInt", 0x0003
    , "Ptr", 0
    , "Ptr", g_FocusCallbackPtr
    , "UInt", 0
    , "UInt", 0
    , "UInt", 0)

; Drag-end hook: EVENT_SYSTEM_MOVESIZEEND fires only on user-interactive moves,
; never on programmatic SetWindowPos/WinMove — no debounce needed.
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
global TileGap        := 0    ; px gap around/between tiled windows — set to 4 to re-enable
global FocusHistory   := []
global LayoutCycleIdx := Map()
global g_KeyLockActive := false
global g_UnlockBuf     := ""
global g_Layouts    := Map()   ; hwnd → [xf, yf, wf, hf]  (0–100 percentages of monitor work area)
global g_LayoutFile := A_Temp "\ahk_layouts.ini"
global g_LastDesktop := 0
global g_MoveSuppressUntil := Map() ; hwnd → tickcount until auto-restore should ignore our own WinMove
global g_UserMoveActive    := Map() ; hwnds currently being user-dragged/resized
global g_AutoRestoreTimers := Map() ; hwnd → reusable timer callback for deferred auto-restore
global g_DebugRestore := false
global g_DebugLogFile := A_Temp "\ahk_restore_debug.log"

; ============================================================
; PER-DESKTOP FOCUS MEMORY
; Stores the last focused window HWND for each desktop number.
; Populated on every desktop switch, restored after landing.
; Persisted to %TEMP%\ahk_desktop_memory.ini across reloads.
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

; ── Restore persisted tile layouts from the previous AHK session ─────────
; HWNDs are stable across Caps+Esc reloads (windows don't close, only AHK dies).
; Stale entries (closed windows) are skipped on load and pruned on save.
; Tries new filename first, then old filename as a one-time migration fallback.
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
if !g_Layouts.Count  ; nothing loaded — try old filename (one-time migration)
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
; ms = 0  →  stays visible until the next ShowOSD call
; Uses the default AutoHotkey tooltip.
; ============================================================
ShowOSD(text, ms := 1500) {
    ToolTip(text)
    if ms > 0
        SetTimer(() => ToolTip(), -ms)
}

; ============================================================
; WINDOW MANAGEMENT HELPERS
; ============================================================

; Launch a program as a non-elevated user from an elevated script.
; This works by asking the shell (explorer.exe) to execute the command.
RunAsUser(target, args := "", workdir := "") {
    try {
        ComObject("Shell.Application").Windows().Item().Document.Application.ShellExecute(target, args, workdir)
    } catch {
        Run(target . (args ? " " . args : ""), workdir)
    }
}

; ============================================================
; KEYBOARD LOCK HELPERS
; ============================================================
_KL_On() {
    global g_KeyLockActive, g_UnlockBuf
    g_KeyLockActive := true
    g_UnlockBuf     := ""
    BlockInput "On"
    ShowOSD("⌨ Keyboard Locked", 0)
}

_KL_Off() {
    global g_KeyLockActive, g_UnlockBuf
    g_KeyLockActive := false
    g_UnlockBuf     := ""
    BlockInput "Off"
    ShowOSD("⌨ Keyboard Unlocked", 1500)
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

    ; 1. Define the logical "Slot" on the screen
    slotL := L + (MW * x_factor // 100)
    slotR := L + (MW * (x_factor + w_factor) // 100)
    slotT := T + (MH * y_factor // 100)
    slotB := T + (MH * (y_factor + h_factor) // 100)

    ; 2. Determine visible boundaries (with halved gaps for internal edges)
    visL := slotL + (x_factor = 0 ? G : G // 2)
    visR := slotR - (x_factor + w_factor >= 100 ? G : G // 2)
    visT := slotT + (y_factor = 0 ? G : G // 2)
    visB := slotB - (y_factor + h_factor >= 100 ? G : G // 2)

    ; 3. DYNAMIC BORDER COMPENSATION (DWM API)
    ; Query actual vs visible rect to find invisible border thickness
    rect := Buffer(16)
    DllCall("user32\GetWindowRect", "Ptr", hwnd, "Ptr", rect)
    actualL := NumGet(rect, 0, "Int"), actualT := NumGet(rect, 4, "Int")
    actualR := NumGet(rect, 8, "Int"), actualB := NumGet(rect, 12, "Int")

    dwmRect := Buffer(16)
    dwmOk := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", dwmRect, "UInt", 16) = 0
    visibleL := NumGet(dwmRect, 0, "Int"), visibleT := NumGet(dwmRect, 4, "Int")
    visibleR := NumGet(dwmRect, 8, "Int"), visibleB := NumGet(dwmRect, 12, "Int")

    ; Calculate current border offsets.
    ; Guard: cloaked windows (inactive desktops) return all-zero rect from DWM.
    ; Wrong offsets corrupt position far more than skipping invisible-border compensation does.
    if (dwmOk && visibleL >= actualL && visibleR <= actualR
              && visibleT >= actualT && visibleB <= actualB
              && (visibleR - visibleL) > 0 && (visibleB - visibleT) > 0) {
        offL := visibleL - actualL, offT := visibleT - actualT
        offR := actualR - visibleR, offB := actualB - visibleB
    } else {
        offL := 0, offT := 0, offR := 0, offB := 0
    }

    ; 4. Execute WinMove
    WinMove(visL - offL, visT - offT, (visR - visL) + offL + offR, (visB - visT) + offT + offB, "ahk_id " hwnd)

    ; 5. OVERFLOW PROTECTION (For Discord/Spotify)
    ; If window hits min-width, adjust position to respect the "middle" line
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

; Restore all tracked windows on desktop n to their stored layouts.
; Called 400ms after switching to desktop n (animation finishes ~300ms).
; Also prunes dead HWNDs from the layout map.
_RestoreDesktop(n) {
    global g_Layouts
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
        if state != 0  ; skip maximized/minimized/unavailable-transition-state
        {
            _Dbg("restore-desktop-skip state=" state " " _WinSig(hwnd))
            continue
        }
        _Dbg("restore-desktop-apply desk=" n " " _WinSig(hwnd) " pct=[" layout[1] "," layout[2] "," layout[3] "," layout[4] "]")
        _ApplyLayout(layout[1], layout[2], layout[3], layout[4], hwnd, false)
    }
    _Dbg("restore-desktop-end desk=" n)
}

; Restore ALL tracked windows on ALL desktops.
; Used for system-event triggers (work-area change, wake, display change) because
; Windows repositions windows on every desktop, not just the active one.
; All three handlers share this function reference → they auto-debounce each other.
_RestoreAllDesktops() {
    global g_Layouts
    _Dbg("restore-all-start tracked=" g_Layouts.Count)
    for hwnd, layout in g_Layouts.Clone() {
        if !_IsLiveWindow(hwnd) {
            _Dbg("restore-all-drop dead " hwnd)
            g_Layouts.Delete(hwnd)
            continue
        }
        state := _GetWindowState(hwnd)
        if state != 0
        {
            _Dbg("restore-all-skip state=" state " " _WinSig(hwnd))
            continue
        }
        _Dbg("restore-all-apply " _WinSig(hwnd) " pct=[" layout[1] "," layout[2] "," layout[3] "," layout[4] "]")
        try _ApplyLayout(layout[1], layout[2], layout[3], layout[4], hwnd, false)
    }
    _Dbg("restore-all-end")
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

; WM_SETTINGCHANGE: SPI_SETWORKAREA (0x2F) fires when AppBar (MenuBar/taskbar) changes
; the reserved work area. Work area is already updated when the message arrives.
_OnSettingChange(wParam, *) {
    if wParam = 0x2F {
        _Dbg("wm-settingchange SPI_SETWORKAREA")
        SetTimer(_RestoreAllDesktops, -300)
        _ScheduleRestoreCurrentDesktop(1200)
    }
}

; WM_POWERBROADCAST: safety net for wake-from-sleep.
; 5s delay: lets AppBars finish their TaskbarCreated re-registration cycle.
; Same function reference as other handlers → debounces if SPI_SETWORKAREA also fires.
_OnPowerBroadcast(wParam, *) {
    if wParam = 0x12 || wParam = 0x7 {
        _Dbg("wm-powerbroadcast wParam=" wParam)
        SetTimer(_RestoreAllDesktops, -5000)
        _ScheduleRestoreCurrentDesktop(6200)
    }
}

; WM_DISPLAYCHANGE: fullscreen game resolution change. 1s delay for driver re-init.
_OnDisplayChange(*) {
    _Dbg("wm-displaychange")
    SetTimer(_RestoreAllDesktops, -1000)
    _ScheduleRestoreCurrentDesktop(1800)
}

; Drag-end callback (EVENT_SYSTEM_MOVESIZEEND).
; Only fires for user-interactive moves, never for programmatic WinMove.
; Only updates layout for windows already being tracked (tiled at least once).
_OnMoveStart(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    global g_UserMoveActive
    if idObject != 0 || !g_Layouts.Has(hwnd)
        return
    g_UserMoveActive[hwnd] := true
}

_OnMoveEnd(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    global g_UserMoveActive
    if idObject != 0  ; OBJID_WINDOW = 0; skip menu/scrollbar/etc. events
        return
    if !g_Layouts.Has(hwnd)
        return
    try {
        g_UserMoveActive.Delete(hwnd)
        if _GetWindowState(hwnd) != 0  ; skip maximized/minimized/unavailable-transition-state
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
        _Dbg("move-end-update " _WinSig(hwnd) " pct=[" g_Layouts[hwnd][1] "," g_Layouts[hwnd][2] "," g_Layouts[hwnd][3] "," g_Layouts[hwnd][4] "]")
        _PersistLayout(hwnd)
    }
}

_CheckLayoutRestores() {
    global g_Layouts, g_MoveSuppressUntil, g_UserMoveActive
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
    if !VDA_IsLoaded || !GetCurrentDesktopNumber
        return
    try currentDesk := DllCall(GetCurrentDesktopNumber) + 1
    catch
        return
    if !currentDesk || currentDesk = g_LastDesktop
        return
    _Dbg("desktop-change old=" g_LastDesktop " new=" currentDesk)
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

    ; Update memory for the desktop we're leaving (buffered in Map, written to disk on exit)
    currentDesk := DllCall(GetCurrentDesktopNumber) + 1  ; VDA is 0-indexed
    if WinExist("A")
        DesktopLastWindow[currentDesk] := WinGetID("A")

    _Dbg("goto-desktop from=" currentDesk " to=" n)
    g_LastDesktop := n
    DllCall(GoToDesktopNumber, "Int", n - 1)

    ; After the switch animation, restore focus then layout on the destination desktop
    SetTimer(() => RestoreFocusOnDesktop(n), -150)
    _ScheduleDesktopRestore(n)
}

RestoreFocusOnDesktop(n) {
    if DesktopLastWindow.Has(n) {
        hwnd := DesktopLastWindow[n]
        ; Make sure the window still exists and isn't minimized to nothing
        if WinExist("ahk_id " hwnd) {
            if WinGetMinMax("ahk_id " hwnd) = -1
                WinRestore("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
            return
        }
        ; Window was closed since we last saw it — forget it
        DesktopLastWindow.Delete(n)
    }
}

MoveToDesktop(n) {
    if !WinExist("A")
        return
    if VDA_IsLoaded {
        hwnd := WinGetID("A")
        DllCall(MoveWindowToDesktopNumber, "Ptr", hwnd, "Int", n - 1)
        DesktopLastWindow[n] := hwnd  ; keep focus on the moved window, not the old remembered one
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
    for index, hwnd in list {  ; index = Z-order depth
        if hwnd = curHwnd
            continue
        if WinGetMinMax("ahk_id " hwnd) = -1
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)   ; must be visible
            continue
        if WinGetExStyle("ahk_id " hwnd) & 0x80           ; skip tool windows
            continue
        cloaked := 0
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
        if cloaked  ; skip windows on other virtual desktops (DWM cloaks them)
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
            ; Factor in Z-order: +50px per depth level prevents selecting
            ; hidden windows over topmost ones
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
    try {
        _HandleDesktopChange()
        if hwnd = 0
            return
        _Dbg("focus " _WinSig(hwnd))
        ; Only track actual window changes
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
; CAPSLOCK CONFIGURATION
; ============================================================
*CapsLock:: return

+CapsLock:: {
    if GetKeyState("CapsLock", "T")
        SetCapsLockState "Off"
    else
        SetCapsLockState "On"
}

; ============================================================
; SECTION 1: TEXT EXPANSION
; ============================================================
::@@:: SendText(CFG_Email)
::#ph:: SendText(CFG_Phone)
::\deg::°
::\delta::Δ
::\pi::π
::\approx::≈
::\theta::θ
::\sigma::σ

; ============================================================
; SECTION 2: THE "HYPER" LAYER  (CapsLock held = Hyper)
;
; NAVIGATION        WINDOW TILING          WINDOW CONTROL
;   W = Up            Z  = Left half         F   = Toggle maximize
;   A = Left          X  = Right half        G   = Float & center (75%)
;   S = Down          F1 = Top-left 1/4      Q   = Close window
;   D = Right         F2 = Top-right 1/4     `   = Pin / unpin (always on top)
;                     F3 = Bottom-left 1/4   Tab = Cycle layouts
;                     F4 = Bottom-right 1/4
; FOCUS             EXTENDED TILING
;   H = Left          Y = Left 60%
;   J = Down          U = Left 1/3
;   K = Up            I = Center 1/3
;   L = Right         O = Right 1/3
;   Backspace = Jump  P = Right 40%
;     to prev window
; WORKSPACE                                  SYSTEM
;   1-9    = Go to virtual desktop           M   = Task Manager
;   Alt+1-9= Move window to virtual desktop  T   = Terminal (focus or open)
;   Left   = Prev desktop                    E   = Open File Explorer
;   Right  = Next desktop                    N   = Apple Music (Toggle)
;                                            R   = Restart Explorer
;                                            Esc = Reload script
; MEDIA
;   [  = Prev track    ]  = Next track    Space = Play/Pause
;   C  = Color picker (PowerToys)         V     = VS Code
; ============================================================
#HotIf GetKeyState("CapsLock", "P")

; --- Arrow navigation ---
w::Up
a::Left
s::Down
d::Right

; --- Workspace: prev / next (routed through GotoDesktop for focus memory) ---
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

; --- Workspace: jump to virtual desktop 1-9 ---
1:: GotoDesktop(1)
2:: GotoDesktop(2)
3:: GotoDesktop(3)
4:: GotoDesktop(4)
5:: GotoDesktop(5)
6:: GotoDesktop(6)
7:: GotoDesktop(7)
8:: GotoDesktop(8)
9:: GotoDesktop(9)

; --- Move window to virtual desktop 1-9 and follow (CapsLock+Shift+1-9) ---
*+1:: MoveToDesktop(1)
*+2:: MoveToDesktop(2)
*+3:: MoveToDesktop(3)
*+4:: MoveToDesktop(4)
*+5:: MoveToDesktop(5)
*+6:: MoveToDesktop(6)
*+7:: MoveToDesktop(7)
*+8:: MoveToDesktop(8)
*+9:: MoveToDesktop(9)

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
*c:: Send "#+c"
*!l:: {
    ; Debounce: key-down repeats if held — without this a single long press
    ; toggles lock on→off→on, leaving the keyboard locked unintentionally.
    static _lastToggle := 0
    if (A_TickCount - _lastToggle < 400)
        return
    _lastToggle := A_TickCount
    g_KeyLockActive ? _KL_Off() : _KL_On()
}

*v:: {
    codePath := EnvGet("LocalAppData") "\Programs\Microsoft VS Code\Code.exe"
    if WinExist("ahk_exe Code.exe")
        WinActivate("ahk_exe Code.exe")
    else if FileExist(codePath) {
        RunAsUser(codePath)
        if WinWait("ahk_exe Code.exe", , 10)
            WinActivate("ahk_exe Code.exe")
    } else {
        try RunAsUser("Code.exe")
    }
}

; --- Apps ---
*n:: {
    static lastHwnd := 0
    
    prevDetect := A_DetectHiddenWindows
    DetectHiddenWindows True
    
    ; If the window we last hid is still hidden, bring it back
    if lastHwnd && WinExist("ahk_id " lastHwnd) && !DllCall("IsWindowVisible", "Ptr", lastHwnd) {
        WinShow(lastHwnd)
        WinActivate(lastHwnd)
    } else {
        ; Otherwise, hide the currently active window and remember it
        activeHwnd := WinActive("A")
        if activeHwnd {
            lastHwnd := activeHwnd
            WinHide(activeHwnd)
        }
    }
    
    DetectHiddenWindows prevDetect
}

*m:: {
    if WinExist("ahk_exe Taskmgr.exe")
        WinActivate("ahk_exe Taskmgr.exe")
    else {
        Run "taskmgr.exe"
        if WinWait("ahk_exe Taskmgr.exe", , 5)
            WinActivate("ahk_exe Taskmgr.exe")
    }
}
*e:: {
    existing := Map()
    for hwnd in WinGetList("ahk_exe explorer.exe ahk_class CabinetWClass")
        existing[hwnd] := true

    Run "explorer.exe"

    ; Wait for a new window HWND to appear, then focus it
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
        _ApplyLayout(0, 0, 100, 40)   ; full width, top 40% of screen
    }

    if WinActive("ahk_exe Code.exe") {
        Send "^``"
        return
    }

    if WinExist("ahk_exe WindowsTerminal.exe") {
        wtHwnd := WinGetID("ahk_exe WindowsTerminal.exe")
        ; Only toggle WT if it's on the current desktop — otherwise open a new one
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

*+r:: {
    ; Force-kill ALL explorer instances (/F = force, /IM = by image name).
    ; Plain ProcessClose can leave ghost instances alive long enough that the
    ; subsequent Run sees an existing explorer and opens a folder window instead
    ; of starting a fresh shell. taskkill /F nukes everything immediately.
    RunWait "taskkill.exe /F /IM explorer.exe", , "Hide"
    Sleep(300)   ; let Windows finish tearing down the old shell
    Run A_WinDir "\explorer.exe"   ; full path — starts fresh as the shell (no window)
}

*\:: {
    try {
        service := ComObject("Schedule.Service")
        service.Connect()
        folder := service.GetFolder("\")
        task := folder.GetTask("Tailscale Auto Switch")

        if (task.Enabled) {
            task.Enabled := false
            if ProcessExist("v2rayN.exe")
                RunWait("taskkill.exe /F /IM v2rayN.exe /T", , "Hide")
            ShowOSD("VPN Auto-Switch: OFF", 2000)
        } else {
            task.Enabled := true
            ShowOSD("VPN Auto-Switch: ON", 2000)
        }
    } catch Error as err {
        ShowOSD("VPN Toggle Error: " err.Message, 3000)
    }
}

Esc:: {
    ToolTip("Reloading script...")
    ReleaseModifiers()
    Sleep(200)
    ; Force-kill this script before reloading to ensure no hung instance remains
    Run('cmd.exe /c taskkill /F /PID ' DllCall("GetCurrentProcessId") ' & start "" "' A_ScriptFullPath '"', , "Hide")
    ExitApp()
}

#HotIf

; ============================================================
; KEYBOARD LOCK — intercept keys while locked
; Suppresses all key input. Tracks "unlock" sequence to release.
; Unlock: type "unlock" OR press Caps+Alt+L.
; The Caps+Alt+L backup here handles the edge case where
; GetKeyState("CapsLock","P") fails to evaluate inside the Hyper
; layer context (e.g. after BlockInput interaction), so the user
; is never permanently stuck.
; ============================================================
#HotIf g_KeyLockActive
u:: _KL_CheckUnlock("u")
n:: _KL_CheckUnlock("n")
l:: _KL_CheckUnlock("l")
o:: _KL_CheckUnlock("o")
c:: _KL_CheckUnlock("c")
k:: _KL_CheckUnlock("k")
*!l:: _KL_Off()   ; Backup unlock: Caps+Alt+L always works even if CapsLock state detection fails
#HotIf

; ============================================================
; SECTION 3: COPILOT KEY REBIND — CAMERA TOGGLE
; ============================================================
#+F23:: {
    global CFG_CameraID, PnPUtilPath, WMI_Service

    if !WMI_Service {
        ShowOSD("WMI not initialized — check script start!")
        return
    }

    ShowOSD("Toggling Camera...", 0)
    exitCode := 1

    ; Re-query current device state from WMI each time — avoids stale cache
    currentlyOn := false
    try {
        escapedID := StrReplace(CFG_CameraID, "\", "\\")
        query := WMI_Service.ExecQuery("SELECT ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PNPDeviceID = '" escapedID "'")
        for device in query {
            currentlyOn := (device.ConfigManagerErrorCode = 0)
        }
        ; Release WMI objects to prevent locking the device
        device := ""
        query := ""
    }

    try {
        tempFile := A_Temp "\camera_toggle_error.txt"
        if FileExist(tempFile)
            FileDelete(tempFile)

        if currentlyOn {
            ; Try pnputil first, redirect output to temp file
            exitCode := RunWait(A_ComSpec ' /c ""' PnPUtilPath '" /disable-device "' CFG_CameraID '" > "' tempFile '" 2>&1"', , "Hide")
            if (exitCode != 0) {
                ; Fallback to PowerShell (NonInteractive prevents hanging on prompts)
                psCmd := "Disable-PnpDevice -InstanceId '" CFG_CameraID "' -Confirm:$false -ErrorAction Stop"
                exitCode := RunWait(A_ComSpec ' /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' psCmd '" >> "' tempFile '" 2>&1', , "Hide")
            }
            if (exitCode = 0)
                ShowOSD("RGB Camera Disabled")
        } else {
            exitCode := RunWait(A_ComSpec ' /c ""' PnPUtilPath '" /enable-device "' CFG_CameraID '" > "' tempFile '" 2>&1"', , "Hide")
            if (exitCode != 0) {
                psCmd := "Enable-PnpDevice -InstanceId '" CFG_CameraID "' -Confirm:$false -ErrorAction Stop"
                exitCode := RunWait(A_ComSpec ' /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' psCmd '" >> "' tempFile '" 2>&1', , "Hide")
            }
            if (exitCode = 0)
                ShowOSD("RGB Camera Enabled")
        }
    } catch Error as err {
        ShowOSD("Execution Error: " err.Message, 3000)
        return
    }

    if (exitCode != 0) {
        errStr := ""
        if FileExist(tempFile) {
            errText := FileRead(tempFile)
            if InStr(errText, "pending system reboot") {
                errStr := "Device is locked. A system reboot is required."
            } else {
                ; Strip boilerplate and newlines
                errText := StrReplace(errText, "Microsoft PnP Utility", "")
                errText := RegExReplace(errText, "s)^[\s\r\n]+", "") ; Trim leading whitespace/newlines
                errText := StrReplace(errText, "`r`n", " ")
                errStr := Trim(errText)
                if (StrLen(errStr) > 80)
                    errStr := SubStr(errStr, 1, 80) "..."
            }
        }
        ShowOSD("Failed (Code " exitCode "): " errStr, 5000)
    }
}


