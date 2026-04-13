#Requires AutoHotkey v2.0+
#SingleInstance Force
#WinActivateForce
#Include config.ahk

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
global hFocusHook := DllCall("SetWinEventHook"
    , "UInt", 0x0003 ; EVENT_SYSTEM_FOREGROUND
    , "UInt", 0x0003
    , "Ptr", 0
    , "Ptr", CallbackCreate(TrackFocusHistory, "F")
    , "UInt", 0
    , "UInt", 0
    , "UInt", 0)

OnExit((*) => DllCall("UnhookWinEvent", "Ptr", hFocusHook))
OnExit(SaveDesktopMemory)

SaveDesktopMemory(*) {
    for desk, hwnd in DesktopLastWindow {
        if hwnd && WinExist("ahk_id " hwnd)
            IniWrite(hwnd, DesktopMemoryFile, "DesktopLastWindow", "d" desk)
    }
}

; ============================================================
; TILING GAP, BORDER & WINDOW HISTORY
; ============================================================
global TileGap        := 4
global FocusHistory   := []
global LayoutCycleIdx := Map()
global WindowOpacity  := Map()
global g_KeyLockActive := false
global g_UnlockBuf     := ""
global g_WindowLayouts := Map()   ; hwnd → [xf, yf, wf, hf] — remembers last tile per window

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

; ============================================================
; OSD HELPER
; ms = 0  →  stays visible until the next ShowOSD call
; Uses Windows 11 Fluent transient-acrylic material (DWMSBT_TRANSIENTWINDOW).
; DwmExtendFrameIntoClientArea turns black pixels into DWM glass holes
; that the acrylic backdrop fills. Click-through, never steals focus.
; ============================================================
ShowOSD(text, ms := 1500) {
    static g := 0, lbl := 0, hFont := 0, hideTimer := 0

    if !g {
        g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20")
        g.BackColor := "000000"  ; black = transparent glass hole for DWM
        g.SetFont("s13 q5 cFFFFFF", "Segoe UI Variable Text")
        lbl := g.Add("Text", "x20 y14 w400 BackgroundTrans Center")
        hFont := DllCall("SendMessageW", "Ptr", lbl.Hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")

        hwnd := g.Hwnd
        ; Extend DWM frame over entire client area — required for system backdrop
        DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", hwnd, "Ptr", Buffer(16, 0xFF))
        ; Dark window chrome (attr 20 = DWMWA_USE_IMMERSIVE_DARK_MODE)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Int*", 1, "UInt", 4)
        ; Transient acrylic (attr 38 = DWMWA_SYSTEMBACKDROP_TYPE, value 3 = DWMSBT_TRANSIENTWINDOW)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 38, "Int*", 3, "UInt", 4)
        ; Rounded corners (attr 33 = DWMWA_WINDOW_CORNER_PREFERENCE, value 2 = DWMWCP_ROUND)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 33, "Int*", 2, "UInt", 4)
    }

    if hideTimer {
        SetTimer(hideTimer, 0)
        hideTimer := 0
    }

    lbl.Value := text

    ; Measure rendered text (DT_CALCRECT|DT_WORDBREAK, max 400px wide)
    hDC := DllCall("GetDC", "Ptr", g.Hwnd, "Ptr")
    if hFont
        DllCall("SelectObject", "Ptr", hDC, "Ptr", hFont)
    rc := Buffer(16, 0)
    NumPut("Int", 400, rc, 8), NumPut("Int", 2000, rc, 12)
    DllCall("DrawTextW", "Ptr", hDC, "WStr", text, "Int", -1, "Ptr", rc, "UInt", 0x410)
    DllCall("ReleaseDC", "Ptr", g.Hwnd, "Ptr", hDC)
    tw := NumGet(rc, 8, "Int")
    th := NumGet(rc, 12, "Int")

    padX := 20, padY := 14
    gW := tw + padX * 2
    gH := th + padY * 2
    lbl.Move(padX, padY, tw, th)

    ; Bottom-center of primary monitor, 50px above taskbar
    MonitorGetWorkArea(MonitorGetPrimary(), &ml, &mt, &mr, &mb)
    g.Show("NoActivate w" gW " h" gH " x" (ml + (mr - ml - gW) // 2) " y" (mb - gH - 50))

    if ms > 0 {
        hideTimer := () => g.Hide()
        SetTimer(hideTimer, -ms)
    }
}

; ============================================================
; WINDOW MANAGEMENT HELPERS
; ============================================================

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

_ApplyLayout(x_factor, y_factor, w_factor, h_factor, overrideHwnd := 0) {
    if overrideHwnd {
        hwnd := overrideHwnd
        if !WinExist("ahk_id " hwnd)
            return
        state := WinGetMinMax("ahk_id " hwnd)
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
    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", dwmRect, "UInt", 16)
    visibleL := NumGet(dwmRect, 0, "Int"), visibleT := NumGet(dwmRect, 4, "Int")
    visibleR := NumGet(dwmRect, 8, "Int"), visibleB := NumGet(dwmRect, 12, "Int")

    ; Calculate current border offsets
    offL := visibleL - actualL, offT := visibleT - actualT
    offR := actualR - visibleR, offB := actualB - visibleB

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

    ; Remember this layout so we can silently restore it after sleep/desktop switch
    g_WindowLayouts[hwnd] := [x_factor, y_factor, w_factor, h_factor]
}

; Silently re-tile all tracked windows on desktop n.
; Called after every desktop switch to fix positions Windows may have
; corrupted during sleep/wake on non-active desktops.
_ReTileDesktop(n) {
    global g_WindowLayouts
    if !VDA_IsLoaded || !GetWindowDesktopNumber
        return
    for hwnd, layout in g_WindowLayouts.Clone() {
        if !WinExist("ahk_id " hwnd) {
            g_WindowLayouts.Delete(hwnd)
            continue
        }
        try {
            deskIdx := DllCall(GetWindowDesktopNumber, "Ptr", hwnd) + 1  ; VDA is 0-indexed
            if deskIdx = n
                _ApplyLayout(layout[1], layout[2], layout[3], layout[4], hwnd)
        }
    }
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
    if !VDA_IsLoaded {
        ShowOSD("VDA not loaded — install the DLL first!")
        return
    }

    ; Update memory for the desktop we're leaving (buffered in Map, written to disk on exit)
    currentDesk := DllCall(GetCurrentDesktopNumber) + 1  ; VDA is 0-indexed
    if WinExist("A")
        DesktopLastWindow[currentDesk] := WinGetID("A")

    DllCall(GoToDesktopNumber, "Int", n - 1)

    ; After the switch animation, restore focus on the destination desktop
    SetTimer(() => RestoreFocusOnDesktop(n), -150)
    ; Re-tile any tracked windows on the destination desktop.
    ; This silently corrects positions Windows corrupts during sleep/wake
    ; on non-active desktops (snaps them to raw zone coords, stripping TileGap).
    SetTimer(() => _ReTileDesktop(n), -400)
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
        GotoDesktop(n)
    } else {
        ShowOSD("VDA not loaded — install the DLL first!")
    }
}

AdjustOpacity(delta) {
    if !WinExist("A")
        return
    hwnd := WinGetID("A")
    cur := WindowOpacity.Has(hwnd) ? WindowOpacity[hwnd] : 255
    newVal := Max(40, Min(255, cur + delta))
    WindowOpacity[hwnd] := newVal
    if newVal = 255
        WinSetTransparent("Off", "A")
    else
        WinSetTransparent(newVal, "A")
    ShowOSD("Opacity: " Round(newVal / 255 * 100) "%")
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
        if hwnd = 0
            return
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
; FOCUS             EXTENDED TILING        OPACITY
;   H = Left          Y = Left 60%           WheelUp   = More opaque
;   J = Down          U = Left 1/3           WheelDown = More transparent
;   K = Up            I = Center 1/3
;   L = Right         O = Right 1/3
;   Backspace = Jump  P = Right 40%
;     to prev window
; WORKSPACE                                  SYSTEM
;   1-9    = Go to virtual desktop           M   = Task Manager
;   Alt+1-9= Move window to virtual desktop  T   = Terminal (focus or open)
;   Left   = Prev desktop                    E   = Open File Explorer
;   Right  = Next desktop                    N   = Notion (focus or open)
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

; --- Move window to virtual desktop 1-9 and follow (CapsLock+Alt+1-9) ---
*!1:: MoveToDesktop(1)
*!2:: MoveToDesktop(2)
*!3:: MoveToDesktop(3)
*!4:: MoveToDesktop(4)
*!5:: MoveToDesktop(5)
*!6:: MoveToDesktop(6)
*!7:: MoveToDesktop(7)
*!8:: MoveToDesktop(8)
*!9:: MoveToDesktop(9)

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
*f:: ToggleMaximize()
*g:: FloatCenter()
*`:: TogglePin()
*q:: {
    if WinExist("A")
        WinClose("A")
}

; --- Opacity ---
WheelUp::   AdjustOpacity(26)
WheelDown:: AdjustOpacity(-26)

; --- Media ---
[::Media_Prev
]::Media_Next
Space::Media_Play_Pause
*c:: Send "#+c"
*!l:: g_KeyLockActive ? _KL_Off() : _KL_On()

*v:: {
    codePath := EnvGet("LocalAppData") "\Programs\Microsoft VS Code\Code.exe"
    if WinExist("ahk_exe Code.exe")
        WinActivate("ahk_exe Code.exe")
    else if FileExist(codePath) {
        Run '"' codePath '"'
        if WinWait("ahk_exe Code.exe", , 10)
            WinActivate("ahk_exe Code.exe")
    } else {
        try Run("Code.exe")
    }
}

; --- Apps ---
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

*n:: {
    notionPath := EnvGet("LocalAppData") "\Programs\Notion\Notion.exe"
    if WinExist("ahk_exe Notion.exe") {
        if WinGetMinMax("ahk_exe Notion.exe") = -1
            WinRestore("ahk_exe Notion.exe")
        WinActivate("ahk_exe Notion.exe")
    } else if FileExist(notionPath) {
        try Run('"' notionPath '"')
    } else {
        try Run("Notion.exe")
    }
}

*r:: {
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
; Caps+Alt+L also toggles lock off.
; ============================================================
#HotIf g_KeyLockActive
u:: _KL_CheckUnlock("u")
n:: _KL_CheckUnlock("n")
l:: _KL_CheckUnlock("l")
o:: _KL_CheckUnlock("o")
c:: _KL_CheckUnlock("c")
k:: _KL_CheckUnlock("k")
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

; ============================================================
; SECTION 4: STARTUP WORKSPACE LAUNCHER
; ============================================================
;
;  Win+Ctrl+S  →  launch & sort everything to its desktop
;
; ── CUSTOMIZING YOUR LAYOUT ─────────────────────────────────
;  Edit WorkspaceLayout() below. Change Desktop numbers to
;  swap things around. Add/remove entries freely.
;  Type "browser" = Edge profile window (detected by new HWND)
;  Type "pwa"     = Edge PWA (detected by window title)
;  Type "app"     = anything else (detected by title or exe)
; ────────────────────────────────────────────────────────────

global WS_Edge := '"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"'
global WS_P1   := WS_Edge ' --profile-directory="Profile 1"'
global WS_P2   := WS_Edge ' --profile-directory="Profile 2"'
global WS_BrowserTimeout := 12000

WorkspaceLayout() {
    local localAppData := EnvGet("LocalAppData")
    local appData      := EnvGet("AppData")
    
    ; Identify paths for apps with versioned folders (Discord)
    local discordPath := "Discord.exe"
    loop files, localAppData "\Discord\app-*\Discord.exe" {
        discordPath := A_LoopFilePath
        break ; use the first one found
    }

    return [
        ; ── Desktop 1 · Personal ────────────────────────────
        { Type: "browser", Launch: WS_P1, Desktop: 1 },
        ; ── Desktop 2 · Work / School ───────────────────────
        { Type: "browser", Launch: WS_P2, Desktop: 2 },
        ; ── Desktop 3 · Messaging ───────────────────────────
        { Type: "app", Launch: discordPath, Match: "ahk_exe Discord.exe", Desktop: 3 },
        { Type: "pwa", Launch: WS_P2 ' --app-id=' CFG_PWA_Slack, Match: "Slack", Desktop: 3 },
        { Type: "app", Launch: '"' localAppData '\Programs\Notion\Notion.exe"',  Match: "ahk_exe Notion.exe",  Desktop: 3 },
        ; ── Desktop 4 · Terminal ─────────────────────────────
        { Type: "app", Launch: 'wt.exe', Match: "ahk_exe WindowsTerminal.exe", Desktop: 4 },
        ; ── Desktop 5 · Spotify / Misc ──────────────────────
        { Type: "app", Launch: '"' appData '\Spotify\Spotify.exe"', Match: "ahk_exe Spotify.exe", Desktop: 5 },
    ]
}

; ── Helper: launch an Edge profile and detect the new window ─
WS_LaunchBrowser(cmd) {
    existing := Map()
    for hwnd in WinGetList("ahk_exe msedge.exe")
        existing[hwnd] := true

    Run(cmd)

    deadline := A_TickCount + WS_BrowserTimeout
    while A_TickCount < deadline {
        for hwnd in WinGetList("ahk_exe msedge.exe") {
            if !existing.Has(hwnd) {
                Sleep(300)
                return hwnd
            }
        }
        Sleep(100)
    }
    return 0
}

; ── Win+Ctrl+S · Launch and distribute ──────────────────────
#^s:: {
    if !VDA_IsLoaded {
        ShowOSD("VDA not loaded — can't distribute windows!", 3000)
        return
    }

    ; Land on desktop 1 first
    DllCall(GoToDesktopNumber, "Int", 0)
    Sleep(500)

    layout := WorkspaceLayout()

    for app in layout {
        dispName := app.HasProp("Match") ? app.Match : "Browser (D" app.Desktop ")"
        ShowOSD("Launching " dispName " (" A_Index "/" layout.Length ")...", 0)
        
        hwnd := 0
        if app.Type = "browser" {
            hwnd := WS_LaunchBrowser(app.Launch)
        } else {
            ; Only launch if not already running
            if !WinExist(app.Match) {
                try {
                    Run(app.Launch)
                    hwnd := WinWait(app.Match, , 5)
                }
            } else {
                hwnd := WinExist(app.Match)
            }
        }

        if hwnd {
            ; Brief sleep to ensure window is ready for movement
            Sleep(250)
            DllCall(MoveWindowToDesktopNumber, "Ptr", hwnd, "Int", app.Desktop - 1)
            
            if app.HasProp("Maximize") && app.Maximize
                WinMaximize("ahk_id " hwnd)
            
            ; Remember this window for its destination desktop's memory
            DesktopLastWindow[app.Desktop] := hwnd
        } else {
            ShowOSD("Timed out on " dispName " — skipping", 0)
            Sleep(1500)
        }
    }

    ; Return home
    DllCall(GoToDesktopNumber, "Int", 0)
    ShowOSD("Workspace ready!", 2500)
}
