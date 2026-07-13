#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk
#Include ..\lib\Layout.ahk

; Build a synthetic window snapshot matching FocusDirection's shape.
MakeWindowSnapshot(left, top, width, height, monitorIndex := 1, zOrderIndex := 1) {
    return {x: left, y: top, w: width, h: height
        , cx: left + width // 2, cy: top + height // 2
        , mon: monitorIndex, index: zOrderIndex}
}

; Executable assertions live in a function so the many local variables never collide
; with library globals (which would trip #Warn LocalSameAsGlobal).
RunFocusScoringTest() {
    ; --- Interval separation ---
    AssertEq(_IntervalSeparation(0, 10, 20, 30), 10, "disjoint separation")
    AssertEq(_IntervalSeparation(0, 25, 20, 30), 0, "overlap -> zero")
    AssertEq(_IntervalSeparation(20, 30, 0, 10), 10, "disjoint reversed")

    currentWindow := MakeWindowSnapshot(1000, 500, 400, 300, 1, 5)

    ; --- Half-plane filtering ---
    windowToTheRight := MakeWindowSnapshot(1500, 500, 400, 300)
    AssertEq(_EvaluateFocusCandidate(currentWindow, windowToTheRight, "left"), 0, "right window is not a left candidate")
    AssertTrue(_EvaluateFocusCandidate(currentWindow, windowToTheRight, "right") != 0, "right window is a right candidate")
    windowToTheLeft := MakeWindowSnapshot(200, 500, 400, 300)
    AssertTrue(_EvaluateFocusCandidate(currentWindow, windowToTheLeft, "left") != 0, "left window is a left candidate")

    ; --- Tuple ordering: closer primary gap wins ---
    nearCandidateScore := _EvaluateFocusCandidate(currentWindow, MakeWindowSnapshot(1450, 500, 300, 300), "right")
    farCandidateScore := _EvaluateFocusCandidate(currentWindow, MakeWindowSnapshot(1900, 500, 300, 300), "right")
    AssertTrue(_FocusScoreIsBetter(nearCandidateScore, farCandidateScore), "nearer candidate beats farther")
    AssertFalse(_FocusScoreIsBetter(farCandidateScore, nearCandidateScore), "farther does not beat nearer")

    ; --- Same-monitor preference dominates distance ---
    farSameMonitorScore := _EvaluateFocusCandidate(currentWindow, MakeWindowSnapshot(1900, 500, 300, 300, 1, 2), "right")
    nearOtherMonitorScore := _EvaluateFocusCandidate(currentWindow, MakeWindowSnapshot(1440, 500, 300, 300, 2, 3), "right")
    AssertTrue(_FocusScoreIsBetter(farSameMonitorScore, nearOtherMonitorScore), "same-monitor wins even when farther")

    ; --- Deterministic tiebreak: identical geometry -> lower z-order index wins ---
    lowerZOrderScore := _EvaluateFocusCandidate(currentWindow, MakeWindowSnapshot(1450, 500, 300, 300, 1, 2), "right")
    higherZOrderScore := _EvaluateFocusCandidate(currentWindow, MakeWindowSnapshot(1450, 500, 300, 300, 1, 9), "right")
    AssertTrue(_FocusScoreIsBetter(lowerZOrderScore, higherZOrderScore), "lower z-order index breaks exact tie")
    AssertFalse(_FocusScoreIsBetter(higherZOrderScore, lowerZOrderScore), "tiebreak is strict and stable")

    ; --- Backdrop skip ---
    engulfingBackdrop := MakeWindowSnapshot(0, 0, 3000, 2000, 1, 1)
    AssertTrue(_CandidateIsBackdropWindow(currentWindow, engulfingBackdrop), "engulfing window flagged as backdrop")
    normalNeighbor := MakeWindowSnapshot(1450, 500, 300, 300)
    AssertFalse(_CandidateIsBackdropWindow(currentWindow, normalNeighbor), "normal neighbor is not a backdrop")
}

RunFocusScoringTest()
Test_Pass("focus_scoring")
ExitApp(0)
