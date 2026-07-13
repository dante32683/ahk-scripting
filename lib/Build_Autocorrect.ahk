#Requires AutoHotkey v2.0+

; Auto-rebuild on startup if Autocorrect.ahk is missing/empty or older than the database
if (IsSet(CFG_Autocorrect) && CFG_Autocorrect) {
    if BuildAutocorrect()
        SafeReload()
}

; Returns true if Autocorrect.ahk was rebuilt, false if already up to date.
BuildAutocorrect() {
    startTime := A_TickCount
    ; repoRoot is the directory where Master.ahk / Master-PC.ahk live.
    ; A_ScriptDir is reliably the project root for this architecture.
    repoRoot := A_ScriptDir
    dbPath   := repoRoot "\Autocorrect_Database.txt"
    outPath  := repoRoot "\lib\Autocorrect.ahk"
    builderPath := A_LineFile

    if !FileExist(dbPath) {
        Perf_Log("autocorrect_rebuild", "no_db", A_TickCount - startTime)
        return false
    }

    ; Skip rebuild only when the output is newer than both the database and the builder,
    ; and is not just an empty stub (< 200 bytes = no hotstrings generated yet)
    if FileExist(outPath)
        && (FileGetTime(dbPath, "M") <= FileGetTime(outPath, "M"))
        && (FileGetTime(builderPath, "M") <= FileGetTime(outPath, "M")) {
        try
            outSize := FileGetSize(outPath)
        catch
            outSize := 0
        if (outSize > 200) {
            Perf_Log("autocorrect_rebuild", "skip", A_TickCount - startTime)
            return false
        }
    }

    try
        dbContent := FileRead(dbPath, "UTF-8")
    catch {
        Perf_Log("autocorrect_rebuild", "read_failed", A_TickCount - startTime)
        return false
    }

    ; Collect valid lines, sort them alphabetically (case-insensitive)
    rawLines := ""
    loop parse, dbContent, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line != "" && InStr(line, "->"))
            rawLines .= line "`n"
    }
    sortedContent := Sort(RTrim(rawLines, "`n"))

    q := Chr(34)  ; double-quote character
    out := "#Requires AutoHotkey v2.0+`n`n"
    out .= "; AUTO-GENERATED — edit Autocorrect_Database.txt, not this file.`n`n"
    out .= "#HotIf CFG_Autocorrect`n"

    seenTriggers := Map()
    loop parse, sortedContent, "`n", "`r" {
        arrowPos := InStr(A_LoopField, "->")
        if !arrowPos
            continue

        rawTrigger    := Trim(SubStr(A_LoopField, 1, arrowPos - 1))
        rawCorrection := Trim(SubStr(A_LoopField, arrowPos + 2))

        if (rawTrigger = "")
            continue

        seenKey := StrLower(rawTrigger)
        if seenTriggers.Has(seenKey)
            continue
        seenTriggers[seenKey] := true

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

            out .= ":CX:" typedTrigger "::AC_Proc(" q sCanonicalTrig q ", " q sCanonicalCorr q ", " q sTypedTrig q ", " q sTypedCorr q ")`n"
        }
    }

    out .= "#HotIf`n"

    try {
        if FileExist(outPath)
            FileDelete(outPath)
        FileAppend(out, outPath, "UTF-8")
    } catch as e {
        MsgBox("Error writing Autocorrect.ahk: " e.Message)
        Perf_Log("autocorrect_rebuild", "write_failed", A_TickCount - startTime)
        return false
    }
    Perf_Log("autocorrect_rebuild", "success", A_TickCount - startTime)
    return true
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
