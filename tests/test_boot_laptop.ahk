#Requires AutoHotkey v2.0+
#SingleInstance Off
; Side-effect-free boot smoke tests (do not steal the live Master instance).
global CFG_TestMode := true
global APP_ProfileOverride := "laptop"
#Include ..\Main.ahk
