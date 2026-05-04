# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Script

- **Start**: Double-click `Master.ahk` (or right-click → Run with AutoHotkey). The script auto-elevates to admin.
- **Reload**: hold `CapsLock` then press `Esc` (force-kills and restarts; rebuilds autocorrect first).
- **Soft reset**: hold `CapsLock` then press `R` (rebuilds autocorrect if DB changed, otherwise releases stuck modifiers and unlocks keyboard lock).
- **Restart Explorer**: `CapsLock+Shift+R`.
- **Toggle CapsLock**: `Shift+CapsLock` (or `Alt+Shift+CapsLock`).
- **Pause script**: `CapsLock+Shift+Space`.
- **Kill**: `Ctrl+Esc`.
- No build step, linter, or test runner — AHK scripts are interpreted directly.

## Setup

1. Copy `config.example.ahk` → `config.ahk` and fill in personal values.
2. Place `VirtualDesktopAccessor.dll` (x64) in the repo root.
3. Run `Master.ahk`.

`config.ahk` is gitignored and must never be committed.

### Config variables (`config.ahk`)

| Variable | Purpose |
|---|---|
| `CFG_Email` / `CFG_Phone` | Text expansion (`@@` / `#ph`) |
| `CFG_Username` | Username for text expansion |
| `CFG_CameraID` | Device Instance Path for camera toggle (from Device Manager → Details) |
| `CFG_TilingMode` | `"Native"` (built-in AHK tiling) or `"FancyZones"` (PowerToys) |
| `CFG_TilingMemory` | `true`/`false` — enables per-app tiling memory in Native mode |
| `CFG_Autocorrect` | `true`/`false` — enables the autocorrect hotstring engine |
| `CFG_FZ_Z/X/P/O` | FancyZones layout IDs for `CapsLock+Z/X/P/O` shortcuts (FancyZones mode only) |

## Architecture

Shared logic lives in `lib/Core.ahk`. Entry points are `Master.ahk` (laptop) and `Master-PC.ahk` (PC).

1. **Init / Performance** — `ListLines 0`, `KeyHistory 0`, admin elevation.
2. **VDA (VirtualDesktopAccessor)** — loads the DLL; handles virtual desktop function pointers. Gracefully degrades if DLL is missing.
3. **WinEvent Hooks** — three `SetWinEventHook` callbacks:
   - `EVENT_SYSTEM_FOREGROUND` → `TrackFocusHistory` (focus tracking + tiling memory snap)
   - `EVENT_SYSTEM_MOVESIZESTART/END` → `_OnMoveStart/_OnMoveEnd` (drift correction suppression)
   - `EVENT_OBJECT_DESTROY` → `_OnWindowDestroy` (persists maximized state on window close)
4. **Modular Tiling** — Both files are always included; `CFG_TilingMode` gates which hotkey block is active:
   - `lib/WindowTiling_Native.ahk`: Native AHK tiling hotkeys.
   - `lib/WindowTiling_FancyZones.ahk`: Passthrough hotkeys for PowerToys FancyZones.
5. **Layout Persistence / Restore** — `g_Layouts` Map persisted to `%TEMP%\ahk_layouts.ini`.
   - **Tiling Mode Check**: `_RestoreDesktop` and `_RestoreAllDesktops` only execute if `g_TilingMode = "Native"`.
   - **Passive drift correction**: `_CheckLayoutRestores` timer (2s) runs only in Native mode.
6. **Tiling Memory** — Per-app layout memory persisted to `%TEMP%\Tiling_Memory.ini` (fractional coordinates xf/yf/wf/hf, 0–100). Controlled by `CFG_TilingMemory`.
   - `_PersistToMemory(hwnd, ...)` — writes fractional layout on every explicit tile.
   - `_AutoSnapFromMemory(hwnd)` — called on focus; snaps window to its last position. If `maximized=1` is stored, maximizes instead.
   - `_OnWindowDestroy` — when a tracked window closes, persists `maximized=1/0` using cached `g_WinSigCache`/`g_WinMaxState`.
   - Max state is kept fresh by: focus hook, `_OnMoveEnd`, `ToggleMaximize`, and the 2s timer.
   - Explicit tiling always clears the `maximized` key, so tiling wins over prior maximized memory.
7. **Window Management Helpers** — `_ApplyLayout` is the single tiling primitive. All tiling functions call it.
8. **Hyper Layer** — `#HotIf GetKeyState("CapsLock", "P")` block; CapsLock acts as a modifier. Desktop/monitor switching is machine-specific and lives in the entry points.
9. **Keyboard Lock** — `CapsLock+Alt+L` toggles `BlockInput`. Unlock by typing `"unlock"` on the physical keyboard.
10. **App Launchers** — `_ActivateOrRunOnCurrentDesktop` ensures hotkey-launched apps stay on the current virtual desktop.
11. **Camera Toggle** — Copilot key (`#+F23`) toggles device via `pnputil.exe` (with PowerShell fallback).
12. **Eye 202020** — `lib/Eye202020.ahk` — 20-20-20 rule eye break timer (laptop only; `Master-PC.ahk` stubs out the API).
13. **Global Remaps** — `Remap.ahk` — macOS-style Alt→Ctrl remapping and smart window/tab closing logic. Included by both entry points.

### Autocorrect System

- **`Autocorrect_Database.txt`** — source of truth; one `trigger->correction` entry per line. Auto-sorted alphabetically on every rebuild.
- **`lib/Build_Autocorrect.ahk`** — rebuilds `lib/Autocorrect.ahk` on startup when the database (or builder itself) is newer than the generated file, or the file is missing/empty (< 200 bytes). Auto-reloads after rebuild.
- **`lib/Autocorrect.ahk`** — **auto-generated**; all hotstrings wrapped in `#HotIf CFG_Autocorrect`. Never edit directly.
- **`lib/Autocorrect_Logic.ahk`** — runtime layer: undo last correction (Backspace within 2 s), permanently disable a correction (`CapsLock+Alt+Backspace`), open disabled list (`CapsLock+Alt+D`).
- **`Autocorrect_Disabled.txt`** — persisted disabled entries in `trigger->correction` format; loaded on startup into `AC_DisabledMap`.

To add corrections: edit `Autocorrect_Database.txt` (one `trigger->correction` per line) and reload — the build step runs automatically.  
To re-enable a disabled correction: remove its line from `Autocorrect_Disabled.txt` (open with `CapsLock+Alt+D`) and reload.

### Standalone Scripts (not included by Master.ahk)

- `Click.ahk` — Simple auto-clicker toggle on F8. Run separately when needed.
- `Status.ahk` — Always-on-top status pill showing mic/cam/Tailscale/v2rayN state. Uses `CapabilityAccessManager` registry keys and Core Audio COM. Run separately.
- `Tailscale.ahk` — Network-aware startup script: detects Wi-Fi SSID and conditionally starts/stops v2rayN, Xray, SSH tunnel, and Tailscale. Run via Task Scheduler on the laptop.
- `Setup.ahk` — One-time setup utility.

## Conventions

- **AHK v2 only** — use v2 syntax exclusively; `#Requires AutoHotkey v2.0+` at the top of every file.
- **Config variables** — all user-specific values go in `config.ahk` and are prefixed `CFG_`.
- **Paths** — use `EnvGet("LocalAppData")`, `A_WinDir`, `A_ScriptDir`, etc. Never hardcode user paths.
- **Tiling** — extend by adding a one-liner calling `_ApplyLayout`. Adjust the `TileGap` global for spacing.
- **OSD messages** — use `ShowOSD(text, ms)` for all user-facing notifications; `ms := 0` keeps the tooltip until the next call.
- **Machine-specific logic** — anything laptop-only goes in `Master.ahk`; PC-only goes in `Master-PC.ahk`. Shared logic always goes in `lib/Core.ahk`.
