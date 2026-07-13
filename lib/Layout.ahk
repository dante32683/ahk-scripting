#Requires AutoHotkey v2.0+

; Typed layout records: slot (gap-adjusted presets) vs visible (learned frames).
; Coordinates are basis points 0..10000 (0.01% of monitor work area).

Layout_Slot(xPct, yPct, wPct, hPct, anchorX := "", anchorY := "") {
    ; When anchors are not given explicitly, derive them from the slot's position so
    ; minimum-size compensation shifts a constrained window toward the correct edge:
    ;   full span  -> stretch (no shift)
    ;   touches low edge only  -> left/top
    ;   touches high edge only -> right/bottom
    ;   interior span          -> center
    if anchorX = ""
        anchorX := _DeriveSlotAnchor(xPct, wPct, "left", "right")
    if anchorY = ""
        anchorY := _DeriveSlotAnchor(yPct, hPct, "top", "bottom")
    return Map(
        "kind", "slot",
        "x", Round(xPct * 100),
        "y", Round(yPct * 100),
        "w", Round(wPct * 100),
        "h", Round(hPct * 100),
        "anchorX", anchorX,
        "anchorY", anchorY
    )
}

_DeriveSlotAnchor(startPercent, sizePercent, lowEdgeAnchorName, highEdgeAnchorName) {
    endPercent := startPercent + sizePercent
    touchesLowEdge := startPercent <= 1
    touchesHighEdge := endPercent >= 99
    if touchesLowEdge && touchesHighEdge
        return "stretch"
    if touchesHighEdge
        return highEdgeAnchorName
    if touchesLowEdge
        return lowEdgeAnchorName
    return "center"
}

Layout_FromLegacyPct(xf, yf, wf, hf, kind := "slot") {
    return Map(
        "kind", kind,
        "x", Round(Integer(xf) * 100),
        "y", Round(Integer(yf) * 100),
        "w", Round(Integer(wf) * 100),
        "h", Round(Integer(hf) * 100),
        "anchorX", "left",
        "anchorY", "top"
    )
}

Layout_VisibleFromWindow(hwnd) {
    vis := Window_GetVisibleRect(hwnd)
    if !vis
        return 0
    ; Resolve monitor from window center without depending on Core helpers.
    cx := vis.x + vis.w // 2
    cy := vis.y + vis.h // 2
    L := 0, T := 0, R := 0, B := 0
    found := false
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &mL, &mT, &mR, &mB)
        if cx >= mL && cx < mR && cy >= mT && cy < mB {
            L := mL, T := mT, R := mR, B := mB
            found := true
            break
        }
    }
    if !found
        MonitorGetWorkArea(MonitorGetPrimary(), &L, &T, &R, &B)
    MW := R - L, MH := B - T
    if !MW || !MH
        return 0
    return Map(
        "kind", "visible",
        "x", Round((vis.x - L) * 10000 / MW),
        "y", Round((vis.y - T) * 10000 / MH),
        "w", Round(vis.w * 10000 / MW),
        "h", Round(vis.h * 10000 / MH),
        "anchorX", "left",
        "anchorY", "top"
    )
}

Layout_Validate(record) {
    if !(record is Map)
        return false
    if !record.Has("kind") || !record.Has("x") || !record.Has("y") || !record.Has("w") || !record.Has("h")
        return false
    if record["kind"] != "slot" && record["kind"] != "visible"
        return false
    for key in ["x", "y", "w", "h"] {
        v := record[key]
        if !(v is Integer) && !(v is Float)
            return false
        if v < -500 || v > 15000
            return false
    }
    if record["w"] <= 0 || record["h"] <= 0
        return false
    return true
}

Layout_ToLegacyPct(record) {
    if !(record is Map)
        return record
    return [
        Round(record["x"] / 100),
        Round(record["y"] / 100),
        Round(record["w"] / 100),
        Round(record["h"] / 100)
    ]
}

Layout_Serialize(record) {
    if !(record is Map)
        return ""
    return record["kind"] "," record["x"] "," record["y"] "," record["w"] "," record["h"]
        . "," (record.Has("anchorX") ? record["anchorX"] : "left")
        . "," (record.Has("anchorY") ? record["anchorY"] : "top")
}

Layout_Deserialize(str) {
    if str = ""
        return 0
    parts := StrSplit(str, ",")
    if parts.Length = 4 {
        ; legacy percentage tuple
        return Layout_FromLegacyPct(parts[1], parts[2], parts[3], parts[4])
    }
    if parts.Length >= 5 {
        kind := parts[1]
        if kind = "slot" || kind = "visible" {
            rec := Map(
                "kind", kind,
                "x", Integer(parts[2]),
                "y", Integer(parts[3]),
                "w", Integer(parts[4]),
                "h", Integer(parts[5]),
                "anchorX", parts.Length >= 6 ? parts[6] : "left",
                "anchorY", parts.Length >= 7 ? parts[7] : "top"
            )
            return Layout_Validate(rec) ? rec : 0
        }
        ; numeric-only legacy with 5 ints unlikely; treat first4 as legacy
        return Layout_FromLegacyPct(parts[1], parts[2], parts[3], parts[4])
    }
    return 0
}

Layout_ResolveVisibleRect(record, L, T, R, B, gap := 0) {
    MW := R - L, MH := B - T
    if !MW || !MH || !Layout_Validate(record)
        return 0

    x := L + Round(record["x"] * MW / 10000)
    y := T + Round(record["y"] * MH / 10000)
    w := Round(record["w"] * MW / 10000)
    h := Round(record["h"] * MH / 10000)

    if record["kind"] = "slot" && gap > 0 {
        x += gap
        y += gap
        w -= gap * 2
        h -= gap * 2
    }

    if w < 1
        w := 1
    if h < 1
        h := 1

    return {x: x, y: y, w: w, h: h, r: x + w, b: y + h}
}

Window_GetOuterRect(hwnd) {
    if !DllCall("IsWindow", "Ptr", hwnd)
        return 0
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return {x: x, y: y, w: w, h: h, r: x + w, b: y + h}
    }
    return 0
}

Window_GetVisibleRect(hwnd) {
    outer := Window_GetOuterRect(hwnd)
    if !outer
        return 0
    ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
    rect := Buffer(16, 0)
    hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", rect, "UInt", 16, "Int")
    if hr = 0 {
        left := NumGet(rect, 0, "Int")
        top := NumGet(rect, 4, "Int")
        right := NumGet(rect, 8, "Int")
        bottom := NumGet(rect, 12, "Int")
        return {x: left, y: top, w: right - left, h: bottom - top, r: right, b: bottom}
    }
    return outer
}

Window_GetFrameOffsets(hwnd) {
    outer := Window_GetOuterRect(hwnd)
    vis := Window_GetVisibleRect(hwnd)
    if !outer || !vis
        return {left: 0, top: 0, right: 0, bottom: 0}
    return {
        left: vis.x - outer.x,
        top: vis.y - outer.y,
        right: outer.r - vis.r,
        bottom: outer.b - vis.b
    }
}

Window_OuterFromVisibleRect(hwnd, vis) {
    off := Window_GetFrameOffsets(hwnd)
    return {
        x: vis.x - off.left,
        y: vis.y - off.top,
        w: vis.w + off.left + off.right,
        h: vis.h + off.top + off.bottom
    }
}

Layout_RectsDiffer(a, b, tol := 4) {
    if !a || !b
        return true
    return Abs(a.x - b.x) > tol
        || Abs(a.y - b.y) > tol
        || Abs(a.w - b.w) > tol
        || Abs(a.h - b.h) > tol
}

; Position-only compensation for windows that could not shrink to the requested
; size because of a minimum width/height. Called with the ACTUAL visible rect the
; window accepted after the initial move. targetOuterX/targetOuterY are the outer
; target coordinates for a left/top-anchored placement. We only shift position (the
; size is already whatever the window would accept) so the anchor edge lands where
; intended.
_CompensateConstrainedPosition(layoutRecord, acceptedVisibleRect, requiredWidth, requiredHeight, frameOffsetLeft, frameOffsetTop, targetOuterX, targetOuterY) {
    compensatedX := targetOuterX
    compensatedY := targetOuterY
    horizontalAnchor := layoutRecord.Has("anchorX") ? layoutRecord["anchorX"] : "left"
    verticalAnchor := layoutRecord.Has("anchorY") ? layoutRecord["anchorY"] : "top"

    if (acceptedVisibleRect.w > requiredWidth) {
        widthOverflow := acceptedVisibleRect.w - requiredWidth
        if horizontalAnchor = "right"
            compensatedX := targetOuterX - widthOverflow
        else if horizontalAnchor = "center"
            compensatedX := targetOuterX - widthOverflow // 2
        ; left / stretch: keep the left edge at the target (overflow to the right)
    }
    if (acceptedVisibleRect.h > requiredHeight) {
        heightOverflow := acceptedVisibleRect.h - requiredHeight
        if verticalAnchor = "bottom"
            compensatedY := targetOuterY - heightOverflow
        else if verticalAnchor = "center"
            compensatedY := targetOuterY - heightOverflow // 2
        ; top / stretch: keep the top edge at the target (overflow downward)
    }
    return {x: compensatedX, y: compensatedY}
}

; ============================================================
; Pure directional focus scoring (unit-tested; no Win32 calls)
; Candidate/current window rects are {x,y,w,h,cx,cy,mon,index} objects, where cx/cy
; are the window center and index is its z-order enumeration position.
; ============================================================

; Separation between two 1-D intervals; zero when they overlap.
_IntervalSeparation(firstIntervalStart, firstIntervalEnd, secondIntervalStart, secondIntervalEnd) {
    if firstIntervalEnd <= secondIntervalStart
        return secondIntervalStart - firstIntervalEnd
    if secondIntervalEnd <= firstIntervalStart
        return firstIntervalStart - secondIntervalEnd
    return 0
}

; True if candidateWindow is a large background window engulfing currentWindow (an
; occluded backdrop), which should never be treated as a directional neighbor.
_CandidateIsBackdropWindow(currentWindow, candidateWindow) {
    engulfsCurrentCenter := currentWindow.cx >= candidateWindow.x
        && currentWindow.cx <= candidateWindow.x + candidateWindow.w
        && currentWindow.cy >= candidateWindow.y
        && currentWindow.cy <= candidateWindow.y + candidateWindow.h
    if !engulfsCurrentCenter
        return false
    candidateArea := candidateWindow.w * candidateWindow.h
    currentArea := currentWindow.w * currentWindow.h
    return candidateArea >= currentArea * 2
}

; Evaluate a candidate for the given direction. Returns a comparable score tuple
; (smaller is better) or 0 if the candidate is not in the requested half-plane. The
; tuple order is deterministic and matches the plan:
;   [same-monitor penalty, perpendicular gap, primary edge gap, center offset, z-order]
; Z-order (enumeration index) participates only as the final tiebreaker, so results
; never depend on WinGetList ordering except to break otherwise-exact ties.
_EvaluateFocusCandidate(currentWindow, candidateWindow, direction, tileGap := 0) {
    if direction = "left" {
        if candidateWindow.cx >= currentWindow.cx
            return 0
        primaryEdgeGap := currentWindow.x - (candidateWindow.x + candidateWindow.w)
        perpendicularGap := _IntervalSeparation(candidateWindow.y, candidateWindow.y + candidateWindow.h, currentWindow.y, currentWindow.y + currentWindow.h)
        centerOffset := Abs(candidateWindow.cy - currentWindow.cy)
    } else if direction = "right" {
        if candidateWindow.cx <= currentWindow.cx
            return 0
        primaryEdgeGap := candidateWindow.x - (currentWindow.x + currentWindow.w)
        perpendicularGap := _IntervalSeparation(candidateWindow.y, candidateWindow.y + candidateWindow.h, currentWindow.y, currentWindow.y + currentWindow.h)
        centerOffset := Abs(candidateWindow.cy - currentWindow.cy)
    } else if direction = "up" {
        if candidateWindow.cy >= currentWindow.cy
            return 0
        primaryEdgeGap := currentWindow.y - (candidateWindow.y + candidateWindow.h)
        perpendicularGap := _IntervalSeparation(candidateWindow.x, candidateWindow.x + candidateWindow.w, currentWindow.x, currentWindow.x + currentWindow.w)
        centerOffset := Abs(candidateWindow.cx - currentWindow.cx)
    } else if direction = "down" {
        if candidateWindow.cy <= currentWindow.cy
            return 0
        primaryEdgeGap := candidateWindow.y - (currentWindow.y + currentWindow.h)
        perpendicularGap := _IntervalSeparation(candidateWindow.x, candidateWindow.x + candidateWindow.w, currentWindow.x, currentWindow.x + currentWindow.w)
        centerOffset := Abs(candidateWindow.cx - currentWindow.cx)
    } else
        return 0
    if primaryEdgeGap < 0
        primaryEdgeGap := 0
    sameMonitorPenalty := (candidateWindow.mon = currentWindow.mon) ? 0 : 1
    return [sameMonitorPenalty, perpendicularGap, primaryEdgeGap, centerOffset, candidateWindow.index]
}

; Lexicographic comparison: true if candidateScore is strictly better (smaller) than
; incumbentScore, or if there is no incumbent yet (incumbentScore = 0).
_FocusScoreIsBetter(candidateScore, incumbentScore) {
    if !incumbentScore
        return true
    loop candidateScore.Length {
        if candidateScore[A_Index] < incumbentScore[A_Index]
            return true
        if candidateScore[A_Index] > incumbentScore[A_Index]
            return false
    }
    return false
}
