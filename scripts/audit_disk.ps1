$ErrorActionPreference = 'SilentlyContinue'

# Sizes are measured as bytes actually allocated on disk. Logical sizes (robocopy /BYTES, Explorer "Size")
# overstate sparse files (e.g. Android emulator / WSL disk images that report hundreds of GB while using a
# few), NTFS-compressed files, and dehydrated cloud placeholders. Directory reparse points (junctions and
# symlinks) are skipped, matching the previous robocopy /XJ behavior.
if (-not ('WinForgeDiskSize' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

public static class WinForgeDiskSize {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);

    const FileAttributes RecallOnOpen = (FileAttributes)0x40000;
    const FileAttributes RecallOnDataAccess = (FileAttributes)0x400000;
    const FileAttributes NotLocal = FileAttributes.Offline | RecallOnOpen | RecallOnDataAccess;
    const FileAttributes Shrunk = FileAttributes.SparseFile | FileAttributes.Compressed;

    // Returns { onDiskBytes, logicalBytes }.
    public static long[] Measure(string path) {
        string full = Path.GetFullPath(path);
        if (!full.StartsWith(@"\\")) full = @"\\?\" + full;
        long[] total = new long[2];
        if (File.Exists(full)) { Add(new FileInfo(full), total); return total; }
        Stack<DirectoryInfo> pending = new Stack<DirectoryInfo>();
        pending.Push(new DirectoryInfo(full));
        while (pending.Count > 0) {
            FileSystemInfo[] entries;
            try { entries = pending.Pop().GetFileSystemInfos(); } catch { continue; }
            foreach (FileSystemInfo entry in entries) {
                if ((entry.Attributes & FileAttributes.Directory) == 0) { Add((FileInfo)entry, total); }
                else if ((entry.Attributes & FileAttributes.ReparsePoint) == 0) { pending.Push((DirectoryInfo)entry); }
            }
        }
        return total;
    }

    static void Add(FileInfo file, long[] total) {
        long logical = file.Length;
        long onDisk = logical;
        FileAttributes attrs = file.Attributes;
        if ((attrs & NotLocal) != 0) {
            // Cloud placeholder whose data is not local; querying it could trigger a download.
            onDisk = 0;
        } else if ((attrs & Shrunk) != 0) {
            uint high;
            uint low = GetCompressedFileSizeW(file.FullName, out high);
            if (low != 0xFFFFFFFF || Marshal.GetLastWin32Error() == 0) onDisk = ((long)high << 32) | low;
        }
        total[0] += onDisk;
        total[1] += logical;
    }
}
'@
}

function Get-FolderSizeGB($path) {
    if (-not (Test-Path $path)) { return 0 }
    return [math]::Round([WinForgeDiskSize]::Measure($path)[0] / 1GB, 2)
}

Write-Output "=== DRIVE SUMMARY ==="
$drives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'
foreach ($d in $drives) {
    $total = [math]::Round($d.Size / 1GB, 2)
    $free = [math]::Round($d.FreeSpace / 1GB, 2)
    $used = [math]::Round(($d.Size - $d.FreeSpace) / 1GB, 2)
    Write-Output "$($d.DeviceID) Used: $used GB / $total GB (Free: $free GB)"
}

foreach ($d in $drives) {
    $root = "$($d.DeviceID)\"
    Write-Output "`n=== $root TOP-LEVEL FOLDERS & FILES (>= 0.1 GB, Junction-Safe) ==="
    Get-ChildItem $root -Force | Where-Object { -not $_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint) } | ForEach-Object {
        $size = [WinForgeDiskSize]::Measure($_.FullName)
        $gb = [math]::Round($size[0] / 1GB, 2)
        $logicalGb = [math]::Round($size[1] / 1GB, 2)
        [PSCustomObject]@{
            Name = $_.Name
            Type = if ($_.PSIsContainer) { "Dir" } else { "File" }
            GB   = $gb
            Note = if ($logicalGb - $gb -ge 1) { "Logical size $logicalGb GB (sparse/compressed/cloud files)" } else { "" }
        }
    } | Where-Object { $_.GB -ge 0.1 } | Sort-Object GB -Descending | Format-Table -AutoSize
}

Write-Output "=== KNOWN CLEANABLE CACHES ==="
$caches = @(
    @{ Name = "User Temp"; Path = $env:TEMP },
    @{ Name = "Windows Temp"; Path = "C:\Windows\Temp" },
    @{ Name = "Windows Update DL"; Path = "C:\Windows\SoftwareDistribution\Download" },
    @{ Name = "NuGet cache"; Path = "$env:USERPROFILE\.nuget\packages" },
    @{ Name = "pip cache"; Path = "$env:LOCALAPPDATA\pip\cache" },
    @{ Name = "npm cache"; Path = "$env:LOCALAPPDATA\npm-cache" },
    @{ Name = "HuggingFace cache"; Path = "$env:USERPROFILE\.cache\huggingface\hub" },
    @{ Name = "LM Studio updater"; Path = "$env:LOCALAPPDATA\lm-studio-updater" },
    @{ Name = "Chrome Cache"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" },
    @{ Name = "Edge Cache"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache" },
    @{ Name = "CrashDumps"; Path = "$env:LOCALAPPDATA\CrashDumps" }
)
foreach ($c in $caches) {
    if (Test-Path $c.Path) {
        $gb = Get-FolderSizeGB $c.Path
        $mb = [math]::Round($gb * 1024, 1)
        if ($mb -gt 20) { Write-Output "$($c.Name): $mb MB ($($c.Path))" }
    }
}

$sdRecent = Get-ChildItem "C:\Windows\SoftwareDistribution\Download" -Force | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-2) }
if ($sdRecent) {
    Write-Output "[NOTE] SoftwareDistribution\Download has files modified in the last 2 hours (Windows Update may be actively staging)."
}

$hiber = Get-Item "C:\hiberfil.sys" -Force
if ($hiber) { Write-Output "hiberfil.sys: $([math]::Round($hiber.Length / 1GB, 2)) GB" }

$pf = Get-CimInstance Win32_PageFileUsage
if ($pf -and $pf.AllocatedBaseSize -ge 8192) {
    Write-Output "pagefile.sys: Allocated $([math]::Round($pf.AllocatedBaseSize / 1024, 2)) GB | CurrentUsage $([math]::Round($pf.CurrentUsage / 1024, 2)) GB | PeakUsage $([math]::Round($pf.PeakUsage / 1024, 2)) GB"
}

$rbItems = @((New-Object -ComObject Shell.Application).NameSpace(0x0a).Items())
$rb = $rbItems | Measure-Object -Property Size -Sum
Write-Output "Recycle Bin: $([math]::Round($rb.Sum / 1MB, 1)) MB ($($rbItems.Count) items)"
