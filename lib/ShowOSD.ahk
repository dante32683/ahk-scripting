#Requires AutoHotkey v2.0+

global g_OsdGui
if !IsSet(g_OsdGui)
    g_OsdGui := ""

ShowOSD(text, ms := 1500) {
    global g_OsdGui
    
    ; Cancel any pending fade-out timer
    SetTimer(_FadeOutOSD, 0)
    
    ; Destroy existing GUI if it exists
    if IsSet(g_OsdGui) && IsObject(g_OsdGui) {
        try g_OsdGui.Destroy()
        g_OsdGui := ""
    }
    
    ; If empty string is passed, we just dismiss the OSD
    if text == ""
        return
        
    ; Create new GUI with DPIScale enabled (default)
    g_OsdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    g_OsdGui.BackColor := "1F1F1F" ; Windows 11 Dark Mode background
    
    ; Set standard clean Segoe UI font (no excessive bolding to keep text crisp)
    g_OsdGui.SetFont("s10", "Segoe UI")
    
    ; Add text control (crisp white text)
    textCtrl := g_OsdGui.Add("Text", "cFFFFFF +Wrap x24 y14 w260", text)
    
    ; Show GUI hidden to calculate its height
    g_OsdGui.Show("Hide")
    g_OsdGui.GetPos(,, &w, &h)
    
    ; Get the DPI of the window to scale coordinates correctly
    dpi := DllCall("GetDpiForWindow", "Ptr", g_OsdGui.Hwnd, "UInt")
    scale := dpi / 96
    
    ; Convert pixel height to logical height for the GUI layout engine
    logicalH := h / scale
    barHeight := logicalH - 28
    
    ; Add the left accent bar (Windows 11 blue)
    g_OsdGui.Add("Text", "w4 h" barHeight " Background0078D4 y14 x12")
    
    ; Position in bottom-right corner of primary monitor (in pixels)
    MonitorGetWorkArea(1, &left, &top, &right, &bottom)
    x := right - w - 20
    y := bottom - h - 20
    
    ; Apply opacity and show
    WinSetTransparent(240, g_OsdGui.Hwnd)
    g_OsdGui.Show("x" x " y" y " NoActivate")
    
    if ms > 0 {
        SetTimer(_FadeOutOSD, -ms)
    }
}

_FadeOutOSD(*) {
    global g_OsdGui
    if !IsSet(g_OsdGui) || !IsObject(g_OsdGui)
        return
    
    currentHwnd := g_OsdGui.Hwnd
    alpha := 240
    loop 24 {
        alpha -= 10
        ; If the global GUI was replaced or cleared, stop fading this instance
        if !IsSet(g_OsdGui) || !IsObject(g_OsdGui) || g_OsdGui.Hwnd != currentHwnd
            return
        try WinSetTransparent(alpha, currentHwnd)
        Sleep 15
    }
    
    ; Clean up the global GUI object if it still matches this instance
    if IsSet(g_OsdGui) && IsObject(g_OsdGui) && g_OsdGui.Hwnd == currentHwnd {
        try g_OsdGui.Destroy()
        g_OsdGui := ""
    }
}
