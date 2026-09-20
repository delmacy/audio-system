Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')
. (Join-Path $PSScriptRoot '..\mxf\Track-Identity.ps1')

$root = Get-ProjectRoot
$profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
$cfg = Read-IniFile (Join-Path $root 'config\recorder\multi-cwp-routing.ini')
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
if ($sessionSections.Count -ne $expectedSessionCount) { throw "Config session_count=$expectedSessionCount but found $($sessionSections.Count) session sections." }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ("runs\phase5-multi-cwp-routing\$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$sessionMap = Join-Path $runDir 'session-map.tsv'
$clientManifest = Join-Path $runDir 'client-manifest.json'
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$hostStdout = Join-Path $runDir 'recorder-stdout.txt'
$hostStderr = Join-Path $runDir 'recorder-stderr.txt'
$simOutDir = Join-Path $runDir 'simulators'
$windowStartUtc = ([DateTime]::UtcNow).ToString('yyyy-MM-ddTHH:00:00.000Z')

$rows = @()
$clients = @()
$expectations = @()
for ($i=0; $i -lt $sessionSections.Count; $i++) {
    $section = $sessionSections[$i]
    $s = $cfg[$section]
    $endpoint = [string]$s['endpoint_id']
    $serviceType = [string]$s['service_type']
    $serviceId = [string]$s['service_id']
    $direction = ([string]$s['direction']).ToUpperInvariant()
    $directionLower = $direction.ToLowerInvariant()
    $activitySignal = [string]$s['activity_signal']
    $burstCount = [int]$s['burst_count']
    $burstMs = [int]$s['burst_ms']
    $silenceMs = [int]$s['silence_ms']
    $keepaliveIntervalMs = [int]$s['keepalive_interval_ms']
    $pausedProbePackets = [int]$s['paused_probe_packets']
    $rtpPort = $rtpBase + ($i * 2)
    $localRtpPort = $localRtpBase + ($i * 2)
    $routeKey = "/record/$endpoint/radio-$serviceId-$directionLower"
    $sdpName = "RADIO $serviceId $endpoint $direction"
    $sdpLabel = "radio-$serviceId-$($endpoint.ToLowerInvariant())-$directionLower"
    $identity = New-LogicalTrackIdentity -ServiceType $serviceType -ServiceId $serviceId -EndpointId $endpoint -Direction $direction `
        -SdpServiceNameRaw $sdpName -SdpLabelRaw $sdpLabel -SdpMidRaw 'audio0'
    $slug = ('{0}-{1}-{2}' -f $endpoint.ToLowerInvariant(),$serviceId,$directionLower)
    $partial = Join-Path $runDir ($slug + '.mxf.partial')
    $final = Join-Path $runDir ($slug + '.mxf')
    $lock = $final + '.lock'
    $fileId = ('P5-{0}-{1}' -f ($i+1),([Guid]::NewGuid().ToString()))
    $fields = @(
        $routeKey,$endpoint,$serviceId,$direction,$activitySignal,[string]$identity.display_name,
        [string]$identity.logical_track_uuid,[string]$identity.track_instance_uuid,$fileId,
        $partial,$final,$lock,[string]$rtpPort,$windowStartUtc,'0','radio'
    )
    foreach ($f in $fields) { if ([string]$f -match "`t|`r|`n") { throw "TSV field contains a forbidden control character for route $routeKey" } }
    $rows += ($fields -join "`t")
    $clients += [ordered]@{
        name=('cwp-{0:D2}' -f ($i+1)); local_ip=$cwpIp; recorder_ip=$recorderIp; rtsp_port=$rtspPort
        recorder_rtp_port=$rtpPort; local_rtp_port=$localRtpPort; endpoint_id=$endpoint; service_id=$serviceId; direction=$direction
        burst_count=$burstCount; burst_ms=$burstMs; silence_ms=$silenceMs; keepalive_interval_ms=$keepaliveIntervalMs; paused_probe_packets=$pausedProbePackets
    }
    $expectations += [ordered]@{
        route_key=$routeKey; endpoint_id=$endpoint; service_id=$serviceId; direction=$direction; rtp_port=$rtpPort
        logical_track_uuid=[string]$identity.logical_track_uuid; track_instance_uuid=[string]$identity.track_instance_uuid
        final_mxf=$final; partial_mxf=$partial; lock_path=$lock
        expected_recorded_packets=($burstCount * [int]($burstMs/20)); expected_ignored_packets=($burstCount * $pausedProbePackets)
        expected_record_commands=$burstCount; expected_pause_commands=$burstCount
    }
}

$header = @('route_key','endpoint_id','service_id','direction','activity_signal','display_name','logical_uuid','instance_uuid','file_id','output_partial','output_final','lock_path','rtp_port','window_start_utc','segment_sequence','session_kind') -join "`t"
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllLines($sessionMap,[string[]](@($header) + $rows),$utf8NoBom)
$clientJson = [ordered]@{schema='recorder-poc.phase5.client-manifest.v1';clients=$clients} | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($clientManifest,$clientJson,$utf8NoBom)

$hostArgs = @(
    '--bind-ip',$recorderIp,'--rtsp-port',[string]$rtspPort,'--session-map',$sessionMap,
    '--audit',$audit,'--ready-file',$ready,'--plugin-dll',$pluginDll,'--recorder-id','RECORDER-POC-01','--max-seconds',[string]$maxSeconds
)

Write-Host '=== Phase 5: Multi-session / CWP Routing ==='
Write-Host "Recorder: $recorderIp`:$rtspPort"
Write-Host "Configured sessions: $expectedSessionCount"
Write-Host "Run: $runDir"
$recorderProcess = Start-NativeProcessRedirected -FilePath $recorderExe -Arguments $hostArgs -StdOutPath $hostStdout -StdErrPath $hostStderr -WorkingDirectory $root
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path $ready)) {
        if ($recorderProcess.Process.HasExited) { throw "recorder-host exited before READY code=$($recorderProcess.Process.ExitCode)" }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Timed out waiting for multi-session recorder READY.' }
        Start-Sleep -Milliseconds 50
    }
    $readyObj = Get-Content -Raw -LiteralPath $ready | ConvertFrom-Json
    if ([int]$readyObj.session_count -ne $expectedSessionCount) { throw "READY session_count=$($readyObj.session_count), expected=$expectedSessionCount" }
    if (@($readyObj.sessions).Count -ne $expectedSessionCount) { throw 'READY session list cardinality mismatch.' }

    $simScript = Join-Path $root 'scripts\cwp\Invoke-MultiCwpRoutingSimulator.ps1'
    $psExe = (Get-Command powershell.exe).Source
    $sim = Invoke-NativeProcessCapture -FilePath $psExe -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$simScript,'-ClientManifest',$clientManifest,'-OutputDirectory',$simOutDir) -WorkingDirectory $root -TimeoutMs 60000
    [IO.File]::WriteAllText((Join-Path $runDir 'multi-simulator-stdout.txt'),[string]$sim.StdOut,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $runDir 'multi-simulator-stderr.txt'),[string]$sim.StdErr,(New-Object Text.UTF8Encoding($false)))
    if ($sim.ExitCode -ne 0) { throw "Multi-CWP simulator failed exit=$($sim.ExitCode): $($sim.StdErr)" }

    $hostResult = Complete-NativeProcessRedirected -Handle $recorderProcess -TimeoutMs 30000
    if ($hostResult.ExitCode -ne 0) { throw "recorder-host failed exit=$($hostResult.ExitCode): $($hostResult.StdErr)" }

    $events = @(Get-Content -LiteralPath $audit | Where-Object {$_.Trim()} | ForEach-Object { $_ | ConvertFrom-Json })
    $routeBoundEvents = @($events | Where-Object { [string]$_.event -eq 'ROUTE_BOUND' })
    $routeActiveEvents = @($events | Where-Object { [string]$_.event -eq 'RTP_ROUTE_ACTIVE' })
    $collisionEvents = @($events | Where-Object { [string]$_.event -eq 'ROUTE_COLLISION' })
    $rejectedEvents = @($events | Where-Object { [string]$_.event -eq 'ROUTE_REJECTED' })
    $integrityFailures = @($events | Where-Object { [string]$_.event -eq 'INTEGRITY_FAILURE' })

    $summaryPattern = 'RECORDER SESSION SUMMARY route=(\S+) session=(\S+) packets_received=(\d+) packets_recorded=(\d+) payload_bytes=(\d+) sequence_gap_packets=(\d+)[^\r\n]*?mux_bytes=(\d+) final=([A-Z_]+) record_commands=(\d+) pause_commands=(\d+) keepalives=(\d+) media_intervals_started=(\d+) media_intervals_closed=(\d+) packets_ignored_not_recording=(\d+) teardown=(\d+)'
    $summaryMatches = [regex]::Matches([string]$hostResult.StdOut,$summaryPattern)
    $summaries = @{}
    foreach ($m in $summaryMatches) {
        $summaries[$m.Groups[1].Value] = [ordered]@{
            session_id=$m.Groups[2].Value; packets_received=[int64]$m.Groups[3].Value; packets_recorded=[int64]$m.Groups[4].Value
            payload_bytes=[int64]$m.Groups[5].Value; sequence_gap_packets=[int64]$m.Groups[6].Value; mux_bytes=[int64]$m.Groups[7].Value
            final=$m.Groups[8].Value; record_commands=[int]$m.Groups[9].Value; pause_commands=[int]$m.Groups[10].Value
            keepalives=[int]$m.Groups[11].Value; media_intervals_started=[int]$m.Groups[12].Value; media_intervals_closed=[int]$m.Groups[13].Value
            packets_ignored_not_recording=[int64]$m.Groups[14].Value; teardown=[int]$m.Groups[15].Value
        }
    }

    $sessionResults = @()
    foreach ($e in $expectations) {
        $route = [string]$e.route_key
        $summary = if ($summaries.ContainsKey($route)) { $summaries[$route] } else { $null }
        $finalExists = Test-Path -LiteralPath ([string]$e.final_mxf)
        $lifecycleOk = $finalExists -and -not (Test-Path -LiteralPath ([string]$e.partial_mxf)) -and -not (Test-Path -LiteralPath ([string]$e.lock_path))
        $routeBound = @($routeBoundEvents | Where-Object { [string]$_.route_key -eq $route }).Count -eq 1
        $routeActive = @($routeActiveEvents | Where-Object { [string]$_.route_key -eq $route }).Count -eq 1
        $ok = (
            $null -ne $summary -and $lifecycleOk -and $routeBound -and $routeActive -and
            [int64]$summary.packets_recorded -eq [int64]$e.expected_recorded_packets -and
            [int64]$summary.packets_ignored_not_recording -eq [int64]$e.expected_ignored_packets -and
            [int]$summary.record_commands -eq [int]$e.expected_record_commands -and
            [int]$summary.pause_commands -eq [int]$e.expected_pause_commands -and
            [int]$summary.media_intervals_started -eq [int]$e.expected_record_commands -and
            [int]$summary.media_intervals_closed -eq [int]$e.expected_record_commands -and
            [int]$summary.teardown -eq 1 -and [string]$summary.final -eq 'CLOSED_COMPLETE' -and [int64]$summary.sequence_gap_packets -eq 0
        )
        $sessionResults += [ordered]@{
            route_key=$route; result=if($ok){'PASS'}else{'FAIL'}; rtp_port=$e.rtp_port
            logical_track_uuid=$e.logical_track_uuid; track_instance_uuid=$e.track_instance_uuid; session_id=if($summary){$summary.session_id}else{$null}
            expected_recorded_packets=$e.expected_recorded_packets; actual_recorded_packets=if($summary){$summary.packets_recorded}else{$null}
            expected_ignored_packets=$e.expected_ignored_packets; actual_ignored_packets=if($summary){$summary.packets_ignored_not_recording}else{$null}
            lifecycle_ok=$lifecycleOk; route_bound_event=$routeBound; rtp_route_active_event=$routeActive
        }
    }

    $sessionIds = @($sessionResults | ForEach-Object { [string]$_.session_id } | Where-Object { $_ })
    $uniqueSessionIds = @($sessionIds | Sort-Object -Unique).Count -eq $expectedSessionCount
    $uniqueLogical = @($expectations | ForEach-Object { [string]$_.logical_track_uuid } | Sort-Object -Unique).Count -eq $expectedSessionCount
    $uniqueInstances = @($expectations | ForEach-Object { [string]$_.track_instance_uuid } | Sort-Object -Unique).Count -eq $expectedSessionCount
    $uniqueRtpPorts = @($expectations | ForEach-Object { [int]$_.rtp_port } | Sort-Object -Unique).Count -eq $expectedSessionCount
    $allSessionPass = @($sessionResults | Where-Object { $_.result -ne 'PASS' }).Count -eq 0
    $result = if($allSessionPass -and $uniqueSessionIds -and $uniqueLogical -and $uniqueInstances -and $uniqueRtpPorts -and
        $routeBoundEvents.Count -eq $expectedSessionCount -and $routeActiveEvents.Count -eq $expectedSessionCount -and
        $collisionEvents.Count -eq 0 -and $rejectedEvents.Count -eq 0 -and $integrityFailures.Count -eq 0){'PASS'}else{'FAIL'}

    $report = [ordered]@{
        schema='recorder-poc.phase5.multi-cwp-routing.v1'; result=$result; session_count=$expectedSessionCount
        fixture_scope='legacy_rx_tx_routing_mechanics'; canonical_mono_service_model_validated=$false
        single_recorder_process=$true; one_rtsp_listener=$true; route_source='session-map.tsv'; window_start_utc=$windowStartUtc
        route_bound_events=$routeBoundEvents.Count; rtp_route_active_events=$routeActiveEvents.Count
        route_collision_events=$collisionEvents.Count; route_rejected_events=$rejectedEvents.Count; integrity_failures=$integrityFailures.Count
        unique_session_ids=$uniqueSessionIds; unique_logical_track_uuids=$uniqueLogical; unique_track_instance_uuids=$uniqueInstances; unique_rtp_ports=$uniqueRtpPorts
        cross_session_contamination_proxy='unique RTP socket -> route mapping plus route-specific expected packet counts; no route collisions/rejections'
        sessions=$sessionResults
    }
    $reportPath = Join-Path $runDir 'phase5-multi-cwp-routing-report.json'
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8

    Write-Host "Sessions summarized: $($summaries.Count) / $expectedSessionCount"
    Write-Host "ROUTE_BOUND: $($routeBoundEvents.Count); RTP_ROUTE_ACTIVE: $($routeActiveEvents.Count)"
    Write-Host "Collisions: $($collisionEvents.Count); rejected routes: $($rejectedEvents.Count); integrity failures: $($integrityFailures.Count)"
    Write-Host "Unique Session IDs: $uniqueSessionIds; LT: $uniqueLogical; TI: $uniqueInstances; RTP ports: $uniqueRtpPorts"
    Write-Host "Report: $reportPath"
    if($result -eq 'PASS'){ Write-Host 'PHASE 5 MULTI-CWP ROUTING: PASS' -ForegroundColor Green; exit 0 }
    Write-Error 'PHASE 5 MULTI-CWP ROUTING: FAIL'; exit 9
} catch {
    try {
        if (-not $recorderProcess.Process.HasExited) { $recorderProcess.Process.Kill(); $recorderProcess.Process.WaitForExit() }
        [IO.File]::WriteAllText($hostStdout,[string]$recorderProcess.StdOutTask.Result,(New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($hostStderr,[string]$recorderProcess.StdErrTask.Result,(New-Object Text.UTF8Encoding($false)))
    } catch {}
    throw
}
