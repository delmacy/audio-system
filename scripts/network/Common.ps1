Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-IniFile {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "INI file not found: $Path"
    }

    $result = @{}
    $section = ''
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith(';') -or $line.StartsWith('#')) { continue }

        if ($line -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim().ToLowerInvariant()
            if (-not $result.ContainsKey($section)) {
                $result[$section] = @{}
            }
            continue
        }

        $parts = $line -split '=', 2
        if ($parts.Count -ne 2) { continue }
        if ([string]::IsNullOrWhiteSpace($section)) {
            throw "INI key found outside a section: $line"
        }

        $key = $parts[0].Trim().ToLowerInvariant()
        $value = $parts[1].Trim()
        $result[$section][$key] = $value
    }

    return $result
}

function Get-IniValue {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Ini,
        [Parameter(Mandatory=$true)][string]$Section,
        [Parameter(Mandatory=$true)][string]$Key,
        [string]$Default = $null
    )

    $s = $Section.ToLowerInvariant()
    $k = $Key.ToLowerInvariant()
    if ($Ini.ContainsKey($s) -and $Ini[$s].ContainsKey($k)) {
        return [string]$Ini[$s][$k]
    }
    return $Default
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-IPv4ToUInt32 {
    param([Parameter(Mandatory=$true)][string]$Address)
    $ip = [System.Net.IPAddress]::Parse($Address)
    $bytes = $ip.GetAddressBytes()
    if ($bytes.Length -ne 4) { throw "Not an IPv4 address: $Address" }
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIPv4 {
    param([Parameter(Mandatory=$true)][uint32]$Value)
    $bytes = [BitConverter]::GetBytes($Value)
    [Array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Get-IPv4Sequence {
    param(
        [Parameter(Mandatory=$true)][string]$StartAddress,
        [Parameter(Mandatory=$true)][int]$Count
    )
    if ($Count -lt 0) { throw 'Count cannot be negative.' }
    $start = Convert-IPv4ToUInt32 $StartAddress
    $items = @()
    for ($i = 0; $i -lt $Count; $i++) {
        $items += Convert-UInt32ToIPv4 ([uint32]($start + $i))
    }
    return $items
}

function Get-DumpcapPath {
    $cmd = Get-Command dumpcap.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "$env:ProgramFiles\Wireshark\dumpcap.exe",
        "${env:ProgramFiles(x86)}\Wireshark\dumpcap.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function Get-DumpcapInterfaces {
    param([string]$DumpcapPath = $(Get-DumpcapPath))
    if (-not $DumpcapPath) { return @() }
    $lines = & $DumpcapPath -D 2>&1
    $items = @()
    foreach ($line in $lines) {
        $text = [string]$line
        if ($text -match '^\s*(\d+)\.\s+(.+)$') {
            $items += [pscustomobject]@{
                Index = [int]$Matches[1]
                Description = $Matches[2].Trim()
                Raw = $text.Trim()
            }
        }
    }
    return $items
}

function Resolve-CaptureInterface {
    param(
        [string]$Requested = 'auto',
        [string]$DumpcapPath = $(Get-DumpcapPath)
    )
    if (-not $DumpcapPath) { throw 'dumpcap.exe was not found. Install Wireshark/Npcap or add dumpcap to PATH.' }

    if ($Requested -and $Requested -ne 'auto') { return $Requested }

    $interfaces = Get-DumpcapInterfaces -DumpcapPath $DumpcapPath
    $loop = $interfaces | Where-Object {
        $_.Description -match 'NPF_Loopback|loopback traffic capture|Npcap Loopback'
    } | Select-Object -First 1

    if ($loop) { return [string]$loop.Index }

    throw 'Could not auto-detect the Npcap loopback capture interface. Run Get-NetworkInventory.ps1 and pass -CaptureInterface explicitly.'
}

function Convert-PrefixLengthToMask {
    param([Parameter(Mandatory=$true)][ValidateRange(0,32)][int]$PrefixLength)
    if ($PrefixLength -eq 0) { return '0.0.0.0' }
    $bits = ('1' * $PrefixLength).PadRight(32, '0')
    $octets = @()
    for ($i = 0; $i -lt 4; $i++) {
        $octets += [Convert]::ToInt32($bits.Substring($i * 8, 8), 2)
    }
    return ($octets -join '.')
}

function Test-IPv4InCidr {
    param(
        [Parameter(Mandatory=$true)][string]$Address,
        [Parameter(Mandatory=$true)][string]$Cidr
    )
    $parts = $Cidr -split '/', 2
    if ($parts.Count -ne 2) { throw "Invalid CIDR: $Cidr" }
    $prefix = [int]$parts[1]
    if ($prefix -lt 0 -or $prefix -gt 32) { throw "Invalid CIDR prefix: $Cidr" }
    $network = [uint64](Convert-IPv4ToUInt32 $parts[0])
    $ip = [uint64](Convert-IPv4ToUInt32 $Address)
    $mask = if ($prefix -eq 0) { [uint64]0 } else { (([uint64]4294967295 -shl (32 - $prefix)) -band [uint64]4294967295) }
    return (($network -band $mask) -eq ($ip -band $mask))
}

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-RepoRoot {
    $here = Split-Path -Parent $PSScriptRoot
    return (Split-Path -Parent $here)
}
