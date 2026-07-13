#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk

; ShowOSD.ahk resolves the active monitor via Core's MonitorFromPoint at runtime.
; Stub it so this isolated unit stays self-contained (no unresolved cross-file refs).
MonitorFromPoint(x, y) => 1

#Include ..\lib\ShowOSD.ahk

; Regression for the OSD repeating-timer leak. The fade timer was created with
; `_OsdFadeTick.Bind(gen)` but stopped with the bare `_OsdFadeTick` — a different
; function object — so it never stopped. The fix stores the exact bound object in
; g_OsdFadeTimer and stops THAT object.

; Stopping clears the stored bound object.
g_OsdGeneration := 7
g_OsdPhase := "fading"
g_OsdFadeTimer := _OsdFadeTick.Bind(7)
_OsdStopFadeTimer()
AssertEq(g_OsdFadeTimer, 0, "stop clears the stored bound timer object")

; A stale-generation tick must self-cancel instead of re-arming forever.
g_OsdGeneration := 9
g_OsdPhase := "fading"
g_OsdFadeTimer := _OsdFadeTick.Bind(2)   ; older generation than 9
_OsdFadeTick(2)                          ; stale -> must stop, not continue fading
AssertEq(g_OsdFadeTimer, 0, "stale tick self-cancels via the stored object")

; A tick after a phase change (no longer fading) must also cancel.
g_OsdGeneration := 3
g_OsdPhase := "idle"
g_OsdFadeTimer := _OsdFadeTick.Bind(3)
_OsdFadeTick(3)
AssertEq(g_OsdFadeTimer, 0, "non-fading tick cancels")

; Shutdown tears everything down cleanly.
g_OsdFadeTimer := _OsdFadeTick.Bind(1)
_OsdShutdown()
AssertEq(g_OsdFadeTimer, 0, "shutdown stops the fade timer")
AssertEq(g_OsdPhase, "idle", "shutdown resets phase")

Test_Pass("osd_timer")
ExitApp(0)
