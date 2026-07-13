#Requires AutoHotkey v2.0+

; Returns true if Autocorrect.ahk was rebuilt, false if already up to date.
; Startup auto-rebuild is triggered from Main.ahk after SafeReload exists.
BuildAutocorrect() {
    startTime := A_TickCount
    ; Builder lives in lib/; repository root is its parent directory.
    SplitPath(A_LineFile, , &libDir)
    SplitPath(libDir, , &repoRoot)
    dbPath   := repoRoot "\Autocorrect_Database.txt"
    outPath  := repoRoot "\lib\Autocorrect.ahk"
    builderPath := A_LineFile

    if !FileExist(dbPath) {
        Perf_Log("autocorrect_rebuild", "no_db", A_TickCount - startTime)
        return false
    }

    if FileExist(outPath)
        && (FileGetTime(dbPath, "M") <= FileGetTime(outPath, "M"))
        && (FileGetTime(builderPath, "M") <= FileGetTime(outPath, "M")) {
        try
            outSize := FileGetSize(outPath)
        catch
            outSize := 0
        ; Compact CX form is far smaller than the legacy multi-line artifact
        if (outSize > 200) {
            headerOk := false
            try {
                f := FileOpen(outPath, "r", "UTF-8")
                sample := f.Read(4000)
                f.Close()
                headerOk := InStr(sample, ":CX:") > 0
            }
            if headerOk {
                Perf_Log("autocorrect_rebuild", "skip", A_TickCount - startTime)
                return false
            }
        }
    }

    parseResult := AC_ParseDatabase(dbPath)
    if !parseResult["ok"] {
        try FileAppend("Autocorrect DB error: " parseResult["error"] "`n", "*", "UTF-8")
        if !(IsSet(CFG_TestMode) && CFG_TestMode)
            MsgBox("Autocorrect database validation failed:`n" parseResult["error"], "Autocorrect Build", "Icon!")
        Perf_Log("autocorrect_rebuild", "validate_failed", A_TickCount - startTime)
        return false
    }

    q := Chr(34)
    segments := []
    segments.Push("#Requires AutoHotkey v2.0+`n`n")
    segments.Push("; AUTO-GENERATED — edit Autocorrect_Database.txt, not this file.`n")
    segments.Push("; schema=cx1 count=" parseResult["count"] "`n`n")
    segments.Push("#HotIf CFG_Autocorrect`n")

    for entry in parseResult["entries"] {
        rawTrigger := entry["trigger"]
        rawCorrection := entry["correction"]
        variants := Map()
        variants[rawTrigger] := rawCorrection
        if RegExMatch(rawTrigger, "[A-Za-z]") {
            titleTrigger := _AC_TitleCase(rawTrigger)
            upperTrigger := StrUpper(rawTrigger)
            variants[titleTrigger] := _AC_TitleCase(rawCorrection)
            variants[upperTrigger] := StrUpper(rawCorrection)
        }
        sCanonicalTrig := _AC_EscapeStringLiteral(rawTrigger)
        sCanonicalCorr := _AC_EscapeStringLiteral(rawCorrection)
        for typedTrigger, typedCorrection in variants {
            sTypedTrig := _AC_EscapeStringLiteral(typedTrigger)
            sTypedCorr := _AC_EscapeStringLiteral(typedCorrection)
            segments.Push(":CX:" typedTrigger "::AC_Proc(" q sCanonicalTrig q ", " q sCanonicalCorr q ", " q sTypedTrig q ", " q sTypedCorr q ")`n")
        }
    }
    segments.Push("#HotIf`n")

    out := ""
    for seg in segments
        out .= seg

    tempPath := outPath "." DllCall("GetCurrentProcessId") ".tmp"
    try {
        if FileExist(tempPath)
            FileDelete(tempPath)
        FileAppend(out, tempPath, "UTF-8")
        if !InStr(FileRead(tempPath, "UTF-8"), ":CX:")
            throw Error("Generated file missing :CX: hotstrings")
        ; Atomic replace — never delete the good file first
        if !DllCall("MoveFileExW", "Str", tempPath, "Str", outPath, "UInt", 9) {
            ; Fallback for cross-volume issues
            FileCopy(tempPath, outPath, true)
            FileDelete(tempPath)
        }
    } catch as e {
        try FileDelete(tempPath)
        MsgBox("Error writing Autocorrect.ahk: " e.Message)
        Perf_Log("autocorrect_rebuild", "write_failed", A_TickCount - startTime)
        return false
    }
    Perf_Log("autocorrect_rebuild", "success", A_TickCount - startTime)
    return true
}

; Strict parser shared by build and validator.
AC_ParseDatabase(dbPath) {
    result := Map("ok", true, "error", "", "entries", [], "count", 0)
    try
        dbContent := FileRead(dbPath, "UTF-8")
    catch as e {
        result["ok"] := false
        result["error"] := "Cannot read database: " e.Message
        return result
    }

    seen := Map()
    lineNo := 0
    rawLines := ""
    loop parse, dbContent, "`n", "`r" {
        lineNo++
        line := Trim(A_LoopField)
        if line = "" || SubStr(line, 1, 1) = ";"
            continue
        arrowPos := InStr(line, "->")
        if !arrowPos {
            result["ok"] := false
            result["error"] := "Line " lineNo ": missing '->' separator"
            return result
        }
        rawTrigger := Trim(SubStr(line, 1, arrowPos - 1))
        rawCorrection := Trim(SubStr(line, arrowPos + 2))
        if rawTrigger = "" {
            result["ok"] := false
            result["error"] := "Line " lineNo ": empty trigger"
            return result
        }
        key := StrLower(rawTrigger)
        if seen.Has(key) {
            result["ok"] := false
            result["error"] := "Line " lineNo ": duplicate trigger '" rawTrigger "' (also line " seen[key] ")"
            return result
        }
        seen[key] := lineNo
        rawLines .= rawTrigger "`t" rawCorrection "`t" lineNo "`n"
    }

    sortedContent := Sort(RTrim(rawLines, "`n"), "COff")
    entries := []
    loop parse, sortedContent, "`n", "`r" {
        parts := StrSplit(A_LoopField, "`t")
        if parts.Length < 2
            continue
        entries.Push(Map("trigger", parts[1], "correction", parts[2], "line", parts.Length >= 3 ? Integer(parts[3]) : 0))
    }
    result["entries"] := entries
    result["count"] := entries.Length
    return result
}

_AC_EscapeStringLiteral(value) {
    value := StrReplace(value, Chr(96), Chr(96) Chr(96))
    return StrReplace(value, Chr(34), Chr(96) Chr(34))
}

_AC_TitleCase(value) {
    if value = ""
        return value
    return StrUpper(SubStr(value, 1, 1)) SubStr(value, 2)
}
