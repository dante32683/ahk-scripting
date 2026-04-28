; ============================================================
; NATIVE TILING LOGIC & HOTKEYS
; ============================================================

; Enable the automatic retiler timer
SetTimer(_CheckLayoutRestores, 2000)

; Set the mode for restoration functions
g_TilingMode := "Native"

#HotIf GetKeyState("CapsLock", "P")

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

; --- Window control ---
*f:: ToggleMaximize()
*g:: FloatCenter()

#HotIf
