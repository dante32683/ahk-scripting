#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk

; Lightweight stand-in for the centralized desktop bookkeeping in Core.
global g_LastDesktop := 1
global g_FocusHistory := []
global g_DesktopLastWindow := Map()
global g_DesktopExcludeHwnd := 0
global g_ScriptPaused := false
global g_SavedDesktops := Map()

class FakeVDA {
    static DESKTOP_UNKNOWN := -1
    static isLoaded := true
}

VDA := FakeVDA

_IsWindowOnDesktop(hwnd, deskIndex) {
    ; Test double: windows 100/101 live on desk 1; 200 lives on desk 2.
    if deskIndex = 1
        return hwnd = 100 || hwnd = 101
    if deskIndex = 2
        return hwnd = 200
    return false
}

State_SetDesktopWindow(desk, hwnd, identity := "") {
    global g_SavedDesktops
    g_SavedDesktops[desk] := hwnd
}

_RestoreFocusOnDesktop(n) {
}

_ScheduleDesktopRestore(n) {
}

_CommitDesktopTransition(newDesk, excludeHwnd := 0) {
    global g_LastDesktop, g_FocusHistory, g_DesktopLastWindow, g_ScriptPaused, g_SavedDesktops
    if g_ScriptPaused
        return
    if !newDesk || newDesk = VDA.DESKTOP_UNKNOWN
        return
    if newDesk = g_LastDesktop
        return

    fromDesk := g_LastDesktop
    if fromDesk > 0 {
        historyIndex := g_FocusHistory.Length
        while historyIndex > 0 {
            prevHwnd := g_FocusHistory[historyIndex]
            if excludeHwnd && prevHwnd = excludeHwnd {
                historyIndex--
                continue
            }
            ; WinExist stubbed via numeric handles in this unit test.
            if prevHwnd && _IsWindowOnDesktop(prevHwnd, fromDesk) {
                State_SetDesktopWindow(fromDesk, prevHwnd)
                g_DesktopLastWindow[fromDesk] := prevHwnd
                break
            }
            historyIndex--
        }
    }

    g_LastDesktop := newDesk
}

RunDesktopTransitionTest() {
    global g_LastDesktop, g_FocusHistory, g_DesktopLastWindow, g_DesktopExcludeHwnd, g_SavedDesktops

    ; Departing desk should remember the last eligible window, not a moved-away one.
    g_LastDesktop := 1
    g_FocusHistory := [100, 101]  ; 101 was just moved to desk 2
    g_DesktopLastWindow := Map()
    g_SavedDesktops := Map()
    _CommitDesktopTransition(2, 101)
    AssertEq(g_LastDesktop, 2, "desktop state updates after confirmed transition")
    AssertEq(g_DesktopLastWindow[1], 100, "departing desk keeps prior eligible window")
    AssertEq(g_SavedDesktops[1], 100, "persisted departing last window excludes moved hwnd")

    ; Duplicate notification for the same target is a no-op.
    g_FocusHistory := [200]
    _CommitDesktopTransition(2, 0)
    AssertEq(g_LastDesktop, 2, "duplicate transition ignored")
    AssertFalse(g_SavedDesktops.Has(2), "no spurious save on duplicate")

    ; Unknown desktop is rejected (treated as error, not success).
    g_LastDesktop := 2
    _CommitDesktopTransition(VDA.DESKTOP_UNKNOWN, 0)
    AssertEq(g_LastDesktop, 2, "unknown desktop does not commit")
}

RunDesktopTransitionTest()
Test_Pass("desktop_transition")
ExitApp(0)
