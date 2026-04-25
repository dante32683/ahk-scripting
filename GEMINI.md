# GEMINI.md - AutoHotkey Automation Project

This document provides context and guidelines for interacting with this AutoHotkey (AHK) automation project.

## Project Overview

This is a personal Windows automation suite built using **AutoHotkey v2**. It aims to enhance productivity through a "Hyper" layer (via CapsLock), advanced window tiling, and virtual desktop management.

### Key Technologies
- **AutoHotkey v2.0+**: The core scripting language.
- **VirtualDesktopAccessor.dll**: An external library used to programmatically manage Windows 10/11 virtual desktops.
- **PowerToys**: Integrated via hotkeys (e.g., Color Picker).
- **pnputil.exe / PowerShell**: Used for hardware toggles (e.g., Camera).

### Architecture
- `Master.ahk`: The main entry point. It handles script initialization (performance optimizations, admin elevation, event hooks), includes configuration, and defines all hotkeys and logic.
- `Remap.ahk`: Included by `Master.ahk`. Provides macOS-like remaps: common `Alt+<key>` shortcuts send `Ctrl+<key>` when CapsLock is **not** held.
- `config.ahk`: (Gitignored) Contains user-specific variables like email, phone, and hardware IDs.
- `config.example.ahk`: A template for creating `config.ahk`.
- `VirtualDesktopAccessor.dll`: Required for virtual desktop features (switching, moving windows).

---

## Setup & Running

### Prerequisites
1.  Install [AutoHotkey v2](https://www.autohotkey.com/).
2.  Ensure `VirtualDesktopAccessor.dll` is present in the root directory (x64 version is required for 64-bit AHK).
3.  (Optional) Install PowerToys for the `CapsLock + C` color picker shortcut.

### Installation
1.  Copy `config.example.ahk` to `config.ahk`.
2.  Fill in your personal details and hardware IDs in `config.ahk`.
3.  Run `Master.ahk`. The script automatically requests administrator privileges if not already granted.        

---

## Performance Optimizations

- **Event-Driven Focus**: Uses `SetWinEventHook` (`EVENT_SYSTEM_FOREGROUND`) instead of timers for zero-CPU focus tracking.
- **WMI Caching**: Pre-initializes the WMI service at startup to ensure instant camera toggling via the Copilot key.
- **Buffered Disk I/O**: Desktop focus memory is stored in a RAM-based `Map` and only flushed to the INI file on script exit (`OnExit`).
- **Centralized Tiling**: All tiling logic flows through a single `_ApplyLayout` helper for consistency and easier gap/border tuning.
- **Fast Window Detection**: Uses optimized AHK search strings (`ahk_exe`, `ahk_class`) instead of manual window loops.

---

## Development Conventions

### Scripting Standards
- **AHK v2**: Exclusively use v2 syntax. Ensure the `#Requires AutoHotkey v2.0+` directive is at the top of new files.
- **Single Instance**: Use `#SingleInstance Force` to ensure only one instance of the script runs.
- **Performance**: Keep `ListLines 0` and `KeyHistory 0` at the top of `Master.ahk`.
- **Portability**: Use `A_UserName`, `EnvGet("USERPROFILE")`, and other built-in variables instead of hardcoded user paths.
- **Modular Design**: Logic is divided into functional sections:
    - **Optimization & Admin Rights**
    - **DLL Loading (VDA)**
    - **Focus Event Hook**
    - **Helper Functions** (Tiling, Desktop Management, OSD)
    - **Text Expansion**
    - **Hyper Layer** (CapsLock hotkeys)
    - **Hardware Toggles**

### Hotkey Design: The Hyper Layer
The script uses a "Hyper" layer pattern:
- `CapsLock` is mapped to a modifier key. Holding it down activates a secondary layer for `W/A/S/D` navigation and tiling (`Z/X/Y/U/I/O/P`).
- Use `Alt + Shift + CapsLock` to toggle the actual CapsLock state.

### Window Management
- Tiling functions should calculate coordinates based on `MonitorGetWorkArea` to ensure they respect taskbars and multi-monitor setups.
- Use `TileGap` to adjust the aesthetic spacing between windows.
- Virtual desktop functions rely on `DllCall` to `VirtualDesktopAccessor.dll`.
- App launch/activate hotkeys should prefer same-desktop activation: `_HwndOnCurrentDesktop()` / `_ActivateOrRunOnCurrentDesktop()` only re-focus windows on the current virtual desktop, otherwise they launch a new window.
- **Opacity**: Window opacity adjustments (e.g., via scroll wheel) are no longer used or supported.

### Configuration
- Never hardcode personal secrets or environment-specific paths in `Master.ahk`. Use `config.ahk` and prefix configuration variables with `CFG_`.
