Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')
. (Join-Path $PSScriptRoot '..\mxf\Track-Identity.ps1')

$root = Get-ProjectRoot
$profilePath = Join-Path $root 'config\profiles\local-poc.ini'
$sessionPath = Join-Path $root 'config\recorder\one-cwp.ini'
$profile = Read-IniFile $profilePath
$sessionCfg = Read-IniFile $sessionPath

$recorderExe = Find-RecorderHostExe
if (-not $recorderExe) { throw 'recorder-host.exe missing. Run scripts\recorder\01-build-recorder-host.cmd first.' }
$pluginDll = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path $pluginDll)) { throw 'gstmxfidentity.dll missing. Phase 2 identity plugin must already be built.' }
$mxfLab = @(
    (Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),
    (Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $mxfLab) { throw 'mxf-lab.exe missing; Phase 2 native build must already exist.' }

$recorderIp = [string]$profile['recorder']['ip']
$rtspPort = [int]$profile['recorder']['rtsp_port']
$rtpPort = [int]$profile['rtp']['port_start']
$cwpIp = [string]$profile['cwp-a']['ip_start']
$endpointId = [string]$sessionCfg['session']['endpoint_id']
$serviceType = [string]$sessionCfg['session']['service_type']
$serviceId = [string]$sessionCfg['session']['service_id']
$direction = [string]$sessionCfg['session']['direction']
$firstRecordMs = [int]$sessionCfg['session']['first_record_ms']
$pauseMs = [int]$sessionCfg['session']['pause_ms']
$secondRecordMs = [int]$sessionCfg['session']['second_record_ms']
$maxSeconds = [int]$sessionCfg['session']['max_recorder_seconds']
$segmentSequence = [int]$sessionCfg['session']['segment_sequence']

$id = New-LogicalTrackIdentity -ServiceType $serviceType -ServiceId $serviceId -EndpointId $endpointId -Direction $direction `
    -SdpServiceNameRaw ([string]$sessionCfg['session']['sdp_service_name']) `
    -SdpLabelRaw ([string]$sessionCfg['session']['sdp_label']) `
    -SdpMidRaw ([string]$sessionCfg['session']['sdp_mid'])

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ("runs\phase3-one-cwp\$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$partial = Join-Path $runDir 'cwp-a01-radio-121500-rx.mxf.partial'
$final = Join-Path $runDir 'cwp-a01-radio-121500-rx.mxf'
$lock = $final + '.lock'
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$hostStdout = Join-Path $runDir 'recorder-stdout.txt'
$hostStderr = Join-Path $runDir 'recorder-stderr.txt'
$cwpStdout = Join-Path $runDir 'cwp-stdout.txt'
$cwpStderr = Join-Path $runDir 'cwp-stderr.txt'
$fileId = ('P3-{0}' -f ([Guid]::NewGuid().ToString()))
$windowStartUtc = ([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH:00:00.000Z')

$gstRoot = $env:GSTREAMER_ROOT_X86_64
if (-not $gstRoot) { $gstBin = Find-GStreamerBin; if($gstBin){$gstRoot=Split-Path $gstBin -Parent} }
if (-not $gstRoot) { throw 'GStreamer not found.' }
$gstBin = Join-Path $gstRoot 'bin'
if (-not (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\') -ieq $gstBin.TrimEnd('\') })) { $env:PATH = $gstBin + ';' + $env:PATH }

Write-Host '=== Phase 3: Minimal Recorder + One CWP ==='
Write-Host "Recorder: $recorderIp`:$rtspPort / RTP $rtpPort"
Write-Host "CWP: $cwpIp"
Write-Host "LogicalTrackUUID: $($id.logical_track_uuid)"
Write-Host "TrackInstanceUUID: $($id.track_instance_uuid)"
Write-Host "Run: $runDir"

$hostArgs = @(
    '--bind-ip',$recorderIp,
    '--rtsp-port',[string]$rtspPort,
    '--rtp-port',[string]$rtpPort,
    '--output',$partial,
    '--final',$final,
    '--lock',$lock,
    '--audit',$audit,
    '--ready-file',$ready,
    '--plugin-dll',$pluginDll,
    '--track-name',[string]$id.display_name,
    '--logical-uuid',[string]$id.logical_track_uuid,
    '--instance-uuid',[string]$id.track_instance_uuid,
    '--file-id',$fileId,
    '--recorder-id','RECORDER-POC-01',
    '--window-start-utc',$windowStartUtc,
    '--segment-sequence',[string]$segmentSequence,
    '--max-seconds',[string]$maxSeconds
)
$recorderProcess = Start-NativeProcessRedirected -FilePath $recorderExe -Arguments $hostArgs -StdOutPath $hostStdout -StdErrPath $hostStderr -WorkingDirectory $root

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path $ready)) {
        if ($recorderProcess.Process.HasExited) { throw "recorder-host exited before READY with code $($recorderProcess.Process.ExitCode)" }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Timed out waiting for recorder READY.' }
        Start-Sleep -Milliseconds 50
    }

    $cwpScript = Join-Path $root 'scripts\cwp\Invoke-OneCwpSimulator.ps1'
    $cwpArgs = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$cwpScript,
        '-LocalIp',$cwpIp,
        '-RecorderIp',$recorderIp,
        '-RtspPort',[string]$rtspPort,
        '-RecorderRtpPort',[string]$rtpPort,
        '-LocalRtpPort',[string]($rtpPort + 1000),
        '-EndpointId',$endpointId,
        '-ServiceId',$serviceId,
        '-FirstRecordMs',[string]$firstRecordMs,
        '-PauseMs',[string]$pauseMs,
        '-SecondRecordMs',[string]$secondRecordMs
    )
    $psExe = (Get-Command powershell.exe).Source
    $cwp = Invoke-NativeProcessCapture -FilePath $psExe -Arguments $cwpArgs -WorkingDirectory $root -TimeoutMs 20000
    [IO.File]::WriteAllText($cwpStdout,[string]$cwp.StdOut,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($cwpStderr,[string]$cwp.StdErr,(New-Object Text.UTF8Encoding($false)))
    if ($cwp.ExitCode -ne 0) { throw "CWP simulator failed exit=$($cwp.ExitCode): $($cwp.StdErr)" }

    $hostResult = Complete-NativeProcessRedirected -Handle $recorderProcess -TimeoutMs 20000
    if ($hostResult.ExitCode -ne 0) { throw "recorder-host failed exit=$($hostResult.ExitCode): $($hostResult.StdErr)" }

    if (-not (Test-Path $final)) { throw 'Final MXF was not produced.' }
    if (Test-Path $partial) { throw '.mxf.partial still exists after graceful close.' }
    if (Test-Path $lock) { throw '.mxf.lock still exists after graceful close.' }

    $ffprobe = Find-Executable @('ffprobe.exe','ffprobe')
    if (-not $ffprobe) { throw 'ffprobe is required for Phase 3 smoke.' }
    $probeJson = & $ffprobe -v error -select_streams a -show_entries stream=index -of json $final
    if ($LASTEXITCODE -ne 0) { throw 'ffprobe could not open final MXF.' }
    $streamCount = @((($probeJson | Out-String | ConvertFrom-Json).streams)).Count

    # Readback with the stock demux only, preserving the Phase 2 isolation rule.
    $originalPluginPath = $env:GST_PLUGIN_PATH
    $originalPluginPath10 = $env:GST_PLUGIN_PATH_1_0
    $originalRegistry = $env:GST_REGISTRY_1_0
    try {
        $env:GST_PLUGIN_PATH = ''
        $env:GST_PLUGIN_PATH_1_0 = ''
        $env:GST_REGISTRY_1_0 = Join-Path $runDir 'registry-stock-reader.bin'
        $read = Invoke-NativeProcessCapture -FilePath $mxfLab -Arguments @('inspect-identity',$final,'--timeout-ms','15000') -TimeoutMs 20000
    } finally {
        $env:GST_PLUGIN_PATH = $originalPluginPath
        $env:GST_PLUGIN_PATH_1_0 = $originalPluginPath10
        $env:GST_REGISTRY_1_0 = $originalRegistry
    }
    [IO.File]::WriteAllText((Join-Path $runDir 'mxf-reader-stdout.txt'),[string]$read.StdOut,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $runDir 'mxf-reader-stderr.txt'),[string]$read.StdErr,(New-Object Text.UTF8Encoding($false)))
    if ($read.ExitCode -ne 0) { throw "Stock MXF identity readback failed: $($read.ExitCode)" }
    $normalized = ([string]$read.StdOut) -replace '\\',''
    $nameOk = $normalized.Contains([string]$id.display_name)
    $ltOk = $normalized.Contains(('LT='+[string]$id.logical_track_uuid))
    $tiOk = $normalized.Contains(('TI='+[string]$id.track_instance_uuid))

    $events = @()
    foreach ($line in Get-Content -LiteralPath $audit) {
        if ($line.Trim()) { $events += ($line | ConvertFrom-Json) }
    }
    $eventNames = @($events | ForEach-Object { [string]$_.event })
    $requiredEvents = @('SESSION_OPEN','SETUP','READY','RECORD','PAUSE','TEARDOWN','SESSION_CLOSE','MEDIA_COMMIT')
    $missingEvents = @($requiredEvents | Where-Object { $_ -notin $eventNames })
    $summaryMatch = [regex]::Match([string]$hostResult.StdOut,'RECORDER SUMMARY packets_received=(\d+) packets_recorded=(\d+) payload_bytes=(\d+) sequence_gap_packets=(\d+)[^\r\n]*?mux_bytes=(\d+) final=([A-Z_]+)')
    $recordedPackets = if($summaryMatch.Success){[int64]$summaryMatch.Groups[2].Value}else{-1}
    $payloadBytes = if($summaryMatch.Success){[int64]$summaryMatch.Groups[3].Value}else{-1}
    $muxBytes = if($summaryMatch.Success){[int64]$summaryMatch.Groups[5].Value}else{-1}
    $finalState = if($summaryMatch.Success){$summaryMatch.Groups[6].Value}else{'UNKNOWN'}
    $expectedPackets = [int](($firstRecordMs+$secondRecordMs)/20)

    $result = if(
        $streamCount -eq 1 -and $nameOk -and $ltOk -and $tiOk -and
        $missingEvents.Count -eq 0 -and $recordedPackets -eq $expectedPackets -and
        $payloadBytes -eq ($expectedPackets*160) -and $muxBytes -gt 0 -and $finalState -eq 'CLOSED_COMPLETE'
    ){'PASS'}else{'FAIL'}

    $report = [ordered]@{
        schema='recorder-poc.phase3.one-cwp.v1'
        result=$result
        recorder_ip=$recorderIp
        rtsp_port=$rtspPort
        rtp_port=$rtpPort
        cwp_ip=$cwpIp
        final_mxf=$final
        file_size_bytes=(Get-Item -LiteralPath $final).Length
        stream_count=$streamCount
        expected_packets=$expectedPackets
        recorded_packets=$recordedPackets
        recorded_payload_bytes=$payloadBytes
        mux_bytes_written=$muxBytes
        final_state=$finalState
        logical_track_uuid=$id.logical_track_uuid
        track_instance_uuid=$id.track_instance_uuid
        embedded_identity=[ordered]@{name=$nameOk;logical_uuid=$ltOk;instance_uuid=$tiOk}
        required_events=$requiredEvents
        missing_events=$missingEvents
        audit_event_count=$events.Count
        window_start_utc=$windowStartUtc
        segment_sequence=$segmentSequence
        storage_boundary='mxfidmux -> appsink -> Win32 StorageWriter'
        source_protection='CreateFileA GENERIC_WRITE / FILE_SHARE_READ only; no FILE_SHARE_DELETE'
    }
    $reportPath = Join-Path $runDir 'phase3-one-cwp-report.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

    Write-Host "Streams: $streamCount / 1"
    Write-Host "RTP recorded: $recordedPackets / $expectedPackets packets; payload=$payloadBytes bytes"
    Write-Host "Embedded identity: name=$nameOk LT=$ltOk TI=$tiOk"
    Write-Host "Required audit events missing: $($missingEvents.Count)"
    Write-Host "Final state: $finalState"
    Write-Host "Report: $reportPath"
    if($result -eq 'PASS'){
        Write-Host 'PHASE 3 ONE-CWP RECORDER: PASS' -ForegroundColor Green
        exit 0
    }
    Write-Error 'PHASE 3 ONE-CWP RECORDER: FAIL'
    exit 7
} catch {
    try {
        if (-not $recorderProcess.Process.HasExited) { $recorderProcess.Process.Kill(); $recorderProcess.Process.WaitForExit() }
        [IO.File]::WriteAllText($hostStdout,[string]$recorderProcess.StdOutTask.Result,(New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($hostStderr,[string]$recorderProcess.StdErrTask.Result,(New-Object Text.UTF8Encoding($false)))
    } catch {}
    throw
}
