#Requires AutoHotkey v2.0+
#SingleInstance Force
#WinActivateForce

#Include config.ahk
#Include lib/Eye202020.ahk
#Include lib/Core_FancyZone.ahk
; #Include lib/Core_Native.ahk
#Include Remap.ahk

; WMI pre-init for camera toggle
global WMI_Service := 0
try {
    WMI_Service := ComObjGet("winmgmts:")
} catch {
    ShowOSD("Warning: WMI init failed. Camera toggle may not work.", 3000)
}

_202020_Init()

; ============================================================
; LAPTOP-SPECIFIC HYPER LAYER EXTENSIONS
; ============================================================
#HotIf GetKeyState("CapsLock", "P")

; Virtual desktop switching
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

1:: GotoDesktop(1)
2:: GotoDesktop(2)
3:: GotoDesktop(3)
4:: GotoDesktop(4)
5:: GotoDesktop(5)
6:: GotoDesktop(6)
7:: GotoDesktop(7)
8:: GotoDesktop(8)
9:: GotoDesktop(9)

*!1:: MoveToDesktop(1)
*!2:: MoveToDesktop(2)
*!3:: MoveToDesktop(3)
*!4:: MoveToDesktop(4)
*!5:: MoveToDesktop(5)
*!6:: MoveToDesktop(6)
*!7:: MoveToDesktop(7)
*!8:: MoveToDesktop(8)
*!9:: MoveToDesktop(9)

; Tailscale task toggle (CapsLock + \)
*\:: {
    try {
        service := ComObject("Schedule.Service")
        service.Connect()
        folder := service.GetFolder("\")
        task := folder.GetTask("Tailscale Auto Switch")

        if (task.Enabled) {
            task.Enabled := false
            if ProcessExist("v2rayN.exe")
                RunWait("taskkill.exe /F /IM v2rayN.exe /T", , "Hide")
            ShowOSD("VPN Auto-Switch: OFF", 2000)
        } else {
            task.Enabled := true
            ShowOSD("VPN Auto-Switch: ON", 2000)
        }
    } catch Error as err {
        ShowOSD("VPN Toggle Error: " err.Message, 3000)
    }
}

#HotIf

; ============================================================
; CAMERA TOGGLE — Copilot key (#+F23)
; ============================================================
#+F23:: {
    global CFG_CameraID, PnPUtilPath, WMI_Service

    if !WMI_Service {
        ShowOSD("WMI not initialized — check script start!")
        return
    }

    ShowOSD("Toggling Camera...", 0)
    exitCode := 1

    ; Re-query current device state from WMI each time — avoids stale cache
    currentlyOn := false
    try {
        escapedID := StrReplace(CFG_CameraID, "\", "\\")
        query := WMI_Service.ExecQuery("SELECT ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PNPDeviceID = '" escapedID "'")
        for device in query {
            currentlyOn := (device.ConfigManagerErrorCode = 0)
        }
        device := ""
        query := ""
    }

    try {
        tempFile := A_Temp "\camera_toggle_error.txt"
        if FileExist(tempFile)
            FileDelete(tempFile)

        if currentlyOn {
            exitCode := RunWait(A_ComSpec ' /c ""' PnPUtilPath '" /disable-device "' CFG_CameraID '" > "' tempFile '" 2>&1"', , "Hide")
            if (exitCode != 0) {
                psCmd := "Disable-PnpDevice -InstanceId '" CFG_CameraID "' -Confirm:$false -ErrorAction Stop"
                exitCode := RunWait(A_ComSpec ' /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' psCmd '" >> "' tempFile '" 2>&1', , "Hide")
            }
            if (exitCode = 0)
                ShowOSD("RGB Camera Disabled")
        } else {
            exitCode := RunWait(A_ComSpec ' /c ""' PnPUtilPath '" /enable-device "' CFG_CameraID '" > "' tempFile '" 2>&1"', , "Hide")
            if (exitCode != 0) {
                psCmd := "Enable-PnpDevice -InstanceId '" CFG_CameraID "' -Confirm:$false -ErrorAction Stop"
                exitCode := RunWait(A_ComSpec ' /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' psCmd '" >> "' tempFile '" 2>&1', , "Hide")
            }
            if (exitCode = 0)
                ShowOSD("RGB Camera Enabled")
        }
    } catch Error as err {
        ShowOSD("Execution Error: " err.Message, 3000)
        return
    }

    if (exitCode != 0) {
        errStr := ""
        if FileExist(tempFile) {
            errText := FileRead(tempFile)
            if InStr(errText, "pending system reboot") {
                errStr := "Device is locked. A system reboot is required."
            } else {
                errText := StrReplace(errText, "Microsoft PnP Utility", "")
                errText := RegExReplace(errText, "s)^[\s\r\n]+", "")
                errText := StrReplace(errText, "`r`n", " ")
                errStr := Trim(errText)
                if (StrLen(errStr) > 80)
                    errStr := SubStr(errStr, 1, 80) "..."
            }
        }
        ShowOSD("Failed (Code " exitCode "): " errStr, 5000)
    }
}

