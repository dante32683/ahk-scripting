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
#Include Layout.ahk

; ============================================================
; FAILSAFE: SMART MODIFIER RELEASE
; ============================================================
ReleaseModifiers(ExitReason := "", ExitCode := "") {
    global g_PrivacyBlackoutActive, g_KeyLockActive
    if IsSet(g_PrivacyBlackoutActive) && g_PrivacyBlackoutActive
        _PrivacyBlackoutOff(false)
    if IsSet(g_KeyLockActive) && g_KeyLockActive {
        g_KeyLockActive := false
        try BlockInput(false)
    }
    for modifierKey in ["LCtrl", "RCtrl", "LShift", "RShift", "LAlt", "RAlt", "LWin", "RWin", "CapsLock"]
        Send "{" modifierKey " up}"
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
global g_PwaProcessIdCache := Map()
global g_SigToHwndIndex := Map()  ; signature -> Map of hwnd -> true

; ============================================================
; WINEVENT PENDING STATE (coalesced; processed on AHK thread)
; ============================================================
global g_PendingForegroundHwnd := 0
global g_PendingLocationDirty := Map()
global g_PendingMoveStart := Map()
global g_PendingMoveEnd := Map()
global g_PendingDestroy := Map()
global g_WinEventProcessScheduled := false
global hFocusHook := 0
global g_MoveStartHook := 0
global g_MoveEndHook := 0
global g_DestroyHook := 0
global g_LocationHook := 0
global g_FocusCallbackPtr := 0
global g_MoveStartCbPtr := 0
global g_MoveEndCbPtr := 0
global g_DestroyCallbackPtr := 0
global g_LocationCbPtr := 0
global g_AppShuttingDown := false

_ScheduleWinEventProcess() {
    global g_WinEventProcessScheduled
    if g_WinEventProcessScheduled
        return
    g_WinEventProcessScheduled := true
    SetTimer(_ProcessWinEvents, -1)
}

_ProcessWinEvents() {
    global g_PendingForegroundHwnd, g_PendingLocationDirty, g_PendingMoveStart
    global g_PendingMoveEnd, g_PendingDestroy, g_WinEventProcessScheduled, g_AppShuttingDown
    g_WinEventProcessScheduled := false
    if g_AppShuttingDown
        return

    focusHwnd := g_PendingForegroundHwnd
    g_PendingForegroundHwnd := 0
    moveStarts := g_PendingMoveStart
    g_PendingMoveStart := Map()
    moveEnds := g_PendingMoveEnd
    g_PendingMoveEnd := Map()
    destroys := g_PendingDestroy
    g_PendingDestroy := Map()
    locationDirty := g_PendingLocationDirty
    g_PendingLocationDirty := Map()

    for hwnd, _ in moveStarts {
        try _ProcessMoveStartEvent(hwnd)
    }
    for hwnd, _ in moveEnds {
        try _ProcessMoveEndEvent(hwnd)
    }
    for hwnd, info in destroys {
        try _ProcessDestroyEvent(hwnd, info)
    }
    if focusHwnd {
        try _ProcessFocusEvent(focusHwnd)
    }
    for hwnd, _ in locationDirty {
        try _ProcessLocationChangeEvent(hwnd)
    }
}

WindowEvents_Init() {
    global CFG_TestMode, hFocusHook, g_MoveStartHook, g_MoveEndHook, g_DestroyHook, g_LocationHook
    global g_FocusCallbackPtr, g_MoveStartCbPtr, g_MoveEndCbPtr, g_DestroyCallbackPtr, g_LocationCbPtr
    if CFG_TestMode
        return

    ; WINEVENT_OUTOFCONTEXT (0) | WINEVENT_SKIPOWNPROCESS (2) = 2
    flags := 2

    g_FocusCallbackPtr := CallbackCreate(TrackFocusHistory, , 7)
    hFocusHook := DllCall("SetWinEventHook"
        , "UInt", 0x0003, "UInt", 0x0003, "Ptr", 0
        , "Ptr", g_FocusCallbackPtr, "UInt", 0, "UInt", 0, "UInt", flags)
    if !hFocusHook
        _Dbg("SetWinEventHook FOREGROUND failed")

    g_MoveStartCbPtr := CallbackCreate(_OnMoveStart, , 7)
    g_MoveStartHook := DllCall("SetWinEventHook"
        , "UInt", 0x000A, "UInt", 0x000A, "Ptr", 0
        , "Ptr", g_MoveStartCbPtr, "UInt", 0, "UInt", 0, "UInt", flags)

    g_MoveEndCbPtr := CallbackCreate(_OnMoveEnd, , 7)
    g_MoveEndHook := DllCall("SetWinEventHook"
        , "UInt", 0x000B, "UInt", 0x000B, "Ptr", 0
        , "Ptr", g_MoveEndCbPtr, "UInt", 0, "UInt", 0, "UInt", flags)

    g_DestroyCallbackPtr := CallbackCreate(_OnWindowDestroy, , 7)
    g_DestroyHook := DllCall("SetWinEventHook"
        , "UInt", 0x8001, "UInt", 0x8001, "Ptr", 0
        , "Ptr", g_DestroyCallbackPtr, "UInt", 0, "UInt", 0, "UInt", flags)

    g_LocationCbPtr := CallbackCreate(_OnLocationChange, , 7)
    g_LocationHook := DllCall("SetWinEventHook"
        , "UInt", 0x800B, "UInt", 0x800B, "Ptr", 0
        , "Ptr", g_LocationCbPtr, "UInt", 0, "UInt", 0, "UInt", flags)

    OnMessage(0x001A, _OnSettingChange)
    OnMessage(0x0218, _OnPowerBroadcast)
    OnMessage(0x007E, _OnDisplayChange)
}

Core_SessionInit() {
    global g_Layouts, g_DesktopLastWindow, g_LastDesktop, g_TilingMode, g_DebugRestore, g_DebugLogFile
    global g_StateSessionLayouts

    ; Iterate the real desktop count when known; fall back to a bounded scan only
    ; to recover stored entries (never as an assumed desktop maximum).
    deskCount := VDA.isLoaded ? VDA.GetDesktopCount() : 0
    if deskCount <= 0
        deskCount := 16
    loop deskCount {
        lastWnd := State_GetDesktopWindow(A_Index)
        if lastWnd {
            identity := State_GetDesktopWindowIdentity(A_Index)
            if _ValidateWindowIdentity(lastWnd, identity)
                g_DesktopLastWindow[A_Index] := lastWnd
        }
    }

    for hwnd, item in g_StateSessionLayouts {
        layout := item["layout"]
        if layout is Map
            g_Layouts[hwnd] := layout
        else if layout is Array && layout.Length = 4
            g_Layouts[hwnd] := Layout_FromLegacyPct(layout[1], layout[2], layout[3], layout[4])
    }

    if VDA.isLoaded
        g_LastDesktop := VDA.GetCurrent()

    if !CFG_TestMode && g_TilingMode = "Native" && IsSet(CFG_DriftCorrection) && CFG_DriftCorrection {
        interval := IsSet(CFG_DriftCheckInterval) ? CFG_DriftCheckInterval : 20000
        if interval < 15000
            interval := 20000
        SetTimer(_CheckLayoutRestores, interval)
    }

    if g_DebugRestore
        try FileDelete(g_DebugLogFile)
    _Dbg("script-start lastDesk=" g_LastDesktop " layouts=" g_Layouts.Count)
}

App_Shutdown(*) {
    global g_AppShuttingDown, hFocusHook, g_MoveStartHook, g_MoveEndHook, g_DestroyHook, g_LocationHook
    global g_FocusCallbackPtr, g_MoveStartCbPtr, g_MoveEndCbPtr, g_DestroyCallbackPtr, g_LocationCbPtr
    global g_AutoRestoreTimers, g_KeyLockActive
    if g_AppShuttingDown
        return
    g_AppShuttingDown := true

    try SetTimer(_ProcessWinEvents, 0)
    try SetTimer(_CheckLayoutRestores, 0)
    try SetTimer(_FlushLocationDirty, 0)
    try SetTimer(Perf_Flush, 0)
    try AC_StopInputHook()

    for hwnd, timer in g_AutoRestoreTimers {
        try SetTimer(timer, 0)
    }
    g_AutoRestoreTimers := Map()

    try State_FlushNow()
    try Perf_Flush()
    try VDA.Cleanup()

    for hook in [hFocusHook, g_MoveStartHook, g_MoveEndHook, g_DestroyHook, g_LocationHook] {
        if hook
            try DllCall("UnhookWinEvent", "Ptr", hook)
    }
    hFocusHook := g_MoveStartHook := g_MoveEndHook := g_DestroyHook := g_LocationHook := 0

    for ptr in [g_FocusCallbackPtr, g_MoveStartCbPtr, g_MoveEndCbPtr, g_DestroyCallbackPtr, g_LocationCbPtr] {
        if ptr
            try CallbackFree(ptr)
    }
    g_FocusCallbackPtr := g_MoveStartCbPtr := g_MoveEndCbPtr := g_DestroyCallbackPtr := g_LocationCbPtr := 0

    ; Disable any keyboard lock BEFORE releasing modifiers so input is never left
    ; blocked if a later step throws.
    if IsSet(g_KeyLockActive) && g_KeyLockActive {
        g_KeyLockActive := false
        try BlockInput(false)
    }
    global g_PrivacyBlackoutActive
    if IsSet(g_PrivacyBlackoutActive) && g_PrivacyBlackoutActive
        try _PrivacyBlackoutOff(false)
    try _OsdShutdown()
    try ReleaseModifiers()
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

_IsPWA(windowHandle) {
    if !windowHandle
        return false
    global g_PwaCache
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

    g_PwaCache[windowHandle] := false ; provisional until async check completes
    SetTimer(() => _AsyncCheckPWA(windowHandle, processId), -50)
    return false
}

_AsyncCheckPWA(hwnd, pid) {
    global g_PwaCache
    if !DllCall("IsWindow", "Ptr", hwnd)
        return
    try {
        if WinGetPID("ahk_id " hwnd) != pid
            return
    } catch {
        return
    }

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
    ; Cache by HWND only — Chromium PIDs can host mixed window types
    if DllCall("IsWindow", "Ptr", hwnd) {
        try {
            if WinGetPID("ahk_id " hwnd) != pid
                return
        } catch {
            return
        }
        g_PwaCache[hwnd] := isPwa
        if isPwa
            _AutoSnapFromMemory(hwnd)
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

_PersistToMemory(windowHandle, recordOrXf, yf := unset, wf := unset, hf := unset) {
    global CFG_TilingMemory, g_HWNDLayoutCache
    if !IsSet(CFG_TilingMemory) || !CFG_TilingMemory
        return
    windowSignature := _GetWinSignature(windowHandle)
    if windowSignature = ""
        return
    if recordOrXf is Map {
        record := recordOrXf
    } else {
        record := Layout_Slot(recordOrXf, yf, wf, hf)
    }
    g_HWNDLayoutCache[windowHandle] := record
    State_SetAppLayout(windowSignature, record)
}

_HasOtherWindowWithSignature(windowHandle, windowSignature) {
    global g_SigToHwndIndex, g_WinSigCache
    if g_SigToHwndIndex.Has(windowSignature) {
        for otherHwnd, _ in g_SigToHwndIndex[windowSignature] {
            if otherHwnd != windowHandle && _IsLiveWindow(otherHwnd)
                return true
        }
        return false
    }
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

    if g_HWNDLayoutCache.Has(windowHandle) {
        cached := g_HWNDLayoutCache[windowHandle]
        if cached is Map && cached.Has("kind")
            _ApplyLayoutRecord(cached, windowHandle, false)
        else if cached is Map && cached.Has("xf")
            _ApplyLayout(Integer(cached["xf"]), Integer(cached["yf"]), Integer(cached["wf"]), Integer(cached["hf"]), windowHandle, false)
        return
    }

    try {
        if _HasOtherWindowWithSignature(windowHandle, windowSignature)
            return
    } catch {
        return
    }

    if g_StateAppMaximized.Has(windowSignature) && g_StateAppMaximized[windowSignature] {
        WinMaximize("ahk_id " windowHandle)
        g_WinMaxState[windowHandle] := 1
        return
    }

    stored := State_GetAppLayout(windowSignature)
    if stored = "" || stored = 0
        return
    if stored is Map {
        g_HWNDLayoutCache[windowHandle] := stored
        _ApplyLayoutRecord(stored, windowHandle, false)
        return
    }
    if stored is String {
        rec := Layout_Deserialize(stored)
        if rec {
            g_HWNDLayoutCache[windowHandle] := rec
            _ApplyLayoutRecord(rec, windowHandle, false)
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

global g_Layouts    := Map()   ; hwnd → LayoutRecord
global g_LayoutFile := A_Temp "\ahk_layouts.ini"
global g_LastDesktop := 0
global g_MoveSuppressUntil := Map()
global g_UserMoveActive    := Map()
global g_AutoRestoreTimers := Map()
global g_WinSigCache  := Map()   ; hwnd → signature string
global g_WinMaxState  := Map()   ; hwnd → 1 if maximized, 0 otherwise
global g_HWNDLayoutCache := Map() ; hwnd → LayoutRecord — ephemeral per-instance position cache
global g_AcceptedGeometryCache := Map() ; hwnd → accepted visible rect (constrained windows)
global g_DebugRestore := IsSet(CFG_DebugRestore) ? CFG_DebugRestore : false
global g_DebugLogFile := A_Temp "\ahk_restore_debug.log"
global g_DbgBuffer := []
global g_DbgFlushScheduled := false

; ============================================================
; PER-DESKTOP FOCUS MEMORY
; ============================================================
global g_DesktopLastWindow := Map()

_Dbg(msg) {
    global g_DebugRestore, g_DbgBuffer, g_DbgFlushScheduled
    if !g_DebugRestore
        return
    ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    ms := Mod(A_TickCount, 1000000)
    g_DbgBuffer.Push(ts "." Format("{:06}", ms) " " msg)
    if !g_DbgFlushScheduled {
        g_DbgFlushScheduled := true
        SetTimer(_DbgFlush, -250)
    }
}

_DbgFlush() {
    global g_DebugRestore, g_DebugLogFile, g_DbgBuffer, g_DbgFlushScheduled
    g_DbgFlushScheduled := false
    if !g_DebugRestore || g_DbgBuffer.Length = 0
        return
    content := ""
    for line in g_DbgBuffer
        content .= line "`n"
    g_DbgBuffer := []
    try FileAppend(content, g_DebugLogFile, "UTF-8")
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
        onDesk := VDA.IsOnCurrentDesktop(hwnd)
        if onDesk = 1
            return true
        if onDesk = 0
            return false
        ; unknown: do not treat error as pinned
        return true
    } catch
        return true
}

_GetWindowState(hwnd, default := -2) {
    try return WinGetMinMax("ahk_id " hwnd)
    catch
        return default
}

_GetWindowOffsets(windowHandle, &offsetLeft, &offsetTop, &offsetRight, &offsetBottom) {
    off := Window_GetFrameOffsets(windowHandle)
    offsetLeft := off.left
    offsetTop := off.top
    offsetRight := off.right
    offsetBottom := off.bottom
    global g_WindowOffsetCache
    g_WindowOffsetCache[windowHandle] := [offsetLeft, offsetTop, offsetRight, offsetBottom]
}

_NeedsAutoRestore(windowHandle, layout) {
    if !(layout is Map)
        return false
    if !_IsLiveWindow(windowHandle)
        return false
    if _GetWindowState(windowHandle) != 0
        return false
    global g_AcceptedGeometryCache, g_TileGap
    _GetMonitorForHwnd(windowHandle, &L, &T, &R, &B)
    expected := Layout_ResolveVisibleRect(layout, L, T, R, B, layout["kind"] = "slot" ? g_TileGap : 0)
    if !expected
        return false
    actual := Window_GetVisibleRect(windowHandle)
    if !actual
        return false
    if g_AcceptedGeometryCache.Has(windowHandle) {
        accepted := g_AcceptedGeometryCache[windowHandle]
        if !Layout_RectsDiffer(actual, accepted, 4)
            return false
    }
    return Layout_RectsDiffer(actual, expected, 4)
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
    _ApplyLayoutRecord(layout, hwnd, false)
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
    if !VDA.isLoaded
        return WinGetID(winSelector)
    for hwnd in WinGetList(winSelector) {
        try {
            onDesk := VDA.IsOnCurrentDesktop(hwnd)
            if onDesk = 1
                return hwnd
            if onDesk = -1 {
                ; fallback compare when API unknown
                winDesk := VDA.GetWindowDesktop(hwnd)
                curDesk := VDA.GetCurrent()
                if winDesk != VDA.DESKTOP_UNKNOWN && winDesk = curDesk
                    return hwnd
            }
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

SafeReload() {
    State_PrepareHandoff()
    _SaveDesktopMemory()
    _SaveLayouts()
    State_FlushNow()
    ReleaseModifiers()
    try App_Shutdown()
    Run('"' A_AhkPath '" /restart "' A_ScriptFullPath '"')
    ExitApp()
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
    return _ApplyLayoutRecord(Layout_Slot(x_factor, y_factor, w_factor, h_factor), overrideHwnd, persist)
}

_ApplyLayoutRecord(record, overrideHwnd := 0, persist := true, targetMonitor := 0) {
    startTime := A_TickCount
    global g_MoveSuppressUntil, g_WinMaxState, g_Layouts, g_AcceptedGeometryCache, g_TileGap
    if !Layout_Validate(record) {
        Perf_Log("apply_layout", 0, "invalid_record", A_TickCount - startTime)
        return false
    }

    if overrideHwnd {
        windowHandle := overrideHwnd
        if !_IsLiveWindow(windowHandle) {
            Perf_Log("apply_layout", windowHandle, "invalid_hwnd", A_TickCount - startTime)
            return false
        }
        state := _GetWindowState(windowHandle)
        if (state = 1 || state = -1) {
            WinRestore("ahk_id " windowHandle)
            Sleep(30)
        }
        if targetMonitor > 0 {
            MonitorGetWorkArea(targetMonitor, &workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
        } else {
            _GetMonitorForHwnd(windowHandle, &workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
        }
    } else {
        if !WinExist("A") {
            Perf_Log("apply_layout", 0, "no_active_window", A_TickCount - startTime)
            return false
        }
        windowHandle := WinGetID("A")
        if !_IsOnCurrentDesktop(windowHandle) {
            Perf_Log("apply_layout", windowHandle, "wrong_desktop", A_TickCount - startTime)
            return false
        }
        _PrepareWindow()
        if targetMonitor > 0
            MonitorGetWorkArea(targetMonitor, &workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
        else
            GetActiveMonitorWorkArea(&workAreaLeft, &workAreaTop, &workAreaRight, &workAreaBottom)
    }

    g_MoveSuppressUntil[windowHandle] := A_TickCount + 1500
    gap := record["kind"] = "slot" ? g_TileGap : 0
    expectedVis := Layout_ResolveVisibleRect(record, workAreaLeft, workAreaTop, workAreaRight, workAreaBottom, gap)
    if !expectedVis {
        Perf_Log("apply_layout", windowHandle, "resolve_failed", A_TickCount - startTime)
        return false
    }

    _GetWindowOffsets(windowHandle, &offsetLeft, &offsetTop, &offsetRight, &offsetBottom)
    outer := Window_OuterFromVisibleRect(windowHandle, expectedVis)
    ; Initial target is always the left/top-anchored placement. Compensation for a
    ; window that rejects the requested size happens AFTER the move, based on the
    ; geometry the window actually accepted — never on its pre-move size.
    targetX := outer.x, targetY := outer.y, targetW := outer.w, targetH := outer.h
    requiredW := expectedVis.w
    requiredH := expectedVis.h

    actualOuter := Window_GetOuterRect(windowHandle)

    g_Layouts[windowHandle] := record
    g_WinMaxState[windowHandle] := 0

    outcome := "move"
    if actualOuter && actualOuter.x = targetX && actualOuter.y = targetY && actualOuter.w = targetW && actualOuter.h = targetH {
        outcome := "skip"
        _Dbg("apply skip-already-in-position " _WinSig(windowHandle))
        finalVis := Window_GetVisibleRect(windowHandle)
        if finalVis
            g_AcceptedGeometryCache[windowHandle] := finalVis
    } else {
        Perf_Increment("win_moves")
        ; 1. Apply the initial move.
        WinMove(targetX, targetY, targetW, targetH, "ahk_id " windowHandle)
        ; 2-4. Read what the window accepted; detect a minimum-size overflow.
        afterVis := Window_GetVisibleRect(windowHandle)
        finalVis := afterVis
        if afterVis && (afterVis.w > requiredW + 2 || afterVis.h > requiredH + 2) {
            ; 5. Compensate position according to the record's anchors.
            adj := _CompensateConstrainedPosition(record, afterVis, requiredW, requiredH, offsetLeft, offsetTop, targetX, targetY)
            if adj.x != targetX || adj.y != targetY {
                WinMove(adj.x, adj.y, , , "ahk_id " windowHandle)
                ; 6. Cache the FINAL post-compensation rectangle (re-read), so drift
                ; detection compares against where the window truly ended up.
                finalVis := Window_GetVisibleRect(windowHandle)
            }
        }
        if finalVis
            g_AcceptedGeometryCache[windowHandle] := finalVis
    }

    desk := VDA.isLoaded ? VDA.GetWindowDesktop(windowHandle) : 0
    _Dbg("apply " _WinSig(windowHandle) " desk=" desk " kind=" record["kind"])

    if persist {
        _PersistLayout(windowHandle)
        legacy := Layout_ToLegacyPct(record)
        _PersistToMemory(windowHandle, record)
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
        if _ApplyLayoutRecord(windowLayout, windowHandle, false) {
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
        try _ApplyLayoutRecord(windowLayout, windowHandle, false)
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
    global g_ScriptPaused, g_WindowOffsetCache, g_AcceptedGeometryCache, g_PrivacyBlackoutActive
    g_WindowOffsetCache := Map()
    g_AcceptedGeometryCache := Map()
    if g_PrivacyBlackoutActive {
        _PrivacyBlackoutOff(false)
        _PrivacyBlackoutOn()
    }
    if g_ScriptPaused
        return
    SetTimer(_RestoreAllDesktops, -1000)
    _ScheduleRestoreCurrentDesktop(1800)
}

_OnWindowDestroy(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    if idObject != 0 || idChild != 0
        return
    global g_PendingDestroy, g_WinSigCache, g_WinMaxState
    info := Map(
        "sig", g_WinSigCache.Has(hwnd) ? g_WinSigCache[hwnd] : "",
        "max", g_WinMaxState.Has(hwnd) ? g_WinMaxState[hwnd] : 0
    )
    g_PendingDestroy[hwnd] := info
    _ScheduleWinEventProcess()
}

_ProcessDestroyEvent(hwnd, info) {
    global g_WinSigCache, g_WinMaxState, CFG_TilingMemory, g_HWNDLayoutCache, g_ProcNameCache, g_WindowOffsetCache
    global g_Layouts, g_UserMoveActive, g_MoveSuppressUntil, g_PwaCache, g_LayoutCycleIdx
    global g_AutoRestoreTimers, g_AcceptedGeometryCache, g_SigToHwndIndex

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
    if g_AcceptedGeometryCache.Has(hwnd)
        g_AcceptedGeometryCache.Delete(hwnd)
    if g_AutoRestoreTimers.Has(hwnd) {
        try SetTimer(g_AutoRestoreTimers[hwnd], 0)
        g_AutoRestoreTimers.Delete(hwnd)
    }
    if g_HWNDLayoutCache.Has(hwnd)
        g_HWNDLayoutCache.Delete(hwnd)

    sig := info is Map && info.Has("sig") ? info["sig"] : ""
    isMax := info is Map && info.Has("max") ? info["max"] : 0
    if sig != "" && g_SigToHwndIndex.Has(sig) && g_SigToHwndIndex[sig].Has(hwnd)
        g_SigToHwndIndex[sig].Delete(hwnd)

    if g_WinSigCache.Has(hwnd)
        g_WinSigCache.Delete(hwnd)
    if g_WinMaxState.Has(hwnd)
        g_WinMaxState.Delete(hwnd)

    if sig = "" || !IsSet(CFG_TilingMemory) || !CFG_TilingMemory
        return
    State_SetAppMaximized(sig, isMax ? true : false)
}

_OnMoveStart(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    if idObject != 0 || idChild != 0
        return
    global g_PendingMoveStart
    g_PendingMoveStart[hwnd] := true
    _ScheduleWinEventProcess()
}

_ProcessMoveStartEvent(hwnd) {
    global g_UserMoveActive, g_Layouts
    if !g_Layouts.Has(hwnd)
        return
    g_UserMoveActive[hwnd] := true
}

_OnMoveEnd(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    if idObject != 0 || idChild != 0
        return
    global g_PendingMoveEnd
    g_PendingMoveEnd[hwnd] := true
    _ScheduleWinEventProcess()
}

_ProcessMoveEndEvent(hwnd) {
    global g_UserMoveActive, g_WinMaxState, g_Layouts, g_AcceptedGeometryCache
    try g_WinMaxState[hwnd] := (_GetWindowState(hwnd) = 1) ? 1 : 0
    if !g_Layouts.Has(hwnd)
        return
    try {
        if g_UserMoveActive.Has(hwnd)
            g_UserMoveActive.Delete(hwnd)

        mode := IsSet(CFG_ManualMoveBehavior) ? CFG_ManualMoveBehavior : "learn"

        if mode = "clear" {
            ; Stop tracking this window entirely after a manual move.
            g_Layouts.Delete(hwnd)
            _DeletePersistedLayout(hwnd)
            if g_AcceptedGeometryCache.Has(hwnd)
                g_AcceptedGeometryCache.Delete(hwnd)
            return
        }

        if mode = "restore" {
            ; Keep the prior record and snap the window back once the move settles.
            _ScheduleAutoRestore(hwnd, 120)
            return
        }

        ; Default "learn": capture where the user put the window as a visible-frame
        ; record, then update both session state and cross-session app memory.
        if _GetWindowState(hwnd) != 0
            return
        rec := Layout_VisibleFromWindow(hwnd)
        if !rec
            return
        g_Layouts[hwnd] := rec
        newVis := Window_GetVisibleRect(hwnd)
        if newVis
            g_AcceptedGeometryCache[hwnd] := newVis
        _PersistLayout(hwnd)
        _PersistToMemory(hwnd, rec)
    }
}

_OnLocationChange(hHook, event, hwnd, idObject, idChild, dwThread, dwTime) {
    ; Raw callback: primitives only
    if idObject != 0 || idChild != 0
        return
    global g_PendingLocationDirty
    g_PendingLocationDirty[hwnd] := true
    SetTimer(_FlushLocationDirty, -150)
}

_FlushLocationDirty() {
    global g_PendingLocationDirty
    if g_PendingLocationDirty.Count = 0
        return
    _ScheduleWinEventProcess()
}

_ProcessLocationChangeEvent(hwnd) {
    global g_Layouts, g_MoveSuppressUntil, g_UserMoveActive, g_ScriptPaused
    Perf_Increment("location_changes")
    if g_ScriptPaused
        return
    if !g_Layouts.Has(hwnd)
        return
    if g_UserMoveActive.Has(hwnd)
        return
    if g_MoveSuppressUntil.Has(hwnd) && g_MoveSuppressUntil[hwnd] > A_TickCount
        return
    layout := g_Layouts[hwnd]
    if _NeedsAutoRestore(hwnd, layout)
        _ScheduleAutoRestore(hwnd)
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
        pinned := VDA.IsPinned(hwnd)
        if pinned = 1
            return true
        winDesk := VDA.GetWindowDesktop(hwnd)
        if winDesk = VDA.DESKTOP_UNKNOWN
            return false
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
    if currentDesk != VDA.DESKTOP_UNKNOWN && WinExist("A")
        g_DesktopLastWindow[currentDesk] := WinGetID("A")

    ; Only commit internal desktop state and schedule restores if the switch
    ; actually succeeded; otherwise g_LastDesktop would diverge from reality.
    if !VDA.GoTo(n)
        return

    g_LastDesktop := n
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
        ; Do not follow the window or record it as the desktop's last window
        ; unless the move actually succeeded.
        if !VDA.MoveWindow(windowHandle, desktopIndex) {
            ShowOSD("Move to desktop " desktopIndex " failed")
            return
        }
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
    if g_Layouts.Has(windowHandle)
        record := g_Layouts[windowHandle]
    else
        record := Layout_Slot(12, 12, 75, 75)
    if WinGetMinMax("ahk_id " windowHandle) != 0
        WinRestore("ahk_id " windowHandle)
    _ApplyLayoutRecord(record, windowHandle, true, monitorIndex)
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
    snapshots := []
    curSnap := 0
    list := WinGetList()
    for index, hwnd in list {
        candidateCount++
        if !_IsLiveWindow(hwnd)
            continue
        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue
            if WinGetExStyle("ahk_id " hwnd) & 0x80
                continue
            cloaked := 0
            DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
            if cloaked
                continue
            if !_IsOnCurrentDesktop(hwnd)
                continue
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            mon := MonitorFromPoint(wx + ww // 2, wy + wh // 2)
            snap := {hwnd: hwnd, x: wx, y: wy, w: ww, h: wh, cx: wx + ww // 2, cy: wy + wh // 2, mon: mon, index: index}
            snapshots.Push(snap)
            if hwnd = curHwnd
                curSnap := snap
        }
    }
    if !curSnap {
        Perf_Log("focus_direction", dir, candidateCount, A_TickCount - startTime)
        return
    }

    tileGap := g_TileGap
    bestCandidateSnapshot := 0
    bestCandidateScore := 0
    for candidateSnapshot in snapshots {
        if candidateSnapshot.hwnd = curHwnd
            continue
        if _CandidateIsBackdropWindow(curSnap, candidateSnapshot)
            continue
        candidateScore := _EvaluateFocusCandidate(curSnap, candidateSnapshot, dir, tileGap)
        if !candidateScore
            continue
        if _FocusScoreIsBetter(candidateScore, bestCandidateScore) {
            bestCandidateScore := candidateScore
            bestCandidateSnapshot := candidateSnapshot
        }
    }

    winner := bestCandidateSnapshot ? bestCandidateSnapshot.hwnd : 0
    winnerSnap := bestCandidateSnapshot
    if winner {
        WinActivate("ahk_id " winner)
        if (IsSet(CFG_FocusTeleportMouse) && CFG_FocusTeleportMouse && winnerSnap)
            DllCall("SetCursorPos", "Int", winnerSnap.cx, "Int", winnerSnap.cy)
    }
    Perf_Log("focus_direction", dir, candidateCount, A_TickCount - startTime)
}

MonitorFromPoint(x, y) {
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
        if x >= L && x < R && y >= T && y < B
            return A_Index
    }
    return MonitorGetPrimary()
}

TrackFocusHistory(hHook, event, hwnd, idObject := 0, idChild := 0, dwThread := 0, dwTime := 0) {
    if idObject != 0 || idChild != 0
        return
    global g_PendingForegroundHwnd
    g_PendingForegroundHwnd := hwnd
    _ScheduleWinEventProcess()
}

_ProcessFocusEvent(hwnd) {
    startTime := A_TickCount
    Perf_Increment("foreground_events")
    global g_ScriptPaused, g_TilingMode, g_Layouts, g_WinSigCache, g_WinMaxState
    global CFG_TilingMemory, g_SigToHwndIndex
    try {
        AC_OnFocusChanged(hwnd)
        if g_ScriptPaused {
            Perf_Log("foreground_event", hwnd, "paused", A_TickCount - startTime)
            return
        }
        ; Desktop-change polling is recovery only when message hook is missing
        if VDA.isLoaded && !VDA.hasHookRegistered
            _HandleDesktopChange()
        if hwnd = 0 || !_IsLiveWindow(hwnd) {
            Perf_Log("foreground_event", hwnd, "invalid", A_TickCount - startTime)
            return
        }

        try {
            sig := g_WinSigCache.Has(hwnd) ? g_WinSigCache[hwnd] : _GetWinSignature(hwnd)
            if sig != "" {
                g_WinSigCache[hwnd] := sig
                if !g_SigToHwndIndex.Has(sig)
                    g_SigToHwndIndex[sig] := Map()
                g_SigToHwndIndex[sig][hwnd] := true
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
