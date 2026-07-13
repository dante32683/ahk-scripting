#Requires AutoHotkey v2.0+

global g_StateDir := ""
global g_StateAppLayouts := Map()       ; signature -> LayoutRecord or serialized
global g_StateAppMaximized := Map()     ; signature -> bool
global g_StateDesktopWindows := Map()   ; desktop -> hwnd
global g_StateDesktopIdentities := Map() ; desktop -> WindowIdentity map
global g_StateSessionLayouts := Map()   ; hwnd -> {identity, layout, pid, proc, class}
global g_StateAutocorrectDisabled := Map()
global g_StateDirtyAreas := Map()
global g_StateFlushTimerActive := false
global g_StateMigrationValidated := 0
global g_StateHandoffPendingWrite := false
global g_StateSchemaVersion := 2

State_Init() {
    global g_StateDir, g_StateAppLayouts, g_StateAppMaximized, g_StateDesktopWindows
    global g_StateDesktopIdentities, g_StateSessionLayouts, g_StateAutocorrectDisabled
    global CFG_TestMode

    if IsSet(CFG_StateDir) && CFG_StateDir != ""
        g_StateDir := CFG_StateDir
    else if IsSet(CFG_TestMode) && CFG_TestMode
        ; Test mode must never read, write, migrate, or consume real user state.
        ; Use a unique per-process temp directory so a boot test cannot delete a
        ; valid production session-handoff file or corrupt saved layouts.
        g_StateDir := A_Temp "\AutoHotkeyMaster_test_" DllCall("GetCurrentProcessId")
    else
        g_StateDir := EnvGet("LocalAppData") "\AutoHotkeyMaster"

    ; Ensure both the state directory and its logs subdirectory exist. logs\ must be
    ; created even when the parent directory already exists, otherwise State_LogError
    ; silently fails for the whole session.
    if !DirExist(g_StateDir)
        try DirCreate(g_StateDir)
    if !DirExist(g_StateDir "\logs")
        try DirCreate(g_StateDir "\logs")

    if !(IsSet(CFG_TestMode) && CFG_TestMode)
        State_MigrateLegacy()

    stateFile := g_StateDir "\state-v2.ini"
    if FileExist(stateFile) {
        try State_LoadStateFile(stateFile)
        catch as e
            State_LogError("load_state", e.Message)
    }

    State_LoadSessionHandoff()

    disabledFile := g_StateDir "\autocorrect-disabled.txt"
    if FileExist(disabledFile) {
        try {
            loop parse, FileRead(disabledFile, "UTF-8"), "`n", "`r" {
                line := Trim(A_LoopField)
                if line = ""
                    continue
                arrowPos := InStr(line, "->")
                trigger := arrowPos ? Trim(SubStr(line, 1, arrowPos - 1)) : line
                if trigger != ""
                    g_StateAutocorrectDisabled[StrLower(trigger)] := line
            }
        } catch as e
            State_LogError("load_autocorrect", e.Message)
    }
}

State_LogError(area, message) {
    global g_StateDir
    try {
        ts := FormatTime(A_NowUTC, "yyyy-MM-dd HH:mm:ss")
        FileAppend(ts " UTC [" area "] " message "`n", g_StateDir "\logs\state.log", "UTF-8")
    }
}

State_EscapeIni(value) {
    value := StrReplace(value, "``", "````")
    value := StrReplace(value, "`n", "``n")
    value := StrReplace(value, "`r", "``r")
    value := StrReplace(value, "=", "``=")
    value := StrReplace(value, "[", "``[")
    value := StrReplace(value, "]", "``]")
    ; Pipe is the field delimiter inside packed DesktopLastWindow values; it must be
    ; encoded so a proc/class/sig containing '|' cannot corrupt the record layout.
    value := StrReplace(value, "|", "``p")
    return value
}

State_UnescapeIni(value) {
    value := StrReplace(value, "``p", "|")
    value := StrReplace(value, "``]", "]")
    value := StrReplace(value, "``[", "[")
    value := StrReplace(value, "``=", "=")
    value := StrReplace(value, "``r", "`r")
    value := StrReplace(value, "``n", "`n")
    value := StrReplace(value, "````", "``")
    return value
}

State_LoadStateFile(stateFile) {
    global g_StateAppLayouts, g_StateAppMaximized, g_StateDesktopWindows, g_StateDesktopIdentities, g_StateSchemaVersion

    ver := IniRead(stateFile, "Schema", "version", "2")
    if Integer(ver) > g_StateSchemaVersion
        throw Error("Unsupported state schema version: " ver)

    sectionsStr := IniRead(stateFile)
    loop parse, sectionsStr, "`n", "`r" {
        section := Trim(A_LoopField)
        if section = "" || section = "Schema" || section = "DesktopLastWindow"
            continue
        ; Isolate each section so one malformed record cannot abort the rest.
        try {
            sig := State_UnescapeIni(section)
            rectStr := IniRead(stateFile, section, "rect", "")
            if rectStr != "" {
                rec := Layout_Deserialize(State_UnescapeIni(rectStr))
                if rec
                    g_StateAppLayouts[sig] := rec
            }

            maxVal := IniRead(stateFile, section, "maximized", "")
            if maxVal != ""
                g_StateAppMaximized[sig] := (maxVal = "1")
        } catch as e
            State_LogError("load_state_section", e.Message)
    }

    try {
        desktopKeys := IniRead(stateFile, "DesktopLastWindow")
        loop parse, desktopKeys, "`n", "`r" {
            line := Trim(A_LoopField)
            if line = ""
                continue
            eq := InStr(line, "=")
            if !eq
                continue
            key := SubStr(line, 1, eq - 1)
            val := SubStr(line, eq + 1)
            if SubStr(key, 1, 1) != "d"
                continue
            deskNum := Integer(SubStr(key, 2))
            if InStr(val, "|") {
                parts := StrSplit(val, "|")
                hwnd := Integer(parts[1])
                identity := Map(
                    "pid", parts.Length >= 2 ? Integer(parts[2]) : 0,
                    "proc", parts.Length >= 3 ? State_UnescapeIni(parts[3]) : "",
                    "class", parts.Length >= 4 ? State_UnescapeIni(parts[4]) : "",
                    "sig", parts.Length >= 5 ? State_UnescapeIni(parts[5]) : ""
                )
                g_StateDesktopWindows[deskNum] := hwnd
                g_StateDesktopIdentities[deskNum] := identity
            } else {
                g_StateDesktopWindows[deskNum] := Integer(val)
            }
        }
    }
}

State_UtcNowUnix() {
    ; A_NowUTC is YYYYMMDDHHMISS; convert to rough unix seconds for age checks
    return DateDiff(A_NowUTC, "19700101000000", "Seconds")
}

State_LoadSessionHandoff() {
    global g_StateDir, g_StateSessionLayouts
    sessionFile := g_StateDir "\session-handoff-v2.ini"
    if !FileExist(sessionFile)
        return

    loadedOk := false
    try {
        ver := IniRead(sessionFile, "Schema", "version", "")
        writeTimeStr := IniRead(sessionFile, "Schema", "write_time_utc", "")
        if writeTimeStr = ""
            writeTimeStr := IniRead(sessionFile, "Schema", "write_time", "")

        writeTime := RegExMatch(writeTimeStr, "^\d+$") ? Integer(writeTimeStr) : 0
        ageOk := false
        if writeTime > 1000000000 {
            age := State_UtcNowUnix() - writeTime
            ageOk := age >= 0 && age < 300
        }

        if (ver = "2" && ageOk) {
            sectionsStr := IniRead(sessionFile)
            loop parse, sectionsStr, "`n", "`r" {
                section := Trim(A_LoopField)
                if section = "" || section = "Schema"
                    continue
                ; One bad window record must not prevent loading the others.
                try {
                    hwnd := Integer(section)
                    if !DllCall("IsWindow", "Ptr", hwnd)
                        continue

                    pid := Integer(IniRead(sessionFile, section, "pid", "0"))
                    procName := State_UnescapeIni(IniRead(sessionFile, section, "proc", ""))
                    className := State_UnescapeIni(IniRead(sessionFile, section, "class", ""))
                    sig := State_UnescapeIni(IniRead(sessionFile, section, "sig", ""))
                    rectStr := State_UnescapeIni(IniRead(sessionFile, section, "rect", ""))

                    identity := Map("pid", pid, "proc", procName, "class", className, "sig", sig)
                    if !_ValidateWindowIdentity(hwnd, identity)
                        continue

                    layout := Layout_Deserialize(rectStr)
                    if !layout
                        continue

                    g_StateSessionLayouts[hwnd] := Map(
                        "identity", sig,
                        "layout", layout,
                        "pid", pid,
                        "proc", procName,
                        "class", className
                    )
                } catch as e
                    State_LogError("load_handoff_section", e.Message)
            }
            loadedOk := true ; valid schema parsed; consume handoff even if zero windows accepted
        }
    } catch as e {
        State_LogError("load_handoff", e.Message)
        return ; keep file for retry / evidence
    }

    if loadedOk {
        try FileDelete(sessionFile)
    }
}

_ValidateWindowIdentity(hwnd, identity) {
    if !hwnd || !DllCall("IsWindow", "Ptr", hwnd)
        return false
    if !(identity is Map)
        return DllCall("IsWindow", "Ptr", hwnd)
    try {
        actualPid := WinGetPID("ahk_id " hwnd)
        actualProc := WinGetProcessName("ahk_id " hwnd)
        actualClass := WinGetClass("ahk_id " hwnd)
    } catch {
        return false
    }
    if identity.Has("pid") && identity["pid"] && actualPid != identity["pid"]
        return false
    if identity.Has("proc") && identity["proc"] != "" && actualProc != identity["proc"]
        return false
    if identity.Has("class") && identity["class"] != "" && actualClass != identity["class"]
        return false
    if identity.Has("sig") && identity["sig"] != "" {
        try {
            liveSig := _GetWinSignature(hwnd)
            if liveSig != "" && liveSig != identity["sig"]
                return false
        }
    }
    return true
}

State_GetAppLayout(signature) {
    global g_StateAppLayouts
    return g_StateAppLayouts.Has(signature) ? g_StateAppLayouts[signature] : ""
}

State_SetAppLayout(signature, record) {
    global g_StateAppLayouts
    if record is String {
        parsed := Layout_Deserialize(record)
        if !parsed
            return
        record := parsed
    } else if record is Array && record.Length = 4 {
        record := Layout_FromLegacyPct(record[1], record[2], record[3], record[4])
    }
    if !Layout_Validate(record)
        return
    existing := g_StateAppLayouts.Has(signature) ? g_StateAppLayouts[signature] : 0
    if existing && Layout_Serialize(existing) = Layout_Serialize(record)
        return
    g_StateAppLayouts[signature] := record
    State_MarkDirty("state")
}

State_SetAppMaximized(signature, isMaximized) {
    global g_StateAppMaximized
    val := isMaximized ? true : false
    if (!g_StateAppMaximized.Has(signature) || g_StateAppMaximized[signature] != val) {
        g_StateAppMaximized[signature] := val
        State_MarkDirty("state")
    }
}

State_GetDesktopWindow(desktop) {
    global g_StateDesktopWindows
    return g_StateDesktopWindows.Has(desktop) ? g_StateDesktopWindows[desktop] : 0
}

State_GetDesktopWindowIdentity(desktop) {
    global g_StateDesktopIdentities
    return g_StateDesktopIdentities.Has(desktop) ? g_StateDesktopIdentities[desktop] : Map()
}

State_SetDesktopWindow(desktop, hwnd, identity := "") {
    global g_StateDesktopWindows, g_StateDesktopIdentities
    if !(identity is Map) {
        identity := Map()
        if hwnd && DllCall("IsWindow", "Ptr", hwnd) {
            try {
                identity["pid"] := WinGetPID("ahk_id " hwnd)
                identity["proc"] := WinGetProcessName("ahk_id " hwnd)
                identity["class"] := WinGetClass("ahk_id " hwnd)
                identity["sig"] := _GetWinSignature(hwnd)
            }
        }
    }
    changed := !g_StateDesktopWindows.Has(desktop) || g_StateDesktopWindows[desktop] != hwnd
    g_StateDesktopWindows[desktop] := hwnd
    g_StateDesktopIdentities[desktop] := identity
    if changed
        State_MarkDirty("state")
}

State_SetSessionLayout(hwnd, identity, record) {
    global g_StateSessionLayouts
    if record is Array && record.Length = 4
        record := Layout_FromLegacyPct(record[1], record[2], record[3], record[4])
    if !Layout_Validate(record)
        return
    meta := Map("identity", identity, "layout", record)
    try {
        meta["pid"] := WinGetPID("ahk_id " hwnd)
        meta["proc"] := WinGetProcessName("ahk_id " hwnd)
        meta["class"] := WinGetClass("ahk_id " hwnd)
    }
    g_StateSessionLayouts[hwnd] := meta
    ; Session handoff is written only on orderly reload, not continuously
}

State_DeleteSessionLayout(hwnd) {
    global g_StateSessionLayouts
    if g_StateSessionLayouts.Has(hwnd)
        g_StateSessionLayouts.Delete(hwnd)
}

State_MarkDirty(area) {
    global g_StateDirtyAreas, CFG_TestMode
    if IsSet(CFG_TestMode) && CFG_TestMode
        return
    g_StateDirtyAreas[area] := true
    State_FlushSoon()
}

State_FlushSoon() {
    global g_StateFlushTimerActive, CFG_TestMode
    if IsSet(CFG_TestMode) && CFG_TestMode
        return
    if !g_StateFlushTimerActive {
        g_StateFlushTimerActive := true
        SetTimer(State_FlushNow, -500)
    }
}

State_PrepareHandoff() {
    global g_StateHandoffPendingWrite
    g_StateHandoffPendingWrite := true
    State_MarkDirty("session")
}

State_FlushNow(*) {
    global g_StateDirtyAreas, g_StateFlushTimerActive, g_StateDir
    global g_StateAppLayouts, g_StateAppMaximized, g_StateDesktopWindows, g_StateDesktopIdentities
    global g_StateSessionLayouts, g_StateAutocorrectDisabled, g_StateHandoffPendingWrite
    global CFG_TestMode

    g_StateFlushTimerActive := false
    if IsSet(CFG_TestMode) && CFG_TestMode
        return true

    ; Update counters locally so StateStore does not hard-depend on Perf_* load order (#Warn).
    global CFG_PerfLogging, g_PerfCounters
    if IsSet(CFG_PerfLogging) && CFG_PerfLogging && IsSet(g_PerfCounters) && g_PerfCounters.Has("state_flushes")
        g_PerfCounters["state_flushes"] := g_PerfCounters["state_flushes"] + 1
    ok := true

    if g_StateDirtyAreas.Has("state") || g_StateDirtyAreas.Has("autocorrect") {
        if g_StateDirtyAreas.Has("state") {
            stateFile := g_StateDir "\state-v2.ini"
            content := "[Schema]`nversion=2`nwrite_time_utc=" State_UtcNowUnix() "`n`n"

            allSigs := Map()
            for sig, _ in g_StateAppLayouts
                allSigs[sig] := true
            for sig, _ in g_StateAppMaximized
                allSigs[sig] := true

            for sig, _ in allSigs {
                content .= "[" State_EscapeIni(sig) "]`n"
                if g_StateAppLayouts.Has(sig)
                    content .= "rect=" State_EscapeIni(Layout_Serialize(g_StateAppLayouts[sig])) "`n"
                if g_StateAppMaximized.Has(sig)
                    content .= "maximized=" (g_StateAppMaximized[sig] ? "1" : "0") "`n"
                content .= "`n"
            }

            content .= "[DesktopLastWindow]`n"
            for desk, hwnd in g_StateDesktopWindows {
                if hwnd && DllCall("IsWindow", "Ptr", hwnd) {
                    id := g_StateDesktopIdentities.Has(desk) ? g_StateDesktopIdentities[desk] : Map()
                    content .= "d" desk "=" hwnd
                        . "|" (id.Has("pid") ? id["pid"] : 0)
                        . "|" State_EscapeIni(id.Has("proc") ? id["proc"] : "")
                        . "|" State_EscapeIni(id.Has("class") ? id["class"] : "")
                        . "|" State_EscapeIni(id.Has("sig") ? id["sig"] : "") "`n"
                }
            }

            if State_AtomicWrite(stateFile, content) {
                g_StateDirtyAreas.Delete("state")
            } else {
                ok := false
                State_LogError("write_state", "atomic write failed")
            }
        }

        if g_StateDirtyAreas.Has("autocorrect") {
            disabledFile := g_StateDir "\autocorrect-disabled.txt"
            acContent := ""
            for , entry in g_StateAutocorrectDisabled
                acContent .= entry "`n"
            if State_AtomicWrite(disabledFile, acContent, "UTF-8")
                g_StateDirtyAreas.Delete("autocorrect")
            else {
                ok := false
                State_LogError("write_autocorrect", "atomic write failed")
            }
        }
    }

    if g_StateHandoffPendingWrite || g_StateDirtyAreas.Has("session") {
        sessionFile := g_StateDir "\session-handoff-v2.ini"
        content := "[Schema]`n"
        content .= "version=2`n"
        content .= "write_time_utc=" State_UtcNowUnix() "`n"
        content .= "source_pid=" DllCall("GetCurrentProcessId") "`n`n"

        for hwnd, item in g_StateSessionLayouts {
            if !DllCall("IsWindow", "Ptr", hwnd)
                continue
            try {
                pid := item.Has("pid") ? item["pid"] : WinGetPID("ahk_id " hwnd)
                procName := item.Has("proc") ? item["proc"] : WinGetProcessName("ahk_id " hwnd)
                className := item.Has("class") ? item["class"] : WinGetClass("ahk_id " hwnd)
                content .= "[" hwnd "]`n"
                content .= "pid=" pid "`n"
                content .= "proc=" State_EscapeIni(procName) "`n"
                content .= "class=" State_EscapeIni(className) "`n"
                content .= "sig=" State_EscapeIni(item["identity"]) "`n"
                content .= "rect=" State_EscapeIni(Layout_Serialize(item["layout"])) "`n`n"
            }
        }

        if State_AtomicWrite(sessionFile, content) {
            g_StateDirtyAreas.Delete("session")
            g_StateHandoffPendingWrite := false
        } else {
            ok := false
            State_LogError("write_handoff", "atomic write failed")
        }
    }

    ; A failed write leaves its dirty flag set (handled above). Schedule a retry so
    ; transient file locks recover automatically instead of losing the change until
    ; the next unrelated mutation.
    if !ok && !(IsSet(CFG_TestMode) && CFG_TestMode) && !g_StateFlushTimerActive {
        g_StateFlushTimerActive := true
        SetTimer(State_FlushNow, -2000)
    }
    return ok
}

State_AtomicWrite(filePath, content, encoding := "UTF-8") {
    SplitPath(filePath, &outFileName, &outDir)
    guid := Format("{:08X}{:08X}", A_TickCount, Random(0, 0x7FFFFFFF))
    tempFile := outDir "\" outFileName "." guid "." DllCall("GetCurrentProcessId") ".tmp"

    try {
        if FileExist(tempFile)
            FileDelete(tempFile)
        f := FileOpen(tempFile, "w", encoding)
        if !f
            throw Error("FileOpen failed")
        f.Write(content)
        f.Close()

        res := DllCall("MoveFileExW", "Str", tempFile, "Str", filePath, "UInt", 9)
        if !res
            throw Error("MoveFileExW failed: " A_LastError)
    } catch as e {
        try FileDelete(tempFile)
        State_LogError("atomic_write", e.Message)
        return false
    }
    return true
}

State_MigrateLegacy() {
    global g_StateDir, g_StateAppLayouts, g_StateAppMaximized, g_StateDesktopWindows, g_StateAutocorrectDisabled
    global g_StateMigrationValidated

    legacyTilingFile := A_ScriptDir "\Tiling_Memory.ini"
    stateFile := g_StateDir "\state-v2.ini"
    migrated := false

    if FileExist(legacyTilingFile) && !FileExist(stateFile) {
        try FileCopy(legacyTilingFile, legacyTilingFile ".bak", true)
        try {
            sectionsStr := IniRead(legacyTilingFile)
            loop parse, sectionsStr, "`n", "`r" {
                section := Trim(A_LoopField)
                if section = ""
                    continue
                rect := IniRead(legacyTilingFile, section, "rect", "")
                if rect != "" {
                    rec := Layout_Deserialize(rect)
                    if rec
                        g_StateAppLayouts[section] := rec
                } else {
                    xf := IniRead(legacyTilingFile, section, "xf", "")
                    yf := IniRead(legacyTilingFile, section, "yf", "")
                    wf := IniRead(legacyTilingFile, section, "wf", "")
                    hf := IniRead(legacyTilingFile, section, "hf", "")
                    if (xf != "" && yf != "" && wf != "" && hf != "")
                        g_StateAppLayouts[section] := Layout_FromLegacyPct(xf, yf, wf, hf)
                }
                maximized := IniRead(legacyTilingFile, section, "maximized", "")
                if maximized != ""
                    g_StateAppMaximized[section] := (maximized = "1")
            }
            migrated := true
            State_MarkDirty("state")
        } catch as e
            State_LogError("migrate_tiling", e.Message)
    }

    legacyLayouts := A_Temp "\ahk_layouts.ini"
    if FileExist(legacyLayouts) {
        try {
            FileCopy(legacyLayouts, legacyLayouts ".bak", true)
            ; Session layouts are HWND-keyed and not valid across reboots; skip into session map.
            ; Content still backed up once.
            migrated := true
        } catch as e
            State_LogError("migrate_layouts", e.Message)
    }

    legacyAcFile := A_ScriptDir "\Autocorrect_Disabled.txt"
    disabledFile := g_StateDir "\autocorrect-disabled.txt"
    if FileExist(legacyAcFile) && !FileExist(disabledFile) {
        try {
            FileCopy(legacyAcFile, legacyAcFile ".bak", true)
            FileCopy(legacyAcFile, disabledFile, true)
            migrated := true
            State_MarkDirty("autocorrect")
        } catch as e
            State_LogError("migrate_ac", e.Message)
    }

    legacyDesktopFile := A_Temp "\ahk_desktop_memory.ini"
    if FileExist(legacyDesktopFile) {
        try {
            FileCopy(legacyDesktopFile, legacyDesktopFile ".bak", true)
            desktopKeys := IniRead(legacyDesktopFile, "DesktopLastWindow")
            loop parse, desktopKeys, "`n", "`r" {
                line := Trim(A_LoopField)
                if line = ""
                    continue
                parts := StrSplit(line, "=")
                if parts.Length = 2 {
                    deskNum := Integer(SubStr(parts[1], 2))
                    g_StateDesktopWindows[deskNum] := Integer(parts[2])
                }
            }
            migrated := true
            State_MarkDirty("state")
            ; Keep original until validated twice; only backup kept permanently
        } catch as e
            State_LogError("migrate_desktop", e.Message)
    }

    if migrated
        g_StateMigrationValidated += 1
}

State_Shutdown() {
    State_FlushNow()
}
