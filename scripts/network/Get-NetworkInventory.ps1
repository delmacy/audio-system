[CmdletBinding()]
param(
    [string]$OutputJson
)

. "$PSScriptRoot\Common.ps1"

$adapters = Get-NetAdapter -IncludeHidden | Sort-Object ifIndex | ForEach-Object {
    $adapter = $_
    $ips = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } |
        Select-Object -ExpandProperty IPAddress)
    [pscustomobject]@{
        ifIndex = $adapter.ifIndex
        Name = $adapter.Name
        InterfaceDescription = $adapter.InterfaceDescription
        Status = $adapter.Status
        MacAddress = $adapter.MacAddress
        IPv4 = $ips
    }
}

$dumpcap = Get-DumpcapPath
$captureInterfaces = @()
if ($dumpcap) {
    $captureInterfaces = @(Get-DumpcapInterfaces -DumpcapPath $dumpcap)
}

$result = [pscustomobject]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    Hostname = $env:COMPUTERNAME
    IsAdministrator = (Test-IsAdministrator)
    DumpcapPath = $dumpcap
    Adapters = $adapters
    CaptureInterfaces = $captureInterfaces
}

Write-Host ''
Write-Host '=== Windows network adapters ===' -ForegroundColor Cyan
$result.Adapters | Format-Table ifIndex, Name, Status, InterfaceDescription, @{N='IPv4';E={($_.IPv4 -join ', ')}} -AutoSize

Write-Host ''
Write-Host '=== dumpcap capture interfaces ===' -ForegroundColor Cyan
if ($dumpcap) {
    $captureInterfaces | Format-Table Index, Description -AutoSize
} else {
    Write-Warning 'dumpcap.exe not found. Install Wireshark/Npcap before the capture smoke test.'
}

if ($OutputJson) {
    $parent = Split-Path -Parent $OutputJson
    if ($parent) { Ensure-Directory $parent }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputJson -Encoding UTF8
    Write-Host "Inventory written to: $OutputJson" -ForegroundColor Green
}
