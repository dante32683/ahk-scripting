#Requires AutoHotkey v2.0+

; Auto-rebuild on startup if Autocorrect.ahk is missing/empty or older than the database
if BuildAutocorrect()
    Reload()

; Returns true if Autocorrect.ahk was rebuilt, false if already up to date.
BuildAutocorrect() {
    SplitPath(A_LineFile, , &builderDir)
    repoRoot := builderDir "\.."
    dbPath   := repoRoot "\Autocorrect_Database.txt"
    outPath  := repoRoot "\lib\Autocorrect.ahk"
    builderPath := A_LineFile

    if !FileExist(dbPath) {
        MsgBox("Autocorrect database not found:`n" dbPath)
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
        if (outSize > 200)
            return false
    }

    try
        dbContent := FileRead(dbPath, "UTF-8")
    catch {
        MsgBox("Could not read autocorrect database.")
        return false
    }

    ; Collect valid lines, sort them alphabetically (case-insensitive), write back
    rawLines := ""
    loop parse, dbContent, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line != "" && InStr(line, "->"))
            rawLines .= line "`n"
    }
    sortedContent := Sort(RTrim(rawLines, "`n"))  ; AHK Sort is case-insensitive by default

    try {
        FileDelete(dbPath)
        FileAppend(sortedContent "`n", dbPath, "UTF-8")
    } catch as e {
        MsgBox("Error writing sorted database: " e.Message)
        return false
    }

    q := Chr(34)  ; double-quote character

    out := "#Requires AutoHotkey v2.0+`n`n"
    out .= "; AUTO-GENERATED — edit Autocorrect_Database.txt, not this file.`n`n"
    out .= "#HotIf CFG_Autocorrect`n"

    loop parse, sortedContent, "`n", "`r" {
        arrowPos := InStr(A_LoopField, "->")
        if !arrowPos
            continue

        rawTrigger    := Trim(SubStr(A_LoopField, 1, arrowPos - 1))
        rawCorrection := Trim(SubStr(A_LoopField, arrowPos + 2))

        if (rawTrigger = "")
            continue

        ; Escape " as `" for use inside double-quoted string literals
        sTrig := StrReplace(rawTrigger,    Chr(34), Chr(96) Chr(34))
        sCorr := StrReplace(rawCorrection, Chr(34), Chr(96) Chr(34))

        out .= ":C:" rawTrigger "::{`n"
        out .= "    if AC_IsDisabled(" q sTrig q ") {`n"
        out .= "        SendText(" q sTrig q " . A_EndChar)`n"
        out .= "        return`n"
        out .= "    }`n"
        out .= "    SendText(" q sCorr q " . A_EndChar)`n"
        out .= "    AC_Reg(" q sTrig q ", " q sCorr q ")`n"
        out .= "}`n"
    }

    out .= "#HotIf`n"

    try {
        if FileExist(outPath)
            FileDelete(outPath)
        FileAppend(out, outPath, "UTF-8")
    } catch as e {
        MsgBox("Error writing Autocorrect.ahk: " e.Message)
        return false
    }
    return true
}
