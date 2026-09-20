param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$requiredFiles = @(
    "docs/phase24/final-poc-packaging-release-candidate.md",
    "docs/phase24/acceptance.md",
    "config/release/final-poc-packaging.ini",
    "scenarios/release/final-poc-packaging-01.json",
    "scripts/release/22-final-poc-packaging-smoke.cmd",
    "scripts/release/Invoke-FinalPocPackagingSmoke.ps1",
    "scripts/runbook/21-operator-runbook-smoke.cmd",
    "scripts/acceptance/20-integrated-acceptance-plan-smoke.cmd",
    "scripts/stress/19-progressive-stress-smoke.cmd",
    "scripts/integrity/17-integrity-manifest-chain-smoke.cmd",
    "scripts/export/16-export-evidence-bundle-smoke.cmd",
    "CHANGELOG-PHASE24-24.0.0.md"
)

$checks = New-Object System.Collections.Generic.List[object]
foreach ($rel in $requiredFiles) {
    $path = Join-Path $Root $rel
    $checks.Add([pscustomobject]@{
        check = "exists:$rel"
        pass = (Test-Path -LiteralPath $path)
        path = $path
    })
}

$docPath = Join-Path $Root "docs/phase24/final-poc-packaging-release-candidate.md"
$docText = if (Test-Path -LiteralPath $docPath) { Get-Content -LiteralPath $docPath -Raw } else { "" }

$semanticChecks = @(
    @{ name = "mentions NOT_RUN remains NOT_RUN"; pattern = "NOT_RUN remains NOT_RUN" },
    @{ name = "live buffer not evidence"; pattern = "live buffer = operational preview, not evidence" },
    @{ name = "fixture not evidence"; pattern = "fixture = harness input, not evidence" },
    @{ name = "synthetic silence not evidence"; pattern = "synthetic silence = presentation convenience, not recorded audio" },
    @{ name = "RC_VALIDATED requires execution"; pattern = "only after the integrated acceptance gates have actually run and passed" }
)

foreach ($item in $semanticChecks) {
    $checks.Add([pscustomobject]@{
        check = $item.name
        pass = ($docText -like ("*" + $item.pattern + "*"))
        path = $docPath
    })
}

$failed = @($checks | Where-Object { -not $_.pass })
$result = [pscustomobject]@{
    phase = 24
    version = "24.0.0"
    status = if ($failed.Count -eq 0) { "PASS" } else { "FAIL" }
    failed_count = $failed.Count
    checks = $checks
    note = "Packaging smoke only; does not execute recorder acceptance gates."
}

$outDir = Join-Path $Root "runs\release\phase24"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outDir "final-poc-packaging-report.json") -Encoding UTF8

if ($Json) {
    $result | ConvertTo-Json -Depth 6
} else {
    Write-Host "Phase 24 Final PoC Packaging Smoke: $($result.status)"
    Write-Host "Report: $outDir\final-poc-packaging-report.json"
    if ($failed.Count -gt 0) {
        Write-Host "Failed checks:"
        $failed | ForEach-Object { Write-Host " - $($_.check)" }
    }
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
