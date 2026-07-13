#Requires AutoHotkey v2.0+

global CFG_PerfLogging := false
global g_PerfBuffer := []
global g_PerfCounters := Map(
    "state_flushes", 0,
    "win_moves", 0,
    "wmi_queries", 0,
    "foreground_events", 0,
    "location_changes", 0,
    "drift_reconciliations", 0
)

Perf_Init() {
    global CFG_PerfLogging
    if !IsSet(CFG_PerfLogging)
        CFG_PerfLogging := false
        
    if !CFG_PerfLogging
        return
        
    ; Set up a timer to flush every 5 seconds
    SetTimer(Perf_Flush, 5000)
    
    ; Register OnExit to flush remaining logs
    OnExit(Perf_OnExit)
}

Perf_Log(event, val1 := "", val2 := "", val3 := "") {
    global CFG_PerfLogging, g_PerfBuffer
    if !CFG_PerfLogging
        return
    
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    row := timestamp "," event "," val1 "," val2 "," val3
    g_PerfBuffer.Push(row)
}

Perf_Increment(counter) {
    global CFG_PerfLogging, g_PerfCounters
    if !CFG_PerfLogging
        return
    if g_PerfCounters.Has(counter)
        g_PerfCounters[counter] := g_PerfCounters[counter] + 1
}

Perf_Flush() {
    global CFG_PerfLogging, g_PerfBuffer, g_PerfCounters
    if !CFG_PerfLogging
        return
    if g_PerfBuffer.Length = 0
        return
        
    outDir := A_Temp "\AutoHotkeyMaster"
    if !DirExist(outDir) {
        try DirCreate(outDir)
        catch
            return
    }
        
    outFile := outDir "\perf.csv"
    
    content := ""
    for row in g_PerfBuffer {
        content .= row "`n"
    }
    
    g_PerfBuffer := []
    
    try {
        FileAppend(content, outFile, "UTF-8")
    } catch {
        ; Silently fail if file is locked
    }
}

Perf_OnExit(ExitReason := "", ExitCode := "") {
    Perf_Flush()
}
