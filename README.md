# AutoHotkey Script

A personal Windows automation script built on AutoHotkey v2. Includes a CapsLock-based hotkey layer, modular window tiling (Native AHK or PowerToys FancyZones), virtual desktop management, camera toggle, and an autocorrect engine with per-entry disable support.

## Running

- **Start**: run `Master.ahk` (laptop) or `Master-PC.ahk` (PC). The script auto-elevates to admin.
- **Reload**: hold `CapsLock` then press `Esc` (rebuilds autocorrect first, then force-restarts the script).
- **Soft reset**: hold `CapsLock` then press `R` (rebuilds autocorrect if DB changed; otherwise releases stuck modifiers and unlocks keyboard lock).
- **Restart Explorer**: `CapsLock+Shift+R`.
- **Pause script**: `CapsLock+Shift+Space`.
- **Kill script**: `Ctrl+Esc`.

## Requirements

- [AutoHotkey v2](https://www.autohotkey.com/)
- [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor/releases) — place in the same folder as `Master.ahk` (x64 version)
- [PowerToys](https://aka.ms/installpowertoys) — required only for FancyZones mode

## Setup

1. Clone the repo
2. Create `custom\`
3. Copy `config.example.ahk` to `custom\config.ahk` and fill in your values
4. In `custom\config.ahk`, set `CFG_TilingMode` to `"FancyZones"` or `"Native"`
5. Put personal local scripts in `custom\`
6. Run `Master.ahk`

`custom\` is gitignored and will never be committed.

## Architecture

- **`Master.ahk`** — laptop entry point; includes virtual desktop support
- **`Master-PC.ahk`** — PC entry point; uses monitor focus/move helpers instead of virtual desktops
- **`lib/Core.ahk`** — all shared logic (tiling engine, VDA, focus tracking, CapsLock layer)
- **`lib/WindowTiling_Native.ahk`** — native tiling actions selected by the shared Hyper dispatcher
- **`lib/WindowTiling_FancyZones.ahk`** — FancyZones actions selected by the shared Hyper dispatcher
- **`lib/Build_Autocorrect.ahk`** — rebuilds `lib/Autocorrect.ahk` from `Autocorrect_Database.txt` on startup when the database is newer; force-restarts automatically
- **`lib/Autocorrect.ahk`** — **auto-generated**; all hotstrings wrapped in `#HotIf CFG_Autocorrect`. Never edit directly.
- **`lib/Autocorrect_Logic.ahk`** — runtime: disable and persistence for autocorrect
- **`Autocorrect_Database.txt`** — source of truth; one `trigger->correction` per line, auto-sorted on rebuild
- **`Autocorrect_Disabled.txt`** — persisted disabled entries; loaded on startup
- **`Remap.ahk`** — macOS-style Alt→Ctrl remaps and global shortcuts
- **`custom\config.ahk`** — user-specific values (gitignored)
- **`custom\Core_custom.ahk` / `custom\Master_custom.ahk` / `custom\Master-PC_custom.ahk`** — optional local extensions (gitignored)
- **`custom\*.ahk`** — optional local extensions, usually included by `custom\Master_custom.ahk` or `custom\Master-PC_custom.ahk` (gitignored)

Both tiling files are always included; `CFG_TilingMode` selects actions in the shared Hyper dispatcher.

## Hotkeys

### CapsLock Layer — shared (both machines, both tiling modes)

Hold CapsLock to activate. CapsLock itself is disabled as a toggle — use `Shift+CapsLock` (or `Alt+Shift+CapsLock`) to toggle it.

| Key | Action |
|-----|--------|
| `W / A / S / D` | Arrow Up / Left / Down / Right |
| `Alt+W/A/S/D` | OS Win+Arrow snap (in Native tiling mode, these are used for tiling — see below) |
| `F` | Previous Tab (`Ctrl+PgUp`) |
| `G` | Next Tab (`Ctrl+PgDn`) |
| `B` | Toggle minimize all windows |
| `Shift+B` | 20-20-20 eye break prompt |
| `N` | Hide/show current window (toggle) |
| `M` | Task Manager |
| `Alt+M` | Toggle the persistent Mac Alt remaps |
| `E` | File Explorer or FilePilot (new window) |
| `V` | VS Code (new window) |
| `Alt+V` | Cursor (new window) |
| `T` | Focus/open Terminal (toggle minimize if already focused) |
| `Alt+T` | Open new WSL tab in Terminal |
| `Shift+T` | Open new Terminal window (default profile) |
| `Alt+Shift+T` | Open new Terminal window (WSL, new window) |
| `R` | Soft reset — rebuilds autocorrect if DB changed, else releases modifiers |
| `Shift+R` | Restart `explorer.exe` |
| `Esc` | Rebuild autocorrect + force reload script |
| `` ` `` | Always on Top (`Ctrl+Win+T`) |
| `[` / `]` | Media Previous / Next |
| `Space` | Media Play/Pause |
| `C` | Color picker (`Alt+Shift+C`) |
| `Alt+L` | Toggle keyboard lock (`BlockInput`) |
| `Alt+K` | Toggle privacy blackout overlay |
| `Delete` | Clear session tiling layout for the active window (does not forget app memory) |
| `Shift+Delete` | Forget persistent remembered layout for the active app |
| `Shift+Space` | Toggle script pause |

`CapsLock+Alt+D` keeps the Native tile or FancyZones snap action. Use
`CapsLock+Alt+Shift+D` to open the disabled-correction file.

### Tiling mode behavior

- **`CFG_TilingMode = "Native"`**: `CapsLock+Alt+W/A/S/D` (and friends) performs **native tiling**.
- **`CFG_TilingMode = "FancyZones"`**: `CapsLock+Z/X/P/O` triggers **PowerToys FancyZones** layouts; `CapsLock+Alt+W/A/S/D` uses OS Win+Arrow snap.

### Native Tiling (`CFG_TilingMode = "Native"`)

Hold `CapsLock`, then:

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
| `Alt+F` | Fill the work area without maximize |
| `Alt+Enter` | Toggle maximize |
| `Alt+G` | Float & center |
| `H / J / K / L` | Focus left / down / up / right (skips occluded fullscreen windows behind tiles) |
| `Backspace` | Focus previous window |
| `Tab` | Cycle window layouts |

### FancyZones (`CFG_TilingMode = "FancyZones"`)

Hold `CapsLock`, then:

| Key | Action |
|-----|--------|
| `Z / X / P / O` | Apply FancyZones layout IDs `CFG_FZ_Z/X/P/O` (sends `Ctrl+Alt+Win+<n>`) |
| `Y` | Focus/open Apple Music |
| `Alt+F` | Fill the work area without maximize |
| `G` | Float & center |
| `H / J / K / L` | Focus left / down / up / right (skips occluded fullscreen windows behind tiles) |
| `Backspace` | Focus previous window |
| `Tab` | Cycle zone (sends `Win+Right`) |

### Laptop-specific (`Master.ahk`)

Hold `CapsLock`, then:

| Key | Action |
|-----|--------|
| `Left / Right` | Previous / Next virtual desktop |
| `1–9` | Go to virtual desktop 1–9 |
| `Alt+1–9` | Move active window to desktop 1–9 |
| `\` / `Alt+\` | Optional local network actions, if configured in `custom\` |

### PC-specific (`Master-PC.ahk`)

Hold `CapsLock`, then:

| Key | Action |
|-----|--------|
| `Left / Right` | Focus previous / next monitor |
| `1 / 2 / 3` | Focus monitor 1 / 2 / 3 |
| `Alt+1 / 2 / 3` | Move active window to monitor 1 / 2 / 3 |
| `Q` | Toggle microphone mute |

### Global remaps (`Remap.ahk`) — active in Mac Alt mode when CapsLock is not held

macOS-style `Alt` → `Ctrl` remapping, plus a few direct actions.
Use `CapsLock+Alt+M` to switch between Mac Alt mode and normal Windows Alt behavior.

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
| `Alt+Shift+P` | Command Palette / Advanced Print |
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
| `Alt+Q` | Close window (or delete highlighted window in Alt+Tab) [Disabled in games] |
| `Alt+Shift+Q` | Force kill active app (`ProcessClose`) |
| `Alt+W` | Close tab (smart: only for tabbed apps) or close window [Disabled in games] |
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
| `Alt+Shift+[` / `Alt+Shift+]` | Previous tab / Next tab (or `CapsLock+F/G`) |
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
| `Copilot key` (`Win+Shift+F23`) | Toggle camera on/off (requires `CFG_CameraID`) |
| `CapsLock+Alt+Backspace` (within 15 s) | Permanently disable the last autocorrection |
| `CapsLock+Alt+Shift+D` | Open `Autocorrect_Disabled.txt` to re-enable corrections |

## Notes

- **Admin**: `Master.ahk` auto-elevates to administrator on start.
- **Virtual desktops**: Uses `VirtualDesktopAccessor.dll`. If missing, desktop 1–9 hotkeys are disabled; `Left/Right` fall back to `Ctrl+Win+Left/Right`.
- **App hotkeys**: Launchers only refocus an existing window if it's on the **current** virtual desktop; otherwise they open a new instance.
- **Tiling memory**: In Native mode, windows remember their last tiled position and snap back there on focus. Windows closed while maximized reopen maximized.
- **CapsLock+T terminal**: plain press focuses/opens Terminal; already-focused Terminal is minimized (active window only). Inside VS Code, sends `Ctrl+\`` (integrated terminal).
- **Spatial focus** (`CapsLock+H/J/K/L`): picks the nearest window in that direction. Fullscreen windows behind tiled panes are skipped via edge-distance and overlap heuristics in `FocusDirection`.

## Standalone scripts (run separately)

- `custom\Click.ahk` — simple auto-clicker toggle on `F8`
- `custom\Status.ahk` — optional local status overlay
- `custom\Network_custom.ahk` — optional local network automation, usually included by `custom\Master_custom.ahk` and optionally run via Task Scheduler
- `Setup.ahk` — one-time setup utility
