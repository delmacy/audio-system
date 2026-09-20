[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$Profile = $null,
    [Nullable[int]]$CwpACount,
    [Nullable[int]]$CwpBCount,
    [switch]$FullProfile
)

. "$PSScriptRoot\Common.ps1"

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($Profile)) {
    $Profile = Join-Path $repoRoot 'config\profiles\local-poc.ini'
}
$Profile = [System.IO.Path]::GetFullPath($Profile)

if (-not (Test-IsAdministrator)) {
    throw 'Setup-PocNetwork.ps1 must be run from an elevated PowerShell (Run as Administrator).'
}

$ini = Read-IniFile -Path $Profile
$desiredAlias = Get-IniValue $ini 'network' 'interface' 'POC-Loopback'
$bindIp = Get-IniValue $ini 'network' 'bind_ip'
$prefixLength = [int](Get-IniValue $ini 'network' 'prefix_length' '16')
$subnet = Get-IniValue $ini 'network' 'subnet'
$netmask = Convert-PrefixLengthToMask $prefixLength
$recorderIp = Get-IniValue $ini 'recorder' 'ip'
$sipIp = Get-IniValue $ini 'sip' 'proxy_ip'
$cwpAStart = Get-IniValue $ini 'cwp-a' 'ip_start'
$cwpBStart = Get-IniValue $ini 'cwp-b' 'ip_start'
$profileCountA = [int](Get-IniValue $ini 'cwp-a' 'count' '5')
$profileCountB = [int](Get-IniValue $ini 'cwp-b' 'count' '5')

if ($FullProfile) {
    $countA = $profileCountA
    $countB = $profileCountB
} else {
    # PowerShell can unwrap Nullable[T] parameters to ordinary values.  Under
    # StrictMode, testing .HasValue is therefore not portable between Windows
    # PowerShell 5.1 and newer PowerShell versions.  PSBoundParameters tells us
    # reliably whether the caller supplied the optional parameter.
    $countA = if ($PSBoundParameters.ContainsKey('CwpACount')) { [int]$CwpACount } else { [Math]::Min(2, $profileCountA) }
    $countB = if ($PSBoundParameters.ContainsKey('CwpBCount')) { [int]$CwpBCount } else { [Math]::Min(2, $profileCountB) }
}

if ($countA -lt 0 -or $countA -gt 100) { throw "CwpACount must be between 0 and 100. Received: $countA" }
if ($countB -lt 0 -or $countB -gt 100) { throw "CwpBCount must be between 0 and 100. Received: $countB" }

# Refuse to materialize the lab CIDR if another adapter already uses an address inside it.
# This avoids silently colliding with a corporate/VPN network such as 10.20.0.0/16.
if ($subnet) {
    $conflicts = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceAlias -ne $desiredAlias -and $_.IPAddress -notlike '169.254.*' -and (Test-IPv4InCidr $_.IPAddress $subnet)
    })
    if ($conflicts.Count -gt 0) {
        Write-Host 'The configured PoC subnet overlaps IPv4 addresses already present on another interface:' -ForegroundColor Red
        $conflicts | Format-Table InterfaceAlias, IPAddress, PrefixLength -AutoSize
        throw "Change [network].subnet/bind_ip and the endpoint ranges in the profile before continuing. Current lab subnet: $subnet"
    }
}

$adapter = Get-NetAdapter -Name $desiredAlias -IncludeHidden -ErrorAction SilentlyContinue
if (-not $adapter) {
    $km = @(Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceDescription -match 'KM-TEST Loopback' })
    if ($km.Count -eq 0) {
        throw 'No Microsoft KM-TEST Loopback Adapter found. Run Install-PocLoopback.ps1 first.'
    }
    if ($km.Count -gt 1) {
        throw "Multiple KM-TEST Loopback adapters found. Rename the intended one to '$desiredAlias' manually, then retry."
    }

    if ($PSCmdlet.ShouldProcess($km[0].Name, "Rename adapter to $desiredAlias")) {
        Rename-NetAdapter -Name $km[0].Name -NewName $desiredAlias
    }
    $adapter = Get-NetAdapter -Name $desiredAlias -IncludeHidden
}

if ($adapter.Status -eq 'Disabled') {
    if ($PSCmdlet.ShouldProcess($desiredAlias, 'Enable adapter')) {
        Enable-NetAdapter -Name $desiredAlias -Confirm:$false
    }
}

$required = @()
if ($bindIp -and $bindIp -ne 'CHANGE_ME') { $required += [pscustomobject]@{ Ip=$bindIp; Skip=$false; Role='LAB_BIND' } }
if ($recorderIp -and $recorderIp -ne 'CHANGE_ME') { $required += [pscustomobject]@{ Ip=$recorderIp; Skip=$true; Role='RECORDER' } }
if ($sipIp -and $sipIp -ne 'CHANGE_ME') { $required += [pscustomobject]@{ Ip=$sipIp; Skip=$true; Role='SIP_PROXY' } }
foreach ($ip in (Get-IPv4Sequence -StartAddress $cwpAStart -Count $countA)) {
    $required += [pscustomobject]@{ Ip=$ip; Skip=$true; Role='CWP_A' }
}
foreach ($ip in (Get-IPv4Sequence -StartAddress $cwpBStart -Count $countB)) {
    $required += [pscustomobject]@{ Ip=$ip; Skip=$true; Role='CWP_B' }
}

$current = @(Get-NetIPAddress -InterfaceAlias $desiredAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue)
foreach ($entry in $required) {
    $elsewhere = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $entry.Ip -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -ne $desiredAlias })
    if ($elsewhere.Count -gt 0) {
        throw "IP $($entry.Ip) already exists on another interface: $($elsewhere[0].InterfaceAlias)"
    }
    if ($current.IPAddress -contains $entry.Ip) {
        Write-Host ("EXISTS {0,-15} {1}" -f $entry.Ip, $entry.Role) -ForegroundColor DarkGray
        continue
    }

    if ($PSCmdlet.ShouldProcess("$desiredAlias / $($entry.Ip)", "Add IPv4 address ($($entry.Role))")) {
        try {
            New-NetIPAddress -InterfaceAlias $desiredAlias -IPAddress $entry.Ip -PrefixLength $prefixLength -AddressFamily IPv4 -SkipAsSource:$entry.Skip | Out-Null
        } catch {
            # Some Windows builds/drivers are happier with netsh for secondary IPs.
            $skip = if ($entry.Skip) { 'true' } else { 'false' }
            & netsh interface ipv4 add address name="$desiredAlias" address=$($entry.Ip) mask=$netmask type=unicast store=active skipassource=$skip | Out-Null
        }
        Write-Host ("ADDED  {0,-15} {1}" -f $entry.Ip, $entry.Role) -ForegroundColor Green
    }
}

Write-Host ''
Write-Host "Configured adapter: $desiredAlias" -ForegroundColor Cyan
Get-NetIPAddress -InterfaceAlias $desiredAlias -AddressFamily IPv4 | Sort-Object IPAddress |
    Format-Table IPAddress, PrefixLength, SkipAsSource -AutoSize

Write-Host "Phase-1 setup uses A=$countA and B=$countB endpoint IPs. Use -FullProfile later to materialize all addresses in the profile." -ForegroundColor Cyan
