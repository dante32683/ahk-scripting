# Architecture

## File Layout

```text
/
├── docs/                          # Canonical documentation (this folder)
├── lib/
│   ├── Core.ahk                   # All shared logic — see module breakdown below
│   ├── WindowTiling_Native.ahk    # Native tiling actions
│   ├── WindowTiling_FancyZones.ahk # FancyZones actions
│   ├── Build_Autocorrect.ahk      # Autocorrect build step
│   ├── Autocorrect.ahk            # Auto-generated hotstring list — never edit
│   ├── Autocorrect_Logic.ahk      # Autocorrect runtime (disable, persist)
│   ├── ShowOSD.ahk                # ShowOSD() helper
│   ├── Perf.ahk                   # Telemetry/instrumentation engine
│   ├── StateStore.ahk             # Centralized StateStore engine
│   └── VDA.ahk                    # Object-oriented dynamic VDA wrapper
├── Main.ahk                       # Central unified entry point
├── Master.ahk                     # Laptop entry point wrapper
├── Master-PC.ahk                  # PC entry point wrapper
├── Remap.ahk                      # Global Alt→Ctrl remaps (both machines)
├── config.example.ahk             # Config template
├── custom/                        # User-specific values and local extensions (gitignored)
│   ├── config.ahk                 # Required local config copied from config.example.ahk
│   ├── Core_custom.ahk            # Optional shared local extensions
│   ├── Master_custom.ahk          # Optional laptop-only local extensions
│   ├── Master-PC_custom.ahk       # Optional PC-only local extensions
│   └── Network_custom.ahk         # Optional local network script
├── Autocorrect_Database.txt       # Autocorrect source of truth
├── VirtualDesktopAccessor.dll     # Virtual desktop COM wrapper (x64)
└── Setup.ahk                      # Standalone: one-time setup
```

## Startup Sequence

All entry points unify under `Main.ahk`:

1. Capture startup tick count (`g_PerfStartupTick`).
2. `#Include custom/config.ahk` — loads local user configuration variables.
3. Validate and resolve machine profile (`APP_Profile`: `laptop` or `desktop`).
4. Apply performance settings (`ListLines false`, `KeyHistory`, `SetWinDelay 0`, `ProcessSetPriority`, `InstallKeybdHook`).
5. `#Include lib/Core.ahk` — includes other core libraries.
6. Initialize telemetry (`Perf_Init()`), StateStore (`State_Init()`), and VirtualDesktopAccessor (`VDA.Init()`).
7. Bind unconditional CapsLock custom combinations and initialize the shared dispatcher.
8. Show startup confirmation OSD message.

## Core.ahk Module Breakdown

`lib/Core.ahk` is organized into logical sections:

### VDA (VirtualDesktopAccessor)

Loads `VirtualDesktopAccessor.dll` via `DllCall("LoadLibrary", ...)` and resolves function pointers for `GetCurrentDesktopNumber`, `GoToDesktopNumber`, `MoveWindowToDesktopNumber`, and `GetWindowDesktopNumber`. If the DLL is missing, all VDA function pointers are set to `0` and feature checks gate on that. The script degrades gracefully — non-VDA hotkeys continue working.

### WinEvent Hooks

Three `SetWinEventHook` callbacks are registered at startup:

| Event | Callback | Purpose |
|---|---|---|
| `EVENT_SYSTEM_FOREGROUND` | `TrackFocusHistory` | Focus tracking + tiling memory snap |
| `EVENT_SYSTEM_MOVESIZESTART/END` | `_OnMoveStart` / `_OnMoveEnd` | Drift correction suppression |
| `EVENT_OBJECT_DESTROY` | `_OnWindowDestroy` | Persist maximized state on window close |

### Tiling Engine

`_ApplyLayout(xf, yf, wf, hf, hwnd, persist)` is the single tiling primitive. All tiling functions are one-liners that call it with different percentage values. It:

1. Resolves the monitor the window is on.
2. Converts fractional percentages to pixel coordinates accounting for `g_TileGap`.
3. Moves and resizes the window with `WinMove`.
4. If `persist = true`, calls `_PersistLayout` (session) and `_PersistToMemory` (cross-session).

### Layout Persistence (Session)

`g_Layouts` is a Map of `hwnd → [xf, yf, wf, hf]` persisted to `%TEMP%\ahk_layouts.ini`. It survives script reloads (the file is re-read on startup) but not reboots. Used by `_RestoreDesktop` and `_CheckLayoutRestores` to correct drift.

Drift correction: a 2-second timer (`_CheckLayoutRestores`) checks whether tracked windows have drifted from their recorded positions and re-applies the layout. Only active in Native mode.

### Tiling Memory (StateStore.ahk)

Per-app positions are persisted to `%LOCALAPPDATA%\AutoHotkeyMaster\layouts.txt` using Section/Key/Value formats managed by the central `StateStore.ahk` engine:

- **Signature** (`_GetWinSignature`) — for normal apps, the signature is the process name (e.g. `WindowsTerminal.exe`). For PWAs, it includes the title: `msedge.exe:Gmail`.
- **Write** (`State_SaveAppLayout`) — called on every explicit tile. Writes `xf/yf/wf/hf` under the signature. Also writes to `g_HWNDLayoutCache` keyed by hwnd for multi-instance support.
- **Read** (`_AutoSnapFromMemory`) — called on focus. If only one instance of the process is running, reads from the StateStore. If multiple instances are running, reads from `g_HWNDLayoutCache` (ephemeral, in-memory only). If the hwnd is not in the cache yet (new window, never explicitly tiled), no snap occurs.
- **Maximized state** — when a window closes, `_OnWindowDestroy` writes `maximized=1` or deletes the key. On focus, a `maximized=1` entry causes a `WinMaximize` instead of a position snap. Explicit tiling always clears `maximized`.

#### Fractional Coordinate System

All positions are stored as integers 0–100 representing percentages of monitor dimensions:

| Key | Meaning |
|---|---|
| `xf` | Left edge of window as % of monitor width |
| `yf` | Top edge of window as % of monitor height |
| `wf` | Window width as % of monitor width |
| `hf` | Window height as % of monitor height |

Example: `xf=50, yf=0, wf=50, hf=100` = right half of the monitor.

### Global State

| Variable | Type | Purpose |
|---|---|---|
| `g_Layouts` | `Map` | `hwnd → [xf, yf, wf, hf]` — session layout persistence |
| `g_WinSigCache` | `Map` | `hwnd → signature` — cached for `_OnWindowDestroy` |
| `g_WinMaxState` | `Map` | `hwnd → 1/0` — cached maximized state |
| `g_HWNDLayoutCache` | `Map` | `hwnd → {xf, yf, wf, hf}` — ephemeral per-instance position cache |
| `g_MoveSuppressUntil` | `Map` | `hwnd → tick` — suppresses drift correction after user moves |
| `g_UserMoveActive` | `Map` | `hwnd → true` — set during user drag |
| `g_AutoRestoreTimers` | `Map` | `hwnd → timer` — pending drift correction timers |
| `g_TilingMode` | `String` | `"Native"` or `"FancyZones"` — mirrors `CFG_TilingMode` |
| `g_StateDir` | `String` | Central directory for files: `%LOCALAPPDATA%\AutoHotkeyMaster` |
| `g_StateMacAltRemaps` | `Boolean` | Saved Mac Alt remap mode |
| `g_LastDesktop` | `Int` | Most recently active virtual desktop number |
| `g_FocusHistory` | `Array` | Ordered hwnd history for `CapsLock+Backspace` |
| `g_DesktopLastWindow` | `Map` | `desktop → hwnd` — per-desktop focus memory |
| `g_ProcNameCache` | `Map` | `hwnd → process name` — initialized before WinEvent hooks |
| `g_WindowOffsetCache` | `Map` | `hwnd → [left, top, right, bottom]` — cached window border offsets |

### Hyper Layer (CapsLock)

`Core.ahk` binds each CapsLock suffix once with an unconditional custom combination.
The dispatcher reads Alt, Shift, profile, and tiling mode inside the handler.
This keeps suppression independent of expression `#HotIf` evaluation.
The dispatcher sends an unused mask key when Alt is down. This prevents a bare Alt release from opening an app menu.

### Spatial Focus

`FocusDirection(dir)` in `lib/Core.ahk` handles `CapsLock+H/J/K/L` through the shared dispatcher.
It scores visible windows on the current virtual desktop by direction, edge gap, overlap along the navigation axis, and z-order.
Background windows that span the active pane are filtered out so focus moves to the adjacent tile.

### App Launchers

`_ActivateOrRunOnCurrentDesktop(exe, run, winTitle?)` checks if the target window exists on the current virtual desktop. If yes, it focuses it (and toggles minimize if it was already focused). If no, it runs the app. This prevents launchers from pulling windows from other desktops.

### Camera Toggle

The Copilot key (`Win+Shift+F23`) calls `pnputil.exe /disable-device` or `/enable-device` on the device ID stored in `CFG_CameraID`. Falls back to a PowerShell `Disable-PnpDevice` call if `pnputil` fails.

### Keyboard Lock

`CapsLock+Alt+L` calls `BlockInput(true)`, freezing all keyboard and mouse input. Unlock requires physically typing `"unlock"` on the keyboard (intercepted at the hook level before BlockInput suppresses it).

### Privacy Blackout

`CapsLock+Alt+K` toggles a borderless always-on-top black window covering all monitors. Useful for screen sharing. Implemented as a `Gui` with `+AlwaysOnTop -Caption +ToolWindow` and `WinSet Transparent`.

## Autocorrect System Data Flow

```text
Autocorrect_Database.txt
        │
        ▼ (Build_Autocorrect.ahk on startup if newer)
lib/Autocorrect.ahk  ←── auto-generated; never edit
        │
        ▼ (#Include at startup)
hotstrings active in all windows (calls AC_Proc in Autocorrect_Logic.ahk)
        │
        ▼ (correction fires)
Autocorrect_Logic.ahk
  ├── Checks _AC_IsNonTextArea() & AC_TempSuppressed
  ├── CapsLock+Alt+Backspace → add to g_StateAutocorrectDisabled via StateStore.ahk
  └── CapsLock+Alt+Shift+D → open autocorrect-disabled.txt
```

## Tiling Focus Flow

```text
Window receives focus
        │
        ▼ (EVENT_SYSTEM_FOREGROUND)
TrackFocusHistory(hwnd)
  ├── updates g_FocusHistory
  ├── updates g_DesktopLastWindow
  ├── caches sig in g_WinSigCache
  ├── caches max state in g_WinMaxState
  └── calls _AutoSnapFromMemory(hwnd)
              │
              ├── single instance → read StateStore (layouts.txt) → _ApplyLayout
              └── multiple instances → read g_HWNDLayoutCache → _ApplyLayout
                                        (no-op if hwnd not in cache)
```

## What Lives Where

| Concern | Location |
|---|---|
| Unified entry point | `Main.ahk` |
| Shared hotkeys / logic | `lib/Core.ahk` |
| Virtual desktop navigation | `Master.ahk` |
| Monitor navigation | `Master-PC.ahk` |
| Native tiling actions | `lib/WindowTiling_Native.ahk` and `lib/Core.ahk` |
| FancyZones actions | `lib/WindowTiling_FancyZones.ahk` and `lib/Core.ahk` |
| Alt→Ctrl remaps | `Remap.ahk` |
| Central state storage | `lib/StateStore.ahk` |
| Virtual Desktop logic | `lib/VDA.ahk` |
| Telemetry & telemetry instrumentation | `lib/Perf.ahk` |
| User-specific values | `custom/config.ahk` |
| Optional shared local extensions | `custom/Core_custom.ahk` |
| Optional laptop local extensions | `custom/Master_custom.ahk` |
| Optional PC local extensions | `custom/Master-PC_custom.ahk` |
| Network-aware switching / hotkeys | `custom/Network_custom.ahk` or another local script included from `custom/Master_custom.ahk` |
