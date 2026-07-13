#Requires AutoHotkey v2.0+
#SingleInstance Force
#WinActivateForce

global g_PerfStartupTick
if !IsSet(g_PerfStartupTick)
    global g_PerfStartupTick := A_TickCount

; Include config
#Include custom/config.ahk

; Resolve profile variables
global CFG_MachineProfile
global CFG_EnableVirtualDesktops
global CFG_NumberKeys

; Determine effective profile
global APP_Profile := "laptop" ; Default
if IsSet(APP_ProfileOverride) && APP_ProfileOverride != "" {
    APP_Profile := APP_ProfileOverride
} else if IsSet(CFG_MachineProfile) {
    APP_Profile := CFG_MachineProfile
}

if (APP_Profile != "laptop" && APP_Profile != "desktop") {
    MsgBox("Invalid profile: '" APP_Profile "'. Valid values are 'laptop' or 'desktop'.", "Startup Error", "Icon!")
    ExitApp(1)
}

; Set defaults based on profile
if !IsSet(CFG_EnableVirtualDesktops) {
    global CFG_EnableVirtualDesktops := (APP_Profile = "laptop")
}

if !IsSet(CFG_NumberKeys) || CFG_NumberKeys = "auto" {
    global CFG_NumberKeys := (APP_Profile = "laptop") ? "desktops" : "monitors"
}

if (CFG_NumberKeys != "desktops" && CFG_NumberKeys != "monitors") {
    MsgBox("Invalid CFG_NumberKeys: '" CFG_NumberKeys "'. Valid values are 'desktops', 'monitors' or 'auto'.", "Startup Error", "Icon!")
    ExitApp(1)
}

; Performance settings
global CFG_TestMode := (IsSet(CFG_TestMode) && CFG_TestMode) || (EnvGet("AHK_TEST_MODE") = "1")
if !CFG_TestMode {
    ListLines false
    KeyHistory IsSet(CFG_DebugKeyHistory) && CFG_DebugKeyHistory ? 15 : 0
    SetWinDelay 0
    ProcessSetPriority(IsSet(CFG_ProcessPriority) ? CFG_ProcessPriority : "AboveNormal")
    SetTitleMatchMode 2
    InstallKeybdHook()
}

; Include shared modules
#Include lib/Core.ahk
#Include *i custom/Core_custom.ahk
#Include Remap.ahk
#Include lib/Autocorrect_Logic.ahk
#Include lib/Build_Autocorrect.ahk
#Include *i lib/Autocorrect.ahk

; ============================================================
; PROFILE-SPECIFIC HOTKEYS
; ============================================================

#HotIf GetKeyState("CapsLock", "P") && APP_Profile = "laptop"

; Laptop Virtual desktop switching
Left:: {
    if GetCurrentDesktopNumber
        GotoDesktop(Max(1, DllCall(GetCurrentDesktopNumber)))
    else
        Send "^#{Left}"
}
Right:: {
    if GetCurrentDesktopNumber
        GotoDesktop(Min(9, DllCall(GetCurrentDesktopNumber) + 2))
    else
        Send "^#{Right}"
}

#HotIf GetKeyState("CapsLock", "P") && APP_Profile = "desktop"

; PC Monitor focus switching
Left:: {
    monitorCount := MonitorGetCount()
    currentMonitorIndex := 1
    if WinExist("A") {
        WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "A")
        centerX := windowX + windowWidth // 2, centerY := windowY + windowHeight // 2
        loop monitorCount {
            MonitorGetWorkArea(A_Index, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom)
            if centerX >= monitorLeft && centerX < monitorRight && centerY >= monitorTop && centerY < monitorBottom {
                currentMonitorIndex := A_Index
                break
            }
        }
    }
    _FocusMonitor(Mod(currentMonitorIndex - 2 + monitorCount, monitorCount) + 1)
}

Right:: {
    monitorCount := MonitorGetCount()
    currentMonitorIndex := 1
    if WinExist("A") {
        WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "A")
        centerX := windowX + windowWidth // 2, centerY := windowY + windowHeight // 2
        loop monitorCount {
            MonitorGetWorkArea(A_Index, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom)
            if centerX >= monitorLeft && centerX < monitorRight && centerY >= monitorTop && centerY < monitorBottom {
                currentMonitorIndex := A_Index
                break
            }
        }
    }
    _FocusMonitor(Mod(currentMonitorIndex, monitorCount) + 1)
}

#HotIf

; Profile-specific customization files
if (APP_Profile = "laptop") {
    #Include *i custom/Master_custom.ahk
} else {
    #Include *i custom/Master-PC_custom.ahk
}

; Telemetry and initialization complete
Perf_Log("init_complete", A_TickCount - g_PerfStartupTick)

if !CFG_TestMode {
    ShowOSD("Script started!")
} else {
    ExitApp(0)
}
