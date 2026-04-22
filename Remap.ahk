#Requires AutoHotkey v2.0+
#SingleInstance Force

; ==============================================================================
; macOS-like Command Key Remapping (Alt -> Ctrl)
; ==============================================================================
; This script remaps the physical Alt key (which physically sits where the 
; Mac Command key sits) to send Ctrl combinations for common shortcuts.

#HotIf !GetKeyState("CapsLock", "P")

; --- Basic Editing ---
!c::Send "^c"      ; Copy
!x::Send "^x"      ; Cut
!v::Send "^v"      ; Paste
!z::Send "^z"      ; Undo
!y::Send "^y"      ; Redo (Windows standard)
!+z::Send "^y"     ; Redo (macOS standard: Cmd+Shift+Z)
!a::Send "^a"      ; Select All

; --- File / Document Operations ---
!s::Send "^s"      ; Save
!o::Send "^o"      ; Open
!p::Send "^p"      ; Print
!n::Send "^n"      ; New File/Window
!f::Send "^f"      ; Find
!h::Send "^h"      ; Replace (Ctrl+H on Windows)

; --- Window / Tab Management ---
!w::Send "^w"      ; Close Tab/Window
!t::Send "^t"      ; New Tab
!r::Send "^r"      ; Refresh/Reload
!m::WinMinimize "A" ; Minimize Window (Cmd+M)

; --- Browser / Navigation ---
!l::Send "^l"      ; Focus Address Bar
![::Send "!{Left}"  ; Back (Cmd+[ -> Alt+Left)
!]::Send "!{Right}" ; Forward (Cmd+] -> Alt+Right)
!1::Send "^1"      ; Switch to Tab 1
!2::Send "^2"      ; Switch to Tab 2
!3::Send "^3"      ; Switch to Tab 3
!4::Send "^4"      ; Switch to Tab 4
!5::Send "^5"      ; Switch to Tab 5
!6::Send "^6"      ; Switch to Tab 6
!7::Send "^7"      ; Switch to Tab 7
!8::Send "^8"      ; Switch to Tab 8
!9::Send "^9"      ; Switch to Tab 9

; --- Text Formatting ---
!b::Send "^b"      ; Bold
!i::Send "^i"      ; Italic
!u::Send "^u"      ; Underline
!/::Send "^/"      ; Comment code (Ctrl+/)

; --- Selection / Movement (macOS style) ---
; Cmd + Left/Right -> Home/End (Start/End of line)
!Left::Send "{Home}"
!Right::Send "{End}"
!+Left::Send "+{Home}"
!+Right::Send "+{End}"

; Cmd + Up/Down -> Ctrl+Home/Ctrl+End (Top/Bottom of document)
!Up::Send "^{Home}"
!Down::Send "^{End}"
!+Up::Send "+^{Home}"
!+Down::Send "+^{End}"

; Cmd + Backspace -> Delete to start of line
!Backspace::Send "+{Home}{Backspace}"

#HotIf
