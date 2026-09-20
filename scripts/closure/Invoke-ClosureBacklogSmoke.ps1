param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\.."))
)

$ErrorActionPreference = "Stop"

$requiredFiles = @(
    "AGENTS.md",
    "CODEX.md",
    "docs\phase25\closure-open-risks-next-implementation-backlog.md",
    "docs\phase25\acceptance.md",
    "config\closure\closure-backlog.ini",
    "scenarios\closure\closure-backlog-01.json"
)

$requiredTerms = @(
    "CWP",
    "Gateway",
    "LogicalTrackUUID",
    "TrackInstanceUUID",
    "TrackIndex",
    "NOT_RUN",
    "live buffer is not evidence",
    "synthetic silence",
    "one mono",
    "open risks",
    "next implementation backlog"
)

$failures = New-Object System.Collections.Generic.List[string]

foreach ($file in $requiredFiles) {
    $path = Join-Path $Root $file
    if (-not (Test-Path $path)) {
        $failures.Add("MISSING_FILE: $file")
    }
}

$agentsPath = Join-Path $Root "AGENTS.md"
if (Test-Path $agentsPath) {
    $agents = Get-Content -Raw -Path $agentsPath
    foreach ($term in $requiredTerms) {
        if ($agents -notmatch [regex]::Escape($term)) {
            $failures.Add("AGENTS_MISSING_TERM: $term")
        }
    }
    foreach ($forbidden in @("ED-137 certified", "all gates passed", "production ready")) {
        if ($agents -match [regex]::Escape($forbidden)) {
            $failures.Add("AGENTS_FORBIDDEN_CLAIM: $forbidden")
        }
    }
}

$result = [ordered]@{
    phase = "25.0.0"
    gate = "closure-backlog-smoke"
    status = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }
    checked_files = $requiredFiles
    failures = @($failures)
    note = "Static closure/handoff validation only; does not execute recorder or integrated campaign."
}

$outDir = Join-Path $Root "runs\closure"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir "closure-backlog-smoke-report.json"
$result | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $outPath

$result | ConvertTo-Json -Depth 8

if ($failures.Count -gt 0) { exit 1 }
exit 0
