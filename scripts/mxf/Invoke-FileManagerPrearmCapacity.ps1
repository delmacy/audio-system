param(
    [int]$FileCount = 100,
    [int]$PrecreateLeadMs = 10000,
    [int]$ReadyDeadlineMs = 250,
    [int]$ActivationDispatchBudgetMs = 250,
    [int]$WindowMinutes = 60,
    [string]$RunId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
. (Join-Path $PSScriptRoot 'Mxf-FileLifecycle.ps1')

if ($FileCount -lt 1) { throw 'FileCount must be >= 1.' }
if ($PrecreateLeadMs -le $ReadyDeadlineMs) { throw 'PrecreateLeadMs must be greater than ReadyDeadlineMs.' }
if ($ReadyDeadlineMs -lt 0) { throw 'ReadyDeadlineMs must be >= 0.' }
if ($ActivationDispatchBudgetMs -lt 1) { throw 'ActivationDispatchBudgetMs must be >= 1.' }

function UtcIso([DateTime]$Value) { return $Value.ToUniversalTime().ToString('o') }
function Get-SingleUtcDateTime {
    param(
        [Parameter(Mandatory=$true)]$Value,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $items = @($Value)
    if ($items.Count -ne 1) {
        throw ("Temporal scalar invariant failed for {0}: expected 1 value, got {1}." -f $Name, $items.Count)
    }
    try {
        return ([DateTime]$items[0]).ToUniversalTime()
    } catch {
        throw ("Temporal scalar invariant failed for {0}: value is not DateTime-compatible ({1})." -f $Name, $items[0].GetType().FullName)
    }
}
function Ms-Between {
    param(
        [Parameter(Mandatory=$true)]$A,
        [Parameter(Mandatory=$true)]$B,
        [string]$AName = 'A',
        [string]$BName = 'B'
    )
    $aUtc = Get-SingleUtcDateTime -Value $A -Name $AName
    $bUtc = Get-SingleUtcDateTime -Value $B -Name $BName
    # Use DateTime.Subtract after enforcing scalar operands. This deliberately avoids
    # PowerShell binary '-' dispatch, which can invoke op_Subtraction on Object[].
    $span = $bUtc.Subtract($aUtc)
    return [math]::Round([double]$span.TotalMilliseconds, 3)
}
function Wait-UntilUtc([DateTime]$TargetUtc) {
    while ($true) {
        $remaining = Ms-Between -A ([DateTime]::UtcNow) -B $TargetUtc -AName 'UtcNow' -BName 'WaitTargetUtc'
        if ($remaining -le 0) { break }
        if ($remaining -gt 30) {
            Start-Sleep -Milliseconds ([int][math]::Max(1, [math]::Floor(([double]$remaining + (-15.0)))))
        } else {
            [Threading.Thread]::SpinWait(2000)
        }
    }
}
function Percentile([double[]]$Values, [double]$P) {
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $idx = [int]([math]::Ceiling(($P / 100.0) * $sorted.Count) + (-1))
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $sorted.Count) { $idx = [int]$sorted.Count + (-1) }
    return [math]::Round([double]$sorted[$idx], 3)
}
function New-LockObject {
    param($Row, [string]$State)
    return [ordered]@{
        schema = 'recorder-poc.prearmed-file-lock.v1'
        file_id = $Row.FileId
        state = $State
        manager_pid = $PID
        logical_file_slot = $Row.Slot
        segment_sequence = 0
        recording_window_start_utc = (UtcIso $script:windowStartUtc)
        recording_window_end_utc = (UtcIso $script:windowEndUtc)
        file_created_utc = (UtcIso $Row.CreatedUtc)
        file_armed_utc = if ($Row.ArmedUtc) { UtcIso $Row.ArmedUtc } else { $null }
        window_activated_utc = if ($Row.ActivatedUtc) { UtcIso $Row.ActivatedUtc } else { $null }
        partial_path = [IO.Path]::GetFullPath($Row.PartialPath)
        expected_final_name = [IO.Path]::GetFileName($Row.FinalPath)
        share_policy = 'READ_ONLY_TO_OTHERS; NO_SHARE_WRITE; NO_SHARE_DELETE'
        heartbeat_utc = [DateTime]::UtcNow.ToString('o')
    }
}

$root = Get-ProjectRoot
$runRoot = Ensure-RunDirectory 'file-manager-capacity'
if ([string]::IsNullOrWhiteSpace($RunId)) {
    # Milliseconds + PID make standalone runs collision-resistant.
    $resolvedRunId = ('prearm-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), $PID)
} else {
    $safeRunId = ($RunId -replace '[^A-Za-z0-9._-]', '_')
    if ([string]::IsNullOrWhiteSpace($safeRunId)) { throw 'RunId became empty after sanitization.' }
    $resolvedRunId = $safeRunId
}
$runDir = Join-Path $runRoot $resolvedRunId
if (Test-Path -LiteralPath $runDir) {
    throw "Run directory already exists: $runDir"
}
New-Item -ItemType Directory -Path $runDir | Out-Null

# Give the test enough time to enter a real precreate phase and still have a
# deterministic boundary ahead of us. The boundary is logical UTC, independent
# from physical file creation time.
$now = [DateTime]::UtcNow
$windowStartUtc = $now.AddMilliseconds($PrecreateLeadMs + 1250)
$windowStartUtc = $windowStartUtc.AddTicks(-($windowStartUtc.Ticks % [TimeSpan]::TicksPerMillisecond))
$windowEndUtc = $windowStartUtc.AddMinutes($WindowMinutes)
$precreateStartUtc = $windowStartUtc.AddMilliseconds(-$PrecreateLeadMs)
$readyDeadlineUtc = $windowStartUtc.AddMilliseconds(-$ReadyDeadlineMs)
$script:windowStartUtc = $windowStartUtc
$script:windowEndUtc = $windowEndUtc

$eventsPath = Join-Path $runDir 'file-manager-events.jsonl'
$filesPath = Join-Path $runDir 'armed-files.json'
$reportPath = Join-Path $runDir 'file-manager-prearm-report.json'

function Write-Event([string]$Type, $Data) {
    $obj = [ordered]@{
        ts_utc = [DateTime]::UtcNow.ToString('o')
        event = $Type
        window_start_utc = UtcIso $script:windowStartUtc
        data = $Data
    }
    ($obj | ConvertTo-Json -Depth 8 -Compress) | Add-Content -LiteralPath $eventsPath -Encoding UTF8
}

$rows = New-Object System.Collections.ArrayList
$streams = New-Object System.Collections.ArrayList
$probeResults = @()
$activationPayloads = New-Object System.Collections.ArrayList
$result = 'FAIL'
$failureReason = $null
$failureStage = 'INITIALIZE'
$batchStartUtc = $null
$batchEndUtc = $null
$activationStartUtc = $null
$activationEndUtc = $null

Write-Host '=== File Manager Pre-arm Capacity Gate ==='
Write-Host "Files: $FileCount"
Write-Host "Window start UTC: $(UtcIso $windowStartUtc)"
Write-Host "Precreate starts:  $(UtcIso $precreateStartUtc)  (lead=${PrecreateLeadMs}ms)"
Write-Host "READY deadline:    $(UtcIso $readyDeadlineUtc)  (${ReadyDeadlineMs}ms before window)"
Write-Host 'No CreateNew operation is permitted after the READY barrier.'

try {
    $failureStage = 'PLAN_NEXT_WINDOW'
    Write-Event 'NEXT_WINDOW_PLANNED' ([ordered]@{
        file_count = $FileCount
        precreate_lead_ms = $PrecreateLeadMs
        ready_deadline_ms_before_window = $ReadyDeadlineMs
    })

    $failureStage = 'WAIT_PRECREATE_START'
    Wait-UntilUtc $precreateStartUtc
    $failureStage = 'PRECREATE_AND_ARM'
    $batchStartUtc = [DateTime]::UtcNow
    Write-Event 'NEXT_WINDOW_PRECREATE_START' ([ordered]@{ file_count = $FileCount })

    for ($i = 1; $i -le $FileCount; $i++) {
        $slot = ('FILE-{0:D3}' -f $i)
        $fileId = 'FILE-' + ([guid]::NewGuid().ToString('N'))
        $base = Join-Path $runDir (("window-{0:yyyyMMdd-HHmmssfff}Z-{1}" -f $windowStartUtc, $slot))
        $partial = $base + '.mxf.partial'
        $final = $base + '.mxf'
        $lock = $base + '.mxf.lock'

        $oneStart = [DateTime]::UtcNow
        # The manager owns the write handle from pre-arm through activation.
        # FileShare.Read intentionally denies a second writer and delete/rename.
        $fs = [System.IO.File]::Open(
            $partial,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::Read)
        [void]$streams.Add($fs)
        $createdUtc = [DateTime]::UtcNow

        $row = [pscustomobject]@{
            Slot = $slot
            FileId = $fileId
            PartialPath = $partial
            FinalPath = $final
            LockPath = $lock
            CreatedUtc = $createdUtc
            ArmedUtc = $null
            ActivatedUtc = $null
            CreateAndArmMs = 0.0
            ArmingMarginMs = 0.0
            ActivationOffsetMs = $null
        }
        [void]$rows.Add($row)

        # The sidecar is part of readiness. It contains both physical creation
        # time and the logical recording window time; they are deliberately distinct.
        $row.ArmedUtc = [DateTime]::UtcNow
        Write-JsonAtomic -Object (New-LockObject -Row $row -State 'ARMED') -Path $lock
        $armedUtcScalar = [DateTime]::UtcNow
        $row.ArmedUtc = $armedUtcScalar
        $row.CreateAndArmMs = Ms-Between -A $oneStart -B $armedUtcScalar -AName "$slot.oneStart" -BName "$slot.armedUtc"
        $row.ArmingMarginMs = Ms-Between -A $armedUtcScalar -B $windowStartUtc -AName "$slot.armedUtc" -BName 'windowStartUtc'
    }

    $batchEndUtc = [DateTime]::UtcNow
    $batchMs = Ms-Between -A $batchStartUtc -B $batchEndUtc -AName 'batchStartUtc' -BName 'batchEndUtc'
    $failureStage = 'LOCK_PROBES'

    # Verify the lock semantics on representative first/middle/last handles.
    $lastIndex = [int]$FileCount + (-1)
    $middleIndex = [int][math]::Floor(([double]$lastIndex) / 2.0)
    $sampleIndexes = @(0, $middleIndex, $lastIndex) | Select-Object -Unique
    foreach ($idx in $sampleIndexes) {
        $r = $rows[$idx]
        $p = Test-DeleteRenameBlocked -PartialPath $r.PartialPath
        $probeResults += [pscustomobject]@{
            slot = $r.Slot
            delete_blocked = [bool]$p.DeleteBlocked
            rename_blocked = [bool]$p.RenameBlocked
        }
    }

    $failureStage = 'READY_BARRIER_EVALUATION'
    $readyCount = @($rows | Where-Object { $_.ArmedUtc -le $readyDeadlineUtc }).Count
    $lateArmed = @($rows | Where-Object { $_.ArmedUtc -gt $readyDeadlineUtc }).Count
    $createdAfterWindow = @($rows | Where-Object { $_.CreatedUtc -ge $windowStartUtc }).Count
    $readyRatio = [math]::Round($readyCount / [double]$FileCount, 6)
    $allLocksPass = @($probeResults | Where-Object { -not $_.delete_blocked -or -not $_.rename_blocked }).Count -eq 0

    Write-Host ("Precreate+arm batch: {0} ms" -f $batchMs)
    Write-Host ("READY at deadline: {0}/{1} ({2:P2})" -f $readyCount, $FileCount, $readyRatio)
    Write-Host ("Created after window start: {0}" -f $createdAfterWindow)
    Write-Host ("Delete/rename lock probes: {0}" -f ($(if ($allLocksPass) { 'PASS' } else { 'FAIL' })))

    Write-Event 'NEXT_WINDOW_READY_BARRIER' ([ordered]@{
        ready = $readyCount
        expected = $FileCount
        ready_ratio = $readyRatio
        late_armed = $lateArmed
        created_after_window_start = $createdAfterWindow
        lock_probe_pass = $allLocksPass
        batch_ms = $batchMs
    })

    if ($readyCount -ne $FileCount -or $createdAfterWindow -ne 0 -or -not $allLocksPass) {
        $failureReason = 'BOUNDARY_SPILL_REQUIRED: next window was not fully armed before the readiness deadline.'
        Write-Event 'BOUNDARY_SPILL_REQUIRED' ([ordered]@{ reason = $failureReason })
        throw $failureReason
    }

    Write-Event 'NEXT_WINDOW_ARMED' ([ordered]@{
        file_count = $FileCount
        min_arming_margin_ms = [math]::Round((($rows | Measure-Object -Property ArmingMarginMs -Minimum).Minimum), 3)
    })

    # Precompute activation markers before T0 so the boundary path does not
    # allocate file names, create files, serialize JSON, or build payload strings.
    $failureStage = 'PRECOMPUTE_ACTIVATION_PAYLOADS'
    foreach ($row in $rows) {
        $payload = [Text.Encoding]::ASCII.GetBytes(("POC_WINDOW_ACTIVATE|slot={0}|window={1}|file={2}`n" -f $row.Slot, (UtcIso $windowStartUtc), $row.FileId))
        [void]$activationPayloads.Add($payload)
    }

    # Critical property: after this point no files are created. At T0 the manager
    # only releases already-open writers into the new logical window.
    $failureStage = 'WAIT_WINDOW_BOUNDARY'
    Wait-UntilUtc $windowStartUtc
    $failureStage = 'ACTIVATION_DISPATCH'
    $activationStartUtc = [DateTime]::UtcNow

    $ordinal = 0
    foreach ($row in $rows) {
        $fs = $streams[$ordinal]
        $row.ActivatedUtc = [DateTime]::UtcNow
        $row.ActivationOffsetMs = Ms-Between -A $windowStartUtc -B $row.ActivatedUtc -AName 'windowStartUtc' -BName "$($row.Slot).ActivatedUtc"
        $payload = $activationPayloads[$ordinal]
        $fs.Position = 0
        $fs.Write($payload, 0, $payload.Length)
        $ordinal++
    }
    $activationEndUtc = [DateTime]::UtcNow
    $activationDispatchMs = Ms-Between -A $activationStartUtc -B $activationEndUtc -AName 'activationStartUtc' -BName 'activationEndUtc'
    Write-Event 'WINDOW_ACTIVATION_BARRIER_RELEASED' ([ordered]@{
        file_count = $FileCount
        barrier_released_utc = UtcIso $activationStartUtc
        dispatch_completed_utc = UtcIso $activationEndUtc
    })

    # Flush after dispatch so durability work is deliberately not on the activation path.
    $failureStage = 'POST_ACTIVATION_FLUSH'
    foreach ($fs in $streams) { $fs.Flush() }

    $activatedCount = @($rows | Where-Object { $null -ne $_.ActivatedUtc }).Count
    $firstOffset = ($rows | Measure-Object -Property ActivationOffsetMs -Minimum).Minimum
    $lastOffset = ($rows | Measure-Object -Property ActivationOffsetMs -Maximum).Maximum
    $activationBudgetPass = ($activationDispatchMs -le $ActivationDispatchBudgetMs)

    Write-Host ("Activated writers: {0}/{1}" -f $activatedCount, $FileCount)
    Write-Host ("Activation dispatch span: {0} ms (budget <= {1} ms)" -f $activationDispatchMs, $ActivationDispatchBudgetMs)
    Write-Host ("First/last activation offset from T0: {0} / {1} ms" -f ([math]::Round($firstOffset,3)), ([math]::Round($lastOffset,3)))

    if ($activatedCount -ne $FileCount) { throw 'Not all pre-armed writers were activated.' }
    if (-not $activationBudgetPass) { throw "Activation dispatch exceeded budget: ${activationDispatchMs}ms > ${ActivationDispatchBudgetMs}ms." }

    $failureStage = 'COMPLETE'
    $result = 'PASS'
    Write-Event 'WINDOW_ACTIVATED' ([ordered]@{
        activated = $activatedCount
        activation_dispatch_ms = $activationDispatchMs
        activation_budget_ms = $ActivationDispatchBudgetMs
    })
}
catch {
    if (-not $failureReason) { $failureReason = $_.Exception.Message }
    try { Write-Event 'GATE_EXCEPTION' ([ordered]@{ stage = $failureStage; message = $failureReason; script_stack = $_.ScriptStackTrace }) } catch {}
}
finally {
    # Close the owned write handles. The probe files are not valid MXF and are
    # renamed accordingly so they can never be mistaken for recorder output.
    for ($i = 0; $i -lt $streams.Count; $i++) {
        try { $streams[$i].Dispose() } catch {}
    }

    foreach ($row in $rows) {
        try {
            if (Test-Path -LiteralPath $row.LockPath) {
                Write-JsonAtomic -Object (New-LockObject -Row $row -State 'PROBE_CLOSED') -Path $row.LockPath
                Remove-Item -LiteralPath $row.LockPath -Force
            }
            if (Test-Path -LiteralPath $row.PartialPath) {
                $closed = $row.PartialPath + '.capacity-probe.closed'
                Move-Item -LiteralPath $row.PartialPath -Destination $closed -Force
            }
        } catch {}
    }

    $armingMargins = @($rows | ForEach-Object { [double]$_.ArmingMarginMs })
    $armDurations = @($rows | ForEach-Object { [double]$_.CreateAndArmMs })
    $readyCountFinal = @($rows | Where-Object { $_.ArmedUtc -and $_.ArmedUtc -le $readyDeadlineUtc }).Count
    $lateArmedFinal = [int]$FileCount + (-1 * [int]$readyCountFinal)
    $createdAfterWindowFinal = @($rows | Where-Object { $_.CreatedUtc -ge $windowStartUtc }).Count
    $activationDispatchFinal = if ($activationStartUtc -and $activationEndUtc) { Ms-Between -A $activationStartUtc -B $activationEndUtc -AName 'activationStartUtc' -BName 'activationEndUtc' } else { $null }
    $batchMsFinal = if ($null -ne $batchStartUtc -and $null -ne $batchEndUtc) { Ms-Between -A $batchStartUtc -B $batchEndUtc -AName 'batchStartUtc' -BName 'batchEndUtc' } elseif ($rows.Count -gt 0 -and $rows[0].CreatedUtc -and $rows[([int]$rows.Count + (-1))].ArmedUtc) { Ms-Between -A $rows[0].CreatedUtc -B $rows[([int]$rows.Count + (-1))].ArmedUtc -AName 'first.CreatedUtc' -BName 'last.ArmedUtc' } else { $null }

    $publicRows = @($rows | ForEach-Object {
        [ordered]@{
            logical_file_slot = $_.Slot
            file_id = $_.FileId
            segment_sequence = 0
            recording_window_start_utc = UtcIso $windowStartUtc
            recording_window_end_utc = UtcIso $windowEndUtc
            file_created_utc = UtcIso $_.CreatedUtc
            file_armed_utc = if ($_.ArmedUtc) { UtcIso $_.ArmedUtc } else { $null }
            window_activated_utc = if ($_.ActivatedUtc) { UtcIso $_.ActivatedUtc } else { $null }
            create_and_arm_ms = $_.CreateAndArmMs
            arming_margin_ms = $_.ArmingMarginMs
            activation_offset_ms = $_.ActivationOffsetMs
            source_partial_name = [IO.Path]::GetFileName($_.PartialPath)
        }
    })
    $publicRows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $filesPath -Encoding UTF8

    $report = [ordered]@{
        schema = 'recorder-poc.file-manager-prearm-capacity.v2'
        run_id = $resolvedRunId
        result = $result
        failure_reason = $failureReason
        failure_stage = $failureStage
        file_count = $FileCount
        recording_window_start_utc = UtcIso $windowStartUtc
        recording_window_end_utc = UtcIso $windowEndUtc
        precreate_lead_ms = $PrecreateLeadMs
        ready_deadline_ms_before_window = $ReadyDeadlineMs
        activation_dispatch_budget_ms = $ActivationDispatchBudgetMs
        no_create_after_ready_barrier = $true
        ready_at_deadline = $readyCountFinal
        ready_ratio = [math]::Round($readyCountFinal / [double]$FileCount, 6)
        late_armed_count = $lateArmedFinal
        created_after_window_start_count = $createdAfterWindowFinal
        all_files_created_before_window = ($createdAfterWindowFinal -eq 0)
        all_files_armed_before_deadline = ($readyCountFinal -eq $FileCount)
        lock_probe_results = $probeResults
        lock_probe_pass = (@($probeResults | Where-Object { -not $_.delete_blocked -or -not $_.rename_blocked }).Count -eq 0)
        batch_precreate_and_arm_ms = $batchMsFinal
        recommended_precreate_lead_ms = if ($null -ne $batchMsFinal) { [int][math]::Ceiling([math]::Max(1000, (($batchMsFinal * 2) + $ReadyDeadlineMs))) } else { $null }
        arming_margin_ms = [ordered]@{
            min = if ($armingMargins.Count) { [math]::Round((($armingMargins | Measure-Object -Minimum).Minimum),3) } else { $null }
            p50 = Percentile $armingMargins 50
            p95 = Percentile $armingMargins 95
            max = if ($armingMargins.Count) { [math]::Round((($armingMargins | Measure-Object -Maximum).Maximum),3) } else { $null }
        }
        per_file_create_and_arm_ms = [ordered]@{
            p50 = Percentile $armDurations 50
            p95 = Percentile $armDurations 95
            max = if ($armDurations.Count) { [math]::Round((($armDurations | Measure-Object -Maximum).Maximum),3) } else { $null }
        }
        activation_dispatch_ms = $activationDispatchFinal
        activation_budget_pass = ($null -ne $activationDispatchFinal -and $activationDispatchFinal -le $ActivationDispatchBudgetMs)
        fallback_if_not_ready = 'BOUNDARY_SPILL_REQUIRED; KEEP CURRENT WINDOW WRITERS ACTIVE; DO NOT DROP REQUIRED MEDIA'
        temporal_contract = [ordered]@{
            physical_creation = 'file_created_utc'
            logical_window = 'recording_window_start_utc + segment_sequence'
            activation = 'window_activated_utc'
            rule = 'physical creation/arming must precede logical window start; no CreateNew on boundary path'
        }
        artifacts = [ordered]@{
            armed_files = $filesPath
            events = $eventsPath
        }
    }
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

Write-Host "Report: $reportPath"
Write-Host "Per-file evidence: $filesPath"
Write-Host "Events: $eventsPath"
if ($result -eq 'PASS') {
    Write-Host 'FILE MANAGER PRE-ARM CAPACITY: PASS'
    exit 0
}
Write-Host ("Failure stage: {0}" -f $failureStage)
Write-Error ("FILE MANAGER PRE-ARM CAPACITY: FAIL - {0}" -f $failureReason)
exit 17
