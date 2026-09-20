[CmdletBinding()]
param([int]$MaxSeconds = 28800)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')
. (Join-Path $PSScriptRoot '..\mxf\Track-Identity.ps1')

$root = Get-ProjectRoot
$exe = Find-RecorderHostExe
if (-not $exe) { throw 'recorder-host.exe ausente; execute 01-build-recorder-host.cmd.' }
$plugin = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path -LiteralPath $plugin)) { throw 'Plugin MXF de identidade ausente.' }
$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$ip = [string]$profile['recorder']['ip']; $port = [int]$profile['recorder']['rtsp_port']
if (Get-NetTCPConnection -LocalAddress $ip -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { throw "Porta RTSP $ip`:$port já está em uso." }
$runDir = Join-Path $root ('runs\operational-recorder\' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$endpoint = 'CWP-LAB-01'; $service = 'LAB-121500'; $rtp = 20500
$identity = New-ServiceLogicalTrackIdentity -ServiceType radio -ServiceId $service -EndpointId $endpoint -MediaFlow mono
$stem = Join-Path $runDir 'radio-lab-121500'
$partial = $stem + '.mxf.partial'; $final = $stem + '.mxf'; $lock = $stem + '.mxf.lock'
$route = "/record/$endpoint/radio-$($service.ToLowerInvariant())-rx"
$fields = @($route,$endpoint,$service,'mono','squ',[string]$identity.display_name,[string]$identity.logical_track_uuid,[string]$identity.track_instance_uuid,('OP-' + [Guid]::NewGuid().ToString()),$partial,$final,$lock,[string]$rtp,([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:00:00.000Z')),'0','radio')
$header = @('route_key','endpoint_id','service_id','media_flow','activity_signal','display_name','logical_uuid','instance_uuid','file_id','output_partial','output_final','lock_path','rtp_port','window_start_utc','segment_sequence','session_kind')
$map = Join-Path $runDir 'session-map.tsv'
[IO.File]::WriteAllLines($map,[string[]]@(($header -join "`t"),($fields -join "`t")),(New-Object Text.UTF8Encoding($false)))
$audit = Join-Path $runDir 'recorder-audit.jsonl'; $ready = Join-Path $runDir 'recorder-ready.json'
$stdout = Join-Path $runDir 'recorder-stdout.txt'; $stderr = Join-Path $runDir 'recorder-stderr.txt'
$args = @('--bind-ip',$ip,'--rtsp-port',[string]$port,'--session-map',$map,'--audit',$audit,'--ready-file',$ready,'--plugin-dll',$plugin,'--recorder-id','RECORDER-POC-01','--max-seconds',[string]$MaxSeconds)
$proc = Start-Process -FilePath $exe -ArgumentList (ConvertTo-NativeArgumentString $args) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while (-not (Test-Path -LiteralPath $ready)) {
  $proc.Refresh()
  if ($proc.HasExited) { throw "Recorder saiu antes de READY, código $($proc.ExitCode): $(Get-Content -LiteralPath $stderr -Raw)" }
  if ([DateTime]::UtcNow -gt $deadline) { throw 'Recorder não atingiu READY em 15 segundos.' }
  Start-Sleep -Milliseconds 100
}
$state = [ordered]@{schema='recorder-poc.operational-recorder.v1';status='READY_IDLE';scope='single_direct_cwp_rtsp_rtp_session';started_utc=[DateTime]::UtcNow.ToString('o');pid=$proc.Id;run_dir=$runDir;rtsp_ip=$ip;rtsp_port=$port;rtp_port=$rtp;endpoint_id=$endpoint;service_id=$service;logical_track_uuid=$identity.logical_track_uuid;track_instance_uuid=$identity.track_instance_uuid;route=$route;partial_mxf=$partial;final_mxf=$final;ready_file=$ready;audit=$audit;max_seconds=$MaxSeconds;live_buffer_available=$false}
$statePath = Join-Path $runDir 'operational-recorder-state.json'
$state | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $statePath -Encoding utf8
Set-Content -LiteralPath (Join-Path $root 'runs\operational-recorder\current-run.txt') -Value $runDir -Encoding utf8
Write-Host "RECORDER READY_IDLE pid=$($proc.Id) RTSP=$ip`:$port RTP=$rtp"
Write-Host "Route: $route"
Write-Host "State: $statePath"
