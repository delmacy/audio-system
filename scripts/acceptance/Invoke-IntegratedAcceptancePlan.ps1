param(
    [string]$RunId = (Get-Date -Format "yyyyMMdd-HHmmss"),
    [string]$ScenarioPath = "scenarios/acceptance/integrated-acceptance-01.json",
    [string]$OutRoot = "runs/acceptance",
    [switch]$SimulatePass
)

$ErrorActionPreference = "Stop"

function New-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Write-JsonFile($Object, [string]$Path) {
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scenario = Get-Content -LiteralPath $ScenarioPath -Raw | ConvertFrom-Json
$runDir = Join-Path $OutRoot $RunId
$gatesDir = Join-Path $runDir "gates"
New-Dir $runDir
New-Dir $gatesDir

$gateResults = @()
foreach ($g in $scenario.gates) {
    $gateId = [string]$g[0]
    $script = [string]$g[1]
    $required = [bool]$g[2]
    $gateDir = Join-Path $gatesDir $gateId
    New-Dir $gateDir

    $status = if ($SimulatePass -or -not $required) { "PASS" } else { "NOT_RUN" }
    if (-not $required -and -not $SimulatePass) { $status = "NOT_RUN" }

    $result = [ordered]@{
        gate_id = $gateId
        script = $script
        required = $required
        status = $status
        simulated = $true
        evidence_path = "gates/$gateId/gate-result.json"
        failure_class = $null
        notes = if ($SimulatePass) { "Deterministic simulated PASS for aggregator smoke." } else { "Not executed by integrated plan smoke." }
    }

    Write-JsonFile $result (Join-Path $gateDir "gate-result.json")
    $gateResults += [pscustomobject]$result
}

$requiredProblem = $gateResults | Where-Object { $_.required -and ($_.status -eq "NOT_RUN" -or $_.status -eq "BLOCKED") }
$failures = $gateResults | Where-Object { $_.status -eq "FAIL" }
$warnings = $gateResults | Where-Object { $_.status -eq "WARN" }

$verdict = "PASS"
if ($failures.Count -gt 0) { $verdict = "FAIL" }
elseif ($requiredProblem.Count -gt 0) { $verdict = "BLOCKED" }
elseif ($warnings.Count -gt 0) { $verdict = "PASS_WITH_WARNINGS" }

$report = [ordered]@{
    phase = "22.0.0"
    run_id = $RunId
    generated_utc = (Get-Date).ToUniversalTime().ToString("o")
    simulated = $true
    simulated_results_are_not_certification = $true
    verdict = $verdict
    invariants = $scenario.invariants
    gates = $gateResults
    evidence_critical_failures = @(
        "silent media loss",
        "cross-service contamination",
        "P0 event silently dropped",
        "LogicalTrackUUID mismatch",
        "TrackInstanceUUID/source-map mismatch",
        "unreported gap",
        "export bundle hash mismatch",
        "manifest chain mismatch",
        "live buffer treated as evidence",
        "synthetic silence treated as recorded evidence"
    )
}

Write-JsonFile $report (Join-Path $runDir "integrated-acceptance-report.json")

$csv = $gateResults | Select-Object gate_id,required,status,script,evidence_path,simulated
$csv | Export-Csv -LiteralPath (Join-Path $runDir "integrated-acceptance-summary.csv") -NoTypeInformation -Encoding UTF8

$md = @()
$md += "# Integrated Acceptance Report"
$md += ""
$md += "Run: $RunId"
$md += ""
$md += "Verdict: **$verdict**"
$md += ""
$md += "> This deterministic smoke validates aggregation logic only. It is not a certification run."
$md += ""
$md += "## Frozen invariants"
$md += ""
$md += "- CWP path: $($scenario.invariants.cwp_path)"
$md += "- Gateway scope: $($scenario.invariants.gateway_scope)"
$md += "- Media model: $($scenario.invariants.media_model)"
$md += "- Live buffer is evidence: $($scenario.invariants.live_buffer_is_evidence)"
$md += "- Synthetic silence is recorded evidence: $($scenario.invariants.synthetic_silence_is_recorded_evidence)"
$md += ""
$md += "## Gates"
$md += ""
$md += "| Gate | Required | Status | Script |"
$md += "|---|---:|---|---|"
foreach ($r in $gateResults) {
    $md += "| $($r.gate_id) | $($r.required) | $($r.status) | $($r.script) |"
}
$md -join "`r`n" | Set-Content -LiteralPath (Join-Path $runDir "integrated-acceptance-report.md") -Encoding UTF8

Write-Host "INTEGRATED ACCEPTANCE PLAN: $verdict"
Write-Host "Run directory: $runDir"
if ($verdict -ne "PASS") { exit 2 }
