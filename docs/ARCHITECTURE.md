# Architecture

## File Layout

```text
/
├── docs/                          # Canonical documentation (this folder)
├── lib/
│   ├── Core.ahk                   # All shared logic — see module breakdown below
│   ├── WindowTiling_Native.ahk    # Native tiling hotkey block
│   ├── WindowTiling_FancyZones.ahk # FancyZones passthrough hotkey block
│   ├── Build_Autocorrect.ahk      # Autocorrect build step
│   ├── Autocorrect.ahk            # Auto-generated hotstring list — never edit
│   ├── Autocorrect_Logic.ahk      # Autocorrect runtime (disable, persist)
│   └── ShowOSD.ahk                # ShowOSD() helper
├── plans/                         # Local planning notes (non-authoritative)
├── Master.ahk                     # Laptop entry point
├── Master-PC.ahk                  # PC entry point
├── Remap.ahk                      # Global Alt→Ctrl remaps (both machines)
├── config.example.ahk             # Config template
├── custom/                        # User-specific values and local extensions (gitignored)
│   ├── config.ahk                 # Required local config copied from config.example.ahk
│   ├── Core_custom.ahk            # Optional shared local extensions
│   ├── Master_custom.ahk          # Optional laptop-only local extensions
│   ├── Master-PC_custom.ahk       # Optional PC-only local extensions
│   └── Network_custom.ahk         # Optional local network script
├── Autocorrect_Database.txt       # Autocorrect source of truth
├── Autocorrect_Disabled.txt       # Persisted disabled corrections
├── Tiling_Memory.ini              # Persisted per-app tiling positions
├── VirtualDesktopAccessor.dll     # Virtual desktop COM wrapper (x64)
└── Setup.ahk                      # Standalone: one-time setup
```

## Startup Sequence

Both entry points follow the same startup order:

1. `#Requires AutoHotkey v2.0+` and performance flags (`ListLines 0`, `KeyHistory 0`).
2. Admin elevation — if not already elevated, re-launches itself with `RunAs`.
3. `#Include custom/config.ahk` — loads all local `CFG_` variables.
4. `#Include lib/Core.ahk` — loads shared logic, registers WinEvent hooks, starts timers.
5. `#Include lib/WindowTiling_Native.ahk` and `lib/WindowTiling_FancyZones.ahk` — both always included; `CFG_TilingMode` gates which hotkey block is active via `#HotIf`.
6. `#Include Remap.ahk` — registers global Alt→Ctrl remaps.
7. `#Include lib/Autocorrect_Logic.ahk` — initializes autocorrect runtime state and registers disable hotkeys.
8. `#Include lib/Build_Autocorrect.ahk` — rebuilds `lib/Autocorrect.ahk` if the database is newer or the generated file is missing/stale (< 200 bytes), then calls `SafeReload()`.
9. `#Include *i lib/Autocorrect.ahk` — loads generated hotstrings when present.
10. Machine-specific hotkeys (virtual desktops or monitor switching).
11. Optional local extension includes from `custom\`.

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

### Tiling Memory (Cross-Session)

Per-app positions persisted to `<script dir>\Tiling_Memory.ini`. Uses a signature-based lookup:

- **Signature** (`_GetWinSignature`) — for normal apps, the signature is the process name (e.g. `WindowsTerminal.exe`). For PWAs, it includes the title: `msedge.exe:Gmail`.
- **Write** (`_PersistToMemory`) — called on every explicit tile. Writes `xf/yf/wf/hf` under the signature section. Also writes to `g_HWNDLayoutCache` keyed by hwnd for multi-instance support.
- **Read** (`_AutoSnapFromMemory`) — called on focus. If only one instance of the process is running, reads from the INI. If multiple instances are running, reads from `g_HWNDLayoutCache` (ephemeral, in-memory only). If the hwnd is not in the cache yet (new window, never explicitly tiled), no snap occurs.
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
| `g_TilingMemoryFile` | `String` | Absolute path to `Tiling_Memory.ini` |
| `g_LayoutFile` | `String` | Absolute path to `%TEMP%\ahk_layouts.ini` |
| `g_LastDesktop` | `Int` | Most recently active virtual desktop number |
| `g_FocusHistory` | `Array` | Ordered hwnd history for `CapsLock+Backspace` |
| `g_DesktopLastWindow` | `Map` | `desktop → hwnd` — per-desktop focus memory |
| `g_ProcNameCache` | `Map` | `hwnd → process name` — initialized before WinEvent hooks so callbacks are safe during startup |
| `g_WindowOffsetCache` | `Map` | `hwnd → [left, top, right, bottom]` — cached window border offsets |

### Hyper Layer (CapsLock)

`#HotIf GetKeyState("CapsLock", "P")` wraps all CapsLock hotkeys. While CapsLock is held, it acts as a modifier. The block is in `Core.ahk` for shared hotkeys; machine-specific hotkeys (desktop/monitor navigation) are in the entry points.

### Spatial Focus

`FocusDirection(dir)` in `lib/Core.ahk` handles `CapsLock+H/J/K/L` (hotkeys in `WindowTiling_Native.ahk` and `WindowTiling_FancyZones.ahk`). It scores visible windows on the current virtual desktop by direction, edge gap, overlap along the navigation axis, and z-order. Background windows that span the active pane (e.g. a fullscreen browser under tiled terminals) are filtered out so focus moves to the adjacent tile.

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
hotstrings active in all windows
        │
        ▼ (correction fires)
Autocorrect_Logic.ahk
  ├── CapsLock+Alt+Backspace → add to Autocorrect_Disabled.txt, reload
  └── CapsLock+Alt+D → open Autocorrect_Disabled.txt
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
              ├── single instance → read Tiling_Memory.ini → _ApplyLayout
              └── multiple instances → read g_HWNDLayoutCache → _ApplyLayout
                                        (no-op if hwnd not in cache)
```

## What Lives Where

| Concern | Location |
|---|---|
| Shared hotkeys / logic | `lib/Core.ahk` |
| Virtual desktop navigation | `Master.ahk` |
| Monitor navigation | `Master-PC.ahk` |
| Native tiling hotkeys | `lib/WindowTiling_Native.ahk` |
| FancyZones hotkeys | `lib/WindowTiling_FancyZones.ahk` |
| Alt→Ctrl remaps | `Remap.ahk` |
| User-specific values | `custom/config.ahk` |
| Optional shared local extensions | `custom/Core_custom.ahk` |
| Optional laptop local extensions | `custom/Master_custom.ahk` |
| Optional PC local extensions | `custom/Master-PC_custom.ahk` |
| Network-aware switching / hotkeys | `custom/Network_custom.ahk` or another local script included from `custom/Master_custom.ahk` |
