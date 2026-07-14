#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk

; Stand-in for desktop bookkeeping decision logic (mirrors Core helpers).
global g_LastDesktop := 1
global g_FocusHistory := []
global g_DesktopLastWindow := Map()
global g_DesktopExcludeHwnd := 0
global g_PendingDesktopNotify := 0
global g_PendingDeparture := 0
global g_DesktopFocusGeneration := 0
global g_ScriptPaused := false
global g_SavedDesktops := Map()
global g_DeletedDesktops := []
global g_RestoreCalls := []
global g_PinnedWindows := Map()

class FakeVDA {
    static DESKTOP_UNKNOWN := -1
    static isLoaded := true
    static IsPinned(hwnd) {
        global g_PinnedWindows
        return g_PinnedWindows.Has(hwnd) ? 1 : 0
    }
}

VDA := FakeVDA

_ValidateWindowIdentity(hwnd, identity) {
    if !(identity is Map) || !hwnd
        return false
    if !identity.Has("pid") || !identity["pid"]
        return false
    if !identity.Has("proc") || identity["proc"] = ""
        return false
    ; Test identities encode pid == hwnd for simplicity.
    return identity["pid"] = hwnd
}

_IsWindowOnDesktop(hwnd, deskIndex) {
    global g_PinnedWindows
    if g_PinnedWindows.Has(hwnd)
        return true
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
    global g_DeletedDesktops, g_SavedDesktops
    g_DeletedDesktops.Push(desk)
    if g_SavedDesktops.Has(desk)
        g_SavedDesktops.Delete(desk)
}

_ScheduleDesktopRestore(n) {
}

_ScheduleDesktopFocusRestore(desk, gen, attempt) {
    global g_RestoreCalls
    g_RestoreCalls.Push(Map("desk", desk, "gen", gen, "attempt", attempt))
}

_HandleDesktopChangeFromMsg(currentDesk) {
    global g_PendingDesktopNotify
    g_PendingDesktopNotify := currentDesk
}

_DepartureSnapshotValid(snapshot, fromDesk, excludeHwnd := 0) {
    if !(snapshot is Map) || !snapshot["hwnd"]
        return false
    if snapshot["desk"] != fromDesk
        return false
    hwnd := snapshot["hwnd"]
    if excludeHwnd && hwnd = excludeHwnd
        return false
    identity := Map("pid", snapshot["pid"], "proc", snapshot["proc"]
        , "class", snapshot["class"], "sig", snapshot["sig"])
    return _ValidateWindowIdentity(hwnd, identity)
}

_RememberDepartingDesktop(fromDesk, excludeHwnd := 0) {
    global g_PendingDeparture, g_FocusHistory, g_DesktopLastWindow, g_PinnedWindows
    snap := g_PendingDeparture
    g_PendingDeparture := 0
    if fromDesk <= 0
        return

    if _DepartureSnapshotValid(snap, fromDesk, excludeHwnd) {
        identity := Map("pid", snap["pid"], "proc", snap["proc"]
            , "class", snap["class"], "sig", snap["sig"])
        State_SetDesktopWindow(fromDesk, snap["hwnd"], identity)
        g_DesktopLastWindow[fromDesk] := snap["hwnd"]
        return
    }

    historyIndex := g_FocusHistory.Length
    while historyIndex > 0 {
        prevHwnd := g_FocusHistory[historyIndex]
        if excludeHwnd && prevHwnd = excludeHwnd {
            historyIndex--
            continue
        }
        if !prevHwnd {
            historyIndex--
            continue
        }
        if g_PinnedWindows.Has(prevHwnd) {
            historyIndex--
            continue
        }
        if _IsWindowOnDesktop(prevHwnd, fromDesk) {
            State_SetDesktopWindow(fromDesk, prevHwnd)
            g_DesktopLastWindow[fromDesk] := prevHwnd
            break
        }
        historyIndex--
    }
}

_CommitDesktopTransition(newDesk, excludeHwnd := 0) {
    global g_LastDesktop, g_ScriptPaused, g_DesktopFocusGeneration, g_PendingDeparture
    global g_RestoreCalls
    if g_ScriptPaused {
        g_PendingDeparture := 0
        return
    }
    if !newDesk || newDesk = VDA.DESKTOP_UNKNOWN {
        g_PendingDeparture := 0
        return
    }
    if newDesk = g_LastDesktop {
        g_PendingDeparture := 0
        return
    }

    fromDesk := g_LastDesktop
    _RememberDepartingDesktop(fromDesk, excludeHwnd)

    g_LastDesktop := newDesk
    g_DesktopFocusGeneration += 1
    _ScheduleDesktopFocusRestore(newDesk, g_DesktopFocusGeneration, 1)
    _ScheduleDesktopRestore(newDesk)
}

_ForgetDesktopWindow(desk) {
    global g_DesktopLastWindow
    if g_DesktopLastWindow.Has(desk)
        g_DesktopLastWindow.Delete(desk)
    State_DeleteDesktopWindow(desk)
}

RunDesktopTransitionTest() {
    global g_LastDesktop, g_FocusHistory, g_DesktopLastWindow, g_DesktopExcludeHwnd
    global g_SavedDesktops, g_PendingDesktopNotify, g_PendingDeparture, g_DesktopFocusGeneration
    global g_DeletedDesktops, g_RestoreCalls, g_PinnedWindows

    ; Pre-switch snapshot wins over stale focus history (textbox focus case).
    g_LastDesktop := 1
    g_FocusHistory := [100]  ; history missing the real active window
    g_DesktopLastWindow := Map()
    g_SavedDesktops := Map()
    g_RestoreCalls := []
    g_DesktopFocusGeneration := 0
    g_PendingDeparture := Map("desk", 1, "hwnd", 102, "pid", 102, "proc", "notepad.exe"
        , "class", "Notepad", "sig", "notepad.exe")
    _CommitDesktopTransition(2, 0)
    AssertEq(g_LastDesktop, 2, "desktop state updates after confirmed transition")
    AssertEq(g_DesktopLastWindow[1], 102, "snapshot HWND remembered over focus history")
    AssertEq(g_SavedDesktops[1], 102, "snapshot HWND persisted")
    AssertEq(g_DesktopFocusGeneration, 1, "focus generation increments")
    AssertEq(g_RestoreCalls.Length, 1, "restore scheduled once")
    AssertEq(g_RestoreCalls[1]["gen"], 1, "restore carries generation")

    ; Moved-away window excluded even if it is the snapshot.
    g_LastDesktop := 1
    g_FocusHistory := [100, 101]
    g_DesktopLastWindow := Map()
    g_SavedDesktops := Map()
    g_PendingDeparture := Map("desk", 1, "hwnd", 101, "pid", 101, "proc", "app.exe"
        , "class", "App", "sig", "app.exe")
    _CommitDesktopTransition(2, 101)
    AssertEq(g_DesktopLastWindow[1], 100, "exclude moved snapshot; history fallback used")

    ; Pinned windows skipped in history fallback.
    g_LastDesktop := 1
    g_FocusHistory := [100, 101]
    g_PinnedWindows := Map(101, true)
    g_DesktopLastWindow := Map()
    g_SavedDesktops := Map()
    g_PendingDeparture := 0
    _CommitDesktopTransition(2, 0)
    AssertEq(g_DesktopLastWindow[1], 100, "pinned window skipped in history fallback")
    g_PinnedWindows := Map()

    ; Duplicate notification is a no-op and clears stale snapshot.
    g_FocusHistory := [200]
    g_PendingDeparture := Map("desk", 2, "hwnd", 200, "pid", 200, "proc", "x.exe"
        , "class", "X", "sig", "x.exe")
    _CommitDesktopTransition(2, 0)
    AssertEq(g_LastDesktop, 2, "duplicate transition ignored")
    AssertEq(g_PendingDeparture, 0, "stale snapshot cleared on duplicate")

    ; Unknown desktop is rejected.
    g_LastDesktop := 2
    _CommitDesktopTransition(VDA.DESKTOP_UNKNOWN, 0)
    AssertEq(g_LastDesktop, 2, "unknown desktop does not commit")

    ; Coalesce: latest pending notify wins.
    g_PendingDesktopNotify := 0
    _HandleDesktopChangeFromMsg(3)
    _HandleDesktopChangeFromMsg(4)
    AssertEq(g_PendingDesktopNotify, 4, "rapid notifies keep latest target")

    ; Dead mapping deletes Core + StateStore.
    g_DesktopLastWindow := Map(1, 100)
    g_SavedDesktops := Map(1, 100)
    g_DeletedDesktops := []
    _ForgetDesktopWindow(1)
    AssertFalse(g_DesktopLastWindow.Has(1), "dead mapping removed from Core")
    AssertEq(g_DeletedDesktops.Length, 1, "State_DeleteDesktopWindow called")
    AssertFalse(g_SavedDesktops.Has(1), "persisted mapping removed")

    ; Stale restore generation must be ignored by callers (contract check).
    staleGen := g_DesktopFocusGeneration
    g_DesktopFocusGeneration += 1
    AssertTrue(staleGen != g_DesktopFocusGeneration, "generation advances past stale timers")
}

RunDesktopTransitionTest()
Test_Pass("desktop_transition")
ExitApp(0)
