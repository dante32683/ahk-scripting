#Requires AutoHotkey v2.0+
#SingleInstance Force

if !A_IsAdmin {
    ; Re-launch through the AutoHotkey interpreter explicitly (matching Main.ahk) rather
    ; than relying on the .ahk file association, which may be missing or point elsewhere.
    try
        Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
    catch
        Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

; ============================================================
; PROFILE RESOLUTION
; ============================================================
customDir := A_ScriptDir "\custom"
configPath := customDir "\config.ahk"
exampleConfig := A_ScriptDir "\config.example.ahk"

if !DirExist(customDir) {
    try DirCreate(customDir)
    catch as e {
        MsgBox("Error creating custom directory: " e.Message, "Setup Error", "Icon!")
        ExitApp(1)
    }
}

profile := "" ; Existing config must supply an explicit profile; never silently default.
if !FileExist(configPath) {
    if FileExist(exampleConfig) {
        r := MsgBox("custom/config.ahk not found. Configure for laptop profile? (Select 'No' for desktop profile)", "Setup Profile Selection", "YesNo Icon?")
        profile := (r = "Yes") ? "laptop" : "desktop"

        try {
            ; Build the configured content in memory, then write it atomically so a
            ; failure can never leave the destination missing (no delete-before-write).
            configContent := FileRead(exampleConfig, "UTF-8")
            configContent := StrReplace(configContent, 'global CFG_MachineProfile := "laptop"', 'global CFG_MachineProfile := "' profile '"')
            if (profile = "desktop") {
                configContent := StrReplace(configContent, 'global CFG_EnableVirtualDesktops := true', 'global CFG_EnableVirtualDesktops := false')
                configContent := StrReplace(configContent, 'global CFG_NumberKeys := "auto"', 'global CFG_NumberKeys := "monitors"')
            } else {
                configContent := StrReplace(configContent, 'global CFG_NumberKeys := "auto"', 'global CFG_NumberKeys := "desktops"')
            }
            tmpConfig := configPath "." DllCall("GetCurrentProcessId") ".tmp"
            if FileExist(tmpConfig)
                FileDelete(tmpConfig)
            FileOpen(tmpConfig, "w", "UTF-8").Write(configContent)
            if !DllCall("MoveFileExW", "Str", tmpConfig, "Str", configPath, "UInt", 9) {
                try FileDelete(tmpConfig)
                throw Error("Could not write config file (MoveFileExW failed: " A_LastError ")")
            }
            MsgBox("custom/config.ahk created and configured as '" profile "' profile. Please edit it with your personal values.", "Setup Info", "Iconi")
        } catch as e {
            MsgBox("Error copying/configuring config.example.ahk: " e.Message, "Setup Error", "Icon!")
            ExitApp(1)
        }
    } else {
        MsgBox("Error: Neither custom/config.ahk nor config.example.ahk was found. Cannot configure the script. Setup aborted.", "Setup Error", "Icon!")
        ExitApp(1)
    }
} else {
    try {
        configText := FileRead(configPath, "UTF-8")
        if RegExMatch(configText, "i)CFG_MachineProfile\s*:=\s*`"([^`"]+)`"", &m) {
            profile := m[1]
        } else {
            MsgBox("custom/config.ahk exists but has no parseable CFG_MachineProfile. Valid values are 'laptop' or 'desktop'. Setup aborted.", "Setup Error", "Icon!")
            ExitApp(1)
        }
    } catch as e {
        MsgBox("Could not read custom/config.ahk: " e.Message "`nSetup aborted.", "Setup Error", "Icon!")
        ExitApp(1)
    }
}

; Reject any profile value other than the two supported ones instead of silently
; falling back to laptop behavior for a typo'd or unrecognized profile.
if (profile != "laptop" && profile != "desktop") {
    MsgBox("Invalid CFG_MachineProfile '" profile "'. Valid values are 'laptop' or 'desktop'. Setup aborted.", "Setup Error", "Icon!")
    ExitApp(1)
}

; Check dependencies based on resolved profile
if (profile = "laptop") {
    vdaDll := A_ScriptDir "\VirtualDesktopAccessor.dll"
    if !FileExist(vdaDll) {
        MsgBox("Warning: VirtualDesktopAccessor.dll is missing from root.`n`nVirtual desktop navigation hotkeys (CapsLock+1-9 / CapsLock+Left/Right) will fall back to standard Windows shortcuts without support for moving active windows between desktops.", "Setup Warning", "Icon!")
    }
}

dbPath := A_ScriptDir "\Autocorrect_Database.txt"
if !FileExist(dbPath) {
    MsgBox("Warning: Autocorrect_Database.txt is missing from root.`n`nThe autocorrect engine will rely on the static cached lib/Autocorrect.ahk file and cannot be rebuilt.", "Setup Warning", "Icon!")
}

entryPoint := (profile = "desktop") ? "Master-PC.ahk" : "Master.ahk"

ahkExe := A_ProgramFiles "\AutoHotkey\v2\AutoHotkey64.exe"
if !FileExist(ahkExe)
    ahkExe := A_ProgramFiles "\AutoHotkey\v2\AutoHotkey.exe"
if !FileExist(ahkExe) {
    MsgBox("AutoHotkey v2 executable not found. Setup aborted.", "Setup Error", "Icon!")
    ExitApp(1)
}

scriptPath := A_ScriptDir "\" entryPoint
taskName := "AHK Master Script"

; Get current user SID via noninteractive PowerShell call
pid := DllCall("GetCurrentProcessId")
tmpSid := A_Temp "\ahk_sid_" pid "_" A_TickCount ".txt"
try FileDelete(tmpSid)
RunWait('powershell.exe -NoProfile -Command "[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value" > "' tmpSid '"', , "Hide")
raw := ""
try raw := FileRead(tmpSid)
try FileDelete(tmpSid)
userSid := Trim(raw, " `t`r`n")

if !userSid {
    MsgBox("Could not determine user SID. Aborting.", "Setup Error", "Icon!")
    ExitApp(1)
}

; XML-escape function
_XmlEscape(str) {
    str := StrReplace(str, "&", "&amp;")
    str := StrReplace(str, "<", "&lt;")
    str := StrReplace(str, ">", "&gt;")
    str := StrReplace(str, '"', "&quot;")
    str := StrReplace(str, "'", "&apos;")
    return str
}

eTaskName := _XmlEscape(taskName)
eAhkExe := _XmlEscape(ahkExe)
eScriptPath := _XmlEscape(scriptPath)
eWorkDir := _XmlEscape(A_ScriptDir)
eUserSid := _XmlEscape(userSid)

; Build the task XML (UTF-16 required by schtasks /xml)
xml := '<?xml version="1.0" encoding="UTF-16"?>'
xml .= '<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">'
xml .= '<RegistrationInfo><URI>\' eTaskName '</URI></RegistrationInfo>'
xml .= '<Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers>'
xml .= '<Principals><Principal id="Author">'
xml .= '<UserId>' eUserSid '</UserId>'
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
xml .= '<Command>' eAhkExe '</Command>'
xml .= '<Arguments>"' eScriptPath '"</Arguments>'
xml .= '<WorkingDirectory>' eWorkDir '</WorkingDirectory>'
xml .= '</Exec></Actions>'
xml .= '</Task>'

tmpXml := A_Temp "\ahk_setup_task_" pid "_" A_TickCount ".xml"
FileOpen(tmpXml, "w", "UTF-16").Write(xml)

exitCode := RunWait(A_ComSpec ' /c schtasks /create /xml "' tmpXml '" /tn "' taskName '" /f', , "Hide")
try FileDelete(tmpXml)

if exitCode = 0 {
    ; Query back task XML to verify correct registration
    tmpQuery := A_Temp "\ahk_query_" pid "_" A_TickCount ".xml"
    queryExit := RunWait(A_ComSpec ' /c schtasks /query /tn "' taskName '" /xml > "' tmpQuery '"', , "Hide")
    if queryExit != 0 {
        try FileDelete(tmpQuery)
        MsgBox("Task created but verification query failed (schtasks exit " queryExit "). The task may still be registered; please verify manually.", "Setup Warning", "Icon!")
        ExitApp(1)
    }
    queryXml := ""
    ; Read without forcing UTF-8: schtasks XML output is UTF-16/console-encoded. Letting
    ; FileRead honor the BOM avoids a false validation failure from a decode mismatch.
    try queryXml := FileRead(tmpQuery)
    try FileDelete(tmpQuery)

    if !InStr(queryXml, eAhkExe) || !InStr(queryXml, eScriptPath) || !InStr(queryXml, eWorkDir) || !InStr(queryXml, "<RunLevel>HighestAvailable</RunLevel>") {
        MsgBox("Task validation failed after creation! The registered scheduled task configuration did not match expected values.", "Setup Error", "Icon!")
        ExitApp(1)
    }
    MsgBox('Task "' taskName '" registered and validated successfully.`n`nEntry point: ' scriptPath, "Setup Complete", "Iconi")
} else {
    MsgBox("schtasks returned exit code " exitCode ". Check that you ran as admin and AutoHotkey v2 is installed.", "Setup Failed", "Icon!")
}
