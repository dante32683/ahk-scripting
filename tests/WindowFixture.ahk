#Requires AutoHotkey v2.0+
; Shared helpers for unit tests (no hooks / no elevation).

AssertTrue(cond, msg := "assert true failed") {
    if !cond
        throw Error(msg)
}

AssertFalse(cond, msg := "assert false failed") {
    if cond
        throw Error(msg)
}

AssertEq(a, b, msg := "") {
    if a != b
        throw Error((msg != "" ? msg ": " : "") "expected " b " got " a)
}

Test_Pass(name) {
    FileAppend("PASS " name "`n", "*", "UTF-8")
}
