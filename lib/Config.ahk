#Requires AutoHotkey v2.0+

; Pure configuration-resolution helpers. No side effects, no globals — so the profile
; and default-resolution rules can be unit-tested without booting the whole script.

; Resolve the effective machine profile. profileOverride (APP_ProfileOverride from a
; wrapper) wins over the configured value. Returns "" for an invalid/unknown value so
; the caller can fail startup with a clear message rather than silently defaulting.
Config_ResolveProfile(profileOverride, configuredProfile) {
    resolvedProfile := "laptop"
    if profileOverride != ""
        resolvedProfile := profileOverride
    else if configuredProfile != ""
        resolvedProfile := configuredProfile
    if resolvedProfile != "laptop" && resolvedProfile != "desktop"
        return ""
    return resolvedProfile
}

; Resolve the number-key behaviour. "auto" (or unset, passed as "") maps to desktops on
; laptop and monitors on desktop. Returns "" for an invalid explicit value.
Config_ResolveNumberKeys(resolvedProfile, configuredNumberKeys) {
    if configuredNumberKeys = "" || configuredNumberKeys = "auto"
        return (resolvedProfile = "laptop") ? "desktops" : "monitors"
    if configuredNumberKeys != "desktops" && configuredNumberKeys != "monitors"
        return ""
    return configuredNumberKeys
}

; Resolve whether virtual desktops are enabled. When unset ("" sentinel), default to
; true only for the laptop profile.
Config_ResolveEnableVirtualDesktops(resolvedProfile, configuredEnableValue) {
    if configuredEnableValue = ""
        return (resolvedProfile = "laptop")
    return configuredEnableValue ? true : false
}
