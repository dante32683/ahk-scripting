#Requires AutoHotkey v2.0+

global g_StateDir := ""
global g_StateAppLayouts := Map()       ; signature -> rect string (xf,yf,wf,hf)
global g_StateAppMaximized := Map()     ; signature -> bool
global g_StateDesktopWindows := Map()   ; desktop -> hwnd
global g_StateSessionLayouts := Map()   ; hwnd -> {identity: string, layout: array}
global g_StateAutocorrectDisabled := Map() ; trigger -> line (trigger->correction)
global g_StateDirtyAreas := Map()       ; area -> bool
global g_StateFlushTimerActive := false

State_Init() {
    global g_StateDir, g_StateAppLayouts, g_StateAppMaximized, g_StateDesktopWindows, g_StateSessionLayouts, g_StateAutocorrectDisabled
    
    ; Determine state directory
    if IsSet(CFG_StateDir) && CFG_StateDir != "" {
        g_StateDir := CFG_StateDir
    } else {
        g_StateDir := EnvGet("LocalAppData") "\AutoHotkeyMaster"
    }
    
    if !DirExist(g_StateDir) {
        try DirCreate(g_StateDir)
    }
        
    ; Migrate legacy files
    State_MigrateLegacy()
    
    ; Load state-v2.ini
    stateFile := g_StateDir "\state-v2.ini"
    if FileExist(stateFile) {
        try {
            sectionsStr := IniRead(stateFile)
            loop parse, sectionsStr, "`n", "`r" {
                section := Trim(A_LoopField)
                if section = "" || section = "DesktopLastWindow"
                    continue
                    
                rectStr := IniRead(stateFile, section, "rect", "")
                if rectStr != "" {
                    g_StateAppLayouts[section] := rectStr
                }
                
                maxVal := IniRead(stateFile, section, "maximized", "")
                if maxVal != "" {
                    g_StateAppMaximized[section] := (maxVal = "1")
                }
            }
            
            ; Load DesktopLastWindow
            try {
                desktopKeys := IniRead(stateFile, "DesktopLastWindow")
                loop parse, desktopKeys, "`n", "`r" {
                    line := Trim(A_LoopField)
                    if line = ""
                        continue
                    parts := StrSplit(line, "=")
                    if parts.Length = 2 {
                        deskNum := SubStr(parts[1], 2) ; e.g. "d1" -> "1"
                        g_StateDesktopWindows[Integer(deskNum)] := Integer(parts[2])
                    }
                }
            }
        }
    }
    
    ; Load session-handoff-v2.ini
    sessionFile := g_StateDir "\session-handoff-v2.ini"
    if FileExist(sessionFile) {
        try {
            ver := IniRead(sessionFile, "Schema", "version", "")
            writeTimeStr := IniRead(sessionFile, "Schema", "write_time", "")
            sourcePid := IniRead(sessionFile, "Schema", "source_pid", "")
            
            writeTime := 0
            if RegExMatch(writeTimeStr, "^\d+$") {
                writeTime := Integer(writeTimeStr)
            }
            
            ; Ignore session handoff older than 5 minutes
            if (ver = "2" && A_TickCount - writeTime < 300000) {
                sectionsStr := IniRead(sessionFile)
                loop parse, sectionsStr, "`n", "`r" {
                    section := Trim(A_LoopField)
                    if section = "" || section = "Schema"
                        continue
                        
                    hwnd := Integer(section)
                    if DllCall("IsWindow", "Ptr", hwnd) {
                        pid := Integer(IniRead(sessionFile, section, "pid", "0"))
                        procName := IniRead(sessionFile, section, "proc", "")
                        className := IniRead(sessionFile, section, "class", "")
                        sig := IniRead(sessionFile, section, "sig", "")
                        rectStr := IniRead(sessionFile, section, "rect", "")
                        
                        if DllCall("IsWindow", "Ptr", hwnd) {
                            actualClass := WinGetClass("ahk_id " hwnd)
                            actualProc := WinGetProcessName("ahk_id " hwnd)
                            
                            if (actualClass = className && actualProc = procName) {
                                rParts := StrSplit(rectStr, ",")
                                if rParts.Length = 4 {
                                    layout := [Integer(rParts[1]), Integer(rParts[2]), Integer(rParts[3]), Integer(rParts[4])]
                                    g_StateSessionLayouts[hwnd] := Map("identity", sig, "layout", layout)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        ; Delete handoff file immediately to prevent reuse
        try FileDelete(sessionFile)
    }
    
    ; Load autocorrect-disabled.txt
    disabledFile := g_StateDir "\autocorrect-disabled.txt"
    if FileExist(disabledFile) {
        try {
            loop parse, FileRead(disabledFile, "UTF-8"), "`n", "`r" {
                line := Trim(A_LoopField)
                if line = ""
                    continue
                arrowPos := InStr(line, "->")
                trigger := arrowPos ? Trim(SubStr(line, 1, arrowPos - 1)) : line
                if trigger != "" {
                    g_StateAutocorrectDisabled[StrLower(trigger)] := line
                }
            }
        }
    }
}

State_GetAppLayout(signature) {
    global g_StateAppLayouts
    return g_StateAppLayouts.Has(signature) ? g_StateAppLayouts[signature] : ""
}

State_SetAppLayout(signature, record) {
    global g_StateAppLayouts
    rectStr := IsObject(record) ? record[1] "," record[2] "," record[3] "," record[4] : record
    if (rectStr != "") {
        if (!g_StateAppLayouts.Has(signature) || g_StateAppLayouts[signature] != rectStr) {
            g_StateAppLayouts[signature] := rectStr
            State_MarkDirty("state")
        }
    }
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

State_SetDesktopWindow(desktop, hwnd, identity := "") {
    global g_StateDesktopWindows
    if (!g_StateDesktopWindows.Has(desktop) || g_StateDesktopWindows[desktop] != hwnd) {
        g_StateDesktopWindows[desktop] := hwnd
        State_MarkDirty("state")
    }
}

State_SetSessionLayout(hwnd, identity, record) {
    global g_StateSessionLayouts
    g_StateSessionLayouts[hwnd] := Map("identity", identity, "layout", record)
    State_MarkDirty("session")
}

State_DeleteSessionLayout(hwnd) {
    global g_StateSessionLayouts
    if g_StateSessionLayouts.Has(hwnd) {
        g_StateSessionLayouts.Delete(hwnd)
        State_MarkDirty("session")
    }
}

State_MarkDirty(area) {
    global g_StateDirtyAreas
    g_StateDirtyAreas[area] := true
    State_FlushSoon()
}

State_FlushSoon() {
    global g_StateFlushTimerActive
    if !g_StateFlushTimerActive {
        g_StateFlushTimerActive := true
        SetTimer(State_FlushNow, -500) ; Debounce 500 ms
    }
}

State_FlushNow() {
    global g_StateDirtyAreas, g_StateFlushTimerActive, g_StateDir
    global g_StateAppLayouts, g_StateAppMaximized, g_StateDesktopWindows, g_StateSessionLayouts, g_StateAutocorrectDisabled
    
    g_StateFlushTimerActive := false
    
    Perf_Increment("state_flushes")
    
    if g_StateDirtyAreas.Has("state") || g_StateDirtyAreas.Has("autocorrect") {
        stateFile := g_StateDir "\state-v2.ini"
        
        content := "; Auto-generated state file`n`n"
        
        allSigs := Map()
        for sig, rect in g_StateAppLayouts {
            allSigs[sig] := true
        }
        for sig, max in g_StateAppMaximized {
            allSigs[sig] := true
        }
        
        for sig, _ in allSigs {
            content .= "[" sig "]`n"
            if g_StateAppLayouts.Has(sig) {
                content .= "rect=" g_StateAppLayouts[sig] "`n"
            }
            if g_StateAppMaximized.Has(sig) {
                content .= "maximized=" (g_StateAppMaximized[sig] ? "1" : "0") "`n"
            }
            content .= "`n"
        }
        
        content .= "[DesktopLastWindow]`n"
        for desk, hwnd in g_StateDesktopWindows {
            if hwnd && DllCall("IsWindow", "Ptr", hwnd) {
                content .= "d" desk "=" hwnd "`n"
            }
        }
        
        State_AtomicWrite(stateFile, content)
        
        if g_StateDirtyAreas.Has("autocorrect") {
            disabledFile := g_StateDir "\autocorrect-disabled.txt"
            acContent := ""
            for , entry in g_StateAutocorrectDisabled {
                acContent .= entry "`n"
            }
            State_AtomicWrite(disabledFile, acContent, "UTF-8")
        }
        
        g_StateDirtyAreas.Delete("state")
        g_StateDirtyAreas.Delete("autocorrect")
    }
    
    if g_StateDirtyAreas.Has("session") {
        sessionFile := g_StateDir "\session-handoff-v2.ini"
        
        content := "[Schema]`n"
        content .= "version=2`n"
        content .= "write_time=" A_TickCount "`n"
        content .= "source_pid=" DllCall("GetCurrentProcessId") "`n`n"
        
        for hwnd, item in g_StateSessionLayouts {
            if DllCall("IsWindow", "Ptr", hwnd) {
                try {
                    pid := WinGetPID("ahk_id " hwnd)
                    procName := WinGetProcessName("ahk_id " hwnd)
                    className := WinGetClass("ahk_id " hwnd)
                    
                    content .= "[" hwnd "]`n"
                    content .= "pid=" pid "`n"
                    content .= "proc=" procName "`n"
                    content .= "class=" className "`n"
                    content .= "sig=" item["identity"] "`n"
                    layout := item["layout"]
                    content .= "rect=" layout[1] "," layout[2] "," layout[3] "," layout[4] "`n`n"
                }
            }
        }
        
        State_AtomicWrite(sessionFile, content)
        g_StateDirtyAreas.Delete("session")
    }
}

State_AtomicWrite(filePath, content, encoding := "UTF-8") {
    SplitPath(filePath, &outFileName, &outDir)
    tempFile := outDir "\" outFileName "." A_TickCount "." DllCall("GetCurrentProcessId") ".tmp"
    
    try {
        if FileExist(tempFile)
            FileDelete(tempFile)
            
        FileOpen(tempFile, "w", encoding).Write(content)
        
        ; MoveFileExW: REPLACE_EXISTING (1) | WRITE_THROUGH (8) = 9
        res := DllCall("MoveFileExW", "Str", tempFile, "Str", filePath, "UInt", 9)
        if !res {
            throw Error("MoveFileExW failed: " A_LastError)
        }
    } catch as e {
        try FileDelete(tempFile)
        return false
    }
    return true
}

State_MigrateLegacy() {
    global g_StateDir, g_StateAppLayouts, g_StateAppMaximized, g_StateDesktopWindows, g_StateAutocorrectDisabled
    
    legacyTilingFile := A_ScriptDir "\Tiling_Memory.ini"
    stateFile := g_StateDir "\state-v2.ini"
    
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
                    g_StateAppLayouts[section] := rect
                } else {
                    xf := IniRead(legacyTilingFile, section, "xf", "")
                    yf := IniRead(legacyTilingFile, section, "yf", "")
                    wf := IniRead(legacyTilingFile, section, "wf", "")
                    hf := IniRead(legacyTilingFile, section, "hf", "")
                    if (xf != "" && yf != "" && wf != "" && hf != "") {
                        g_StateAppLayouts[section] := xf "," yf "," wf "," hf
                    }
                }
                
                maximized := IniRead(legacyTilingFile, section, "maximized", "")
                if maximized != "" {
                    g_StateAppMaximized[section] := (maximized = "1")
                }
            }
        }
        
        State_MarkDirty("state")
    }
    
    legacyAcFile := A_ScriptDir "\Autocorrect_Disabled.txt"
    disabledFile := g_StateDir "\autocorrect-disabled.txt"
    
    if FileExist(legacyAcFile) && !FileExist(disabledFile) {
        try {
            FileCopy(legacyAcFile, legacyAcFile ".bak", true)
            FileCopy(legacyAcFile, disabledFile, true)
            State_MarkDirty("autocorrect")
        }
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
                    deskNum := SubStr(parts[1], 2) ; e.g. "d1" -> "1"
                    g_StateDesktopWindows[Integer(deskNum)] := Integer(parts[2])
                }
            }
            State_MarkDirty("state")
            FileDelete(legacyDesktopFile)
        }
    }
}

State_Shutdown() {
    State_FlushNow()
}
