# AGENTS.md

Canonical entry point for all AI agents working in this repository.

## Pre-Flight

Before starting any task:

1. Read `docs/CONTEXT.md` — what the script is and why it is built the way it is.
2. Read `docs/ARCHITECTURE.md` — file layout, module breakdown, data flows, global state.
3. Read `docs/RUNBOOK.md` — setup, daily ops, and how to extend the script.
4. Read `docs/CONVENTIONS.md` — AHK v2 rules, naming, and what goes where.
5. Read `docs/BUGS.md` — active issue ledger and known risks.

For short tasks (one hotkey, one autocorrect entry), reading `ARCHITECTURE.md` and `CONVENTIONS.md` is sufficient.

## Quick Reference

- **Start / Reload**: `Master.ahk` (laptop) or `Master-PC.ahk` (PC). Reload with `CapsLock+Esc`.
- **No build step** — AHK scripts are interpreted directly. The only build step is autocorrect generation, which runs automatically on reload when the database is newer.
- **Shared logic** → `lib/Core.ahk`. Laptop-only → `Master.ahk`. PC-only → `Master-PC.ahk`.
- **Tiling** → call `_ApplyLayout(xf, yf, wf, hf, hwnd, true)`. All values are percentages 0–100.
- **OSD notifications** → `ShowOSD(text, ms)`. Never call `ToolTip` directly.
- **Config values** → `custom\config.ahk`, prefixed `CFG_`. The whole `custom\` folder is gitignored. Never commit it.

## Gemini Helper

Gemini CLI is available through `tools/gemini-subagent.ps1` for bounded advisory work. Use it when the user asks for a cheap side review or second-pass analysis.

```powershell
.\tools\gemini-subagent.ps1 -Mode Review -Prompt "Review the current git diff for likely bugs. Return only concrete findings."
```

Treat Gemini output as advisory only. Verify claims locally before changing code.
