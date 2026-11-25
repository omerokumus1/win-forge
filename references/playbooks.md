# Win-Forge Playbooks (Windows 10 & Windows 11)

## 1. Elevation Pattern

When `IsAdmin` is `False`, write an `.ps1` script to a scratch/temp path with `Start-Transcript`, run it elevated, then inspect the transcript:

```powershell
Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs -Wait
```

> **Fallback for non-elevatable / restricted shells:** If `Start-Process -Verb RunAs` throws `The request is not supported` (`InvalidOperationException`) or UAC cannot be spawned from the host runner, do **not** attempt any UAC bypass. Guard the generated `.ps1` script with an `IsAdmin` check at the top, save it, and give the user the exact command to paste into **Terminal (Admin)** (`Win + X → Terminal (Admin)`).

---

## 2. Disk & Cache Cleanup

### User-Level Safe Clean (Non-Admin)
```powershell
Get-ChildItem $env:TEMP -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "$env:LOCALAPPDATA\CrashDumps" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "$env:USERPROFILE\.nuget\packages" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Clear-RecycleBin -DriveLetter C -Force -ErrorAction SilentlyContinue

# Enable Storage Sense
$ss = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
New-Item -Path $ss -Force | Out-Null
Set-ItemProperty -Path $ss -Name "01" -Value 1 -Type DWord
```

### `Windows.old` & Update Cleanup (`cleanmgr` — Elevated)
```powershell
$vcBase = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
foreach ($key in @("Previous Installations", "Update Cleanup", "Temporary Setup Files")) {
    $p = Join-Path $vcBase $key
    if (Test-Path $p) {
        Set-ItemProperty -Path $p -Name "StateFlags0099" -Value 2 -Type DWord -ErrorAction SilentlyContinue
    }
}
Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:99" -PassThru -Wait
```

### Move Large Folder to Secondary Drive via Junction (Elevated / Admin if protected)
```powershell
robocopy "C:\SourceFolder" "D:\TargetFolder" /E /COPYALL /MOVE /R:1 /W:1
cmd /c mklink /J "C:\SourceFolder" "D:\TargetFolder"
```

---

## 3. OneDrive Full Disable (Known-Folder-Safe)

### Step A: Check & Repoint Known Folders FIRST
```powershell
$usf = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
$sf  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
$paths = Get-ItemProperty $usf | Select-Object Desktop, Personal, "My Pictures"
```
If any path points inside `OneDrive\`:
1. Copy local files from those `OneDrive\*` folders to `C:\Users\$env:USERNAME\Desktop`, `Documents`, `Pictures` (skip cloud-only placeholders).
2. Repoint both `$usf` and `$sf`:
```powershell
foreach ($k in @($usf, $sf)) {
    Set-ItemProperty -Path $k -Name "Desktop"     -Value "$env:USERPROFILE\Desktop"
    Set-ItemProperty -Path $k -Name "Personal"    -Value "$env:USERPROFILE\Documents"
    Set-ItemProperty -Path $k -Name "My Pictures" -Value "$env:USERPROFILE\Pictures"
}
```
3. Restart `explorer.exe` and verify Desktop/Documents files before deleting `OneDrive`.

### Step B: Disable OneDrive Entirely
```powershell
Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
Get-ScheduledTask | Where-Object { $_.TaskName -like "OneDrive*" } | Disable-ScheduledTask -ErrorAction SilentlyContinue

# Elevated:
$odPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
New-Item -Path $odPol -Force | Out-Null
Set-ItemProperty -Path $odPol -Name "DisableFileSyncNGSC" -Value 1 -Type DWord
```

### Emergency Recovery from Volume Shadow Copy (Elevated)
```powershell
vssadmin list shadows
# Replace ShadowCopyVolume with the observed \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopyN path
cmd /c mklink /d "C:\ShadowTemp_OneDrive" "\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1\Users\$env:USERNAME\OneDrive"
robocopy "C:\ShadowTemp_OneDrive\<DesktopFolder>" "$env:USERPROFILE\Desktop" /E /COPYALL /R:1 /W:1
cmd /c rmdir "C:\ShadowTemp_OneDrive"
```

---

## 4. Startup, Process & Service Optimization

- **Store App Startups (`State = 1` disables, `2` enables):**
  `HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\<PackageFamily>\<TaskId>`
- **PowerToys Auto-Run (Both `settings.json` AND Scheduled Task):**
  1. Set `"startup": false` in `$env:LOCALAPPDATA\Microsoft\PowerToys\settings.json`.
  2. Disable Scheduled Task `\PowerToys\Autorun for <username>`:
     `Disable-ScheduledTask -TaskPath "\PowerToys\" -TaskName "Autorun for $env:USERNAME"`
- **Edge Startup Boost & Background Mode (Elevated):**
  ```powershell
  $edgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
  New-Item -Path $edgePol -Force | Out-Null
  Set-ItemProperty -Path $edgePol -Name "StartupBoostEnabled" -Value 0 -Type DWord
  Set-ItemProperty -Path $edgePol -Name "BackgroundModeEnabled" -Value 0 -Type DWord
  ```
- **Services (Elevated):** Use `Set-Service -Name "<name>" -StartupType Manual` (use `Disabled` for services that self-revert to `Automatic`, e.g., `PCManager Service Store`). Note that MSIX/Store-packaged services whose `PathName` is inside `C:\Program Files\WindowsApps\` (e.g., `IntelGraphicsSoftwareService`, `SamsungQuickShareService`) throw `Access is denied` (`ERROR 5`) on `Set-Service` / `sc config` even as Admin—uninstall the parent Store `AppxPackage` if unwanted.

---

## 5. Taskbar Widget Removal (Win 10 vs. Win 11)

```powershell
$build = [System.Environment]::OSVersion.Version.Build
if ($build -ge 22000) {
    # Windows 11 Widgets
    $pol = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    New-Item -Path $pol -Force | Out-Null
    Set-ItemProperty -Path $pol -Name "AllowNewsAndInterests" -Value 0 -Type DWord
} else {
    # Windows 10 News and interests
    $pol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
    New-Item -Path $pol -Force | Out-Null
    Set-ItemProperty -Path $pol -Name "EnableFeeds" -Value 0 -Type DWord
}
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
```

> **Windows 11 Build 26300+ Fallback:** If writing `Dsh\AllowNewsAndInterests` or `TaskbarDa` throws `UnauthorizedAccessException` (`Attempted to perform an unauthorized operation`) even when elevated, remove the Widgets/Feeds packages instead (with user approval):
> ```powershell
> foreach ($pkg in @("Microsoft.WidgetsPlatformRuntime", "Microsoft.StartExperiencesApp", "MicrosoftWindows.Client.WebExperience")) {
>     Get-AppxPackage $pkg | Remove-AppxPackage -ErrorAction SilentlyContinue
> }
> ```

---

## 6. Power, Dev/Gaming & Locale Checks

- **Hibernate Timeout Check:** `powercfg /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE` (AC `0` = Never, DC in seconds). Only run `powercfg /h off` if the user confirms they do not need Hibernate or Fast Startup.
- **Pagefile → System Managed (Elevated, reboot required):** Only when `audit_disk.ps1` prints the pagefile `[ADVISORY]` and the user confirms the fixed size was not set on purpose.
  ```powershell
  $cs = Get-CimInstance Win32_ComputerSystem
  Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true }
  ```
  Verify before rebooting: `(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management').PagingFiles` is `?:\pagefile.sys` and `Get-CimInstance Win32_PageFileSetting` returns nothing. `pagefile.sys` shrinks after the reboot; confirm in the Phase 4 re-scan.
- **Ultimate Performance Power Plan (Elevated):**
  `powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61` then `powercfg /setactive <GUID>`.
- **Regional Format Check:** Check `(Get-ItemProperty "HKCU:\Control Panel\International").LocaleName` and `Get-WinSystemLocale` before changing Windows Display Language; set `Set-Culture <locale>` if Regional Format needs to stay pinned after switching UI language.

---

## 7. Driver Verification & Silent Install

```powershell
# Verify Authenticode signature before installing
$sig = Get-AuthenticodeSignature $installerPath
if ($sig.Status -ne 'Valid') { throw "Invalid signature: $($sig.Status)" }

# Intel DCH Graphics installer: pass -s only (avoid --overwrite/--report if ExitCode 1007 occurs)
$p = Start-Process -FilePath $installerPath -ArgumentList "-s" -PassThru -Wait
```
Delete the temporary installer after verifying `Win32_VideoController` / `Win32_PnPSignedDriver` reports the updated `DriverVersion` and `Status = OK`.

---

## 8. Process, Service & Gaming Reference (What It Does & Removal Impact)

Use these reference notes alongside open-ended discovery so every option presented to the user explains **what it does** and **what happens if removed/disabled**:

### Microsoft, Chrome & Vendor Targets (Targeted + General Scan)
| Target | What It Does | Impact If Disabled / Removed |
| :--- | :--- | :--- |
| `WidgetService` / `MicrosoftStartFeedProvider` / `msedgewebview2` (Widgets) | Renders Win 11 Taskbar Widgets and MSN news/weather feeds in RAM (~150–250 MB). | Taskbar Widgets board is removed/disabled; desktop and Edge browser are unaffected. |
| `edgeupdate` / `StartupBoostEnabled` / `BackgroundModeEnabled` | Pre-loads Microsoft Edge at sign-in and polls for Edge updates in the background. | Edge launches slightly slower cold, and updates when opened instead of in the background. |
| `GoogleUpdater*` / `RunPlatformExperienceHelper_*` | Chrome/Google background auto-update polling and telemetry tasks. | Chrome still updates when opened or via `chrome://settings/help`; stops background polling. |
| `MapsBroker` / `MapsToastTask` | Downloads and maintains offline maps for the Windows Maps app. | Offline Windows Maps sync stops; online maps in browsers work normally. |
| `lfsvc` (Geolocation Service) | Provides Wi-Fi/IP approximate location to Windows Store/desktop apps. | Windows Weather/Maps/Find My Device lose automatic location unless re-enabled. |
| `WSearch` (Windows Search) | Indexes local files for fast Start Menu and File Explorer searches. | Start/Explorer file searches become slower (keep `Auto` unless using a 3rd-party tool like Everything). |
| `DiagTrack` / `CEIP` (`Consolidator`, `UsbCeip`) / `Compatibility Appraiser` / `SoftLanding*` | Windows telemetry, diagnostics, and feature/promo suggestions. | Stops diagnostic uploads and OS suggestions with no impact on apps or stability. |
| `Intel Telemetry 3` / `NvTmRep_CrashReport*` / `NvDriverUpdateCheckDaily` | Intel/NVIDIA crash reporting and daily driver update polling. | GPU drivers keep working; you check/update drivers manually when desired. |
| `Office*` update tasks / `ClickToRunSvc` | Polls for Microsoft 365/Office updates on a schedule. | Set `ClickToRunSvc` to `Manual` and disable polling tasks if you prefer updating Office manually from File → Account. |
| **Core OS (Never Remove)** | `svchost.exe`, `dwm.exe`, `explorer.exe`, `StartMenuExperienceHost`, `ShellExperienceHost`, `RuntimeBroker`, `TextInputHost`, `WinDefend`, `MDCoreSvc` | Disabling or killing these breaks desktop shell, input, or Windows security. |

### Gaming Distinctions (Never Break What Your Games Use)
- **Play PC Game Pass / Xbox App / Microsoft Store games → DO NOT REMOVE:**
  - `GamingServices`, `GamingServicesNet`, `Microsoft.GamingApp`, `XboxService`, `XblAuthManager`, `XblGameSave`, `XboxNetApiSvc`, `Microsoft.XboxIdentityProvider`, `Microsoft.XboxGamingOverlay`. Removing these breaks Game Pass launches, Xbox Live sign-in, and cloud saves.
- **Play Steam / Epic / Riot / Standalone games only (do NOT use Xbox/Game Pass):**
  - Even though you play games, unused Xbox/Game Pass items (`XboxService`, `XblGameSaveTask`, Game Bar) are **safe** to set to `Manual` or disable—Steam, CS2, PUBG, and Epic titles do not require them.
- **Keep for Controllers, Anti-Cheat & Hardware:**
  - `GameInputRedistService`: Keep if you use gamepads/controllers on Windows.
  - Anti-cheat services (`vgc` / Riot Vanguard, `EasyAntiCheat`, `BattlEye`): Never disable while playing games that require them.
  - GPU & peripheral agents (`NVDisplay.ContainerLocalSystem`, `logioptionsplus_agent`, Synapse, iCUE): Keep if you rely on driver overlays, custom mouse/keyboard mappings, or per-game DPI profiles (unless saved to onboard device memory).
