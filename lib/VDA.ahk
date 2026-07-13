#Requires AutoHotkey v2.0+

class VDA {
    static hVDA := 0
    static isLoaded := false
    
    static pGoToDesktopNumber := 0
    static pMoveWindowToDesktopNumber := 0
    static pGetCurrentDesktopNumber := 0
    static pGetWindowDesktopNumber := 0
    static pRegisterHook := 0
    static pUnregisterHook := 0
    static hookMsg := 0x1400 + 30
    static hasHookRegistered := false

    static Init() {
        global CFG_EnableVirtualDesktops
        if !IsSet(CFG_EnableVirtualDesktops) || !CFG_EnableVirtualDesktops
            return false

        vdaDll := A_ScriptDir "\VirtualDesktopAccessor.dll"
        if !FileExist(vdaDll)
            return false

        this.hVDA := DllCall("LoadLibrary", "Str", vdaDll, "Ptr")
        if !this.hVDA
            return false

        this.pGoToDesktopNumber := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "GoToDesktopNumber", "Ptr")
        this.pMoveWindowToDesktopNumber := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "MoveWindowToDesktopNumber", "Ptr")
        this.pGetCurrentDesktopNumber := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "GetCurrentDesktopNumber", "Ptr")
        this.pGetWindowDesktopNumber := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "GetWindowDesktopNumber", "Ptr")

        if (this.pGoToDesktopNumber && this.pMoveWindowToDesktopNumber && this.pGetCurrentDesktopNumber && this.pGetWindowDesktopNumber) {
            this.isLoaded := true
            
            ; Resolve register/unregister hooks
            this.pRegisterHook := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "RegisterPostMessageHook", "Ptr")
            if !this.pRegisterHook
                this.pRegisterHook := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "Registerfor_VirtualDesktopNotification", "Ptr")
            if !this.pRegisterHook
                this.pRegisterHook := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "RegisterPostHTMLNotificationMessage", "Ptr")
                
            this.pUnregisterHook := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "UnregisterPostMessageHook", "Ptr")
            if !this.pUnregisterHook
                this.pUnregisterHook := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "Unregisterfor_VirtualDesktopNotification", "Ptr")
            if !this.pUnregisterHook
                this.pUnregisterHook := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "UnregisterPostHTMLNotificationMessage", "Ptr")
                
            if this.pRegisterHook {
                DllCall(this.pRegisterHook, "Ptr", A_ScriptHwnd, "Int", this.hookMsg)
                this.hasHookRegistered := true
                OnMessage(this.hookMsg, this.OnDesktopChangeMessage)
            }
        }
        return this.isLoaded
    }

    static GoTo(desktopNum) {
        if !this.isLoaded
            return false
        DllCall(this.pGoToDesktopNumber, "Int", desktopNum - 1)
        return true
    }

    static MoveWindow(hwnd, desktopNum) {
        if !this.isLoaded
            return false
        DllCall(this.pMoveWindowToDesktopNumber, "Ptr", hwnd, "Int", desktopNum - 1)
        return true
    }

    static GetCurrent() {
        if !this.isLoaded
            return 0
        return DllCall(this.pGetCurrentDesktopNumber, "Int") + 1
    }

    static GetWindowDesktop(hwnd) {
        if !this.isLoaded
            return 0
        res := DllCall(this.pGetWindowDesktopNumber, "Ptr", hwnd, "Int")
        return (res = -1) ? 0 : res + 1
    }

    static OnDesktopChangeMessage(wParam, lParam, msg, hwnd) {
        ; wParam is the new desktop number (0-based)
        newDesktop := wParam + 1
        _HandleDesktopChangeFromMsg(newDesktop)
    }

    static Cleanup() {
        if this.isLoaded {
            if this.hasHookRegistered && this.pUnregisterHook {
                DllCall(this.pUnregisterHook, "Ptr", A_ScriptHwnd)
            }
            DllCall("FreeLibrary", "Ptr", this.hVDA)
            this.isLoaded := false
        }
    }
}
