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
$cfg = Read-IniFile (Join-Path $root 'config\recorder\media-engine.ini')
$recorderExe = Find-RecorderHostExe
if (-not $recorderExe) { throw 'recorder-host.exe missing. Build it before integrated acceptance.' }
$pluginDll = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path $pluginDll)) { throw 'gstmxfidentity.dll missing.' }

$recorderIp = [string]$profile['recorder']['ip']
$rtspPort = [int]$profile['recorder']['rtsp_port']
$rtpPort = [int]$profile['rtp']['port_start'] + 30
$cwpIp = [string]$profile['cwp-a']['ip_start']
$endpointId = [string]$cfg['session']['endpoint_id']
$serviceType = [string]$cfg['session']['service_type']
$serviceId = [string]$cfg['session']['service_id']
$direction = [string]$cfg['session']['direction']
$activitySignal = [string]$cfg['session']['activity_signal']
$maxSeconds = [int]$cfg['session']['max_recorder_seconds']
$segmentSequence = [int]$cfg['session']['segment_sequence']

$id = New-LogicalTrackIdentity -ServiceType $serviceType -ServiceId $serviceId -EndpointId $endpointId -Direction $direction `
    -SdpServiceNameRaw ([string]$cfg['session']['sdp_service_name']) `
    -SdpLabelRaw ([string]$cfg['session']['sdp_label']) `
    -SdpMidRaw ([string]$cfg['session']['sdp_mid'])

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ("runs\phase6-media-engine\$stamp")
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
$fileId = ('P6-{0}' -f ([Guid]::NewGuid().ToString()))
$windowStartUtc = ([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH:00:00.000Z')

$hostArgs = @(
    '--bind-ip',$recorderIp,'--rtsp-port',[string]$rtspPort,'--rtp-port',[string]$rtpPort,
    '--output',$partial,'--final',$final,'--lock',$lock,'--audit',$audit,'--ready-file',$ready,
    '--plugin-dll',$pluginDll,'--track-name',[string]$id.display_name,'--logical-uuid',[string]$id.logical_track_uuid,
    '--instance-uuid',[string]$id.track_instance_uuid,'--file-id',$fileId,'--recorder-id','RECORDER-POC-01',
    '--window-start-utc',$windowStartUtc,'--segment-sequence',[string]$segmentSequence,'--max-seconds',[string]$maxSeconds,
    '--session-kind','radio','--service-id',$serviceId,'--endpoint-id',$endpointId,'--direction',$direction,'--activity-signal',$activitySignal
)

Write-Host '=== Phase 6: Media Engine RTP Impairment Smoke ==='
Write-Host "Recorder: $recorderIp`:$rtspPort / RTP $rtpPort"
$recorderProcess = Start-NativeProcessRedirected -FilePath $recorderExe -Arguments $hostArgs -StdOutPath $hostStdout -StdErrPath $hostStderr -WorkingDirectory $root
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path $ready)) {
        if ($recorderProcess.Process.HasExited) { throw "recorder-host exited before READY code=$($recorderProcess.Process.ExitCode)" }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Timed out waiting for recorder READY.' }
        Start-Sleep -Milliseconds 50
    }

    $sim = Join-Path $root 'scripts\cwp\Invoke-MediaEngineImpairmentSimulator.ps1'
    $psExe = (Get-Command powershell.exe).Source
    $simArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$sim,
        '-LocalIp',$cwpIp,'-RecorderIp',$recorderIp,'-RtspPort',[string]$rtspPort,'-RecorderRtpPort',[string]$rtpPort,
        '-LocalRtpPort',[string]($rtpPort+1000),'-EndpointId',$endpointId,'-ServiceId',$serviceId,'-Direction',$direction)
    $cwp = Invoke-NativeProcessCapture -FilePath $psExe -Arguments $simArgs -WorkingDirectory $root -TimeoutMs 30000
    [IO.File]::WriteAllText($cwpStdout,[string]$cwp.StdOut,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($cwpStderr,[string]$cwp.StdErr,(New-Object Text.UTF8Encoding($false)))
    if ($cwp.ExitCode -ne 0) { throw "Media engine simulator failed exit=$($cwp.ExitCode): $($cwp.StdErr)" }

    $hostResult = Complete-NativeProcessRedirected -Handle $recorderProcess -TimeoutMs 20000
    if ($hostResult.ExitCode -ne 0) { throw "recorder-host failed exit=$($hostResult.ExitCode): $($hostResult.StdErr)" }
    if (-not (Test-Path $final) -or (Test-Path $partial) -or (Test-Path $lock)) { throw 'Final file lifecycle invariant failed.' }

    $summaryLine = ([string]$hostResult.StdOut -split "`r?`n" | Where-Object { $_ -match '^RECORDER SUMMARY ' } | Select-Object -Last 1)
    if (-not $summaryLine) { throw 'RECORDER SUMMARY not found.' }
    $summary = Parse-SummaryFields $summaryLine

    $expected = [ordered]@{
        packets_recorded = [int64]$cfg['media_engine']['expected_recorded_packets']
        sequence_gap_packets = [int64]$cfg['media_engine']['expected_sequence_gap_packets']
        duplicates = [int64]$cfg['media_engine']['expected_duplicates']
        out_of_order = [int64]$cfg['media_engine']['expected_out_of_order']
        malformed = [int64]$cfg['media_engine']['expected_malformed']
        wrong_pt = [int64]$cfg['media_engine']['expected_wrong_pt']
        timestamp_discontinuities = [int64]$cfg['media_engine']['expected_timestamp_discontinuities']
    }
    $actual = [ordered]@{}
    foreach ($k in $expected.Keys) { $actual[$k] = [int64](Require-Field $summary $k) }
    $actual['final'] = Require-Field $summary 'final'
    $actual['teardown'] = [int64](Require-Field $summary 'teardown')

    $events = @(Get-Content -LiteralPath $audit | Where-Object {$_.Trim()} | ForEach-Object { $_ | ConvertFrom-Json })
    function Count-Event([string]$Name) { return @($events | Where-Object { [string]$_.event -eq $Name }).Count }
    $eventChecks = [ordered]@{
        duplicate_event = ((Count-Event 'RTP_DUPLICATE_DROPPED') -ge 1)
        out_of_order_event = ((Count-Event 'RTP_OUT_OF_ORDER_DROPPED') -ge 1)
        gap_event = ((Count-Event 'GAP_START') -ge 1)
        timestamp_event = ((Count-Event 'RTP_TIMESTAMP_DISCONTINUITY') -ge 1)
        wrong_payload_event = ((Count-Event 'RTP_UNSUPPORTED_PAYLOAD_DROPPED') -ge 1)
        malformed_event = ((Count-Event 'RTP_MALFORMED_DROPPED') -ge 1)
    }
    $metricsOk = $true
    foreach ($k in $expected.Keys) { if ($actual[$k] -ne $expected[$k]) { $metricsOk = $false } }
    $eventsOk = @($eventChecks.Values | Where-Object { -not $_ }).Count -eq 0
    $result = if($metricsOk -and $eventsOk -and $actual['final'] -eq 'CLOSED_COMPLETE' -and $actual['teardown'] -eq 1){'PASS'}else{'FAIL'}

    $report = [ordered]@{
        schema='recorder-poc.phase6.media-engine.v1'
        result=$result
        logical_track_uuid=$id.logical_track_uuid
        track_instance_uuid=$id.track_instance_uuid
        expected=$expected
        actual=$actual
        event_checks=$eventChecks
        summary_line=$summaryLine
        final_file=$final
        audit=$audit
        contract='RTP impairments are classified and either safely recorded or safely dropped; MXF contains only accepted PCMA payloads.'
    }
    $reportPath = Join-Path $runDir 'phase6-media-engine-report.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

    Write-Host "Recorded packets: $($actual['packets_recorded']) / $($expected['packets_recorded'])"
    Write-Host "Gaps: $($actual['sequence_gap_packets']); dup=$($actual['duplicates']); out_of_order=$($actual['out_of_order']); malformed=$($actual['malformed']); wrong_pt=$($actual['wrong_pt']); tsdisc=$($actual['timestamp_discontinuities'])"
    Write-Host "Report: $reportPath"
    if($result -eq 'PASS'){ Write-Host 'PHASE 6 MEDIA ENGINE: PASS' -ForegroundColor Green; exit 0 }
    Write-Error 'PHASE 6 MEDIA ENGINE: FAIL'; exit 9
} catch {
    try { if (-not $recorderProcess.Process.HasExited) { $recorderProcess.Process.Kill(); $recorderProcess.Process.WaitForExit() } } catch {}
    throw
}
