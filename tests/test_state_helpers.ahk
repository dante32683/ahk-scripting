#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk

; Minimal stub used by StateStore identity helpers during include.
_GetWinSignature(windowHandle) => ""

#Include ..\lib\Layout.ahk
#Include ..\lib\StateStore.ahk

; Wrapped in a function so local variable names never collide with library globals.
RunStateHelpersTest() {
    ; --- Layout serialize/deserialize roundtrip ---
    slotRecord := Layout_Slot(10, 20, 30, 40)
    serialized := Layout_Serialize(slotRecord)
    deserialized := Layout_Deserialize(serialized)
    AssertTrue(Layout_Validate(deserialized), "deserialized record validates")
    AssertEq(deserialized["x"], 1000, "x basis points preserved")
    AssertEq(deserialized["w"], 3000, "w basis points preserved")

    ; Legacy 4-tuple still parses.
    legacyRecord := Layout_Deserialize("12,12,75,75")
    AssertTrue(Layout_Validate(legacyRecord), "legacy tuple validates")
    AssertEq(legacyRecord["x"], 1200, "legacy pct scaled to basis points")

    ; --- Identity validation ---
    AssertFalse(_ValidateWindowIdentity(0, Map("pid", 1, "proc", "x.exe")), "hwnd 0 rejected")
    AssertFalse(_ValidateWindowIdentity(1, Map()), "empty identity cannot verify HWND")
    AssertFalse(_ValidateWindowIdentity(1, Map("pid", 5)), "identity without proc rejected")

    ; --- Persistent layout clear ---
    State_SetAppLayout("clear-me.exe", Layout_Slot(10, 10, 40, 40))
    State_SetAppMaximized("clear-me.exe", true)
    State_DeleteAppLayout("clear-me.exe")
    AssertEq(State_GetAppLayout("clear-me.exe"), "", "cleared persistent layout is gone")
    AssertFalse(g_StateAppMaximized.Has("clear-me.exe"), "cleared maximized flag is gone")

    ; --- INI escaping roundtrips (strict; no `|| true` escape hatch) ---
    AssertEq(State_UnescapeIni(State_EscapeIni("hello")), "hello", "plain roundtrip")
    AssertEq(State_UnescapeIni(State_EscapeIni("a=b[c]")), "a=b[c]", "special chars roundtrip")
    AssertTrue(InStr(State_EscapeIni("a=b"), "``="), "= is actually escaped")

    ; The pipe delimiter used to pack DesktopLastWindow records MUST be encoded so a
    ; value containing '|' cannot corrupt the record layout.
    valueWithPipes := "proc|with|pipes"
    escapedValue := State_EscapeIni(valueWithPipes)
    AssertFalse(InStr(escapedValue, "|"), "raw pipe removed by escaping")
    AssertEq(State_UnescapeIni(escapedValue), valueWithPipes, "pipe roundtrips losslessly")

    ; --- Desktop identity is stored and round-trips, not silently dropped ---
    State_SetDesktopWindow(3, 12345, Map("pid", 42, "proc", "example.exe", "class", "ExampleClass", "sig", "example.exe:title"))
    AssertEq(State_GetDesktopWindow(3), 12345, "desktop hwnd stored")
    storedIdentity := State_GetDesktopWindowIdentity(3)
    AssertEq(storedIdentity["pid"], 42, "desktop identity pid stored")
    AssertEq(storedIdentity["proc"], "example.exe", "desktop identity proc stored")
}

RunStateHelpersTest()
Test_Pass("state_store_helpers")
ExitApp(0)
