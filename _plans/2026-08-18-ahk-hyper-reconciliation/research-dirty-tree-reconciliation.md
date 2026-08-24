# AHK dirty-tree reconciliation

Date: 2026-08-18

## Compared trees

- Handoff source baseline: `f052caa7e9baf4d5a5984dc76703df6e5dda7de2`.
- Clean implementation worktree: `C:\Users\dziad\dev\ahk-orchestrator-work`.
- User checkout: `C:\Users\dziad\dev\ahk`, same baseline with dirty changes.

## User changes

The user checkout changes three files:

- `lib/Core.ahk`: a re-entry guard for window-event drains and window-existence checks after yielding calls.
- `lib/StateStore.ahk`: shorter critical sections and file writes outside the input-critical section.
- `lib/Autocorrect_Logic.ahk`: an `IsSet` guard before stopping the input hook.

These changes do not alter the Hyper hotkey section, tiling bindings, or the extracted autocorrect commands.

## Implementation changes

The clean worktree changes five files:

- `lib/Core.ahk`: unconditional CapsLock custom combinations, central dispatch, profile and tiling routing, defaults, and reload helper.
- `Main.ahk`: removes duplicate profile direction hotkeys.
- `lib/WindowTiling_Native.ahk`: removes duplicate Native hotkeys.
- `lib/WindowTiling_FancyZones.ahk`: removes duplicate FancyZones hotkeys.
- `lib/Autocorrect_Logic.ahk`: exposes callable disable and file-open functions.

## Reconciliation result

The changes are functionally separate and merged cleanly. The user checkout changes remain present.

The one intentional behavior change is `CapsLock+Alt+Shift+D` for the disabled-correction file. `CapsLock+Alt+D` remains the Native tile or FancyZones snap action, so the old D overlap cannot recur.

The merged checkout passed `tools/check.ps1`. Physical keyboard acceptance remains untested until the merged checkout runs on Windows.
