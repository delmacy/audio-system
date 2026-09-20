[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reportPath = Join-Path $root 'runs\live-player-branch\player-v2-live-report.json'
New-Item -ItemType Directory -Force -Path (Split-Path $reportPath -Parent) | Out-Null
[ordered]@{
  schema = 'recorder-poc.player-v2-live-gate.v1'
  result = 'BLOCKED'
  gate_scope = 'live_preview_frontend'
  reason = 'The new React timeline is a visual demo. A recorder live tap and live frontend are not connected.'
  evidence = $false
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host 'LIVE PLAYER BRANCH: BLOCKED — live tap/frontend not connected.'
Write-Host "Report: $reportPath"
exit 2
