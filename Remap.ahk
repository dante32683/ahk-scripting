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
!+v::Send "^+v"    ; Paste as Plain Text (Cmd+Shift+V)
!z::Send "^z"      ; Undo
!y::Send "^y"      ; Redo (Windows standard)
!+z::Send "^y"     ; Redo (macOS standard: Cmd+Shift+Z)
!a::Send "^a"      ; Select All

; --- File / Document / App Operations ---
!s::Send "^s"      ; Save
!+s::Send "^+s"    ; Save As
!o::Send "^o"      ; Open
!p::Send "^p"      ; Print
!+p::Send "^+p"    ; Command Palette / Advanced Print
!n::Send "^n"      ; New File/Window
!+n::Send "^+n"    ; New Incognito/Private Window
!f::Send "^f"      ; Find
!+f::Send "^+f"    ; Find in Files (Global Search)
!g::Send "^g"      ; Find Next
!+g::Send "^+g"    ; Find Previous
!h::Send "^h"      ; Replace (Ctrl+H on Windows)
!,::Send "^,"      ; Preferences/Settings (Cmd+,)

; --- Window / Tab Management ---
!w::Send "^w"      ; Close Tab/Window
!+w::Send "^+w"    ; Close All Tabs/Window
!t::Send "^t"      ; New Tab
!+t::Send "^+t"    ; Restore Closed Tab
!r::Send "^r"      ; Refresh/Reload
!+r::Send "^+r"    ; Hard Refresh
!m::WinMinimize "A" ; Minimize Window (Cmd+M)

; --- View / Zoom ---
!=::Send "^{=}"    ; Zoom In (Cmd+=)
!NumpadAdd::Send "^{NumpadAdd}" ; Zoom In
!-::Send "^{-}"    ; Zoom Out (Cmd+-)
!NumpadSub::Send "^{NumpadSub}" ; Zoom Out
!0::Send "^0"      ; Reset Zoom

; --- Browser / Navigation ---
!l::Send "^l"      ; Focus Address Bar
!d::Send "^d"      ; Bookmark
!+d::Send "^+d"    ; Bookmark All Tabs
!+b::Send "^+b"    ; Toggle Bookmarks Bar
![::Send "!{Left}"  ; Back (Cmd+[ -> Alt+Left)
!]::Send "!{Right}" ; Forward (Cmd+] -> Alt+Right)
!+[::Send "^{PgUp}" ; Previous Tab (Cmd+Shift+[ -> Ctrl+PgUp)
!+]::Send "^{PgDn}" ; Next Tab (Cmd+Shift+] -> Ctrl+PgDn)
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
!k::Send "^k"      ; Insert Hyperlink (Cmd+K)
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

; Cmd + Delete -> Delete to end of line
!Delete::Send "+{End}{Delete}"

; Cmd + Enter -> Send/Submit
!Enter::Send "^{Enter}"

#HotIf