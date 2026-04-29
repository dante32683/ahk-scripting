# AutoHotkey Script

A personal Windows automation script built on AutoHotkey v2. Includes a CapsLock-based hotkey layer, modular window tiling (Native AHK or PowerToys FancyZones), virtual desktop management, and camera toggle.

## Requirements

- [AutoHotkey v2](https://www.autohotkey.com/)
- [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor/releases) — place in the same folder as `Master.ahk` (x64 version recommended)
- [PowerToys](https://aka.ms/installpowertoys) — required only for FancyZones mode or color picker (`CapsLock + C`)

## Setup

1. Clone the repo
2. Copy `config.example.ahk` to `config.ahk` and fill in your values
3. In `config.ahk`, set `CFG_TilingMode` to `"FancyZones"` or `"Native"`
4. Run `Master.ahk`

`config.ahk` is gitignored and will never be committed.

## Architecture

- **`Master.ahk`** — laptop entry point; includes Eye202020 timer
- **`Master-PC.ahk`** — PC entry point; includes multi-monitor helpers; stubs out Eye202020
- **`lib/Core.ahk`** — all shared logic (tiling engine, VDA, focus tracking, CapsLock layer)
- **`lib/WindowTiling_FancyZones.ahk`** — FancyZones hotkeys (active when `CFG_TilingMode = "FancyZones"`)
- **`lib/WindowTiling_Native.ahk`** — native AHK tiling hotkeys (active when `CFG_TilingMode = "Native"`)
- **`Remap.ahk`** — macOS-style Alt→Ctrl remaps and global shortcuts
- **`config.ahk`** — user-specific values (gitignored)

Both tiling files are always included; `CFG_TilingMode` in `config.ahk` gates which hotkey set is active. No commenting/uncommenting needed.

## Hotkeys

### CapsLock Layer
Hold CapsLock to activate. CapsLock itself is disabled — use `Shift + CapsLock` (or `Alt + Shift + CapsLock`) to toggle it.

| Key | Action (Native Mode) | Action (FancyZones Mode) |
|-----|----------------------|--------------------------|
| `W / A / S / D` | Arrow keys | Arrow keys |
| `Alt + W/A/S/D` | Win snap Up/Left/Down/Right | Win snap Up/Left/Down/Right |
| `H / J / K / L` | Focus Left/Down/Up/Right | Focus Left/Down/Up/Right |
| `Z` | Tile left half | Snap to Zone 1 (`^!#1`) |
| `X` | Tile right half | Snap to Zone 2 (`^!#2`) |
| `F1–F4` | Tile quadrants | (Disabled) |
| `F` | Toggle maximize | Toggle maximize |
| `G` | Float & center (75%) | Float & center (75%) |
| `Tab` | Cycle window layouts | Next FancyZone (`#{Right}`) |
| `1–9` | Go to virtual desktop 1–9 | Go to virtual desktop 1–9 |
| `Shift + 1–9` | Move to desktop 1–9 | Move to desktop 1–9 |
| `Left / Right` | Prev/Next desktop | Prev/Next desktop |
| `` ` `` | Always on Top (`^#t`) | Always on Top (`^#t`) |
| `M` | Task Manager | Task Manager |
| `T` | Focus/Open Terminal | Focus/Open Terminal |
| `E` | Open File Explorer | Open File Explorer |
| `R` | Soft reset | Soft reset |
| `V` | Open VS Code | Open VS Code |
| `Y` | Tile left 60% | Apple Music |
| `Esc` | Reload script | Reload script |

### Global (Alt remaps — active when CapsLock is not held)
| Key | Action |
|-----|--------|
| `Alt + Q` | Close window (or close highlighted window in Alt+Tab switcher) |
| `Alt + W` | Close tab (`^w`) |
| `Alt + J` | Alt+Shift+L (window arrange) |
| `Alt + K` | Alt+Shift+H (window arrange) |
| `Alt + C/X/V` | Copy / Cut / Paste |
| `Alt + Shift + V` | Paste as plain text |
| `Alt + Z / Y` | Undo / Redo |
| `Alt + Shift + Z` | Redo (macOS-style) |
| `Alt + A` | Select All |
| `Alt + S` | Save |
| `Alt + F` | Find |
| `Alt + M` | Minimize window |
| `Alt + Left/Right` | Home / End (start/end of line) |
| `Alt + Shift + Left/Right` | Select word by word (`^+Left/Right`) |
| `Alt + Up/Down` | Ctrl+Home / Ctrl+End (top/bottom of document) |
| `Alt + Shift + Up/Down` | Select to top/bottom of document |
| `Alt + Backspace` | Delete whole word backwards |
| `` Alt + ` `` | Cycle to next window of the same app |
| `` Alt + Shift + ` `` | Cycle to previous window of the same app |
| `Alt + Enter` | Send / Submit (`^Enter`) |
| `Ctrl + Esc` | Kill script |
| `Copilot key` | Toggle camera on/off |

## Notes

- **Admin**: `Master.ahk` auto-elevates to administrator on start.
- **Virtual desktops**: Desktop switching/moving uses `VirtualDesktopAccessor.dll`. If the DLL is missing, desktop `1–9` hotkeys are disabled and the script falls back to `Ctrl+Win+Left/Right` for prev/next desktop.
- **App hotkeys and virtual desktops**: App launchers only refocus an existing window if it's on the **current** virtual desktop; otherwise they open a new window.
- **Alt remaps (macOS-like)**: `Remap.ahk` maps common `Alt+<key>` combos to `Ctrl+<key>` (and a few direct actions) when CapsLock is not held, emulating macOS Command key bindings.
