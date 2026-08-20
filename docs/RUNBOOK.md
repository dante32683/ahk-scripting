# Runbook

## Requirements

- Windows 11.
- [AutoHotkey v2](https://www.autohotkey.com/) — install the x64 version.
- [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor/releases) — x64 build; place in the repo root.
- [PowerToys](https://aka.ms/installpowertoys) — required only if `CFG_TilingMode = "FancyZones"`.

## First-Time Setup

1. Clone or copy this repo somewhere permanent (e.g. `C:\Users\<you>\Documents\AutoHotkey`).
2. Create `custom\`.
3. Copy `config.example.ahk` → `custom\config.ahk` and fill in your values. See the config reference below.
4. Put optional personal scripts such as `Core_custom.ahk`, `Master_custom.ahk`, `Master-PC_custom.ahk`, and local network helpers in `custom\`.
5. Place `VirtualDesktopAccessor.dll` (x64) in the repo root.
6. Run `Master.ahk` (laptop) or `Master-PC.ahk` (PC).

`custom\` is gitignored and must never be committed.

### Config Reference

| Variable | Required | Purpose |
|---|---|---|
| `CFG_Email` | No | Text expansion target for `@@` |
| `CFG_Phone` | No | Text expansion target for `#ph` |
| `CFG_Username` | No | Text expansion target for username shortcut |
| `CFG_CameraID` | No | Device Instance Path for camera toggle. Find it in Device Manager → your camera → Properties → Details → Device Instance Path. |
| `CFG_TilingMode` | Yes | `"Native"` or `"FancyZones"` |
| `CFG_TilingMemory` | Yes | `true` or `false` — enables per-app tiling memory in Native mode |
| `CFG_Autocorrect` | Yes | `true` or `false` — enables the autocorrect engine |
| `CFG_MacAltRemaps` | No | Initial Alt mode. `true` enables the macOS-style Alt remaps. The saved toggle overrides this value. |
| `CFG_GameProcesses` | No | Array of game executable filenames (e.g. `["game.exe"]`) to disable `Alt+Q` and `Alt+W` remaps |
| `CFG_FZ_Z` | FancyZones only | FancyZones layout ID for `CapsLock+Z` |
| `CFG_FZ_X` | FancyZones only | FancyZones layout ID for `CapsLock+X` |
| `CFG_FZ_P` | FancyZones only | FancyZones layout ID for `CapsLock+P` |
| `CFG_FZ_O` | FancyZones only | FancyZones layout ID for `CapsLock+O` |
| `CFG_FocusTeleportMouse` | No | `true` or `false` — enables mouse cursor teleportation to targeted window on CapsLock+h/j/k/l (Default: `true`) |
| `CFG_MonitorFocusTeleportMouse` | No | `true` or `false` — enables mouse cursor teleportation to focused monitor on CapsLock+Left/Right (Default: `true`) |
| `CFG_DriftCorrection` | No | `true` or `false` — enables layout drift correction loop (Default: `true`) |
| `CFG_DriftCheckInterval` | No | Number (ms) — interval for drift correction checks (Default: `2000`) |
| `CFG_NetworkProfileName` | No | String — network profile name for optional local automation |
| `CFG_NetworkToolExe` | No | String — executable name for an optional local network tool |
| `CFG_NetworkToolPath` | No | String — full path to an optional local network tool |
| `CFG_NetworkToolDir` | No | String — working directory for an optional local network tool |
| `CFG_TunnelUser` | No | String — username for optional local tunnel automation |
| `CFG_TunnelHost` | No | String — host for optional local tunnel automation |
| `CFG_TunnelBinaryPath` | No | String — full path to an optional tunnel helper |

FancyZones layout IDs are GUIDs shown in the FancyZones editor under PowerToys settings.

## Daily Operations

| Action | How |
|---|---|
| Start | Double-click `Master.ahk` (or right-click → Run with AutoHotkey) |
| Reload (hard) | `CapsLock+Esc` — kills and restarts; rebuilds autocorrect first |
| Soft reset | `CapsLock+R` — rebuilds autocorrect if DB changed; otherwise releases stuck modifiers and unlocks keyboard lock |
| Restart Explorer | `CapsLock+Shift+R` |
| Pause script | `CapsLock+Shift+Space` |
| Kill script | `Ctrl+Esc` |
| Toggle CapsLock | `Shift+CapsLock` or `Alt+Shift+CapsLock` |
| Toggle Mac Alt mode | `CapsLock+Alt+M` |

## Spatial Focus (`CapsLock+H/J/K/L`)

`FocusDirection` in `lib/Core.ahk` scores candidate windows by edge distance (with center-distance fallback when outer rects overlap), overlap penalty, and z-order. Candidates that span nearly the full width or height of the active window — typical of a fullscreen app behind tiled panes — are excluded. Set `CFG_FocusTeleportMouse := false` in `custom\config.ahk` to disable cursor teleport on focus switch.

## Adding A Tiling Layout

All tiling is done by calling `_ApplyLayout(xf, yf, wf, hf, hwnd, persist)` where `xf/yf/wf/hf` are percentages (0–100) of monitor dimensions.

To add a new Native layout, add an action function in `lib/WindowTiling_Native.ahk`.
Then route one unused suffix in the Hyper dispatcher in `lib/Core.ahk`:

```ahk
_HyperHandleLetter(key) {
    if key = "<key>" && g_TilingMode = "Native" && _HyperAltDown() {
        _ApplyLayout(xf, yf, wf, hf, "A", true)
        return
    }
}
```

Example — tile to the left 40%:

```ahk
if key = "i" && g_TilingMode = "Native" && _HyperAltDown()
    _ApplyLayout(0, 0, 40, 100, "A", true)
```

To adjust the gap between the window edge and the monitor edge, change the `g_TileGap` global at the top of `Core.ahk`.

## Adding An Autocorrect Entry

1. Open `Autocorrect_Database.txt`.
2. Add a line in the format `trigger->correction`. Example: `teh->the`.
3. Save the file.
4. Press `CapsLock+Esc` to reload. The build step runs automatically and sorts the database.

The generated `lib/Autocorrect.ahk` is gitignored, and the script builds or rebuilds it automatically on startup if the database is newer or missing.

To re-enable a disabled correction:

1. Press `CapsLock+Alt+Shift+D` to open `Autocorrect_Disabled.txt`.
2. Delete the relevant line.
3. Press `CapsLock+Esc` to reload.

## Adding An App Launcher

App launcher actions live in the shared Hyper dispatcher in `Core.ahk`.
Use `_ActivateOrRunOnCurrentDesktop` so a launcher does not pull windows from another virtual desktop:

```ahk
CapsLock & <key>::_ActivateOrRunOnCurrentDesktop("AppName.exe", "shell:appsFolder\...")
```

For apps that can be launched by executable path:

```ahk
CapsLock & <key>::_ActivateOrRunOnCurrentDesktop("notepad.exe", "notepad.exe")
```

If the app is laptop-only or PC-only, add it to the respective entry point file, not `Core.ahk`.

## Enabling Local Network Automation

Local network automation belongs in a gitignored `custom\` script. If you want it to run outside the main script, register that custom script with Windows Task Scheduler:

1. Open Task Scheduler.
2. Create a task triggered on network connection (Event Log: `Microsoft-Windows-NetworkProfile/Operational`, Event ID 10000).
3. Set the action to run `AutoHotkey.exe` with your gitignored `custom\...` script as the argument.
4. Run with highest privileges.

Any network hotkeys should be registered from a gitignored custom file.

## Updating VirtualDesktopAccessor

If virtual desktop switching breaks after a Windows update:

1. Download the latest `VirtualDesktopAccessor.dll` (x64) from the [releases page](https://github.com/Ciantic/VirtualDesktopAccessor/releases).
2. Replace the DLL in the repo root.
3. Press `CapsLock+Esc` to reload.

If the new DLL does not fix it, the Windows COM interfaces may have changed. Check the VDA GitHub issues for compatibility status. In the meantime, `CapsLock+Left/Right` falls back to `Ctrl+Win+Left/Right` (navigation only).
