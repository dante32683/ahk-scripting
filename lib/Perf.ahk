#Requires AutoHotkey v2.0+

; Do not overwrite a config-provided CFG_PerfLogging value.
if !IsSet(CFG_PerfLogging)
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
global g_PerfHeaderWritten := false
global g_PerfLastCounterSig := ""

Perf_Init() {
    global CFG_PerfLogging, CFG_TestMode
    if !IsSet(CFG_PerfLogging)
        global CFG_PerfLogging := false
    if (IsSet(CFG_TestMode) && CFG_TestMode) || !CFG_PerfLogging
        return
    SetTimer(Perf_Flush, 5000)
    OnExit(Perf_OnExit)
}

Perf_CsvEscape(value) {
    value := String(value)
    if InStr(value, ",") || InStr(value, '"') || InStr(value, "`n")
        return '"' StrReplace(value, '"', '""') '"'
    return value
}

Perf_Log(event, val1 := "", val2 := "", val3 := "") {
    global CFG_PerfLogging, g_PerfBuffer
    if !CFG_PerfLogging
        return
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    row := Perf_CsvEscape(timestamp) "," Perf_CsvEscape(event) "," Perf_CsvEscape(val1) "," Perf_CsvEscape(val2) "," Perf_CsvEscape(val3)
    g_PerfBuffer.Push(row)
}

Perf_Increment(counter) {
    global CFG_PerfLogging, g_PerfCounters
    if !CFG_PerfLogging
        return
    if g_PerfCounters.Has(counter)
        g_PerfCounters[counter] := g_PerfCounters[counter] + 1
}

Perf_Flush(*) {
    global CFG_PerfLogging, g_PerfBuffer, g_PerfCounters, g_PerfHeaderWritten, g_PerfLastCounterSig
    if !CFG_PerfLogging
        return

    ; Build a signature of current counters so we can emit a snapshot row whenever any
    ; counter changed, even if no timed events were buffered this interval.
    counterSig := ""
    for k, v in g_PerfCounters
        counterSig .= k "=" v ";"
    countersChanged := (counterSig != g_PerfLastCounterSig)

    if g_PerfBuffer.Length = 0 && !countersChanged
        return

    outDir := A_Temp "\AutoHotkeyMaster"
    if !DirExist(outDir) {
        try DirCreate(outDir)
        catch
            return
    }
    outFile := outDir "\perf.csv"

    pending := g_PerfBuffer.Clone()
    content := ""
    if !g_PerfHeaderWritten && !FileExist(outFile)
        content .= "timestamp,event,val1,val2,val3`n"
    for row in pending
        content .= row "`n"
    if countersChanged {
        ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        content .= Perf_CsvEscape(ts) ",counters," Perf_CsvEscape(counterSig) ",,`n"
    }

    try {
        FileAppend(content, outFile, "UTF-8")
        ; Only clear/advance state after the append actually succeeded, so a locked
        ; file does not silently discard buffered rows or the counter snapshot.
        g_PerfBuffer := []
        g_PerfHeaderWritten := true
        g_PerfLastCounterSig := counterSig
    } catch {
        ; Keep buffer and last-counter signature on failure; retry next interval.
    }
}

Perf_OnExit(ExitReason := "", ExitCode := "") {
    Perf_Flush()
}
