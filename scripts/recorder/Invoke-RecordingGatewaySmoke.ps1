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
function New-TelephoneLegIdentity([string]$ServiceType,[string]$ServiceId,[string]$EndpointId,[string]$Direction,[string]$CallLegId,[string]$SdpServiceNameRaw,[string]$SdpLabelRaw,[string]$SdpMidRaw) {
    $canonical = ('identity-v1|service_type={0}|service_id={1}|endpoint_id={2}|direction={3}|call_leg_id={4}' -f `
        $ServiceType.Trim().ToLowerInvariant(),$ServiceId.Trim().ToLowerInvariant(),$EndpointId.Trim().ToLowerInvariant(),$Direction.Trim().ToLowerInvariant(),$CallLegId.Trim().ToLowerInvariant())
    $logical = New-UuidV5 -Namespace $script:RecorderLogicalTrackNamespace -Name $canonical
    $instance = New-UuidV7
    $human = ('{0} {1} | {2} | {3} | {4}' -f $ServiceType.ToUpperInvariant(),$ServiceId,$EndpointId,$Direction,$CallLegId)
    return [ordered]@{
        canonical_identity=$canonical
        logical_track_uuid=$logical.ToString()
        track_instance_uuid=$instance.ToString()
        display_name=$human
        track_name=('{0} | LT={1}' -f $human,$logical.ToString())
        sdp_service_name_raw=$SdpServiceNameRaw
        sdp_label_raw=$SdpLabelRaw
        sdp_mid_raw=$SdpMidRaw
    }
}

$root = Get-ProjectRoot
$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$cfg = Read-IniFile (Join-Path $root 'config\recorder\sip-gateway-ingress.ini')
$recorderExe = Find-RecorderHostExe
if (-not $recorderExe) { throw 'recorder-host.exe missing. Build it before integrated acceptance.' }
$pluginDll = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path $pluginDll)) { throw 'gstmxfidentity.dll missing.' }
$mxfLab = @((Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),(Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $mxfLab) { throw 'mxf-lab.exe missing; Phase 2 native build must already exist.' }

$recorderIp = [string]$profile['recorder']['ip']
$rtspPort = [int]$profile['recorder']['rtsp_port']
$rtpPort = [int]$profile['rtp']['port_start'] + 80
$gatewayIp = [string]$profile['cwp-a']['ip_start']
$endpointId = [string]$cfg['session']['endpoint_id']
$serviceType = [string]$cfg['session']['service_type']
$serviceId = [string]$cfg['session']['service_id']
$direction = [string]$cfg['session']['direction']
$callLegId = [string]$cfg['session']['call_leg_id']
$maxSeconds = [int]$cfg['session']['max_recorder_seconds']
$segmentSequence = [int]$cfg['session']['segment_sequence']
$ringingMs = [int]$cfg['gateway']['ringing_ms']
$answeredMediaMs = [int]$cfg['gateway']['answered_media_ms']
$sipCallIdRaw = [string]$cfg['gateway']['sip_call_id_raw']
$sipFromRaw = [string]$cfg['gateway']['sip_from_raw']
$sipToRaw = [string]$cfg['gateway']['sip_to_raw']

$id = New-TelephoneLegIdentity -ServiceType $serviceType -ServiceId $serviceId -EndpointId $endpointId -Direction $direction -CallLegId $callLegId `
    -SdpServiceNameRaw ([string]$cfg['session']['sdp_service_name']) -SdpLabelRaw ([string]$cfg['session']['sdp_label']) -SdpMidRaw ([string]$cfg['session']['sdp_mid'])

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ("runs\phase8-recording-gateway\$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$partial = Join-Path $runDir 'telephone-tel-01-cwp-a17-rx.mxf.partial'
$final = Join-Path $runDir 'telephone-tel-01-cwp-a17-rx.mxf'
$lock = $final + '.lock'
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$gatewayAudit = Join-Path $runDir 'gateway-audit.jsonl'
$correlation = Join-Path $runDir 'gateway-correlation.json'
$hostStdout = Join-Path $runDir 'recorder-stdout.txt'
$hostStderr = Join-Path $runDir 'recorder-stderr.txt'
$gwStdout = Join-Path $runDir 'gateway-stdout.txt'
$gwStderr = Join-Path $runDir 'gateway-stderr.txt'
$fileId = ('P8-{0}' -f ([Guid]::NewGuid().ToString()))
$windowStartUtc = ([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH:00:00.000Z')

Write-Host '=== Phase 8: Recording Gateway / SIP ingress Smoke ==='
Write-Host "Recorder: $recorderIp`:$rtspPort / RTP $rtpPort"
Write-Host "Gateway: $gatewayIp / RTP local $($rtpPort+1000)"
Write-Host "Canonical identity: $($id.canonical_identity)"

$hostArgs = @(
    '--bind-ip',$recorderIp,'--rtsp-port',[string]$rtspPort,'--rtp-port',[string]$rtpPort,
    '--output',$partial,'--final',$final,'--lock',$lock,'--audit',$audit,'--ready-file',$ready,
    '--plugin-dll',$pluginDll,'--track-name',[string]$id.display_name,'--logical-uuid',[string]$id.logical_track_uuid,
    '--instance-uuid',[string]$id.track_instance_uuid,'--file-id',$fileId,'--recorder-id','RECORDER-POC-01',
    '--window-start-utc',$windowStartUtc,'--segment-sequence',[string]$segmentSequence,'--max-seconds',[string]$maxSeconds,
    '--session-kind','telephone','--service-id',$serviceId,'--endpoint-id',$endpointId,'--direction',$direction,'--activity-signal','CALL'
)
$recorderProcess = Start-NativeProcessRedirected -FilePath $recorderExe -Arguments $hostArgs -StdOutPath $hostStdout -StdErrPath $hostStderr -WorkingDirectory $root
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path $ready)) {
        if ($recorderProcess.Process.HasExited) { throw "recorder-host exited before READY code=$($recorderProcess.Process.ExitCode)" }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Timed out waiting for recorder READY.' }
        Start-Sleep -Milliseconds 50
    }
    $gatewayScript = Join-Path $root 'scripts\gateway\Invoke-RecordingGatewaySipIngress.ps1'
    $psExe = (Get-Command powershell.exe).Source
    $gwArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$gatewayScript,
        '-LocalIp',$gatewayIp,'-RecorderIp',$recorderIp,'-RtspPort',[string]$rtspPort,'-RecorderRtpPort',[string]$rtpPort,'-LocalRtpPort',[string]($rtpPort+1000),
        '-EndpointId',$endpointId,'-ServiceId',$serviceId,'-Direction',$direction,'-CallLegId',$callLegId,
        '-SipCallIdRaw',$sipCallIdRaw,'-SipFromRaw',$sipFromRaw,'-SipToRaw',$sipToRaw,
        '-RingingMs',[string]$ringingMs,'-AnsweredMediaMs',[string]$answeredMediaMs,'-AuditPath',$gatewayAudit,'-CorrelationPath',$correlation)
    $gw = Invoke-NativeProcessCapture -FilePath $psExe -Arguments $gwArgs -WorkingDirectory $root -TimeoutMs 30000
    [IO.File]::WriteAllText($gwStdout,[string]$gw.StdOut,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($gwStderr,[string]$gw.StdErr,(New-Object Text.UTF8Encoding($false)))
    if ($gw.ExitCode -ne 0) { throw "Recording Gateway failed exit=$($gw.ExitCode): $($gw.StdErr)" }

    $hostResult = Complete-NativeProcessRedirected -Handle $recorderProcess -TimeoutMs 30000
    if ($hostResult.ExitCode -ne 0) { throw "recorder-host failed exit=$($hostResult.ExitCode): $($hostResult.StdErr)" }
    if (-not (Test-Path $final)) { throw 'Final MXF was not produced.' }
    if (Test-Path $partial) { throw '.mxf.partial still exists after graceful close.' }
    if (Test-Path $lock) { throw '.mxf.lock still exists after graceful close.' }

    $summaryLine = ([string]$hostResult.StdOut -split "`r?`n" | Where-Object { $_ -match '^RECORDER SUMMARY ' } | Select-Object -Last 1)
    if (-not $summaryLine) { throw 'RECORDER SUMMARY not found.' }
    $summary = Parse-SummaryFields $summaryLine
    $expectedPackets = [int]($answeredMediaMs / 20)
    $recordedPackets = [int64](Require-Field $summary 'packets_recorded')
    $payloadBytes = [int64](Require-Field $summary 'payload_bytes')
    $finalState = Require-Field $summary 'final'

    $gatewayEvents = @(Get-Content -LiteralPath $gatewayAudit | Where-Object {$_.Trim()} | ForEach-Object { $_ | ConvertFrom-Json })
    $gatewayRequired = @('SIP_INVITE_RECEIVED','SIP_RINGING','SIP_ANSWERED','GATEWAY_RECORDING_SESSION_OPENING','GATEWAY_RECORDING_SESSION_READY','GATEWAY_RTP_FORWARD_STARTED','GATEWAY_RTP_FORWARD_STOPPED','SIP_BYE_RECEIVED','GATEWAY_RECORDING_SESSION_CLOSING','GATEWAY_RECORDING_SESSION_CLOSED','GATEWAY_CALL_CLOSED')
    $gatewayMissing = @($gatewayRequired | Where-Object { $_ -notin @($gatewayEvents | ForEach-Object { [string]$_.event }) })
    $corr = Get-Content -LiteralPath $correlation -Raw | ConvertFrom-Json
    $correlationOk = ([string]$corr.call_leg_id -eq $callLegId -and [string]$corr.sip_call_id_raw -eq $sipCallIdRaw -and [int]$corr.packets -eq $expectedPackets)
    $result = if($finalState -eq 'CLOSED_COMPLETE' -and $recordedPackets -eq $expectedPackets -and $payloadBytes -eq ($expectedPackets*160) -and $gatewayMissing.Count -eq 0 -and $correlationOk){'PASS'}else{'FAIL'}
    $report = [ordered]@{
        schema='recorder-poc.phase8.recording-gateway-smoke.v1'
        result=$result
        contract='SIP-like gateway lifecycle opens one RTSP recording session and forwards PCMA RTP without introducing SIP semantics inside RecorderHost.'
        canonical_identity=$id.canonical_identity
        logical_track_uuid=$id.logical_track_uuid
        track_instance_uuid=$id.track_instance_uuid
        final_state=$finalState
        expected_packets=$expectedPackets
        recorded_packets=$recordedPackets
        recorded_payload_bytes=$payloadBytes
        gateway_missing_events=$gatewayMissing
        correlation_ok=$correlationOk
        gateway_audit=$gatewayAudit
        recorder_audit=$audit
        final_mxf=$final
    }
    $reportPath = Join-Path $runDir 'phase8-recording-gateway-report.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host "Gateway events missing: $($gatewayMissing.Count)"
    Write-Host "RTP recorded: $recordedPackets / $expectedPackets packets; payload=$payloadBytes bytes"
    Write-Host "Correlation OK: $correlationOk"
    Write-Host "Report: $reportPath"
    if($result -eq 'PASS'){ Write-Host 'PHASE 8 RECORDING GATEWAY: PASS' -ForegroundColor Green; exit 0 }
    Write-Error 'PHASE 8 RECORDING GATEWAY: FAIL'; exit 11
} catch {
    try { if (-not $recorderProcess.Process.HasExited) { $recorderProcess.Process.Kill(); $recorderProcess.Process.WaitForExit() } } catch {}
    throw
}
