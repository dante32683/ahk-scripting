#Requires AutoHotkey v2.0+

; ============================================================
; PERSONAL CONFIG TEMPLATE
; Copy this file to custom\config.ahk and fill in your own values.
; The custom\ folder is gitignored and will never be committed.
; ============================================================

global CFG_Email    := "you@example.com"
global CFG_Phone    := "5551234567"
global CFG_Username := "your_username"
global CFG_CameraID := ""                         ; Device Instance ID from Device Manager
                                                  ; Right-click camera → Properties → Details
                                                  ; → Property: "Device instance path"
global CFG_MachineProfile := "laptop" ; "laptop" or "desktop"
global CFG_EnableVirtualDesktops := true

; Tiling mode: "FancyZones" (PowerToys) or "Native" (built-in AHK tiling)
global CFG_TilingMode := "FancyZones"

; CapsLock+1–9 / CapsLock+Alt+1–9 behaviour:
;   "desktops" — switch to / move window to virtual desktop N  (laptop default)
;   "monitors"  — focus / move window to monitor N             (PC default)
global CFG_NumberKeys := "auto"

; FancyZones layout IDs for CapsLock shortcuts
global CFG_FZ_Z := "1"
global CFG_FZ_X := "2"
global CFG_FZ_P := "0"
global CFG_FZ_O := "4"

; Autocorrect: automatically fix common Wikipedia misspellings
global CFG_Autocorrect := true

; Tiling enhancements (Native mode only)
global CFG_TilingMemory    := true
global CFG_TilePadding     := 4

global CFG_GameProcesses   := []  ; opt-in list e.g. ["cs2.exe", "javaw.exe"] — no hard-coded games

; Tiling exclusions (processes to ignore for window tiling/focus restoring)
global CFG_TilingExclusions := [
    "Raycast.exe",
    "SearchHost.exe",
    "ShellExperienceHost.exe",
    "StartMenuExperienceHost.exe",
    "PowerToys.exe",
    "PowerLauncher.exe",
    "PowerToys.PowerLauncher.exe",
    "Microsoft.CmdPal.UI.exe",
    "PowerToys.CommandPaletteExtension.exe"
]

; --- Focus & Mouse Teleportation Settings ---
global CFG_FocusTeleportMouse := true
global CFG_MonitorFocusTeleportMouse := true

; --- Native Tiling Drift Correction Settings ---
global CFG_DriftCorrection := true
global CFG_DriftCheckInterval := 20000  ; slow fallback reconcile (ms); location-change is primary

; What happens when you manually drag/resize a tracked window (Native mode):
;   "learn"   — remember the new position as this window's layout (default)
;   "clear"   — stop tracking the window after a manual move
;   "restore" — snap the window back to its previous tiled layout
global CFG_ManualMoveBehavior := "learn"

; --- Optional local network automation ---
; Keep concrete network names, hostnames, user names, and executable paths in
; custom\config.ahk or another gitignored custom file.
global CFG_NetworkProfileName := "YourNetworkName"
global CFG_NetworkToolExe     := "network-tool.exe"
global CFG_NetworkToolPath    := "C:\Tools\NetworkTool\network-tool.exe"
global CFG_NetworkToolDir     := "C:\Tools\NetworkTool"
global CFG_TunnelUser         := "your_tunnel_user"
global CFG_TunnelHost         := "example.internal"
global CFG_TunnelBinaryPath   := "C:\Tools\Tunnel\tunnel.exe"

