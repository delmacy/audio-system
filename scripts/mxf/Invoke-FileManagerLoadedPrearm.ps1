param(
    [int]$FileCount = 100,
    [int]$ActivePercent = 25,
    [int]$PrecreateLeadMs = 3000,
    [int]$ReadyDeadlineMs = 250,
    [int]$ActivationDispatchBudgetMs = 250,
    [int]$WarmupMs = 500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')

if ($FileCount -lt 1) { throw 'FileCount must be >= 1.' }
if ($ActivePercent -lt 25 -or $ActivePercent -gt 100) { throw 'ActivePercent must be between 25 and 100.' }
if ($PrecreateLeadMs -le $ReadyDeadlineMs) { throw 'PrecreateLeadMs must be greater than ReadyDeadlineMs.' }

function UtcIso([DateTime]$Value) { return $Value.ToUniversalTime().ToString('o') }
function MsBetween([DateTime]$A, [DateTime]$B) { return [math]::Round($B.ToUniversalTime().Subtract($A.ToUniversalTime()).TotalMilliseconds, 3) }
function WaitUntilUtc([DateTime]$TargetUtc) {
    while ($true) {
        $remaining = $TargetUtc.Subtract([DateTime]::UtcNow).TotalMilliseconds
        if ($remaining -le 0) { break }
        if ($remaining -gt 30) { Start-Sleep -Milliseconds ([int][math]::Max(1, [math]::Floor($remaining - 15))) }
        else { [Threading.Thread]::SpinWait(2000) }
    }
}
function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}
function Metric([object]$Obj, [string]$Name, [double]$Default = 0) {
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return [double]$p.Value
}
function New-ProbeBatch {
    param(
        [Parameter(Mandatory=$true)][string]$BatchName,
        [Parameter(Mandatory=$true)][string]$Directory,
        [Parameter(Mandatory=$true)][int]$Count,
        [Parameter(Mandatory=$true)][DateTime]$LogicalWindowStartUtc
    )
    $rows = New-Object System.Collections.ArrayList
    $streams = New-Object System.Collections.ArrayList
    $header = New-Object byte[] 4096
    for ($h = 0; $h -lt $header.Length; $h++) { $header[$h] = [byte](($h + 31) -band 0xFF) }
    $start = [DateTime]::UtcNow
    for ($i = 1; $i -le $Count; $i++) {
        $slot = ('FILE-{0:D3}' -f $i)
        $partial = Join-Path $Directory (('{0}-{1}.mxf.partial' -f $BatchName, $slot))
        $lock = $partial + '.lock'
        $fs = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
        $created = [DateTime]::UtcNow
        $fs.Write($header, 0, $header.Length)
        $armed = [DateTime]::UtcNow
        $lockObj = [ordered]@{
            schema = 'recorder-poc.loaded-prearm-lock.v1'
            state = 'ARMED'
            batch = $BatchName
            slot = $slot
            file_id = ([guid]::NewGuid().ToString())
            file_created_utc = UtcIso $created
            file_armed_utc = UtcIso $armed
            recording_window_start_utc = UtcIso $LogicalWindowStartUtc
            partial_path = [IO.Path]::GetFullPath($partial)
        }
        $lockObj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $lock -Encoding UTF8
        [void]$streams.Add($fs)
        [void]$rows.Add([pscustomobject]@{ slot=$slot; partial_path=$partial; lock_path=$lock; created_utc=$created; armed_utc=$armed })
    }
    $end = [DateTime]::UtcNow
    return [pscustomobject]@{ rows=$rows; streams=$streams; start_utc=$start; end_utc=$end; elapsed_ms=(MsBetween $start $end) }
}
function Close-Batch($Batch) {
    if ($null -eq $Batch) { return }
    foreach ($fs in $Batch.streams) { try { $fs.Flush(); $fs.Dispose() } catch {} }
}

$runRoot = Ensure-RunDirectory 'file-manager-loaded-capacity'
$runId = 'loaded-prearm-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '-' + $PID
$runDir = Join-Path $runRoot $runId
New-Item -ItemType Directory -Path $runDir | Out-Null
$currentDir = Join-Path $runDir 'current-window'
$nextDir = Join-Path $runDir 'next-window'
New-Item -ItemType Directory -Path $currentDir,$nextDir | Out-Null

$manifestPath = Join-Path $runDir 'current-window-files.json'
$reportPath = Join-Path $runDir 'loaded-prearm-report.json'
$workerReady = Join-Path $runDir 'load-worker.ready'
$workerStop = Join-Path $runDir 'load-worker.stop'
$workerMetrics = Join-Path $runDir 'load-worker-metrics.json'
$workerSummary = Join-Path $runDir 'load-worker-summary.json'
$workerStdout = Join-Path $runDir 'load-worker-stdout.txt'
$workerStderr = Join-Path $runDir 'load-worker-stderr.txt'
$workerScript = Join-Path $PSScriptRoot 'Invoke-CurrentWindowLoadWorker.ps1'

$currentBatch = $null
$nextBatch = $null
$worker = $null
$result = 'FAIL'
$failure = $null
$failureStage = 'INITIALIZE'
$activationDispatchMs = $null
$loadedReady = 0
$measurementDelta = $null

Write-Host '=== File Manager Loaded Pre-arm Gate ==='
Write-Host "Current files: $FileCount"
Write-Host "Active media: ${ActivePercent}%"
Write-Host "Next files: $FileCount"
Write-Host "Precreate lead: ${PrecreateLeadMs}ms"
Write-Host 'Load: PCMA-like 160-byte/20ms packets + JSONL logging + SQLite WAL.'

try {
    $failureStage = 'BASELINE_CURRENT_BATCH'
    $baselineLogicalStart = [DateTime]::UtcNow.AddMinutes(-1)
    $currentBatch = New-ProbeBatch -BatchName 'current' -Directory $currentDir -Count $FileCount -LogicalWindowStartUtc $baselineLogicalStart
    Write-Host ("Baseline create+arm current 100: {0} ms" -f $currentBatch.elapsed_ms)

    # The worker becomes the owner of the current-window handles.
    Close-Batch $currentBatch
    $currentBatch.streams.Clear()
    $manifestRows = @($currentBatch.rows | ForEach-Object {
        $canonicalPath = [IO.Path]::GetFullPath([string]$_.partial_path)
        [pscustomobject]@{
            slot = [string]$_.slot
            partial_path = $canonicalPath
        }
    })
    $manifestDocument = [pscustomobject]@{
        schema = 'recorder-poc.current-window-file-manifest.v2'
        file_count = $FileCount
        generated_utc = [DateTime]::UtcNow.ToString('o')
        files = $manifestRows
    }
    ConvertTo-Json -InputObject $manifestDocument -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    # Validate the exact document shape and every path before starting the child.
    $manifestCheck = Read-JsonSafe $manifestPath
    if ($null -eq $manifestCheck) { throw 'Current-window manifest failed parent-side JSON validation.' }
    if ([string]$manifestCheck.schema -ne 'recorder-poc.current-window-file-manifest.v2') {
        throw ("Current-window manifest schema mismatch after serialization: {0}" -f [string]$manifestCheck.schema)
    }
    $manifestCheckRows = @($manifestCheck.files | ForEach-Object { $_ })
    if ($manifestCheckRows.Count -ne $FileCount) {
        throw ("Current-window manifest row count mismatch: expected={0} actual={1}" -f $FileCount, $manifestCheckRows.Count)
    }
    $manifestIndex = 0
    foreach ($manifestRow in $manifestCheckRows) {
        $manifestIndex++
        $pathProp = $manifestRow.PSObject.Properties['partial_path']
        if ($null -eq $pathProp -or $null -eq $pathProp.Value) {
            throw ("Parent manifest validation: missing partial_path at index={0}" -f $manifestIndex)
        }
        if ($pathProp.Value -is [System.Array]) {
            throw ("Parent manifest validation: partial_path is array at index={0}" -f $manifestIndex)
        }
        $pathText = ([string]$pathProp.Value).Trim()
        if ($pathText.Contains('"')) {
            throw ("Parent manifest validation: partial_path contains quotes at index={0} value=[{1}]" -f $manifestIndex,$pathText)
        }
        $canonical = [IO.Path]::GetFullPath($pathText)
        if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
            throw ("Parent manifest validation: file missing at index={0} path=[{1}]" -f $manifestIndex,$canonical)
        }
        $manifestRow.partial_path = $canonical
    }
    Write-Host ("Manifest validation: {0}/{0} canonical rooted paths exist." -f $FileCount)

    $failureStage = 'START_CURRENT_WINDOW_LOAD'
    $psExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
    $args = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $workerScript),
        '-RunDir',('"{0}"' -f $runDir),
        '-ManifestPath',('"{0}"' -f $manifestPath),
        '-ActivePercent',[string]$ActivePercent
    )
    $worker = Start-Process -FilePath $psExe -ArgumentList $args -RedirectStandardOutput $workerStdout -RedirectStandardError $workerStderr -PassThru -WindowStyle Hidden

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $workerReady)) {
        if ($worker.HasExited) {
            try { $worker.WaitForExit() } catch {}
            $workerFailureSummary = Read-JsonSafe $workerSummary
            $workerStage = if ($null -ne $workerFailureSummary -and $null -ne $workerFailureSummary.PSObject.Properties['failure_stage']) {
                [string]$workerFailureSummary.failure_stage
            } else { 'UNKNOWN' }
            $workerReason = if ($null -ne $workerFailureSummary -and $null -ne $workerFailureSummary.PSObject.Properties['failure_reason']) {
                [string]$workerFailureSummary.failure_reason
            } else { $null }
            $stderrTail = $null
            if (Test-Path -LiteralPath $workerStderr) {
                try {
                    $stderrTail = ((Get-Content -LiteralPath $workerStderr -Tail 12) -join ' | ').Trim()
                } catch {}
            }
            throw ("Load worker exited before READY: exit={0}; stage={1}; reason={2}; stderr={3}" -f $worker.ExitCode,$workerStage,$workerReason,$stderrTail)
        }
        if ([DateTime]::UtcNow -ge $readyDeadline) {
            $workerFailureSummary = Read-JsonSafe $workerSummary
            $workerStage = if ($null -ne $workerFailureSummary -and $null -ne $workerFailureSummary.PSObject.Properties['failure_stage']) {
                [string]$workerFailureSummary.failure_stage
            } else { 'UNKNOWN' }
            throw ("Load worker READY timeout; worker_stage={0}" -f $workerStage)
        }
        Start-Sleep -Milliseconds 25
    }

    $readyInfo = Read-JsonSafe $workerReady
    if ($null -eq $readyInfo) { throw 'Load worker READY handshake unreadable.' }
    if ([int]$readyInfo.total_files_open -ne $FileCount) {
        throw ("Load worker READY open-file mismatch: expected={0} actual={1}" -f $FileCount,[int]$readyInfo.total_files_open)
    }
    if (-not ([bool]$readyInfo.sqlite_ready)) {
        throw 'Load worker READY reported sqlite_ready=False.'
    }
    Start-Sleep -Milliseconds $WarmupMs

    $failureStage = 'LOADED_PREARM_NEXT_BATCH'
    $metricsBefore = Read-JsonSafe $workerMetrics
    $windowStartUtc = [DateTime]::UtcNow.AddMilliseconds($PrecreateLeadMs)
    $readyDeadlineUtc = $windowStartUtc.AddMilliseconds(-$ReadyDeadlineMs)
    $nextBatch = New-ProbeBatch -BatchName 'next' -Directory $nextDir -Count $FileCount -LogicalWindowStartUtc $windowStartUtc
    $metricsAfter = Read-JsonSafe $workerMetrics

    $loadedReady = @($nextBatch.rows | Where-Object { $_.armed_utc -le $readyDeadlineUtc }).Count
    $createdAfterT0 = @($nextBatch.rows | Where-Object { $_.created_utc -ge $windowStartUtc }).Count
    $lastArmed = ($nextBatch.rows | Sort-Object armed_utc | Select-Object -Last 1).armed_utc
    $minArmingMarginMs = MsBetween $lastArmed $windowStartUtc

    $measurementDelta = [ordered]@{
        packet_writes = [int64]((Metric $metricsAfter 'packet_writes') - (Metric $metricsBefore 'packet_writes'))
        bytes_written = [int64]((Metric $metricsAfter 'bytes_written') - (Metric $metricsBefore 'bytes_written'))
        log_events = [int64]((Metric $metricsAfter 'log_events') - (Metric $metricsBefore 'log_events'))
        db_transactions = [int64]((Metric $metricsAfter 'db_transactions') - (Metric $metricsBefore 'db_transactions'))
        db_rows = [int64]((Metric $metricsAfter 'db_rows') - (Metric $metricsBefore 'db_rows'))
        db_exec_ms_total = [math]::Round((Metric $metricsAfter 'db_exec_ms_total') - (Metric $metricsBefore 'db_exec_ms_total'), 3)
    }

    Write-Host ("Loaded create+arm next 100: {0} ms" -f $nextBatch.elapsed_ms)
    Write-Host ("READY before T0-250ms: {0}/{1}" -f $loadedReady, $FileCount)
    Write-Host ("Minimum arming margin: {0} ms" -f $minArmingMarginMs)
    Write-Host ("Concurrent load during prearm: packets={0}, bytes={1}, logs={2}, db_tx={3}, db_rows={4}" -f $measurementDelta.packet_writes,$measurementDelta.bytes_written,$measurementDelta.log_events,$measurementDelta.db_transactions,$measurementDelta.db_rows)

    if ($loadedReady -ne $FileCount) { throw 'BOUNDARY_SPILL_REQUIRED: loaded pre-arm missed readiness deadline.' }
    if ($createdAfterT0 -ne 0) { throw 'One or more next-window files were created at/after T0.' }
    if ($measurementDelta.packet_writes -le 0 -or $measurementDelta.log_events -le 0 -or $measurementDelta.db_transactions -le 0 -or $measurementDelta.db_rows -le 0) {
        throw 'Concurrent workload evidence did not advance during loaded pre-arm.'
    }

    $failureStage = 'LOADED_ACTIVATION'
    WaitUntilUtc $windowStartUtc
    $activationStart = [DateTime]::UtcNow
    $marker = [Text.Encoding]::ASCII.GetBytes("NEXT_WINDOW_ACTIVATE`n")
    foreach ($fs in $nextBatch.streams) { $fs.Write($marker,0,$marker.Length) }
    $activationEnd = [DateTime]::UtcNow
    $activationDispatchMs = MsBetween $activationStart $activationEnd
    Write-Host ("Loaded activation dispatch: {0} ms (budget <= {1} ms)" -f $activationDispatchMs,$ActivationDispatchBudgetMs)
    if ($activationDispatchMs -gt $ActivationDispatchBudgetMs) { throw 'Activation dispatch exceeded budget under load.' }

    $failureStage = 'STOP_LOAD_WORKER'
    New-Item -ItemType File -Path $workerStop -Force | Out-Null
    if (-not $worker.WaitForExit(5000)) { try { $worker.Kill() } catch {}; throw 'Load worker did not stop within 5 seconds.' }
    $summary = Read-JsonSafe $workerSummary
    if ($null -eq $summary) { throw 'Load worker summary missing/unreadable.' }
    if ([string]$summary.result -ne 'PASS') { throw ("Load worker failed: {0}" -f $summary.failure_reason) }

    $failureStage = 'COMPLETE'
    $result = 'PASS'
}
catch {
    $failure = $_.Exception.Message
}
finally {
    if (-not (Test-Path -LiteralPath $workerStop)) { try { New-Item -ItemType File -Path $workerStop -Force | Out-Null } catch {} }
    if ($worker -and -not $worker.HasExited) { try { if (-not $worker.WaitForExit(2000)) { $worker.Kill() } } catch {} }
    Close-Batch $nextBatch
    Close-Batch $currentBatch

    $summaryFinal = Read-JsonSafe $workerSummary
    $baselineMs = if ($currentBatch) { [double]$currentBatch.elapsed_ms } else { $null }
    $loadedMs = if ($nextBatch) { [double]$nextBatch.elapsed_ms } else { $null }
    $deltaMs = if ($null -ne $baselineMs -and $null -ne $loadedMs) { [math]::Round($loadedMs - $baselineMs,3) } else { $null }
    $deltaPct = if ($null -ne $baselineMs -and $baselineMs -gt 0 -and $null -ne $loadedMs) { [math]::Round((($loadedMs / $baselineMs) - 1.0) * 100.0,2) } else { $null }

    $report = [ordered]@{
        schema = 'recorder-poc.file-manager-loaded-prearm.v1'
        result = $result
        failure_stage = $failureStage
        failure_reason = $failure
        file_count_current = $FileCount
        active_percent = $ActivePercent
        active_file_count_expected = [int][math]::Ceiling($FileCount * ($ActivePercent / 100.0))
        file_count_next = $FileCount
        precreate_lead_ms = $PrecreateLeadMs
        ready_deadline_ms_before_window = $ReadyDeadlineMs
        baseline_precreate_and_arm_ms = $baselineMs
        loaded_precreate_and_arm_ms = $loadedMs
        loaded_delay_delta_ms = $deltaMs
        loaded_delay_delta_pct = $deltaPct
        loaded_ready_at_deadline = $loadedReady
        loaded_activation_dispatch_ms = $activationDispatchMs
        concurrent_work_during_loaded_prearm = $measurementDelta
        worker_summary = $summaryFinal
        artifacts = [ordered]@{
            current_manifest = $manifestPath
            worker_metrics = $workerMetrics
            worker_summary = $workerSummary
            worker_stdout = $workerStdout
            worker_stderr = $workerStderr
            runtime_log = (Join-Path $runDir 'runtime-events.jsonl')
            sqlite = (Join-Path $runDir 'runtime-index.sqlite')
        }
    }
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

Write-Host "Report: $reportPath"
if ($null -ne $currentBatch -and $null -ne $nextBatch) {
    $delta = [math]::Round([double]$nextBatch.elapsed_ms - [double]$currentBatch.elapsed_ms,3)
    $pct = if ([double]$currentBatch.elapsed_ms -gt 0) { [math]::Round((([double]$nextBatch.elapsed_ms / [double]$currentBatch.elapsed_ms)-1)*100,2) } else { 0 }
    Write-Host ("Delay under workload: {0} ms ({1}%)" -f $delta,$pct)
}
if ($result -eq 'PASS') {
    Write-Host 'FILE MANAGER LOADED PRE-ARM: PASS'
    exit 0
}
Write-Host ("Failure stage: {0}" -f $failureStage)
Write-Error ("FILE MANAGER LOADED PRE-ARM: FAIL - {0}" -f $failure)
exit 25
