# Tiling Fix Summary

## Problem

`MenuBar` restarts or AppBar changes were causing Windows to shift tiled windows by a small amount. The failure was most visible on inactive virtual desktops: if the work-area change happened while you were on desktop 1, windows on desktop 3 would often still be wrong when you switched back.

## What We Tried

1. Read the existing `Master.ahk` restore system and the repo notes in `CLAUDE.md`.
2. Added immediate layout persistence so `g_Layouts` writes to `%TEMP%\ahk_layouts.ini` on tile/update instead of only on script exit.
3. Added extra desktop-switch restores:
   - foreground-hook-based desktop change detection
   - repeated `_RestoreDesktop(n)` retries after a switch
   - delayed current-desktop restore after `WM_SETTINGCHANGE` / power / display events
4. That still did not fix the core failure.

## Key Troubleshooting Step

We added debug logging to `%TEMP%\ahk_restore_debug.log` around:

- `GotoDesktop`
- desktop change detection
- `_RestoreDesktop`
- `_RestoreAllDesktops`
- `_ApplyLayout`
- system message handlers

The log showed the real bug:

- after leaving desktop 3, tracked windows on that inactive desktop were being pruned as "dead"
- `g_Layouts` dropped to `0`
- by the time `MenuBar` restarted on desktop 1, there was nothing left to restore

## Root Cause

The script used `WinExist("ahk_id ...")` as the liveness check for tracked windows.

That is wrong for this use case. Cloaked windows on inactive virtual desktops are still valid HWNDs, but `WinExist` was effectively treating them as gone during restore/prune logic.

## Fixes That Matter

### 1. Use real HWND liveness checks

Added `_IsLiveWindow(hwnd)` using:

```ahk
DllCall("user32\IsWindow", "Ptr", hwnd, "Int")
```

and replaced `WinExist` with `_IsLiveWindow` in:

- layout load
- layout save
- restore pruning
- override validation in `_ApplyLayout`

This was the fix that made off-desktop restore start working.

### 2. Keep immediate layout persistence

Tracked layouts are now persisted during normal use, not just on exit:

- tiling updates call `_PersistLayout(hwnd)`
- user drag end updates call `_PersistLayout(hwnd)`
- clearing a layout deletes the persisted entry

This avoids losing tracked layouts if the script exits unexpectedly.

### 3. Add passive drift correction

Added a low-overhead `EVENT_OBJECT_LOCATIONCHANGE` hook that watches tracked windows only.

If a tracked window moves without a user drag, and its actual outer position differs materially from the expected tiled position, the script schedules an automatic snap-back.

Efficiency/safety measures:

- only tracked windows are considered
- `EVENT_SYSTEM_MOVESIZESTART/END` marks user drags so the auto-correct path does not fight manual movement
- the script suppresses auto-correction briefly after its own `WinMove`
- no polling loop was added

### 4. Keep system-event-based bulk restore

The restore system still uses:

- `WM_SETTINGCHANGE` for `SPI_SETWORKAREA`
- `WM_POWERBROADCAST`
- `WM_DISPLAYCHANGE`
- desktop-switch restore retries

This remains the primary safety net for work-area and display changes.

### 5. Harden transient state handling

`WinGetMinMax("ahk_id " hwnd)` was throwing during desktop transitions.

Added `_GetWindowState(hwnd, default := -2)` and switched restore/auto-restore code to use it so transition-state failures are skipped instead of crashing timer callbacks.

## Documentation Updated

`CLAUDE.md` was updated to reflect:

- `g_Layouts` and `%TEMP%\ahk_layouts.ini`
- the `IsWindow` vs `WinExist` virtual-desktop gotcha
- system-event restore behavior
- passive drift correction via `EVENT_OBJECT_LOCATIONCHANGE`
- user-drag distinction via `EVENT_SYSTEM_MOVESIZESTART/END`

## Final State

The working approach now is:

- keep tracked layouts persisted immediately
- never prune inactive-desktop windows just because they are cloaked
- restore on desktop switches and relevant system events
- passively detect unexpected programmatic movement and snap tracked windows back
- avoid polling to keep battery/performance overhead low
