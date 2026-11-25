# win-forge

> *"Hello, friend! I built this skill to help you clean up your PC and get the most out of your hardware—safely and on your own terms."*

An interactive, verification-first **Windows 10 & Windows 11** system audit, cleanup, de-bloating, optimization, and driver management skill for Antigravity (`v1`).

> **Philosophy:** Never run blind "all-in-one" scripts that silently break your desktop, updates, or apps. `win-forge` scans read-only first, shows exact live numbers, lets you choose what to change, and executes **one step at a time** with post-action verification.
>
> **Why Scripts + an AI Agent:** Traditional Windows cleaners are too deterministic—what's safe to remove depends on your specific hardware and habits. Pairing read-only audit scripts with an AI agent lets `win-forge` read your live setup, explain the trade-offs, and tailor every change to your conditions.
>
> **Works in Any Language:** The underlying scripts stay clean in English while the AI agent automatically translates findings, explanations, and interactive choices into whatever language you prompt in (English, Turkish, etc.).

---

## How It Works

`win-forge` enforces a strict four-phase, **iterative** workflow:

1. **Phase 1 — Read-Only Discovery (Fixed 5-Step Plan + Baseline):** Displays the standardized 5-part read-only analysis plan and runs non-destructive PowerShell audits (`audit_system.ps1`, `audit_disk.ps1`, and `audit_drivers.ps1`) to capture baseline disk space, large files, caches, bloatware, CPU/RAM load, performance flags (`HAGS`, `HVCI`, `TRIM`), GPU routing, 5-layer startups, Known Folders, targeted + general background processes, and pending driver updates. Nothing is modified until you decide.
2. **Phase 2 — User Selection (Scannable Sections + Trade-Offs):** Organizes findings cleanly under **1. System, Performance & Display State**, **2. Storage & Caches**, and **3. Startups, Services, Apps & Drivers**—featuring a **Merged Numbered Action Table** (explaining what each item does, what happens if disabled/removed, and its safety tag: `🟢 Safe`, `🟡 Conditional`, `🎮 Gaming`) plus nested bullets for already-clean items.
3. **Phase 3 — One-by-One Execution & Verification:** Runs one approved task at a time (elevating cleanly via transcript-logged UAC sessions, or providing an `IsAdmin`-guarded script when the host runner cannot elevate), verifies the new state (free space delta, registry value, service status, or driver version), and reports back before moving on.
4. **Phase 4 — Final Re-Scan & Iterative Tracking:** Re-runs the read-only audit scripts at the end to report a verified **before-vs-after delta**, and reminds you that Windows optimization is **iterative**—OS/Store updates and new installs can re-enable features or add new background tasks over time, so periodic re-runs keep your machine dialed in.

---

## What `v1` Covers

### 1. System, Performance, Process & Startup Audit
- Detects **Windows 10** (`Build < 22000`) vs. **Windows 11** (`Build >= 22000`), uptime, CPU load/clock, RAM/pagefile, active power plan, SSD health/TRIM, and performance flags (`HAGS`, `GameMode`, `HVCI`, `DevMode`).
- Checks display-to-GPU routing (`Win32_VideoController`) so monitors aren't accidentally running on integrated graphics when a discrete GPU is installed.
- Combines **targeted checks** (Microsoft telemetry/Widgets/OneDrive/Edge/Maps/Geolocation/Office polling, Chrome/Google updaters, vendor telemetry, gaming services) with **open-ended discovery** (`Win32_Process` RAM + CPU% grouping) so both known and unfamiliar background apps are surfaced.
- Audits **all 5 Windows startup layers**—not just `Run` keys:
  1. `HKCU`, `HKLM`, and `WOW6432Node` Registry `Run` (with `StartupApproved` status)
  2. User & System `Startup` folders
  3. Store / UWP `AppModel\SystemAppData` startup tasks
  4. Non-Windows & Windows Telemetry Scheduled Tasks (catching hidden launchers like `\PowerToys\Autorun for <user>`)
  5. Third-party `Automatic` Windows Services (flagging orphaned missing binaries and MSIX-protected Store services)

### 2. Junction-Safe Disk Audit & Cleanup
- Measures directory sizes using `robocopy /L /XJ` so NTFS junctions never double-count files.
- Safely clears User `Temp` (e.g., `docker-scout`, stale installers), `CrashDumps`, `.nuget\packages`, Chrome/Edge `Cache` folders (without touching cookies, history, or logins), and the Recycle Bin.
- Enables Windows **Storage Sense** for ongoing automated cleanup.
- Checks `C:\Windows\SoftwareDistribution\Download` for active `UsoSvc` locks before touching it so live Windows Updates are never corrupted.
- Removes `C:\Windows.old`, `Update Cleanup`, and `Temporary Setup Files` using Windows' built-in Disk Cleanup (`cleanmgr.exe /sagerun:99`).
- Supports relocating large folders to a secondary drive (`D:`) with `robocopy` + `mklink /J`. It copies, verifies, and keeps the original as `.old` until you confirm the app works. For games, it points you to the launcher's own move feature instead.

### 3. Known-Folder-Safe OneDrive Disable
- **Safety Guardrail:** Always checks `User Shell Folders` (`Desktop`, `Personal`, `My Pictures`) **before** touching `OneDrive`. If Known Folder Move redirected your folders into `OneDrive\`, it migrates local files and repoints Windows back to `C:\Users\<user>\Desktop`, `Documents`, and `Pictures` first.
- Includes a **Volume Shadow Copy (`vssadmin`) + `robocopy` recovery playbook** in case OneDrive folders were removed prematurely.
- Stops OneDrive, clears its `Run` entry, disables its 3 Scheduled Tasks, and sets `DisableFileSyncNGSC = 1` via Group Policy.

### 4. Startup, Bloat & Service Optimization
- Disables **Microsoft Edge** `StartupBoostEnabled` and `BackgroundModeEnabled` via Policy.
- Disables Store app auto-starts (`State = 1`) and PowerToys both in `settings.json` and Task Scheduler.
- Sets on-demand third-party services to `Manual` (or `Disabled` for services that self-revert to `Automatic`, such as `PCManager Service Store`).

### 5. Taskbar Widget Removal (Win 10 & Win 11)
- **Windows 10:** Disables News and interests via `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds\EnableFeeds = 0`.
- **Windows 11:** Disables Widgets via `HKLM:\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests = 0`.
- Restarts `explorer.exe` cleanly so changes take effect immediately.

### 6. Dev, Gaming Safety, Power & Locale Checks
- **Gaming Distinctions:** Never breaks games you actually play—protects `GamingServices`/`Xbox*` if you use PC Game Pass or Microsoft Store games, `GameInputRedistService` for controllers, and anti-cheats (`vgc`, `EasyAntiCheat`, `BattlEye`). At the same time, clearly notes when unused gaming services (e.g., Xbox/Game Pass services if you only play Steam/Epic/Riot) are safe to manualize or remove even for gamers.
- Audits `HIBERNATEIDLE` AC/DC timeouts and `hiberfil.sys` / Fast Startup trade-offs via `powercfg`.
- Supports Ultimate Performance power plan activation, Developer Mode, and Windows Defender exclusions for project `Workspace` & IDE directories.
- Audits Display Language vs. Regional Format (`HKCU:\Control Panel\International`) vs. System Locale before UI language switches.

### 7. Driver Audit & Update
- Inventories signed PnP drivers (`Win32_PnPSignedDriver`) and queries Windows Update (`Microsoft.Update.Session` `Type='Driver'`).
- Cross-checks OEM vs. vendor releases, validates Authenticode signatures (`Get-AuthenticodeSignature`) before installing, handles silent install quirks (e.g., Intel Graphics DCH `-s` vs. `ExitCode 1007`), and removes temporary installers afterward.

---

## Repository Structure

```text
win-forge/
├── SKILL.md                  # Core Antigravity skill instructions & interactive workflow
├── README.md                 # Project overview, safety model & usage guide
├── future_development.md     # 9-module v2+ expansion roadmap
├── references/
│   └── playbooks.md          # Verified Win10/11 PowerShell execution playbooks
└── scripts/
    ├── audit_system.ps1      # Read-only OS, RAM, Known Folders & 5-layer startup audit
    ├── audit_disk.ps1        # Read-only junction-safe disk & cache audit
    └── audit_drivers.ps1     # Read-only signed driver & Windows Update driver check
```

---

## Installation & Usage

### In Antigravity
Place this repository in your global or workspace skills directory:
- **Global:** `~/.gemini/antigravity/skills/win-forge/`
- **Workspace:** `<repo>/.agents/skills/win-forge/`

Then ask the agent things like:
- *"Use win-forge to check what's slowing down my PC and taking up disk space."*
- *"Run win-forge to audit my startup apps and background processes."*
- *"Check my drivers with win-forge."*

### Using `win-forge` Iteratively (Recommended)
Windows optimization is an **iterative process**, not a one-time fix. Windows Updates, Microsoft Store updates, and newly installed apps routinely re-enable settings (such as `HVCI` or `StartupBoost`), revert services back to `Automatic`, add new updater tasks, or accumulate gigabytes of new dev/AI caches.

To actively track and maintain your PC over time:
1. **Run an initial full pass:** Let `win-forge` establish a baseline, choose your optimizations one by one, and review the Phase 4 final re-scan.
2. **Re-run periodically** (e.g., monthly, after major Windows feature updates, or after installing new IDEs, SDKs, or games):
   - *"Re-run win-forge to check if anything reverted or crept back into startup."*
   - *"Run win-forge disk and performance audit to see what's grown since last time."*
3. **Compare against your previous baseline:** Check free disk space, `pagefile.sys` growth, active `Auto` services, and `HVCI`/`HAGS`/power-plan flags—and note that running your terminal/agent elevated (`IsAdmin: True`) exposes system-wide tasks and multi-user `$Recycle.Bin` usage.

### Running Audit Scripts Standalone (Read-Only)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit_system.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit_disk.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit_drivers.ps1
```

---

## Roadmap
See [future_development.md](./future_development.md) for the **v2+** plan expanding all **9 modules** (including **App Manager**, **System Repair** (`DISM`/`sfc`/`chkdsk`/`lodctr`), deeper **Debloat**, WSL2/Docker `vhdx` compaction, and OEM driver automation).

---

## Contributing & Contact
If you want to contribute or share feedback, don't hesitate—open an issue or PR, or reach out to me on X: [@omerokumusx](https://x.com/omerokumusx) and [@omerokumusx_tr](https://x.com/omerokumusx_tr).
