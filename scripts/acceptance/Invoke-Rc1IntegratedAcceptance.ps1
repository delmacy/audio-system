[CmdletBinding()]
param([string]$Root = '',[string]$RunId = ('rc1-acceptance-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff')))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$scenario = Get-Content -LiteralPath (Join-Path $Root 'scenarios\acceptance\integrated-acceptance-01.json') -Raw | ConvertFrom-Json
$rc1Dir = (Get-Content -LiteralPath (Join-Path $Root 'runs\rc1\current-run.txt') -Raw).Trim()
$runDir = Join-Path $Root "runs\acceptance\$RunId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$mapping = @{
  '01-network'='01-network-rc1*'
  '02-mxf-identity-file-manager'='02-mxf-file-manager-loaded-prearm-rc1*'
  '03-recorder-one-cwp'='02-one-cwp-smoke*'
  '04-radio-persistent-session'='03-radio-persistent-session-smoke*'
  '05-multi-session-routing'='04-multi-cwp-routing-smoke*'
  '06-media-engine-rtp-protection'='05-media-engine-smoke*'
  '07-window-rotation'='06-window-rotation-media-offset*'
  '08-recording-gateway'='07-recording-gateway-smoke*'
  '09-service-perspective-matrix'='08-service-perspective-tone-validation*'
  '11-temporal-index'='09-temporal-index-smoke-media-offset*'
  '12-observability-eventbus'='10-observability-event-bus-smoke-retry1*'
  '13-historical-playback'='11-historical-playback-media-offset-retry1*'
  '14-segment-export'='12-playback-segment-export-smoke-retry3*'
  '15-web-player-shell'='13-web-player-shell-smoke-retry2*'
  '16-player-interaction-modes'='14-player-interaction-modes-smoke-retry1*'
  '17-live-player-branch'='15-live-player-branch-smoke*'
  '18-evidence-bundle'='16-export-evidence-bundle-smoke-retry1*'
  '19-integrity-manifest-chain'='17-integrity-manifest-chain-real*'
  '20-fault-injection-recovery'='18-fault-injection-real-subset*'
  '21-progressive-stress'='19-progressive-stress-real-subset*'
}
$partial = @{
  '12-observability-eventbus'='In-memory harness only; no Recorder sink saturation or P0 spill.'
  '15-web-player-shell'='Static player fixture only; historical API and browser path not exercised.'
  '16-player-interaction-modes'='Static mode contract only; real playback UI not exercised.'
  '17-live-player-branch'='Static fixture only; Recorder live tap not exercised.'
  '18-evidence-bundle'='Real source MXFs and WAV hashed, but Recorder-generated recording-file manifests are absent.'
  '19-integrity-manifest-chain'='External reconstructed source manifest verified; Recorder-generated manifest chain absent.'
  '20-fault-injection-recovery'='Real RTP impairment subset passed; five recovery scenarios NOT_RUN.'
  '21-progressive-stress'='Direct mono load L1-L5 passed; Gateway mix, fault overlays and long soak NOT_RUN.'
}
$results = @()
foreach ($entry in $scenario.gates) {
  $id = [string]$entry[0]; $script = [string]$entry[1]; $required = [bool]$entry[2]
  $status = 'NOT_RUN'; $evidence = $null; $reason = 'No RC1 execution evidence.'
  if ($mapping.ContainsKey($id)) {
    $candidates = @(Get-ChildItem -LiteralPath $rc1Dir -Filter ($mapping[$id] + '.invocation.json') -File -ErrorAction SilentlyContinue)
    $successful = @($candidates | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Add-Member -NotePropertyName source_path -NotePropertyValue $_.FullName -PassThru } | Where-Object { [int]$_.exit_code -eq 0 } | Sort-Object started_utc -Descending)
    if ($successful.Count -gt 0) {
      $inv = $successful[0]
      $status = 'PASS'; $evidence = [string]$inv.source_path; $reason = 'RC1 command exited 0; see invocation and captured output.'
    } elseif ($candidates.Count -gt 0) {
      $inv = Get-Content -LiteralPath $candidates[0].FullName -Raw | ConvertFrom-Json
      $evidence = $candidates[0].FullName
      $status = if ([int]$inv.exit_code -eq 2) { 'BLOCKED' } else { 'FAIL' }
      $reason = "RC1 command exit code $($inv.exit_code)."
    }
  }
  if ($partial.ContainsKey($id) -and $status -ne 'NOT_RUN' -and $status -ne 'FAIL') { $status='BLOCKED'; $reason=$partial[$id] }
  $results += [pscustomobject]@{gate_id=$id;script=$script;required=$required;status=$status;simulated=$false;evidence_path=$evidence;reason=$reason}
}
$requiredFailures = @($results | Where-Object { $_.required -and $_.status -eq 'FAIL' })
$requiredIncomplete = @($results | Where-Object { $_.required -and $_.status -ne 'PASS' })
$verdict = if ($requiredFailures.Count -gt 0) { 'FAIL' } elseif ($requiredIncomplete.Count -gt 0) { 'BLOCKED' } else { 'PASS' }
$report = [ordered]@{schema='recorder-poc.rc1-integrated-acceptance.v1';run_id=$RunId;generated_utc=(Get-Date).ToUniversalTime().ToString('o');simulated=$false;verdict=$verdict;required_passed=@($results | Where-Object { $_.required -and $_.status -eq 'PASS' }).Count;required_total=@($results | Where-Object required).Count;invariants=$scenario.invariants;gates=$results}
$reportPath = Join-Path $runDir 'integrated-acceptance-report.json'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8
$results | Export-Csv -LiteralPath (Join-Path $runDir 'integrated-acceptance-summary.csv') -NoTypeInformation -Encoding utf8
$md = @('# RC1 integrated acceptance','','Verdict: **' + $verdict + '**','','This report aggregates recorded RC1 invocations. PASS is scoped to the command run and its evidence.','','| Gate | Required | Status | Reason |','|---|---:|---|---|')
foreach ($row in $results) { $md += "| $($row.gate_id) | $($row.required) | $($row.status) | $($row.reason) |" }
$md -join "`r`n" | Set-Content -LiteralPath (Join-Path $runDir 'integrated-acceptance-report.md') -Encoding utf8
Write-Host "Report: $reportPath"
Write-Host "RC1 INTEGRATED ACCEPTANCE: $verdict (required PASS $($report.required_passed)/$($report.required_total))"
if ($verdict -eq 'FAIL') { exit 1 }
if ($verdict -eq 'BLOCKED') { exit 2 }
