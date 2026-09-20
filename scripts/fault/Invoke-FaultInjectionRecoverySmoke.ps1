[CmdletBinding()]
param(
  [string]$Root = '',
  [string]$RunId = ('fault-injection-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$runRoot = Join-Path $Root "runs\fault-injection\$RunId"
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$command = Join-Path $Root 'scripts\recorder\05-media-engine-smoke.cmd'
$output = & $command 2>&1
$exitCode = $LASTEXITCODE
$output | Out-File -LiteralPath (Join-Path $runRoot 'media-engine.stdout-stderr.txt') -Encoding utf8
$phase6Dir = Get-ChildItem -LiteralPath (Join-Path $Root 'runs\phase6-media-engine') -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$phase6Path = if ($phase6Dir) { Join-Path $phase6Dir.FullName 'phase6-media-engine-report.json' } else { '' }
$phase6 = if ($phase6Path -and (Test-Path -LiteralPath $phase6Path)) { Get-Content -LiteralPath $phase6Path -Raw | ConvertFrom-Json } else { $null }
$rtpPass = $exitCode -eq 0 -and $phase6 -and $phase6.result -eq 'PASS' -and
  [int64]$phase6.actual.sequence_gap_packets -gt 0 -and [int64]$phase6.actual.duplicates -gt 0 -and
  [int64]$phase6.actual.out_of_order -gt 0 -and [int64]$phase6.actual.malformed -gt 0 -and
  [int64]$phase6.actual.wrong_pt -gt 0 -and [int64]$phase6.actual.timestamp_discontinuities -gt 0
$cases = @(
  [ordered]@{case='rtp_impairments';status=$(if($rtpPass){'PASS'}else{'FAIL'});evidence=$phase6Path},
  [ordered]@{case='rtsp_drop_and_recovery';status='NOT_RUN';evidence=$null},
  [ordered]@{case='indexer_restart';status='NOT_RUN';evidence=$null},
  [ordered]@{case='observability_sink_degradation';status='NOT_RUN';evidence=$null},
  [ordered]@{case='export_retry';status='NOT_RUN';evidence=$null},
  [ordered]@{case='partial_file_recovery';status='NOT_RUN';evidence=$null}
)
$result = if (-not $rtpPass) { 'FAIL' } else { 'BLOCKED' }
$report = [ordered]@{
  schema='recorder-poc.fault-injection-report.v2'
  result=$result
  gate_scope='real_recorder_rtp_fault_subset'
  simulated=$false
  recorded_evidence=$true
  run_id=$RunId
  generated_at_utc=(Get-Date).ToUniversalTime().ToString('o')
  command=$command
  command_exit_code=$exitCode
  command_output='media-engine.stdout-stderr.txt'
  injected_fault_cases_passed=$(if($rtpPass){6}else{0})
  remaining_scenario_cases_not_run=5
  cases=$cases
}
$reportPath = Join-Path $runRoot 'fault-injection-report.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host "Report: $reportPath"
Write-Host "FAULT INJECTION/RECOVERY: $result (RTP subset $(if($rtpPass){'PASS'}else{'FAIL'}); recovery cases NOT_RUN)"
if ($result -eq 'FAIL') { exit 1 }
exit 2
