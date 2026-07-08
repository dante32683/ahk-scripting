# Documentation Hub

This repo is a personal Windows automation script built on AutoHotkey v2. It runs on two machines (laptop and PC) from separate entry points that share a common core library.

The docs here are the authoritative reference for all code in this repo.

## Read Order

1. `CONTEXT.md` — what this script is, why it is built the way it is, and key design decisions.
2. `ARCHITECTURE.md` — file layout, module relationships, startup sequence, data flows, and global state.
3. `RUNBOOK.md` — setup, daily operations, and how to extend the script.
4. `CONVENTIONS.md` — AHK v2 style rules, naming conventions, and what goes where.
5. `BUGS.md` — active issue ledger and known behavioral quirks.

## Source Files

### Entry Points

- `Master.ahk` — laptop entry point. Includes virtual desktop support.
- `Master-PC.ahk` — PC entry point. Uses monitor switching instead of virtual desktops.

### Core Library

- `lib/Core.ahk` — all shared logic: tiling engine, VDA integration, focus tracking, CapsLock layer, app launchers, camera toggle, keyboard lock.
- `lib/WindowTiling_Native.ahk` — native AHK tiling hotkeys. Active when `CFG_TilingMode = "Native"`.
- `lib/WindowTiling_FancyZones.ahk` — FancyZones passthrough hotkeys. Active when `CFG_TilingMode = "FancyZones"`.
- `lib/ShowOSD.ahk` — `ShowOSD(text, ms)` helper for user-facing notifications.

### Autocorrect System

- `Autocorrect_Database.txt` — source of truth; one `trigger->correction` per line, auto-sorted on rebuild.
- `lib/Build_Autocorrect.ahk` — rebuilds `lib/Autocorrect.ahk` on startup when the database is newer. Force-restarts after rebuild.
- `lib/Autocorrect.ahk` — **auto-generated and gitignored**. Never edit directly. Rebuilt on startup when the database is newer.
- `lib/Autocorrect_Logic.ahk` — runtime: disable and persistence for corrections.
- `Autocorrect_Disabled.txt` — persisted disabled entries; loaded on startup.

### Global Remaps

- `Remap.ahk` — macOS-style Alt→Ctrl remapping and smart window/tab closing logic. Included by both entry points.

### Configuration

- `custom/config.ahk` — user-specific values. Gitignored; copy from `config.example.ahk`.
- `config.example.ahk` — template with all required variables.
- `custom/Core_custom.ahk`, `custom/Master_custom.ahk`, `custom/Master-PC_custom.ahk` — optional local extensions. Gitignored.

### Standalone and Optional Scripts

- `custom/Click.ahk` — simple auto-clicker toggle on F8 (gitignored).
- `custom/Status.ahk` — optional local status overlay (gitignored).
- `custom/Network_custom.ahk` — optional local network automation, usually included by `custom/Master_custom.ahk` and optionally run via Task Scheduler (gitignored).
- `Setup.ahk` — one-time setup utility.

## Planning Documents

- `plans/` — local planning notes and reference docs. Not authoritative unless content is copied into a canonical doc.

## Authority Levels

- Canonical: `ARCHITECTURE.md`, `RUNBOOK.md`, `CONVENTIONS.md`
- Operational: `BUGS.md`
- Historical / reference: `plans/`
