#Requires AutoHotkey v2.0+

class VDA {
    static hVDA := 0
    static isLoaded := false

    static pGoToDesktopNumber := 0
    static pMoveWindowToDesktopNumber := 0
    static pGetCurrentDesktopNumber := 0
    static pGetWindowDesktopNumber := 0
    static pGetDesktopCount := 0
    static pIsPinnedWindow := 0
    static pIsWindowOnCurrentVirtualDesktop := 0
    static pRegisterHook := 0
    static pUnregisterHook := 0
    static hookMsg := 0x1400 + 30
    static hasHookRegistered := false
    static msgCallback := 0  ; exact bound object registered with OnMessage (needed to unregister)

    ; Sentinel: unknown/error desktop (never treat as pinned)
    static DESKTOP_UNKNOWN := -1

    static Init() {
        global CFG_EnableVirtualDesktops, CFG_TestMode
        if IsSet(CFG_TestMode) && CFG_TestMode
            return false
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
        this.pGetDesktopCount := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "GetDesktopCount", "Ptr")
        this.pIsPinnedWindow := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "IsPinnedWindow", "Ptr")
        this.pIsWindowOnCurrentVirtualDesktop := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "IsWindowOnCurrentVirtualDesktop", "Ptr")
        this.pRegisterHook := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "RegisterPostMessageHook", "Ptr")
        this.pUnregisterHook := DllCall("GetProcAddress", "Ptr", this.hVDA, "AStr", "UnregisterPostMessageHook", "Ptr")

        if !(this.pGoToDesktopNumber && this.pMoveWindowToDesktopNumber && this.pGetCurrentDesktopNumber && this.pGetWindowDesktopNumber) {
            DllCall("FreeLibrary", "Ptr", this.hVDA)
            this.hVDA := 0
            return false
        }

        this.isLoaded := true

        if this.pRegisterHook {
            ; VDA exported functions return -1 on error. Only treat a non-error
            ; result as a successful registration.
            regResult := DllCall(this.pRegisterHook, "Ptr", A_ScriptHwnd, "Int", this.hookMsg, "Int")
            if regResult != -1 {
                this.hasHookRegistered := true
                ; Keep the exact bound object so Cleanup() can unregister it. A fresh
                ; .Bind(this) is a different object and would not remove this callback.
                this.msgCallback := this.OnDesktopChangeMessage.Bind(this)
                OnMessage(this.hookMsg, this.msgCallback)
            }
        }
        return true
    }

    static GoTo(desktopNum) {
        if !this.isLoaded
            return false
        ; A desktop number below 1 is always invalid, even when the count is unknown;
        ; otherwise desktopNum - 1 becomes a negative zero-based index passed to the DLL.
        if desktopNum < 1
            return false
        count := this.GetDesktopCount()
        if count > 0 && desktopNum > count
            return false
        result := DllCall(this.pGoToDesktopNumber, "Int", desktopNum - 1, "Int")
        return result != -1
    }

    static MoveWindow(hwnd, desktopNum) {
        if !this.isLoaded
            return false
        if desktopNum < 1
            return false
        count := this.GetDesktopCount()
        if count > 0 && desktopNum > count
            return false
        result := DllCall(this.pMoveWindowToDesktopNumber, "Ptr", hwnd, "Int", desktopNum - 1, "Int")
        return result != -1
    }

    static GetCurrent() {
        if !this.isLoaded
            return this.DESKTOP_UNKNOWN
        res := DllCall(this.pGetCurrentDesktopNumber, "Int")
        return (res = -1) ? this.DESKTOP_UNKNOWN : res + 1
    }

    static GetWindowDesktop(hwnd) {
        if !this.isLoaded
            return this.DESKTOP_UNKNOWN
        res := DllCall(this.pGetWindowDesktopNumber, "Ptr", hwnd, "Int")
        return (res = -1) ? this.DESKTOP_UNKNOWN : res + 1
    }

    ; Positive count, or 0 when unknown/unavailable. Never invent a count: callers
    ; must treat 0 as "cannot validate" and skip range checks rather than assume 9.
    static GetDesktopCount() {
        if !this.isLoaded || !this.pGetDesktopCount
            return 0
        res := DllCall(this.pGetDesktopCount, "Int")
        return (res = -1) ? 0 : res
    }

    ; Returns: 1 pinned, 0 not pinned, -1 unknown/error
    static IsPinned(hwnd) {
        if !this.isLoaded || !this.pIsPinnedWindow
            return -1
        res := DllCall(this.pIsPinnedWindow, "Ptr", hwnd, "Int")
        if res = -1
            return -1
        return res ? 1 : 0
    }

    ; Returns: 1 yes, 0 no, -1 unknown/error
    static IsOnCurrentDesktop(hwnd) {
        if !this.isLoaded
            return -1
        if this.pIsWindowOnCurrentVirtualDesktop {
            res := DllCall(this.pIsWindowOnCurrentVirtualDesktop, "Ptr", hwnd, "Int")
            if res = -1
                return -1
            return res ? 1 : 0
        }
        ; Check pin state first: a pinned window is visible on every desktop, so it can
        ; be resolved even when the current/window desktop queries return unknown.
        pinned := this.IsPinned(hwnd)
        if pinned = 1
            return 1
        cur := this.GetCurrent()
        win := this.GetWindowDesktop(hwnd)
        if cur = this.DESKTOP_UNKNOWN || win = this.DESKTOP_UNKNOWN
            return -1
        return (win = cur) ? 1 : 0
    }

    static OnDesktopChangeMessage(wParam, lParam, msg, hwnd) {
        ; Official VDA v2 example: wParam = old desktop (0-based), lParam = new desktop (0-based)
        newDesktop := Integer(lParam) + 1
        _HandleDesktopChangeFromMsg(newDesktop)
    }

    static Cleanup() {
        if this.hasHookRegistered && this.pUnregisterHook {
            try DllCall(this.pUnregisterHook, "Ptr", A_ScriptHwnd)
            this.hasHookRegistered := false
        }
        ; Also remove the AutoHotkey message callback; unregistering the DLL hook alone
        ; leaves the OnMessage handler bound to a stale registration.
        if this.msgCallback {
            try OnMessage(this.hookMsg, this.msgCallback, 0)
            this.msgCallback := 0
        }
        if this.hVDA {
            try DllCall("FreeLibrary", "Ptr", this.hVDA)
            this.hVDA := 0
        }
        this.isLoaded := false
    }
}
