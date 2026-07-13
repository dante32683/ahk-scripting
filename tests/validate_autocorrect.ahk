#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk

; Stub Core's Perf_Log so this isolated validator has no unresolved cross-file refs.
Perf_Log(*) => 0

#Include ..\lib\Build_Autocorrect.ahk

ValidateAutocorrectDatabase() {
    databasePath := A_ScriptDir "\..\Autocorrect_Database.txt"
    parseResult := AC_ParseDatabase(databasePath)
    if !parseResult["ok"] {
        FileAppend("FAIL autocorrect_db: " parseResult["error"] "`n", "*", "UTF-8")
        ExitApp(1)
    }
    AssertTrue(parseResult["count"] > 0, "database has entries")
    Test_Pass("autocorrect_db count=" parseResult["count"])
}

ValidateAutocorrectDatabase()
ExitApp(0)
