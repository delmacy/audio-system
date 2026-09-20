[CmdletBinding()]
param([string]$Root = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$app = Join-Path $Root 'web\player-app'
$built = Join-Path $Root 'web\player\index.html'
$files = @(
  (Join-Path $app 'package.json'),
  (Join-Path $app 'src\App.tsx'),
  (Join-Path $app 'src\App.css'),
  (Join-Path $app 'src\timeline-model.ts'),
  (Join-Path $app 'src\timeline-store.ts')
)
foreach ($file in $files) { if (-not (Test-Path -LiteralPath $file)) { throw "Frontend source missing: $file" } }
Push-Location $app
try {
  & npm.cmd run build
  if ($LASTEXITCODE -ne 0) { throw "Vite build failed with exit $LASTEXITCODE" }
} finally { Pop-Location }
if (-not (Test-Path -LiteralPath $built)) { throw "Built frontend missing: $built" }
$timeline = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/timeline' -TimeoutSec 30
if ($timeline.schema -ne 'recorder-poc.timeline-observed.v1') { throw 'Observed timeline API schema mismatch.' }
if ($timeline.counts.media_intervals -lt 1) { throw 'No observed closed-MXF media intervals in the returned window.' }
if ($timeline.counts.media_intervals -ne ($timeline.counts.indexed_intervals + $timeline.counts.unindexed_intervals)) { throw 'Timeline provenance count mismatch.' }
$report = [ordered]@{
  schema = 'recorder-poc.web-player-v2-observed-shell-smoke.v1'
  result = 'PASS'
  gate_scope = 'react_typescript_build_and_observed_closed_mxf_timeline_api'
  evidence_scope = 'indexed_intervals_plus_unindexed_recorder_audit_navigation_only'
  frontend = $built
  window_start_utc = $timeline.window_start_utc
  window_end_utc = $timeline.window_end_utc
  counts = $timeline.counts
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$out = Join-Path $Root 'runs\web-player-shell\web-player-v2-shell-smoke-result.json'
New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent) | Out-Null
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "WEB PLAYER V2 SHELL: PASS (observed closed-MXF timeline; full evidence chain not claimed)"
Write-Host "Report: $out"
