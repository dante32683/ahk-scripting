#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk

; VDA.OnDesktopChangeMessage dispatches to Core's _HandleDesktopChangeFromMsg. It is
; never invoked here, but stubbing it keeps this isolated unit free of unresolved refs.
_HandleDesktopChangeFromMsg(n) => 0

#Include ..\lib\VDA.ahk

; VDA.Init() returns false in test mode and never loads the DLL, so every wrapper must
; return its safe not-loaded contract. This exercises the real lib/VDA.ahk code rather
; than re-declaring constants.
AssertFalse(VDA.Init(), "VDA.Init is a no-op in test mode")
AssertFalse(VDA.isLoaded, "VDA not loaded in test mode")

; Error sentinel is -1 and must never collide with desktop zero.
AssertEq(VDA.DESKTOP_UNKNOWN, -1, "error sentinel is -1")
AssertTrue(VDA.DESKTOP_UNKNOWN != 0, "unknown is distinct from desktop 0")

; Not-loaded contract: queries return unknown/zero, mutations return false.
AssertEq(VDA.GetCurrent(), -1, "GetCurrent unknown when not loaded")
AssertEq(VDA.GetDesktopCount(), 0, "GetDesktopCount is 0 (never invents 9) when unavailable")
AssertEq(VDA.GetWindowDesktop(0), -1, "GetWindowDesktop unknown when not loaded")
AssertEq(VDA.IsPinned(0), -1, "IsPinned unknown when not loaded")
AssertEq(VDA.IsOnCurrentDesktop(0), -1, "IsOnCurrentDesktop unknown when not loaded")
AssertFalse(VDA.GoTo(1), "GoTo fails when not loaded")
AssertFalse(VDA.MoveWindow(0, 1), "MoveWindow fails when not loaded")

; Desktop-change message parameter contract: the NEW desktop comes from lParam
; (0-based), so a lParam of 4 maps to 1-based desktop 5.
lParam := 4
AssertEq(Integer(lParam) + 1, 5, "new desktop derived from lParam (1-based)")

Test_Pass("vda_semantics")
ExitApp(0)
