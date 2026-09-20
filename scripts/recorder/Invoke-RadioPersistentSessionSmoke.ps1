Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')
. (Join-Path $PSScriptRoot '..\mxf\Track-Identity.ps1')

$root = Get-ProjectRoot
$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$cfg = Read-IniFile (Join-Path $root 'config\recorder\radio-persistent.ini')
$recorderExe = Find-RecorderHostExe
if (-not $recorderExe) { throw 'recorder-host.exe missing. Build it before integrated acceptance.' }
$pluginDll = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path $pluginDll)) { throw 'gstmxfidentity.dll missing.' }
$mxfLab = @((Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),(Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $mxfLab) { throw 'mxf-lab.exe missing.' }

$recorderIp = [string]$profile['recorder']['ip']
$rtspPort = [int]$profile['recorder']['rtsp_port']
$rtpPort = [int]$profile['rtp']['port_start'] + 20
$cwpIp = [string]$profile['cwp-a']['ip_start']
$endpointId = [string]$cfg['session']['endpoint_id']
$serviceType = [string]$cfg['session']['service_type']
$serviceId = [string]$cfg['session']['service_id']
$direction = [string]$cfg['session']['direction']
$activitySignal = [string]$cfg['session']['activity_signal']
$burstCount = [int]$cfg['session']['burst_count']
$burstMs = [int]$cfg['session']['burst_ms']
$silenceMs = [int]$cfg['session']['silence_ms']
$keepaliveIntervalMs = [int]$cfg['session']['keepalive_interval_ms']
$pausedProbePackets = [int]$cfg['session']['paused_probe_packets']
$maxSeconds = [int]$cfg['session']['max_recorder_seconds']
$segmentSequence = [int]$cfg['session']['segment_sequence']

$id = New-LogicalTrackIdentity -ServiceType $serviceType -ServiceId $serviceId -EndpointId $endpointId -Direction $direction `
    -SdpServiceNameRaw ([string]$cfg['session']['sdp_service_name']) `
    -SdpLabelRaw ([string]$cfg['session']['sdp_label']) `
    -SdpMidRaw ([string]$cfg['session']['sdp_mid'])

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ("runs\phase4-radio-persistent\$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$partial = Join-Path $runDir 'radio-121500-cwp-a17-rx.mxf.partial'
$final = Join-Path $runDir 'radio-121500-cwp-a17-rx.mxf'
$lock = $final + '.lock'
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$hostStdout = Join-Path $runDir 'recorder-stdout.txt'
$hostStderr = Join-Path $runDir 'recorder-stderr.txt'
$cwpStdout = Join-Path $runDir 'cwp-stdout.txt'
$cwpStderr = Join-Path $runDir 'cwp-stderr.txt'
$fileId = ('P4-{0}' -f ([Guid]::NewGuid().ToString()))
$windowStartUtc = ([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH:00:00.000Z')

$hostArgs = @(
    '--bind-ip',$recorderIp,'--rtsp-port',[string]$rtspPort,'--rtp-port',[string]$rtpPort,
    '--output',$partial,'--final',$final,'--lock',$lock,'--audit',$audit,'--ready-file',$ready,
    '--plugin-dll',$pluginDll,'--track-name',[string]$id.display_name,'--logical-uuid',[string]$id.logical_track_uuid,
    '--instance-uuid',[string]$id.track_instance_uuid,'--file-id',$fileId,'--recorder-id','RECORDER-POC-01',
    '--window-start-utc',$windowStartUtc,'--segment-sequence',[string]$segmentSequence,'--max-seconds',[string]$maxSeconds,
    '--session-kind','radio','--service-id',$serviceId,'--endpoint-id',$endpointId,'--direction',$direction,'--activity-signal',$activitySignal
)

Write-Host '=== Phase 4: Radio Persistent RTSP Session ==='
Write-Host "Recorder: $recorderIp`:$rtspPort / RTP $rtpPort"
Write-Host "Radio: $serviceId endpoint=$endpointId bursts=$burstCount"
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
        '-LocalRtpPort',[string]($rtpPort+1000),'-EndpointId',$endpointId,'-ServiceId',$serviceId,
        '-BurstCount',[string]$burstCount,'-BurstMs',[string]$burstMs,'-SilenceMs',[string]$silenceMs,
        '-KeepaliveIntervalMs',[string]$keepaliveIntervalMs,'-PausedProbePackets',[string]$pausedProbePackets)
    $cwp = Invoke-NativeProcessCapture -FilePath $psExe -Arguments $simArgs -WorkingDirectory $root -TimeoutMs 30000
    [IO.File]::WriteAllText($cwpStdout,[string]$cwp.StdOut,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($cwpStderr,[string]$cwp.StdErr,(New-Object Text.UTF8Encoding($false)))
    if ($cwp.ExitCode -ne 0) { throw "Radio simulator failed exit=$($cwp.ExitCode): $($cwp.StdErr)" }

    $hostResult = Complete-NativeProcessRedirected -Handle $recorderProcess -TimeoutMs 20000
    if ($hostResult.ExitCode -ne 0) { throw "recorder-host failed exit=$($hostResult.ExitCode): $($hostResult.StdErr)" }
    if (-not (Test-Path $final) -or (Test-Path $partial) -or (Test-Path $lock)) { throw 'Final file lifecycle invariant failed.' }

    $events = @(Get-Content -LiteralPath $audit | Where-Object {$_.Trim()} | ForEach-Object { $_ | ConvertFrom-Json })
    function Count-Event([string]$Name) { return @($events | Where-Object { [string]$_.event -eq $Name }).Count }

    $summary = [regex]::Match([string]$hostResult.StdOut,'RECORDER SUMMARY packets_received=(\d+) packets_recorded=(\d+) payload_bytes=(\d+) sequence_gap_packets=(\d+)[^\r\n]*?mux_bytes=(\d+) final=([A-Z_]+) record_commands=(\d+) pause_commands=(\d+) keepalives=(\d+) media_intervals_started=(\d+) media_intervals_closed=(\d+) packets_ignored_not_recording=(\d+) teardown=(\d+)')
    if (-not $summary.Success) { throw 'Recorder summary did not contain Phase 4 counters.' }
    $recordedPackets = [int64]$summary.Groups[2].Value
    $finalState = $summary.Groups[6].Value
    $recordCommands = [int]$summary.Groups[7].Value
    $pauseCommands = [int]$summary.Groups[8].Value
    $keepalives = [int]$summary.Groups[9].Value
    $intervalsStarted = [int]$summary.Groups[10].Value
    $intervalsClosed = [int]$summary.Groups[11].Value
    $ignoredPackets = [int64]$summary.Groups[12].Value
    $teardown = [int]$summary.Groups[13].Value

    $expectedActivePackets = $burstCount * [int]($burstMs/20)
    $expectedIgnoredPackets = $burstCount * $pausedProbePackets
    $expectedKeepalives = $burstCount * [int][Math]::Ceiling($silenceMs / [double]$keepaliveIntervalMs)

    $eventChecks = [ordered]@{
        session_open = ((Count-Event 'SESSION_OPEN') -eq 1)
        setup = ((Count-Event 'SETUP') -eq 1)
        service_enabled = ((Count-Event 'SERVICE_ENABLED') -eq 1)
        record = ((Count-Event 'RECORD') -eq $burstCount)
        pause = ((Count-Event 'PAUSE') -eq $burstCount)
        media_start = ((Count-Event 'MEDIA_START') -eq $burstCount)
        media_end = ((Count-Event 'MEDIA_END') -eq $burstCount)
        squ_on = if($activitySignal -ieq 'squ'){((Count-Event 'SQU_ON') -eq $burstCount)}else{$true}
        squ_off = if($activitySignal -ieq 'squ'){((Count-Event 'SQU_OFF') -eq $burstCount)}else{$true}
        keepalive_aggregated = ((Count-Event 'KEEPALIVE_OK') -eq 1)
        service_disabled = ((Count-Event 'SERVICE_DISABLED') -eq 1)
        teardown = ((Count-Event 'TEARDOWN') -eq 1)
        session_close = ((Count-Event 'SESSION_CLOSE') -eq 1)
    }

    $allEventsOk = @($eventChecks.Values | Where-Object { -not $_ }).Count -eq 0
    $result = if($allEventsOk -and $recordedPackets -eq $expectedActivePackets -and $ignoredPackets -eq $expectedIgnoredPackets -and
        $recordCommands -eq $burstCount -and $pauseCommands -eq $burstCount -and $keepalives -eq $expectedKeepalives -and
        $intervalsStarted -eq $burstCount -and $intervalsClosed -eq $burstCount -and $teardown -eq 1 -and $finalState -eq 'CLOSED_COMPLETE'){'PASS'}else{'FAIL'}

    $report = [ordered]@{
        schema='recorder-poc.phase4.radio-persistent-session.v1'; result=$result
        logical_track_uuid=$id.logical_track_uuid; track_instance_uuid=$id.track_instance_uuid
        single_rtsp_session_expected=$true; single_output_mxf=$final
        burst_count=$burstCount; expected_active_packets=$expectedActivePackets; recorded_packets=$recordedPackets
        expected_paused_probe_packets=$expectedIgnoredPackets; ignored_not_recording_packets=$ignoredPackets
        expected_keepalives=$expectedKeepalives; keepalives=$keepalives
        record_commands=$recordCommands; pause_commands=$pauseCommands
        media_intervals_started=$intervalsStarted; media_intervals_closed=$intervalsClosed
        final_state=$finalState; teardown_received=([bool]$teardown); event_checks=$eventChecks
        contract='frequency enabled => session/file stay open; activity RECORD<->PAUSE; disable => TEARDOWN/finalize'
    }
    $reportPath = Join-Path $runDir 'phase4-radio-persistent-report.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

    Write-Host "Bursts: $recordCommands / $burstCount; PAUSE: $pauseCommands / $burstCount"
    Write-Host "Media intervals: $intervalsStarted started / $intervalsClosed closed"
    Write-Host "RTP recorded: $recordedPackets / $expectedActivePackets; ignored while paused: $ignoredPackets / $expectedIgnoredPackets"
    Write-Host "Keepalives: $keepalives / $expectedKeepalives (one aggregated KEEPALIVE_OK audit event)"
    Write-Host "Report: $reportPath"
    if($result -eq 'PASS'){ Write-Host 'PHASE 4 RADIO PERSISTENT SESSION: PASS' -ForegroundColor Green; exit 0 }
    Write-Error 'PHASE 4 RADIO PERSISTENT SESSION: FAIL'; exit 9
} catch {
    try { if (-not $recorderProcess.Process.HasExited) { $recorderProcess.Process.Kill(); $recorderProcess.Process.WaitForExit() } } catch {}
    throw
}
