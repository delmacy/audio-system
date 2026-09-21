[CmdletBinding()]
param([int]$MaxSeconds = 28800)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')

$root = Get-ProjectRoot
$exe = Find-RecorderHostExe
if (-not $exe) { throw 'recorder-host.exe ausente; execute 01-build-recorder-host.cmd.' }

$plugin = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path -LiteralPath $plugin)) { throw 'Plugin MXF de identidade ausente.' }

$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$ip = [string]$profile['recorder']['ip']
$port = [int]$profile['recorder']['rtsp_port']

# Clean start: a stale recorder-host or a previous listener on the configured
# RTSP port must never make a new recorder launch fail.
$stalePids = @()
$stalePids += @(Get-Process -Name 'recorder-host' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$stalePids += @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess)
$stalePids = @($stalePids | Where-Object { $_ -and [int]$_ -gt 0 } | Sort-Object -Unique)

foreach ($stalePid in $stalePids) {
  Write-Host "PRE-FLIGHT: encerrando processo antigo PID=$stalePid antes de iniciar o gravador."
  & taskkill.exe /PID ([string]$stalePid) /T /F 2>$null | Out-Null
}

$deadlinePort = [DateTime]::UtcNow.AddSeconds(8)
do {
  $occupied = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
  if ($occupied.Count -eq 0) { break }
  Start-Sleep -Milliseconds 150
} while ([DateTime]::UtcNow -lt $deadlinePort)

$occupied = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
if ($occupied.Count -gt 0) {
  $owners = ($occupied | Select-Object -ExpandProperty OwningProcess -Unique) -join ','
  throw "Não foi possível liberar a porta RTSP $ip`:$port. PID(s): $owners"
}

$now = Get-Date
$runDir = Join-Path $root ('runs\operational-recorder\' + $now.ToString('yyyyMMdd-HHmmssfff'))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$materializer = Join-Path $root 'scripts\player\recorder_materializer.py'
$materializedJson = & python $materializer --run-dir $runDir
if ($LASTEXITCODE -ne 0 -or -not $materializedJson) { throw 'Falha ao materializar topologia do gravador.' }
$materialized = ($materializedJson -join [Environment]::NewLine) | ConvertFrom-Json
if ([int]$materialized.session_count -le 0) { throw 'Nenhuma track foi materializada.' }

$map = [string]$materialized.session_map
$manifestPath = [string]$materialized.manifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$windowEnd = [DateTimeOffset]::Parse([string]$manifest.window_end_utc)
$secondsToBoundary = [Math]::Max(1,[int][Math]::Ceiling(($windowEnd - [DateTimeOffset]::UtcNow).TotalSeconds))
$effectiveMaxSeconds = if ($MaxSeconds -gt 0) { [Math]::Min($MaxSeconds,$secondsToBoundary) } else { $secondsToBoundary }
$topologySignal = Join-Path $root 'runs\operational-recorder\topology-change.signal'
$shutdownSignal = Join-Path $root 'runs\operational-recorder\shutdown.signal'
if (Test-Path -LiteralPath $shutdownSignal) {
  Remove-Item -LiteralPath $shutdownSignal -Force -ErrorAction SilentlyContinue
}

$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$stdout = Join-Path $runDir 'recorder-stdout.txt'
$stderr = Join-Path $runDir 'recorder-stderr.txt'

$args = @(
  '--bind-ip',$ip,
  '--rtsp-port',[string]$port,
  '--session-map',$map,
  '--audit',$audit,
  '--ready-file',$ready,
  '--plugin-dll',$plugin,
  '--recorder-id','RECORDER-POC-01',
  '--max-seconds',[string]$effectiveMaxSeconds,
  '--shared-mxf-by-output',
  '--topology-watch-file',$topologySignal,
  '--topology-revision',[string]$manifest.topology_revision,
  '--shutdown-watch-file',$shutdownSignal
)

$proc = Start-Process -FilePath $exe -ArgumentList (ConvertTo-NativeArgumentString $args) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr

$deadline = [DateTime]::UtcNow.AddSeconds(20)
while (-not (Test-Path -LiteralPath $ready)) {
  $proc.Refresh()
  if ($proc.HasExited) {
    $err = if (Test-Path $stderr) { Get-Content -LiteralPath $stderr -Raw } else { '' }
    throw "Recorder saiu antes de READY, código $($proc.ExitCode): $err"
  }
  if ([DateTime]::UtcNow -gt $deadline) { throw 'Recorder não atingiu READY em 20 segundos.' }
  Start-Sleep -Milliseconds 100
}

$state = [ordered]@{
  schema='audio-system.operational-recorder.v3'
  status='READY_IDLE'
  scope='shared_category_mxf'
  started_utc=[DateTime]::UtcNow.ToString('o')
  pid=$proc.Id
  run_dir=$runDir
  recording_root=(Join-Path $root 'recordings')
  rtsp_ip=$ip
  rtsp_port=$port
  session_count=[int]$materialized.session_count
  track_count=@($manifest.tracks).Count
  shared_mxf=$true
  files=$manifest.files
  tracks=$manifest.tracks
  topology_manifest=$manifestPath
  session_map=$map
  ready_file=$ready
  audit=$audit
  stdout=$stdout
  stderr=$stderr
  max_seconds=$effectiveMaxSeconds
  rotation_minutes=[int]$manifest.settings.rotation_minutes
  topology_revision=[int]$manifest.topology_revision
  topology_change_guard_seconds=[int]$manifest.settings.topology_change_guard_seconds
  window_end_utc=[string]$manifest.window_end_utc
  shutdown_signal=$shutdownSignal
  live_buffer_available=$false
}
$statePath = Join-Path $runDir 'operational-recorder-state.json'
$state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding utf8
Set-Content -LiteralPath (Join-Path $root 'runs\operational-recorder\current-run.txt') -Value $runDir -Encoding utf8

Write-Host "RECORDER READY_IDLE pid=$($proc.Id) RTSP=$ip`:$port sessions=$($materialized.session_count)"
foreach ($name in @('cwp','radio','telephone')) {
  $file = $manifest.files.$name
  if ($file) { Write-Host ("{0}: {1} tracks={2}" -f $name.ToUpperInvariant(),$file.path,$file.track_count) }
}
Write-Host "Manifest: $manifestPath"
Write-Host "State: $statePath"
