# AutoHotkey Script

A personal Windows automation script built on AutoHotkey v2. Includes a CapsLock-based hotkey layer, window tiling, virtual desktop management, text expansion, and camera toggle.

## Requirements

- [AutoHotkey v2](https://www.autohotkey.com/)
- [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor/releases) — place in the same folder as `Master.ahk` (x64 version recommended)
- [PowerToys](https://aka.ms/installpowertoys) — for the color picker (`CapsLock + C`)

## Setup

1. Clone the repo
2. Copy `config.example.ahk` to `config.ahk` and fill in your values
3. Run `Master.ahk`

`config.ahk` is gitignored and will never be committed.

## Highlights & Optimizations

- **Zero-CPU Focus Tracking**: Replaced polling timers with event-driven system hooks.
- **Portability**: Uses environment variables and built-in AHK variables for paths.
- **Instant Toggles**: Pre-initialized WMI objects for lag-free camera toggling.
- **Buffered State**: Desktop focus memory is buffered in RAM and only written to disk on exit to prevent stutters.
- **Native Apps**: Optimized for Electron-based desktop apps (Discord, Spotify, Notion, Slack).

## Hotkeys

### CapsLock Layer
Hold CapsLock to activate. CapsLock itself is disabled — use `Shift + CapsLock` to toggle it.

| Key | Action |
|-----|--------|
| `W / A / S / D` | Arrow keys |
| `Z` | Tile window left half |
| `X` | Tile window right half |
| `F1` | Tile top-left quarter |
| `F2` | Tile top-right quarter |
| `F3` | Tile bottom-left quarter |
| `F4` | Tile bottom-right quarter |
| `F` | Toggle maximize |
| `G` | Float & center (75%) |
| `Tab` | Cycle window layouts |
| `Q` | Close window |
| `` ` `` | Pin / unpin (always on top) |
| `1–9` | Go to virtual desktop 1–9 |
| `Alt + 1–9` | Move window to virtual desktop 1–9 |
| `Left / Right` | Previous / next virtual desktop |
| `M` | Task Manager |
| `T` | Focus or open Windows Terminal |
| `E` | Open File Explorer |
| `R` | Restart Explorer (Shell) |
| `V` | Open VS Code |
| `N` | Apple Music (Toggle) |
| `C` | Color picker (PowerToys) |
| `[` / `]` | Previous / next media track |
| `Space` | Play / pause media |
| `Esc` | Reload script |

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


