# AutoHotkey Script

A personal Windows automation script built on AutoHotkey v2. Includes a CapsLock-based hotkey layer, modular window tiling (Native AHK or PowerToys FancyZones), virtual desktop management, camera toggle, and an autocorrect engine with undo/disable support.

## Requirements

- [AutoHotkey v2](https://www.autohotkey.com/)
- [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor/releases) — place in the same folder as `Master.ahk` (x64 version)
- [PowerToys](https://aka.ms/installpowertoys) — required only for FancyZones mode

## Setup

1. Clone the repo
2. Copy `config.example.ahk` to `config.ahk` and fill in your values
3. In `config.ahk`, set `CFG_TilingMode` to `"FancyZones"` or `"Native"`
4. Run `Master.ahk`

`config.ahk` is gitignored and will never be committed.

## Architecture

- **`Master.ahk`** — laptop entry point; includes Eye202020 timer
- **`Master-PC.ahk`** — PC entry point; stubs out Eye202020; no virtual desktops
- **`lib/Core.ahk`** — all shared logic (tiling engine, VDA, focus tracking, CapsLock layer)
- **`lib/WindowTiling_Native.ahk`** — native AHK tiling hotkeys (active when `CFG_TilingMode = "Native"`)
- **`lib/WindowTiling_FancyZones.ahk`** — FancyZones passthrough hotkeys (active when `CFG_TilingMode = "FancyZones"`)
- **`lib/Build_Autocorrect.ahk`** — rebuilds `lib/Autocorrect.ahk` from `Autocorrect_Database.txt` on startup when the database is newer; reloads automatically
- **`lib/Autocorrect.ahk`** — **auto-generated**; all hotstrings wrapped in `#HotIf CFG_Autocorrect`. Never edit directly.
- **`lib/Autocorrect_Logic.ahk`** — runtime: undo, disable, and persistence for autocorrect
- **`Autocorrect_Database.txt`** — source of truth; one `trigger->correction` per line, auto-sorted on rebuild
- **`Autocorrect_Disabled.txt`** — persisted disabled entries; loaded on startup
- **`Remap.ahk`** — macOS-style Alt→Ctrl remaps and global shortcuts
- **`config.ahk`** — user-specific values (gitignored)

Both tiling files are always included; `CFG_TilingMode` gates which hotkey set is active.

## Hotkeys

### CapsLock Layer — shared (both machines, both tiling modes)

Hold CapsLock to activate. CapsLock itself is disabled as a toggle — use `Shift+CapsLock` (or `Alt+Shift+CapsLock`) to toggle it.

| Key | Action |
|-----|--------|
| `W / A / S / D` | Arrow Up / Left / Down / Right |
| `Alt+W/A/S/D` | Win+Arrow snap (overridden in Native tiling mode — see below) |
| `F` | Previous Tab (`Ctrl+PgUp`) |
| `G` | Next Tab (`Ctrl+PgDn`) |
| `B` | Toggle minimize all windows |
| `Shift+B` | 20-20-20 eye break prompt |
| `N` | Hide/show current window (toggle) |
| `M` | Task Manager |
| `E` | File Explorer (new window) |
| `V` | VS Code (new window) |
| `T` | Focus/open Terminal (toggle minimize if already focused) |
| `Alt+T` | Open new Debian tab in Terminal |
| `Alt+Shift+T` | Open new Terminal window (Debian, new window) |
| `R` | Soft reset — rebuilds autocorrect if DB changed, else releases modifiers |
| `Shift+R` | Restart `explorer.exe` |
| `Esc` | Rebuild autocorrect + force reload script |
| `` ` `` | Always on Top (`Ctrl+Win+T`) |
| `[` / `]` | Media Previous / Next |
| `Space` | Media Play/Pause |
| `C` | Color picker (`Alt+Shift+C`) |
| `Alt+L` | Toggle keyboard lock (`BlockInput`) |
| `Delete` | Clear tiling layout for active window |
| `Shift+Space` | Toggle script pause |

### Native Tiling additions (`CFG_TilingMode = "Native"`)

These override the `Alt+W/A/S/D` Win-snap hotkeys when in Native mode.

| Key | Action |
|-----|--------|
| `Alt+W` | Tile top half |
| `Alt+A` | Tile left half |
| `Alt+S` | Tile bottom half |
| `Alt+D` | Tile right half |
| `Alt+Q` | Tile top-left quadrant |
| `Alt+E` | Tile top-right quadrant |
| `Alt+Z` | Tile bottom-left quadrant |
| `Alt+C` | Tile bottom-right quadrant |
| `Alt+U` | Tile left third |
| `Alt+I` | Tile center third |
| `Alt+O` | Tile right third |
| `Alt+Y` | Tile left 60% |
| `Alt+P` | Tile right 40% |
| `Alt+F` / `Alt+Enter` | Toggle maximize |
| `Alt+G` | Float & center |
| `H / J / K / L` | Focus left / down / up / right |
| `Backspace` | Focus previous window |
| `Tab` | Cycle window layouts |

### Laptop-specific (`Master.ahk`)

| Key | Action |
|-----|--------|
| `Left / Right` | Previous / Next virtual desktop |
| `1–9` | Go to virtual desktop 1–9 |
| `Alt+1–9` | Move active window to desktop 1–9 |
| `\` | Toggle Tailscale auto-switch scheduled task |

### PC-specific (`Master-PC.ahk`)

| Key | Action |
|-----|--------|
| `Left / Right` | Focus previous / next monitor |
| `1 / 2 / 3` | Focus monitor 1 / 2 / 3 |
| `Alt+1 / 2 / 3` | Move active window to monitor 1 / 2 / 3 |

### Global remaps (`Remap.ahk`) — active when CapsLock is not held

macOS-style `Alt` → `Ctrl` remapping, plus a few direct actions.

**Editing**
| Key | Action |
|-----|--------|
| `Alt+C/X/V` | Copy / Cut / Paste |
| `Alt+Shift+V` | Paste as plain text |
| `Alt+Z` | Undo |
| `Alt+Y` / `Alt+Shift+Z` | Redo |
| `Alt+A` | Select All |
| `Alt+B / I / U` | Bold / Italic / Underline |
| `Alt+/` | Toggle comment |
| `Alt+Backspace` | Delete word backwards |

**File / Document**
| Key | Action |
|-----|--------|
| `Alt+S` | Save |
| `Alt+Shift+S` | Save As |
| `Alt+O` | Open |
| `Alt+P` | Print |
| `Alt+N` | New file/window |
| `Alt+Shift+N` | New incognito/private window |
| `Alt+,` | Preferences/Settings |

**Find**
| Key | Action |
|-----|--------|
| `Alt+F` | Find |
| `Alt+Shift+F` | Find in Files |
| `Alt+G` / `Alt+Shift+G` | Find Next / Find Previous |
| `Alt+H` | Replace |

**Window / Tab Management**
| Key | Action |
|-----|--------|
| `Alt+Q` | Close window (or delete highlighted window in Alt+Tab) |
| `Alt+Shift+Q` | Force kill active app (`ProcessClose`) |
| `Alt+W` | Close tab (smart: only for tabbed apps) or close window |
| `Alt+Shift+W` | Close all tabs / window (`Ctrl+Shift+W`) |
| `Alt+T` | New tab |
| `Alt+Shift+T` | Restore closed tab |
| `Alt+M` | Minimize window |
| `Alt+R` | Refresh/Reload |
| `Alt+Shift+R` | Hard refresh |
| `` Alt+` `` | Cycle to next window of same app |
| `` Alt+Shift+` `` | Cycle to previous window of same app |

**Text Cursor (macOS style)**
| Key | Action |
|-----|--------|
| `Alt+Left / Right` | Home / End (start/end of line) |
| `Alt+Shift+Left / Right` | Select word by word |
| `Alt+Up / Down` | Top / Bottom of document |
| `Alt+Shift+Up / Down` | Select to top / bottom of document |

**Browser / Navigation**
| Key | Action |
|-----|--------|
| `Alt+L` | Focus address bar |
| `Alt+D` | Bookmark |
| `Alt+Shift+B` | Toggle bookmarks bar |
| `Alt+[` / `Alt+]` | Back / Forward |
| `Alt+Shift+[` / `Alt+Shift+]` | Previous tab / Next tab |
| `Alt+1–9` | Switch to tab 1–9 |
| `Alt+LButton` | Ctrl+Click (open link in new tab) |

**View**
| Key | Action |
|-----|--------|
| `Alt+=` | Zoom In |
| `Alt+-` | Zoom Out |
| `Alt+0` | Reset zoom |

**Other**
| Key | Action |
|-----|--------|
| `Alt+Enter` | Send/Submit (`Ctrl+Enter`) |
| `Ctrl+Esc` | Kill script |
| `Copilot key` | Toggle camera on/off |
| `Backspace` (within 2 s of autocorrect) | Undo last autocorrection |
| `CapsLock+Alt+Backspace` | Permanently disable the last autocorrection |
| `CapsLock+Alt+D` | Open `Autocorrect_Disabled.txt` to re-enable corrections |

## Notes

- **Admin**: `Master.ahk` auto-elevates to administrator on start.
- **Virtual desktops**: Uses `VirtualDesktopAccessor.dll`. If missing, desktop 1–9 hotkeys are disabled; `Left/Right` fall back to `Ctrl+Win+Left/Right`.
- **App hotkeys**: Launchers only refocus an existing window if it's on the **current** virtual desktop; otherwise they open a new instance.
- **Tiling memory**: In Native mode, windows remember their last tiled position and snap back there on focus. Windows closed while maximized reopen maximized.
- **CapsLock+T terminal**: plain press focuses/opens Terminal; already-focused Terminal is minimized. Inside VS Code, sends `Ctrl+\`` (integrated terminal).
