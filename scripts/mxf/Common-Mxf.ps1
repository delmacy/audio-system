Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Find-Executable {
    param([Parameter(Mandatory=$true)][string[]]$Names)
    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Find-GStreamerBin {
    $gst = Find-Executable @('gst-launch-1.0.exe','gst-launch-1.0')
    if ($gst) { return (Split-Path $gst -Parent) }

    $candidates = @()
    if ($env:GSTREAMER_ROOT_X86_64) { $candidates += (Join-Path $env:GSTREAMER_ROOT_X86_64 'bin') }
    if ($env:GSTREAMER_ROOT_X86) { $candidates += (Join-Path $env:GSTREAMER_ROOT_X86 'bin') }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\gstreamer\1.0\msvc_x86_64\bin') }
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'gstreamer\1.0\msvc_x86_64\bin') }

    foreach ($dir in $candidates) {
        if ($dir -and (Test-Path (Join-Path $dir 'gst-launch-1.0.exe'))) { return $dir }
    }
    return $null
}

function Get-GstTool {
    param([Parameter(Mandatory=$true)][string]$Name)
    $bin = Find-GStreamerBin
    if (-not $bin) { return $null }
    $exe = Join-Path $bin $Name
    if (Test-Path $exe) { return $exe }
    return $null
}

function Ensure-RunDirectory {
    param([string]$Name = 'mxf-spike')
    $root = Get-ProjectRoot
    $dir = Join-Path $root ("runs\" + $Name)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Assert-GStreamerMxf {
    $inspect = Get-GstTool 'gst-inspect-1.0.exe'
    if (-not $inspect) { throw 'GStreamer not found. Run 00-inventory.cmd and install the official 64-bit MSVC runtime if needed.' }

    foreach ($plugin in @('mxfmux','mxfdemux','alawenc','alawdec','audiotestsrc','queue','filesink','fakesink')) {
        & $inspect $plugin *> $null
        if ($LASTEXITCODE -ne 0) { throw "Required GStreamer element missing: $plugin" }
    }
}

function Invoke-ExternalChecked {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw ("Command failed with exit code {0}: {1}" -f $LASTEXITCODE, $FilePath) }
}

function Invoke-NativeProcessCapture {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $null,
        [int]$TimeoutMs = 0
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }

    # .NET Framework / Windows PowerShell 5.1 does not provide ArgumentList,
    # so quote arguments explicitly.
    $quoted = @()
    foreach ($arg in $Arguments) {
        if ($null -eq $arg) { $arg = '' }
        $s = [string]$arg
        if ($s -match '[\s"]') {
            $s = '"' + ($s -replace '(\\*)"', '$1$1\\"' -replace '(\\+)$', '$1$1') + '"'
        }
        $quoted += $s
    }
    $psi.Arguments = ($quoted -join ' ')

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    if (-not $p.Start()) { throw "Failed to start native process: $FilePath" }

    # Read both pipes asynchronously to avoid stdout/stderr deadlocks.
    $stdoutTask = $p.StandardOutput.ReadToEndAsync()
    $stderrTask = $p.StandardError.ReadToEndAsync()
    $timedOut = $false

    if ($TimeoutMs -gt 0) {
        if (-not $p.WaitForExit($TimeoutMs)) {
            $timedOut = $true
            try { $p.Kill() } catch {}
        }
    } else {
        $p.WaitForExit()
    }
    $p.WaitForExit()

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $exitCode = if ($timedOut) { 124 } else { $p.ExitCode }
    try { $p.Refresh() } catch {}
    $peakWorkingSet64 = try { [int64]$p.PeakWorkingSet64 } catch { [int64]0 }
    $totalProcessorMs = try { [math]::Round($p.TotalProcessorTime.TotalMilliseconds, 1) } catch { 0 }
    $userProcessorMs = try { [math]::Round($p.UserProcessorTime.TotalMilliseconds, 1) } catch { 0 }

    return [pscustomobject]@{
        ExitCode = $exitCode
        StdOut = $stdout
        StdErr = $stderr
        TimedOut = $timedOut
        PeakWorkingSet64 = $peakWorkingSet64
        TotalProcessorMs = $totalProcessorMs
        UserProcessorMs = $userProcessorMs
        FilePath = $FilePath
        Arguments = @($Arguments)
    }
}
