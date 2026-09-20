[CmdletBinding()]
param([switch]$ToneValidation,[int]$ServiceCount = 0)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')
. (Join-Path $PSScriptRoot '..\mxf\Track-Identity.ps1')

$root = Get-ProjectRoot
$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$cfg = Read-IniFile (Join-Path $root 'config\recorder\service-perspective-matrix.ini')
$recorderExe = Find-RecorderHostExe
if (-not $recorderExe) { throw 'recorder-host.exe missing. Build it before integrated acceptance.' }
$pluginDll = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path $pluginDll)) { throw 'gstmxfidentity.dll missing.' }

$recorderIp = [string]$profile['recorder']['ip']
$rtspPort = [int]$profile['recorder']['rtsp_port']
$cwpIp = [string]$profile['cwp-a']['ip_start']
$rtpBase = [int]$profile['rtp']['port_start'] + [int]$cfg['host']['rtp_port_base_offset']
$localRtpBase = [int]$profile['rtp']['port_start'] + [int]$cfg['host']['local_rtp_port_base_offset']
$maxSeconds = [int]$cfg['host']['max_recorder_seconds']
$sessionSections = @($cfg.Keys | Where-Object { $_ -like 'session-*' } | Sort-Object)
$expectedSessionCount = [int]$cfg['host']['session_count']
if ($sessionSections.Count -ne $expectedSessionCount) { throw "Config session_count=$expectedSessionCount but found $($sessionSections.Count)." }
if ($ServiceCount -gt 0) {
    if ($ServiceCount -gt 100) { throw 'ServiceCount exceeds the optional L6 capacity challenge.' }
    while ($sessionSections.Count -lt $ServiceCount) {
        $number = $sessionSections.Count + 1
        $section = ('session-{0:D3}' -f $number)
        $cfg[$section] = @{
            endpoint_id = ('CWP-STRESS-{0:D3}' -f $number)
            service_type = 'radio'
            service_id = ('STRESS-{0:D3}' -f $number)
            media_flow = 'mono'
            activity_signal = 'squ'
            burst_count = '2'
            burst_ms = '240'
            silence_ms = '300'
            keepalive_interval_ms = '150'
            paused_probe_packets = '1'
        }
        $sessionSections += $section
    }
    $sessionSections = @($sessionSections | Select-Object -First $ServiceCount)
    $expectedSessionCount = $ServiceCount
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ("runs\phase9-service-perspective-matrix\$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$toneFiles = @()
if ($ToneValidation) {
    $ffmpeg = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
    foreach ($frequency in @(2500,3500)) {
        $tonePath = Join-Path $runDir ("tone-$frequency.pcma")
        & $ffmpeg -y -v error -f lavfi -i "sine=frequency=$($frequency):sample_rate=8000:duration=2" -ac 1 -ar 8000 -c:a pcm_alaw -f alaw $tonePath
        if ($LASTEXITCODE -ne 0 -or (Get-Item -LiteralPath $tonePath).Length -lt 8000) { throw "Could not generate PCMA tone $frequency Hz" }
        $toneFiles += $tonePath
    }
}
$sessionMap = Join-Path $runDir 'session-map.tsv'
$clientManifest = Join-Path $runDir 'client-manifest.json'
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$hostStdout = Join-Path $runDir 'recorder-stdout.txt'
$hostStderr = Join-Path $runDir 'recorder-stderr.txt'
$simOutDir = Join-Path $runDir 'simulators'
$windowStartUtc = ([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH:00:00.000Z')

$rows = @(); $clients = @(); $expectations = @(); $logicalSet = @{}
for ($i=0; $i -lt $sessionSections.Count; $i++) {
    $section = $sessionSections[$i]
    $s = $cfg[$section]
    $endpoint = [string]$s['endpoint_id']
    $serviceType = [string]$s['service_type']
    $serviceId = [string]$s['service_id']
    $mediaFlow = if($s.ContainsKey('media_flow')){[string]$s['media_flow']}else{'mono'}
    if ($mediaFlow.ToLowerInvariant() -ne 'mono') { throw "Phase 9 base model requires media_flow=mono; found $mediaFlow in $section" }
    if ($s.ContainsKey('direction')) { throw "Phase 9 service matrix must not use direction in $section. Use media_flow=mono." }
    $activitySignal = [string]$s['activity_signal']
    $burstCount = [int]$s['burst_count']; $burstMs=[int]$s['burst_ms']; $silenceMs=[int]$s['silence_ms']
    $pcmaFile = if ($ToneValidation -and $i -lt 2) { $toneFiles[$i] } else { '' }
    $keepaliveIntervalMs=[int]$s['keepalive_interval_ms']; $pausedProbePackets=[int]$s['paused_probe_packets']
    $callLegId = if($s.ContainsKey('call_leg_id')){[string]$s['call_leg_id']}else{''}
    $rtpPort = $rtpBase + ($i * 2); $localRtpPort = $localRtpBase + ($i * 2)
    $serviceSlug = if($serviceType.ToLowerInvariant() -eq 'telephone'){ 'tel-' + $serviceId.ToLowerInvariant() } else { 'radio-' + $serviceId.ToLowerInvariant() }
    $routeKey = "/record/$endpoint/$serviceSlug"
    $sdpName = "$($serviceType.ToUpperInvariant()) $serviceId $endpoint $($mediaFlow.ToUpperInvariant())"
    $sdpLabel = "$serviceSlug-$($endpoint.ToLowerInvariant())-$($mediaFlow.ToLowerInvariant())"
    $identity = New-ServiceLogicalTrackIdentity -ServiceType $serviceType -ServiceId $serviceId -EndpointId $endpoint -MediaFlow $mediaFlow -CallLegId $callLegId `
        -SdpServiceNameRaw $sdpName -SdpLabelRaw $sdpLabel -SdpMidRaw 'audio0'
    $logicalSet[[string]$identity.logical_track_uuid] = $true
    $slug = ('{0}-{1}-{2}' -f $endpoint.ToLowerInvariant(),$serviceId.ToLowerInvariant(),$mediaFlow.ToLowerInvariant()) -replace '[^a-z0-9\-]','-'
    $partial = Join-Path $runDir ($slug + '.mxf.partial')
    $final = Join-Path $runDir ($slug + '.mxf')
    $lock = $final + '.lock'
    $fileId = ('P9-{0}-{1}' -f ($i+1),([Guid]::NewGuid().ToString()))
    $fields = @($routeKey,$endpoint,$serviceId,$mediaFlow,$activitySignal,[string]$identity.display_name,[string]$identity.logical_track_uuid,[string]$identity.track_instance_uuid,$fileId,$partial,$final,$lock,[string]$rtpPort,$windowStartUtc,'0',$serviceType)
    foreach ($f in $fields) { if ([string]$f -match "`t|`r|`n") { throw "TSV field contains a forbidden control character for route $routeKey" } }
    $rows += ($fields -join "`t")
    $clients += [ordered]@{name=('service-{0:D2}' -f ($i+1)); local_ip=$cwpIp; recorder_ip=$recorderIp; rtsp_port=$rtspPort; recorder_rtp_port=$rtpPort; local_rtp_port=$localRtpPort; endpoint_id=$endpoint; service_id=$serviceId; service_type=$serviceType; media_flow=$mediaFlow; burst_count=$burstCount; burst_ms=$burstMs; silence_ms=$silenceMs; keepalive_interval_ms=$keepaliveIntervalMs; paused_probe_packets=$pausedProbePackets; pcma_file=$pcmaFile}
    $expectations += [ordered]@{route_key=$routeKey; endpoint_id=$endpoint; service_id=$serviceId; service_type=$serviceType; media_flow=$mediaFlow; logical_track_uuid=[string]$identity.logical_track_uuid; track_instance_uuid=[string]$identity.track_instance_uuid; final_mxf=$final; expected_recorded_packets=($burstCount * [int]($burstMs/20)); expected_ignored_packets=($burstCount*$pausedProbePackets)}
}
$header = @('route_key','endpoint_id','service_id','media_flow','activity_signal','display_name','logical_uuid','instance_uuid','file_id','output_partial','output_final','lock_path','rtp_port','window_start_utc','segment_sequence','session_kind') -join "`t"
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllLines($sessionMap,[string[]](@($header) + $rows),$utf8NoBom)
[ordered]@{schema='recorder-poc.phase9.client-manifest.v1';clients=$clients;model='one-service-one-mono-flow'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $clientManifest -Encoding UTF8

$hostArgs = @('--bind-ip',$recorderIp,'--rtsp-port',[string]$rtspPort,'--session-map',$sessionMap,'--audit',$audit,'--ready-file',$ready,'--plugin-dll',$pluginDll,'--recorder-id','RECORDER-POC-01','--max-seconds',[string]$maxSeconds)
Write-Host '=== Phase 9: Service Perspective Matrix ==='
Write-Host "Recorder: $recorderIp`:$rtspPort"
Write-Host "Configured mono service sessions: $expectedSessionCount"
Write-Host "Run: $runDir"
$recorderProcess = Start-NativeProcessRedirected -FilePath $recorderExe -Arguments $hostArgs -StdOutPath $hostStdout -StdErrPath $hostStderr -WorkingDirectory $root
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path $ready)) {
        if ($recorderProcess.Process.HasExited) { throw "recorder-host exited before READY code=$($recorderProcess.Process.ExitCode)" }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Timed out waiting for service matrix recorder READY.' }
        Start-Sleep -Milliseconds 50
    }
    $readyObj = Get-Content -Raw -LiteralPath $ready | ConvertFrom-Json
    if ([int]$readyObj.session_count -ne $expectedSessionCount) { throw "READY session_count=$($readyObj.session_count), expected=$expectedSessionCount" }
    $simScript = Join-Path $root 'scripts\cwp\Invoke-ServicePerspectiveSimulator.ps1'
    $psExe = (Get-Command powershell.exe).Source
    $sim = Invoke-NativeProcessCapture -FilePath $psExe -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$simScript,'-ClientManifest',$clientManifest,'-OutputDirectory',$simOutDir) -WorkingDirectory $root -TimeoutMs 60000
    [IO.File]::WriteAllText((Join-Path $runDir 'service-simulator-stdout.txt'),[string]$sim.StdOut,$utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $runDir 'service-simulator-stderr.txt'),[string]$sim.StdErr,$utf8NoBom)
    if ($sim.ExitCode -ne 0) { throw "Service perspective simulator failed exit=$($sim.ExitCode): $($sim.StdErr)" }
    $hostResult = Complete-NativeProcessRedirected -Handle $recorderProcess -TimeoutMs 30000
    if ($hostResult.ExitCode -ne 0) { throw "recorder-host failed exit=$($hostResult.ExitCode): $($hostResult.StdErr)" }
    $events = @(Get-Content -LiteralPath $audit | Where-Object {$_.Trim()} | ForEach-Object { $_ | ConvertFrom-Json })
    $summaryPattern = 'RECORDER SESSION SUMMARY route=(\S+) session=(\S+) packets_received=(\d+) packets_recorded=(\d+) payload_bytes=(\d+) sequence_gap_packets=(\d+)[^\r\n]*?mux_bytes=(\d+) final=([A-Z_]+) record_commands=(\d+) pause_commands=(\d+) keepalives=(\d+) media_intervals_started=(\d+) media_intervals_closed=(\d+) packets_ignored_not_recording=(\d+) teardown=(\d+)'
    $summaryMatches = [regex]::Matches([string]$hostResult.StdOut,$summaryPattern)
    if ($summaryMatches.Count -ne $expectedSessionCount) { throw "Expected $expectedSessionCount session summaries, found $($summaryMatches.Count)." }
    if ($logicalSet.Keys.Count -ne $expectedSessionCount) { throw 'LogicalTrackUUID collision in mono service matrix.' }
    $ffprobe = Find-Executable @('ffprobe.exe','ffprobe')
    if (-not $ffprobe) { throw 'ffprobe is required to verify one mono audio stream per MXF.' }
    foreach ($e in $expectations) {
        $found = $false
        foreach($m in $summaryMatches){ if($m.Groups[1].Value -eq $e.route_key){
            $found=$true
            if($m.Groups[8].Value -ne 'CLOSED_COMPLETE'){ throw "Route $($e.route_key) final=$($m.Groups[8].Value)" }
            if([int64]$m.Groups[4].Value -ne [int64]$e.expected_recorded_packets){ throw "Recorded packet count mismatch for $($e.route_key)" }
            if([int64]$m.Groups[14].Value -ne [int64]$e.expected_ignored_packets){ throw "Ignored packet count mismatch for $($e.route_key)" }
            if([int64]$m.Groups[7].Value -le 0){ throw "No MXF bytes written for $($e.route_key)" }
            break
        } }
        if(-not $found){ throw "Missing summary for $($e.route_key)" }
        if(-not (Test-Path -LiteralPath $e.final_mxf) -or (Test-Path -LiteralPath ($e.final_mxf + '.partial')) -or (Test-Path -LiteralPath ($e.final_mxf + '.lock'))){ throw "MXF lifecycle failed for $($e.route_key)" }
        $probeJson = & $ffprobe -v error -select_streams a -show_entries stream=channels -of json $e.final_mxf
        if($LASTEXITCODE -ne 0){ throw "ffprobe failed for $($e.route_key)" }
        $streams = @(($probeJson | Out-String | ConvertFrom-Json).streams)
        if($streams.Count -ne 1 -or [int]$streams[0].channels -ne 1){ throw "Expected one mono audio stream for $($e.route_key)" }
    }
    $toneResults = @()
    if ($ToneValidation) {
        function TonePower([byte[]]$pcm,[int]$frequency) {
            $real = 0.0; $imag = 0.0; $sampleCount = 3200
            if ($pcm.Length -lt 2 * $sampleCount) { throw 'Decoded PCM is too short for tone measurement.' }
            for ($sample = 0; $sample -lt $sampleCount; $sample++) {
                $value = [BitConverter]::ToInt16($pcm,2*$sample)
                $angle = 2.0 * [Math]::PI * $frequency * $sample / 8000.0
                $real += $value * [Math]::Cos($angle)
                $imag += $value * [Math]::Sin($angle)
            }
            return ($real*$real + $imag*$imag)
        }
        for ($toneIndex=0; $toneIndex -lt 2; $toneIndex++) {
            $expectedFrequency = if ($toneIndex -eq 0) { 2500 } else { 3500 }
            $otherFrequency = if ($toneIndex -eq 0) { 3500 } else { 2500 }
            $entry = $expectations[$toneIndex]
            $probeText = & $ffprobe -v error -show_entries 'stream=index,codec_name,channels,sample_rate:stream_tags=track_name' -of json $entry.final_mxf
            if ($LASTEXITCODE -ne 0) { throw "ffprobe failed for tone track $($entry.route_key)" }
            $track = @(($probeText | Out-String | ConvertFrom-Json).streams)[0]
            $embedded = [string]$track.tags.track_name
            if (-not $embedded.Contains('LT=' + $entry.logical_track_uuid) -or -not $embedded.Contains('TI=' + $entry.track_instance_uuid)) { throw "Embedded LT/TI mismatch for tone track $($entry.route_key)" }
            $pcmPath = Join-Path $runDir ("tone-track-$expectedFrequency.pcm")
            & $ffmpeg -y -v error -i $entry.final_mxf -map '0:a:0' -ac 1 -ar 8000 -c:a pcm_s16le -f s16le $pcmPath
            if ($LASTEXITCODE -ne 0) { throw "Tone MXF decode failed for $($entry.route_key)" }
            $pcm = [IO.File]::ReadAllBytes($pcmPath)
            $wanted = TonePower $pcm $expectedFrequency
            $unwanted = TonePower $pcm $otherFrequency
            $ratio = $wanted / [Math]::Max($unwanted,1.0)
            if ($ratio -lt 100.0) { throw "Tone leakage or wrong track: $($entry.route_key) ratio=$ratio" }
            $toneResults += [pscustomobject]@{route_key=$entry.route_key;logical_track_uuid=$entry.logical_track_uuid;track_instance_uuid=$entry.track_instance_uuid;expected_hz=$expectedFrequency;other_hz=$otherFrequency;power_ratio=$ratio;decoded_pcm_bytes=$pcm.Length;embedded_identity_verified=$true}
        }
    }
    $report = [ordered]@{schema='recorder-poc.phase9.service-perspective-matrix.v1';result='PASS';run_dir=$runDir;model='one-service-one-mono-flow';sessions=$expectedSessionCount;unique_logical_tracks=$logicalSet.Keys.Count;no_rx_tx_split=$true;no_stereo_artificialization=$true;mono_streams_verified=$expectedSessionCount;embedded_identity_verified_for_tone_tracks=$ToneValidation.IsPresent;tone_validation=$toneResults;expectations=$expectations;audit=$audit;session_map=$sessionMap;load_scope='direct_rtsp_rtp_session_matrix';gateway_mix_executed=$false;fault_overlay_executed=$false}
    $reportPath = Join-Path $runDir 'service-perspective-matrix-report.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host "Report: $reportPath"
    Write-Host 'SERVICE PERSPECTIVE MATRIX: PASS' -ForegroundColor Green
} catch {
    try { if ($recorderProcess -and -not $recorderProcess.Process.HasExited) { $recorderProcess.Process.Kill(); $recorderProcess.Process.WaitForExit() } } catch {}
    Write-Error ("SERVICE PERSPECTIVE MATRIX: FAIL - {0}" -f $_.Exception.Message)
    exit 1
}
