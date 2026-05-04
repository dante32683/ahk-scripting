#Requires AutoHotkey v2.0+

global AC_LastTrigger   := ""
global AC_LastCorrection := ""
global AC_LastTick      := 0
global AC_DisabledMap   := Map()
global AC_DisabledPath  := A_ScriptDir "\Autocorrect_Disabled.txt"

; Load persisted disabled entries into AC_DisabledMap on startup
_AC_LoadDisabled() {
    global AC_DisabledMap, AC_DisabledPath
    if !FileExist(AC_DisabledPath)
        return
    try {
        loop parse, FileRead(AC_DisabledPath, "UTF-8"), "`n", "`r" {
            line := Trim(A_LoopField)
            if (line = "")
                continue
            arrowPos := InStr(line, "->")
            trigger  := arrowPos ? Trim(SubStr(line, 1, arrowPos - 1)) : line
            if (trigger != "")
                AC_DisabledMap[StrLower(trigger)] := line  ; value = "trigger->correction" for re-saving
        }
    }
}

; Persist AC_DisabledMap to file, sorted alphabetically
AC_SaveDisabled() {
    global AC_DisabledMap, AC_DisabledPath
    lines := ""
    for , entry in AC_DisabledMap
        lines .= entry "`n"
    lines := Sort(RTrim(lines, "`n"))
    try {
        if FileExist(AC_DisabledPath)
            FileDelete(AC_DisabledPath)
        if (lines != "")
            FileAppend(lines "`n", AC_DisabledPath, "UTF-8")
    } catch as e {
        MsgBox("Error saving disabled list: " e.Message)
    }
}

_AC_LoadDisabled()

AC_IsDisabled(trigger) {
    global AC_DisabledMap
    return AC_DisabledMap.Has(StrLower(trigger))
}

AC_Reg(trigger, correction) {
    global AC_LastTrigger  := trigger
    global AC_LastCorrection := correction
    global AC_LastTick     := A_TickCount
}

#HotIf CFG_Autocorrect

; Clear last trigger if the user clicks away
~*LButton::
~*RButton::
~*MButton:: {
    global AC_LastTrigger := ""
}
#HotIf

#HotIf GetKeyState("CapsLock", "P") && GetKeyState("Alt", "P")

; Permanently disable last autocorrect (CapsLock+Alt+Backspace)
*Backspace:: {
    global AC_LastTrigger, AC_LastCorrection, AC_DisabledMap, AC_LastTick
    
    ; Only allow disabling if the correction happened recently (within 15 seconds)
    ; to prevent accidentally disabling a correction from a long time ago.
    if (AC_LastTrigger != "" && A_TickCount - AC_LastTick < 15000) {
        AC_DisabledMap[StrLower(AC_LastTrigger)] := AC_LastTrigger "->" AC_LastCorrection
        AC_SaveDisabled()

        Send("{Backspace " StrLen(AC_LastCorrection) "}")
        SendText(AC_LastTrigger . A_EndChar)

        if IsSet(ShowOSD)
            ShowOSD("Autocorrect disabled: " AC_LastTrigger)

        AC_LastTrigger := ""
    }
}

; Open disabled list in default text editor (CapsLock+Alt+D)
*d:: {
    global AC_DisabledPath
    if !FileExist(AC_DisabledPath)
        FileAppend("", AC_DisabledPath, "UTF-8")
    Run('"' AC_DisabledPath '"')
    if IsSet(ShowOSD)
        ShowOSD("Autocorrect_Disabled.txt opened")
}

#HotIf
