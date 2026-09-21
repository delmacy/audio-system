[CmdletBinding()]
param(
    [int]$MaxSeconds = 28800,
    [string]$RecordingRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')

$root = Get-ProjectRoot
$exe = Find-RecorderHostExe
if (-not $exe) { throw 'recorder-host.exe was not built.' }
$plugin = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path -LiteralPath $plugin)) { throw 'gstmxfidentity.dll was not built.' }

$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$ip = [string]$profile['recorder']['ip']
$port = [int]$profile['recorder']['rtsp_port']

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runRoot = Join-Path $root 'runs\event-recorder'
$runDir = Join-Path $runRoot $stamp
if (-not $RecordingRoot) { $RecordingRoot = Join-Path $root 'recordings\event-files' }
New-Item -ItemType Directory -Force -Path $runDir,$RecordingRoot | Out-Null

$materializer = Join-Path $root 'scripts\player\recorder_materializer.py'
$materializedJson = & python $materializer '--run-dir' $runDir
if ($LASTEXITCODE -ne 0 -or -not $materializedJson) { throw 'Failed to materialize recorder routes.' }
$materialized = ($materializedJson -join [Environment]::NewLine) | ConvertFrom-Json
if ([int]$materialized.session_count -le 0) { throw 'No recorder routes were materialized.' }

$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$stdout = Join-Path $runDir 'recorder-stdout.txt'
$stderr = Join-Path $runDir 'recorder-stderr.txt'
$shutdown = Join-Path $runDir 'shutdown.signal'

$args = @(
    '--bind-ip',$ip,
    '--rtsp-port',[string]$port,
    '--session-map',[string]$materialized.session_map,
    '--audit',$audit,
    '--ready-file',$ready,
    '--plugin-dll',$plugin,
    '--recorder-id','RECORDER-EVENT-POC-01',
    '--max-seconds',[string]$MaxSeconds,
    '--event-files',
    '--recording-root',$RecordingRoot,
    '--shutdown-watch-file',$shutdown
)

$handle = Start-NativeProcessRedirected -FilePath $exe -Arguments $args -StdOutPath $stdout -StdErrPath $stderr -WorkingDirectory $root
$deadline = [DateTime]::UtcNow.AddSeconds(20)
while (-not (Test-Path -LiteralPath $ready)) {
    if ($handle.Process.HasExited) {
        throw "Event recorder exited before READY with code $($handle.Process.ExitCode)."
    }
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Event recorder did not reach READY.' }
    Start-Sleep -Milliseconds 100
}

$state = [ordered]@{
    schema='audio-system.event-recorder.v1'
    status='READY_IDLE'
    storage_strategy='event_files'
    timestamp_authority='media_ingress_utc'
    folder_layout='YYYY/MM/DD/HH/service'
    pid=$handle.Process.Id
    started_utc=[DateTime]::UtcNow.ToString('o')
    run_dir=$runDir
    recording_root=$RecordingRoot
    rtsp_ip=$ip
    rtsp_port=$port
    session_count=[int]$materialized.session_count
    session_map=[string]$materialized.session_map
    topology_manifest=[string]$materialized.manifest
    audit=$audit
    stdout=$stdout
    stderr=$stderr
    shutdown_signal=$shutdown
}
$statePath = Join-Path $runDir 'event-recorder-state.json'
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
Set-Content -LiteralPath (Join-Path $runRoot 'current-run.txt') -Value $runDir -Encoding utf8

Write-Host ('EVENT RECORDER READY pid={0} RTSP={1}:{2} routes={3}' -f $handle.Process.Id,$ip,$port,$materialized.session_count) -ForegroundColor Green
Write-Host 'AUDIO FORMAT: CCITT G.711 A-law, 8000 Hz, 8-bit, mono (PCMA/RTP PT 8)'
Write-Host 'TIMESTAMP AUTHORITY: media ingress time; physical file creation time is non-authoritative'
Write-Host ('FOLDER LAYOUT: {0}\YYYY\MM\DD\HH\<service>\' -f $RecordingRoot)
Write-Host ('STATE: {0}' -f $statePath)
Write-Host ('AUDIT/INDEX JOURNAL: {0}' -f $audit)
