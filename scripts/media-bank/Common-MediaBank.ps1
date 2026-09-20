Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    $p = Split-Path -Parent $PSScriptRoot
    return (Resolve-Path (Join-Path $p '..')).Path
}

function Join-Root([string]$Root, [string]$Relative) {
    if ([System.IO.Path]::IsPathRooted($Relative)) { return $Relative }
    return (Join-Path $Root $Relative)
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Find-FFmpeg {
    $candidates = @(
        'C:\ffmpeg\bin\ffmpeg.exe',
        'C:\Program Files\ffmpeg\bin\ffmpeg.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }
    return $null
}

function Get-SpeakerHint([string]$Path) {
    $s = $Path.ToLowerInvariant()
    if ($s -match 'controller|controlador|torre|tower|atc') { return 'controller' }
    if ($s -match 'pilot|piloto|aircraft|aeronave') { return 'pilot' }
    if ($s -match 'ring|toque') { return 'ring' }
    if ($s -match 'busy|ocupado') { return 'busy' }
    if ($s -match 'telephone|telefone|phone') { return 'telephone' }
    return 'unknown'
}

function Get-AudioFiles([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $exts = @('.wav','.mp3','.m4a','.aac','.ogg','.flac','.wma','.opus','.alaw','.ulaw')
    return @(Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() })
}

function Write-CsvUtf8NoType($Rows, [string]$Path) {
    $dir = Split-Path -Parent $Path
    Ensure-Dir $dir | Out-Null
    @($Rows) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}

function Read-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$Default) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    $in = $false
    foreach ($line in Get-Content -LiteralPath $Path) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#') -or $t.StartsWith(';')) { continue }
        if ($t -match '^\[(.+)\]$') { $in = ($Matches[1] -ieq $Section); continue }
        if ($in -and $t -match '^([^=]+)=(.*)$') {
            if ($Matches[1].Trim() -ieq $Key) { return $Matches[2].Trim() }
        }
    }
    return $Default
}
