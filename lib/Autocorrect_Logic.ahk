#Requires AutoHotkey v2.0+

global AC_LastTrigger   := ""
global AC_LastCorrection := ""
global AC_LastTypedTrigger := ""
global AC_LastTypedCorrection := ""
global AC_LastTick      := 0
global AC_LastEndChar   := ""
global AC_DisabledMap   := Map()
global AC_DisabledPath  := A_ScriptDir "\Autocorrect_Disabled.txt"

AC_EnsureDisabledMap() {
    global AC_DisabledMap
    if !IsSet(AC_DisabledMap)
        AC_DisabledMap := Map()
}

; Load persisted disabled entries into AC_DisabledMap on startup
_AC_LoadDisabled() {
    global AC_DisabledMap, AC_DisabledPath
    AC_EnsureDisabledMap()
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
    AC_EnsureDisabledMap()
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
    AC_EnsureDisabledMap()
    return AC_DisabledMap.Has(StrLower(trigger))
}

AC_Reg(trigger, correction, typedTrigger := "", typedCorrection := "") {
    global AC_LastTrigger  := trigger
    global AC_LastCorrection := correction
    global AC_LastTypedTrigger := typedTrigger != "" ? typedTrigger : trigger
    global AC_LastTypedCorrection := typedCorrection != "" ? typedCorrection : correction
    global AC_LastTick     := A_TickCount
    global AC_LastEndChar  := A_EndChar
}

AC_ClearLastCorrection(*) {
    global AC_LastTrigger := ""
    global AC_LastCorrection := ""
    global AC_LastTypedTrigger := ""
    global AC_LastTypedCorrection := ""
    global AC_LastEndChar := ""
}

AC_ClearLastCorrectionOnUserKey(*) {
    global AC_LastTrigger, AC_LastTick
    if AC_LastTrigger = ""
        return
    if GetKeyState("CapsLock", "P") && GetKeyState("Alt", "P")
        return
    if A_TickCount - AC_LastTick < 250
        return
    AC_ClearLastCorrection()
}

#HotIf CFG_Autocorrect

; Clear last trigger if the user clicks away
~*LButton::
~*RButton::
~*MButton:: {
    AC_ClearLastCorrection()
}

~*0::
~*1::
~*2::
~*3::
~*4::
~*5::
~*6::
~*7::
~*8::
~*9::
~*a::
~*b::
~*c::
~*d::
~*e::
~*f::
~*g::
~*h::
~*i::
~*j::
~*k::
~*l::
~*m::
~*n::
~*o::
~*p::
~*q::
~*r::
~*s::
~*t::
~*u::
~*v::
~*w::
~*x::
~*y::
~*z::
~*Space::
~*Enter::
~*Tab::
~*Backspace::
~*Delete::
~*Left::
~*Right::
~*Up::
~*Down:: AC_ClearLastCorrectionOnUserKey()

; Reset hotstring recognizer on text mutation shortcuts to prevent buffer desync
~^Backspace::
~^Delete::
~^z::
~^y::
~^x::
~^v::
~^a:: {
    Hotstring("Reset")
}
#HotIf

#HotIf GetKeyState("CapsLock", "P") && GetKeyState("Alt", "P")

; Permanently disable last autocorrect (CapsLock+Alt+Backspace)
*Backspace:: {
    global AC_LastTrigger, AC_LastCorrection, AC_LastTypedTrigger, AC_LastTypedCorrection, AC_DisabledMap, AC_LastTick, AC_LastEndChar
    AC_EnsureDisabledMap()

    ; Only allow disabling if the correction happened recently (within 15 seconds)
    ; to prevent accidentally disabling a correction from a long time ago.
    if (AC_LastTrigger != "" && A_TickCount - AC_LastTick < 15000) {
        AC_DisabledMap[StrLower(AC_LastTrigger)] := AC_LastTrigger "->" AC_LastCorrection
        AC_SaveDisabled()

        Send("{Backspace " (StrLen(AC_LastTypedCorrection) + StrLen(AC_LastEndChar)) "}")
        SendText(AC_LastTypedTrigger . AC_LastEndChar)

        ShowOSD("Autocorrect disabled: " AC_LastTrigger)

        AC_ClearLastCorrection()
    }
}

; Open disabled list in default text editor (CapsLock+Alt+D)
*d:: {
    global AC_DisabledPath
    if !FileExist(AC_DisabledPath)
        FileAppend("", AC_DisabledPath, "UTF-8")
    Run('"' AC_DisabledPath '"')
    ShowOSD("Autocorrect_Disabled.txt opened")
}

#HotIf
