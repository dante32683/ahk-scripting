# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Script

- **Start**: Double-click `Master.ahk` (or right-click → Run with AutoHotkey). The script auto-elevates to admin.
- **Reload**: hold `CapsLock` then press `Esc` (force-kills and restarts the process).
- **Soft reset**: hold `CapsLock` then press `R` (releases stuck modifiers, unlocks keyboard lock, restores the last `CapsLock+N` hidden window).
- **Toggle CapsLock**: `Shift + CapsLock` (or `Alt + Shift + CapsLock`).
- **Kill**: `Ctrl + Esc`.
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
| `CFG_CameraID` | Device Instance Path for camera toggle (from Device Manager → Details) |
| `CFG_Autocorrect` | `true`/`false` — enables the autocorrect hotstring engine |

## Architecture

Shared logic lives in `lib/Core.ahk`. Entry points are `Master.ahk` (laptop) and `Master-PC.ahk` (PC).
The codebase is divided into modular sections:

1. **Init / Performance** — `ListLines 0`, `KeyHistory 0`, admin elevation.
2. **VDA (VirtualDesktopAccessor)** — loads the DLL; handles virtual desktop function pointers.
3. **Focus Event Hook** — `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` drives `TrackFocusHistory`.
4. **Modular Tiling** — Window management hotkeys are decoupled from core logic. `lib/Core.ahk` includes one of:
   - `lib/WindowTiling_Native.ahk`: Automated AHK tiling, retiler timer, and restoration logic.
   - `lib/WindowTiling_FancyZones.ahk`: Passthrough hotkeys for PowerToys FancyZones.
5. **Layout Persistence / Restore** — `g_Layouts` Map persisted to `%TEMP%\ahk_layouts.ini`.
   - **Tiling Mode Check**: `_RestoreDesktop` and `_RestoreAllDesktops` only execute if `g_TilingMode == "Native"`.
   - **Passive drift correction**: `_CheckLayoutRestores` timer (2s) runs only in Native mode.
6. **Window Management Helpers** — `_ApplyLayout` is the single tiling primitive.
7. **Hyper Layer** — `#HotIf GetKeyState("CapsLock", "P")` block; CapsLock acts as a modifier.
8. **Keyboard Lock** — `CapsLock+Alt+L` toggles `BlockInput`. Unlock by typing `"unlock"`.
9. **App Launchers** — Ensures app hotkeys stay on the current virtual desktop.
10. **Camera Toggle** — Copilot key (#+F23) toggles device via `pnputil.exe`.

### Autocorrect System

- **`Autocorrect_Database.txt`** — source of truth; one `trigger->correction` entry per line. Auto-sorted alphabetically on every rebuild.
- **`lib/Build_Autocorrect.ahk`** — included by `Master.ahk`; rebuilds `lib/Autocorrect.ahk` on startup when the database is newer than the generated file (or the file is missing/empty), then reloads.
- **`lib/Autocorrect.ahk`** — **auto-generated**; contains all hotstrings wrapped in `#HotIf CFG_Autocorrect`. Never edit directly.
- **`lib/Autocorrect_Logic.ahk`** — runtime layer: undo last correction (Backspace within 2 s), permanently disable a correction (`CapsLock+Alt+Backspace`), open disabled list (`CapsLock+Alt+D`).
- **`Autocorrect_Disabled.txt`** — persisted disabled entries in `trigger->correction` format; loaded on startup into `AC_DisabledMap`.

To add corrections: edit `Autocorrect_Database.txt` (one `trigger->correction` per line) and reload — the build step runs automatically.
To re-enable a disabled correction: remove its line from `Autocorrect_Disabled.txt` (open with `CapsLock+Alt+D`) and reload.

### Standalone Scripts (not included by Master.ahk)

- `Click.ahk` — Simple auto-clicker toggle on F8. Run separately when needed.
- `Status.ahk` — Always-on-top status pill showing mic/cam/Tailscale/v2rayN state. Uses `CapabilityAccessManager` registry keys and Core Audio COM. Run separately.
- `Tailscale.ahk` — Network-aware startup script: detects Wi‑Fi SSID and conditionally starts/stops v2rayN, Xray, SSH tunnel, and Tailscale. Intended to run on the laptop via Task Scheduler (not included by `Master-PC.ahk`).

## Conventions

- **AHK v2 only** — use v2 syntax exclusively; `#Requires AutoHotkey v2.0+` at the top of every file.
- **Config variables** — all user-specific values go in `config.ahk` and are prefixed `CFG_`.
- **Paths** — use `EnvGet("LocalAppData")`, `A_WinDir`, `A_ScriptDir`, etc. Never hardcode user paths in `Master.ahk`.
- **Tiling** — extend by adding a new one-liner calling `_ApplyLayout`. Adjust `TileGap` global for spacing.
- **OSD messages** — use `ShowOSD(text, ms)` for all user-facing notifications; `ms := 0` keeps the tooltip until the next call.
