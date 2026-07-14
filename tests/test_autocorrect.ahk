#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk

; BuildAutocorrect() records telemetry via Core's Perf_Log. AC_ParseDatabase (the unit
; under test) does not, but stub it so the isolated module has no unresolved refs.
Perf_Log(*) => 0

#Include ..\lib\Build_Autocorrect.ahk

WriteTemporaryDatabase(name, content) {
    databasePath := A_Temp "\autocorrect_test_" DllCall("GetCurrentProcessId") "_" name ".txt"
    if FileExist(databasePath)
        FileDelete(databasePath)
    FileAppend(content, databasePath, "UTF-8")
    return databasePath
}

; Wrapped in a function so local variable names never collide with library globals.
RunAutocorrectParserTest() {
    createdDatabaseFiles := []

    ; --- Valid database parses, sorts, and counts ---
    validDatabasePath := WriteTemporaryDatabase("valid", "teh->the`nrecieve->receive`nabc->alphabet`n")
    createdDatabaseFiles.Push(validDatabasePath)
    validResult := AC_ParseDatabase(validDatabasePath)
    AssertTrue(validResult["ok"], "valid database parses")
    AssertEq(validResult["count"], 3, "three entries parsed")
    AssertEq(validResult["entries"][1]["trigger"], "abc", "entries sorted case-insensitively")

    ; --- Case-insensitive duplicate is a hard error reporting both lines ---
    duplicateDatabasePath := WriteTemporaryDatabase("duplicate", "im->I'm`nIm->I'm`n")
    createdDatabaseFiles.Push(duplicateDatabasePath)
    duplicateResult := AC_ParseDatabase(duplicateDatabasePath)
    AssertFalse(duplicateResult["ok"], "duplicate trigger rejected")
    AssertTrue(InStr(duplicateResult["error"], "duplicate"), "error names the duplicate")

    ; --- Malformed lines rejected, not silently skipped ---
    missingArrowPath := WriteTemporaryDatabase("noarrow", "teh->the`nbrokenline`n")
    createdDatabaseFiles.Push(missingArrowPath)
    AssertFalse(AC_ParseDatabase(missingArrowPath)["ok"], "missing -> rejected")
    emptyTriggerPath := WriteTemporaryDatabase("empty", "->the`n")
    createdDatabaseFiles.Push(emptyTriggerPath)
    AssertFalse(AC_ParseDatabase(emptyTriggerPath)["ok"], "empty trigger rejected")
    emptyCorrPath := WriteTemporaryDatabase("emptycorr", "teh->`n")
    createdDatabaseFiles.Push(emptyCorrPath)
    emptyCorrResult := AC_ParseDatabase(emptyCorrPath)
    AssertFalse(emptyCorrResult["ok"], "empty correction rejected")
    AssertTrue(InStr(emptyCorrResult["error"], "empty correction"), "empty correction names the problem")

    ; --- Comments and blank lines are ignored ---
    withCommentsPath := WriteTemporaryDatabase("comments", "; header comment`n`nteh->the`n")
    createdDatabaseFiles.Push(withCommentsPath)
    withCommentsResult := AC_ParseDatabase(withCommentsPath)
    AssertTrue(withCommentsResult["ok"], "comments/blanks tolerated")
    AssertEq(withCommentsResult["count"], 1, "only the real entry counted")

    ; --- Case variant generation ---
    AssertEq(_AC_TitleCase("teh"), "Teh", "title-case capitalizes first letter")
    AssertEq(_AC_TitleCase("i'm"), "I'm", "title-case leaves apostrophes intact")
    AssertEq(StrUpper("teh"), "TEH", "upper variant")

    ; --- String-literal escaping for generated hotstrings ---
    escapedLiteral := _AC_EscapeStringLiteral('a"b')
    AssertTrue(InStr(escapedLiteral, Chr(96) Chr(34)), "double quote escaped with backtick")

    for databaseFile in createdDatabaseFiles
        try FileDelete(databaseFile)
}

RunAutocorrectParserTest()
Test_Pass("autocorrect_parser")
ExitApp(0)
