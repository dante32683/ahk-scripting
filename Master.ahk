#Requires AutoHotkey v2.0+
#SingleInstance Force
#WinActivateForce
#Include config.ahk

; ============================================================
; OPTIMIZATION: PERFORMANCE & MEMORY
; ============================================================
ListLines 0
KeyHistory 0
ProcessSetPriority "Normal"
SetTitleMatchMode 2

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
global hVDA := 0
global GoToDesktopNumber := 0
global MoveWindowToDesktopNumber := 0
global GetCurrentDesktopNumber := 0
global GetWindowDesktopNumber := 0

VDA_DLL := A_ScriptDir "\VirtualDesktopAccessor.dll"
if !FileExist(VDA_DLL) {
    ShowOSD("VDA DLL not found at:`n" VDA_DLL "`nWorkspace 1-9 keys disabled.", 5000)
} else {
    hVDA := DllCall("LoadLibrary", "Str", VDA_DLL, "Ptr")
    if !hVDA {
        ShowOSD("VDA DLL failed to load! Bitness mismatch?`nNeed x64 DLL for 64-bit AHK.`nPath: " VDA_DLL, 6000)
    } else {
        GoToDesktopNumber        := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GoToDesktopNumber",        "Ptr")
        MoveWindowToDesktopNumber := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "MoveWindowToDesktopNumber", "Ptr")
        GetCurrentDesktopNumber   := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetCurrentDesktopNumber",   "Ptr")
        GetWindowDesktopNumber    := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetWindowDesktopNumber",    "Ptr")
        if !GoToDesktopNumber {
            ShowOSD(
                "VDA loaded but functions missing.`nGet the latest release:`ngithub.com/Ciantic/VirtualDesktopAccessor/releases",
                6000
            )
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
; (State is queried live from WMI on each toggle — no stale cache)
; ============================================================
global DeviceID := CFG_CameraID
global PnPUtilPath := (A_Is64bitOS && A_PtrSize = 4)
    ? A_WinDir "\Sysnative\pnputil.exe"
    : A_WinDir "\System32\pnputil.exe"

ShowOSD("Script started!")
SetTimer(TrackFocusHistory, 150)

; ============================================================
; TILING GAP, BORDER & WINDOW HISTORY
; ============================================================
global TileGap    := 4
global TileBorder := 8      ; invisible Win11 window border compensation
global FocusHistory   := []
global LayoutCycleIdx := Map()
global WindowOpacity  := Map()

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
; ms = 0  →  tooltip stays until the next ShowOSD/ToolTip call
; ============================================================
ShowOSD(text, ms := 1500) {
    ToolTip(text)
    if ms > 0
        SetTimer(() => ToolTip(), -ms)
}

; ============================================================
; WINDOW MANAGEMENT HELPERS
; ============================================================

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

PrepareWindow() {
    state := WinGetMinMax("A")
    if (state = 1 || state = -1)
        WinRestore("A")
}

TileLeft() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    half := (R - L) // 2
    WinMove(L + G - TileBorder, T + G, half + TileBorder*2 - (3 * G) // 2, (B - T) + TileBorder - 2 * G, "A")
}

TileRight() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    half := (R - L) // 2
    WinMove(L + half + G // 2 - TileBorder, T + G, half + TileBorder*2 - (3 * G) // 2, (B - T) + TileBorder - 2 * G, "A")
}

TileTopLeft() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    half_w := (R - L) // 2
    half_h := (B - T) // 2
    WinMove(L + G - TileBorder, T + G, half_w + TileBorder*2 - (3 * G) // 2, half_h + TileBorder - (3 * G) // 2, "A")
}

TileTopRight() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    half_w := (R - L) // 2
    half_h := (B - T) // 2
    WinMove(L + half_w + G // 2 - TileBorder, T + G, half_w + TileBorder*2 - (3 * G) // 2, half_h + TileBorder - (3 * G) // 2, "A")
}

TileBottomLeft() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    half_w := (R - L) // 2
    half_h := (B - T) // 2
    WinMove(L + G - TileBorder, T + half_h + G // 2, half_w + TileBorder*2 - (3 * G) // 2, half_h + TileBorder - (3 * G) // 2, "A")
}

TileBottomRight() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    half_w := (R - L) // 2
    half_h := (B - T) // 2
    WinMove(L + half_w + G // 2 - TileBorder, T + half_h + G // 2, half_w + TileBorder*2 - (3 * G) // 2, half_h + TileBorder - (3 * G) // 2, "A")
}

FloatCenter() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    mw := R - L
    mh := B - T
    ww := mw * 75 // 100
    wh := mh * 75 // 100
    WinMove(L + (mw - ww) // 2, T + (mh - wh) // 2, ww, wh, "A")
}

TileLeftThird() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    third := (R - L) // 3
    WinMove(L + G - TileBorder, T + G, third + TileBorder*2 - (3 * G) // 2, (B - T) + TileBorder - 2 * G, "A")
}

TileCenterThird() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    third := (R - L) // 3
    WinMove(L + third + G // 2 - TileBorder, T + G, third + TileBorder*2 - G, (B - T) + TileBorder - 2 * G, "A")
}

TileRightThird() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    third := (R - L) // 3
    WinMove(L + 2 * third + G // 2 - TileBorder, T + G, third + TileBorder*2 - (3 * G) // 2, (B - T) + TileBorder - 2 * G, "A")
}

TileLeft60() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    w60 := (R - L) * 60 // 100
    WinMove(L + G - TileBorder, T + G, w60 + TileBorder*2 - (3 * G) // 2, (B - T) + TileBorder - 2 * G, "A")
}

TileRight40() {
    if !WinExist("A")
        return
    PrepareWindow()
    GetActiveMonitorWorkArea(&L, &T, &R, &B)
    G := TileGap
    w60 := (R - L) * 60 // 100
    w40 := (R - L) * 40 // 100
    WinMove(L + w60 + G // 2 - TileBorder, T + G, w40 + TileBorder*2 - (3 * G) // 2, (B - T) + TileBorder - 2 * G, "A")
}

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
    if !GoToDesktopNumber {
        ShowOSD("VDA not loaded — install the DLL first!")
        return
    }

    ; Save the currently focused window to the desktop we're leaving
    if GetCurrentDesktopNumber {
        currentDesk := DllCall(GetCurrentDesktopNumber) + 1  ; VDA is 0-indexed
        if WinExist("A") {
            hwnd := WinGetID("A")
            DesktopLastWindow[currentDesk] := hwnd
            IniWrite(hwnd, DesktopMemoryFile, "DesktopLastWindow", "d" currentDesk)
        }
    }

    DllCall(GoToDesktopNumber, "Int", n - 1)

    ; After the switch animation, restore focus on the destination desktop
    SetTimer(() => RestoreFocusOnDesktop(n), -150)
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
    ; No memory for this desktop yet — leave Windows to decide naturally
}

MoveToDesktop(n) {
    if !WinExist("A")
        return
    if MoveWindowToDesktopNumber {
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
    WinGetPos(&cx, &cy, &cw, &ch, "A")
    curX := cx + cw // 2
    curY := cy + ch // 2

    bestHwnd := 0
    bestScore := 0x7FFFFFFF

    list := WinGetList()
    for index, hwnd in list {  ; index = Z-order depth
        if hwnd = WinGetID("A")
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

    if bestHwnd
        WinActivate("ahk_id " bestHwnd)
}

TrackFocusHistory() {
    static lastHwnd := 0
    try {
        hwnd := WinGetID("A")
        if hwnd = 0 || hwnd = lastHwnd
            return
        lastHwnd := hwnd
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
    hwnd := WinGetID("A")
    idx := LayoutCycleIdx.Has(hwnd) ? Mod(LayoutCycleIdx[hwnd] + 1, 8) : 0
    LayoutCycleIdx[hwnd] := idx
    if (idx = 0)
        TileLeft()
    else if (idx = 1)
        TileRight()
    else if (idx = 2)
        TileLeft60()
    else if (idx = 3)
        TileRight40()
    else if (idx = 4)
        TileLeftThird()
    else if (idx = 5)
        TileRightThird()
    else if (idx = 6)
        TileCenterThird()
    else if (idx = 7)
        FloatCenter()
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
; SECTION 2: TEXT EXPANSION
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
; SECTION 3: THE "HYPER" LAYER  (CapsLock held = Hyper)
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

*v:: Run '"C:\Users\" CFG_Username "\AppData\Local\Programs\Microsoft VS Code\Code.exe"'

; --- Apps ---
*m:: Run "taskmgr.exe"
*e:: Run "explorer.exe"

*t:: {
    if WinActive("ahk_exe Code.exe") {
        Send "^``"
    } else if WinExist("ahk_exe WindowsTerminal.exe") {
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
            else {
                WinRestore("ahk_exe WindowsTerminal.exe")
                WinActivate("ahk_exe WindowsTerminal.exe")
            }
        } else {
            Run 'wt.exe', "C:\Users\" CFG_Username
        }
    } else {
        Run 'wt.exe', "C:\Users\" CFG_Username
    }
}

*n:: {
    ; Find any Edge window with "Notion" in the title (SetTitleMatchMode 2 is global)
    notionHwnd := 0
    for hwnd in WinGetList("ahk_exe msedge.exe") {
        if InStr(WinGetTitle("ahk_id " hwnd), "Notion") {
            notionHwnd := hwnd
            break
        }
    }
    if notionHwnd {
        if WinGetMinMax("ahk_id " notionHwnd) = -1
            WinRestore("ahk_id " notionHwnd)
        WinActivate("ahk_id " notionHwnd)
    } else {
        Run WS_P1 ' --app-id=' CFG_PWA_Notion
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

Esc:: {
    ToolTip("Reloading script...")
    Sleep(800)
    ToolTip()
    ReleaseModifiers()
    Reload()
}

#HotIf

; ============================================================
; SECTION 5: COPILOT KEY REBIND — CAMERA TOGGLE
; ============================================================
#+F23:: {
    global DeviceID, PnPUtilPath

    ShowOSD("Toggling Camera...", 0)
    exitCode := 1

    ; Re-query current device state from WMI each time — avoids stale cache
    currentlyOn := false
    try {
        wmi := ComObjGet("winmgmts:")
        escapedID := StrReplace(DeviceID, "\", "\\")
        query := wmi.ExecQuery("SELECT ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PNPDeviceID = '" escapedID "'")
        for device in query
            currentlyOn := (device.ConfigManagerErrorCode = 0)
    }

    try {
        if currentlyOn {
            exitCode := RunWait('"' PnPUtilPath '" /disable-device "' DeviceID '"', , "Hide")
            if (exitCode != 0) {
                psCmd := "Disable-PnpDevice -InstanceId '" DeviceID "' -Confirm:$false"
                exitCode := RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' psCmd '"', ,
                    "Hide")
            }
            if (exitCode = 0)
                ShowOSD("RGB Camera Disabled")
        } else {
            exitCode := RunWait('"' PnPUtilPath '" /enable-device "' DeviceID '"', , "Hide")
            if (exitCode != 0) {
                psCmd := "Enable-PnpDevice -InstanceId '" DeviceID "' -Confirm:$false"
                exitCode := RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' psCmd '"', ,
                    "Hide")
            }
            if (exitCode = 0)
                ShowOSD("RGB Camera Enabled")
        }
    } catch Error as err {
        ShowOSD("Execution Error: " err.Message, 3000)
        return
    }

    if (exitCode != 0)
        ShowOSD("Failed to toggle! (Exit Code: " exitCode ")")
}

; ============================================================
; SECTION 6: STARTUP WORKSPACE LAUNCHER
; ============================================================
;
;  Win+Ctrl+S  →  launch & sort everything to its desktop
;  Win+Ctrl+Q  →  close all work/messaging apps (end of day)
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
    return [
        ; ── Desktop 1 · Personal ────────────────────────────
        { Type: "browser", Launch: WS_P1, Desktop: 1 },
        ; ── Desktop 2 · Work / School ───────────────────────
        { Type: "browser", Launch: WS_P2, Desktop: 2 },
        ; ── Desktop 3 · Messaging ───────────────────────────
        { Type: "pwa", Launch: WS_P1 ' --app-id=' CFG_PWA_Discord,    Match: "Discord",     Desktop: 3 },
        { Type: "pwa", Launch: WS_P2 ' --app-id=' CFG_PWA_Slack,      Match: "Slack",       Desktop: 3 },
        { Type: "pwa", Launch: WS_P1 ' --app-id=' CFG_PWA_Messages,   Match: "Messages",    Desktop: 3 },
        { Type: "pwa", Launch: WS_P1 ' --app-id=' CFG_PWA_Instagram,  Match: "Instagram",   Desktop: 3 },
        { Type: "pwa", Launch: WS_P1 ' --app-id=' CFG_PWA_GoogleMeet, Match: "Google Meet", Desktop: 3 },
        ; ── Desktop 4 · Terminal ─────────────────────────────
        { Type: "app", Launch: 'wt.exe', Match: "ahk_exe WindowsTerminal.exe", Desktop: 4 },
        ; ── Desktop 5 · Spotify / Misc ──────────────────────
        { Type: "pwa", Launch: WS_P1 ' --app-id=' CFG_PWA_Spotify, Match: "Spotify", Desktop: 5 },
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
    if !MoveWindowToDesktopNumber || !GoToDesktopNumber {
        ShowOSD("VDA not loaded — can't distribute windows!", 3000)
        return
    }

    DllCall(GoToDesktopNumber, "Int", 0)
    Sleep(500)

    layout := WorkspaceLayout()

    for app in layout {
        dispName := app.HasProp("Match") ? app.Match : "Browser (Desktop " app.Desktop ")"
        ShowOSD("Launching " dispName " (" A_Index "/" layout.Length ")...", 0)
        hwnd := 0

        if app.Type = "browser" {
            hwnd := WS_LaunchBrowser(app.Launch)
        } else {
            if !WinExist(app.Match)
                Run(app.Launch)
            hwnd := WinWait(app.Match, , 10)
        }

        if hwnd {
            Sleep(200)
            DllCall(MoveWindowToDesktopNumber, "Ptr", hwnd, "Int", app.Desktop - 1)
            Sleep(200)
            if app.HasProp("Maximize") && app.Maximize
                WinMaximize("ahk_id " hwnd)
        } else {
            ShowOSD("Timed out on desktop " app.Desktop " — skipping", 0)
            Sleep(2000)
        }
    }

    DllCall(GoToDesktopNumber, "Int", 0)
    ShowOSD("Workspace ready!", 2500)
}
