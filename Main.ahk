#Requires AutoHotkey v2.0+
#WinActivateForce

global g_PerfStartupTick
if !IsSet(g_PerfStartupTick)
    global g_PerfStartupTick := A_TickCount

; Include config
#Include *i custom/config.ahk

; Resolve profile variables
global CFG_MachineProfile
global CFG_EnableVirtualDesktops
global CFG_NumberKeys
global CFG_TestMode := (IsSet(CFG_TestMode) && CFG_TestMode) || (EnvGet("AHK_TEST_MODE") = "1")

#Include lib/Config.ahk

; Determine effective profile through the pure resolver (unit-tested in test_config.ahk)
global APP_Profile := Config_ResolveProfile(
    IsSet(APP_ProfileOverride) ? APP_ProfileOverride : "",
    IsSet(CFG_MachineProfile) ? CFG_MachineProfile : "")

if APP_Profile = "" {
    bad := IsSet(APP_ProfileOverride) && APP_ProfileOverride != "" ? APP_ProfileOverride
        : (IsSet(CFG_MachineProfile) ? CFG_MachineProfile : "")
    MsgBox("Invalid profile: '" bad "'. Valid values are 'laptop' or 'desktop'.", "Startup Error", "Icon!")
    ExitApp(1)
}

; Set defaults based on profile
global CFG_EnableVirtualDesktops := Config_ResolveEnableVirtualDesktops(
    APP_Profile, IsSet(CFG_EnableVirtualDesktops) ? CFG_EnableVirtualDesktops : "")

global CFG_NumberKeys := Config_ResolveNumberKeys(
    APP_Profile, IsSet(CFG_NumberKeys) ? CFG_NumberKeys : "")

if CFG_NumberKeys = "" {
    MsgBox("Invalid CFG_NumberKeys. Valid values are 'desktops', 'monitors' or 'auto'.", "Startup Error", "Icon!")
    ExitApp(1)
}

; Elevation (skipped in test mode)
if !CFG_TestMode && !A_IsAdmin {
    try {
        Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"')
    } catch {
        Run('*RunAs "' A_ScriptFullPath '"')
    }
    ExitApp()
}

; Performance settings
if !CFG_TestMode {
    ListLines false
    KeyHistory IsSet(CFG_DebugKeyHistory) && CFG_DebugKeyHistory ? 15 : 0
    SetWinDelay 0
    ProcessSetPriority(IsSet(CFG_ProcessPriority) ? CFG_ProcessPriority : "AboveNormal")
    SetTitleMatchMode 2
    InstallKeybdHook()
}

; Include shared modules (definitions only; no subsystem side effects yet)
#Include lib/Core.ahk
#Include *i custom/Core_custom.ahk
#Include Remap.ahk
#Include lib/Autocorrect_Logic.ahk

; Ordered initialization
Perf_Init()
State_Init()
VDA.Init()
Core_SessionInit()
WindowEvents_Init()

; Autocorrect: rebuild first if needed, then include generated hotstrings
#Include lib/Build_Autocorrect.ahk
if (IsSet(CFG_Autocorrect) && CFG_Autocorrect && !CFG_TestMode) {
    if BuildAutocorrect()
        SafeReload()
}
#Include *i lib/Autocorrect.ahk
; ============================================================
; PROFILE-SPECIFIC HOTKEYS
; ============================================================

#HotIf GetKeyState("CapsLock", "P") && APP_Profile = "laptop"

Left:: {
    if VDA.isLoaded {
        cur := VDA.GetCurrent()
        if cur != VDA.DESKTOP_UNKNOWN
            GotoDesktop(Max(1, cur - 1))
        else
            Send "^#{Left}"
    } else
        Send "^#{Left}"
}
Right:: {
    if VDA.isLoaded {
        cur := VDA.GetCurrent()
        count := VDA.GetDesktopCount()
        if cur != VDA.DESKTOP_UNKNOWN
            ; Clamp to the real desktop count when known; otherwise advance by one
            ; and let VDA.GoTo reject an out-of-range target.
            GotoDesktop(count > 0 ? Min(count, cur + 1) : cur + 1)
        else
            Send "^#{Right}"
    } else
        Send "^#{Right}"
}

#HotIf GetKeyState("CapsLock", "P") && APP_Profile = "desktop"

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

; Telemetry and initialization complete
OnExit(App_Shutdown)
Perf_Log("init_complete", A_TickCount - g_PerfStartupTick)

if !CFG_TestMode {
    ShowOSD("Script started!")
} else {
    ExitApp(0)
}
