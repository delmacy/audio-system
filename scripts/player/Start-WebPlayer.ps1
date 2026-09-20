[CmdletBinding()]
param([int]$Port = 8765)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$url = "http://127.0.0.1:$Port/"
$frontendAvailable = Test-Path -LiteralPath (Join-Path $root 'web\player\index.html')
$runtimeStatus = if ($frontendAvailable) { 'READY' } else { 'API_ONLY' }
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
  try {
    $health = Invoke-RestMethod -Uri ($url + 'health') -TimeoutSec 3
    if ($health.status -eq 'ok' -and $health.scope -eq 'historical_closed_mxf') {
      $hostDir = Join-Path $root 'runs\web-player-runtime\host'
      New-Item -ItemType Directory -Force -Path $hostDir | Out-Null
      [ordered]@{schema='recorder-poc.web-player-runtime.v1';status=$runtimeStatus;scope='historical_closed_mxf';checked_utc=[DateTime]::UtcNow.ToString('o');pid=$listener.OwningProcess;url=$url;index=$health.index;live_tap_available=$false;frontend_available=$frontendAvailable} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $hostDir 'state.json') -Encoding utf8
      Write-Host "WEB PLAYER $runtimeStatus $url pid=$($listener.OwningProcess)"
      exit 0
    }
  } catch {}
  throw "Porta $Port ocupada por outro processo."
}
$python = (Get-Command python.exe -ErrorAction Stop).Source
$script = Join-Path $PSScriptRoot 'serve_player.py'
$hostDir = Join-Path $root 'runs\web-player-runtime\host'
New-Item -ItemType Directory -Force -Path $hostDir | Out-Null
$stdout = Join-Path $hostDir 'stdout.log'; $stderr = Join-Path $hostDir 'stderr.log'
$process = Start-Process -FilePath $python -ArgumentList @('-u',('"' + $script + '"'),'--port',[string]$Port) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$deadline = [DateTime]::UtcNow.AddSeconds(12)
while ($true) {
  $process.Refresh()
  if ($process.HasExited) { throw "Web Player encerrou: $(Get-Content -LiteralPath $stderr -Raw)" }
  try {
    $health = Invoke-RestMethod -Uri ($url + 'health') -TimeoutSec 2
    if ($health.status -eq 'ok') { break }
  } catch {}
  if ([DateTime]::UtcNow -gt $deadline) { throw 'Web Player não respondeu em 12 segundos.' }
  Start-Sleep -Milliseconds 200
}
$state = [ordered]@{schema='recorder-poc.web-player-runtime.v1';status=$runtimeStatus;scope='historical_closed_mxf';started_utc=[DateTime]::UtcNow.ToString('o');pid=$process.Id;url=$url;index=$health.index;live_tap_available=$false;frontend_available=$frontendAvailable;stdout=$stdout;stderr=$stderr}
$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $hostDir 'state.json') -Encoding utf8
Write-Host "WEB PLAYER $runtimeStatus $url pid=$($process.Id)"
