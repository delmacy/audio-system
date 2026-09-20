param(
    [int]$MaxSeconds = 28800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')
. (Join-Path $PSScriptRoot '..\mxf\Track-Identity.ps1')

$root = Get-ProjectRoot
$exe = Find-RecorderHostExe
if (-not $exe) { throw 'recorder-host.exe missing; build it before the tone test.' }
$plugin = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path -LiteralPath $plugin)) { throw 'gstmxfidentity.dll missing.' }
$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$ip = [string]$profile['recorder']['ip']
$port = [int]$profile['recorder']['rtsp_port']
if (Get-NetTCPConnection -LocalAddress $ip -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { throw ('RTSP port already in use: ' + $ip + ':' + $port) }

$definitions = @(
  [ordered]@{name='radio-121500';endpoint='CWP-TONE-01';service='121500';type='radio';rtp=20500},
  [ordered]@{name='radio-118700';endpoint='CWP-TONE-02';service='118700';type='radio';rtp=20502},
  [ordered]@{name='tel-050';endpoint='TEL-TONE-01';service='050';type='telephone';rtp=20504}
)

$runDir = Join-Path $root ('runs\operational-recorder\' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$tab = [char]9
$rows = @()
$stateTracks = @()
$windowStartUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:00:00.000Z')

foreach ($d in $definitions) {
  $identity = New-ServiceLogicalTrackIdentity -ServiceType $d.type -ServiceId $d.service -EndpointId $d.endpoint -MediaFlow 'mono'
  $slug = if ($d.type -eq 'telephone') { 'tel-' + $d.service } else { 'radio-' + $d.service }
  $route = '/record/' + $d.endpoint + '/' + $slug
  $stem = Join-Path $runDir $d.name
  $partial = $stem + '.mxf.partial'
  $final = $stem + '.mxf'
  $lock = $stem + '.mxf.lock'
  $fileId = 'TONE-' + [Guid]::NewGuid().ToString()
  $fields = @($route,$d.endpoint,$d.service,'mono','activity',[string]$identity.display_name,[string]$identity.logical_track_uuid,[string]$identity.track_instance_uuid,$fileId,$partial,$final,$lock,[string]$d.rtp,$windowStartUtc,'0',[string]$d.type)
  $rows += ($fields -join $tab)
  $stateTracks += [ordered]@{name=$d.name;endpoint_id=$d.endpoint;service_id=$d.service;service_type=$d.type;logical_track_uuid=[string]$identity.logical_track_uuid;track_instance_uuid=[string]$identity.track_instance_uuid;route=$route;rtp_port=$d.rtp;final_mxf=$final}
}

$header = @('route_key','endpoint_id','service_id','media_flow','activity_signal','display_name','logical_uuid','instance_uuid','file_id','output_partial','output_final','lock_path','rtp_port','window_start_utc','segment_sequence','session_kind') -join $tab
$map = Join-Path $runDir 'session-map.tsv'
[IO.File]::WriteAllLines($map,[string[]](@($header)+$rows),(New-Object Text.UTF8Encoding($false)))
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$stdout = Join-Path $runDir 'recorder-stdout.txt'
$stderr = Join-Path $runDir 'recorder-stderr.txt'
$args = @('--bind-ip',$ip,'--rtsp-port',[string]$port,'--session-map',$map,'--audit',$audit,'--ready-file',$ready,'--plugin-dll',$plugin,'--recorder-id','RECORDER-POC-TONE','--max-seconds',[string]$MaxSeconds)
$proc = Start-Process -FilePath $exe -ArgumentList (ConvertTo-NativeArgumentString $args) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while (-not (Test-Path -LiteralPath $ready)) {
  $proc.Refresh()
  if ($proc.HasExited) { throw ('Recorder exited before READY. See ' + $stderr) }
  if ([DateTime]::UtcNow -gt $deadline) { throw 'Recorder did not reach READY in 15 seconds.' }
  Start-Sleep -Milliseconds 100
}
$state = [ordered]@{schema='audio-system.tone-recorder-lab.v1';status='READY_IDLE';scope='multi_track_tone_injection';started_utc=[DateTime]::UtcNow.ToString('o');pid=$proc.Id;run_dir=$runDir;rtsp_ip=$ip;rtsp_port=$port;tracks=$stateTracks;audit=$audit;ready_file=$ready;max_seconds=$MaxSeconds}
$statePath = Join-Path $runDir 'operational-recorder-state.json'
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
Set-Content -LiteralPath (Join-Path $root 'runs\operational-recorder\current-run.txt') -Value $runDir -Encoding utf8
Write-Host ('TONE RECORDER READY pid=' + $proc.Id + ' RTSP=' + $ip + ':' + $port + ' tracks=3') -ForegroundColor Green
$stateTracks | ForEach-Object { Write-Host ('  ' + $_.name + ' -> ' + $_.route + ' RTP=' + $_.rtp_port) }
Write-Host ('State: ' + $statePath)