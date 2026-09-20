Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('Poc.Win32FileGuard' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Poc {
    public static class Win32FileGuard {
        public const uint FILE_SHARE_READ = 0x00000001;
        public const uint FILE_SHARE_WRITE = 0x00000002;
        public const uint OPEN_ALWAYS = 4;
        public const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern SafeFileHandle CreateFileW(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile);
    }
}
'@
}

function Open-MxfDeleteGuard {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path $full -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

    # desiredAccess=0: metadata-only guard. It does not compete with the writer's
    # read/write access. Share READ+WRITE, intentionally NOT SHARE_DELETE.
    # Delete and rename require delete access on Windows, so they are denied while
    # this handle remains open.
    $h = [Poc.Win32FileGuard]::CreateFileW(
        $full,
        [uint32]0,
        [Poc.Win32FileGuard]::FILE_SHARE_READ -bor [Poc.Win32FileGuard]::FILE_SHARE_WRITE,
        [IntPtr]::Zero,
        [Poc.Win32FileGuard]::OPEN_ALWAYS,
        [Poc.Win32FileGuard]::FILE_ATTRIBUTE_NORMAL,
        [IntPtr]::Zero)
    if ($h.IsInvalid) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "CreateFileW delete guard failed for '$full' (Win32=$err)."
    }
    return $h
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Path
    )
    $tmp = $Path + '.tmp'
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function New-MxfLifecycleRecord {
    param(
        [Parameter(Mandatory=$true)][string]$FileId,
        [Parameter(Mandatory=$true)][string]$PartialPath,
        [Parameter(Mandatory=$true)][string]$FinalPath,
        [Parameter(Mandatory=$true)][string]$LockPath,
        [int]$ExpectedTracks = 0
    )
    $now = [DateTime]::UtcNow.ToString('o')
    return [ordered]@{
        schema = 'recorder-poc.mxf-lock.v1'
        file_id = $FileId
        state = 'RECORDING_LOCKED'
        recorder_pid = $PID
        writer_pid = $null
        created_utc = $now
        heartbeat_utc = $now
        partial_path = [IO.Path]::GetFullPath($PartialPath)
        final_path = [IO.Path]::GetFullPath($FinalPath)
        lock_path = [IO.Path]::GetFullPath($LockPath)
        expected_tracks = $ExpectedTracks
        last_received = $null
        last_written = $null
        last_durable = $null
    }
}

function Update-MxfLifecycleRecord {
    param(
        [Parameter(Mandatory=$true)]$Record,
        [Parameter(Mandatory=$true)][string]$LockPath,
        [string]$State,
        [Nullable[int]]$WriterPid
    )
    if ($State) { $Record.state = $State }
    if ($null -ne $WriterPid) { $Record.writer_pid = [int]$WriterPid }
    $Record.heartbeat_utc = [DateTime]::UtcNow.ToString('o')
    Write-JsonAtomic -Object $Record -Path $LockPath
}

function Test-PidAlive {
    param([Nullable[int]]$ProcessId)
    if ($null -eq $ProcessId -or $ProcessId -le 0) { return $false }
    return [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Read-MxfLock {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Lock file not found: $Path" }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-MxfLockDisposition {
    param([Parameter(Mandatory=$true)]$Lock)
    $recAlive = Test-PidAlive ([Nullable[int]]$Lock.recorder_pid)
    $writerAlive = Test-PidAlive ([Nullable[int]]$Lock.writer_pid)
    if ($recAlive -or $writerAlive) { return 'ACTIVE_LOCK' }
    return 'STALE_LOCK'
}

function Test-DeleteRenameBlocked {
    param([Parameter(Mandatory=$true)][string]$PartialPath)
    $deleteBlocked = $false
    $renameBlocked = $false
    $renameTarget = $PartialPath + '.rename-probe'
    try {
        Remove-Item -LiteralPath $PartialPath -Force -ErrorAction Stop
    } catch {
        $deleteBlocked = $true
    }
    if (-not (Test-Path -LiteralPath $PartialPath)) {
        # Restore an empty placeholder only if a platform unexpectedly allowed delete.
        New-Item -ItemType File -Force -Path $PartialPath | Out-Null
    }
    try {
        Move-Item -LiteralPath $PartialPath -Destination $renameTarget -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $renameTarget) {
            Move-Item -LiteralPath $renameTarget -Destination $PartialPath -Force
        }
    } catch {
        $renameBlocked = $true
    }
    return [pscustomobject]@{
        DeleteBlocked = $deleteBlocked
        RenameBlocked = $renameBlocked
    }
}
