param(
    [int]$LegCount = 1000,
    [int]$RingSeconds = 10,
    [double]$ToneHz = 440.0,
    [int]$ReadyTimeoutSeconds = 30,
    [int]$FinalizeTimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')

if ($LegCount -lt 1 -or $LegCount -gt 1800) { throw 'LegCount must be between 1 and 1800.' }
if ($RingSeconds -lt 1 -or $RingSeconds -gt 16) { throw 'RingSeconds must be between 1 and 16 seconds.' }

$root = Get-ProjectRoot
$exe = Find-RecorderHostExe
if (-not $exe) { throw 'recorder-host.exe was not built.' }
$plugin = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path -LiteralPath $plugin)) { throw 'gstmxfidentity.dll was not built.' }
$lab = @((Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),(Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $lab) { throw 'mxf-lab.exe was not built.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ('runs\event-rtp-burst\' + $stamp)
$recordingRoot = Join-Path $runDir 'recordings'
New-Item -ItemType Directory -Force -Path $runDir,$recordingRoot | Out-Null
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$stdout = Join-Path $runDir 'recorder-stdout.txt'
$stderr = Join-Path $runDir 'recorder-stderr.txt'
$shutdown = Join-Path $runDir 'shutdown.signal'
$sessionMap = Join-Path $runDir 'session-map.tsv'
$driverStdout = Join-Path $runDir 'rtp-driver-stdout.txt'
$driverStderr = Join-Path $runDir 'rtp-driver-stderr.txt'
$summaryPath = Join-Path $runDir 'rtp-burst-summary.json'
$pcma = Join-Path $runDir ('ring-{0:g}Hz-{1}s.pcma' -f $ToneHz,$RingSeconds)
$wav = Join-Path $runDir ('ring-{0:g}Hz-{1}s.wav' -f $ToneHz,$RingSeconds)
$rtspPort = 8854
$baseRtpPort = 26000

$generator = Join-Path $root 'scripts\generator\audio_generator.py'
$generatorArgs = @($generator,'--frequency',[string]$ToneHz,'--duration',[string]$RingSeconds,'--level-dbfs','-12','--pcma',$pcma,'--wav',$wav)
& python @generatorArgs
if ($LASTEXITCODE -ne 0) { throw "Audio generator failed with exit code $LASTEXITCODE" }
$expectedPayloadBytes = 8000 * $RingSeconds
if ((Get-Item -LiteralPath $pcma).Length -ne $expectedPayloadBytes) { throw 'Generated PCMA size mismatch.' }

$tab = [char]9
$header = @('route_key','endpoint_id','service_id','media_flow','activity_signal','display_name','logical_uuid','instance_uuid','file_id','output_partial','output_final','lock_path','rtp_port','window_start_utc','segment_sequence','session_kind') -join $tab
$rows = New-Object 'System.Collections.Generic.List[string]'
$rows.Add($header)
$windowStart = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:00:00.000Z')
for ($i = 0; $i -lt $LegCount; $i++) {
    $endpoint = 'RTP-CWP-{0:D4}' -f ($i + 1)
    $route = '/record/{0}/tel-rtp-ring' -f $endpoint
    $placeholder = Join-Path $runDir ('placeholder-' + $endpoint + '.mxf')
    $rows.Add((@($route,$endpoint,'RTP-RING','mono','none',('RTP RING ' + $endpoint),[Guid]::NewGuid().ToString(),[Guid]::NewGuid().ToString(),('PLACEHOLDER-' + $endpoint),($placeholder + '.partial'),$placeholder,($placeholder + '.lock'),[string]($baseRtpPort + $i),$windowStart,'0','telephone') -join $tab))
}
[IO.File]::WriteAllLines($sessionMap,[string[]]$rows,(New-Object Text.UTF8Encoding($false)))

$recorderArgs = @('--bind-ip','127.0.0.1','--rtsp-port',[string]$rtspPort,'--session-map',$sessionMap,'--audit',$audit,'--ready-file',$ready,'--plugin-dll',$plugin,'--recorder-id','RECORDER-CI-RTP-BURST','--max-seconds','180','--event-files','--recording-root',$recordingRoot,'--shutdown-watch-file',$shutdown)
$recorder = Start-NativeProcessRedirected -FilePath $exe -Arguments $recorderArgs -StdOutPath $stdout -StdErrPath $stderr -WorkingDirectory $root
try {
    $deadline = [DateTime]::UtcNow.AddSeconds($ReadyTimeoutSeconds)
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($recorder.Process.HasExited) { throw "Recorder exited before READY code=$($recorder.Process.ExitCode)." }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Recorder READY timeout.' }
        Start-Sleep -Milliseconds 50
    }
    $readyState = Get-Content -LiteralPath $ready -Raw | ConvertFrom-Json
    if (-not $readyState.ready -or [int]$readyState.session_count -ne $LegCount) { throw 'Recorder READY state mismatch.' }

    $driver = Join-Path $root 'scripts\recorder\event_rtp_burst_driver.py'
    $driverArgs = @($driver,'--host','127.0.0.1','--rtsp-port',[string]$rtspPort,'--base-rtp-port',[string]$baseRtpPort,'--legs',[string]$LegCount,'--duration-ms',[string]($RingSeconds * 1000),'--pcma-file',$pcma,'--service-id','RTP-RING')
    $driverHandle = Start-NativeProcessRedirected -FilePath 'python' -Arguments $driverArgs -StdOutPath $driverStdout -StdErrPath $driverStderr -WorkingDirectory $root
    $driverResult = Complete-NativeProcessRedirected -Handle $driverHandle -TimeoutMs (($RingSeconds + 120) * 1000)
    if ($driverResult.ExitCode -ne 0) { throw "RTP burst driver failed exit=$($driverResult.ExitCode) stderr=$($driverResult.StdErr)" }
    if ($driverResult.StdOut -notmatch 'RTP BURST DRIVER: PASS') { throw 'RTP burst driver did not report PASS.' }

    $finalDeadline = [DateTime]::UtcNow.AddSeconds($FinalizeTimeoutSeconds)
    do {
        $files = @(Get-ChildItem -LiteralPath $recordingRoot -Recurse -File -Filter '*.mxf' -ErrorAction SilentlyContinue)
        $partials = @(Get-ChildItem -LiteralPath $recordingRoot -Recurse -File -Filter '*.partial' -ErrorAction SilentlyContinue)
        if ($files.Count -eq $LegCount -and $partials.Count -eq 0) { break }
        if ([DateTime]::UtcNow -gt $finalDeadline) { throw "Finalize timeout files=$($files.Count) partials=$($partials.Count)." }
        Start-Sleep -Milliseconds 200
    } while ($true)

    $events = @()
    foreach ($line in Get-Content -LiteralPath $audit) { if ($line.Trim()) { $events += ($line | ConvertFrom-Json) } }
    if (@($events | Where-Object { $_.event -eq 'EVENT_FILE_OPEN' }).Count -ne $LegCount) { throw 'EVENT_FILE_OPEN count mismatch.' }
    if (@($events | Where-Object { $_.event -eq 'EVENT_FILE_CLOSED' }).Count -ne $LegCount) { throw 'EVENT_FILE_CLOSED count mismatch.' }
    if (@($events | Where-Object { $_.event -eq 'MEDIA_INGRESS_ORIGIN' }).Count -ne $LegCount) { throw 'MEDIA_INGRESS_ORIGIN count mismatch.' }
    if (@($events | Where-Object { $_.event -eq 'INTEGRITY_FAILURE' }).Count -ne 0) { throw 'Audit contains INTEGRITY_FAILURE.' }

    $files = @($files | Sort-Object FullName)
    $lastIndex = [int]$files.Count - 1
    $indices = @(0,[int][Math]::Floor($lastIndex*0.25),[int][Math]::Floor($lastIndex*0.50),[int][Math]::Floor($lastIndex*0.75),$lastIndex) | Select-Object -Unique
    foreach ($index in $indices) {
        $file = $files[[int]$index]
        & $lab inspect $file.FullName '--expected-tracks' '1' '--timeout-ms' '15000' '--expected-alaw-8k-mono'
        if ($LASTEXITCODE -ne 0) { throw "MXF inspection failed: $($file.FullName)" }
    }

    Set-Content -LiteralPath $shutdown -Value 'shutdown' -Encoding ascii
    $recorderResult = Complete-NativeProcessRedirected -Handle $recorder -TimeoutMs 60000
    if ($recorderResult.ExitCode -ne 0) { throw "Recorder shutdown failed exit=$($recorderResult.ExitCode)" }
    $expectedPackets = [int64]$LegCount * [int64]$RingSeconds * 50
    $summaryText = [string](@($recorderResult.StdOut -split "`r?`n" | Where-Object { $_ -like 'RECORDER HOST SUMMARY*' } | Select-Object -Last 1)[0])
    foreach ($pair in @{'packets_received'=$expectedPackets;'packets_recorded'=$expectedPackets;'sequence_gap_packets'=0;'duplicates'=0;'out_of_order'=0;'malformed'=0;'wrong_pt'=0;'timestamp_discontinuities'=0}.GetEnumerator()) {
        $pattern = [regex]::Escape([string]$pair.Key) + '=([0-9]+)'
        if ($summaryText -notmatch $pattern) { throw "Summary missing $($pair.Key)." }
        if ([int64]$Matches[1] -ne [int64]$pair.Value) { throw "Summary $($pair.Key)=$($Matches[1]) expected=$($pair.Value)." }
    }

    $driverPassLine = [string](@($driverResult.StdOut -split "`r?`n" | Where-Object { $_ -like 'RTP BURST DRIVER: PASS*' } | Select-Object -Last 1)[0])
    $driverJson = $driverPassLine.Substring('RTP BURST DRIVER: PASS '.Length) | ConvertFrom-Json
    $totalMxfBytes = ($files | Measure-Object -Property Length -Sum).Sum
    [ordered]@{schema='audio-system.event-rtp-burst-test.v1';passed=$true;leg_count=$LegCount;ring_seconds=$RingSeconds;expected_packets=$expectedPackets;payload_bytes_per_leg=$expectedPayloadBytes;total_payload_bytes=[int64]$expectedPayloadBytes*[int64]$LegCount;mxf_count=$files.Count;total_mxf_bytes=[int64]$totalMxfBytes;driver=$driverJson;recording_root=$recordingRoot;audit=$audit} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    Write-Host ('EVENT RTP BURST E2E: PASS files={0} seconds={1} packets={2} stream_elapsed_ms={3} max_schedule_lateness_ms={4} root={5}' -f $files.Count,$RingSeconds,$expectedPackets,$driverJson.stream_elapsed_ms,$driverJson.max_schedule_lateness_ms,$recordingRoot) -ForegroundColor Green
} finally {
    if (-not $recorder.Process.HasExited) {
        try { Set-Content -LiteralPath $shutdown -Value 'shutdown' -Encoding ascii; [void]$recorder.Process.WaitForExit(10000) } catch {}
        if (-not $recorder.Process.HasExited) { try { $recorder.Process.Kill() } catch {} }
    }
}
