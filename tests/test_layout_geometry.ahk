#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk
#Include ..\lib\Layout.ahk

; Wrapped in a function so local variable names never collide with library globals.
RunLayoutGeometryTest() {
    ; --- Slot record shape and roundtrip ---
    leftHalfSlot := Layout_Slot(0, 0, 50, 100)
    AssertTrue(Layout_Validate(leftHalfSlot), "slot validates")
    AssertEq(leftHalfSlot["kind"], "slot")
    AssertEq(leftHalfSlot["x"], 0)
    AssertEq(leftHalfSlot["w"], 5000)

    serialized := Layout_Serialize(leftHalfSlot)
    deserialized := Layout_Deserialize(serialized)
    AssertTrue(Layout_Validate(deserialized), "roundtrip validates")
    AssertEq(deserialized["kind"], "slot")
    AssertEq(deserialized["w"], 5000)

    legacyRecord := Layout_Deserialize("12,12,75,75")
    AssertTrue(Layout_Validate(legacyRecord), "legacy pct validates")
    AssertEq(legacyRecord["x"], 1200)

    resolvedRect := Layout_ResolveVisibleRect(Layout_Slot(0, 0, 50, 100), 0, 0, 1000, 800, 4)
    AssertTrue(resolvedRect != 0, "resolve returns rect")
    AssertTrue(resolvedRect.w > 0 && resolvedRect.h > 0, "resolved size positive")

    ; Gap is applied to slot records only.
    fullSlotWithGap := Layout_ResolveVisibleRect(Layout_Slot(0, 0, 100, 100), 0, 0, 1000, 800, 10)
    AssertEq(fullSlotWithGap.x, 10, "slot gap insets left edge")
    AssertEq(fullSlotWithGap.w, 980, "slot gap insets width both sides")

    AssertTrue(Layout_RectsDiffer({x:0,y:0,w:10,h:10}, {x:10,y:0,w:10,h:10}, 4), "differing rects")
    AssertFalse(Layout_RectsDiffer({x:0,y:0,w:10,h:10}, {x:2,y:1,w:10,h:10}, 4), "within tolerance")

    ; --- Anchor derivation from slot geometry (drives min-size compensation) ---
    AssertEq(Layout_Slot(0, 0, 50, 100)["anchorX"], "left", "left column -> anchor left")
    AssertEq(Layout_Slot(50, 0, 50, 100)["anchorX"], "right", "right column -> anchor right")
    AssertEq(Layout_Slot(33, 0, 34, 100)["anchorX"], "center", "middle column -> anchor center")
    AssertEq(Layout_Slot(0, 0, 100, 50)["anchorX"], "stretch", "full width -> anchor stretch")
    AssertEq(Layout_Slot(0, 50, 100, 50)["anchorY"], "bottom", "bottom row -> anchor bottom")
    AssertEq(Layout_Slot(0, 0, 100, 50)["anchorY"], "top", "top row -> anchor top")

    ; --- Minimum-size compensation uses anchors, not pre-move heuristics ---
    ; A window that accepted 700px when only 500 was requested has 200px overflow.
    acceptedWideRect := {x: 1000, y: 0, w: 700, h: 300, r: 1700, b: 300}

    leftAnchoredSlot := Layout_Slot(0, 0, 50, 100)
    leftCompensated := _CompensateConstrainedPosition(leftAnchoredSlot, acceptedWideRect, 500, 300, 0, 0, 1000, 0)
    AssertEq(leftCompensated.x, 1000, "left anchor keeps x")

    rightAnchoredSlot := Layout_Slot(50, 0, 50, 100)
    rightCompensated := _CompensateConstrainedPosition(rightAnchoredSlot, acceptedWideRect, 500, 300, 0, 0, 1000, 0)
    AssertEq(rightCompensated.x, 800, "right anchor shifts x left by full overflow")

    centerAnchoredSlot := Layout_Slot(25, 0, 50, 100)
    centerCompensated := _CompensateConstrainedPosition(centerAnchoredSlot, acceptedWideRect, 500, 300, 0, 0, 1000, 0)
    AssertEq(centerCompensated.x, 900, "center anchor shifts x left by half overflow")

    ; No overflow -> no shift.
    acceptedFittingRect := {x: 1000, y: 0, w: 500, h: 300, r: 1500, b: 300}
    fittingCompensated := _CompensateConstrainedPosition(rightAnchoredSlot, acceptedFittingRect, 500, 300, 0, 0, 1000, 0)
    AssertEq(fittingCompensated.x, 1000, "no overflow -> position unchanged")
}

RunLayoutGeometryTest()
Test_Pass("layout_geometry")
ExitApp(0)
