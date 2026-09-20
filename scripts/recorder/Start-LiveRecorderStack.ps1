[CmdletBinding()]
param([int]$Cycles = 0, [int]$RestartDelayMs = 750)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$start = Join-Path $PSScriptRoot 'Start-RecorderLab.ps1'
$completed = 0
while ($Cycles -eq 0 -or $completed -lt $Cycles) {
  try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $start -MaxSeconds 28800 | Out-Null
    $pointer = Join-Path $root 'runs\operational-recorder\current-run.txt'
    $run = (Get-Content -LiteralPath $pointer -Raw).Trim()
    $state = Get-Content -LiteralPath (Join-Path $run 'operational-recorder-state.json') -Raw | ConvertFrom-Json
    $proc = Get-Process -Id ([int]$state.pid) -ErrorAction SilentlyContinue
    if ($proc) { Wait-Process -Id $proc.Id }
    $completed++
  } catch {
    Add-Content -LiteralPath (Join-Path $root 'runs\operational-recorder\live-supervisor-errors.log') -Value "$(Get-Date -Format o) $($_.Exception.Message)"
  }
  Start-Sleep -Milliseconds $RestartDelayMs
}
