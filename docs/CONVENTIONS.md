# Conventions

## AHK Version

Always use AHK v2 syntax. Every file must start with:

```ahk
#Requires AutoHotkey v2.0+
```

Never use v1 constructs (`MsgBox, text`, legacy hotstring syntax, `%var%` outside strings, etc.). v1 and v2 are not compatible and the script will fail silently or unexpectedly if mixed.

## File Organization

- **Shared logic** always goes in `lib/Core.ahk`. If something is used by both `Master.ahk` and `Master-PC.ahk`, it belongs in Core.
- **Machine-specific logic** goes in the entry point:
  - Laptop-only → `Master.ahk`
  - PC-only → `Master-PC.ahk`
- **Tiling hotkeys** go in `lib/WindowTiling_Native.ahk` or `lib/WindowTiling_FancyZones.ahk`, not in the entry points or Core.
- **Global remaps** (Alt→Ctrl) go in `Remap.ahk`.
- **Personal/local behavior** goes in gitignored `custom\` files. Shared local behavior belongs in `custom\Core_custom.ahk`; laptop-only behavior belongs in `custom\Master_custom.ahk`; PC-only behavior belongs in `custom\Master-PC_custom.ahk`.
- Never add behavior to the autocorrect files — `lib/Autocorrect.ahk` is auto-generated and `lib/Build_Autocorrect.ahk` is a build tool.

## Naming

- **Config variables** — all user-specific config values are prefixed `CFG_` (e.g. `CFG_TilingMode`, `CFG_Email`). Never hardcode personal values in shared files.
- **Private functions** — internal helpers that are not called from other files are prefixed with `_` (e.g. `_ApplyLayout`, `_GetWinSignature`). Public-facing functions are not prefixed (e.g. `ShowOSD`, `TrackFocusHistory`).
- **Global state** — global variables that represent persistent state are prefixed `g_` (e.g. `g_Layouts`, `g_TilingMode`). Config variables (`CFG_`) are the exception.

## Paths

Never hardcode user paths. Always use AHK built-in variables:

| Variable | Expands to |
|---|---|
| `A_ScriptDir` | Directory containing the running script |
| `A_WinDir` | Windows directory (e.g. `C:\Windows`) |
| `A_Temp` | User temp directory |
| `EnvGet("LocalAppData")` | `C:\Users\<user>\AppData\Local` |
| `EnvGet("AppData")` | `C:\Users\<user>\AppData\Roaming` |
| `EnvGet("USERPROFILE")` | `C:\Users\<user>` |

## OSD Messages

All user-facing notifications use `ShowOSD(text, ms)` from `lib/ShowOSD.ahk`:

```ahk
ShowOSD("Tiling memory enabled", 2000)  ; show for 2 seconds
ShowOSD("Keyboard locked", 0)           ; stay until next call
```

Do not use `ToolTip` directly. `ms := 0` keeps the tooltip visible until the next `ShowOSD` call, which is the correct behavior for persistent state indicators (e.g. keyboard lock, script pause).

## Tiling

To add a new tiling layout, call `_ApplyLayout` with fractional percentages. Do not add special-cased logic inside `_ApplyLayout` itself — it is the generic primitive and should stay generic.

```ahk
_ApplyLayout(xf, yf, wf, hf, hwnd, persist)
```

- `xf/yf` — top-left corner as % of monitor dimensions (0–100)
- `wf/hf` — size as % of monitor dimensions (0–100)
- `hwnd` — target window handle, or `"A"` for the active window
- `persist` — `true` to save to session layout and tiling memory; `false` for internal restores

Adjust `g_TileGap` (global in `Core.ahk`) to change the pixel gap between window edges and monitor edges. Do not override gap per-hotkey.

## Hotkey Structure

CapsLock actions use one unconditional custom combination per suffix in `lib/Core.ahk`.
The shared handler decides profile, tiling mode, Alt, and Shift behavior.

Global remaps go in `Remap.ahk`. A mode condition can enable or disable their hotkey blocks.

Machine-specific actions that use a shared suffix must be selected inside the shared handler.
Do not add duplicate CapsLock hotkeys in entry points or tiling modules.

## WinEvent Callbacks

WinEvent callbacks receive raw Windows event arguments. Keep them fast — do not do blocking I/O or slow operations. If a callback needs to trigger expensive work, post it to a timer or use `SetTimer` with a short delay.

WinEvent callbacks must not throw unhandled exceptions. Wrap the body in `try { ... }` with at minimum a no-op `catch`.

## Comments

Write comments only when the **why** is non-obvious: a hidden Windows constraint, a platform quirk, a workaround for a specific bug. Do not comment what the code does — well-named functions and variables do that. Do not leave TODO or FIXME comments in committed code; use `docs/BUGS.md` instead.

## Committing

- `custom\` is gitignored. Never commit local config or personal scripts from it.
- `lib/Autocorrect.ahk` is auto-generated and gitignored. It is rebuilt automatically on startup when the database is newer.
- `Tiling_Memory.ini` is gitignored (personal state).
- Branch naming: `feat/<short-description>`, `fix/<short-description>`, `chore/<short-description>`.
