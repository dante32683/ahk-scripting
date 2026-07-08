#Requires AutoHotkey v2.0+
#SingleInstance Force

if !A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

; ============================================================
; HEALTH VALIDATION CHECKS
; ============================================================
configPath := A_ScriptDir "\config.ahk"
if !FileExist(configPath) {
    exampleConfig := A_ScriptDir "\config.example.ahk"
    if FileExist(exampleConfig) {
        r := MsgBox("config.ahk not found. Copy config.example.ahk to config.ahk?", "Setup Check", "YesNo Icon?")
        if r = "Yes" {
            FileCopy(exampleConfig, configPath)
            MsgBox("config.ahk created. Please edit it with your personal values.", "Setup Info", "Iconi")
        }
    } else {
        MsgBox("Warning: Neither config.ahk nor config.example.ahk was found.", "Setup Warning", "Icon!")
    }
}

vdaDll := A_ScriptDir "\VirtualDesktopAccessor.dll"
if !FileExist(vdaDll) {
    MsgBox("Warning: VirtualDesktopAccessor.dll is missing from root.`n`nVirtual desktop navigation hotkeys (CapsLock+1-9 / CapsLock+Left/Right) will fall back to standard Windows shortcuts without support for moving active windows between desktops.", "Setup Warning", "Icon!")
}

dbPath := A_ScriptDir "\Autocorrect_Database.txt"
if !FileExist(dbPath) {
    MsgBox("Warning: Autocorrect_Database.txt is missing from root.`n`nThe autocorrect engine will rely on the static cached lib/Autocorrect.ahk file and cannot be rebuilt.", "Setup Warning", "Icon!")
}

; Choose entry point.

; If you want deterministic behavior across machines, set a machine flag in config.ahk
; and use it here instead of A_ComputerName.
entryPoint := FileExist(A_ScriptDir "\Master-PC.ahk") && (A_ComputerName = "DESKTOP-PC")
    ? "Master-PC.ahk"
    : "Master.ahk"

ahkExe := A_ProgramFiles "\AutoHotkey\v2\AutoHotkey64.exe"
if !FileExist(ahkExe)
    ahkExe := A_ProgramFiles "\AutoHotkey\v2\AutoHotkey.exe"

scriptPath := A_ScriptDir "\" entryPoint
taskName := "AHK Master Script"

; Get current user SID
tmpSid := A_Temp "\ahk_sid.txt"
try FileDelete(tmpSid)
RunWait(A_ComSpec ' /c wmic useraccount where name="' A_UserName '" get sid /value > "' tmpSid '"', , "Hide")
raw := ""
try raw := FileRead(tmpSid)
userSid := ""
if RegExMatch(raw, "SID=(\S+)", &m)
    userSid := Trim(m[1])
try FileDelete(tmpSid)

if !userSid {
    MsgBox("Could not determine user SID. Aborting.", "Setup Error", "Icon!")
    ExitApp()
}

; Build the task XML (UTF-16 required by schtasks /xml)
xml := '<?xml version="1.0" encoding="UTF-16"?>'
xml .= '<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">'
xml .= '<RegistrationInfo><URI>\' taskName '</URI></RegistrationInfo>'
xml .= '<Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers>'
xml .= '<Principals><Principal id="Author">'
xml .= '<UserId>' userSid '</UserId>'
xml .= '<LogonType>InteractiveToken</LogonType>'
xml .= '<RunLevel>HighestAvailable</RunLevel>'
xml .= '</Principal></Principals>'
xml .= '<Settings>'
xml .= '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>'
xml .= '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>'
xml .= '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>'
xml .= '<AllowHardTerminate>true</AllowHardTerminate>'
xml .= '<StartWhenAvailable>true</StartWhenAvailable>'
xml .= '<Enabled>true</Enabled>'
xml .= '<RestartOnFailure><Interval>PT1M</Interval><Count>3</Count></RestartOnFailure>'
xml .= '</Settings>'
xml .= '<Actions Context="Author"><Exec>'
xml .= '<Command>"' ahkExe '"</Command>'
xml .= '<Arguments>"' scriptPath '"</Arguments>'
xml .= '</Exec></Actions>'
xml .= '</Task>'

tmpXml := A_Temp "\ahk_setup_task.xml"
FileOpen(tmpXml, "w", "UTF-16").Write(xml)

exitCode := RunWait(A_ComSpec ' /c schtasks /create /xml "' tmpXml '" /tn "' taskName '" /f', , "Hide")
try FileDelete(tmpXml)

if exitCode = 0
    MsgBox('Task "' taskName '" registered successfully.`n`nEntry point: ' scriptPath, "Setup Complete", "Iconi")
else
    MsgBox("schtasks returned exit code " exitCode ". Check that you ran as admin and AutoHotkey v2 is installed.", "Setup Failed", "Icon!")

