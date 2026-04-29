; ============================================================
; NATIVE TILING LOGIC & HOTKEYS
; ============================================================

#HotIf GetKeyState("CapsLock", "P") && g_TilingMode = "Native"

; --- Tiling: halves & quadrants ---
*z:: TileLeft()
*x:: TileRight()
*F1:: TileTopLeft()
*F2:: TileTopRight()
*F3:: TileBottomLeft()
*F4:: TileBottomRight()

; --- Tiling: thirds & splits ---
*y:: TileLeft60()
*u:: TileLeftThird()
*i:: TileCenterThird()
*o:: TileRightThird()
*p:: TileRight40()

; --- Layout cycle ---
Tab:: CycleLayout()

; --- Focus ---
*h:: FocusDirection("left")
*j:: FocusDirection("down")
*k:: FocusDirection("up")
*l:: FocusDirection("right")
Backspace:: FocusJumpBack()

; --- Window control ---
*f:: ToggleMaximize()
*g:: FloatCenter()

#HotIf
