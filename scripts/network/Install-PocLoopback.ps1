[CmdletBinding()]
param()

. "$PSScriptRoot\Common.ps1"

$existing = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceDescription -match 'KM-TEST Loopback' })

if ($existing.Count -gt 0) {
    Write-Host 'Microsoft KM-TEST Loopback Adapter already present:' -ForegroundColor Green
    $existing | Format-Table ifIndex, Name, Status, InterfaceDescription -AutoSize
    exit 0
}

Write-Host 'No Microsoft KM-TEST Loopback Adapter was detected.' -ForegroundColor Yellow
Write-Host 'Opening the Windows Add Hardware wizard (hdwwiz.exe).' -ForegroundColor Yellow
Write-Host 'Choose: Install hardware manually -> Network adapters -> Microsoft -> Microsoft KM-TEST Loopback Adapter.'
Start-Process hdwwiz.exe
Write-Host ''
Write-Host 'After installation completes, run this script again, then run Setup-PocNetwork.ps1 as Administrator.' -ForegroundColor Cyan
