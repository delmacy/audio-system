[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Profile
)

. "$PSScriptRoot\Common.ps1"
$ini = Read-IniFile -Path $Profile
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

$mode = Get-IniValue $ini 'profile' 'mode'
$interface = Get-IniValue $ini 'network' 'interface'
$bindIp = Get-IniValue $ini 'network' 'bind_ip'
$recorderIp = Get-IniValue $ini 'recorder' 'ip'
$rtspPort = Get-IniValue $ini 'recorder' 'rtsp_port'
$sipIp = Get-IniValue $ini 'sip' 'proxy_ip'
$sipPort = Get-IniValue $ini 'sip' 'proxy_port'

foreach ($pair in @(
    @{Name='network.interface';Value=$interface},
    @{Name='network.bind_ip';Value=$bindIp},
    @{Name='recorder.ip';Value=$recorderIp},
    @{Name='recorder.rtsp_port';Value=$rtspPort}
)) {
    if (-not $pair.Value -or $pair.Value -eq 'CHANGE_ME') {
        $errors.Add("Missing required value: $($pair.Name)")
    }
}

foreach ($entry in @(
    @{Name='network.bind_ip';Value=$bindIp},
    @{Name='recorder.ip';Value=$recorderIp}
)) {
    if ($entry.Value -and $entry.Value -ne 'CHANGE_ME') {
        $parsed = $null
        if (-not [System.Net.IPAddress]::TryParse($entry.Value, [ref]$parsed)) {
            $errors.Add("Invalid IP address: $($entry.Name)=$($entry.Value)")
        }
    }
}

$adapter = $null
if ($interface -and $interface -ne 'CHANGE_ME') {
    $adapter = Get-NetAdapter -Name $interface -IncludeHidden -ErrorAction SilentlyContinue
    if (-not $adapter) { $errors.Add("Windows interface not found: $interface") }
}

if ($bindIp -and $bindIp -ne 'CHANGE_ME') {
    $bound = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $bindIp -ErrorAction SilentlyContinue
    if (-not $bound) { $errors.Add("bind_ip is not configured on this host: $bindIp") }
}

if ($mode -eq 'EXTERNAL_RECORDER') {
    $warnings.Add('EXTERNAL_RECORDER profile: validation does not send SIP, RTSP, RTP or ICMP traffic.')
    if ($sipIp -eq 'CHANGE_ME') { $warnings.Add('SIP proxy is still CHANGE_ME. This is acceptable only if the external test does not require SIP.') }
}

Write-Host "Profile: $Profile" -ForegroundColor Cyan
Write-Host "Mode:    $mode"
Write-Host "NIC:     $interface"
Write-Host "Bind IP: $bindIp"
Write-Host "Recorder: $recorderIp`:$rtspPort"
Write-Host "SIP:      $sipIp`:$sipPort"

foreach ($w in $warnings) { Write-Warning $w }
if ($errors.Count -gt 0) {
    Write-Host ''
    foreach ($e in $errors) { Write-Host "ERROR: $e" -ForegroundColor Red }
    Write-Host 'PROFILE VALIDATION: FAIL (NO TRAFFIC SENT)' -ForegroundColor Red
    exit 2
}

Write-Host ''
Write-Host 'PROFILE VALIDATION: PASS (NO TRAFFIC SENT)' -ForegroundColor Green
exit 0
