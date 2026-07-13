#Requires AutoHotkey v2.0+
#SingleInstance Off
global CFG_TestMode := true
#Include WindowFixture.ahk
#Include ..\lib\Config.ahk

RunConfigResolutionTest() {
    ; --- Profile resolution ---
    AssertEq(Config_ResolveProfile("desktop", "laptop"), "desktop", "override wins over config")
    AssertEq(Config_ResolveProfile("", "desktop"), "desktop", "config used when no override")
    AssertEq(Config_ResolveProfile("", ""), "laptop", "default is laptop")
    AssertEq(Config_ResolveProfile("nonsense", ""), "", "invalid override rejected")
    AssertEq(Config_ResolveProfile("", "bogus"), "", "invalid config rejected")

    ; --- Number keys resolution ---
    AssertEq(Config_ResolveNumberKeys("laptop", "auto"), "desktops", "laptop auto -> desktops")
    AssertEq(Config_ResolveNumberKeys("desktop", "auto"), "monitors", "desktop auto -> monitors")
    AssertEq(Config_ResolveNumberKeys("desktop", ""), "monitors", "desktop unset -> monitors")
    AssertEq(Config_ResolveNumberKeys("laptop", "monitors"), "monitors", "explicit override honored")
    AssertEq(Config_ResolveNumberKeys("laptop", "junk"), "", "invalid number-keys rejected")

    ; --- Virtual desktops default ---
    AssertTrue(Config_ResolveEnableVirtualDesktops("laptop", ""), "laptop defaults VD on")
    AssertFalse(Config_ResolveEnableVirtualDesktops("desktop", ""), "desktop defaults VD off")
    AssertTrue(Config_ResolveEnableVirtualDesktops("desktop", true), "explicit true honored on desktop")
    AssertFalse(Config_ResolveEnableVirtualDesktops("laptop", false), "explicit false honored on laptop")
}

RunConfigResolutionTest()
Test_Pass("config_resolution")
ExitApp(0)
