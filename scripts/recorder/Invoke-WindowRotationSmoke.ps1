Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')
. (Join-Path $PSScriptRoot '..\mxf\Track-Identity.ps1')

function Parse-SummaryFields([string]$Line) {
    $result = @{}
    foreach ($m in [regex]::Matches($Line,'(?<k>[A-Za-z0-9_]+)=(?<v>[^\s]+)')) { $result[$m.Groups['k'].Value] = $m.Groups['v'].Value }
    return $result
}
function Require-Field([hashtable]$Map,[string]$Key) { if (-not $Map.ContainsKey($Key)) { throw "Missing summary field: $Key" }; return $Map[$Key] }

$root = Get-ProjectRoot
$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$cfg = Read-IniFile (Join-Path $root 'config\recorder\window-rotation.ini')
$recorderExe = Find-RecorderHostExe
if (-not $recorderExe) { throw 'recorder-host.exe missing. Build it before integrated acceptance.' }
$pluginDll = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path $pluginDll)) { throw 'gstmxfidentity.dll missing.' }

$recorderIp = [string]$profile['recorder']['ip']
$rtspPort = [int]$profile['recorder']['rtsp_port']
$rtpPort = [int]$profile['rtp']['port_start'] + 40
$cwpIp = [string]$profile['cwp-a']['ip_start']
$endpointId = [string]$cfg['session']['endpoint_id']
$serviceType = [string]$cfg['session']['service_type']
$serviceId = [string]$cfg['session']['service_id']
$direction = [string]$cfg['session']['direction']
$activitySignal = [string]$cfg['session']['activity_signal']
$maxSeconds = [int]$cfg['session']['max_recorder_seconds']
$segmentSequence = [int]$cfg['session']['segment_sequence']
$rotateAfterPause = [int]$cfg['rotation']['rotate_after_pause_count']
$rotateMax = [int]$cfg['rotation']['rotate_max_count']

$id = New-LogicalTrackIdentity -ServiceType $serviceType -ServiceId $serviceId -EndpointId $endpointId -Direction $direction `
    -SdpServiceNameRaw ([string]$cfg['session']['sdp_service_name']) `
    -SdpLabelRaw ([string]$cfg['session']['sdp_label']) `
    -SdpMidRaw ([string]$cfg['session']['sdp_mid'])

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ("runs\phase7-window-rotation\$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$baseFinal = Join-Path $runDir 'radio-121500-cwp-a17-rx.mxf'
$basePartial = $baseFinal + '.partial'
$baseLock = $baseFinal + '.lock'
$expectedSeg0 = Join-Path $runDir 'radio-121500-cwp-a17-rx.seg000.mxf'
$expectedSeg1 = Join-Path $runDir 'radio-121500-cwp-a17-rx.seg001.mxf'
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$hostStdout = Join-Path $runDir 'recorder-stdout.txt'
$hostStderr = Join-Path $runDir 'recorder-stderr.txt'
$cwpStdout = Join-Path $runDir 'cwp-stdout.txt'
$cwpStderr = Join-Path $runDir 'cwp-stderr.txt'
$fileId = ('P7-{0}' -f ([Guid]::NewGuid().ToString()))
$windowStartUtc = ([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH:00:00.000Z')

$hostArgs = @(
    '--bind-ip',$recorderIp,'--rtsp-port',[string]$rtspPort,'--rtp-port',[string]$rtpPort,
    '--output',$basePartial,'--final',$baseFinal,'--lock',$baseLock,'--audit',$audit,'--ready-file',$ready,
    '--plugin-dll',$pluginDll,'--track-name',[string]$id.display_name,'--logical-uuid',[string]$id.logical_track_uuid,
    '--instance-uuid',[string]$id.track_instance_uuid,'--file-id',$fileId,'--recorder-id','RECORDER-POC-01',
    '--window-start-utc',$windowStartUtc,'--segment-sequence',[string]$segmentSequence,'--max-seconds',[string]$maxSeconds,
    '--session-kind','radio','--service-id',$serviceId,'--endpoint-id',$endpointId,'--direction',$direction,'--activity-signal',$activitySignal,
    '--rotate-window-after-pauses',[string]$rotateAfterPause,'--rotate-window-max-count',[string]$rotateMax
)

Write-Host '=== Phase 7: Window Rotation Smoke ==='
Write-Host "Recorder: $recorderIp`:$rtspPort / RTP $rtpPort"
Write-Host "Rotate after PAUSE count: $rotateAfterPause; max rotations: $rotateMax"
$recorderProcess = Start-NativeProcessRedirected -FilePath $recorderExe -Arguments $hostArgs -StdOutPath $hostStdout -StdErrPath $hostStderr -WorkingDirectory $root
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path $ready)) {
        if ($recorderProcess.Process.HasExited) { throw "recorder-host exited before READY code=$($recorderProcess.Process.ExitCode)" }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Timed out waiting for recorder READY.' }
        Start-Sleep -Milliseconds 50
    }

    $sim = Join-Path $root 'scripts\cwp\Invoke-RadioPersistentSessionSimulator.ps1'
    $psExe = (Get-Command powershell.exe).Source
    $simArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$sim,
        '-LocalIp',$cwpIp,'-RecorderIp',$recorderIp,'-RtspPort',[string]$rtspPort,'-RecorderRtpPort',[string]$rtpPort,
        '-LocalRtpPort',[string]($rtpPort+1000),'-EndpointId',$endpointId,'-ServiceId',$serviceId,'-Direction',$direction,
        '-BurstCount',[string]([int]$cfg['session']['burst_count']),'-BurstMs',[string]([int]$cfg['session']['burst_ms']),
        '-SilenceMs',[string]([int]$cfg['session']['silence_ms']),'-KeepaliveIntervalMs',[string]([int]$cfg['session']['keepalive_interval_ms']),
        '-PausedProbePackets',[string]([int]$cfg['session']['paused_probe_packets']))
    $cwp = Invoke-NativeProcessCapture -FilePath $psExe -Arguments $simArgs -WorkingDirectory $root -TimeoutMs 40000
    [IO.File]::WriteAllText($cwpStdout,[string]$cwp.StdOut,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($cwpStderr,[string]$cwp.StdErr,(New-Object Text.UTF8Encoding($false)))
    if ($cwp.ExitCode -ne 0) { throw "Window rotation simulator failed exit=$($cwp.ExitCode): $($cwp.StdErr)" }

    $hostResult = Complete-NativeProcessRedirected -Handle $recorderProcess -TimeoutMs 30000
    if ($hostResult.ExitCode -ne 0) { throw "recorder-host failed exit=$($hostResult.ExitCode): $($hostResult.StdErr)" }

    $summaryLine = ([string]$hostResult.StdOut -split "`r?`n" | Where-Object { $_ -match '^RECORDER SUMMARY ' } | Select-Object -Last 1)
    if (-not $summaryLine) { throw 'RECORDER SUMMARY not found.' }
    $summary = Parse-SummaryFields $summaryLine
    $events = @(Get-Content -LiteralPath $audit | Where-Object {$_.Trim()} | ForEach-Object { $_ | ConvertFrom-Json })
    function Count-Event([string]$Name) { return @($events | Where-Object { [string]$_.event -eq $Name }).Count }

    $actual = [ordered]@{
        final = Require-Field $summary 'final'
        teardown = [int64](Require-Field $summary 'teardown')
        record_commands = [int64](Require-Field $summary 'record_commands')
        pause_commands = [int64](Require-Field $summary 'pause_commands')
        media_intervals_started = [int64](Require-Field $summary 'media_intervals_started')
        media_intervals_closed = [int64](Require-Field $summary 'media_intervals_closed')
        window_open_count = [int64](Require-Field $summary 'window_open_count')
        windows_closed_complete = [int64](Require-Field $summary 'windows_closed_complete')
        rotations_completed = [int64](Require-Field $summary 'rotations_completed')
        segment_sequence = [int64](Require-Field $summary 'segment_sequence')
    }
    $fileChecks = [ordered]@{
        segment0_exists = (Test-Path -LiteralPath $expectedSeg0)
        segment1_exists = (Test-Path -LiteralPath $expectedSeg1)
        segment0_partial_absent = -not (Test-Path -LiteralPath ($expectedSeg0 + '.partial'))
        segment1_partial_absent = -not (Test-Path -LiteralPath ($expectedSeg1 + '.partial'))
        segment0_lock_absent = -not (Test-Path -LiteralPath ($expectedSeg0 + '.lock'))
        segment1_lock_absent = -not (Test-Path -LiteralPath ($expectedSeg1 + '.lock'))
    }
    $eventChecks = [ordered]@{
        window_rotation_requested = ((Count-Event 'WINDOW_ROTATION_REQUESTED') -eq 1)
        window_rotated = ((Count-Event 'WINDOW_ROTATED') -eq 1)
        window_opened = ((Count-Event 'WINDOW_OPENED') -eq 1)
        window_closed_complete = ((Count-Event 'WINDOW_CLOSED_COMPLETE') -eq 2)
        session_open = ((Count-Event 'SESSION_OPEN') -eq 1)
        session_close = ((Count-Event 'SESSION_CLOSE') -eq 1)
    }
    $expected = [ordered]@{
        final='CLOSED_COMPLETE'; teardown=1; record_commands=4; pause_commands=4; media_intervals_started=4; media_intervals_closed=4
        window_open_count=[int64]$cfg['rotation']['expected_window_open_count']
        windows_closed_complete=[int64]$cfg['rotation']['expected_windows_closed_complete']
        rotations_completed=[int64]$cfg['rotation']['expected_rotations_completed']
        segment_sequence=[int64]$cfg['rotation']['expected_final_segment_sequence']
    }
    $metricsOk = $true
    foreach ($k in $expected.Keys) { if ([string]$actual[$k] -ne [string]$expected[$k]) { $metricsOk = $false } }
    $filesOk = @($fileChecks.Values | Where-Object { -not $_ }).Count -eq 0
    $eventsOk = @($eventChecks.Values | Where-Object { -not $_ }).Count -eq 0
    $result = if($metricsOk -and $filesOk -and $eventsOk){'PASS'}else{'FAIL'}

    $report = [ordered]@{
        schema='recorder-poc.phase7.window-rotation.v1'
        result=$result
        logical_track_uuid=$id.logical_track_uuid
        initial_track_instance_uuid=$id.track_instance_uuid
        expected=$expected
        actual=$actual
        file_checks=$fileChecks
        event_checks=$eventChecks
        summary_line=$summaryLine
        segment0=$expectedSeg0
        segment1=$expectedSeg1
        audit=$audit
        contract='A persistent RTSP session rotates physical MXF windows at a PAUSE boundary while preserving LogicalTrackUUID and renewing TrackInstanceUUID.'
    }
    $reportPath = Join-Path $runDir 'phase7-window-rotation-report.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

    Write-Host "Windows: opened=$($actual.window_open_count), closed=$($actual.windows_closed_complete), rotations=$($actual.rotations_completed), segment=$($actual.segment_sequence)"
    Write-Host "Files: seg0=$($fileChecks.segment0_exists), seg1=$($fileChecks.segment1_exists)"
    Write-Host "Report: $reportPath"
    if($result -eq 'PASS'){ Write-Host 'PHASE 7 WINDOW ROTATION: PASS' -ForegroundColor Green; exit 0 }
    Write-Error 'PHASE 7 WINDOW ROTATION: FAIL'; exit 9
} catch {
    try { if (-not $recorderProcess.Process.HasExited) { $recorderProcess.Process.Kill(); $recorderProcess.Process.WaitForExit() } } catch {}
    throw
}
