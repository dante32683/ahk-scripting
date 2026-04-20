#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; DIAGNOSTIC SCRIPT: Tracks Vesktop's Window State and Virtual Desktop Assignment
; Press 'Esc' to close the script when you are done testing.
; ==============================================================================

DetectHiddenWindows True
SetTimer(UpdateTooltip, 200)

UpdateTooltip() {
    ; Load the VirtualDesktopAccessor DLL to check desktops
    static GetWindowDesktopNumber := 0
    static GetCurrentDesktopNumber := 0
    if (!GetWindowDesktopNumber) {
        hVDA := DllCall("LoadLibrary", "Str", A_ScriptDir "\VirtualDesktopAccessor.dll", "Ptr")
        if (hVDA) {
            GetWindowDesktopNumber := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetWindowDesktopNumber", "Ptr")
            GetCurrentDesktopNumber := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetCurrentDesktopNumber", "Ptr")
        }
    }

    curDesk := GetCurrentDesktopNumber ? (DllCall(GetCurrentDesktopNumber) + 1) : "?"
    text := "--- Window Tracker ---`n"
    text .= "Current Active Desktop: " curDesk "`n`n"

    found := false
    for hwnd in WinGetList("ahk_exe applemusic.exe") {
        title := WinGetTitle(hwnd)
        if (title = "")
            continue
        
        found := true
        vis := DllCall("IsWindowVisible", "Ptr", hwnd) ? "VISIBLE" : "HIDDEN"
        
        desk := "?"
        if (GetWindowDesktopNumber) {
            ; The DLL returns -1 if the window isn't assigned to a desktop. We add 1 so it matches humans (Desktop 1, 2, 3)
            deskNum := DllCall(GetWindowDesktopNumber, "Ptr", hwnd) + 1
            desk := (deskNum > 0) ? deskNum : "None/Error"
        }
        
        text .= "App: " title "`n"
        text .= "State: " vis "`n"
        text .= "Assigned Desktop: " desk "`n"
        text .= "----------------------`n"
    }

    if (!found)
        text .= "No titled Apple window found."
        
    ToolTip(text, 10, 10) ; Pin tooltip to top-left of screen
}

Esc::ExitApp()