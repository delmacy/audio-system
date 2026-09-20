[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reportPath = Join-Path $root 'runs\player-interaction-modes\player-v2-interaction-report.json'
New-Item -ItemType Directory -Force -Path (Split-Path $reportPath -Parent) | Out-Null
[ordered]@{
  schema = 'recorder-poc.player-v2-interaction-gate.v1'
  result = 'BLOCKED'
  gate_scope = 'historical_audio_playback_modes'
  reason = 'The new React timeline has visual demo interaction only; real closed-MXF playback modes are not connected yet.'
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host 'PLAYER INTERACTION MODES: BLOCKED — real playback modes not connected to the new frontend.'
Write-Host "Report: $reportPath"
exit 2
