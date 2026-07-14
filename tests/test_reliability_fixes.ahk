#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
global CFG_Autocorrect := false
#Include WindowFixture.ahk

; Stubs for StateStore / Autocorrect isolation
_GetWinSignature(windowHandle) => ""
Perf_Log(*) => 0
Perf_Increment(*) => 0
ShowOSD(*) => 0

#Include ..\lib\Layout.ahk
#Include ..\lib\StateStore.ahk
#Include ..\lib\Autocorrect_Logic.ahk
#Include ..\lib\Build_Autocorrect.ahk

RunReliabilityFixesTest() {
    ; --- State_Init resets maps (no leftover from prior mutations) ---
    State_SetAppLayout("leftover.exe", Layout_Slot(0, 0, 50, 100))
    AssertTrue(g_StateAppLayouts.Has("leftover.exe"), "precondition: leftover present")
    State_Init()
    AssertFalse(g_StateAppLayouts.Has("leftover.exe"), "State_Init clears prior app layouts")

    ; --- Persistent layout clear must remove both rect and maximized memory ---
    State_SetAppLayout("app.exe", Layout_Slot(0, 0, 50, 100))
    State_SetAppMaximized("app.exe", true)
    AssertTrue(g_StateAppLayouts.Has("app.exe"), "app layout stored")
    AssertTrue(g_StateAppMaximized.Has("app.exe"), "app maximized stored")
    State_DeleteAppLayout("app.exe")
    AssertFalse(g_StateAppLayouts.Has("app.exe"), "DeleteAppLayout removes rect")
    AssertFalse(g_StateAppMaximized.Has("app.exe"), "DeleteAppLayout removes maximized")
    ; Cleared layout must not silently reappear from an empty get.
    AssertEq(State_GetAppLayout("app.exe"), "", "cleared layout returns empty")

    ; --- Schema: missing / unsupported versions rejected ---
    schemaDir := A_Temp "\ahk_schema_test_" DllCall("GetCurrentProcessId")
    try DirCreate(schemaDir)
    badMissing := schemaDir "\missing.ini"
    FileAppend("[AppLayouts]`n", badMissing, "UTF-8")
    threw := false
    try State_LoadStateFile(badMissing)
    catch
        threw := true
    AssertTrue(threw, "missing schema version throws")

    badFuture := schemaDir "\future.ini"
    FileAppend("[Schema]`nversion=99`n", badFuture, "UTF-8")
    threw := false
    try State_LoadStateFile(badFuture)
    catch
        threw := true
    AssertTrue(threw, "future schema version throws")

    ; --- Identity: empty / incomplete maps cannot verify an HWND ---
    AssertFalse(_ValidateWindowIdentity(1, Map()), "empty identity rejected")
    AssertFalse(_ValidateWindowIdentity(1, Map("pid", 0, "proc", "")), "zero pid rejected")
    AssertFalse(_ValidateWindowIdentity(1, "not-a-map"), "non-map identity rejected")

    ; --- Failed atomic write preserves destination and reports failure ---
    existing := schemaDir "\keep-me.ini"
    FileAppend("good-content`n", existing, "UTF-8")
    beforeContent := FileRead(existing, "UTF-8")
    ; Point temp write at an impossible path to force failure without deleting existing.
    AssertFalse(State_AtomicWrite(schemaDir "\no_such_dir\nested\file.ini", "x"), "atomic write fails for bad path")
    AssertTrue(FileExist(existing), "existing good file still present after unrelated failure")
    ; Compare to the pre-failure bytes (UTF-8 BOM can make a literal string compare fail).
    AssertEq(FileRead(existing, "UTF-8"), beforeContent, "existing content preserved")

    ; --- Autocorrect: empty corrections rejected; InputHook path is test-mode safe ---
    emptyCorrPath := A_Temp "\ac_empty_" DllCall("GetCurrentProcessId") ".txt"
    FileAppend("teh->`n", emptyCorrPath, "UTF-8")
    emptyResult := AC_ParseDatabase(emptyCorrPath)
    AssertFalse(emptyResult["ok"], "empty correction rejected")
    AssertTrue(InStr(emptyResult["error"], "empty correction"), "empty correction error text")
    try FileDelete(emptyCorrPath)

    AC_Reg("teh", "the", "teh", "the")
    genBefore := AC_Generation
    AC_StartInputHook()  ; CFG_TestMode: must no-op without crashing / InputHook shadowing
    AssertEq(AC_Generation, genBefore, "test-mode StartInputHook leaves generation intact")
    AssertEq(AC_InputHook, 0, "test-mode StartInputHook does not install a hook")

    ; Stale-hook generation guard: clear only matches current generation
    AC_HadSubsequentInput := false
    AC_OnHookEnd(genBefore - 1, 0)  ; stale
    AssertEq(AC_LastTrigger, "teh", "stale OnEnd does not clear newer correction")
    AC_ClearLastCorrection()

    ; Cleanup temp schema dir
    try DirDelete(schemaDir, true)
}

RunReliabilityFixesTest()
Test_Pass("reliability_fixes")
ExitApp(0)
