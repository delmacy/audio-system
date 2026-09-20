[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$Profile = $null,
    [int]$MaxCwpA = 100,
    [int]$MaxCwpB = 100
)

. "$PSScriptRoot\Common.ps1"
$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($Profile)) {
    $Profile = Join-Path $repoRoot 'config\profiles\local-poc.ini'
}
$Profile = [System.IO.Path]::GetFullPath($Profile)

if (-not (Test-IsAdministrator)) {
    throw 'Remove-PocNetwork.ps1 must be run as Administrator.'
}

$ini = Read-IniFile -Path $Profile
$alias = Get-IniValue $ini 'network' 'interface' 'POC-Loopback'
$ips = @(
    (Get-IniValue $ini 'network' 'bind_ip'),
    (Get-IniValue $ini 'recorder' 'ip'),
    (Get-IniValue $ini 'sip' 'proxy_ip')
)
$ips += @(Get-IPv4Sequence (Get-IniValue $ini 'cwp-a' 'ip_start') $MaxCwpA)
$ips += @(Get-IPv4Sequence (Get-IniValue $ini 'cwp-b' 'ip_start') $MaxCwpB)
$ips = $ips | Where-Object { $_ -and $_ -ne 'CHANGE_ME' } | Select-Object -Unique

foreach ($ip in $ips) {
    $existing = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -IPAddress $ip -ErrorAction SilentlyContinue
    if ($existing -and $PSCmdlet.ShouldProcess("$alias / $ip", 'Remove IPv4 address')) {
        Remove-NetIPAddress -InterfaceAlias $alias -IPAddress $ip -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "REMOVED $ip" -ForegroundColor Yellow
    }
}
