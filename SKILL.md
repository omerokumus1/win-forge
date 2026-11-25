---
name: win-forge
description: >-
  Interactive Windows 10 and Windows 11 system audit, disk cleanup, startup/process
  de-bloating, OneDrive removal, dev/gaming tuning, and driver update workflow.
  Use when the user asks to clean up, speed up, audit disk space, inspect Task
  Manager/startup bloat, disable OneDrive safely, or check/update drivers on Windows.
---

# Win-Forge (v1)

An interactive, step-by-step Windows 10 & Windows 11 optimization and cleanup skill.

> **Opening Greeting (translate into the user's language at the start of a session):** *"Hello, friend! I built this skill to help you clean up your PC and get the most out of your hardware—safely and on your own terms."*

## Core Execution Rules (Interactive & One-by-One)

1. **Never modify anything during initial discovery; always baseline disk, performance, and driver states first.** Before proposing or executing any changes, run [audit_system.ps1](./scripts/audit_system.ps1), [audit_disk.ps1](./scripts/audit_disk.ps1), and [audit_drivers.ps1](./scripts/audit_drivers.ps1) read-only to record current disk space, CPU/RAM load, power/performance flags, GPU routing, startup state, and pending driver updates.
2. **Present scannable findings with clear trade-offs.** Never dump dense prose paragraphs alongside a duplicate bottom list. Always organize Phase 1 output under these exact 3 numbered sections:
   - **1. System, Performance & Display State** — compact summary table (`OS & Power`, `CPU & RAM`, `Performance Flags`, `GPU Routing`, `SSD Health` with `🟢 Healthy` / `🟡 Review` / `🔴 Action Needed` tags).
   - **2. Storage & Caches** — clean `Storage Snapshot` table (`Folder / Cache`, `Size`, `Notes`—never an inline run-on line).
   - **3. Startups, Services, Apps & Drivers** — brief **Drivers & BIOS** status, a **Merged Numbered Action Table** (`#`, `Item`, `Size / RAM`, `What It Does`, `If Disabled / Removed`, `Tag` — `🟢 Safe` / `🟡 Conditional` / `🎮 Gaming`), **Already Clean / Protected** formatted as **nested bullets** (category header bullet + indented sub-bullets, never semicolon-separated inline text), and `"Reply with the numbers to run (e.g., 1, 2)"`.
3. **Wait for user selection.** Let the user choose which numbered items to run.
4. **Execute one by one with verification.** Run **one approved task at a time**, verify its result (exit code, free space delta, registry/service/process state), report the outcome briefly, then proceed to the next item.
5. **Handle elevation cleanly.** Check if the shell is elevated (`IsAdmin`). Run user-scoped actions directly; wrap `HKLM`, `Service`, `cleanmgr`, `powercfg`, or driver installs in an elevated script (`Start-Process powershell -Verb RunAs -Wait`) that logs to a transcript so output is captured. If `-Verb RunAs` fails or is unsupported in the current environment (`InvalidOperationException` / non-interactive runner), do not attempt to bypass elevation—save a self-contained `.ps1` script to scratch/temp, verify `IsAdmin` inside it, and give the user the exact one-line command to run from an Administrator PowerShell (`Win + X → Terminal (Admin)`).
6. **Respond in the user's language.** This skill works in any language—automatically match the user's language and translate all audit summaries, 1-line explanations, removal impacts, and prompts naturally, while keeping exact Windows file paths, registry keys, service names, and process names intact for precision.

---

## Phase 1: Read-Only Discovery

1. **Display the Fixed 5-Step Read-Only Analysis Plan (No Plan Designing Needed):** Open with the greeting (translated to the user's language), show this fixed 5-step plan, and immediately execute all three read-only audits without modifying anything:
   - **Storage, Large Files & Caches:** Measure top-level drive usage (`robocopy /L /XJ`), `pagefile.sys` / `hiberfil.sys`, Recycle Bin, and cleanable dev/browser/system caches (`Temp`, `CrashDumps`, `.nuget`, `pip`, `npm`, `huggingface`, Chrome/Edge).
   - **Bloatware & Installed Apps:** Inventory optional/vendor Store apps (`Get-AppxPackage`) and safety-critical Known Folders (`Desktop`, `Documents`, `Pictures` OneDrive redirection check).
   - **Background Processes, CPU & RAM:** Snapshot live CPU load/clock, total process count, top RAM & CPU consumers, and targeted Microsoft/Chrome/vendor/gaming processes.
   - **All 5 Startup Layers & Services:** Audit `HKCU`/`HKLM`/`WOW6432Node` `Run` (with `StartupApproved` flags), Startup folders, Store startup tasks, non-Windows & telemetry Scheduled Tasks, and 3rd-party `Automatic` services (flagging orphaned binaries and MSIX-protected services).
   - **Performance Flags, GPU Routing, BIOS & Drivers:** Inspect `HAGS`, `GameMode`, `HVCI`, `DevMode`, SSD health/TRIM, active display-to-GPU routing, BIOS age, PnP device errors, and pending Windows Update drivers.
2. **Execute the Mandatory Pre-Flight Baseline (Zero Changes):** Run **all three** read-only audits and present only the scannable analysis results—do not take any action until the user decides what to do:

- **System, Performance State, Processes, Startups & Known Folders:** [audit_system.ps1](./scripts/audit_system.ps1)
- **Disk Space, Pagefile & Caches (Junction-Safe):** [audit_disk.ps1](./scripts/audit_disk.ps1)
- **Installed Drivers, BIOS Age, Device Errors & Windows Update Drivers:** [audit_drivers.ps1](./scripts/audit_drivers.ps1)

Before recommending any action, verify the OS version (`Build >= 22000` = Windows 11, `< 22000` = Windows 10) and flag any safety risks (e.g., OneDrive Known Folder Move active, or Windows Update actively locking `SoftwareDistribution\Download`). Combine **targeted checks** for known bloat/updaters (Microsoft telemetry/Widgets/OneDrive/Edge/Maps/Geolocation/Office polling, Chrome/Google updaters, Intel/NVIDIA telemetry/updaters, gaming services) with **open-ended discovery** across all running processes, 5 startup layers, and installed apps so unknown bloat is never missed. Note that running Phase 1 elevated (`IsAdmin: True`) also reveals system-wide Scheduled Tasks (e.g. `\Intel\*`, `\GoogleSystem\*`) and multi-SID `$Recycle.Bin` usage hidden from non-admin scans.

---

## Phase 2 & 3: Action Modules (Execute One by One)

Use the exact verified commands and OS-specific branches in [playbooks.md](./references/playbooks.md) for each approved item:

1. **Disk & Cache Cleanup**
   - Clear User `Temp` (skip locked files), `CrashDumps`, `.nuget\packages`, Chrome/Edge `Cache` folders only (never cookies/logins), and Recycle Bin.
   - Enable **Storage Sense** (`StoragePolicy\01 = 1`).
   - Check `UsoSvc` / recent timestamps before touching `C:\Windows\SoftwareDistribution\Download`; if locked by an active Windows Update download, skip and advise cleaning after restart.
   - Clean `C:\Windows.old`, `Update Cleanup`, and `Temporary Setup Files` safely via `cleanmgr.exe /sagerun:99` (`VolumeCaches` `StateFlags0099 = 2`).
   - Move large folders/games from `C:` to a secondary drive (`D:`) via `robocopy` + directory junction (`mklink /J`) when requested.

2. **OneDrive Full Disable (Known-Folder-Safe)**
   - **MANDATORY PRE-CHECK:** Inspect `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders` (`Desktop`, `Personal`, `My Pictures`) **before** deleting `OneDrive`.
   - If redirected into `OneDrive\`, migrate local files out and repoint both `User Shell Folders` and `Shell Folders` to local paths (`C:\Users\<user>\Desktop`, `Documents`, `Pictures`) **first**.
   - Stop `OneDrive`, remove its `HKCU\...\Run` entry, disable its 3 Scheduled Tasks, and set `HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive\DisableFileSyncNGSC = 1`.
   - *(Emergency recovery reference in `playbooks.md`: VSS `vssadmin` + `mklink /d` + `robocopy`.)*

3. **Startup, Background Process & Service Optimization**
   - Audit all 5 layers: `HKCU/HKLM\...\Run`, Startup folders, Store `AppModel\SystemAppData` (`State = 1` disables), Scheduled Tasks (e.g., `\PowerToys\Autorun for <user>`), and Services.
   - Disable Edge `StartupBoostEnabled` & `BackgroundModeEnabled` via `HKLM:\SOFTWARE\Policies\Microsoft\Edge`.
   - Set on-demand third-party services to `Manual` (or `Disabled` if they self-revert to `Automatic` on reboot, such as `PCManager Service Store`).

4. **Taskbar & UI Cleanup (Win 10 vs. Win 11)**
   - **Windows 10** (`Build < 22000`): Set `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds\EnableFeeds = 0` (News and interests / weather widget).
   - **Windows 11** (`Build >= 22000`): Set `HKLM:\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests = 0` (Widgets). On newer Win 11 builds where `Dsh` / `TaskbarDa` registry writes throw `UnauthorizedAccessException` even as Admin, remove `Microsoft.WidgetsPlatformRuntime`, `Microsoft.StartExperiencesApp`, and `MicrosoftWindows.Client.WebExperience` via `Remove-AppxPackage` (if approved) or toggle Widgets off in Settings.
   - Restart `explorer.exe` to apply immediately.

5. **Dev, Gaming, Power & Locale Checks**
   - **Power & Hibernation:** Check `powercfg /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE` (AC vs. DC timeouts) and `hiberfil.sys` / Fast Startup trade-offs; activate Ultimate Performance (`powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61`) if requested.
   - **Dev & Gaming Safety Distinctions:** Add Windows Defender exclusions for project `Workspace` and IDE paths; enable Developer Mode; check external display GPU routing when gaming. **Never remove gaming components the user's games depend on** (keep `GamingServices`, `XboxService`, `XblGameSave`, `Microsoft.GamingApp`, `XboxIdentityProvider` for PC Game Pass / Microsoft Store games; keep `GameInputRedistService` for controllers; keep anti-cheats like `vgc`, `EasyAntiCheat`, `BattlEye`; keep GPU/peripheral suites if used). **Conversely, even if the user plays games**, unused gaming services (e.g., Xbox/Game Pass services when the user only plays Steam/Epic/Riot titles) are safe to manualize or remove. Always disclose HVCI (Memory Integrity) security vs. FPS/anti-cheat trade-offs before toggling.
   - **Language & Locale Safety:** Audit `WinSystemLocale`, `WinUserLanguageList`, and `HKCU:\Control Panel\International` (`LocaleName`) before Display Language changes so Regional Format (`d.MM.yyyy`, `,` decimal) and non-Unicode apps don't unexpectedly change.

6. **Driver Audit & Update**
   - Compare `Win32_PnPSignedDriver` versions and `Microsoft.Update.Session` (`IsInstalled=0 and Type='Driver'`) against OEM/vendor releases.
   - Never offer or install a pending driver tagged `[NOT PRESENT]` by `audit_drivers.ps1`: its hardware ID matches no connected device (e.g., an NVIDIA driver offered for a GPU that was replaced by an AMD card—these records survive DDU). Offer instead to remove the stale device record listed under it (`pnputil /remove-device`, see [playbooks.md](./references/playbooks.md) §7) so Windows Update stops offering the driver.
   - Verify `Get-AuthenticodeSignature` (`Status -eq 'Valid'`) on any downloaded installer before running.
   - For Intel Graphics DCH packages (`gfx_win_101*.exe`), use `-s` only (extra flags like `--overwrite`/`--report` can fail with `ExitCode 1007` / `ERROR_BAD_COMMAND`). Delete temporary installers after verification.

---

## Phase 4: Final Re-Scan & Iterative Tracking

1. **Final Post-Action Re-Scan:** After all approved tasks finish, run [audit_system.ps1](./scripts/audit_system.ps1) and [audit_disk.ps1](./scripts/audit_disk.ps1) (plus [audit_drivers.ps1](./scripts/audit_drivers.ps1) if drivers were updated) **one last time** and summarize the before-vs-after delta using these two lightweight tables (keep cells crisp and numeric—no dates):
   - **1. Disk Space** (`Drive` | `Before` | `Now` | `Gained`) — fixed drives only (e.g., `C: (SSD)`, `D: (HDD)`).
   - **2. System Load** (`Metric` | `Before` | `Now` | `Change`) — rows for `Processes`, `RAM Used`, `Startup Apps (Run)` (numeric counts), `Background Bloat` (brief list → `Removed / Disabled / Manual`), and `Drivers Updated` (if any).
2. **Iterative-Process Notice:** Always conclude with a brief reminder that Windows optimization is **an iterative process**—Windows Updates, Store updates, and newly installed apps can re-enable features (e.g., `HVCI`), revert services, or add new background updaters—so the user should actively track changes and re-run `win-forge` periodically.

---

## Contributing & Contact

If you want to contribute or share feedback, don't hesitate—open an issue or PR, or reach out to me on X: [@omerokumusx](https://x.com/omerokumusx) and [@omerokumusx_tr](https://x.com/omerokumusx_tr).
