# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Script

- **Start**: Double-click `Master.ahk` (or right-click → Run with AutoHotkey). The script auto-elevates to admin.
- **Reload**: `CapsLock + Esc` (force-kills and restarts the process).
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

## Architecture

All logic lives in a single `Master.ahk` entry point. The file is divided into clearly labeled sections:

1. **Init / Performance** — `ListLines 0`, `KeyHistory 0`, admin elevation.
2. **VDA (VirtualDesktopAccessor)** — loads the DLL at startup; all virtual desktop calls go through `GoToDesktopNumber`, `MoveWindowToDesktopNumber`, `GetCurrentDesktopNumber`, `GetWindowDesktopNumber` function pointers. Falls back gracefully if the DLL is missing.
3. **Focus Event Hook** — `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` drives `TrackFocusHistory`. Zero polling. Unhooked on exit.
4. **Desktop Focus Memory** — `DesktopLastWindow` Map holds last-focused HWND per desktop. Written to `%TEMP%\ahk_desktop_memory.ini` only on exit via `OnExit`. Restored on reload (HWNDs survive `CapsLock+Esc`). `MoveToDesktop` writes the moved window into `DesktopLastWindow[n]` before switching so focus lands on the moved window, not the previously remembered one.
5. **Layout Persistence / Restore** — `g_Layouts` Map (`hwnd → [xf, yf, wf, hf]`) is persisted to `%TEMP%\ahk_layouts.ini` on every tile/update and restored on reload. Use `IsWindow`, not `WinExist`, when validating tracked HWNDs: cloaked windows on inactive virtual desktops are still live and must not be pruned.
   - **Desktop switch**: `GotoDesktop(n)` and foreground-based desktop-change detection both schedule `_RestoreDesktop(n)` retries.
   - **System events**: `WM_SETTINGCHANGE` (`SPI_SETWORKAREA`), `WM_POWERBROADCAST`, and `WM_DISPLAYCHANGE` schedule `_RestoreAllDesktops()` plus a delayed current-desktop pass.
   - **Passive drift correction**: `EVENT_OBJECT_LOCATIONCHANGE` watches only tracked windows. If a tracked window moves without a user drag and its outer position differs materially from the expected tile, `_ScheduleAutoRestore(hwnd)` snaps it back. Programmatic retiles are suppressed briefly so the hook does not fight the script’s own `WinMove`.
6. **Window Management Helpers** — `_ApplyLayout(x%, y%, w%, h%, overrideHwnd, persist)` is the single tiling primitive. `persist` defaults `true`; restore helpers pass `false` to skip disk I/O. DWM extended-frame bounds are used for border compensation, with a guard for invalid cloaked-window rects. `EVENT_SYSTEM_MOVESIZESTART/END` distinguishes user drags from automatic correction, and `FocusDirection` skips cloaked windows (`DWMWA_CLOAKED`) so windows on other virtual desktops are never selected.
7. **Hyper Layer** — `#HotIf GetKeyState("CapsLock", "P")` block; CapsLock acts as a modifier. WASD = arrows, HJKL = focus direction, Z/X/number keys = tiling/desktops.
8. **Keyboard Lock** — `CapsLock+Alt+L` toggles `BlockInput`. While locked, typing `"unlock"` releases it (tracked in `g_UnlockBuf`; 6-char rolling buffer). A second `#HotIf g_KeyLockActive` block intercepts the unlock keys.
9. **Camera Toggle** — Copilot key (`#+F23`) uses WMI (pre-initialized at startup) to query device state, then `pnputil.exe` (with PowerShell fallback) to enable/disable by `CFG_CameraID`.

### Standalone Scripts (not included by Master.ahk)

- `Click.ahk` — Simple auto-clicker toggle on F8. Run separately when needed.
- `Status.ahk` — Always-on-top status pill showing mic/cam/Tailscale/v2rayN state. Uses `CapabilityAccessManager` registry keys and Core Audio COM. Run separately.
- `Tailscale.ahk` — Network-aware startup script: detects Wi-Fi SSID and conditionally starts/stops v2rayN, Xray, SSH tunnel, and Tailscale. Intended to run on login/network change.

## Conventions

- **AHK v2 only** — use v2 syntax exclusively; `#Requires AutoHotkey v2.0+` at the top of every file.
- **Config variables** — all user-specific values go in `config.ahk` and are prefixed `CFG_`.
- **Paths** — use `EnvGet("LocalAppData")`, `A_WinDir`, `A_ScriptDir`, etc. Never hardcode user paths in `Master.ahk`.
- **Tiling** — extend by adding a new one-liner calling `_ApplyLayout`. Adjust `TileGap` global for spacing.
- **OSD messages** — use `ShowOSD(text, ms)` for all user-facing notifications; `ms := 0` keeps the tooltip until the next call.
