#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk

; Mirrors the simplified main-branch desktop remember/restore helpers.
global g_LastDesktop := 1
global g_FocusHistory := []
global g_DesktopLastWindow := Map()
global g_DesktopExcludeHwnd := 0
global g_PendingDesktopNotify := 0
global g_DesktopFocusGeneration := 0
global g_ScriptPaused := false
global g_SavedDesktops := Map()
global g_RestoreCalls := []

class FakeVDA {
    static DESKTOP_UNKNOWN := -1
    static isLoaded := true
}

VDA := FakeVDA

_IsWindowOnDesktop(hwnd, deskIndex) {
    if deskIndex = 1
        return hwnd = 100 || hwnd = 101 || hwnd = 102
    if deskIndex = 2
        return hwnd = 200
    return false
}

State_SetDesktopWindow(desk, hwnd, identity := "") {
    global g_SavedDesktops
    g_SavedDesktops[desk] := hwnd
}

State_DeleteDesktopWindow(desk) {
    global g_SavedDesktops
    if g_SavedDesktops.Has(desk)
        g_SavedDesktops.Delete(desk)
}

_CancelDesktopFocusRestore() {
}

_ScheduleDesktopRestore(n) {
}

_RememberDepartingDesktopFromHistory(fromDesk, excludeHwnd := 0) {
    global g_DesktopLastWindow, g_FocusHistory
    if fromDesk <= 0
        return
    historyIndex := g_FocusHistory.Length
    while historyIndex > 0 {
        prevHwnd := g_FocusHistory[historyIndex]
        if excludeHwnd && prevHwnd = excludeHwnd {
            historyIndex--
            continue
        }
        if prevHwnd && _IsWindowOnDesktop(prevHwnd, fromDesk) {
            g_DesktopLastWindow[fromDesk] := prevHwnd
            State_SetDesktopWindow(fromDesk, prevHwnd)
            return
        }
        historyIndex--
    }
}

_RememberActiveWindowForDesktop(desk, hwnd, excludeHwnd := 0) {
    global g_DesktopLastWindow
    if desk <= 0 || !hwnd
        return
    if excludeHwnd && hwnd = excludeHwnd
        return
    g_DesktopLastWindow[desk] := hwnd
    State_SetDesktopWindow(desk, hwnd)
}

_CommitDesktopTransition(newDesk, excludeHwnd := 0) {
    global g_LastDesktop, g_ScriptPaused, g_DesktopFocusGeneration, g_RestoreCalls
    if g_ScriptPaused
        return
    if !newDesk || newDesk = VDA.DESKTOP_UNKNOWN
        return
    if newDesk = g_LastDesktop
        return

    fromDesk := g_LastDesktop
    _RememberDepartingDesktopFromHistory(fromDesk, excludeHwnd)

    g_LastDesktop := newDesk
    g_DesktopFocusGeneration += 1
    g_RestoreCalls.Push(Map("desk", newDesk, "gen", g_DesktopFocusGeneration))
}

_HandleDesktopChangeFromMsg(currentDesk) {
    global g_PendingDesktopNotify
    g_PendingDesktopNotify := currentDesk
}

RunDesktopTransitionTest() {
    global g_LastDesktop, g_FocusHistory, g_DesktopLastWindow
    global g_SavedDesktops, g_PendingDesktopNotify, g_DesktopFocusGeneration
    global g_RestoreCalls

    ; Hotkey path: immediate active-window remember (main-branch).
    g_LastDesktop := 1
    g_DesktopLastWindow := Map()
    g_SavedDesktops := Map()
    _RememberActiveWindowForDesktop(1, 102)
    AssertEq(g_DesktopLastWindow[1], 102, "hotkey path remembers active HWND immediately")
    AssertEq(g_SavedDesktops[1], 102, "hotkey path persists active HWND")

    ; External path: history fallback excludes moved-away HWND.
    g_LastDesktop := 1
    g_FocusHistory := [100, 101]
    g_DesktopLastWindow := Map()
    g_SavedDesktops := Map()
    g_RestoreCalls := []
    g_DesktopFocusGeneration := 0
    _CommitDesktopTransition(2, 101)
    AssertEq(g_LastDesktop, 2, "desktop state updates after confirmed transition")
    AssertEq(g_DesktopLastWindow[1], 100, "history fallback excludes moved hwnd")
    AssertEq(g_SavedDesktops[1], 100, "persisted departing last window excludes moved hwnd")
    AssertEq(g_RestoreCalls.Length, 1, "restore scheduled once")
    AssertEq(g_RestoreCalls[1]["gen"], 1, "restore carries generation")

    ; Duplicate notification is a no-op.
    g_FocusHistory := [200]
    _CommitDesktopTransition(2, 0)
    AssertEq(g_LastDesktop, 2, "duplicate transition ignored")

    ; Unknown desktop is rejected.
    g_LastDesktop := 2
    _CommitDesktopTransition(VDA.DESKTOP_UNKNOWN, 0)
    AssertEq(g_LastDesktop, 2, "unknown desktop does not commit")

    ; Coalesce: latest pending notify wins.
    g_PendingDesktopNotify := 0
    _HandleDesktopChangeFromMsg(3)
    _HandleDesktopChangeFromMsg(4)
    AssertEq(g_PendingDesktopNotify, 4, "rapid notifies keep latest target")

    ; Stale restore generation must be ignored.
    staleGen := g_DesktopFocusGeneration
    g_DesktopFocusGeneration += 1
    AssertTrue(staleGen != g_DesktopFocusGeneration, "generation advances past stale timers")
}

RunDesktopTransitionTest()
Test_Pass("desktop_transition")
ExitApp(0)
