Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\mxf\Common-Mxf.ps1')

$gstRuntimeBin = Find-GStreamerBin
if ($gstRuntimeBin -and -not (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\') -ieq $gstRuntimeBin.TrimEnd('\') })) {
    $env:PATH = $gstRuntimeBin + ';' + $env:PATH
}

function Read-IniFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    $result = @{}
    $section = ''
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim().ToLowerInvariant()
            if (-not $result.ContainsKey($section)) { $result[$section] = @{} }
            continue
        }
        if ($line -match '^([^=]+)=(.*)$') {
            if (-not $section) { throw "INI key outside section: $line" }
            $key = $Matches[1].Trim().ToLowerInvariant()
            $value = $Matches[2].Trim()
            $result[$section][$key] = $value
        }
    }
    return $result
}

function Find-RecorderHostExe {
    $root = Get-ProjectRoot
    return @(
        (Join-Path $root 'src\recorder-host\x64\Release\recorder-host.exe'),
        (Join-Path $root 'src\recorder-host\Release\recorder-host.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function ConvertTo-NativeArgumentString {
    param([string[]]$Arguments)
    $quoted = @()
    foreach ($arg in $Arguments) {
        if ($null -eq $arg) { $arg = '' }
        $s = [string]$arg
        if ($s -match '[\s"]') {
            $s = '"' + ($s -replace '(\\*)"', '$1$1\\"' -replace '(\\+)$', '$1$1') + '"'
        }
        $quoted += $s
    }
    return ($quoted -join ' ')
}

function Start-NativeProcessRedirected {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory=$true)][string]$StdOutPath,
        [Parameter(Mandatory=$true)][string]$StdErrPath,
        [string]$WorkingDirectory = $null
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ConvertTo-NativeArgumentString $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    if (-not $p.Start()) { throw "Failed to start: $FilePath" }
    $stdoutTask = $p.StandardOutput.ReadToEndAsync()
    $stderrTask = $p.StandardError.ReadToEndAsync()
    return [pscustomobject]@{
        Process = $p
        StdOutTask = $stdoutTask
        StdErrTask = $stderrTask
        StdOutPath = $StdOutPath
        StdErrPath = $StdErrPath
    }
}

function Complete-NativeProcessRedirected {
    param(
        [Parameter(Mandatory=$true)]$Handle,
        [int]$TimeoutMs = 30000
    )
    $p = $Handle.Process
    $timedOut = -not $p.WaitForExit($TimeoutMs)
    if ($timedOut) { try { $p.Kill() } catch {}; $p.WaitForExit() }
    else { $p.WaitForExit() }
    $stdout = $Handle.StdOutTask.Result
    $stderr = $Handle.StdErrTask.Result
    [IO.File]::WriteAllText($Handle.StdOutPath,[string]$stdout,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($Handle.StdErrPath,[string]$stderr,(New-Object Text.UTF8Encoding($false)))
    return [pscustomobject]@{
        ExitCode = if($timedOut){124}else{$p.ExitCode}
        TimedOut = $timedOut
        StdOut = $stdout
        StdErr = $stderr
    }
}
