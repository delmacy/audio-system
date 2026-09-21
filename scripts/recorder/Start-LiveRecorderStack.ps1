[CmdletBinding()]
param([int]$Cycles = 0, [int]$RestartDelayMs = 750)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$start = Join-Path $PSScriptRoot 'Start-RecorderLab.ps1'
$indexer = Join-Path $root 'scripts\player\recorder_index.py'
$completed = 0
$stopSignal = Join-Path $root 'runs\operational-recorder\stop.signal'
if (Test-Path -LiteralPath $stopSignal) { Remove-Item -LiteralPath $stopSignal -Force }

while ($Cycles -eq 0 -or $completed -lt $Cycles) {
  if (Test-Path -LiteralPath $stopSignal) { break }
  try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $start -MaxSeconds 28800 | Out-Null

    $pointer = Join-Path $root 'runs\operational-recorder\current-run.txt'
    $run = (Get-Content -LiteralPath $pointer -Raw).Trim()
    $statePath = Join-Path $run 'operational-recorder-state.json'
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

    $proc = Get-Process -Id ([int]$state.pid) -ErrorAction SilentlyContinue
    if ($proc) { Wait-Process -Id $proc.Id }
    if (Test-Path -LiteralPath $stopSignal) { break }

    $indexJson = & python $indexer ingest --manifest ([string]$state.topology_manifest) --audit ([string]$state.audit)
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao indexar janela MXF fechada.' }

    $state.status = 'CLOSED_COMPLETE'
    $state | Add-Member -NotePropertyName indexed_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $state | Add-Member -NotePropertyName index_result -NotePropertyValue (($indexJson -join [Environment]::NewLine) | ConvertFrom-Json) -Force
    $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding utf8
    $completed++
  } catch {
    Add-Content -LiteralPath (Join-Path $root 'runs\operational-recorder\live-supervisor-errors.log') -Value "$(Get-Date -Format o) $($_.Exception.Message)"
  }

  if (Test-Path -LiteralPath $stopSignal) { break }
  Start-Sleep -Milliseconds $RestartDelayMs
}
if (Test-Path -LiteralPath $stopSignal) { Remove-Item -LiteralPath $stopSignal -Force -ErrorAction SilentlyContinue }
