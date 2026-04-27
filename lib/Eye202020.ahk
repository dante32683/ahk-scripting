#Requires AutoHotkey v2.0+

; ============================================================
; 20-20-20 EYE BREAK REMINDER (WinUI renders; AHK sends IPC snapshots)
; NOTE: This file only defines globals/functions.
; The entry point must call `_202020_Init()` during startup.
; ============================================================

global g_202020_Enabled := true
global g_202020_DisabledDate := ""  ; YYYYMMDD for "disabled for rest of day"
global g_202020_ElapsedMs := 0
global g_202020_LastTick := 0
global g_202020_InBreak := false
global g_202020_BreakStart := 0
global g_202020_FlashGreenCount := 0
global g_202020_FlashGreenNext := 0
global g_202020_ZoneSize := 40        ; WinUI hit/hover zone (px)
global g_202020_DotSize  := 12        ; WinUI dot size (px)
global g_202020_Margin   := 12        ; WinUI margin from work-area corner (px)
global g_202020_DotGap   := 4         ; WinUI gap between stacked dots (px)
global g_202020_IniFile := A_Temp "\ahk_202020.ini"
; Named pipe paths are literal on Windows. AHK does not treat backslash as an escape,
; so use the real pipe path form directly.
global g_202020_StatePipeName := "\\.\pipe\MenuBar.202020.state"
global g_202020_CmdPipeName   := "\\.\pipe\MenuBar.202020.cmd"
global g_202020_StatePipe := 0
global g_202020_CmdPipe := 0
global g_202020_LastSnapshotMs := 0
global g_202020_LastMode := ""
global g_202020_LastEnabledSent := ""
global g_202020_CmdBuf := ""
global g_202020_DebugIpc := false
global g_202020_IpcLogFile := A_Temp "\ahk_202020_ipc.log"

_202020_Today() => FormatTime(, "yyyyMMdd")

_202020_IsEnabled() {
    global g_202020_Enabled, g_202020_DisabledDate
    if !g_202020_Enabled
        return false
    if (g_202020_DisabledDate != "" && g_202020_DisabledDate = _202020_Today())
        return false
    if (g_202020_DisabledDate != "" && g_202020_DisabledDate != _202020_Today())
        g_202020_DisabledDate := ""
    return true
}

_202020_SaveState(*) {
    global g_202020_IniFile, g_202020_Enabled, g_202020_DisabledDate
    try IniWrite(g_202020_Enabled ? 1 : 0, g_202020_IniFile, "state", "enabled")
    try IniWrite(g_202020_DisabledDate, g_202020_IniFile, "state", "disabledDate")
}

_202020_LoadState() {
    global g_202020_IniFile, g_202020_Enabled, g_202020_DisabledDate
    try g_202020_Enabled := IniRead(g_202020_IniFile, "state", "enabled", "1") = "1"
    try g_202020_DisabledDate := IniRead(g_202020_IniFile, "state", "disabledDate", "")
}

_202020_Reset(reason := "") {
    global g_202020_ElapsedMs, g_202020_InBreak, g_202020_BreakStart
    global g_202020_FlashGreenCount, g_202020_FlashGreenNext
    g_202020_ElapsedMs := 0
    g_202020_InBreak := false
    g_202020_BreakStart := 0
    g_202020_FlashGreenCount := 0
    g_202020_FlashGreenNext := 0
    _202020_IpcLog("reset reason=" reason)
    _202020_Snapshot(true)
}

_202020_Init() {
    global g_202020_LastTick, g_202020_LastSnapshotMs
    _202020_LoadState()
    g_202020_LastTick := A_TickCount
    g_202020_LastSnapshotMs := 0
    _202020_RegisterDisplayNotifications()
    SetTimer(_202020_Tick, 250)
    SetTimer(_202020_IpcTick, 200)
    _202020_Snapshot(true)
}

_202020_StatusColor(ms) {
    ; green 0-15, orange 15-19, red 19-20, >=20 red flashing handled elsewhere
    if ms < 15*60*1000
        return "6CCB5F"
    if ms < 19*60*1000
        return "FCE100"
    return "FF99A4"
}

_202020_TooltipText() {
    global g_202020_ElapsedMs
    remaining := 20*60*1000 - g_202020_ElapsedMs
    if remaining >= 0 {
        s := Floor(remaining/1000)
        return "Look away in " Floor(s/60) ":" Format("{:02}", Mod(s, 60))
    } else {
        s := Floor((-remaining)/1000)
        return "Overdue by " Floor(s/60) ":" Format("{:02}", Mod(s, 60))
    }
}

_202020_StartBreak() {
    global g_202020_InBreak, g_202020_BreakStart
    global g_202020_FlashGreenCount, g_202020_FlashGreenNext
    g_202020_InBreak := true
    g_202020_BreakStart := A_TickCount
    g_202020_FlashGreenCount := 0
    g_202020_FlashGreenNext := 0
    _202020_IpcLog("startBreak inBreak=true")
    _202020_Snapshot(true)
}

_202020_Tick() {
    global g_ScriptPaused
    global g_202020_ElapsedMs, g_202020_LastTick, g_202020_InBreak, g_202020_BreakStart
    global g_202020_FlashGreenCount, g_202020_FlashGreenNext

    if !IsSet(g_ScriptPaused)
        g_ScriptPaused := false
    pausedOrDisabled := g_ScriptPaused || !_202020_IsEnabled()

    now := A_TickCount
    if !g_202020_LastTick
        g_202020_LastTick := now
    dt := now - g_202020_LastTick
    g_202020_LastTick := now

    if g_202020_InBreak {
        elapsed := now - g_202020_BreakStart
        if elapsed >= 20000 {
            ; Break complete: flash green 3 times, then restart cycle at 0
            g_202020_InBreak := false
            g_202020_ElapsedMs := 0
            g_202020_FlashGreenCount := 6  ; 6 visibility toggles = 3 flashes
            g_202020_FlashGreenNext := now
            _202020_Snapshot(true)
        }
        return
    }

    ; Flash-green post-break sequence (visibility toggles)
    if g_202020_FlashGreenCount > 0 {
        if now >= g_202020_FlashGreenNext {
            g_202020_FlashGreenNext := now + 500
            g_202020_FlashGreenCount -= 1
            _202020_Snapshot(true)
        }
        return
    }

    ; Accumulate only when not idle >= 60s
    if !pausedOrDisabled && A_TimeIdlePhysical < 60000 {
        g_202020_ElapsedMs += dt
    }
    ; Snapshot cadence handled in _202020_IpcTick (1Hz steady + forced transitions)
}

_202020_TogglePrompt() {
    global g_202020_Enabled, g_202020_DisabledDate

    if _202020_IsEnabled() {
        r := MsgBox("20-20-20 is ON.`n`nYes  = Disable fully`nNo   = Disable for rest of day`nCancel = Keep enabled", "20-20-20", "YesNoCancel Iconi")
        if r = "Yes" {
            g_202020_Enabled := false
            g_202020_DisabledDate := ""
        } else if r = "No" {
            g_202020_DisabledDate := _202020_Today()
        }
    } else {
        r := MsgBox("20-20-20 is OFF.`n`nYes  = Enable`nNo   = Enable (and clear 'rest of day')`nCancel = Keep disabled", "20-20-20", "YesNoCancel Iconi")
        if r = "Yes" || r = "No" {
            g_202020_Enabled := true
            g_202020_DisabledDate := ""
        }
    }
    _202020_SaveState()
    _202020_Snapshot(true)
}

_202020_RegisterDisplayNotifications() {
    ; Best-effort monitor on/off detection via GUID_CONSOLE_DISPLAY_STATE.
    ; Uses WM_POWERBROADCAST / PBT_POWERSETTINGCHANGE (0x8013).
    static GUID_CONSOLE_DISPLAY_STATE := "{6FE69556-704A-47A0-8F24-C28D936FDA47}"
    try {
        guid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "Str", GUID_CONSOLE_DISPLAY_STATE, "Ptr", guid)
        DllCall("user32\RegisterPowerSettingNotification", "Ptr", A_ScriptHwnd, "Ptr", guid, "UInt", 0)
    }
}

; ----------------------------
; IPC (Named pipe JSONL)
; WinUI should host the pipe servers:
;   \\.\pipe\MenuBar.202020.state  (AHK -> WinUI)
;   \\.\pipe\MenuBar.202020.cmd    (WinUI -> AHK)
; ----------------------------

_202020_UnixMs() {
    ; FILETIME is 100ns since 1601-01-01
    ft := Buffer(8, 0)
    if DllCall("kernel32\GetProcAddress", "Ptr", DllCall("kernel32\GetModuleHandle", "Str", "kernel32.dll", "Ptr"), "AStr", "GetSystemTimePreciseAsFileTime", "Ptr")
        DllCall("kernel32\GetSystemTimePreciseAsFileTime", "Ptr", ft)
    else
        DllCall("kernel32\GetSystemTimeAsFileTime", "Ptr", ft)
    lo := NumGet(ft, 0, "UInt")
    hi := NumGet(ft, 4, "UInt")
    t := (hi << 32) | lo
    ; convert to unix epoch
    unix100ns := t - 116444736000000000
    return Floor(unix100ns / 10000)
}

_202020_EscapeJson(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    return s
}

_202020_IpcLog(line) {
    global g_202020_DebugIpc, g_202020_IpcLogFile
    if !g_202020_DebugIpc
        return
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss.fff") " " line "`n", g_202020_IpcLogFile, "UTF-8")
}

_202020_IpcTick() {
    global g_ScriptPaused
    if !IsSet(g_ScriptPaused)
        g_ScriptPaused := false
    _202020_PollCmd()
    _202020_Snapshot(false) ; 1Hz steady; forced snapshots use _202020_Snapshot(true)
}

_202020_LastErr() => DllCall("kernel32\GetLastError", "UInt")

_202020_TryConnectStatePipe() {
    global g_202020_StatePipe, g_202020_StatePipeName
    if g_202020_StatePipe
        return true
    h := DllCall("kernel32\CreateFileW"
        , "Str", g_202020_StatePipeName
        , "UInt", 0x40000000 ; GENERIC_WRITE
        , "UInt", 0
        , "Ptr", 0
        , "UInt", 3          ; OPEN_EXISTING
        , "UInt", 0
        , "Ptr", 0
        , "Ptr")
    if (h = -1 || !h) {
        err := _202020_LastErr()
        if err = 231 { ; ERROR_PIPE_BUSY
            ; Server exists but no instance available yet — wait briefly and retry once.
            DllCall("kernel32\WaitNamedPipeW", "Str", g_202020_StatePipeName, "UInt", 50)
            h := DllCall("kernel32\CreateFileW"
                , "Str", g_202020_StatePipeName
                , "UInt", 0x40000000
                , "UInt", 0
                , "Ptr", 0
                , "UInt", 3
                , "UInt", 0
                , "Ptr", 0
                , "Ptr")
            if (h = -1 || !h)
                return false
        } else {
            return false
        }
    }
    g_202020_StatePipe := h
    _202020_IpcLog("connected state pipe")
    return true
}

_202020_TryConnectCmdPipe() {
    global g_202020_CmdPipe, g_202020_CmdPipeName
    if g_202020_CmdPipe
        return true
    h := DllCall("kernel32\CreateFileW"
        , "Str", g_202020_CmdPipeName
        , "UInt", 0x80000000 ; GENERIC_READ
        , "UInt", 0
        , "Ptr", 0
        , "UInt", 3          ; OPEN_EXISTING
        , "UInt", 0
        , "Ptr", 0
        , "Ptr")
    if (h = -1 || !h) {
        err := _202020_LastErr()
        if err = 231 { ; ERROR_PIPE_BUSY
            DllCall("kernel32\WaitNamedPipeW", "Str", g_202020_CmdPipeName, "UInt", 50)
            h := DllCall("kernel32\CreateFileW"
                , "Str", g_202020_CmdPipeName
                , "UInt", 0x80000000
                , "UInt", 0
                , "Ptr", 0
                , "UInt", 3
                , "UInt", 0
                , "Ptr", 0
                , "Ptr")
            if (h = -1 || !h)
                return false
        } else {
            return false
        }
    }
    g_202020_CmdPipe := h
    _202020_IpcLog("connected cmd pipe")
    return true
}

_202020_ClosePipe(&h) {
    if h {
        try DllCall("kernel32\CloseHandle", "Ptr", h)
        h := 0
    }
}

_202020_WriteState(line) {
    global g_202020_StatePipe
    if !g_202020_StatePipe && !_202020_TryConnectStatePipe()
        return false
    data := line "`n"
    ; UTF-8 bytes
    size := StrPut(data, "UTF-8") - 1
    buf := Buffer(size, 0)
    StrPut(data, buf, "UTF-8")
    ok := DllCall("kernel32\WriteFile", "Ptr", g_202020_StatePipe, "Ptr", buf, "UInt", size, "UInt*", &written := 0, "Ptr", 0, "Int")
    if !ok {
        _202020_ClosePipe(&g_202020_StatePipe)
        return false
    }
    _202020_IpcLog("state -> " line)
    return true
}

_202020_PeekAvailable(h) {
    avail := 0
    ok := DllCall("kernel32\PeekNamedPipe", "Ptr", h, "Ptr", 0, "UInt", 0, "UInt*", 0, "UInt*", &avail, "UInt*", 0, "Int")
    return ok ? avail : -1
}

_202020_PollCmd() {
    global g_202020_CmdPipe, g_202020_CmdBuf
    if !g_202020_CmdPipe && !_202020_TryConnectCmdPipe()
        return
    avail := _202020_PeekAvailable(g_202020_CmdPipe)
    if avail < 0 {
        ; broken handle / disconnected server
        _202020_ClosePipe(&g_202020_CmdPipe)
        return
    }
    if avail = 0
        return
    toRead := Min(avail, 4096)
    buf := Buffer(toRead, 0)
    ok := DllCall("kernel32\ReadFile", "Ptr", g_202020_CmdPipe, "Ptr", buf, "UInt", toRead, "UInt*", &got := 0, "Ptr", 0, "Int")
    if !ok || got = 0 {
        _202020_ClosePipe(&g_202020_CmdPipe)
        return
    }
    chunk := StrGet(buf, got, "UTF-8")
    g_202020_CmdBuf .= chunk
    while (p := InStr(g_202020_CmdBuf, "`n")) {
        line := Trim(SubStr(g_202020_CmdBuf, 1, p-1))
        g_202020_CmdBuf := SubStr(g_202020_CmdBuf, p+1)
        if line {
            _202020_IpcLog("cmd <- " line)
            _202020_HandleCmd(line)
        }
    }
}

_202020_HandleCmd(jsonLine) {
    ; Minimal JSON parsing: extract cmd string.
    if !RegExMatch(jsonLine, '"cmd"\s*:\s*"([^"]+)"', &m)
        return
    cmd := m[1]
    _202020_IpcLog("handle cmd=" cmd)
    if (cmd = "reset" || cmd = "resetTimer" || cmd = "resetActiveTimer") {
        if _202020_IsEnabled()
            _202020_Reset("ipc")
        return
    }
    if cmd = "startBreak" {
        if !_202020_IsEnabled()
            return
        if g_202020_ElapsedMs < 20*60*1000
            _202020_Reset("ipc-startBreak")
        else
            _202020_StartBreak()
        return
    }
    if cmd = "togglePrompt" {
        _202020_TogglePrompt()
        return
    }
    if cmd = "disableForToday" {
        global g_202020_DisabledDate
        g_202020_DisabledDate := _202020_Today()
        _202020_SaveState()
        _202020_Snapshot(true)
        return
    }
    if cmd = "setEnabled" {
        if RegExMatch(jsonLine, '"value"\s*:\s*(true|false)', &v) {
            global g_202020_Enabled
            g_202020_Enabled := (v[1] = "true")
            _202020_SaveState()
            _202020_Snapshot(true)
        }
        return
    }
}

_202020_Mode() {
    global g_ScriptPaused, g_202020_InBreak, g_202020_FlashGreenCount, g_202020_ElapsedMs
    if !IsSet(g_ScriptPaused)
        g_ScriptPaused := false
    if g_ScriptPaused || !_202020_IsEnabled()
        return "normal"
    if g_202020_InBreak
        return "break"
    if g_202020_FlashGreenCount > 0
        return "postbreak"
    if g_202020_ElapsedMs >= 20*60*1000
        return "overdue"
    return "normal"
}

_202020_Snapshot(force := false) {
    global g_202020_LastSnapshotMs, g_202020_LastMode, g_202020_LastEnabledSent
    global g_202020_ElapsedMs, g_202020_InBreak, g_202020_BreakStart
    global g_202020_Margin, g_202020_DotSize, g_202020_DotGap, g_202020_ZoneSize
    global g_ScriptPaused

    now := A_TickCount
    mode := _202020_Mode()
    enabledNow := (!g_ScriptPaused) && _202020_IsEnabled()

    if !force {
        if (now - g_202020_LastSnapshotMs) < 1000 && mode = g_202020_LastMode && enabledNow = g_202020_LastEnabledSent
            return
    }

    ; immediate-on-transition behavior
    if mode != g_202020_LastMode || enabledNow != g_202020_LastEnabledSent
        force := true

    if !force && (now - g_202020_LastSnapshotMs) < 1000
        return

    g_202020_LastSnapshotMs := now
    g_202020_LastMode := mode
    g_202020_LastEnabledSent := enabledNow

    tooltip := _202020_TooltipText()

    stackCount := 1
    breakElapsed := 0
    if mode = "break" {
        breakElapsed := Max(0, now - g_202020_BreakStart)
        seg := Floor(breakElapsed / 5000) ; dot drop cadence
        stackCount := Max(1, 4 - Min(seg, 3))
    }

    baseColor := (mode = "break" || mode = "overdue") ? "#FF99A4" : ("#" _202020_StatusColor(g_202020_ElapsedMs))
    if mode = "postbreak"
        baseColor := "#6CCB5F"
    if !enabledNow
        baseColor := "#" _202020_StatusColor(0)

    visible := enabledNow

    flashKind := "none"
    flashInterval := 0
    if mode = "overdue" {
        flashKind := "toggle"
        flashInterval := 400
    } else if mode = "postbreak" {
        flashKind := "toggle"
        flashInterval := 500
    }

    msg := '{'
        . '"v":1,'
        . '"ts":' _202020_UnixMs() ','
        . '"enabled":' (enabledNow ? "true" : "false") ','
        . '"mode":"' mode '",'
        . '"colors":{"green":"#6CCB5F","warn":"#FCE100","alert":"#FF99A4"},'
        . '"elapsedActiveMs":' g_202020_ElapsedMs ','
        . '"dot":{'
            . '"marginPx":' g_202020_Margin ','
            . '"dotSizePx":' g_202020_DotSize ','
            . '"gapPx":' g_202020_DotGap ','
            . '"zonePx":' g_202020_ZoneSize ','
            . '"stackCount":' stackCount ','
            . '"baseColor":"' baseColor '",'
            . '"visible":' (visible ? "true" : "false")
        . '},'
        . '"flash":{"kind":"' flashKind '","intervalMs":' flashInterval '},'
        . '"break":{'
            . '"active":' (mode="break" ? "true" : "false") ','
            . '"totalMs":20000,'
            . '"elapsedMs":' breakElapsed ','
            . '"blinkCycleMs":1000,'
            . '"blinkOffMs":400,'
            . '"dropEveryMs":5000'
        . '},'
        . '"tooltip":"' _202020_EscapeJson(tooltip) '"'
    . '}'

    _202020_WriteState(msg)
}

