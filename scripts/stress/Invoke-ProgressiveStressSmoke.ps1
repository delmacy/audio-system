[CmdletBinding()]
param(
  [string]$Root = '',
  [string]$ScenarioPath = 'scenarios\stress\progressive-stress-01.json',
  [string]$RunId = ('progressive-stress-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$scenario = Get-Content -LiteralPath (Join-Path $Root $ScenarioPath) -Raw | ConvertFrom-Json
if ($scenario.schema -ne 'recorder-poc.progressive-stress.v1' -or $scenario.media_model.media_flow -ne 'mono' -or -not $scenario.media_model.one_service_one_logical_track -or $scenario.media_model.rx_tx_track_split_allowed) { throw 'Invalid stress scenario media model.' }
$rc1Dir = (Get-Content -LiteralPath (Join-Path $Root 'runs\rc1\current-run.txt') -Raw).Trim()
$runDir = Join-Path $Root "runs\stress\$RunId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$names = @{ L1='19-load-L1-one-service'; L2='19-load-L2-five-services'; L3='19-load-L3-ten-services'; L4='19-load-L4-thirty-services'; L5='19-load-L5-fifty-services' }
$rounds = @()
foreach ($level in $scenario.levels) {
  $name = $names[[string]$level.level]
  $status = 'NOT_RUN'; $evidence = $null; $directCount = 0
  if ($name) {
    $invocationPath = Join-Path $rc1Dir "$name.invocation.json"
    $outputPath = Join-Path $rc1Dir "$name.stdout-stderr.txt"
    if ((Test-Path -LiteralPath $invocationPath) -and (Test-Path -LiteralPath $outputPath)) {
      $invocation = Get-Content -LiteralPath $invocationPath -Raw | ConvertFrom-Json
      $output = Get-Content -LiteralPath $outputPath -Raw
      $match = [regex]::Match($output,'(?m)^Report: (.+service-perspective-matrix-report\.json)\s*$')
      if ($match.Success -and [int]$invocation.exit_code -eq 0) {
        $evidence = $match.Groups[1].Value.Trim()
        $direct = Get-Content -LiteralPath $evidence -Raw | ConvertFrom-Json
        $directCount = [int]$direct.sessions
        if ($direct.result -eq 'PASS' -and $directCount -eq [int]$level.services -and [int]$direct.unique_logical_tracks -eq $directCount -and [int]$direct.mono_streams_verified -eq $directCount -and $direct.no_rx_tx_split) { $status = 'PASS' } else { $status = 'FAIL' }
      } else { $status = 'FAIL' }
    }
  }
  $rounds += [pscustomobject]@{level=[string]$level.level;planned_services=[int]$level.services;direct_load_status=$status;direct_services_executed=$directCount;gateway_mix_status='NOT_RUN';fault_overlay_status=$(if($level.fault_overlay -eq 'none'){'NOT_APPLICABLE'}else{'NOT_RUN'});evidence=$evidence}
}
$directFailures = @($rounds | Where-Object { $_.direct_load_status -eq 'FAIL' })
$result = if ($directFailures.Count -gt 0) { 'FAIL' } else { 'BLOCKED' }
$report = [ordered]@{
  schema='recorder-poc.progressive-stress-report.v2'
  result=$result
  gate_scope='real_direct_rtsp_rtp_mono_load_subset'
  simulated=$false
  scenario_id=$scenario.scenario_id
  run_id=$RunId
  generated_utc=(Get-Date).ToUniversalTime().ToString('o')
  direct_load_levels_passed=@($rounds | Where-Object { $_.direct_load_status -eq 'PASS' }).Count
  gateway_mix_executed=$false
  fault_overlays_executed=$false
  long_duration_soak_executed=$false
  optional_L6_status='NOT_RUN'
  rounds=$rounds
}
$reportPath = Join-Path $runDir 'stress-run-report.json'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8
$rounds | Export-Csv -LiteralPath (Join-Path $runDir 'stress-rounds.csv') -NoTypeInformation -Encoding utf8
Write-Host "Report: $reportPath"
Write-Host "PROGRESSIVE STRESS: $result (direct mono load levels PASS=$($report.direct_load_levels_passed)/5; gateway mix, overlays, soak NOT_RUN)"
if ($result -eq 'FAIL') { exit 1 }
exit 2
