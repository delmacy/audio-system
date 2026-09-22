param(
    [string]$ScenarioPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\recorder\Common-Recorder.ps1')

$root = Get-ProjectRoot
if (-not $ScenarioPath) {
    $ScenarioPath = Join-Path $root 'config\tone-scenarios\mixed-lab.json'
}
$runner = Join-Path $root 'scripts\generator\Invoke-ToneScenario.ps1'
if (-not (Test-Path -LiteralPath $runner)) { throw "Tone scenario runner not found: $runner" }
if (-not (Test-Path -LiteralPath $ScenarioPath)) { throw "Tone scenario not found: $ScenarioPath" }

Write-Host ('Injecting multitrack tone scenario: ' + $ScenarioPath) -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -ScenarioPath $ScenarioPath
if ($LASTEXITCODE -ne 0) { throw "Tone scenario injection failed with exit code $LASTEXITCODE" }
Write-Host 'MULTITRACK TONE INJECTION: PASS' -ForegroundColor Green
