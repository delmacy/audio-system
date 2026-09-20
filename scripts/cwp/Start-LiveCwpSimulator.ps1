[CmdletBinding()]
param(
  [int]$Cycles = 0,
  [int]$PauseBetweenCyclesMs = 1000,
  [string]$LocalIp = '10.20.1.101',
  [string]$RecorderIp = '10.20.0.10',
  [int]$RecorderRtpPort = 20500,
  [int]$LocalRtpPort = 21500,
  [string]$EndpointId = 'CWP-LAB-01',
  [string]$ServiceId = 'lab-121500'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sim = Join-Path $PSScriptRoot 'Invoke-OneCwpSimulator.ps1'
$cycle = 0
Write-Host "LIVE CWP SIMULATOR READY endpoint=$EndpointId service=$ServiceId recorder=$RecorderIp`:$RecorderRtpPort"
while ($Cycles -eq 0 -or $cycle -lt $Cycles) {
  $cycle++
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sim -LocalIp $LocalIp -RecorderIp $RecorderIp -RtspPort 8554 -RecorderRtpPort $RecorderRtpPort -LocalRtpPort $LocalRtpPort -EndpointId $EndpointId -ServiceId $ServiceId -FirstRecordMs 1500 -PauseMs 500 -SecondRecordMs 1500
  if ($LASTEXITCODE -ne 0) { Write-Warning "CWP cycle $cycle failed with exit $LASTEXITCODE" }
  if ($PauseBetweenCyclesMs -gt 0) { Start-Sleep -Milliseconds $PauseBetweenCyclesMs }
}
