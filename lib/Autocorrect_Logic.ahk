#Requires AutoHotkey v2.0+

global AC_LastTrigger   := ""
global AC_LastCorrection := ""
global AC_LastTypedTrigger := ""
global AC_LastTypedCorrection := ""
global AC_LastTick      := 0
global AC_LastEndChar   := ""
global AC_TempSuppressed := Map()

_AC_IsNonTextArea() {
    if !WinExist("A")
        return false
    try {
        className := WinGetClass("A")
        procName := WinGetProcessName("A")
        
        if (className = "VirtualConsoleClass" || className = "ConsoleWindowClass" || className = "TermWindow")
            return true
            
        if (procName = "cmd.exe" || procName = "powershell.exe" || procName = "wsl.exe" || procName = "WindowsTerminal.exe")
            return true
            
        style := WinGetStyle("A")
        if !(style & 0xC00000) { ; No WS_CAPTION
            if IsSet(CFG_GameProcesses) {
                for game in CFG_GameProcesses {
                    if (procName = game)
                        return true
                }
            }
        }
    }
    return false
}

AC_Proc(canonicalTrig, canonicalCorr, typedTrig, typedCorr) {
    if _AC_IsNonTextArea() {
        SendText(typedTrig . A_EndChar)
        return
    }
    if AC_IsDisabled(canonicalTrig) {
        SendText(typedTrig . A_EndChar)
        return
    }
    global AC_TempSuppressed
    if AC_TempSuppressed.Has(StrLower(canonicalTrig)) {
        if A_TickCount - AC_TempSuppressed[StrLower(canonicalTrig)] < 2000 {
            SendText(typedTrig . A_EndChar)
            return
        }
        AC_TempSuppressed.Delete(StrLower(canonicalTrig))
    }
    SendText(typedCorr . A_EndChar)
    AC_Reg(canonicalTrig, canonicalCorr, typedTrig, typedCorr)
}

AC_IsDisabled(trigger) {
    global g_StateAutocorrectDisabled
    return g_StateAutocorrectDisabled.Has(StrLower(trigger))
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
    global AC_LastTrigger, AC_LastCorrection, AC_LastTypedTrigger, AC_LastTypedCorrection, AC_LastTick, AC_LastEndChar
    global g_StateAutocorrectDisabled

    if (AC_LastTrigger != "" && A_TickCount - AC_LastTick < 15000) {
        g_StateAutocorrectDisabled[StrLower(AC_LastTrigger)] := AC_LastTrigger "->" AC_LastCorrection
        State_MarkDirty("autocorrect")
        global AC_TempSuppressed
        AC_TempSuppressed[StrLower(AC_LastTrigger)] := A_TickCount

        Send("{Backspace " (StrLen(AC_LastTypedCorrection) + StrLen(AC_LastEndChar)) "}")
        SendText(AC_LastTypedTrigger . AC_LastEndChar)

        ShowOSD("Autocorrect disabled: " AC_LastTrigger)

        AC_ClearLastCorrection()
    }
}

; Open disabled list in default text editor (CapsLock+Alt+D)
*d:: {
    global g_StateDir
    disabledFile := g_StateDir "\autocorrect-disabled.txt"
    if !FileExist(disabledFile)
        FileAppend("", disabledFile, "UTF-8")
    Run('"' disabledFile '"')
    ShowOSD("autocorrect-disabled.txt opened")
}

#HotIf
