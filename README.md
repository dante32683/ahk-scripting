# AutoHotkey Script

A personal Windows automation script built on AutoHotkey v2. Includes a CapsLock-based hotkey layer, modular window tiling (Native or PowerToys FancyZones), virtual desktop management, text expansion, and camera toggle.

## Requirements

- [AutoHotkey v2](https://www.autohotkey.com/)
- [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor/releases) — place in the same folder as `Master.ahk` (x64 version recommended)
- [PowerToys](https://aka.ms/installpowertoys) — for FancyZones or the color picker (`CapsLock + C`)

## Setup

1. Clone the repo
2. Copy `config.example.ahk` to `config.ahk` and fill in your values
3. **Choose Tiling Mode**: Open `lib/Core.ahk` and scroll to the bottom. Uncomment your preferred version:
   - `lib/WindowTiling_Native.ahk`: Full AutoHotkey-driven automated tiling with drift correction.
   - `lib/WindowTiling_FancyZones.ahk`: Replaces native tiling with hotkeys that trigger PowerToys FancyZones.
4. Run `Master.ahk`

`config.ahk` is gitignored and will never be committed.

## Hotkeys

### CapsLock Layer
Hold CapsLock to activate. CapsLock itself is disabled — use `Alt + Shift + CapsLock` to toggle it.

| Key | Action (Native Mode) | Action (FancyZones Mode) |
|-----|----------------------|--------------------------|
| `W / A / S / D` | Arrow keys | Arrow keys |
| `Z` | Tile left half | Snap to Zone 1 (`^!#1`) |
| `X` | Tile right half | Snap to Zone 2 (`^!#2`) |
| `F1–F4` | Tile quadrants | (Disabled) |
| `F` | Toggle maximize | Snap to Zone 0 (`^!#0`) |
| `G` | Float & center (75%) | Snap to Zone 3 (`^!#3`) |
| `Tab` | Cycle window layouts | Next FancyZone (`#{Right}`) |
| `1–9` | Go to virtual desktop 1–9 | Go to virtual desktop 1–9 |
| `Shift + 1–9` | Move to desktop 1–9 | Move to desktop 1–9 |
| `Left / Right` | Prev/Next desktop | Prev/Next desktop |
| `Q` | Close window | Close window |
| `` ` `` | Pin / unpin | Pin / unpin |
| `M` | Task Manager | Task Manager |
| `T` | Focus/Open Terminal | Focus/Open Terminal |
| `E` | Open File Explorer | Open File Explorer |
| `R` | Soft reset | Soft reset |
| `V` | Open VS Code | Open VS Code |
| `Y` | (Native Tiling) | Apple Music |
| `Esc` | Reload script | Reload script |

### Global
| Key | Action |
|-----|--------|
| `Ctrl + Esc` | Kill script |
| `Copilot key` | Toggle camera on/off |

### Text Expansion
| Trigger | Output |
|---------|--------|
| `@@` | Email address (from config) |
| `#ph` | Phone number (from config) |
| `\deg` | ° |
| `\delta` | Δ |
| `\pi` | π |
| `\approx` | ≈ |
| `\theta` | θ |
| `\sigma` | σ |

## Notes

- **Admin**: `Master.ahk` auto-elevates to administrator on start.
- **Virtual desktops**: Desktop switching/moving uses `VirtualDesktopAccessor.dll`. If the DLL is missing, desktop `1–9` hotkeys are disabled and the script falls back to the built-in `Ctrl+Win+Left/Right` behavior for prev/next desktop.
- **App hotkeys and virtual desktops**: App launchers in the CapsLock layer only refocus an existing app window if it’s on your **current** virtual desktop; otherwise they open a new window instead of switching desktops.
- **Alt remaps (macOS-like)**: `Remap.ahk` is included by `Master.ahk` and remaps common `Alt+<key>` combos to `Ctrl+<key>` when **CapsLock is not held** to emulate macOS Command key bindings. This includes standard editing (copy/paste), browser navigation (tabs, bookmarks, history), app operations (save, find, new window, preferences), text formatting (bold, link), and macOS-style cursor movement (Cmd+Arrows, Cmd+Backspace/Delete, Cmd+Enter).


