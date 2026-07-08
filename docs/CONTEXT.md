# Context

## What This Repo Is

A personal Windows automation script built on AutoHotkey v2. It runs on two machines — a laptop and a PC — with a shared core library and machine-specific entry points. The main things it does:

- Adds a CapsLock-based hotkey layer for tiling, app launching, and system control.
- Remaps Alt to Ctrl globally to mirror macOS muscle memory.
- Tiles windows using either a native AHK engine or PowerToys FancyZones.
- Tracks window positions and restores them automatically on focus.
- Provides an autocorrect engine with per-entry disable.
- Toggles the laptop camera via `pnputil.exe`.
- Manages virtual desktops (laptop) or monitor switching (PC).

## Why CapsLock As A Modifier

CapsLock is the best available modifier on a standard keyboard for this use case:

- It is physically large and easy to reach without looking.
- It is not used by any application as a functional key.
- AHK v2 can intercept it before the OS sees it, so holding it does not toggle CapsLock.
- It does not conflict with any standard Ctrl/Alt/Win shortcuts.

Shift+CapsLock (or Alt+Shift+CapsLock) toggles CapsLock state when actually needed.

## Why Two Entry Points

The laptop and PC have fundamentally different setups:

- The laptop uses virtual desktops (via `VirtualDesktopAccessor.dll`); the PC uses multiple monitors.
- CapsLock+Left/Right switches virtual desktops on the laptop and focuses monitors on the PC.
- CapsLock+1–9 navigates to desktops on the laptop and focuses monitors 1–3 on the PC.

`Master.ahk` and `Master-PC.ahk` handle these differences. All logic that applies to both machines lives in `lib/Core.ahk`.

## Why Native Tiling Over FancyZones

FancyZones works well, but native tiling gives more direct control:

- Tiling positions are defined in code as fractional percentages (`xf/yf/wf/hf`), not in a GUI config file.
- Adding a new layout is a one-liner calling `_ApplyLayout`.
- Positions are remembered per-app and restored automatically on focus without any external service.
- The native engine can be extended (e.g., per-instance caching for multi-window apps) without depending on PowerToys internals.

FancyZones mode is preserved for users who prefer it. `CFG_TilingMode` gates which hotkey block is active.

## Why Fractional Coordinates

Tiling positions are stored as percentages of monitor dimensions (0–100), not pixel values. This means layouts survive monitor resolution changes and DPI adjustments without needing to be recalibrated. See `ARCHITECTURE.md § Tiling Memory` for the full system.

## VirtualDesktopAccessor And Its Fragility

Virtual desktop switching uses `VirtualDesktopAccessor.dll` (an open-source DLL that wraps undocumented Windows COM interfaces). This is the only reliable way to move windows between virtual desktops programmatically on Windows 11. The tradeoffs:

- The DLL can break on major Windows updates because the underlying COM interfaces are not public API.
- If the DLL is missing or broken, CapsLock+1–9 and CapsLock+Left/Right fall back to `Ctrl+Win+Left/Right` (navigation only; window moving is disabled).
- The script degrades gracefully — all other features continue working.

## Why AHK v2

AHK v1 is in maintenance-only mode and has fundamental syntax limitations. v2 fixes those (proper functions, OOP, Maps, typed variables) and is the active development branch. All files in this repo require `#Requires AutoHotkey v2.0+`.

## The Autocorrect Engine

The autocorrect engine exists because Windows has no native system-wide autocorrect for desktop apps. The design:

- A plain-text database (`Autocorrect_Database.txt`) is the only file a user edits.
- A build step generates `lib/Autocorrect.ahk` from the database so the hotstring list is always in sync.
- Users can permanently disable a correction (`CapsLock+Alt+Backspace`) without editing any file.
- The generated file is gitignored, and the script builds or rebuilds it automatically on startup if the database is newer or missing.

## The macOS Remap Layer

`Remap.ahk` remaps Alt to Ctrl for common editing shortcuts (copy, paste, undo, save, close tab, etc.) to match macOS muscle memory on Windows. It is always active when CapsLock is not held. Smart logic distinguishes between closing a tab (Alt+W) and closing a window (Alt+Q) based on which app is focused.
