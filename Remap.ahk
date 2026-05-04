#Requires AutoHotkey v2.0+
#SingleInstance Force

; ==============================================================================
; macOS-like Command Key Remapping (Alt -> Ctrl)
; ==============================================================================
; This script remaps the physical Alt key (which physically sits where the 
; Mac Command key sits) to send Ctrl combinations for common shortcuts.

global g_AltTabOpen := false

~!Tab:: {
    global g_AltTabOpen
    g_AltTabOpen := true
}
~LAlt up::
~RAlt up::
~*Esc::
~*Enter:: {
    global g_AltTabOpen
    g_AltTabOpen := false
}

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
!q:: {
    global g_AltTabOpen
    if g_AltTabOpen {
        Send "{Blind}{Delete}"
    } else {
        if WinActive("ahk_class CabinetWClass")
            Send "!{F4}"
        else
            try WinClose("A")
    }
}
!+q:: {
    try {
        if !WinExist("A")
            return
        activePid := WinGetPID("A")
        if activePid
            ProcessClose(activePid)
    }
}
!w:: {
    if WinActive("ahk_exe WindowsTerminal.exe") {
        Send "^+w"     ; Close Tab in Terminal
        return
    }

    tabbedApps := [
        "ahk_exe chrome.exe",
        "ahk_exe msedge.exe",
        "ahk_exe firefox.exe",
        "ahk_exe brave.exe",
        "ahk_exe vivaldi.exe",
        "ahk_exe opera.exe",
        "ahk_class CabinetWClass",
        "ahk_exe Code.exe",
        "ahk_exe Cursor.exe",
        "ahk_exe obsidian.exe",
        "ahk_exe notepad.exe"
    ]
    isTabbed := false
    for app in tabbedApps {
        if WinActive(app) {
            isTabbed := true
            break
        }
    }
    if isTabbed {
        Send "^w"      ; Close Tab
    } else {
        try WinClose("A")   ; Close App
    }
}
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
!/::Send "^/"      ; Comment code (Ctrl+/)

; --- Selection / Movement (macOS style) ---
; Cmd + Left/Right -> Home/End (Start/End of line)
!Left::Send "{Home}"
!Right::Send "{End}"
!+Left::Send "^+{Left}"
!+Right::Send "^+{Right}"

; Cmd + Up/Down -> Ctrl+Home/Ctrl+End (Top/Bottom of document)
!Up::Send "^{Home}"
!Down::Send "^{End}"
!+Up::Send "+^{Home}"
!+Down::Send "+^{End}"

; Cmd + Backspace -> Delete to start of line
!Backspace::Send "^{Backspace}"

; Cmd + Enter -> Send/Submit
!Enter::Send "^{Enter}"

; Alt + Left Click -> Ctrl + Left Click (e.g. open links in a new tab)
!LButton::Send "^{Click}"

; Cmd + ` -> Cycle windows of the same app (forward / backward)
!`:: CycleSameAppWindow(1)
!+`:: CycleSameAppWindow(-1)

#HotIf

CycleSameAppWindow(dir) {
    if !WinExist("A")
        return
    curHwnd := WinGetID("A")
    proc := WinGetProcessName("ahk_id " curHwnd)

    windows := []
    for hwnd in WinGetList("ahk_exe " proc) {
        if hwnd != curHwnd {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue
            if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
                continue
            cloaked := 0
            DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
            if cloaked
                continue
        }
        windows.Push(hwnd)
    }

    if windows.Length <= 1
        return

    curIdx := 0
    for i, hwnd in windows {
        if hwnd = curHwnd {
            curIdx := i
            break
        }
    }

    if !curIdx
        return

    nextIdx := Mod(curIdx - 1 + dir + windows.Length, windows.Length) + 1
    WinActivate("ahk_id " windows[nextIdx])
}