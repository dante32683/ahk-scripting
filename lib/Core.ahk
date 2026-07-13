#Requires AutoHotkey v2.0+

global g_PerfStartupTick
if !IsSet(g_PerfStartupTick)
    global g_PerfStartupTick := A_TickCount

; Shared core: everything both machines use.
; Entry points must include:
;   - config.ahk
; before including this file.

; ============================================================
; MODULAR WINDOW TILING — both loaded; CFG_TilingMode selects active set
; ============================================================
#Include WindowTiling_FancyZones.ahk
#Include WindowTiling_Native.ahk
#Include ShowOSD.ahk
#Include Perf.ahk
#Include StateStore.ahk
#Include VDA.ahk

global CFG_TestMode := (IsSet(CFG_TestMode) && CFG_TestMode) || (EnvGet("AHK_TEST_MODE") = "1")

Perf_Init()

; ============================================================
; VIRTUAL DESKTOP ACCESSOR (VDA)
; ============================================================
VDA.Init()

; ============================================================
; FAILSAFE: SMART MODIFIER RELEASE
; ============================================================
OnExit ReleaseModifiers

ReleaseModifiers(ExitReason := "", ExitCode := "") {
    global g_PrivacyBlackoutActive
    if IsSet(g_PrivacyBlackoutActive) && g_PrivacyBlackoutActive
        _PrivacyBlackoutOff(false)
    for mod in ["LCtrl", "RCtrl", "LShift", "RShift", "LAlt", "RAlt", "LWin", "RWin", "CapsLock"]
        Send "{" mod " up}"
}

; ============================================================
; CAMERA TOGGLE — VARIABLES (entry point does WMI init)
; ============================================================
global g_PnPUtilPath := (A_Is64bitOS && A_PtrSize = 4)
    ? A_WinDir "\Sysnative\pnputil.exe"
    : A_WinDir "\System32\pnputil.exe"

global g_ProcNameCache := Map()
global g_WindowOffsetCache := Map()
global g_PwaCache := Map()

ShowOSD("Script started!")

; ============================================================
; FOCUS EVENT HOOK (Zero-CPU Focus Tracking)
; ============================================================
global g_WinEventQueue := []

_EnqueueWinEvent(type, args) {
    global g_WinEventQueue
    g_WinEventQueue.Push({type: type, args: args})
    SetTimer(_ProcessWinEvents, -1)
}

_ProcessWinEvents() {
    global g_WinEventQueue
    events := g_WinEventQueue
    g_WinEventQueue := []
    
    for ev in events {
        try {
            if ev.type = "focus" {
                _ProcessFocusEvent(ev.args*)
            } else if ev.type = "movestart" {
                _ProcessMoveStartEvent(ev.args*)
            } else if ev.type = "moveend" {
                _ProcessMoveEndEvent(ev.args*)
            } else if ev.type = "destroy" {
                _ProcessDestroyEvent(ev.args*)
            } else if ev.type = "locationchange" {
                _ProcessLocationChangeEvent(ev.args*)
            }
        }
    }
}
global hFocusHook := 0
global g_MoveStartHook := 0
global g_MoveEndHook := 0
global g_DestroyHook := 0
global g_LocationHook := 0

State_Init()

if !CFG_TestMode {
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

     global g_DestroyCallbackPtr := CallbackCreate(_OnWindowDestroy, , 7)
    global g_DestroyHook := DllCall("SetWinEventHook"
        , "UInt", 0x8001 ; EVENT_OBJECT_DESTROY
        , "UInt", 0x8001
        , "Ptr", 0
        , "Ptr", g_DestroyCallbackPtr
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0)

    global g_LocationCbPtr := CallbackCreate(_OnLocationChange, , 7)
    global g_LocationHook := DllCall("SetWinEventHook"
        , "UInt", 0x800B ; EVENT_OBJECT_LOCATIONCHANGE
        , "UInt", 0x800B
        , "Ptr", 0
        , "Ptr", g_LocationCbPtr
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0)

    OnExit((*) => DllCall("UnhookWinEvent", "Ptr", hFocusHook))
    OnExit((*) => DllCall("UnhookWinEvent", "Ptr", g_MoveStartHook))
    OnExit((*) => DllCall("UnhookWinEvent", "Ptr", g_MoveEndHook))
    OnExit((*) => DllCall("UnhookWinEvent", "Ptr", g_DestroyHook))
    OnExit((*) => DllCall("UnhookWinEvent", "Ptr", g_LocationHook))
    OnExit((*) => State_Shutdown())
    OnExit((*) => VDA.Cleanup())
    OnMessage(0x001A, _OnSettingChange)  ; WM_SETTINGCHANGE — work area resize (AppBar dock/undock)
    OnMessage(0x0218, _OnPowerBroadcast) ; WM_POWERBROADCAST — wake from sleep
    OnMessage(0x007E, _OnDisplayChange)  ; WM_DISPLAYCHANGE  — resolution change (fullscreen game exit)
}

_SaveDesktopMemory(*) {
    for desk, hwnd in g_DesktopLastWindow {
        if hwnd && WinExist("ahk_id " hwnd)
            State_SetDesktopWindow(desk, hwnd)
    }
}

_SaveLayouts(*) {
    for hwnd, layout in g_Layouts {
        if _IsLiveWindow(hwnd) {
            sig := _GetWinSignature(hwnd)
            State_SetSessionLayout(hwnd, sig, layout)
        }
    }
}

_PersistLayout(hwnd) {
    if !g_Layouts.Has(hwnd)
        return
    sig := _GetWinSignature(hwnd)
    State_SetSessionLayout(hwnd, sig, g_Layouts[hwnd])
}

_DeletePersistedLayout(hwnd) {
    State_DeleteSessionLayout(hwnd)
}

; ============================================================
; TILING GAP, BORDER & WINDOW HISTORY
; ============================================================
global g_TileGap        := IsSet(CFG_TilePadding) ? CFG_TilePadding : 4
global g_TilingMemoryFile := A_ScriptDir "\Tiling_Memory.ini"

if !IsSet(CFG_TilingMemory)
    global CFG_TilingMemory := true

_GetProcessName(hwnd) {
    if !hwnd
        return ""
    global g_ProcNameCache
    proc := g_ProcNameCache.Has(hwnd) ? g_ProcNameCache[hwnd] : ""
    if proc = "" {
        try {
            proc := WinGetProcessName("ahk_id " hwnd)
            if proc != ""
                g_ProcNameCache[hwnd] := proc
        } catch {
            proc := ""
        }
    }
    return proc
}

global g_PwaProcessIdCache := Map()

_IsPWA(windowHandle) {
    if !windowHandle
        return false
    global g_PwaCache, g_PwaProcessIdCache
    if g_PwaCache.Has(windowHandle)
        return g_PwaCache[windowHandle]

    processName := _GetProcessName(windowHandle)
    if !(processName = "msedge.exe" || processName = "chrome.exe") {
        g_PwaCache[windowHandle] := false
        return false
    }

    windowTitle := WinGetTitle("ahk_id " windowHandle)
    if (processName = "msedge.exe" && !RegExMatch(windowTitle, "i)[\-–—]\s+(?:InPrivate\s+[\-–—]\s+|InPrivate\s+)?Microsoft\s+Edge\s*$")) {
        g_PwaCache[windowHandle] := true
        return true
    }
    if (processName = "chrome.exe" && !RegExMatch(windowTitle, "i)[\-–—]\s+Google\s+Chrome\s*$")) {
        g_PwaCache[windowHandle] := true
        return true
    }

    try {
        processId := WinGetPID("ahk_id " windowHandle)
    } catch {
        return false
    }

    if g_PwaProcessIdCache.Has(processId) {
        isPwa := g_PwaProcessIdCache[processId]
        g_PwaCache[windowHandle] := isPwa
        return isPwa
    }

    g_PwaCache[windowHandle] := false ; Default for now
    SetTimer(() => _AsyncCheckPWA(windowHandle, processId), -50)
    return false
}

_AsyncCheckPWA(hwnd, pid) {
    global g_PwaProcessIdCache, g_PwaCache
    if !DllCall("IsWindow", "Ptr", hwnd)
        return
        
    isPwa := false
    try {
        static wmi := 0
        if !wmi
            wmi := ComObjGet("winmgmts:")
        Perf_Increment("wmi_queries")
        for process in wmi.ExecQuery("Select CommandLine from Win32_Process where ProcessId = " pid) {
            commandLine := process.CommandLine
            if InStr(commandLine, "--app-id=") || InStr(commandLine, "--app=") {
                isPwa := true
                break
            }
        }
    }
    g_PwaProcessIdCache[pid] := isPwa
    if DllCall("IsWindow", "Ptr", hwnd) {
        g_PwaCache[hwnd] := isPwa
        if isPwa {
            _AutoSnapFromMemory(hwnd)
        }
    }
}
}

_NormalizePWATitle(windowTitle) {
    windowTitle := RegExReplace(windowTitle, "^\(\d+\)\s+", "")           ; "(7) Instagram" → "Instagram"
    windowTitle := RegExReplace(windowTitle, "\s*-\s*\(\d+\)\s+.*$", "")  ; "App - (7) App" → "App"
    windowTitle := RegExReplace(windowTitle, "^.+\s+and\s+\d+\s+more\s+pages?\s+-\s+", "") ; "Tab and N more pages - Profile - Edge" → "Profile - Edge"
    windowTitle := RegExReplace(windowTitle, ":\s+[^:]+$", "")             ; "App: Trying to connect" → "App"
    return Trim(windowTitle)
}

_GetWinSignature(windowHandle) {
    if !WinExist("ahk_id " windowHandle)
        return ""
    processName := _GetProcessName(windowHandle)
    if !processName
        return ""
    if _IsPWA(windowHandle) {
        windowTitle := _NormalizePWATitle(WinGetTitle("ahk_id " windowHandle))
        return processName . ":" . RegExReplace(windowTitle, "[\[\]=]", "_")
    }
    return processName
}

_PersistToMemory(windowHandle, x_factor, y_factor, w_factor, h_factor) {
    global CFG_TilingMemory, g_HWNDLayoutCache
    if !IsSet(CFG_TilingMemory) || !CFG_TilingMemory
        return
    windowSignature := _GetWinSignature(windowHandle)
    if windowSignature = ""
        return
    g_HWNDLayoutCache[windowHandle] := Map("xf", x_factor, "yf", y_factor, "wf", w_factor, "hf", h_factor)

    State_SetAppLayout(windowSignature, x_factor "," y_factor "," w_factor "," h_factor)
}

_HasOtherWindowWithSignature(windowHandle, windowSignature) {
    global g_WinSigCache
    signatureProcess := InStr(windowSignature, ":") ? StrSplit(windowSignature, ":")[1] : windowSignature
    for otherHwnd in WinGetList() {
        if otherHwnd = windowHandle || !_IsLiveWindow(otherHwnd)
            continue
        if _GetProcessName(otherHwnd) != signatureProcess
            continue
        otherSignature := g_WinSigCache.Has(otherHwnd) ? g_WinSigCache[otherHwnd] : _GetWinSignature(otherHwnd)
        if otherSignature = windowSignature
            return true
    }
    return false
}

_AutoSnapFromMemory(windowHandle) {
    global CFG_TilingMemory, g_WinMaxState, g_HWNDLayoutCache, g_WinSigCache
    if !IsSet(CFG_TilingMemory) || !CFG_TilingMemory
        return
    if !_IsLiveWindow(windowHandle)
        return
    windowSignature := g_WinSigCache.Has(windowHandle) ? g_WinSigCache[windowHandle] : _GetWinSignature(windowHandle)
    if windowSignature = ""
        return

    ; Per-HWND session memory wins over the shared INI.
    if g_HWNDLayoutCache.Has(windowHandle) {
        cachedLayout := g_HWNDLayoutCache[windowHandle]
        _ApplyLayout(Integer(cachedLayout["xf"]), Integer(cachedLayout["yf"]),
                     Integer(cachedLayout["wf"]), Integer(cachedLayout["hf"]), windowHandle, false)
        return
    }

    ; If another live window has the exact same signature, do not guess from shared app memory.
    try {
        if _HasOtherWindowWithSignature(windowHandle, windowSignature)
            return
    }
    catch {
        return
    }

    if g_StateAppMaximized.Has(windowSignature) && g_StateAppMaximized[windowSignature] {
        WinMaximize("ahk_id " windowHandle)
        g_WinMaxState[windowHandle] := 1
        return
    }

    rectStr := State_GetAppLayout(windowSignature)
    if rectStr != "" {
        parts := StrSplit(rectStr, ",")
        if parts.Length = 4 {
            g_HWNDLayoutCache[windowHandle] := Map("xf", parts[1], "yf", parts[2], "wf", parts[3], "hf", parts[4])
            _ApplyLayout(Integer(parts[1]), Integer(parts[2]), Integer(parts[3]), Integer(parts[4]), windowHandle, false)
            return
        }
    }
}

global g_FocusHistory   := []
global g_LayoutCycleIdx := Map()
global g_KeyLockActive := false
global g_UnlockBuf     := ""
global g_ScriptPaused  := false
global g_CapsN_LastHiddenHwnd := 0
global g_PrivacyBlackoutActive := false
global g_PrivacyBlackoutGuis := []
global g_TilingMode    := CFG_TilingMode

; --- Safe Global Fallbacks ---
if !IsSet(CFG_Autocorrect)
    global CFG_Autocorrect := true
if !IsSet(CFG_FocusTeleportMouse)
    global CFG_FocusTeleportMouse := true
if !IsSet(CFG_MonitorFocusTeleportMouse)
    global CFG_MonitorFocusTeleportMouse := true
if !IsSet(CFG_DriftCorrection)
    global CFG_DriftCorrection := true
if !IsSet(CFG_DriftCheckInterval)
    global CFG_DriftCheckInterval := 2000

; Master-PC.ahk sets CFG_NumberKeys := "monitors" before this include; laptop relies on
; config.ahk (default "desktops"). This fallback is a last-resort safety net only.
global CFG_NumberKeys  := IsSet(CFG_NumberKeys) ? CFG_NumberKeys : "desktops"

global g_Layouts    := Map()   ; hwnd → [xf, yf, wf, hf]
global g_LayoutFile := A_Temp "\ahk_layouts.ini"
global g_LastDesktop := 0
global g_MoveSuppressUntil := Map()
global g_UserMoveActive    := Map()
global g_AutoRestoreTimers := Map()
global g_WinSigCache  := Map()   ; hwnd → signature string
global g_WinMaxState  := Map()   ; hwnd → 1 if maximized, 0 otherwise
global g_HWNDLayoutCache := Map() ; hwnd → {xf, yf, wf, hf} — ephemeral per-instance position cache
global g_DebugRestore := IsSet(CFG_DebugRestore) ? CFG_DebugRestore : false
global g_DebugLogFile := A_Temp "\ahk_restore_debug.log"

; ============================================================
; PER-DESKTOP FOCUS MEMORY
; ============================================================
global g_DesktopLastWindow := Map()

loop 9 {
    lastWnd := State_GetDesktopWindow(A_Index)
    if lastWnd && DllCall("IsWindow", "Ptr", lastWnd)
        g_DesktopLastWindow[A_Index] := lastWnd
}

for hwnd, item in g_StateSessionLayouts {
    g_Layouts[hwnd] := item["layout"]
}

if VDA.isLoaded {
    g_LastDesktop := VDA.GetCurrent()
}

if (g_TilingMode = "Native" && IsSet(CFG_DriftCorrection) && CFG_DriftCorrection)
    SetTimer(_CheckLayoutRestores, IsSet(CFG_DriftCheckInterval) ? CFG_DriftCheckInterval : 5000)

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
    if !(hwnd && DllCall("IsWindow", "Ptr", hwnd) && DllCall("IsWindowVisible", "Ptr", hwnd))
        return false

    proc := _GetProcessName(hwnd)
    if !proc
        return false

    ; EXCLUSIONS: Do not tile/track these transient or system windows
    try {
        if IsSet(CFG_TilingExclusions) {
            for excludedProc in CFG_TilingExclusions {
                if (proc = excludedProc)
                    return false
            }
        } else {
            if (proc = "Raycast.exe" || proc = "SearchHost.exe" || proc = "ShellExperienceHost.exe" || proc = "StartMenuExperienceHost.exe"
                || proc = "PowerToys.exe" || proc = "PowerLauncher.exe" || proc = "PowerToys.PowerLauncher.exe" || proc = "Microsoft.CmdPal.UI.exe" || proc = "PowerToys.CommandPaletteExtension.exe")
                return false
        }
    }
    return true
}

_IsOnCurrentDesktop(hwnd) {
    if !VDA.isLoaded
        return true
    try {
        winDesk := VDA.GetWindowDesktop(hwnd)
        if (winDesk = 0) ; Pin to all desktops or error
            return true
        curDesk := VDA.GetCurrent()
        return winDesk = curDesk
    } catch
        return true
}

_GetWindowState(hwnd, default := -2) {
    try return WinGetMinMax("ahk_id " hwnd)
    catch
        return default
}

_GetWindowOffsets(windowHandle, &offsetLeft, &offsetTop, &offsetRight, &offsetBottom) {
    global g_WindowOffsetCache
    if g_WindowOffsetCache.Has(windowHandle) {
        offsets := g_WindowOffsetCache[windowHandle]
        offsetLeft := offsets[1]
        offsetTop := offsets[2]
        offsetRight := offsets[3]
        offsetBottom := offsets[4]
        return
    }

    rect := Buffer(16)
    DllCall("user32\GetWindowRect", "Ptr", windowHandle, "Ptr", rect)
    actualLeft := NumGet(rect, 0, "Int"), actualTop := NumGet(rect, 4, "Int")
    actualRight := NumGet(rect, 8, "Int"), actualBottom := NumGet(rect, 12, "Int")

    dwmRect := Buffer(16)
    dwmOk := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", windowHandle, "UInt", 9, "Ptr", dwmRect, "UInt", 16) = 0
    visibleL := NumGet(dwmRect, 0, "Int"), visibleT := NumGet(dwmRect, 4, "Int")
    visibleR := NumGet(dwmRect, 8, "Int"), visibleB := NumGet(dwmRect, 12, "Int")

    if (dwmOk && visibleL >= actualLeft && visibleR <= actualRight
              && visibleT >= actualTop && visibleB <= actualBottom
              && (visibleR - visibleL) > 0 && (visibleB - visibleT) > 0) {
        offsetLeft := visibleL - actualLeft, offsetTop := visibleT - actualTop
        offsetRight := actualRight - visibleR, offsetBottom := actualBottom - visibleB
    } else {
        offsetLeft := 0, offsetTop := 0, offsetRight := 0, offsetBottom := 0
    }

    g_WindowOffsetCache[windowHandle] := [offsetLeft, offsetTop, offsetRight, offsetBottom]
}

; Compute the compensated outer (left) X for a window that is wider than its slot
; (e.g. DWM minimum-width constraints, common for Terminal / Settings / Slack). The
; window's interior edge — the one facing screen center — is aligned to the slot
; boundary and the overflow spills toward the outer screen edge, so the split line
; between adjacent tiles stays clean. A middle slot that touches neither screen edge
; (e.g. the center third) centers its overflow symmetrically. Full-width / spanning
; slots get no compensation. Returns defaultX when no adjustment applies. This single
; helper is shared by _ApplyLayout (pre- and post-move) and _GetExpectedOuterPos so
; the applier and the drift checker can never disagree and fight each other.
_CompensateWideX(x_factor, w_factor, visibleLeft, visibleRight, visibleWidth, requiredWidth, offsetLeft, defaultX) {
    if (visibleWidth <= requiredWidth)
        return defaultX
    if (x_factor = 0 && w_factor < 100)                    ; left-anchored: align interior (right) edge
        return visibleRight - visibleWidth - offsetLeft
    if (x_factor + w_factor = 100 && x_factor > 0)         ; right-anchored: align interior (left) edge
        return visibleLeft - offsetLeft
    if (x_factor > 0 && x_factor + w_factor < 100)         ; free-floating middle slot: center the overflow
        return visibleLeft - offsetLeft - (visibleWidth - requiredWidth) // 2
    return defaultX                                        ; full-width / spanning: no compensation
}

_GetExpectedOuterPos(windowHandle, x_factor, y_factor, w_factor, h_factor, &expectedX, &expectedY) {
    _GetMonitorForHwnd(windowHandle, &workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
    gapSize  := g_TileGap
    workAreaWidth := workAreaRight - workAreaLeft
    workAreaHeight := workAreaBottom - workAreaTop

    slotLeft := workAreaLeft + (workAreaWidth * x_factor // 100)
    slotRight := workAreaLeft + (workAreaWidth * (x_factor + w_factor) // 100)
    slotTop := workAreaTop + (workAreaHeight * y_factor // 100)
    slotBottom := workAreaTop + (workAreaHeight * (y_factor + h_factor) // 100)

    visibleLeft := slotLeft + (x_factor = 0 ? gapSize : gapSize // 2)
    visibleRight := slotRight - (x_factor + w_factor >= 100 ? gapSize : gapSize // 2)
    visibleTop := slotTop + (y_factor = 0 ? gapSize : gapSize // 2)

    _GetWindowOffsets(windowHandle, &offsetLeft, &offsetTop, &offsetRight, &offsetBottom)

    expectedX := visibleLeft - offsetLeft
    expectedY := visibleTop - offsetTop

    rect := Buffer(16)
    DllCall("user32\GetWindowRect", "Ptr", windowHandle, "Ptr", rect)
    actualLeft := NumGet(rect, 0, "Int"), actualRight := NumGet(rect, 8, "Int")
    actualW := actualRight - actualLeft

    requiredWidth := visibleRight - visibleLeft
    currentVisibleWidth := actualW - offsetLeft - offsetRight
    expectedX := _CompensateWideX(x_factor, w_factor, visibleLeft, visibleRight, currentVisibleWidth, requiredWidth, offsetLeft, expectedX)
}

_NeedsAutoRestore(windowHandle, layout) {
    if !_IsLiveWindow(windowHandle)
        return false
    WinGetPos(&windowX, &windowY, , , "ahk_id " windowHandle)
    _GetExpectedOuterPos(windowHandle, layout[1], layout[2], layout[3], layout[4], &expectedX, &expectedY)

    distanceX := Abs(windowX - expectedX)
    distanceY := Abs(windowY - expectedY)

    ; Only restore if the movement is small (drift/bug).
    ; If it's a large movement (e.g. > 200px), assume it's intentional and don't fight it.
    return (distanceX > 6 && distanceX < 200) || (distanceY > 6 && distanceY < 200)
}

_AutoRestoreWindow(hwnd) {
    if g_TilingMode != "Native"
        return
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
        Run('"' target '"' . (args ? " " . args : ""), workdir)
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
    ShowOSD("Keyboard Locked (Auto-unlock in 5m)", 0)
    SetTimer(_KL_Off, -300000) ; 5-minute safety timeout (run once)
}

_KL_Off() {
    global g_KeyLockActive, g_UnlockBuf
    g_KeyLockActive := false
    g_UnlockBuf     := ""
    BlockInput "Off"
    SetTimer(_KL_Off, 0) ; Cancel safety timer
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

; ============================================================
; PRIVACY BLACKOUT HELPERS
; ============================================================
TogglePrivacyBlackout() {
    global g_PrivacyBlackoutActive
    if g_PrivacyBlackoutActive
        _PrivacyBlackoutOff()
    else
        _PrivacyBlackoutOn()
}

_PrivacyBlackoutOn() {
    global g_PrivacyBlackoutActive, g_PrivacyBlackoutGuis
    if g_PrivacyBlackoutActive
        return

    ShowOSD("")
    g_PrivacyBlackoutGuis := []
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        overlay := Gui("+AlwaysOnTop -Caption +ToolWindow")
        overlay.BackColor := "000000"
        overlay.MarginX := 0
        overlay.MarginY := 0
        overlay.Show("x" l " y" t " w" (r - l) " h" (b - t) " NoActivate")
        WinSetAlwaysOnTop(true, "ahk_id " overlay.Hwnd)
        g_PrivacyBlackoutGuis.Push(overlay)
    }

    g_PrivacyBlackoutActive := true
    SetTimer(_PrivacyBlackoutKeepOnTop, 1000)
}

_PrivacyBlackoutOff(notify := true) {
    global g_PrivacyBlackoutActive, g_PrivacyBlackoutGuis
    SetTimer(_PrivacyBlackoutKeepOnTop, 0)
    for overlay in g_PrivacyBlackoutGuis {
        try overlay.Destroy()
    }
    g_PrivacyBlackoutGuis := []
    g_PrivacyBlackoutActive := false
    if notify
        ShowOSD("Privacy Blackout Off", 1500)
}

_PrivacyBlackoutKeepOnTop() {
    global g_PrivacyBlackoutActive, g_PrivacyBlackoutGuis
    if !g_PrivacyBlackoutActive
        return
    for overlay in g_PrivacyBlackoutGuis {
        try WinSetAlwaysOnTop(true, "ahk_id " overlay.Hwnd)
    }
}

SoftReset() {
    global g_KeyLockActive
    global g_CapsN_LastHiddenHwnd
    global g_PrivacyBlackoutActive
    ReleaseModifiers()
    ShowOSD("")
    if g_PrivacyBlackoutActive
        _PrivacyBlackoutOff(false)
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

GetActiveMonitorWorkArea(&workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom) {
    if WinExist("A") {
        try {
            _GetMonitorForHwnd(WinGetID("A"), &workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
            return
        }
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
}

_GetMonitorForHwnd(windowHandle, &workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom) {
    try {
        if WinExist("ahk_id " windowHandle) {
            WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "ahk_id " windowHandle)
            centerX := windowX + windowWidth // 2
            centerY := windowY + windowHeight // 2
            loop MonitorGetCount() {
                MonitorGetWorkArea(A_Index, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom)
                if (centerX >= monitorLeft && centerX < monitorRight && centerY >= monitorTop && centerY < monitorBottom) {
                    workAreaLeft := monitorLeft, workAreaTop := monitorTop, workAreaRight := monitorRight, workAreaBottom := monitorBottom
                    return
                }
            }
        }
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
}

_PrepareWindow() {
    state := WinGetMinMax("A")
    if (state = 1 || state = -1)
        WinRestore("A")
}

_ApplyLayout(x_factor, y_factor, w_factor, h_factor, overrideHwnd := 0, persist := true) {
    startTime := A_TickCount
    global g_MoveSuppressUntil, g_WinMaxState, g_TilingMemoryFile
    if overrideHwnd {
        windowHandle := overrideHwnd
        if !_IsLiveWindow(windowHandle) {
            Perf_Log("apply_layout", windowHandle, "invalid_hwnd", A_TickCount - startTime)
            return
        }
        state := _GetWindowState(windowHandle)
        if (state = 1 || state = -1)
            WinRestore("ahk_id " windowHandle)
        _GetMonitorForHwnd(windowHandle, &workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
    } else {
        if !WinExist("A") {
            Perf_Log("apply_layout", 0, "no_active_window", A_TickCount - startTime)
            return
        }
        windowHandle := WinGetID("A")
        if !_IsOnCurrentDesktop(windowHandle) {
            Perf_Log("apply_layout", windowHandle, "wrong_desktop", A_TickCount - startTime)
            return
        }
        _PrepareWindow()
        GetActiveMonitorWorkArea(&workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
    }

    mode := persist ? "store" : "restore"
    g_MoveSuppressUntil[windowHandle] := A_TickCount + 1500
    gapSize   := g_TileGap
    workAreaWidth  := workAreaRight - workAreaLeft
    workAreaHeight := workAreaBottom - workAreaTop

    slotLeft   := workAreaLeft + (workAreaWidth * x_factor // 100)
    slotRight  := workAreaLeft + (workAreaWidth * (x_factor + w_factor) // 100)
    slotTop    := workAreaTop + (workAreaHeight * y_factor // 100)
    slotBottom := workAreaTop + (workAreaHeight * (y_factor + h_factor) // 100)

    visibleLeft   := slotLeft + (x_factor = 0 ? gapSize : gapSize // 2)
    visibleRight  := slotRight - (x_factor + w_factor >= 100 ? gapSize : gapSize // 2)
    visibleTop    := slotTop + (y_factor = 0 ? gapSize : gapSize // 2)
    visibleBottom := slotBottom - (y_factor + h_factor >= 100 ? gapSize : gapSize // 2)

    _GetWindowOffsets(windowHandle, &offsetLeft, &offsetTop, &offsetRight, &offsetBottom)

    targetX := visibleLeft - offsetLeft
    targetY := visibleTop - offsetTop
    targetW := (visibleRight - visibleLeft) + offsetLeft + offsetRight
    targetH := (visibleBottom - visibleTop) + offsetTop + offsetBottom

    ; Get current window position
    rect := Buffer(16)
    DllCall("user32\GetWindowRect", "Ptr", windowHandle, "Ptr", rect)
    actualLeft := NumGet(rect, 0, "Int"), actualTop := NumGet(rect, 4, "Int")
    actualRight := NumGet(rect, 8, "Int"), actualBottom := NumGet(rect, 12, "Int")
    actualW := actualRight - actualLeft
    actualH := actualBottom - actualTop

    ; Account for DWM width adjustments (e.g., minimum width constraints) in the expected X coordinate
    visibleWidth := actualW - offsetLeft - offsetRight
    requiredWidth := visibleRight - visibleLeft
    expectedX := _CompensateWideX(x_factor, w_factor, visibleLeft, visibleRight, visibleWidth, requiredWidth, offsetLeft, targetX)

    g_Layouts[windowHandle] := [x_factor, y_factor, w_factor, h_factor]
    g_WinMaxState[windowHandle] := 0

    outcome := "move"
    if (actualLeft = expectedX && actualTop = targetY && actualW = targetW && actualH = targetH) {
        ; Already in the correct position, skip WinMove!
        _Dbg("apply skip-already-in-position " _WinSig(windowHandle))
        outcome := "skip"
    } else {
        Perf_Increment("win_moves")
        WinMove(targetX, targetY, targetW, targetH, "ahk_id " windowHandle)

        ; If the window is too wide for the target slot (e.g. minimum width constraint),
        ; adjust its X position so it aligns with the correct screen edge.
        dwmRectAfter := Buffer(16)
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", windowHandle, "UInt", 9, "Ptr", dwmRectAfter, "UInt", 16)
        visibleWidthAfter := NumGet(dwmRectAfter, 8, "Int") - NumGet(dwmRectAfter, 0, "Int")
        if (visibleWidthAfter > requiredWidth) {
            newX := _CompensateWideX(x_factor, w_factor, visibleLeft, visibleRight, visibleWidthAfter, requiredWidth, offsetLeft, targetX)
            if (newX != targetX)
                WinMove(newX, targetY, , , "ahk_id " windowHandle)
        }
    }

    _Dbg("apply mode=" mode " " _WinSig(windowHandle) " desk?=" (GetWindowDesktopNumber ? DllCall(GetWindowDesktopNumber, "Ptr", windowHandle) + 1 : 0)
        " mon=[" workAreaLeft "," workAreaTop "," workAreaRight "," workAreaBottom "] target=[" visibleLeft "," visibleTop "," visibleRight "," visibleBottom "] offs=[" offsetLeft "," offsetTop "," offsetRight "," offsetBottom "]"
        " pct=[" x_factor "," y_factor "," w_factor "," h_factor "]")
    if persist {
        _PersistLayout(windowHandle)
        _PersistToMemory(windowHandle, x_factor, y_factor, w_factor, h_factor)
        ; Tiling overrides any prior maximized memory
        windowSignature := _GetWinSignature(windowHandle)
        if windowSignature != ""
            State_SetAppMaximized(windowSignature, false)
    }
    
    Perf_Log("apply_layout", windowHandle, outcome, A_TickCount - startTime)
    return true
}

_RestoreDesktop(desktopNumber) {
    if g_TilingMode != "Native"
        return false
    global g_Layouts
    global g_ScriptPaused
    if g_ScriptPaused
        return false
    if !VDA.isLoaded
        return false
    _Dbg("restore-desktop-start desk=" desktopNumber " tracked=" g_Layouts.Count)
    anyMoved := false
    for windowHandle, windowLayout in g_Layouts.Clone() {
        if !_IsLiveWindow(windowHandle) {
            _Dbg("restore-desktop-drop dead " windowHandle)
            if g_Layouts.Has(windowHandle)
                g_Layouts.Delete(windowHandle)
            continue
        }
        try {
            windowDesktopNumber := VDA.GetWindowDesktop(windowHandle)
            if windowDesktopNumber != desktopNumber {
                _Dbg("restore-desktop-skip desk-mismatch want=" desktopNumber " got=" windowDesktopNumber " " _WinSig(windowHandle))
                continue
            }
        }
        state := _GetWindowState(windowHandle)
        if state != 0
            continue
        if _ApplyLayout(windowLayout[1], windowLayout[2], windowLayout[3], windowLayout[4], windowHandle, false) {
            anyMoved := true
        }
    }
    _Dbg("restore-desktop-end desk=" desktopNumber)
    return anyMoved
}

_RestoreAllDesktops() {
    if g_TilingMode != "Native"
        return
    global g_Layouts
    global g_ScriptPaused
    if g_ScriptPaused
        return
    for windowHandle, windowLayout in g_Layouts.Clone() {
        if !_IsLiveWindow(windowHandle) {
            if g_Layouts.Has(windowHandle)
                g_Layouts.Delete(windowHandle)
            continue
        }
        state := _GetWindowState(windowHandle)
        if state != 0
            continue
        try _ApplyLayout(windowLayout[1], windowLayout[2], windowLayout[3], windowLayout[4], windowHandle, false)
    }
}

_RestoreCurrentDesktop() {
    if !VDA.isLoaded
        return
    _RestoreDesktop(VDA.GetCurrent())
}

_DesktopRestoreTick(n, step) {
    moved := _RestoreDesktop(n)
    if moved && step < 3 {
        nextDelay := (step = 1) ? -600 : -1000
        SetTimer(() => _DesktopRestoreTick(n, step + 1), nextDelay)
    }
}

_ScheduleDesktopRestore(n) {
    _Dbg("schedule-desktop-restore desk=" n)
    SetTimer(() => _DesktopRestoreTick(n, 1), -1000)
}

_ScheduleRestoreCurrentDesktop(delay := 600) {
    _Dbg("schedule-current-desktop delay=" delay)
    if !VDA.isLoaded
        return
    SetTimer(() => _ScheduleDesktopRestore(VDA.GetCurrent()), -delay)
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

_OnWindowDestroy(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    _EnqueueWinEvent("destroy", [hHook, event, hwnd, idObject, idChild, dwThread, dwTime])
}

_ProcessDestroyEvent(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    global g_WinSigCache, g_WinMaxState, CFG_TilingMemory, g_HWNDLayoutCache, g_ProcNameCache, g_WindowOffsetCache
    global g_Layouts, g_UserMoveActive, g_MoveSuppressUntil, g_PwaCache, g_LayoutCycleIdx
    ; Filter to top-level window destruction only
    if idObject != 0 || idChild != 0
        return
    if g_ProcNameCache.Has(hwnd)
        g_ProcNameCache.Delete(hwnd)
    if g_LayoutCycleIdx.Has(hwnd)
        g_LayoutCycleIdx.Delete(hwnd)
    if g_WindowOffsetCache.Has(hwnd)
        g_WindowOffsetCache.Delete(hwnd)
    if g_Layouts.Has(hwnd) {
        g_Layouts.Delete(hwnd)
        _DeletePersistedLayout(hwnd)
    }
    if g_UserMoveActive.Has(hwnd)
        g_UserMoveActive.Delete(hwnd)
    if g_MoveSuppressUntil.Has(hwnd)
        g_MoveSuppressUntil.Delete(hwnd)
    if g_PwaCache.Has(hwnd)
        g_PwaCache.Delete(hwnd)
    if g_AutoRestoreTimers.Has(hwnd)
        g_AutoRestoreTimers.Delete(hwnd)
    if g_HWNDLayoutCache.Has(hwnd)
        g_HWNDLayoutCache.Delete(hwnd)

    if !g_WinSigCache.Has(hwnd)
        return
    sig := g_WinSigCache[hwnd]
    isMax := g_WinMaxState.Has(hwnd) ? g_WinMaxState[hwnd] : 0
    g_WinSigCache.Delete(hwnd)
    if g_WinMaxState.Has(hwnd)
        g_WinMaxState.Delete(hwnd)
    if !IsSet(CFG_TilingMemory) || !CFG_TilingMemory
        return
    if isMax
        State_SetAppMaximized(sig, true)
    else
        State_SetAppMaximized(sig, false)
}

_OnMoveStart(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    _EnqueueWinEvent("movestart", [hHook, event, hwnd, idObject, idChild, dwThread, dwTime])
}

_ProcessMoveStartEvent(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    global g_UserMoveActive
    if idObject != 0 || !g_Layouts.Has(hwnd)
        return
    g_UserMoveActive[hwnd] := true
}

_OnMoveEnd(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    _EnqueueWinEvent("moveend", [hHook, event, hwnd, idObject, idChild, dwThread, dwTime])
}

_ProcessMoveEndEvent(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    global g_UserMoveActive, g_WinMaxState
    if idObject != 0
        return
    ; Update max-state cache regardless of whether we track layouts
    try g_WinMaxState[hwnd] := (_GetWindowState(hwnd) = 1) ? 1 : 0
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

_OnLocationChange(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    if idObject != 0 || idChild != 0
        return
    global g_Layouts, g_UserMoveActive, g_ScriptPaused
    if g_ScriptPaused
        return
    if !g_Layouts.Has(hwnd)
        return
    if g_UserMoveActive.Has(hwnd)
        return
    _EnqueueWinEvent("locationchange", [hwnd])
}

_ProcessLocationChangeEvent(hwnd) {
    global g_Layouts, g_MoveSuppressUntil, g_UserMoveActive, g_ScriptPaused
    if g_ScriptPaused
        return
    if !g_Layouts.Has(hwnd)
        return
    if g_UserMoveActive.Has(hwnd)
        return
    if g_MoveSuppressUntil.Has(hwnd) && g_MoveSuppressUntil[hwnd] > A_TickCount
        return
        
    layout := g_Layouts[hwnd]
    if _NeedsAutoRestore(hwnd, layout) {
        _ScheduleAutoRestore(hwnd)
    }
}

_CheckLayoutRestores() {
    global g_Layouts, g_MoveSuppressUntil, g_UserMoveActive
    global g_ScriptPaused, g_WinMaxState
    if g_ScriptPaused
        return
    Perf_Increment("drift_reconciliations")
    for hwnd, layout in g_Layouts {
        if !_IsLiveWindow(hwnd)
            continue
        ; Keep max-state cache fresh for all tracked windows
        try g_WinMaxState[hwnd] := (_GetWindowState(hwnd) = 1) ? 1 : 0
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
    global g_ScriptPaused, g_FocusHistory, g_DesktopLastWindow
    if g_ScriptPaused
        return
    if !VDA.isLoaded
        return
    try currentDesk := VDA.GetCurrent()
    catch
        return
    _HandleDesktopChangeFromMsg(currentDesk)
}

_HandleDesktopChangeFromMsg(currentDesk) {
    global g_LastDesktop
    global g_ScriptPaused, g_FocusHistory, g_DesktopLastWindow
    if g_ScriptPaused
        return
    if !currentDesk || currentDesk = g_LastDesktop
        return

    ; Save the last active window on the departing desktop
    if g_LastDesktop > 0 {
        historyIndex := g_FocusHistory.Length
        while historyIndex > 0 {
            prevHwnd := g_FocusHistory[historyIndex]
            if WinExist("ahk_id " prevHwnd) && _IsWindowOnDesktop(prevHwnd, g_LastDesktop) {
                State_SetDesktopWindow(g_LastDesktop, prevHwnd)
                g_DesktopLastWindow[g_LastDesktop] := prevHwnd
                break
            }
            historyIndex--
        }
    }

    g_LastDesktop := currentDesk
    SetTimer(() => _RestoreFocusOnDesktop(currentDesk), -150)
    _ScheduleDesktopRestore(currentDesk)
}

_IsWindowOnDesktop(hwnd, deskIndex) {
    if !VDA.isLoaded
        return true
    try {
        winDesk := VDA.GetWindowDesktop(hwnd)
        if (winDesk = 0) ; Pin to all desktops or error
            return true
        return winDesk = deskIndex
    } catch
        return false
}

TileTop()         => _ApplyLayout(0, 0, 100, 50)
TileBottom()      => _ApplyLayout(0, 50, 100, 50)
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
    global g_WinMaxState
    if !WinExist("A")
        return
    hwnd := WinGetID("A")
    if !_IsOnCurrentDesktop(hwnd)
        return
    if WinGetMinMax("ahk_id " hwnd) = 1 {
        WinRestore("ahk_id " hwnd)
        g_WinMaxState[hwnd] := 0
        _ScheduleAutoRestore(hwnd, 50)
    } else {
        WinMaximize("ahk_id " hwnd)
        g_WinMaxState[hwnd] := 1
    }
}

GotoDesktop(n) {
    global g_LastDesktop
    if !VDA.isLoaded {
        ShowOSD("VDA not loaded — install the DLL first!")
        return
    }
    currentDesk := VDA.GetCurrent()
    if WinExist("A")
        g_DesktopLastWindow[currentDesk] := WinGetID("A")

    g_LastDesktop := n
    VDA.GoTo(n)

    SetTimer(() => _RestoreFocusOnDesktop(n), -150)
    _ScheduleDesktopRestore(n)
}

_RestoreFocusOnDesktop(n) {
    if g_DesktopLastWindow.Has(n) {
        hwnd := g_DesktopLastWindow[n]
        if WinExist("ahk_id " hwnd) {
            if _IsOnCurrentDesktop(hwnd) {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    WinRestore("ahk_id " hwnd)
                WinActivate("ahk_id " hwnd)
                return
            }
        }
        g_DesktopLastWindow.Delete(n)
    }
}

MoveToDesktop(desktopIndex) {
    if !WinExist("A")
        return
    if VDA.isLoaded {
        windowHandle := WinGetID("A")
        VDA.MoveWindow(windowHandle, desktopIndex)
        g_DesktopLastWindow[desktopIndex] := windowHandle
        GotoDesktop(desktopIndex)
    } else {
        ShowOSD("VDA not loaded — install the DLL first!")
    }
}

; ============================================================
; MONITOR HELPERS  (shared; also used by Master-PC hyper layer)
; ============================================================

_FocusMonitor(monitorIndex) {
    monitorCount := MonitorGetCount()
    if monitorIndex < 1 || monitorIndex > monitorCount
        return
    MonitorGetWorkArea(monitorIndex, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom)
    historyIndex := g_FocusHistory.Length
    while historyIndex > 0 {
        windowHandle := g_FocusHistory[historyIndex]
        if WinExist("ahk_id " windowHandle) && WinGetMinMax("ahk_id " windowHandle) != -1 {
            WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "ahk_id " windowHandle)
            centerX := windowX + windowWidth // 2
            centerY := windowY + windowHeight // 2
            if centerX >= monitorLeft && centerX < monitorRight && centerY >= monitorTop && centerY < monitorBottom {
                WinActivate("ahk_id " windowHandle)
                if (IsSet(CFG_MonitorFocusTeleportMouse) && CFG_MonitorFocusTeleportMouse)
                    DllCall("SetCursorPos", "Int", centerX, "Int", centerY)
                return
            }
        }
        historyIndex--
    }
    for windowHandle in WinGetList() {
        if WinGetMinMax("ahk_id " windowHandle) = -1
            continue
        if !(WinGetStyle("ahk_id " windowHandle) & 0x10000000)
            continue
        WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "ahk_id " windowHandle)
        centerX := windowX + windowWidth // 2, centerY := windowY + windowHeight // 2
        if centerX >= monitorLeft && centerX < monitorRight && centerY >= monitorTop && centerY < monitorBottom {
            WinActivate("ahk_id " windowHandle)
            return
        }
    }
}

_MoveWindowToMonitor(monitorIndex) {
    if !WinExist("A")
        return
    monitorCount := MonitorGetCount()
    if monitorIndex < 1 || monitorIndex > monitorCount {
        ShowOSD("Monitor " monitorIndex " doesn't exist (have " monitorCount ")")
        return
    }
    windowHandle := WinGetID("A")
    MonitorGetWorkArea(monitorIndex, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom)
    if g_Layouts.Has(windowHandle) {
        layout := g_Layouts[windowHandle]
        x_factor := layout[1], y_factor := layout[2], w_factor := layout[3], h_factor := layout[4]
    } else {
        x_factor := 12, y_factor := 12, w_factor := 75, h_factor := 75
    }
    monitorWidth := monitorRight - monitorLeft, monitorHeight := monitorBottom - monitorTop
    targetX := monitorLeft + (monitorWidth * x_factor // 100)
    targetY := monitorTop + (monitorHeight * y_factor // 100)
    targetWidth := monitorWidth * w_factor // 100
    targetHeight := monitorHeight * h_factor // 100
    if WinGetMinMax("ahk_id " windowHandle) != 0
        WinRestore("ahk_id " windowHandle)
    WinMove(targetX, targetY, targetWidth, targetHeight, "ahk_id " windowHandle)
    g_Layouts[windowHandle] := [x_factor, y_factor, w_factor, h_factor]
    _PersistLayout(windowHandle)
    ShowOSD("→ Monitor " monitorIndex)
}

; Dispatch: CapsLock+1–9 → focus desktop OR monitor
_NumberKey(index) {
    if CFG_NumberKeys = "monitors"
        _FocusMonitor(index)
    else
        GotoDesktop(index)
}

; Dispatch: CapsLock+Alt+1–9 → move window to desktop OR monitor
_NumberKeyAlt(index) {
    if CFG_NumberKeys = "monitors"
        _MoveWindowToMonitor(index)
    else
        MoveToDesktop(index)
}

FocusDirection(dir) {
    startTime := A_TickCount
    candidateCount := 0
    if !WinExist("A") {
        Perf_Log("focus_direction", dir, 0, A_TickCount - startTime)
        return
    }
    curHwnd := WinGetID("A")
    WinGetPos(&cx, &cy, &cw, &ch, "ahk_id " curHwnd)
    curX := cx + cw // 2
    curY := cy + ch // 2
    gapSize := g_TileGap

    bestHwnd := 0
    bestScore := 0x7FFFFFFF

    list := WinGetList()
    for index, hwnd in list {
        candidateCount++
        if hwnd = curHwnd
            continue
        if !_IsLiveWindow(hwnd)
            continue
        if WinGetMinMax("ahk_id " hwnd) = -1
            continue
        if WinGetExStyle("ahk_id " hwnd) & 0x80 ; WS_EX_TOOLWINDOW
            continue
        cloaked := 0
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
        if cloaked
            continue
        if !_IsOnCurrentDesktop(hwnd)
            continue

        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        wX := wx + ww // 2
        wY := wy + wh // 2

        edgeDist := 0
        overlap := 0
        spanLimit := 0
        valid := false
        if dir = "left" && wX < curX {
            edgeDist := cx - (wx + ww)
            overlap := ((wx + ww) - cx > 0) ? (wx + ww) - cx : 0
            spanLimit := cw
            valid := true
        } else if dir = "right" && wX > curX {
            edgeDist := wx - (cx + cw)
            overlap := ((cx + cw) - wx > 0) ? (cx + cw) - wx : 0
            spanLimit := cw
            valid := true
        } else if dir = "up" && wY < curY {
            edgeDist := cy - (wy + wh)
            overlap := ((wy + wh) - cy > 0) ? (wy + wh) - cy : 0
            spanLimit := ch
            valid := true
        } else if dir = "down" && wY > curY {
            edgeDist := wy - (cy + ch)
            overlap := ((cy + ch) - wy > 0) ? (cy + ch) - wy : 0
            spanLimit := ch
            valid := true
        }

        if !valid
            continue
        ; Occluded fullscreen windows span nearly the full active width/height.
        if overlap >= spanLimit - gapSize
            continue

        dist := edgeDist > 0 ? edgeDist : ((dir = "left" || dir = "right") ? Abs(wX - curX) : Abs(wY - curY))
        ; Penalize off-axis distance so navigation lands on a visually adjacent window
        ; rather than one far above/below (for left/right) or left/right (for up/down).
        perpDist := (dir = "left" || dir = "right") ? Abs(wY - curY) : Abs(wX - curX)
        score := dist + (overlap * 2) + (perpDist * 0.5) + (index * 50)
        if score < bestScore {
            bestScore := score
            bestHwnd := hwnd
        }
    }

    if bestHwnd {
        WinActivate("ahk_id " bestHwnd)
        if (IsSet(CFG_FocusTeleportMouse) && CFG_FocusTeleportMouse) {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " bestHwnd)
            DllCall("SetCursorPos", "Int", wx + ww // 2, "Int", wy + wh // 2)
        }
    }
    
    Perf_Log("focus_direction", dir, candidateCount, A_TickCount - startTime)
}

TrackFocusHistory(hHook, event, hwnd, idObject := 0, idChild := 0, dwThread := 0, dwTime := 0) {
    _EnqueueWinEvent("focus", [hHook, event, hwnd, idObject, idChild, dwThread, dwTime])
}

_ProcessFocusEvent(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    startTime := A_TickCount
    Perf_Increment("foreground_events")
    global g_ScriptPaused, g_TilingMode, g_Layouts, g_WinSigCache, g_WinMaxState
    global CFG_TilingMemory
    try {
        if g_ScriptPaused {
            Perf_Log("foreground_event", hwnd, "paused", A_TickCount - startTime)
            return
        }
        _HandleDesktopChange()
        if hwnd = 0 || !_IsLiveWindow(hwnd) {
            Perf_Log("foreground_event", hwnd, "invalid", A_TickCount - startTime)
            return
        }

        ; --- CACHE SIG + MAX STATE ---
        try {
            sig := g_WinSigCache.Has(hwnd) ? g_WinSigCache[hwnd] : _GetWinSignature(hwnd)
            if sig != "" {
                g_WinSigCache[hwnd] := sig
                isMax := (_GetWindowState(hwnd) = 1) ? 1 : 0
                g_WinMaxState[hwnd] := isMax
                if isMax && IsSet(CFG_TilingMemory) && CFG_TilingMemory
                    State_SetAppMaximized(sig, true)
            }
        }

        ; --- AUTO-MEMORY SNAP ---
        if g_TilingMode = "Native" && !g_Layouts.Has(hwnd) {
            ; skip popups/dropdowns: need WS_CAPTION; skip dialogs/tool windows: must have no owner
            if (WinGetStyle("ahk_id " hwnd) & 0xC00000) && (DllCall("GetWindow", "Ptr", hwnd, "UInt", 4) = 0)
                _AutoSnapFromMemory(hwnd)
        }

        if g_FocusHistory.Length > 0 && g_FocusHistory[g_FocusHistory.Length] = hwnd {
            Perf_Log("foreground_event", hwnd, "duplicate", A_TickCount - startTime)
            return
        }
        g_FocusHistory.Push(hwnd)
        if g_FocusHistory.Length > 30
            g_FocusHistory.RemoveAt(1)
            
        Perf_Log("foreground_event", hwnd, "success", A_TickCount - startTime)
    }
}

FocusJumpBack() {
    curHwnd := WinExist("A") ? WinGetID("A") : 0
    loop {
        if g_FocusHistory.Length = 0
            return
        hwnd := g_FocusHistory.Pop()
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
    if !_IsOnCurrentDesktop(hwnd)
        return
    idx := g_LayoutCycleIdx.Has(hwnd) ? Mod(g_LayoutCycleIdx[hwnd] + 1, layouts.Length) : 0
    g_LayoutCycleIdx[hwnd] := idx
    layouts[idx + 1]()
}

; ============================================================
; EMERGENCY KILL SWITCH
; ============================================================
#SuspendExempt
*^Esc:: {
    ReleaseModifiers()
    ExitApp()
}
#SuspendExempt False

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

+CapsLock::
!+CapsLock:: {
    ; Wait up to 300ms: if CapsLock is released it was a toggle tap,
    ; if still held it's being used as a Hyper modifier — don't toggle.
    KeyWait "CapsLock", "T0.3"
    if !GetKeyState("CapsLock", "P") && (A_PriorKey = "CapsLock" || A_PriorKey = "LShift" || A_PriorKey = "RShift" || A_PriorKey = "LAlt" || A_PriorKey = "RAlt" || A_PriorKey = "Shift" || A_PriorKey = "Alt") {
        if GetKeyState("CapsLock", "T")
            SetCapsLockState "Off"
        else
            SetCapsLockState "On"
    }
}

; ============================================================
; THE "HYPER" LAYER  (CapsLock held = Hyper)
; ============================================================

#HotIf GetKeyState("CapsLock", "P")

; --- Number keys: desktops or monitors (CFG_NumberKeys) ---
1:: _NumberKey(1)
2:: _NumberKey(2)
3:: _NumberKey(3)
4:: _NumberKey(4)
5:: _NumberKey(5)
6:: _NumberKey(6)
7:: _NumberKey(7)
8:: _NumberKey(8)
9:: _NumberKey(9)

*!1:: _NumberKeyAlt(1)
*!2:: _NumberKeyAlt(2)
*!3:: _NumberKeyAlt(3)
*!4:: _NumberKeyAlt(4)
*!5:: _NumberKeyAlt(5)
*!6:: _NumberKeyAlt(6)
*!7:: _NumberKeyAlt(7)
*!8:: _NumberKeyAlt(8)
*!9:: _NumberKeyAlt(9)

; --- Arrow navigation ---
w::Up
a::Left
s::Down
d::Right

; --- Tab navigation ---
f::Send "^{PgUp}"   ; Previous Tab
g::Send "^{PgDn}"   ; Next Tab

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
*`:: Send("^#t")
Delete:: {
    hwnd := WinExist("A") ? WinGetID("A") : 0
    if hwnd && g_Layouts.Has(hwnd) {
        g_Layouts.Delete(hwnd)
        _DeletePersistedLayout(hwnd)
        ShowOSD("Layout cleared")
    }
}

; --- Media ---
*[:: Send "{Media_Prev}"
*]:: Send "{Media_Next}"
*Space:: Send "{Media_Play_Pause}"
*c:: Send("!+c")
*!l:: {
    static _lastToggle := 0
    if (A_TickCount - _lastToggle < 400)
        return
    _lastToggle := A_TickCount
    g_KeyLockActive ? _KL_Off() : _KL_On()
}
*!k:: TogglePrivacyBlackout()

; --- Apps ---

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

SafeReload() {
    _SaveDesktopMemory()
    _SaveLayouts()
    ReleaseModifiers()
    Reload()
}

*r:: {
    if g_PrivacyBlackoutActive
        _PrivacyBlackoutOff(false)
    if BuildAutocorrect() {
        ShowOSD("Autocorrect rebuilt — reloading...")
        ReleaseModifiers()
        Sleep(200)
        SafeReload()
    } else
        SoftReset()
}

*+r:: {
    if g_PrivacyBlackoutActive
        _PrivacyBlackoutOff(false)
    RunWait "taskkill.exe /F /IM explorer.exe", , "Hide"
    Sleep(300)
    Run A_WinDir "\explorer.exe"
}

Esc:: {
    ShowOSD("Building Autocorrect & Reloading...")
    if g_PrivacyBlackoutActive
        _PrivacyBlackoutOff(false)
    try BuildAutocorrect()
    ReleaseModifiers()
    Sleep(200)
    SafeReload()
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
