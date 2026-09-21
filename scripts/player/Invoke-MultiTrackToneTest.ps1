Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\recorder\Common-Recorder.ps1')
$root = Get-ProjectRoot
$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$localIp = [string]$profile['cwp-a']['ip_start']
$recorderIp = [string]$profile['recorder']['ip']
$rtspPort = [int]$profile['recorder']['rtsp_port']
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $root ('runs\tone-injection\' + $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null

$sim = Join-Path $root 'scripts\cwp\Invoke-ServiceMonoSessionSimulator.ps1'
$ps = (Get-Command powershell.exe).Source
$tracks = @(
  [ordered]@{name='radio-121500';endpoint='CWP-TONE-01';service='121500';type='radio';recorder_rtp=20500;local_rtp=21500;tone_hz=440;delay=0;bursts=4;burst_ms=400;silence_ms=600},
  [ordered]@{name='radio-118700';endpoint='CWP-TONE-02';service='118700';type='radio';recorder_rtp=20502;local_rtp=21502;tone_hz=440;delay=500;bursts=3;burst_ms=700;silence_ms=900},
  [ordered]@{name='tel-050';endpoint='TEL-TONE-01';service='050';type='telephone';recorder_rtp=20504;local_rtp=21504;tone_hz=660;delay=1200;bursts=2;burst_ms=1000;silence_ms=1300}
)
$running = @()
foreach ($t in $tracks) {
  $stdout = Join-Path $out ($t.name + '-stdout.txt')
  $stderr = Join-Path $out ($t.name + '-stderr.txt')
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$sim,'-LocalIp',$localIp,'-RecorderIp',$recorderIp,'-RtspPort',[string]$rtspPort,'-RecorderRtpPort',[string]$t.recorder_rtp,'-LocalRtpPort',[string]$t.local_rtp,'-EndpointId',$t.endpoint,'-ServiceId',$t.service,'-ServiceType',$t.type,'-MediaFlow','mono','-BurstCount',[string]$t.bursts,'-BurstMs',[string]$t.burst_ms,'-SilenceMs',[string]$t.silence_ms,'-KeepaliveIntervalMs','100','-PausedProbePackets','0','-StartDelayMs',[string]$t.delay,'-ToneHz',[string]$t.tone_hz,'-ToneLevelDbfs','-12')
  Write-Host ('Injecting ' + $t.name + ' tone=' + $t.tone_hz + 'Hz delay=' + $t.delay + 'ms bursts=' + $t.bursts + ' burst=' + $t.burst_ms + 'ms gap=' + $t.silence_ms + 'ms') -ForegroundColor Yellow
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