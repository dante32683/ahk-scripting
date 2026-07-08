# Bugs And Known Issues

This is the active issue ledger for the script. Log bugs here instead of leaving TODO comments in code.

## Open

_No open bugs at this time._

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

The 2-second drift correction timer (`_CheckLayoutRestores`) can re-snap a window the user intentionally moved if they release it and then do not interact with it for 2 seconds. `_OnMoveStart`/`_OnMoveEnd` suppress correction during the drag, and `g_MoveSuppressUntil` extends that grace period after the drag ends.

Mitigation: if a window keeps snapping back unexpectedly, press `CapsLock+Delete` to clear its tiling layout for the session.

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

