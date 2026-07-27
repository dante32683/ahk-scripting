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
; Must be set BEFORE the tiling #Include files: CapsLock+Esc reload often
; keeps CapsLock held, so #HotIf can evaluate during load. An unset
; g_TilingMode throws a brief error dialog mentioning FancyZones/Native.
global g_TilingMode := IsSet(CFG_TilingMode) ? CFG_TilingMode : "Native"
if g_TilingMode != "Native" && g_TilingMode != "FancyZones"
    g_TilingMode := "Native"
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
global g_SigToHwndIndex := Map()  ; signature -> Map of hwnd -> true
; HWNDs that must not auto-snap from persistent memory this session
; (cleared on explicit tile, destroy, or script reload via Map reset).
global g_SessionNoAutoSnap := Map()

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
        catch as e
            _Dbg("event-error movestart hwnd=" hwnd " " e.Message)
    }
    for hwnd, _ in moveEnds {
        try _ProcessMoveEndEvent(hwnd)
        catch as e
            _Dbg("event-error moveend hwnd=" hwnd " " e.Message)
    }
    for hwnd, info in destroys {
        try _ProcessDestroyEvent(hwnd, info)
        catch as e
            _Dbg("event-error destroy hwnd=" hwnd " " e.Message)
    }
    if focusHwnd {
        try _ProcessFocusEvent(focusHwnd)
        catch as e
            _Dbg("event-error focus hwnd=" focusHwnd " " e.Message)
    }
    for hwnd, _ in locationDirty {
        try _ProcessLocationChangeEvent(hwnd)
        catch as e
            _Dbg("event-error location hwnd=" hwnd " " e.Message)
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
    if !hFocusHook {
        _Dbg("SetWinEventHook FOREGROUND failed")
        try CallbackFree(g_FocusCallbackPtr)
        g_FocusCallbackPtr := 0
    }

    g_MoveStartCbPtr := CallbackCreate(_OnMoveStart, , 7)
    g_MoveStartHook := DllCall("SetWinEventHook"
        , "UInt", 0x000A, "UInt", 0x000A, "Ptr", 0
        , "Ptr", g_MoveStartCbPtr, "UInt", 0, "UInt", 0, "UInt", flags)
    if !g_MoveStartHook {
        _Dbg("SetWinEventHook MOVESIZESTART failed")
        try CallbackFree(g_MoveStartCbPtr)
        g_MoveStartCbPtr := 0
    }

    g_MoveEndCbPtr := CallbackCreate(_OnMoveEnd, , 7)
    g_MoveEndHook := DllCall("SetWinEventHook"
        , "UInt", 0x000B, "UInt", 0x000B, "Ptr", 0
        , "Ptr", g_MoveEndCbPtr, "UInt", 0, "UInt", 0, "UInt", flags)
    if !g_MoveEndHook {
        _Dbg("SetWinEventHook MOVESIZEEND failed")
        try CallbackFree(g_MoveEndCbPtr)
        g_MoveEndCbPtr := 0
    }

    g_DestroyCallbackPtr := CallbackCreate(_OnWindowDestroy, , 7)
    g_DestroyHook := DllCall("SetWinEventHook"
        , "UInt", 0x8001, "UInt", 0x8001, "Ptr", 0
        , "Ptr", g_DestroyCallbackPtr, "UInt", 0, "UInt", 0, "UInt", flags)
    if !g_DestroyHook {
        _Dbg("SetWinEventHook OBJECT_DESTROY failed")
        try CallbackFree(g_DestroyCallbackPtr)
        g_DestroyCallbackPtr := 0
    }

    g_LocationCbPtr := CallbackCreate(_OnLocationChange, , 7)
    g_LocationHook := DllCall("SetWinEventHook"
        , "UInt", 0x800B, "UInt", 0x800B, "Ptr", 0
        , "Ptr", g_LocationCbPtr, "UInt", 0, "UInt", 0, "UInt", flags)
    if !g_LocationHook {
        _Dbg("SetWinEventHook LOCATIONCHANGE failed")
        try CallbackFree(g_LocationCbPtr)
        g_LocationCbPtr := 0
    }

    OnMessage(0x001A, _OnSettingChange)
    OnMessage(0x0218, _OnPowerBroadcast)
    OnMessage(0x007E, _OnDisplayChange)
}

Core_SessionInit() {
    global g_Layouts, g_DesktopLastWindow, g_LastDesktop, g_TilingMode, g_DebugRestore, g_DebugLogFile
    global g_StateSessionLayouts, g_StateDesktopWindows

    ; Recover exactly the desktop entries that were actually persisted, rather than
    ; guessing a maximum desktop count and scanning a fixed range.
    for desk, lastWnd in g_StateDesktopWindows {
        if lastWnd {
            identity := State_GetDesktopWindowIdentity(desk)
            if _ValidateWindowIdentity(lastWnd, identity)
                g_DesktopLastWindow[desk] := lastWnd
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
    try _CancelDesktopFocusRestore()

    for hwnd, timer in g_AutoRestoreTimers {
        try SetTimer(timer, 0)
    }
    g_AutoRestoreTimers := Map()
    global g_GeometrySettleTimers
    if IsSet(g_GeometrySettleTimers) {
        for hwnd, timer in g_GeometrySettleTimers {
            try SetTimer(timer, 0)
        }
        g_GeometrySettleTimers := Map()
    }

    ; Collect live maps into StateStore before the final flush so reload/exit
    ; does not lose session layouts or desktop-last-window entries that were
    ; only held in Core globals.
    try _SaveDesktopMemory()
    try _SaveLayouts()
    try State_FlushNow()
    try Perf_Flush()
    ; Flush any buffered debug lines before exit; a pending _DbgFlush one-shot would
    ; otherwise be canceled by process teardown, losing the final diagnostics.
    try SetTimer(_DbgFlush, 0)
    try _DbgFlush()
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

; clearPersistent=false: drop this HWND's session layout only.
; clearPersistent=true: also forget the app's remembered cross-session layout so it
; cannot return after focus changes or script restart.
; Either way, suppress auto-snap for this HWND for the rest of the session so a
; remaining persistent layout cannot immediately return on the next focus.
_ClearWindowLayout(clearPersistent := false) {
    global g_Layouts, g_HWNDLayoutCache, g_AcceptedGeometryCache, g_WinSigCache
    global g_SessionNoAutoSnap, CFG_TilingMemory
    hwnd := WinExist("A") ? WinGetID("A") : 0
    if !hwnd
        return

    hadSession := g_Layouts.Has(hwnd)
    if hadSession {
        g_Layouts.Delete(hwnd)
        _DeletePersistedLayout(hwnd)
    }
    if g_AcceptedGeometryCache.Has(hwnd)
        g_AcceptedGeometryCache.Delete(hwnd)
    if g_HWNDLayoutCache.Has(hwnd)
        g_HWNDLayoutCache.Delete(hwnd)
    g_SessionNoAutoSnap[hwnd] := true

    if clearPersistent && IsSet(CFG_TilingMemory) && CFG_TilingMemory {
        sig := g_WinSigCache.Has(hwnd) ? g_WinSigCache[hwnd] : _GetWinSignature(hwnd)
        if sig != "" {
            State_DeleteAppLayout(sig)
            ShowOSD("Layout forgotten")
            return
        }
    }
    if hadSession || clearPersistent
        ShowOSD("Layout cleared")
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

    try {
        processId := WinGetPID("ahk_id " windowHandle)
    } catch {
        return false
    }

    windowTitle := WinGetTitle("ahk_id " windowHandle)
    titleLooksLikePwa := false
    if (processName = "msedge.exe" && !RegExMatch(windowTitle, "i)[\-–—]\s+(?:InPrivate\s+[\-–—]\s+|InPrivate\s+)?Microsoft\s+Edge\s*$"))
        titleLooksLikePwa := true
    if (processName = "chrome.exe" && !RegExMatch(windowTitle, "i)[\-–—]\s+Google\s+Chrome\s*$"))
        titleLooksLikePwa := true

    ; Title heuristic is provisional only — always verify via command line.
    g_PwaCache[windowHandle] := titleLooksLikePwa
    SetTimer(() => _AsyncCheckPWA(windowHandle, processId), -50)
    return titleLooksLikePwa
}

_RemoveFromSigIndex(hwnd, sig) {
    global g_SigToHwndIndex
    if sig = "" || !g_SigToHwndIndex.Has(sig)
        return
    if g_SigToHwndIndex[sig].Has(hwnd)
        g_SigToHwndIndex[sig].Delete(hwnd)
    if g_SigToHwndIndex[sig].Count = 0
        g_SigToHwndIndex.Delete(sig)
}

_IndexWinSignature(hwnd, sig) {
    global g_SigToHwndIndex, g_WinSigCache
    if sig = ""
        return
    ; Drop any previous signature for this HWND before indexing the new one.
    if g_WinSigCache.Has(hwnd) && g_WinSigCache[hwnd] != sig
        _RemoveFromSigIndex(hwnd, g_WinSigCache[hwnd])
    g_WinSigCache[hwnd] := sig
    if !g_SigToHwndIndex.Has(sig)
        g_SigToHwndIndex[sig] := Map()
    g_SigToHwndIndex[sig][hwnd] := true
}

_AsyncCheckPWA(hwnd, pid) {
    global g_PwaCache, g_WinSigCache
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

    ; Re-validate after the WMI query: HWND reuse or process exit must abort.
    if !DllCall("IsWindow", "Ptr", hwnd)
        return
    try {
        if WinGetPID("ahk_id " hwnd) != pid
            return
    } catch {
        return
    }

    wasPwa := g_PwaCache.Has(hwnd) ? g_PwaCache[hwnd] : false
    oldSig := g_WinSigCache.Has(hwnd) ? g_WinSigCache[hwnd] : ""
    ; Final HWND-specific classification (never PID-wide — Chromium hosts mixed types).
    g_PwaCache[hwnd] := isPwa

    if wasPwa = isPwa && oldSig != "" {
        ; Classification unchanged and already indexed — nothing to reindex.
        if isPwa
            _AutoSnapFromMemory(hwnd)
        return
    }

    ; Provisional generic signature (e.g. chrome.exe) may now become chrome.exe:Title.
    if oldSig != ""
        _RemoveFromSigIndex(hwnd, oldSig)
    if g_WinSigCache.Has(hwnd)
        g_WinSigCache.Delete(hwnd)

    newSig := _GetWinSignature(hwnd)
    if newSig != ""
        _IndexWinSignature(hwnd, newSig)

    ; Retry layout lookup under the final signature once identity is known.
    if isPwa || (oldSig != "" && newSig != "" && oldSig != newSig)
        _AutoSnapFromMemory(hwnd)
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
    ; Index is an optimization only. An existing bucket that lacks another live
    ; HWND is NOT proof that no peer exists — unfocused windows may never have
    ; been indexed. Always fall through to enumeration when the index is empty
    ; or inconclusive.
    if g_SigToHwndIndex.Has(windowSignature) {
        for otherHwnd, _ in g_SigToHwndIndex[windowSignature] {
            if otherHwnd != windowHandle && _IsLiveWindow(otherHwnd)
                return true
        }
    }
    signatureProcess := InStr(windowSignature, ":") ? StrSplit(windowSignature, ":")[1] : windowSignature
    for otherHwnd in WinGetList() {
        if otherHwnd = windowHandle || !_IsLiveWindow(otherHwnd)
            continue
        if _GetProcessName(otherHwnd) != signatureProcess
            continue
        otherSignature := g_WinSigCache.Has(otherHwnd) ? g_WinSigCache[otherHwnd] : _GetWinSignature(otherHwnd)
        if otherSignature = windowSignature {
            ; Opportunistically index discovered peers for later fast path.
            if otherSignature != ""
                _IndexWinSignature(otherHwnd, otherSignature)
            return true
        }
    }
    return false
}

_AutoSnapFromMemory(windowHandle) {
    global CFG_TilingMemory, g_WinMaxState, g_HWNDLayoutCache, g_WinSigCache, g_SessionNoAutoSnap
    if !IsSet(CFG_TilingMemory) || !CFG_TilingMemory
        return
    if !_IsLiveWindow(windowHandle)
        return
    if g_SessionNoAutoSnap.Has(windowHandle)
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
; g_TilingMode is initialized above, before WindowTiling_* includes.

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
        ; Unknown/error is not success and not pinned. For active-window actions
        ; (tile/maximize/remap) stay permissive so a flaky VDA query does not
        ; brick the hotkey; focus candidacy uses the strict check below.
        return true
    } catch
        return true
}

; Shared eligibility for directional focus / important-window commands.
; Prefer same-monitor candidates at scoring time; this only gates visibility,
; tool-window, cloaked, and current-desktop/pinned membership.
_IsFocusEligible(hwnd) {
    if !_IsLiveWindow(hwnd)
        return false
    try {
        if WinGetMinMax("ahk_id " hwnd) = -1
            return false
        if WinGetExStyle("ahk_id " hwnd) & 0x80  ; WS_EX_TOOLWINDOW
            return false
        cloaked := 0
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
        if cloaked
            return false
        if VDA.isLoaded {
            onDesk := VDA.IsOnCurrentDesktop(hwnd)
            ; Strict: require an explicit yes. Unknown/error is not success.
            if onDesk != 1
                return false
        }
    } catch {
        return false
    }
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
    global g_ScriptPaused, g_AutoRestoreRetryCount
    if g_ScriptPaused
        return
    if !g_Layouts.Has(hwnd) || !_IsLiveWindow(hwnd)
        return
    if g_UserMoveActive.Has(hwnd)
        return
    if g_MoveSuppressUntil.Has(hwnd) && g_MoveSuppressUntil[hwnd] > A_TickCount {
        ; Do not drop restores that fire during move suppression — reschedule.
        if !IsSet(g_AutoRestoreRetryCount)
            g_AutoRestoreRetryCount := Map()
        retries := g_AutoRestoreRetryCount.Has(hwnd) ? g_AutoRestoreRetryCount[hwnd] : 0
        if retries >= 5
            return
        g_AutoRestoreRetryCount[hwnd] := retries + 1
        remaining := g_MoveSuppressUntil[hwnd] - A_TickCount
        _ScheduleAutoRestore(hwnd, Min(Max(remaining + 20, 50), 2000))
        return
    }
    if IsSet(g_AutoRestoreRetryCount) && g_AutoRestoreRetryCount.Has(hwnd)
        g_AutoRestoreRetryCount.Delete(hwnd)
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
    global g_LayoutApplyGeneration
    if !IsSet(g_LayoutApplyGeneration)
        g_LayoutApplyGeneration := Map()
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
        ; Cancel any prior settle before skip/fail paths can leave a stale timer.
        _CancelGeometrySettle(windowHandle)
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
        _CancelGeometrySettle(windowHandle)
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

    applyGen := (g_LayoutApplyGeneration.Has(windowHandle) ? g_LayoutApplyGeneration[windowHandle] : 0) + 1
    g_LayoutApplyGeneration[windowHandle] := applyGen

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
    ; Explicit tiling re-enables auto-snap for this HWND.
    global g_SessionNoAutoSnap
    if g_SessionNoAutoSnap.Has(windowHandle)
        g_SessionNoAutoSnap.Delete(windowHandle)

    outcome := "move"
    if actualOuter && actualOuter.x = targetX && actualOuter.y = targetY && actualOuter.w = targetW && actualOuter.h = targetH {
        outcome := "skip"
        _Dbg("apply skip-already-in-position " _WinSig(windowHandle))
        finalVis := Window_GetVisibleRect(windowHandle)
        if finalVis
            g_AcceptedGeometryCache[windowHandle] := finalVis
    } else {
        Perf_Increment("win_moves")
        ; The liveness check above happened before WinRestore/Sleep and several
        ; geometry queries, so the window may have closed in between. Re-check
        ; here and treat a vanished window as a normal no-op, not an error.
        if !DllCall("IsWindow", "Ptr", windowHandle) {
            Perf_Log("apply_layout", windowHandle, "window_gone", A_TickCount - startTime)
            return false
        }
        ; 1. Apply the initial move.
        try {
            WinMove(targetX, targetY, targetW, targetH, "ahk_id " windowHandle)
        } catch {
            Perf_Log("apply_layout", windowHandle, "move_failed", A_TickCount - startTime)
            return false
        }
        ; 2-4. Read what the window accepted; detect a minimum-size overflow.
        afterVis := Window_GetVisibleRect(windowHandle)
        finalVis := afterVis
        if afterVis && (afterVis.w > requiredW + 2 || afterVis.h > requiredH + 2) {
            ; 5. Compensate position according to the record's anchors.
            adj := _CompensateConstrainedPosition(record, afterVis, requiredW, requiredH, offsetLeft, offsetTop, targetX, targetY)
            if adj.x != targetX || adj.y != targetY {
                try WinMove(adj.x, adj.y, , , "ahk_id " windowHandle)
                ; 6. Cache the FINAL post-compensation rectangle (re-read), so drift
                ; detection compares against where the window truly ended up.
                finalVis := Window_GetVisibleRect(windowHandle)
            }
        }
        if finalVis
            g_AcceptedGeometryCache[windowHandle] := finalVis
        ; Some apps enforce min size / adjust frames shortly after WinMove.
        ; Schedule a short bounded settle so transient geometry is not fought forever.
        _ScheduleGeometrySettle(windowHandle, record, requiredW, requiredH, offsetLeft, offsetTop, targetX, targetY, applyGen)
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

; Bounded settle: 3 checks over ~50/100/150 ms after WinMove so apps that
; enforce minimum size shortly after the move get a corrected accepted rect.
global g_GeometrySettleTimers := Map()
global g_LayoutApplyGeneration := Map()
global g_AutoRestoreRetryCount := Map()

_CancelGeometrySettle(hwnd) {
    global g_GeometrySettleTimers
    if !g_GeometrySettleTimers.Has(hwnd)
        return
    try SetTimer(g_GeometrySettleTimers[hwnd], 0)
    g_GeometrySettleTimers.Delete(hwnd)
}

_ScheduleGeometrySettle(hwnd, record, requiredW, requiredH, offsetLeft, offsetTop, targetX, targetY, applyGen := 0) {
    global g_GeometrySettleTimers
    _CancelGeometrySettle(hwnd)
    state := Map("n", 0, "gen", applyGen, "layoutKey", Layout_Serialize(record)
        , "record", record, "reqW", requiredW, "reqH", requiredH
        , "ol", offsetLeft, "ot", offsetTop, "tx", targetX, "ty", targetY)
    tick := () => _GeometrySettleTick(hwnd, state)
    g_GeometrySettleTimers[hwnd] := tick
    SetTimer(tick, -50)
}

_GeometrySettleTick(hwnd, state) {
    global g_GeometrySettleTimers, g_AcceptedGeometryCache, g_Layouts, g_MoveSuppressUntil
    global g_LayoutApplyGeneration, g_UserMoveActive
    state["n"] += 1
    if !DllCall("IsWindow", "Ptr", hwnd) || !g_Layouts.Has(hwnd) {
        if g_GeometrySettleTimers.Has(hwnd)
            g_GeometrySettleTimers.Delete(hwnd)
        return
    }
    if state["gen"] && g_LayoutApplyGeneration.Has(hwnd) && g_LayoutApplyGeneration[hwnd] != state["gen"] {
        if g_GeometrySettleTimers.Has(hwnd)
            g_GeometrySettleTimers.Delete(hwnd)
        return
    }
    if Layout_Serialize(g_Layouts[hwnd]) != state["layoutKey"] {
        if g_GeometrySettleTimers.Has(hwnd)
            g_GeometrySettleTimers.Delete(hwnd)
        return
    }
    if g_UserMoveActive.Has(hwnd) {
        if g_GeometrySettleTimers.Has(hwnd)
            g_GeometrySettleTimers.Delete(hwnd)
        return
    }
    if _GetWindowState(hwnd) != 0 {
        if g_GeometrySettleTimers.Has(hwnd)
            g_GeometrySettleTimers.Delete(hwnd)
        return
    }
    vis := Window_GetVisibleRect(hwnd)
    if vis {
        if (vis.w > state["reqW"] + 2 || vis.h > state["reqH"] + 2) {
            adj := _CompensateConstrainedPosition(state["record"], vis, state["reqW"], state["reqH"]
                , state["ol"], state["ot"], state["tx"], state["ty"])
            if adj.x != state["tx"] || adj.y != state["ty"] {
                g_MoveSuppressUntil[hwnd] := A_TickCount + 1500
                ; Runs 50-150 ms after the original move; the window may be gone.
                try WinMove(adj.x, adj.y, , , "ahk_id " hwnd)
                vis := Window_GetVisibleRect(hwnd)
            }
        }
        if vis
            g_AcceptedGeometryCache[hwnd] := vis
    }
    if state["n"] < 3 {
        ; Inter-tick delays of 50 ms → fires near 50 / 100 / 150 ms from start.
        SetTimer(g_GeometrySettleTimers[hwnd], -50)
        return
    }
    if g_GeometrySettleTimers.Has(hwnd)
        g_GeometrySettleTimers.Delete(hwnd)
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

_InvalidateGeometryCaches() {
    global g_WindowOffsetCache, g_AcceptedGeometryCache
    g_WindowOffsetCache := Map()
    g_AcceptedGeometryCache := Map()
}

_OnSettingChange(wParam, *) {
    global g_ScriptPaused
    if g_ScriptPaused
        return
    if wParam = 0x2F {
        _Dbg("wm-settingchange SPI_SETWORKAREA")
        _InvalidateGeometryCaches()
        SetTimer(_RestoreAllDesktops, -300)
        _ScheduleRestoreCurrentDesktop(1200)
    }
}

_OnPowerBroadcast(wParam, lParam, *) {
    global g_ScriptPaused
    if g_ScriptPaused
        return
    if wParam = 0x12 || wParam = 0x7 {
        _InvalidateGeometryCaches()
        SetTimer(_RestoreAllDesktops, -5000)
        _ScheduleRestoreCurrentDesktop(6200)
    }
}

_OnDisplayChange(*) {
    global g_ScriptPaused, g_PrivacyBlackoutActive
    _InvalidateGeometryCaches()
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
    global g_AutoRestoreTimers, g_AcceptedGeometryCache, g_SigToHwndIndex, g_SessionNoAutoSnap
    global g_GeometrySettleTimers, g_DesktopLastWindow, g_AutoRestoreRetryCount, g_LayoutApplyGeneration

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
    if g_SessionNoAutoSnap.Has(hwnd)
        g_SessionNoAutoSnap.Delete(hwnd)
    if g_AutoRestoreTimers.Has(hwnd) {
        try SetTimer(g_AutoRestoreTimers[hwnd], 0)
        g_AutoRestoreTimers.Delete(hwnd)
    }
    if g_AutoRestoreRetryCount.Has(hwnd)
        g_AutoRestoreRetryCount.Delete(hwnd)
    if g_LayoutApplyGeneration.Has(hwnd)
        g_LayoutApplyGeneration.Delete(hwnd)
    if g_GeometrySettleTimers.Has(hwnd) {
        try SetTimer(g_GeometrySettleTimers[hwnd], 0)
        g_GeometrySettleTimers.Delete(hwnd)
    }
    if g_HWNDLayoutCache.Has(hwnd)
        g_HWNDLayoutCache.Delete(hwnd)

    ; Drop dead HWND from desktop memory (Core + persistent StateStore).
    desksToForget := []
    for desk, mappedHwnd in g_DesktopLastWindow {
        if mappedHwnd = hwnd
            desksToForget.Push(desk)
    }
    for desk in desksToForget {
        g_DesktopLastWindow.Delete(desk)
        State_DeleteDesktopWindow(desk)
    }
    State_ClearDesktopWindowByHwnd(hwnd)

    ; Pending autocorrect undo must not survive HWND reuse.
    global AC_LastHwnd
    if IsSet(AC_LastHwnd) && AC_LastHwnd = hwnd
        AC_ClearLastCorrection()

    sig := info is Map && info.Has("sig") ? info["sig"] : ""
    isMax := info is Map && info.Has("max") ? info["max"] : 0
    if sig != ""
        _RemoveFromSigIndex(hwnd, sig)
    ; Drop any pending location/move work for the destroyed HWND so it cannot
    ; be processed after the handle is reused.
    global g_PendingLocationDirty, g_PendingMoveStart, g_PendingMoveEnd
    if g_PendingLocationDirty.Has(hwnd)
        g_PendingLocationDirty.Delete(hwnd)
    if g_PendingMoveStart.Has(hwnd)
        g_PendingMoveStart.Delete(hwnd)
    if g_PendingMoveEnd.Has(hwnd)
        g_PendingMoveEnd.Delete(hwnd)

    if g_WinSigCache.Has(hwnd)
        g_WinSigCache.Delete(hwnd)
    if g_WinMaxState.Has(hwnd)
        g_WinMaxState.Delete(hwnd)

    if sig = "" || !IsSet(CFG_TilingMemory) || !CFG_TilingMemory
        return
    ; Only persist maximize=true on destroy. Writing false when a non-max peer
    ; closes would wipe maximize memory for other same-signature windows.
    if isMax
        State_SetAppMaximized(sig, true)
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
            ; Stop tracking this window entirely after a manual move, and suppress
            ; persistent auto-snap for the rest of the session (same as Delete).
            global g_SessionNoAutoSnap, g_HWNDLayoutCache
            g_Layouts.Delete(hwnd)
            _DeletePersistedLayout(hwnd)
            if g_AcceptedGeometryCache.Has(hwnd)
                g_AcceptedGeometryCache.Delete(hwnd)
            if g_HWNDLayoutCache.Has(hwnd)
                g_HWNDLayoutCache.Delete(hwnd)
            g_SessionNoAutoSnap[hwnd] := true
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
    global g_Layouts, g_MoveSuppressUntil, g_UserMoveActive, g_ScriptPaused, g_PendingLocationDirty
    Perf_Increment("location_changes")
    if g_ScriptPaused
        return
    if !g_Layouts.Has(hwnd)
        return
    if g_UserMoveActive.Has(hwnd)
        return
    if g_MoveSuppressUntil.Has(hwnd) && g_MoveSuppressUntil[hwnd] > A_TickCount {
        ; Do not discard: keep the HWND dirty and retry after suppression ends.
        g_PendingLocationDirty[hwnd] := true
        remaining := g_MoveSuppressUntil[hwnd] - A_TickCount
        SetTimer(_FlushLocationDirty, -Max(remaining + 30, 50))
        return
    }
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
    global g_ScriptPaused
    if g_ScriptPaused
        return
    if !VDA.isLoaded
        return
    try currentDesk := VDA.GetCurrent()
    catch
        return
    _HandleDesktopChangeFromMsg(currentDesk)
}

; HWND that was just moved off the departing desktop; must not be saved as that
; desktop's last window when the subsequent switch notification arrives.
global g_DesktopExcludeHwnd := 0
global g_PendingDesktopNotify := 0
global g_DesktopWatchdogTarget := 0
global g_DesktopFocusGeneration := 0
global g_DesktopRestoreCallback := 0

_HandleDesktopChangeFromMsg(currentDesk) {
    global g_PendingDesktopNotify
    ; Coalesce rapid notifications: keep only the latest target and process once.
    g_PendingDesktopNotify := currentDesk
    SetTimer(_FlushDesktopNotify, -1)
}

_FlushDesktopNotify() {
    global g_PendingDesktopNotify, g_DesktopExcludeHwnd
    target := g_PendingDesktopNotify
    g_PendingDesktopNotify := 0
    if !target
        return
    exclude := g_DesktopExcludeHwnd
    g_DesktopExcludeHwnd := 0
    _CommitDesktopTransition(target, exclude)
}

_ForgetDesktopWindow(desk) {
    global g_DesktopLastWindow
    if g_DesktopLastWindow.Has(desk)
        g_DesktopLastWindow.Delete(desk)
    State_DeleteDesktopWindow(desk)
}

; Hotkey path: capture WinGetID("A") BEFORE the switch (main-branch behavior).
_RememberActiveWindowForDesktop(desk, excludeHwnd := 0) {
    global g_DesktopLastWindow
    if desk <= 0
        return
    if !WinExist("A")
        return
    try hwnd := WinGetID("A")
    catch
        return
    if !hwnd || (excludeHwnd && hwnd = excludeHwnd)
        return
    if !WinExist("ahk_id " hwnd)
        return
    g_DesktopLastWindow[desk] := hwnd
    State_SetDesktopWindow(desk, hwnd)
}

; External/OS path: after the switch, "A" is already on the new desk — use history.
_RememberDepartingDesktopFromHistory(fromDesk, excludeHwnd := 0) {
    global g_DesktopLastWindow, g_FocusHistory
    if fromDesk <= 0
        return
    historyIndex := g_FocusHistory.Length
    while historyIndex > 0 {
        prevHwnd := g_FocusHistory[historyIndex]
        if excludeHwnd && prevHwnd = excludeHwnd {
            historyIndex--
            continue
        }
        if prevHwnd && WinExist("ahk_id " prevHwnd) && _IsWindowOnDesktop(prevHwnd, fromDesk) {
            g_DesktopLastWindow[fromDesk] := prevHwnd
            State_SetDesktopWindow(fromDesk, prevHwnd)
            return
        }
        historyIndex--
    }
}

; Focus restore timing:
; - CapsLock+N is already on the target desktop quickly → short delay
; - Trackpad/OS swipe needs more settle time → 150 ms (main-branch default)
global g_DesktopFocusHotkeyDelay := 50
global g_DesktopFocusSwipeDelay := 150

_ScheduleDesktopFocusRestore(desk, gen, delayMs) {
    global g_DesktopRestoreCallback
    _CancelDesktopFocusRestore()
    g_DesktopRestoreCallback := _RestoreFocusOnDesktop.Bind(desk, gen)
    SetTimer(g_DesktopRestoreCallback, -delayMs)
}

; Bookkeeping for external/OS desktop changes (swipe, Win+Ctrl+Left, VDA hook).
; Hotkey GotoDesktop does its own immediate remember+restore like main.
_CommitDesktopTransition(newDesk, excludeHwnd := 0) {
    global g_LastDesktop, g_ScriptPaused, g_DesktopWatchdogTarget, g_DesktopFocusGeneration
    global g_DesktopFocusSwipeDelay
    if g_ScriptPaused
        return
    if !newDesk || newDesk = VDA.DESKTOP_UNKNOWN
        return
    if newDesk = g_LastDesktop
        return

    fromDesk := g_LastDesktop
    _RememberDepartingDesktopFromHistory(fromDesk, excludeHwnd)

    g_LastDesktop := newDesk
    g_DesktopWatchdogTarget := 0
    g_DesktopFocusGeneration += 1
    _ScheduleDesktopFocusRestore(newDesk, g_DesktopFocusGeneration, g_DesktopFocusSwipeDelay)
    _ScheduleDesktopRestore(newDesk)
}

_CancelDesktopFocusRestore() {
    global g_DesktopRestoreCallback
    if g_DesktopRestoreCallback {
        try SetTimer(g_DesktopRestoreCallback, 0)
        g_DesktopRestoreCallback := 0
    }
}

_ScheduleDesktopWatchdog(expectedDesk) {
    global g_DesktopWatchdogTarget
    g_DesktopWatchdogTarget := expectedDesk
    SetTimer(_DesktopSwitchWatchdog, -250)
}

_DesktopSwitchWatchdog() {
    global g_DesktopWatchdogTarget, g_DesktopExcludeHwnd, g_LastDesktop
    expected := g_DesktopWatchdogTarget
    g_DesktopWatchdogTarget := 0
    if !expected || !VDA.isLoaded
        return
    try cur := VDA.GetCurrent()
    catch
        return
    if cur = VDA.DESKTOP_UNKNOWN
        return
    if cur = g_LastDesktop
        return
    exclude := g_DesktopExcludeHwnd
    g_DesktopExcludeHwnd := 0
    _CommitDesktopTransition(cur, exclude)
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
    ; Persist BOTH transitions to app memory. Persisting only the maximize would leave a
    ; stale maximized=1 after the user restores a window, wrongly maximizing future ones.
    global CFG_TilingMemory
    isMaxNow := WinGetMinMax("ahk_id " hwnd) != 1
    if isMaxNow {
        WinMaximize("ahk_id " hwnd)
        g_WinMaxState[hwnd] := 1
    } else {
        WinRestore("ahk_id " hwnd)
        g_WinMaxState[hwnd] := 0
        _ScheduleAutoRestore(hwnd, 50)
    }
    if IsSet(CFG_TilingMemory) && CFG_TilingMemory {
        sig := _GetWinSignature(hwnd)
        if sig != ""
            State_SetAppMaximized(sig, isMaxNow)
    }
}

; Restored main-branch behavior: save active HWND before switch, activate after a short delay.
GotoDesktop(n) {
    global g_LastDesktop, g_DesktopLastWindow, g_DesktopFocusGeneration, g_DesktopExcludeHwnd
    global g_DesktopFocusHotkeyDelay
    if !VDA.isLoaded {
        ShowOSD("VDA not loaded — install the DLL first!")
        return
    }

    currentDesk := g_LastDesktop
    try {
        cur := VDA.GetCurrent()
        if cur && cur != VDA.DESKTOP_UNKNOWN
            currentDesk := cur
    }
    exclude := g_DesktopExcludeHwnd
    g_DesktopExcludeHwnd := 0
    _RememberActiveWindowForDesktop(currentDesk, exclude)

    if !VDA.GoTo(n)
        return

    g_LastDesktop := n
    g_DesktopFocusGeneration += 1
    ; CapsLock+N: switch is intentional and already settling — restore sooner than swipe.
    _ScheduleDesktopFocusRestore(n, g_DesktopFocusGeneration, g_DesktopFocusHotkeyDelay)
    _ScheduleDesktopRestore(n)
    if VDA.hasHookRegistered
        _ScheduleDesktopWatchdog(n)
}

; Simple restore (main-branch). Generation ignores stale timers from rapid switches.
_RestoreFocusOnDesktop(n, gen := 0) {
    global g_DesktopFocusGeneration, g_DesktopLastWindow, g_DesktopRestoreCallback
    g_DesktopRestoreCallback := 0
    if gen && gen != g_DesktopFocusGeneration
        return
    if VDA.isLoaded {
        try {
            cur := VDA.GetCurrent()
            if cur != VDA.DESKTOP_UNKNOWN && cur != n
                return
        }
    }
    if !g_DesktopLastWindow.Has(n)
        return
    hwnd := g_DesktopLastWindow[n]
    if WinExist("ahk_id " hwnd) {
        ; Match main: compare window desktop to current. Unknown → try activate anyway.
        ; Do NOT use IsWindowOnCurrentVirtualDesktop here — it often returns 0 mid-switch
        ; and the old strict path deleted the mapping, which broke focus restore.
        canActivate := true
        if VDA.isLoaded {
            try {
                pinned := VDA.IsPinned(hwnd)
                winDesk := VDA.GetWindowDesktop(hwnd)
                cur := VDA.GetCurrent()
                if pinned = 1 {
                    canActivate := true
                } else if winDesk != VDA.DESKTOP_UNKNOWN && cur != VDA.DESKTOP_UNKNOWN {
                    canActivate := (winDesk = cur)
                }
            }
        }
        if canActivate {
            if WinGetMinMax("ahk_id " hwnd) = -1
                WinRestore("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
            return
        }
    }
    g_DesktopLastWindow.Delete(n)
    State_DeleteDesktopWindow(n)
}

MoveToDesktop(desktopIndex) {
    global g_DesktopExcludeHwnd, g_DesktopLastWindow
    if !WinExist("A")
        return
    if !VDA.isLoaded {
        ShowOSD("VDA not loaded — install the DLL first!")
        return
    }
    windowHandle := WinGetID("A")
    if !VDA.MoveWindow(windowHandle, desktopIndex) {
        ShowOSD("Move to desktop " desktopIndex " failed")
        return
    }
    ; Destination remembers the moved window; exclude it from the departing desk save.
    g_DesktopLastWindow[desktopIndex] := windowHandle
    State_SetDesktopWindow(desktopIndex, windowHandle)
    g_DesktopExcludeHwnd := windowHandle
    GotoDesktop(desktopIndex)
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
        if _IsFocusEligible(windowHandle) {
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
        if !_IsFocusEligible(windowHandle)
            continue
        WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "ahk_id " windowHandle)
        centerX := windowX + windowWidth // 2, centerY := windowY + windowHeight // 2
        if centerX >= monitorLeft && centerX < monitorRight && centerY >= monitorTop && centerY < monitorBottom {
            WinActivate("ahk_id " windowHandle)
            if (IsSet(CFG_MonitorFocusTeleportMouse) && CFG_MonitorFocusTeleportMouse)
                DllCall("SetCursorPos", "Int", centerX, "Int", centerY)
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
        if !_IsFocusEligible(hwnd)
            continue
        try {
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
                _IndexWinSignature(hwnd, sig)
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
        if hwnd = curHwnd || !WinExist("ahk_id " hwnd)
            continue
        ; Same eligibility as directional/monitor focus, but allow minimized targets.
        try {
            if WinGetExStyle("ahk_id " hwnd) & 0x80
                continue
            cloaked := 0
            DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
            if cloaked
                continue
            if VDA.isLoaded && VDA.IsOnCurrentDesktop(hwnd) != 1
                continue
            if !_IsLiveWindow(hwnd) && WinGetMinMax("ahk_id " hwnd) != -1
                continue
        } catch {
            continue
        }
        if WinGetMinMax("ahk_id " hwnd) = -1
            WinRestore("ahk_id " hwnd)
        WinActivate("ahk_id " hwnd)
        return
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
    ; Do not use A_PriorKey here: KeyHistory is 0 by default (Main.ahk), which
    ; blanks A_PriorKey and would permanently disable Shift+CapsLock toggling.
    KeyWait "CapsLock", "T0.3"
    if !GetKeyState("CapsLock", "P") {
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
Delete:: _ClearWindowLayout(false)   ; session layout only
+Delete:: _ClearWindowLayout(true)    ; also forget persistent app memory

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
