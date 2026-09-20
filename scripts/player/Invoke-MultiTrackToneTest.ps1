param(
  [string]$Ffmpeg = 'ffmpeg'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\recorder\Common-Recorder.ps1')
$root = Get-ProjectRoot
$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$localIp = [string]$profile['cwp-a']['ip_start']
$recorderIp = [string]$profile['recorder']['ip']
$rtspPort = [int]$profile['recorder']['rtsp_port']
$ff = Get-Command $Ffmpeg -ErrorAction SilentlyContinue
if (-not $ff) { throw 'FFmpeg was not found in PATH.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $root ('runs\tone-injection\' + $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null

$tone440 = Join-Path $out 'tone-440Hz.pcma'
$tone660 = Join-Path $out 'tone-660Hz.pcma'
& $ff.Source '-hide_banner' '-loglevel' 'error' '-y' '-f' 'lavfi' '-i' 'sine=frequency=440:sample_rate=8000:duration=2' '-ac' '1' '-ar' '8000' '-f' 'alaw' $tone440
if ($LASTEXITCODE -ne 0) { throw 'Failed to generate 440 Hz tone.' }
& $ff.Source '-hide_banner' '-loglevel' 'error' '-y' '-f' 'lavfi' '-i' 'sine=frequency=660:sample_rate=8000:duration=2' '-ac' '1' '-ar' '8000' '-f' 'alaw' $tone660
if ($LASTEXITCODE -ne 0) { throw 'Failed to generate 660 Hz tone.' }
Write-Host ('Generated tone: ' + $tone440) -ForegroundColor Cyan
Write-Host ('Generated tone: ' + $tone660) -ForegroundColor Cyan

$sim = Join-Path $root 'scripts\cwp\Invoke-ServiceMonoSessionSimulator.ps1'
$ps = (Get-Command powershell.exe).Source
$tracks = @(
  [ordered]@{name='radio-121500';endpoint='CWP-TONE-01';service='121500';type='radio';recorder_rtp=20500;local_rtp=21500;file=$tone440;delay=0;bursts=4;burst_ms=400;silence_ms=600},
  [ordered]@{name='radio-118700';endpoint='CWP-TONE-02';service='118700';type='radio';recorder_rtp=20502;local_rtp=21502;file=$tone440;delay=500;bursts=3;burst_ms=700;silence_ms=900},
  [ordered]@{name='tel-050';endpoint='TEL-TONE-01';service='050';type='telephone';recorder_rtp=20504;local_rtp=21504;file=$tone660;delay=1200;bursts=2;burst_ms=1000;silence_ms=1300}
)
$running = @()
foreach ($t in $tracks) {
  $stdout = Join-Path $out ($t.name + '-stdout.txt')
  $stderr = Join-Path $out ($t.name + '-stderr.txt')
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$sim,'-LocalIp',$localIp,'-RecorderIp',$recorderIp,'-RtspPort',[string]$rtspPort,'-RecorderRtpPort',[string]$t.recorder_rtp,'-LocalRtpPort',[string]$t.local_rtp,'-EndpointId',$t.endpoint,'-ServiceId',$t.service,'-ServiceType',$t.type,'-MediaFlow','mono','-BurstCount',[string]$t.bursts,'-BurstMs',[string]$t.burst_ms,'-SilenceMs',[string]$t.silence_ms,'-KeepaliveIntervalMs','100','-PausedProbePackets','0','-StartDelayMs',[string]$t.delay,'-PcmaFile',$t.file)
  Write-Host ('Injecting ' + $t.name + ' delay=' + $t.delay + 'ms bursts=' + $t.bursts + ' burst=' + $t.burst_ms + 'ms gap=' + $t.silence_ms + 'ms') -ForegroundColor Yellow
  $handle = Start-NativeProcessRedirected -FilePath $ps -Arguments $args -StdOutPath $stdout -StdErrPath $stderr -WorkingDirectory $root
  $running += [pscustomobject]@{track=$t;handle=$handle}
}
$fail = 0
foreach ($r in $running) {
  $result = Complete-NativeProcessRedirected -Handle $r.handle -TimeoutMs 60000
  if ($result.ExitCode -ne 0 -or [string]$result.StdOut -notmatch 'SERVICE MONO SIMULATOR: PASS') {
    $fail++
    Write-Host ('FAIL ' + $r.track.name + ' exit=' + $result.ExitCode + ' stderr=' + [string]$result.StdErr) -ForegroundColor Red
  } else {
    Write-Host ('PASS ' + $r.track.name) -ForegroundColor Green
  }
}
if ($fail -gt 0) { throw ('Tone injection failed for ' + $fail + ' track(s).') }
Write-Host ('TONE INJECTION PASS output=' + $out) -ForegroundColor Green