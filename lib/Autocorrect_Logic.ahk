#Requires AutoHotkey v2.0+

global AC_LastTrigger   := ""
global AC_LastCorrection := ""
global AC_LastTypedTrigger := ""
global AC_LastTypedCorrection := ""
global AC_LastTick      := 0
global AC_LastEndChar   := ""
global AC_LastHwnd      := 0
global AC_Generation    := 0
global AC_HadSubsequentInput := false
global AC_TempSuppressed := Map()
global AC_InputHook := 0
global AC_HookGeneration := 0

_AC_IsNonTextArea() {
    if !WinExist("A")
        return false
    try {
        className := WinGetClass("A")
        procName := WinGetProcessName("A")

        if (className = "VirtualConsoleClass" || className = "ConsoleWindowClass" || className = "TermWindow")
            return true

        if (procName = "cmd.exe" || procName = "powershell.exe" || procName = "pwsh.exe" || procName = "wsl.exe" || procName = "WindowsTerminal.exe")
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
    AC_StartInputHook()
}

AC_IsDisabled(trigger) {
    global g_StateAutocorrectDisabled
    return g_StateAutocorrectDisabled.Has(StrLower(trigger))
}

AC_Reg(trigger, correction, typedTrigger := "", typedCorrection := "") {
    global AC_LastTrigger, AC_LastCorrection, AC_LastTypedTrigger, AC_LastTypedCorrection
    global AC_LastTick, AC_LastEndChar, AC_LastHwnd, AC_Generation, AC_HadSubsequentInput
    AC_LastTrigger := trigger
    AC_LastCorrection := correction
    AC_LastTypedTrigger := typedTrigger != "" ? typedTrigger : trigger
    AC_LastTypedCorrection := typedCorrection != "" ? typedCorrection : correction
    AC_LastTick := A_TickCount
    AC_LastEndChar := A_EndChar
    AC_HadSubsequentInput := false
    try AC_LastHwnd := WinExist("A")
    catch
        AC_LastHwnd := 0
    AC_Generation += 1
}

AC_ClearLastCorrection(*) {
    global AC_LastTrigger, AC_LastCorrection, AC_LastTypedTrigger, AC_LastTypedCorrection
    global AC_LastEndChar, AC_LastHwnd, AC_HadSubsequentInput
    AC_LastTrigger := ""
    AC_LastCorrection := ""
    AC_LastTypedTrigger := ""
    AC_LastTypedCorrection := ""
    AC_LastEndChar := ""
    AC_LastHwnd := 0
    AC_HadSubsequentInput := false
    AC_StopInputHook()
}

AC_OnFocusChanged(hwnd) {
    global AC_LastHwnd, AC_LastTrigger
    if AC_LastTrigger = ""
        return
    if hwnd != AC_LastHwnd
        AC_ClearLastCorrection()
}

AC_StartInputHook() {
    global AC_InputHook, AC_HookGeneration, AC_Generation, CFG_TestMode
    if IsSet(CFG_TestMode) && CFG_TestMode
        return
    AC_StopInputHook()
    startingGeneration := AC_Generation
    AC_HookGeneration := startingGeneration
    hookObj := InputHook("V L0 I1 T15")
    hookObj.KeyOpt("{All}", "N")
    ; Ignore pure modifiers so they don't clear undo state alone
    for modifierKey in ["LCtrl", "RCtrl", "LShift", "RShift", "LAlt", "RAlt", "LWin", "RWin", "CapsLock"]
        hookObj.KeyOpt("{" modifierKey "}", "-N")
    ; Bind the originating generation into the callbacks. A stale hook whose OnEnd
    ; fires after a newer correction started must NOT clear the newer state, and it
    ; can only be recognized as stale by comparing its own captured generation — not
    ; the mutable global AC_HookGeneration, which the newer hook already overwrote.
    hookObj.OnKeyDown := AC_OnHookKey.Bind(startingGeneration)
    hookObj.OnEnd := AC_OnHookEnd.Bind(startingGeneration)
    AC_InputHook := hookObj
    hookObj.Start()
}

AC_StopInputHook() {
    global AC_InputHook
    if AC_InputHook {
        try AC_InputHook.Stop()
        AC_InputHook := 0
    }
}

AC_OnHookKey(boundGeneration, inputHook, virtualKeyCode, scanCode) {
    global AC_HadSubsequentInput, AC_Generation
    if boundGeneration != AC_Generation
        return
    ; Exception: the disable shortcut is CapsLock+Alt+Backspace. When the user is
    ; pressing exactly that chord, the Backspace keydown must NOT clear the pending
    ; correction — otherwise AC_LastTrigger is gone before the *Backspace disable
    ; hotkey runs and the disable silently no-ops.
    if virtualKeyCode = 0x08 && GetKeyState("CapsLock", "P")
        && (GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P"))
        return
    AC_HadSubsequentInput := true
    AC_ClearLastCorrection()
}

AC_OnHookEnd(boundGeneration, inputHook) {
    global AC_Generation, AC_InputHook
    if boundGeneration != AC_Generation
        return
    AC_InputHook := 0
    AC_ClearLastCorrection()
}

#HotIf CFG_Autocorrect

~*LButton::
~*RButton::
~*MButton::
~*XButton1::
~*XButton2:: {
    AC_ClearLastCorrection()
}

; Reset hotstring recognizer on text mutation shortcuts to prevent buffer desync
~^Backspace::
~^Delete::
~^z::
~^y::
~^x::
~^v::
~^a:: {
    Hotstring("Reset")
    AC_ClearLastCorrection()
}
#HotIf

#HotIf GetKeyState("CapsLock", "P") && GetKeyState("Alt", "P")

*Backspace:: {
    global AC_LastTrigger, AC_LastCorrection, AC_LastTypedTrigger, AC_LastTypedCorrection
    global AC_LastTick, AC_LastEndChar, AC_LastHwnd, AC_Generation, AC_HadSubsequentInput
    global g_StateAutocorrectDisabled, AC_TempSuppressed

    if AC_LastTrigger = "" || AC_HadSubsequentInput
        return
    if A_TickCount - AC_LastTick >= 15000
        return
    try {
        if WinExist("A") && WinGetID("A") != AC_LastHwnd
            return
    } catch {
        return
    }

    g_StateAutocorrectDisabled[StrLower(AC_LastTrigger)] := AC_LastTrigger "->" AC_LastCorrection
    State_MarkDirty("autocorrect")
    AC_TempSuppressed[StrLower(AC_LastTrigger)] := A_TickCount

    Send("{Backspace " (StrLen(AC_LastTypedCorrection) + StrLen(AC_LastEndChar)) "}")
    SendText(AC_LastTypedTrigger . AC_LastEndChar)
    ShowOSD("Autocorrect disabled: " AC_LastTrigger)
    AC_ClearLastCorrection()
}

*d:: {
    global g_StateDir
    disabledFile := g_StateDir "\autocorrect-disabled.txt"
    if !FileExist(disabledFile)
        FileAppend("", disabledFile, "UTF-8")
    Run('"' disabledFile '"')
    ShowOSD("autocorrect-disabled.txt opened")
}

#HotIf
