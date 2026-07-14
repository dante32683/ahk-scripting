#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk

; Minimal stubs so we can exercise signature-index helpers without loading Core.
global g_SigToHwndIndex := Map()
global g_WinSigCache := Map()
global g_PwaCache := Map()

_RemoveFromSigIndex(hwnd, sig) {
    global g_SigToHwndIndex
    if sig = "" || !g_SigToHwndIndex.Has(sig)
        return
    if g_SigToHwndIndex[sig].Has(hwnd)
        g_SigToHwndIndex[sig].Delete(hwnd)
    if g_SigToHwndIndex[sig].Count = 0
        g_SigToHwndIndex.Delete(sig)
}

_IndexWinSignature(hwnd, sig) {
    global g_SigToHwndIndex, g_WinSigCache
    if sig = ""
        return
    g_WinSigCache[hwnd] := sig
    if !g_SigToHwndIndex.Has(sig)
        g_SigToHwndIndex[sig] := Map()
    g_SigToHwndIndex[sig][hwnd] := true
}

; Mirrors the reclassification steps performed by _AsyncCheckPWA after WMI confirms a PWA.
SimulatePwaReclassify(hwnd, oldSig, newSig) {
    global g_PwaCache, g_WinSigCache
    if oldSig != ""
        _RemoveFromSigIndex(hwnd, oldSig)
    if g_WinSigCache.Has(hwnd)
        g_WinSigCache.Delete(hwnd)
    g_PwaCache[hwnd] := true
    _IndexWinSignature(hwnd, newSig)
}

RunPwaReclassTest() {
    hwnd := 4242
    provisional := "chrome.exe"
    finalSig := "chrome.exe:Gmail"

    _IndexWinSignature(hwnd, provisional)
    AssertTrue(g_SigToHwndIndex.Has(provisional), "provisional signature indexed")
    AssertTrue(g_SigToHwndIndex[provisional].Has(hwnd), "hwnd under provisional sig")
    AssertEq(g_WinSigCache[hwnd], provisional, "cache holds provisional sig")

    SimulatePwaReclassify(hwnd, provisional, finalSig)

    AssertFalse(g_SigToHwndIndex.Has(provisional) && g_SigToHwndIndex[provisional].Has(hwnd)
        , "old signature-index entry removed")
    if g_SigToHwndIndex.Has(provisional)
        AssertEq(g_SigToHwndIndex[provisional].Count, 0, "provisional bucket emptied")
    AssertTrue(g_SigToHwndIndex.Has(finalSig), "final signature indexed")
    AssertTrue(g_SigToHwndIndex[finalSig].Has(hwnd), "hwnd under final PWA sig")
    AssertEq(g_WinSigCache[hwnd], finalSig, "cache holds final PWA sig")
    AssertTrue(g_PwaCache[hwnd], "HWND-specific PWA classification stored")

    ; Destroyed / reused HWND safety: removing again is a no-op.
    _RemoveFromSigIndex(hwnd, finalSig)
    AssertFalse(g_SigToHwndIndex.Has(finalSig) && g_SigToHwndIndex[finalSig].Has(hwnd)
        , "index cleared after destroy-style removal")
}

RunPwaReclassTest()
Test_Pass("pwa_reclass")
ExitApp(0)
