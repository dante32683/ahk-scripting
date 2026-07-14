# Bugs And Known Issues

This is the active issue ledger for the script. Log bugs here instead of leaving TODO comments in code.

## Open / Deferred (perf-reliability-overhaul)

These are known limitations deferred during the performance & reliability overhaul. None
block normal use after the desktop-focus and state-encoding repairs; remaining items are
edge-case hardening.

- **DEFER-001 (Low, State):** Legacy state files (`Tiling_Memory.ini`, `%TEMP%\ahk_layouts.ini`,
  `Autocorrect_Disabled.txt`) are migrated into `%LOCALAPPDATA%\AutoHotkeyMaster` and backed
  up (`*.bak`) but the originals are never deleted (deliberate). Legacy desktop memory
  (`%TEMP%\ahk_desktop_memory.ini`) is consumed once without importing raw HWNDs, because
  those handles cannot be identity-verified after reboot.
- **DEFER-002 (Low, Perf):** Baseline vs. after performance measurements (working set, idle
  CPU, tiling/focus P50/P95) require running on the target Windows machine over time. Set
  `CFG_PerfLogging := true` to emit `%TEMP%\AutoHotkeyMaster\perf.csv`; no numbers are
  committed to the repo because they cannot be gathered in a static/CI environment.
- **DEFER-003 (Low, State):** INI escaping (`State_EscapeIni`) uses sequential replacement.
  A window signature containing a literal backtick followed by an escape letter is a
  theoretical corruption case shared with the pre-existing scheme; process/class/title
  values in practice do not contain backticks. The `|` delimiter is now encoded, which was
  the real reported risk.
- **DEFER-004 (Medium, Focus):** Same-app cycling still uses fail-open desktop membership when
  VDA returns unknown; directional/monitor focus fail closed. Unifying that remains open.
- **DEFER-005 (Low, PWA):** Stable `--app-id` identity (instead of normalized title) is not
  yet preferred for final PWA signatures; WMI verification now corrects title heuristics.
- **MANUAL-001 (High, Desktop):** Two-desktop textbox caret restore must be verified manually
  (click textbox A → switch → textbox B → switch back → type without clicking).

---

## Known Risks

### RISK-001: VirtualDesktopAccessor Breaks On Windows Updates

Priority: High
Area: Virtual desktops

`VirtualDesktopAccessor.dll` wraps undocumented Windows COM interfaces for virtual desktop management. Major Windows 11 updates can change these interfaces, breaking the DLL without warning.

Mitigation: when desktop switching stops working after an update, check the [VDA releases page](https://github.com/Ciantic/VirtualDesktopAccessor/releases) for a new build. The script degrades gracefully — `CapsLock+Left/Right` falls back to `Ctrl+Win+Left/Right` and all other hotkeys continue working.

### RISK-002: Tiling Memory Collision On Multi-Instance Apps

Priority: Medium
Area: Tiling memory

When multiple windows of the same process are open (e.g. two terminals), they share the same INI signature. The per-HWND cache (`g_HWNDLayoutCache`) handles this for windows that have been explicitly tiled in the current session, but a newly opened window will not auto-snap until it has been tiled at least once.

Mitigation: tile each new terminal window once after opening it. The position is then remembered for the rest of the session.

### RISK-003: Drift Correction And User Moves

Priority: Low
Area: Tiling / drift correction

Drift correction is now event-driven: `EVENT_OBJECT_LOCATIONCHANGE` marks a tracked window
dirty and a ~150 ms debounce reconciles it, with a slow safety pass (`_CheckLayoutRestores`,
`CFG_DriftCheckInterval`, default 20 s) only to recover missed events. `_OnMoveStart`/
`_OnMoveEnd` suppress correction during a drag and `g_MoveSuppressUntil` extends the grace
period afterward. Manual-move behavior is configurable via `CFG_ManualMoveBehavior`
(`learn` / `clear` / `restore`).

Mitigation: set `CFG_ManualMoveBehavior := "learn"` (default) so a manual move is remembered
rather than reverted; or `"clear"` to stop tracking a window after you move it.

### RISK-004: Admin Elevation And UAC Prompts

Priority: Low
Area: Startup

`Master.ahk` auto-elevates to admin via `RunAs`. On machines with UAC set to always prompt, this produces a confirmation dialog on every startup or reload. There is no workaround without disabling UAC or creating a task scheduler entry that runs the script elevated at logon.

### RISK-005: Keyboard Lock With No Unlock Fallback

Priority: Medium
Area: Keyboard lock

`CapsLock+Alt+L` calls `BlockInput(true)`, which blocks all input. Unlock requires typing `"unlock"` on the physical keyboard. If the script crashes or is killed while the keyboard is locked, the only recovery is to reboot.

Mitigation: the lock is only intended for short periods (e.g. cleaning a keyboard). Do not activate it and then leave the machine unattended.

---

## Resolved

### ~~Multi-instance windows always skipped auto-snap~~ — RESOLVED

Area: Tiling memory

When multiple windows of the same process were open, `_AutoSnapFromMemory` bailed out entirely because it could not determine which saved position belonged to which window. All instances were skipped.

Fix: added `g_HWNDLayoutCache` — an ephemeral per-HWND Map written on every explicit tile. When multiple instances are detected, `_AutoSnapFromMemory` reads from the cache instead of the shared INI. Windows that have not been explicitly tiled in the current session still do not snap (correct behavior — there is no reliable way to assign a saved position to a new window).

### ~~New terminal windows skipped custom scaling when another terminal was open~~ — RESOLVED

Area: Terminal Hotkeys

When terminal hotkeys that spawn new windows (`CapsLock + Shift + T` or `CapsLock + Alt + Shift + T`) were used, the `WinWait` check matched existing Windows Terminal windows immediately instead of waiting for the newly created window to initialize. This caused the existing terminal to receive focus and the custom `FloatCenter` layout while the new terminal window opened at default size.

Fix: Implemented `_RunAndWaitForNewWindow` inside the `*t::` block, which captures currently open terminal `HWND`s, launches the terminal command, and detects the new window's `HWND` to target it specifically for `FloatCenter` scaling.

### ~~Spatial focus jumped to occluded background windows~~ — RESOLVED

Area: Focus navigation

`CapsLock+H/J/K/L` could focus a fullscreen window behind tiled panes (e.g. a browser under side-by-side terminals) because scoring used center-to-center distance only.

Fix: `FocusDirection` now uses edge-distance scoring with overlap penalty, center-distance fallback for shadow overlap, and excludes candidates whose axis overlap spans nearly the full active window. `CapsLock+T` minimize toggle now targets `"A"` only so multiple terminal windows are not minimized together.

