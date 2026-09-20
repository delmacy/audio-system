[CmdletBinding()]
param(
    [string]$Profile = $null,
    [string]$CaptureInterface = 'auto',
    [int]$CaptureSeconds = 8,
    [string]$OutputDirectory = $null
)

. "$PSScriptRoot\Common.ps1"
$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($Profile)) {
    $Profile = Join-Path $repoRoot 'config\profiles\local-poc.ini'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot 'runs\network-smoke'
}
$Profile = [System.IO.Path]::GetFullPath($Profile)
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

$ini = Read-IniFile -Path $Profile
$addrA = Get-IniValue $ini 'cwp-a' 'ip_start' '10.20.1.101'
$addrB = Get-IniValue $ini 'cwp-b' 'ip_start' '10.20.2.101'

Ensure-Directory $OutputDirectory
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$pcap = Join-Path $OutputDirectory "phase1-$stamp.pcapng"
$inventory = Join-Path $OutputDirectory "phase1-$stamp-inventory.json"

& "$PSScriptRoot\Get-NetworkInventory.ps1" -OutputJson $inventory

$dumpcap = Get-DumpcapPath
if (-not $dumpcap) {
    throw 'dumpcap.exe not found. Install Wireshark with Npcap before running the smoke test.'
}
$iface = Resolve-CaptureInterface -Requested $CaptureInterface -DumpcapPath $dumpcap
$filter = 'udp portrange 41000-41099'

Write-Host ''
Write-Host "Starting dumpcap on interface: $iface" -ForegroundColor Cyan
Write-Host "Capture file: $pcap" -ForegroundColor Cyan
Write-Host "Capture filter: $filter" -ForegroundColor Cyan

$argString = "-i `"$iface`" -a duration:$CaptureSeconds -f `"$filter`" -w `"$pcap`" -q"
$proc = Start-Process -FilePath $dumpcap -ArgumentList $argString -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 1200

$testPassed = $false
try {
    & "$PSScriptRoot\Test-PocUdp.ps1" -AddressA $addrA -AddressB $addrB | Out-Host
    $testPassed = $true
} finally {
    try { $proc.WaitForExit(($CaptureSeconds + 3) * 1000) | Out-Null } catch {}
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}

if (-not (Test-Path -LiteralPath $pcap)) {
    throw 'dumpcap did not create the expected pcapng file.'
}

$size = (Get-Item -LiteralPath $pcap).Length
Write-Host ''
Write-Host "PCAPNG bytes: $size" -ForegroundColor Cyan
if ($testPassed -and $size -gt 0) {
    Write-Host 'PHASE-1 NETWORK SMOKE: PASS' -ForegroundColor Green
    Write-Host "Open in Wireshark: $pcap"
    Write-Host 'Display filter: udp.port == 41001 || udp.port == 41002'
    exit 0
}

Write-Host 'PHASE-1 NETWORK SMOKE: FAIL' -ForegroundColor Red
exit 3
