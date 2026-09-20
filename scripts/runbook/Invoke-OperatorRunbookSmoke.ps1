param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"

$scenarioPath = Join-Path $Root "scenarios\runbook\operator-runbook-01.json"
$reportDir = Join-Path $Root "runs\runbook"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$scenario = Get-Content $scenarioPath -Raw | ConvertFrom-Json
$results = @()

foreach ($rel in $scenario.required_files) {
    $path = Join-Path $Root $rel
    $results += [pscustomobject]@{
        check = "required_file"
        target = $rel
        status = $(if (Test-Path $path) { "PASS" } else { "FAIL" })
    }
}

$runbookRel = "docs\phase23\operator-runbook-deployment-notes.md"
$runbookPath = Join-Path $Root $runbookRel
$text = if (Test-Path $runbookPath) { Get-Content $runbookPath -Raw } else { "" }
foreach ($term in $scenario.required_terms) {
    $results += [pscustomobject]@{
        check = "required_term"
        target = $term
        status = $(if ($text.Contains($term)) { "PASS" } else { "FAIL" })
    }
}

$failures = @($results | Where-Object { $_.status -ne "PASS" })
$status = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }

$report = [pscustomobject]@{
    phase = "23.0.0"
    gate = "operator-runbook-smoke"
    status = $status
    generated_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $Root
    results = $results
}

$reportPath = Join-Path $reportDir "operator-runbook-smoke-report.json"
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $reportPath

Write-Host "Operator runbook smoke: $status"
Write-Host "Report: $reportPath"

if ($status -ne "PASS") { exit 1 }
exit 0
