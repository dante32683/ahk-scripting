; ============================================================
; NATIVE TILING LOGIC & HOTKEYS
; ============================================================

#HotIf GetKeyState("CapsLock", "P") && g_TilingMode = "Native"

; --- Tiling: Rectangle-style (Alt + CapsLock) ---
!w:: TileTop()
!a:: TileLeft()
!s:: TileBottom()
!d:: TileRight()

!q:: TileTopLeft()
!e:: TileTopRight()
!z:: TileBottomLeft()
!c:: TileBottomRight()

!u:: TileLeftThird()
!i:: TileCenterThird()
!o:: TileRightThird()

!y:: TileLeft60()
!p:: TileRight40()

!Enter:: ToggleMaximize()

; --- Layout cycle ---
Tab:: CycleLayout()

; --- Focus ---
*h:: FocusDirection("left")
*j:: FocusDirection("down")
*k:: FocusDirection("up")
*l:: FocusDirection("right")
Backspace:: FocusJumpBack()

; --- Window control ---
!f:: ToggleMaximize()
!g:: FloatCenter()

#HotIf
