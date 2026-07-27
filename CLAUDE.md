# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

Read `AGENTS.md` for the full project context and AI workflow instructions. The canonical documentation lives in `docs/`.

## Running the Script

- **Start**: Double-click `Master.ahk` (laptop) or `Master-PC.ahk` (PC). Both are thin shims that set `APP_ProfileOverride` and include `Main.ahk`, which holds all startup logic. The script auto-elevates to admin.
- **Reload**: hold `CapsLock` then press `Esc` (force-kills and restarts; rebuilds autocorrect first).
- **Soft reset**: hold `CapsLock` then press `R` (rebuilds autocorrect if DB changed, otherwise releases stuck modifiers and unlocks keyboard lock).
- **Restart Explorer**: `CapsLock+Shift+R`.
- **Toggle CapsLock**: `Shift+CapsLock` (or `Alt+Shift+CapsLock`).
- **Pause script**: `CapsLock+Shift+Space`.
- **Kill**: `Ctrl+Esc`.
- No build step or linter — AHK scripts are interpreted directly.
- **Tests**: `tools\check.ps1` runs the `tests\` suite with `AHK_TEST_MODE=1`. Test mode disables hooks, VDA, and all state writes, and uses a per-process temp state directory, so a test run never touches a live instance or real user state.

```bash
powershell -ExecutionPolicy Bypass -File tools/check.ps1
```

## Setup

1. Create `custom\`.
2. Copy `config.example.ahk` → `custom\config.ahk` and fill in personal values.
3. Put optional personal scripts in `custom\`.
4. Place `VirtualDesktopAccessor.dll` (x64) in the repo root.
5. Run `Master.ahk`.

`custom\` is gitignored and must never be committed.

### Config variables (`custom\config.ahk`)

| Variable | Purpose |
|---|---|
| `CFG_Email` / `CFG_Phone` | Text expansion (`@@` / `#ph`) |
| `CFG_Username` | Username for text expansion |
| `CFG_CameraID` | Device Instance Path for camera toggle (from Device Manager → Details) |
| `CFG_TilingMode` | `"Native"` (built-in AHK tiling) or `"FancyZones"` (PowerToys) |
| `CFG_TilingMemory` | `true`/`false` — enables per-app tiling memory in Native mode |
| `CFG_Autocorrect` | `true`/`false` — enables the autocorrect hotstring engine |
| `CFG_FZ_Z/X/P/O` | FancyZones layout IDs for `CapsLock+Z/X/P/O` shortcuts (FancyZones mode only) |
| `CFG_MachineProfile` | `"laptop"` or `"desktop"` — overridden by `APP_ProfileOverride` in the entry point |
| `CFG_EnableVirtualDesktops` | `true`/`false` — gates VDA DLL loading; defaults per profile |
| `CFG_NumberKeys` | `"desktops"`, `"monitors"`, or `"auto"` — what `CapsLock+1–9` does |
| `CFG_ManualMoveBehavior` | `"learn"` (default), `"clear"`, or `"restore"` — what a manual drag/resize does to a tracked window |
| `CFG_DriftCorrection` / `CFG_DriftCheckInterval` | Enables drift correction and sets the slow fallback reconcile interval (ms) |
| `CFG_TilingExclusions` | Array of process names never tiled or focus-restored |
| `CFG_GameProcesses` | Opt-in array of processes treated as games |
| `CFG_TilePadding` | Gap in px between tiled windows |
| `CFG_FocusTeleportMouse` / `CFG_MonitorFocusTeleportMouse` | Move the cursor along with directional / monitor focus changes |

See `config.example.ahk` for the full annotated list.

## Architecture

`Main.ahk` is the single entry point; `Master.ahk` and `Master-PC.ahk` only set a profile override and include it. Shared logic lives in `lib/Core.ahk`, with three extracted modules: `lib/StateStore.ahk` (persistence), `lib/Layout.ahk` (geometry), and `lib/VDA.ahk` (virtual desktops).

1. **Init / Performance** — profile resolution via the pure `Config_Resolve*` functions in `lib/Config.ahk`, then `ListLines 0`, `KeyHistory 0`, `SetWinDelay 0`, admin elevation. Subsystems start in a fixed order: `Perf_Init` → `State_Init` → `VDA.Init` → `Core_SessionInit` → `WindowEvents_Init`.
2. **VDA (`lib/VDA.ahk`)** — class wrapping the DLL's function pointers, plus a `RegisterPostMessageHook` callback for desktop-change notifications. Gracefully degrades if the DLL is missing. Query methods return `-1`/`DESKTOP_UNKNOWN` for "unknown", never a guessed value — callers must distinguish it from "no".
3. **WinEvent Hooks** — five `SetWinEventHook` callbacks. The raw callbacks only record primitives into pending maps and schedule `_ProcessWinEvents`, which drains them on the AHK thread under `Critical`:
   - `EVENT_SYSTEM_FOREGROUND` → `TrackFocusHistory` (focus tracking + tiling memory snap)
   - `EVENT_SYSTEM_MOVESIZESTART/END` → `_OnMoveStart/_OnMoveEnd` (drift correction suppression)
   - `EVENT_OBJECT_DESTROY` → `_OnWindowDestroy` (persists maximized state, purges per-HWND caches)
   - `EVENT_OBJECT_LOCATIONCHANGE` → `_OnLocationChange` (primary, event-driven drift correction)
4. **Modular Tiling** — Both files are always included; `CFG_TilingMode` gates which hotkey block is active:
   - `lib/WindowTiling_Native.ahk`: Native AHK tiling hotkeys.
   - `lib/WindowTiling_FancyZones.ahk`: Passthrough hotkeys for PowerToys FancyZones.
5. **Layout Records (`lib/Layout.ahk`)** — layouts are typed Maps, not raw rectangles: `kind` is `"slot"` (a gap-adjusted preset) or `"visible"` (a learned frame), coordinates are basis points 0–10000 of the monitor work area, and `anchorX`/`anchorY` drive minimum-size compensation. `Layout_Deserialize` is strict and non-throwing — a corrupt record returns `0` instead of aborting the caller. This file also holds the pure, unit-tested directional focus scoring.
6. **State Persistence (`lib/StateStore.ahk`)** — all durable state lives in `%LocalAppData%\AutoHotkeyMaster\` (override with `CFG_StateDir`):
   - `state-v2.ini` — per-app layouts and maximized flags, plus last-focused window per desktop. UTF-16, since Win32 `IniRead` only handles Unicode that way.
   - `session-handoff-v2.ini` — HWND-keyed layouts written only on orderly reload, consumed once and deleted; entries expire after 300 s.
   - `logs\state.log` — load/write failures.
   - Writes are debounced (`State_MarkDirty` → 500 ms flush) and atomic (temp file + `MoveFileExW`), with a retry on failure. The schema version is required and exact: a *future* version blocks writes rather than clobbering the file.
   - Restoring anything HWND-keyed goes through `_ValidateWindowIdentity` (pid + process + class + signature) and fails closed — handles get reused, so a bare HWND is never trusted.
   - `State_MigrateLegacy` imports the old `Tiling_Memory.ini` / `Autocorrect_Disabled.txt` once, backing up the originals. Legacy desktop memory is consumed but never restored (raw HWNDs, no identity).
7. **Tiling Memory** — per-app layout memory keyed by window signature (process name, or `proc:normalized-title` for PWAs). Controlled by `CFG_TilingMemory`.
   - `_PersistToMemory(hwnd, record)` — writes the layout record on every explicit tile.
   - `_AutoSnapFromMemory(hwnd)` — called on focus; snaps window to its last position, or maximizes if that was the stored state.
   - `_ProcessDestroyEvent` — when a tracked window closes, persists `maximized=1` (never `0`, which would wipe memory for same-signature peers).
   - Explicit tiling clears the maximized flag, so tiling wins over prior maximized memory, and re-enables auto-snap for that HWND.
8. **Drift Correction** — `_ProcessLocationChangeEvent` is the primary path; `_CheckLayoutRestores` is a slow fallback sweep (`CFG_DriftCheckInterval`). Both run only in Native mode, skip windows the user is actively moving, and honor `g_MoveSuppressUntil` (set for 1500 ms by every tile so our own moves don't trigger a correction). Restores are bounded — retries are capped so a repeatedly tiled window cannot reschedule forever.
9. **Local Extension Hooks** — optional `custom\Core_custom.ahk`, `custom\Master_custom.ahk`, and `custom\Master-PC_custom.ahk` files hold private machine-specific behavior outside the tracked repo.
10. **Window Management Helpers** — `_ApplyLayoutRecord` is the single tiling primitive (`_ApplyLayout` wraps it for percentage slots). It applies the move, re-reads what the window actually accepted, compensates position for minimum-size overflow according to the record's anchors, and schedules a short bounded settle for apps that adjust their frame just after the move.
11. **Hyper Layer** — `#HotIf GetKeyState("CapsLock", "P")` block; CapsLock acts as a modifier. Profile-specific desktop/monitor switching is gated on `APP_Profile` in `Main.ahk`.
12. **Keyboard Lock** — `CapsLock+Alt+L` toggles `BlockInput`. Unlock by typing `"unlock"` on the physical keyboard.
13. **App Launchers** — `_ActivateOrRunOnCurrentDesktop` ensures hotkey-launched apps stay on the current virtual desktop.
14. **Camera Toggle** — Copilot key (`#+F23`) toggles device via `pnputil.exe` (with PowerShell fallback).
15. **Global Remaps** — `Remap.ahk` — macOS-style Alt→Ctrl remapping and smart window/tab closing logic. Included by `Main.ahk`.

### Autocorrect System

- **`Autocorrect_Database.txt`** — source of truth; one `trigger->correction` entry per line. Auto-sorted alphabetically on every rebuild.
- **`lib/Build_Autocorrect.ahk`** — rebuilds `lib/Autocorrect.ahk` on startup when the database (or builder itself) is newer than the generated file, or the file is missing/empty (< 200 bytes). Force-restarts after rebuild.
- **`lib/Autocorrect.ahk`** — **auto-generated**; all hotstrings wrapped in `#HotIf CFG_Autocorrect`. Never edit directly.
- **`lib/Autocorrect_Logic.ahk`** — runtime layer: permanently disable a correction (`CapsLock+Alt+Backspace`), open disabled list (`CapsLock+Alt+D`).
- **Disabled entries** — persisted by StateStore to `%LocalAppData%\AutoHotkeyMaster\autocorrect-disabled.txt` in `trigger->correction` format, loaded on startup. A legacy `Autocorrect_Disabled.txt` in the script directory is migrated once on first run.

To add corrections: edit `Autocorrect_Database.txt` (one `trigger->correction` per line) and reload — the build step runs automatically.
To re-enable a disabled correction: remove its line from the disabled list (open with `CapsLock+Alt+D`) and reload.

### Standalone and Optional Scripts

- `custom\Click.ahk` — Simple auto-clicker toggle on F8. Run separately when needed (gitignored).
- `custom\Status.ahk` — Optional always-on-top status overlay. Run separately (gitignored).
- `custom\Network_custom.ahk` — Optional local network automation. Usually included by `custom\Master_custom.ahk` on laptop, and may also run via Task Scheduler (gitignored).
- `Setup.ahk` — One-time setup utility.

## Conventions

- **AHK v2 only** — use v2 syntax exclusively; `#Requires AutoHotkey v2.0+` at the top of every file.
- **Config variables** — all user-specific values go in `custom\config.ahk` and are prefixed `CFG_`.
- **Paths** — use `EnvGet("LocalAppData")`, `A_WinDir`, `A_ScriptDir`, etc. Never hardcode user paths.
- **Tiling** — extend by adding a one-liner calling `_ApplyLayout`. Adjust the `g_TileGap` global for spacing.
- **Persistence** — never write state files directly; go through `State_*` so writes stay debounced, atomic, and versioned.
- **OSD messages** — use `ShowOSD(text, ms)` for all user-facing notifications; `ms := 0` keeps the tooltip until the next call.
- **Machine-specific logic** — profile-gated hotkeys go in `Main.ahk` under `APP_Profile`; private per-machine behavior goes in `custom\`. Shared logic always goes in `lib/Core.ahk`.
- **Concurrency** — AHK threads are interruptible, so any timer or WinEvent handler that enumerates a shared global `Map` must hold `Critical` (or iterate a snapshot). Deleting from a `Map` mid-enumeration is undefined behavior, and `_ProcessDestroyEvent` deletes from most of them.
- **Window handles go stale** — an HWND validated before a `Sleep`, a `WinRestore`, or any other yield point may be dead by the time you use it. Re-check `IsWindow` immediately before acting, and wrap `WinMove`/`WinActivate` in `try` — an uncaught "Target window not found" surfaces as a modal error dialog.
