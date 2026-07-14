#Requires AutoHotkey v2.0+

global g_OsdGui := ""
global g_OsdGeneration := 0
global g_OsdAlpha := 240
global g_OsdPhase := "idle" ; idle | shown | fading
global g_OsdFadeTimer := 0  ; the exact bound function object currently registered as a repeating timer

; Stop whatever fade timer is currently registered, using the same object it was
; created with. AutoHotkey requires the identical function object to delete a timer;
; a fresh `_OsdFadeTick` bare reference (or a new .Bind()) is a different object and
; would leave the old repeating timer firing forever.
_OsdStopFadeTimer() {
    global g_OsdFadeTimer
    if g_OsdFadeTimer {
        try SetTimer(g_OsdFadeTimer, 0)
        g_OsdFadeTimer := 0
    }
}

ShowOSD(text, ms := 1500) {
    global g_OsdGui, g_OsdGeneration, g_OsdAlpha, g_OsdPhase
    if IsSet(CFG_TestMode) && CFG_TestMode
        return

    g_OsdGeneration += 1
    gen := g_OsdGeneration
    _OsdStopFadeTimer()

    if IsSet(g_OsdGui) && IsObject(g_OsdGui) {
        try g_OsdGui.Destroy()
        g_OsdGui := ""
    }
    g_OsdPhase := "idle"
    if text == ""
        return

    g_OsdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    g_OsdGui.BackColor := "1F1F1F"
    g_OsdGui.SetFont("s10", "Segoe UI")
    g_OsdGui.Add("Text", "cFFFFFF +Wrap x24 y14 w260", text)
    g_OsdGui.Show("Hide")
    g_OsdGui.GetPos(,, &w, &h)

    dpi := DllCall("GetDpiForWindow", "Ptr", g_OsdGui.Hwnd, "UInt")
    dpi := dpi > 0 ? dpi : 96  ; guard against a zero DPI result (division below)
    scale := dpi / 96
    logicalH := h / scale
    barHeight := logicalH - 28
    g_OsdGui.Add("Text", "w4 h" barHeight " Background0078D4 y14 x12")

    ; Active monitor (focused window), fallback primary
    mon := 1
    if WinExist("A") {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "A")
            mon := MonitorFromPoint(wx + ww // 2, wy + wh // 2)
        }
    }
    MonitorGetWorkArea(mon, &left, &top, &right, &bottom)
    x := right - w - 20
    y := bottom - h - 20

    g_OsdAlpha := 240
    WinSetTransparent(g_OsdAlpha, g_OsdGui.Hwnd)
    g_OsdGui.Show("x" x " y" y " NoActivate")
    g_OsdPhase := "shown"

    if ms > 0
        SetTimer(_OsdStartFade.Bind(gen), -ms)
}

_OsdStartFade(gen) {
    global g_OsdGeneration, g_OsdPhase, g_OsdFadeTimer
    if gen != g_OsdGeneration || g_OsdPhase != "shown"
        return
    g_OsdPhase := "fading"
    _OsdStopFadeTimer()
    g_OsdFadeTimer := _OsdFadeTick.Bind(gen)
    SetTimer(g_OsdFadeTimer, 15)
}

_OsdFadeTick(gen) {
    global g_OsdGui, g_OsdGeneration, g_OsdAlpha, g_OsdPhase
    if gen != g_OsdGeneration || g_OsdPhase != "fading" {
        _OsdStopFadeTimer()
        return
    }
    if !IsSet(g_OsdGui) || !IsObject(g_OsdGui) {
        _OsdStopFadeTimer()
        g_OsdPhase := "idle"
        return
    }
    g_OsdAlpha -= 10
    if g_OsdAlpha <= 0 {
        _OsdStopFadeTimer()
        try g_OsdGui.Destroy()
        g_OsdGui := ""
        g_OsdPhase := "idle"
        return
    }
    try WinSetTransparent(g_OsdAlpha, g_OsdGui.Hwnd)
}

; Destroy any active OSD and stop its fade timer. Called from ordered shutdown.
_OsdShutdown() {
    global g_OsdGui, g_OsdPhase
    _OsdStopFadeTimer()
    if IsSet(g_OsdGui) && IsObject(g_OsdGui) {
        try g_OsdGui.Destroy()
        g_OsdGui := ""
    }
    g_OsdPhase := "idle"
}
