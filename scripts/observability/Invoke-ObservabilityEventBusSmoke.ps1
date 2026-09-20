[CmdletBinding()]
param(
    [int]$P0Events = 100,
    [int]$P1Events = 500,
    [int]$P2Events = 5000,
    [int]$P3Events = 10000,
    [int]$SinkStallMs = 1500
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$runId = 'observability-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff') + '-' + $PID
$runDir = Join-Path $root "runs\observability\$runId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$auditPath = Join-Path $runDir 'audit.jsonl'
$metricsPath = Join-Path $runDir 'recorder.prom'
$reportPath = Join-Path $runDir 'observability-report.json'

$capacities = @{ P0 = 4096; P1 = 8192; P2 = 4096; P3 = 2048 }
$queues = @{ P0 = [Collections.Generic.Queue[object]]::new(); P1 = [Collections.Generic.Queue[object]]::new(); P2 = [Collections.Generic.Queue[object]]::new(); P3 = [Collections.Generic.Queue[object]]::new() }
$accepted = @{ P0 = 0; P1 = 0; P2 = 0; P3 = 0 }
$dropped = @{ P0 = 0; P1 = 0; P2 = 0; P3 = 0 }
$coalesced = @{ P0 = 0; P1 = 0; P2 = 0; P3 = 0 }
$exported = @{ P0 = 0; P1 = 0; P2 = 0; P3 = 0 }
$seq = 0L

function New-Event([string]$Priority,[string]$Type,[int]$Ordinal) {
    $script:seq++
    [pscustomobject][ordered]@{
        schema='recorder-poc.event.v1'; event_id=[guid]::NewGuid().ToString(); producer_sequence=$script:seq
        utc=[DateTime]::UtcNow.ToString('o'); priority=$Priority; event_type=$Type
        recorder_id='RECORDER-01'; service_id=('SVC-{0:D3}' -f ($Ordinal % 20)); endpoint_id=('CWP-{0:D2}' -f ($Ordinal % 10))
        logical_track_uuid=$null; session_id=$null; file_id=$null; track_instance_uuid=$null
        payload=[ordered]@{ ordinal=$Ordinal }
    }
}
function Enqueue-Event([object]$Event) {
    $p = [string]$Event.priority
    $q = $queues[$p]
    if ($q.Count -lt $capacities[$p]) { $q.Enqueue($Event); $accepted[$p]++; return }
    if ($p -eq 'P2') { $coalesced[$p]++; return }
    if ($p -eq 'P3') { $dropped[$p]++; return }
    if ($p -eq 'P1') { $dropped[$p]++; return }
    throw 'P0 queue saturation: required evidence could not be preserved.'
}

1..$P0Events | ForEach-Object { Enqueue-Event (New-Event P0 'GAP_START' $_) }
1..$P1Events | ForEach-Object { Enqueue-Event (New-Event P1 'SQU_ON' $_) }
1..$P2Events | ForEach-Object { Enqueue-Event (New-Event P2 'METRIC_SAMPLE' $_) }
1..$P3Events | ForEach-Object { Enqueue-Event (New-Event P3 'DEBUG_TRACE' $_) }

Start-Sleep -Milliseconds $SinkStallMs
foreach ($p in 'P0','P1','P2','P3') {
    while ($queues[$p].Count -gt 0) {
        $event = $queues[$p].Dequeue()
        ($event | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $auditPath -Encoding UTF8
        $exported[$p]++
    }
}

$metricLines = @(
  '# TYPE recorder_event_bus_accepted_total counter'
  "recorder_event_bus_accepted_total{priority=`"P0`"} $($accepted.P0)"
  "recorder_event_bus_accepted_total{priority=`"P1`"} $($accepted.P1)"
  "recorder_event_bus_accepted_total{priority=`"P2`"} $($accepted.P2)"
  "recorder_event_bus_accepted_total{priority=`"P3`"} $($accepted.P3)"
  '# TYPE recorder_event_bus_dropped_total counter'
  "recorder_event_bus_dropped_total{priority=`"P0`"} $($dropped.P0)"
  "recorder_event_bus_dropped_total{priority=`"P1`"} $($dropped.P1)"
  "recorder_event_bus_dropped_total{priority=`"P2`"} $($dropped.P2)"
  "recorder_event_bus_dropped_total{priority=`"P3`"} $($dropped.P3)"
  '# TYPE recorder_event_bus_coalesced_total counter'
  "recorder_event_bus_coalesced_total{priority=`"P2`"} $($coalesced.P2)"
  '# TYPE recorder_event_bus_queue_depth gauge'
  'recorder_event_bus_queue_depth{priority="P0"} 0'
  'recorder_event_bus_queue_depth{priority="P1"} 0'
  'recorder_event_bus_queue_depth{priority="P2"} 0'
  'recorder_event_bus_queue_depth{priority="P3"} 0'
)
$metricLines | Set-Content -LiteralPath $metricsPath -Encoding ASCII

$pass = ($dropped.P0 -eq 0 -and $exported.P0 -eq $P0Events -and $queues.P0.Count -eq 0 -and $queues.P1.Count -eq 0 -and $queues.P2.Count -eq 0 -and $queues.P3.Count -eq 0)
$report = [ordered]@{
  schema='recorder-poc.phase12-observability-smoke.v1'; result=if($pass){'PASS'}else{'FAIL'}; run_id=$runId
  gate_scope='in_memory_event_bus_harness'; recorder_connected=$false; p0_saturation_tested=$false
  sink_stall_ms=$SinkStallMs; accepted=$accepted; exported=$exported; dropped=$dropped; coalesced=$coalesced
  p0_loss=($P0Events-$exported.P0); audit_path=$auditPath; metrics_path=$metricsPath
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host '=== Phase 12 Observability Event Bus Smoke ==='
Write-Host ("P0 accepted/exported/lost: {0}/{1}/{2}" -f $accepted.P0,$exported.P0,($P0Events-$exported.P0))
Write-Host ("P3 dropped under pressure: {0}" -f $dropped.P3)
Write-Host ("P2 coalesced under pressure: {0}" -f $coalesced.P2)
Write-Host "Audit: $auditPath"
Write-Host "Metrics: $metricsPath"
Write-Host "Report: $reportPath"
if (-not $pass) { Write-Error 'PHASE 12 OBSERVABILITY EVENT BUS: FAIL'; exit 1 }
Write-Host 'PHASE 12 OBSERVABILITY EVENT BUS: PASS'
