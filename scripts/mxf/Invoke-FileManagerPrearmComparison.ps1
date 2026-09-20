param(
    [int]$FileCount = 100,
    [int]$ShortLeadMs = 3000,
    [int]$LongLeadMs = 10000,
    [int]$ReadyDeadlineMs = 250,
    [int]$ActivationDispatchBudgetMs = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')

function Get-OptionalPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory=$true)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return $p.Value
}

function Get-OptionalNestedPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory=$true)][string]$Parent,
        [Parameter(Mandatory=$true)][string]$Child,
        $Default = $null
    )
    $parentValue = Get-OptionalPropertyValue -Object $Object -Name $Parent -Default $null
    if ($null -eq $parentValue) { return $Default }
    return Get-OptionalPropertyValue -Object $parentValue -Name $Child -Default $Default
}

function Convert-OptionalDouble($Value) {
    if ($null -eq $Value -or $Value -eq '') { return $null }
    try { return [double]$Value } catch { return $null }
}
function Convert-OptionalInt($Value) {
    if ($null -eq $Value -or $Value -eq '') { return $null }
    try { return [int]$Value } catch { return $null }
}

function Invoke-Trial {
    param(
        [int]$LeadMs,
        [string]$Label,
        [string]$RunId
    )
    $root = Get-ProjectRoot
    $runRoot = Join-Path $root 'runs\file-manager-capacity'
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    $script = Join-Path $PSScriptRoot 'Invoke-FileManagerPrearmCapacity.ps1'
    $runDir = Join-Path $runRoot $RunId
    $reportPath = Join-Path $runDir 'file-manager-prearm-report.json'

    Write-Host ""
    Write-Host ("=== Comparison trial {0}: lead={1}ms run={2} ===" -f $Label, $LeadMs, $RunId)

    # IMPORTANT: capture child stdout locally. If native-process stdout is allowed
    # to escape this function, the caller receives Object[] (text lines + the
    # PSCustomObject below) instead of one trial object.
    $trialOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
        -FileCount $FileCount `
        -PrecreateLeadMs $LeadMs `
        -ReadyDeadlineMs $ReadyDeadlineMs `
        -ActivationDispatchBudgetMs $ActivationDispatchBudgetMs `
        -RunId $RunId 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $trialOutput) {
        Write-Host ([string]$line)
    }

    if (-not (Test-Path -LiteralPath $reportPath)) {
        return [pscustomobject]@{
            label = $Label
            requested_lead_ms = $LeadMs
            process_exit_code = $exitCode
            result = 'NO_REPORT'
            failure_stage = 'REPORT_DISCOVERY'
            failure_reason = "Expected report was not created: $reportPath"
            ready_at_deadline = $null
            ready_ratio = $null
            batch_precreate_and_arm_ms = $null
            arming_margin_min_ms = $null
            arming_margin_p95_ms = $null
            activation_dispatch_ms = $null
            created_after_window_start_count = $null
            report_schema_complete = $false
            report = $reportPath
        }
    }

    try {
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            label = $Label
            requested_lead_ms = $LeadMs
            process_exit_code = $exitCode
            result = 'INVALID_REPORT'
            failure_stage = 'REPORT_PARSE'
            failure_reason = $_.Exception.Message
            ready_at_deadline = $null
            ready_ratio = $null
            batch_precreate_and_arm_ms = $null
            arming_margin_min_ms = $null
            arming_margin_p95_ms = $null
            activation_dispatch_ms = $null
            created_after_window_start_count = $null
            report_schema_complete = $false
            report = $reportPath
        }
    }

    $resultValue = [string](Get-OptionalPropertyValue $report 'result' 'UNKNOWN')
    $failureStageValue = [string](Get-OptionalPropertyValue $report 'failure_stage' '')
    $failureReasonValue = [string](Get-OptionalPropertyValue $report 'failure_reason' '')
    $readyValue = Convert-OptionalInt (Get-OptionalPropertyValue $report 'ready_at_deadline' $null)
    $ratioValue = Convert-OptionalDouble (Get-OptionalPropertyValue $report 'ready_ratio' $null)
    $batchValue = Convert-OptionalDouble (Get-OptionalPropertyValue $report 'batch_precreate_and_arm_ms' $null)
    $minMarginValue = Convert-OptionalDouble (Get-OptionalNestedPropertyValue $report 'arming_margin_ms' 'min' $null)
    $p95MarginValue = Convert-OptionalDouble (Get-OptionalNestedPropertyValue $report 'arming_margin_ms' 'p95' $null)
    $activationValue = Convert-OptionalDouble (Get-OptionalPropertyValue $report 'activation_dispatch_ms' $null)
    $createdLateValue = Convert-OptionalInt (Get-OptionalPropertyValue $report 'created_after_window_start_count' $null)

    # A PASS is expected to expose the core metrics. A FAIL may legitimately stop
    # before some metrics exist, and the comparison must still survive and report it.
    $schemaComplete = ($null -ne $readyValue -and $null -ne $batchValue -and $null -ne $minMarginValue)

    return [pscustomobject]@{
        label = $Label
        requested_lead_ms = $LeadMs
        process_exit_code = $exitCode
        result = $resultValue
        failure_stage = $failureStageValue
        failure_reason = $failureReasonValue
        ready_at_deadline = $readyValue
        ready_ratio = $ratioValue
        batch_precreate_and_arm_ms = $batchValue
        arming_margin_min_ms = $minMarginValue
        arming_margin_p95_ms = $p95MarginValue
        activation_dispatch_ms = $activationValue
        created_after_window_start_count = $createdLateValue
        report_schema_complete = $schemaComplete
        report = $reportPath
    }
}

$root = Get-ProjectRoot
$runRoot = Join-Path $root 'runs\file-manager-capacity'
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$comparisonId = "prearm-comparison-$stamp-$PID"
$comparisonPath = Join-Path $runRoot ("$comparisonId.json")

$shortRunId = "$comparisonId-3s"
$longRunId = "$comparisonId-10s"
$short = Invoke-Trial -LeadMs $ShortLeadMs -Label '3s' -RunId $shortRunId
$long = Invoke-Trial -LeadMs $LongLeadMs -Label '10s' -RunId $longRunId
$trials = @($short, $long)

# Scalar snapshots used below; avoid StrictMode failures on partial objects.
$shortResult = [string](Get-OptionalPropertyValue $short 'result' 'UNKNOWN')
$longResult = [string](Get-OptionalPropertyValue $long 'result' 'UNKNOWN')
$longFailureStage = [string](Get-OptionalPropertyValue $long 'failure_stage' '')
$longFailureReason = [string](Get-OptionalPropertyValue $long 'failure_reason' '')

# Read comparison metrics through the optional-property helper as a second
# containment layer. A partial/failed report may legitimately omit metrics.
$shortBatch = Convert-OptionalDouble (Get-OptionalPropertyValue $short 'batch_precreate_and_arm_ms' $null)
$longBatch = Convert-OptionalDouble (Get-OptionalPropertyValue $long 'batch_precreate_and_arm_ms' $null)
$shortMargin = Convert-OptionalDouble (Get-OptionalPropertyValue $short 'arming_margin_min_ms' $null)
$longMargin = Convert-OptionalDouble (Get-OptionalPropertyValue $long 'arming_margin_min_ms' $null)
$shortActivation = Convert-OptionalDouble (Get-OptionalPropertyValue $short 'activation_dispatch_ms' $null)
$longActivation = Convert-OptionalDouble (Get-OptionalPropertyValue $long 'activation_dispatch_ms' $null)

$batchDelta = $null
if ($null -ne $shortBatch -and $null -ne $longBatch) {
    $batchDelta = [math]::Round(($longBatch + (-1.0 * $shortBatch)),3)
}
$marginGain = $null
if ($null -ne $shortMargin -and $null -ne $longMargin) {
    $marginGain = [math]::Round(($longMargin + (-1.0 * $shortMargin)),3)
}
$activationDelta = $null
if ($null -ne $shortActivation -and $null -ne $longActivation) {
    $activationDelta = [math]::Round(($longActivation + (-1.0 * $shortActivation)),3)
}

$comparison = [ordered]@{
    schema = 'recorder-poc.file-manager-prearm-comparison.v3'
    comparison_id = $comparisonId
    generated_utc = [DateTime]::UtcNow.ToString('o')
    file_count = $FileCount
    short_lead_ms = $ShortLeadMs
    long_lead_ms = $LongLeadMs
    ready_deadline_ms_before_window = $ReadyDeadlineMs
    activation_dispatch_budget_ms = $ActivationDispatchBudgetMs
    trials = $trials
    comparison = [ordered]@{
        batch_delta_ms_10s_minus_3s = $batchDelta
        min_arming_margin_gain_ms = $marginGain
        activation_dispatch_delta_ms = $activationDelta
        interpretation = if ($shortResult -eq 'PASS' -and $longResult -eq 'PASS') {
            'Both profiles passed with the same corrected implementation; compare batch cost and arming margin.'
        } elseif ($longResult -eq 'PASS') {
            '10s passed while 3s did not; inspect the 3s failure_stage to determine whether lead time was the limiting factor.'
        } else {
            '10s did not pass; the failure_stage/failure_reason must be resolved before attributing the result to lead time.'
        }
    }
}
$comparison | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $comparisonPath -Encoding UTF8

Write-Host ""
Write-Host '=== 3s vs 10s summary ==='
$trials | Select-Object label,result,process_exit_code,ready_at_deadline,batch_precreate_and_arm_ms,arming_margin_min_ms,arming_margin_p95_ms,activation_dispatch_ms,failure_stage,report_schema_complete | Format-Table -AutoSize

foreach ($trial in $trials) {
    if ([string](Get-OptionalPropertyValue $trial 'result' 'UNKNOWN') -ne 'PASS') {
        $trialLabel = [string](Get-OptionalPropertyValue $trial 'label' '?')
        $trialStage = [string](Get-OptionalPropertyValue $trial 'failure_stage' '')
        $trialReason = [string](Get-OptionalPropertyValue $trial 'failure_reason' '')
        $trialReport = [string](Get-OptionalPropertyValue $trial 'report' '')
        Write-Host ("{0} failure: stage={1} reason={2}" -f $trialLabel, $trialStage, $trialReason)
        Write-Host ("{0} report: {1}" -f $trialLabel, $trialReport)
    }
}
Write-Host "Comparison report: $comparisonPath"

if ($longResult -ne 'PASS') {
    Write-Error ("FILE MANAGER PRE-ARM COMPARISON: FAIL - 10s profile result={0}, stage={1}, reason={2}" -f $longResult, $longFailureStage, $longFailureReason)
    exit 18
}
Write-Host 'FILE MANAGER PRE-ARM COMPARISON: PASS (10s profile)'
exit 0
