# AHK Refactor Plan: Laptop + PC Dual-Config

## Goal

Split the current monolithic `Master.ahk` into a shared library plus two machine-specific
entry points: `Master.ahk` (laptop, unchanged from the task scheduler's perspective) and
`Master-PC.ahk` (gaming PC, multi-monitor). Add `Setup.ahk` to auto-register the Task
Scheduler startup task on a fresh machine.

---

## Resulting File Structure

```
AutoHotkey/
├── Master.ahk             ← Laptop entry point (thin wrapper + laptop-only hotkeys)
├── Master-PC.ahk          ← PC entry point (thin wrapper + PC-only hotkeys)  [NEW]
├── Setup.ahk              ← Auto-registers Task Scheduler task on new machine  [NEW]
├── Remap.ahk              ← macOS-style Alt→Ctrl remaps (shared, unchanged)
├── config.ahk             ← Machine-specific values (gitignored)
├── lib/
│   ├── Core.ahk           ← All shared functions, globals, and base hotkeys  [NEW]
│   └── Eye202020.ahk      ← 20-20-20 eye break + MenuBar IPC (laptop only)   [NEW]
├── VirtualDesktopAccessor.dll
├── .gitignore
└── CLAUDE.md
```

`Camera.ahk` is NOT extracted as a separate file. The camera toggle hotkey (`#+F23`) is
small enough to live inline in `Master.ahk`. Same for the Tailscale toggle (`*\::`).

---

## What Goes Where

### `lib/Core.ahk` — Shared (everything both machines need)

Extract the following from `Master.ahk`:

| Content | Approx. lines in current Master.ahk |
|---|---|
| Performance settings (`ListLines`, `KeyHistory`, `ProcessSetPriority`, etc.) | 10–17 |
| Admin elevation block | 22–25 |
| VDA loading (`GoToDesktopNumber`, etc.) | 30–55 |
| `ReleaseModifiers` + `OnExit` registration | 60–66 |
| `PnPUtilPath` + `WMI_Service` globals (camera vars, but NOT the hotkey) | 71–82 |
| `ShowOSD` start message | 83 |
| Focus event hooks (`SetWinEventHook` for FOREGROUND, MOVESIZESTART, MOVESIZEEND) | 88–131 |
| All `OnExit` registrations (`SaveDesktopMemory`, `_SaveLayouts`, etc.) | 123–131 |
| `SaveDesktopMemory`, `_SaveLayouts`, `_PersistLayout`, `_DeletePersistedLayout` | 133–166 |
| All globals (`TileGap`, `FocusHistory`, `g_*`, `DesktopLastWindow`, etc.) | 171–211 |
| `_LoadLayoutsFrom` + initial layout load | 234–256 |
| `g_LastDesktop` init | 258–260 |
| Timer setup (`SetTimer(_CheckLayoutRestores, 2000)`) | 265 |
| `_Dbg`, `_WinSig` | 271–286 |
| `_IsLiveWindow`, `_GetWindowState`, `_GetExpectedOuterPos` | 288–343 |
| `_NeedsAutoRestore`, `_AutoRestoreWindow`, `_ScheduleAutoRestore` | 345–378 |
| `ShowOSD` function | 385–389 |
| `ToggleScriptPaused` | 391–401 |
| `_SendWinShift` | 875–881 |
| `RunAsUser`, `_HwndOnCurrentDesktop`, `_ActivateOrRunOnCurrentDesktop` | 888–929 |
| `_KL_On`, `_KL_Off`, `_KL_CheckUnlock`, `SoftReset` | 934–977 |
| `GetActiveMonitorWorkArea`, `_GetMonitorForHwnd`, `PrepareWindow` | 979–1015 |
| `_ApplyLayout` | 1017–1102 |
| `_RestoreDesktop`, `_RestoreAllDesktops`, `_RestoreCurrentDesktop` | 1104–1172 |
| `_ScheduleDesktopRestore`, `_ScheduleRestoreCurrentDesktop` | 1174–1185 |
| `_OnSettingChange`, `_OnPowerBroadcast`, `_OnDisplayChange` | 1187–1259 |
| `_OnMoveStart`, `_OnMoveEnd`, `_CheckLayoutRestores` | 1261–1314 |
| `_HandleDesktopChange` | 1316–1332 |
| Tile shorthand functions (`TileLeft`, `TileRight`, etc. through `FloatCenter`) | 1336–1347 |
| `ToggleMaximize`, `TogglePin` | 1349–1364 |
| `GotoDesktop`, `RestoreFocusOnDesktop`, `MoveToDesktop` | 1366–1413 |
| `FocusDirection` | 1415–1473 |
| `TrackFocusHistory`, `FocusJumpBack` | 1475–1504 |
| `CycleLayout` | 1506–1516 |
| Emergency kill switch (`^Esc::`) | 1521–1524 |
| Pause/resume `#SuspendExempt` block | 1532–1536 |
| CapsLock config (`*CapsLock::`, `!+CapsLock::`) | 1541–1548 |
| Text expansion hotstrings (`#ph`, `\deg`, `\delta`, etc.) | 1553–1560 |
| **Entire shared Hyper Layer block** (`#HotIf GetKeyState("CapsLock", "P")`) containing: | 1590–1843 |
| — WASD arrows | 1592–1596 |
| — Tiling: Z, X, F1–F4, Y, U, I, O, P, Tab | 1634–1650 |
| — Focus: H, J, K, L, Backspace | 1652–1657 |
| — Window control: B, +B, F, G, \`, Q, Delete | 1659–1685 |
| — Media: [, ], Space, C | 1687–1691 |
| — Apps: V, N, M, E, T, +T | 1701–1799 |
| — R (SoftReset), +R (restart explorer) | 1801–1811 |
| — Esc (reload script) | 1834–1841 |
| Keyboard lock intercept block (`#HotIf g_KeyLockActive`) | 1854–1862 |

**NOT included in Core.ahk:**
- CapsLock+1–9 (GotoDesktop) — machine-specific key mapping
- CapsLock+Left/Right (prev/next desktop or monitor) — machine-specific
- CapsLock+Alt+1–9 (MoveToDesktop) — machine-specific
- Tailscale toggle (`*\::`) — laptop only
- Camera toggle (`#+F23::`) — laptop only
- 20-20-20 globals and functions — goes in `lib/Eye202020.ahk`
- WMI init code block — stays in entry point (needed for camera; skipped on PC)

---

### `lib/Eye202020.ahk` — Eye Break Reminder (laptop only)

Extract all 20-20-20 code from `Master.ahk` lines 179–873:

- All `g_202020_*` globals
- All `_202020_*` functions
- `_202020_RegisterDisplayNotifications`
- Named pipe IPC (`_202020_TryConnectStatePipe`, `_202020_WriteState`, `_202020_PollCmd`, etc.)

**Important:** `_202020_Init()` call (line 263) stays in the entry point startup sequence,
not in the file itself. The file defines the functions; the entry point calls Init.

The WM_POWERBROADCAST handler in `lib/Core.ahk` calls `_202020_Reset` — this means
`lib/Core.ahk` must be included AFTER `lib/Eye202020.ahk`, or the function reference
must be guarded with `IsSet`. Simplest fix: `lib/Eye202020.ahk` is included first in
both entry points, so the function exists when `Core.ahk` sets up `OnMessage`. On PC
where Eye202020 is not included, replace the `_OnPowerBroadcast` call to `_202020_Reset`
with a no-op by declaring a stub in `Master-PC.ahk` before including `Core.ahk`:

```ahk
; Stub so Core.ahk's _OnPowerBroadcast doesn't crash on PC (no 20-20-20)
_202020_Reset(*) => 0
```

---

### `Master.ahk` — Laptop Entry Point (refactored)

After refactoring, `Master.ahk` becomes thin:

```ahk
#Requires AutoHotkey v2.0+
#SingleInstance Force
#WinActivateForce
#Include config.ahk
#Include lib/Eye202020.ahk
#Include lib/Core.ahk
#Include Remap.ahk

; WMI pre-init for camera toggle
global WMI_Service := 0
try {
    WMI_Service := ComObjGet("winmgmts:")
} catch {
    ShowOSD("Warning: WMI init failed. Camera toggle may not work.", 3000)
}

_202020_Init()

; ============================================================
; LAPTOP-SPECIFIC HYPER LAYER EXTENSIONS
; (appended inside an additional #HotIf block)
; ============================================================
#HotIf GetKeyState("CapsLock", "P")

; Virtual desktop switching
Left:: {
    if GetCurrentDesktopNumber
        GotoDesktop(Max(1, DllCall(GetCurrentDesktopNumber)))
    else
        Send "^#{Left}"
}
Right:: {
    if GetCurrentDesktopNumber
        GotoDesktop(Min(9, DllCall(GetCurrentDesktopNumber) + 2))
    else
        Send "^#{Right}"
}

1:: GotoDesktop(1)
2:: GotoDesktop(2)
3:: GotoDesktop(3)
4:: GotoDesktop(4)
5:: GotoDesktop(5)
6:: GotoDesktop(6)
7:: GotoDesktop(7)
8:: GotoDesktop(8)
9:: GotoDesktop(9)

*!1:: MoveToDesktop(1)
*!2:: MoveToDesktop(2)
*!3:: MoveToDesktop(3)
*!4:: MoveToDesktop(4)
*!5:: MoveToDesktop(5)
*!6:: MoveToDesktop(6)
*!7:: MoveToDesktop(7)
*!8:: MoveToDesktop(8)
*!9:: MoveToDesktop(9)

; Tailscale task toggle (CapsLock + \)
*\:: {
    try {
        service := ComObject("Schedule.Service")
        service.Connect()
        folder := service.GetFolder("\")
        task := folder.GetTask("Tailscale Auto Switch")
        if (task.Enabled) {
            task.Enabled := false
            if ProcessExist("v2rayN.exe")
                RunWait("taskkill.exe /F /IM v2rayN.exe /T", , "Hide")
            ShowOSD("VPN Auto-Switch: OFF", 2000)
        } else {
            task.Enabled := true
            ShowOSD("VPN Auto-Switch: ON", 2000)
        }
    } catch Error as err {
        ShowOSD("VPN Toggle Error: " err.Message, 3000)
    }
}

#HotIf

; ============================================================
; CAMERA TOGGLE — Copilot key (#+F23)
; ============================================================
#+F23:: {
    ; [paste the full camera toggle block from lines 1867–1938 of old Master.ahk]
}
```

---

### `Master-PC.ahk` — PC Entry Point (new)

```ahk
#Requires AutoHotkey v2.0+
#SingleInstance Force
#WinActivateForce
#Include config.ahk

; Stub: no 20-20-20 on PC (no MenuBar). Must be before Core.ahk.
_202020_Reset(*) => 0
_202020_IsEnabled() => false
_202020_TogglePrompt() => 0

#Include lib/Core.ahk
#Include Remap.ahk

; ============================================================
; MULTI-MONITOR HELPERS (PC-specific)
; ============================================================

; Move the active window to monitor n, preserving its tiled layout percentages.
; If the window has a stored layout (g_Layouts), re-applies it on the new monitor.
; If it doesn't, just centers it at 75% (FloatCenter equivalent).
MoveWindowToMonitor(n) {
    if !WinExist("A")
        return
    monCount := MonitorGetCount()
    if n < 1 || n > monCount {
        ShowOSD("Monitor " n " doesn't exist (have " monCount ")")
        return
    }
    hwnd := WinGetID("A")
    MonitorGetWorkArea(n, &L, &T, &R, &B)
    ; Get current layout percentages; default to FloatCenter if untracked
    if g_Layouts.Has(hwnd) {
        layout := g_Layouts[hwnd]
        xf := layout[1], yf := layout[2], wf := layout[3], hf := layout[4]
    } else {
        xf := 12, yf := 12, wf := 75, hf := 75
    }
    MW := R - L, MH := B - T
    G := TileGap
    x := L + (MW * xf // 100)
    y := T + (MH * yf // 100)
    w := MW * wf // 100
    h := MH * hf // 100
    if WinGetMinMax("ahk_id " hwnd) != 0
        WinRestore("ahk_id " hwnd)
    WinMove(x, y, w, h, "ahk_id " hwnd)
    g_Layouts[hwnd] := [xf, yf, wf, hf]
    _PersistLayout(hwnd)
    ShowOSD("→ Monitor " n)
}

; Focus the most recently used window on monitor n.
; Falls back to whatever is topmost on that monitor if no history.
FocusMonitor(n) {
    monCount := MonitorGetCount()
    if n < 1 || n > monCount
        return
    MonitorGetWorkArea(n, &L, &T, &R, &B)
    ; Search FocusHistory in reverse for a window currently on this monitor
    i := FocusHistory.Length
    while i > 0 {
        hwnd := FocusHistory[i]
        if WinExist("ahk_id " hwnd) && WinGetMinMax("ahk_id " hwnd) != -1 {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            cx := wx + ww // 2
            cy := wy + wh // 2
            if cx >= L && cx < R && cy >= T && cy < B {
                WinActivate("ahk_id " hwnd)
                DllCall("SetCursorPos", "Int", cx, "Int", cy)
                return
            }
        }
        i--
    }
    ; Fallback: pick topmost non-minimized window on that monitor
    for hwnd in WinGetList() {
        if WinGetMinMax("ahk_id " hwnd) = -1
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        cx := wx + ww // 2, cy := wy + wh // 2
        if cx >= L && cx < R && cy >= T && cy < B {
            WinActivate("ahk_id " hwnd)
            return
        }
    }
}

; ============================================================
; PC HYPER LAYER EXTENSIONS
; ============================================================
#HotIf GetKeyState("CapsLock", "P")

; --- Monitor navigation ---
; CapsLock+Left/Right: focus previous/next monitor (cycles 1→2→3→1)
Left:: {
    monCount := MonitorGetCount()
    ; Find which monitor the active window is on
    curMon := 1
    if WinExist("A") {
        WinGetPos(&wx, &wy, &ww, &wh, "A")
        cx := wx + ww // 2, cy := wy + wh // 2
        loop monCount {
            MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
            if cx >= L && cx < R && cy >= T && cy < B {
                curMon := A_Index
                break
            }
        }
    }
    FocusMonitor(Mod(curMon - 2 + monCount, monCount) + 1)
}
Right:: {
    monCount := MonitorGetCount()
    curMon := 1
    if WinExist("A") {
        WinGetPos(&wx, &wy, &ww, &wh, "A")
        cx := wx + ww // 2, cy := wy + wh // 2
        loop monCount {
            MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
            if cx >= L && cx < R && cy >= T && cy < B {
                curMon := A_Index
                break
            }
        }
    }
    FocusMonitor(Mod(curMon, monCount) + 1)
}

; CapsLock+1/2/3: focus monitor 1/2/3
1:: FocusMonitor(1)
2:: FocusMonitor(2)
3:: FocusMonitor(3)

; CapsLock+Alt+1/2/3: move active window to monitor 1/2/3
*!1:: MoveWindowToMonitor(1)
*!2:: MoveWindowToMonitor(2)
*!3:: MoveWindowToMonitor(3)

; CapsLock+4-9: still available for virtual desktops if the user sets them up,
; or can be left unmapped. Uncomment below to enable virtual desktops on PC:
; 4:: GotoDesktop(4)
; ... etc

#HotIf
```

---

## PC vs Laptop: Feature Differences

| Feature | Laptop (`Master.ahk`) | PC (`Master-PC.ahk`) |
|---|---|---|
| Virtual desktops (1–9) | CapsLock+1–9 = switch, CapsLock+Alt+1–9 = move | Not bound by default |
| Prev/next workspace | CapsLock+Left/Right = prev/next virtual desktop | CapsLock+Left/Right = prev/next monitor |
| Monitor switching | Not needed (single screen) | CapsLock+1/2/3 = focus monitor 1/2/3 |
| Move window to monitor | N/A | CapsLock+Alt+1/2/3 |
| Camera toggle | CapsLock + Copilot key (#+F23) | Not present |
| Tailscale toggle | CapsLock+\ | Not present |
| 20-20-20 eye break | Yes, with MenuBar IPC | Not present |
| Tiling | All tile layouts (works per-monitor already) | Same, unchanged |
| WASD/HJKL | Yes | Yes |
| App launchers (T, M, E, V) | Yes | Yes |
| Keyboard lock | Yes | Yes |
| Remap.ahk (Alt→Ctrl) | Yes | Yes |
| VDA loaded | Yes (required) | Optional (loads if DLL present, silently skips if not) |

### PC-Specific Config Variables

Add these to `config.ahk` on the PC machine. The existing config.ahk `CFG_Email` and
`CFG_Phone` still apply. New PC-only variables:

```ahk
; How many physical monitors are connected (used for bounds checking)
; AHK can query this dynamically, so this is optional — here for documentation.
; global CFG_MonitorCount := 3

; Add any PC-specific app paths if they differ from defaults, e.g.:
; global CFG_BrowserExe := "msedge.exe"
```

---

## Phase 5: `Setup.ahk` — Task Scheduler Auto-Registration

Registers the "AHK Master Script" task (run `Master.ahk` at logon, highest privilege,
restart on failure). Does NOT register Tailscale — that's laptop-only and gitignored.

```ahk
#Requires AutoHotkey v2.0+
#SingleInstance Force

if !A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

; Detect which entry point to register based on which machine this is
entryPoint := FileExist(A_ScriptDir "\Master-PC.ahk") && (A_ComputerName = "DESKTOP-PC")
    ? "Master-PC.ahk"
    : "Master.ahk"
; Alternatively: always ask, or detect via CFG_Machine in config.ahk

ahkExe   := A_ProgramFiles "\AutoHotkey\v2\AutoHotkey64.exe"
scriptPath := A_ScriptDir "\" entryPoint
taskName := "AHK Master Script"

; Get current user SID
sidOutput := ""
RunWait(A_ComSpec ' /c wmic useraccount where name="' A_UserName '" get sid /value > "' A_Temp '\ahk_sid.txt"', , "Hide")
raw := FileRead(A_Temp "\ahk_sid.txt")
if RegExMatch(raw, "SID=(\S+)", &m)
    userSid := Trim(m[1])
else {
    MsgBox("Could not determine user SID. Aborting.", "Setup Error", "Icon!")
    ExitApp()
}

; Build the task XML (same structure as AHK Master Script.xml, minus MenuBar action)
xml := '<?xml version="1.0" encoding="UTF-16"?>'
xml .= '<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">'
xml .= '<RegistrationInfo><URI>\' taskName '</URI></RegistrationInfo>'
xml .= '<Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers>'
xml .= '<Principals><Principal id="Author">'
xml .= '<UserId>' userSid '</UserId>'
xml .= '<LogonType>InteractiveToken</LogonType>'
xml .= '<RunLevel>HighestAvailable</RunLevel>'
xml .= '</Principal></Principals>'
xml .= '<Settings>'
xml .= '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>'
xml .= '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>'
xml .= '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>'
xml .= '<AllowHardTerminate>true</AllowHardTerminate>'
xml .= '<StartWhenAvailable>true</StartWhenAvailable>'
xml .= '<Enabled>true</Enabled>'
xml .= '<RestartOnFailure><Interval>PT1M</Interval><Count>3</Count></RestartOnFailure>'
xml .= '</Settings>'
xml .= '<Actions Context="Author"><Exec>'
xml .= '<Command>"' ahkExe '"</Command>'
xml .= '<Arguments>"' scriptPath '"</Arguments>'
xml .= '</Exec></Actions>'
xml .= '</Task>'

; Write XML as UTF-16 LE (required by schtasks /xml)
tmpXml := A_Temp "\ahk_setup_task.xml"
FileOpen(tmpXml, "w", "UTF-16").Write(xml)

exitCode := RunWait(A_ComSpec ' /c schtasks /create /xml "' tmpXml '" /tn "' taskName '" /f', , "Hide")
FileDelete(tmpXml)
try FileDelete(A_Temp "\ahk_sid.txt")

if exitCode = 0
    MsgBox('Task "' taskName '" registered successfully.`n`nEntry point: ' scriptPath, "Setup Complete", "Iconi")
else
    MsgBox("schtasks returned exit code " exitCode ". Check that you ran as admin.", "Setup Failed", "Icon!")
```

---

## Implementation Order

1. **Create `lib/` directory.**
2. **Create `lib/Eye202020.ahk`** — cut all `g_202020_*` globals and `_202020_*` functions
   from `Master.ahk` (lines 179–873). Do NOT include the `_202020_Init()` call.
3. **Create `lib/Core.ahk`** — cut everything listed in the table above from `Master.ahk`.
   Add `OnMessage` registrations and `OnExit` registrations here.
   Keep `_202020_Init()` call out of Core.ahk.
4. **Refactor `Master.ahk`** — what remains is: `#Requires`, `#SingleInstance`,
   `#WinActivateForce`, includes for `config.ahk` + `lib/Eye202020.ahk` + `lib/Core.ahk`
   + `Remap.ahk`, WMI init, `_202020_Init()` call, the laptop-only hyper layer block
   (desktop switching, Tailscale toggle), and the camera toggle hotkey.
5. **Verify `Master.ahk` still works** — reload with CapsLock+Esc, test all hotkeys.
6. **Create `lib/Core.ahk`** stubs check: search for any remaining references to
   `_202020_Init`, `_202020_Reset`, `_202020_TogglePrompt`, `_202020_IsEnabled` in
   `lib/Core.ahk`. The only one that should appear is the call to `_202020_Reset` inside
   `_OnPowerBroadcast` and the call to `_202020_TogglePrompt` inside the `*+b::` hotkey
   in the shared Hyper Layer. Both are fine as long as the function is declared before
   `Core.ahk` is executed (guaranteed by include order).
7. **Create `Master-PC.ahk`** with the stubs, Core include, and PC-only hotkeys.
8. **Create `Setup.ahk`** and test it on the laptop first to verify the task registers
   correctly (compare output with the existing `AHK Master Script.xml` to sanity-check).
9. **Commit everything** — including `lib/`, `Master-PC.ahk`, `Setup.ahk`. The `.gitignore`
   already excludes `config.ahk`, `Tailscale.ahk`, and `*.xml`.

---

## Gotchas & Known Subtleties

- **`#HotIf` blocks can appear multiple times for the same condition.** AHK v2 merges them.
  The PC entry point opens a second `#HotIf GetKeyState("CapsLock", "P")` block on top of
  the one from `Core.ahk`. This is valid and expected.
- **`_ApplyLayout` already targets the monitor the window is on** via `_GetMonitorForHwnd`.
  The tile functions (`TileLeft`, `TileRight`, etc.) work correctly on a multi-monitor PC
  without any changes — they tile on whichever monitor the active window is on.
- **DWM border compensation** in `_ApplyLayout` uses `DwmGetWindowAttribute` (DWMA_EXTENDED_FRAME_BOUNDS = 9).
  This is the same on multi-monitor setups.
- **VDA + multi-monitor:** Virtual desktops and multiple physical monitors coexist in Windows.
  If the PC user also wants virtual desktops, they can uncomment the `GotoDesktop(4–9)` lines
  in `Master-PC.ahk`. The VDA DLL will load silently if present.
- **`_202020_Reset` stub on PC:** The PC stubs must be defined before `#Include lib/Core.ahk`
  because `Core.ahk` has the `_OnPowerBroadcast` handler that calls `_202020_Reset` at parse
  time (no, it's called at runtime, so order matters less than expected — but declaring before
  is safer and avoids AHK's forward-reference limitations with function literals).
- **`*+b::` in shared hyper layer** calls `_202020_TogglePrompt()`. On PC this is stubbed to
  a no-op, so the key combo just does nothing silently.
- **`ShowOSD("Script started!")` line (line 83)** is currently between the VDA block and the
  WMI init. After refactoring, it should remain in `lib/Core.ahk` at the end of the init
  sequence, after all globals are set. Alternatively, move it to each entry point for
  machine-specific messages ("Laptop script started" / "PC script started").
- **`_202020_IniFile`** and related files go in `%TEMP%`, which is per-user. No conflict.
- **Layout persistence file** (`ahk_layouts.ini`) in `%TEMP%` is per-machine. Each machine
  has its own `%TEMP%`, so there is no collision.
