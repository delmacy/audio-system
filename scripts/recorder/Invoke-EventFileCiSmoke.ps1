param(
    [int]$CallMs = 2400,
    [int]$AnswerAfterMs = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')

$root = Get-ProjectRoot
$exe = Find-RecorderHostExe
if (-not $exe) { throw 'recorder-host.exe was not built.' }
$plugin = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path -LiteralPath $plugin)) { throw 'gstmxfidentity.dll was not built.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ('runs\event-recorder\' + $stamp)
$recordingRoot = Join-Path $runDir 'recordings'
New-Item -ItemType Directory -Force -Path $runDir,$recordingRoot | Out-Null

$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$stdout = Join-Path $runDir 'recorder-stdout.txt'
$stderr = Join-Path $runDir 'recorder-stderr.txt'
$shutdown = Join-Path $runDir 'shutdown.signal'
$sessionMap = Join-Path $runDir 'session-map.tsv'
$interactionId = [Guid]::NewGuid().ToString()
$serviceId = 'OPS-TEL'
$tab = [char]9

$legs = @(
    [ordered]@{
        endpoint='CI-CWP-01'; route='/record/CI-CWP-01/tel-ops-tel';
        rtp=22500; local_rtp=23500;
        logical=[Guid]::NewGuid().ToString(); instance=[Guid]::NewGuid().ToString();
        leg=[Guid]::NewGuid().ToString(); tone=440; answer=$false
    },
    [ordered]@{
        endpoint='CI-CWP-02'; route='/record/CI-CWP-02/tel-ops-tel';
        rtp=22501; local_rtp=23501;
        logical=[Guid]::NewGuid().ToString(); instance=[Guid]::NewGuid().ToString();
        leg=[Guid]::NewGuid().ToString(); tone=660; answer=$true
    }
)

$header = @(
    'route_key','endpoint_id','service_id','media_flow','activity_signal','display_name',
    'logical_uuid','instance_uuid','file_id','output_partial','output_final','lock_path',
    'rtp_port','window_start_utc','segment_sequence','session_kind'
) -join $tab
$rows = @($header)
foreach ($leg in $legs) {
    $placeholder = Join-Path $runDir ('placeholder-' + $leg.endpoint + '.mxf')
    $rows += (@(
        $leg.route,$leg.endpoint,$serviceId,'mono','none',
        ('CI TELEPHONE ' + $leg.endpoint),$leg.logical,$leg.instance,
        ('PLACEHOLDER-' + $leg.endpoint),($placeholder + '.partial'),$placeholder,($placeholder + '.lock'),
        [string]$leg.rtp,[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:00:00.000Z'),'0','telephone'
    ) -join $tab)
}
[IO.File]::WriteAllLines($sessionMap,[string[]]$rows,(New-Object Text.UTF8Encoding($false)))

$recorderArgs = @(
    '--bind-ip','127.0.0.1',
    '--rtsp-port','8654',
    '--session-map',$sessionMap,
    '--audit',$audit,
    '--ready-file',$ready,
    '--plugin-dll',$plugin,
    '--recorder-id','RECORDER-CI-EVENT',
    '--max-seconds','30',
    '--event-files',
    '--recording-root',$recordingRoot,
    '--shutdown-watch-file',$shutdown
)
$recorder = Start-NativeProcessRedirected -FilePath $exe -Arguments $recorderArgs -StdOutPath $stdout -StdErrPath $stderr -WorkingDirectory $root

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($recorder.Process.HasExited) {
            throw "Event recorder exited before READY with code $($recorder.Process.ExitCode)"
        }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Event recorder did not reach READY.' }
        Start-Sleep -Milliseconds 100
    }

    $simulator = Join-Path $root 'scripts\cwp\Invoke-ServiceMonoSessionSimulator.ps1'
    $powershell = (Get-Command powershell.exe).Source
    $running = @()

    foreach ($leg in $legs) {
        $simOut = Join-Path $runDir ('sim-' + $leg.endpoint + '-stdout.txt')
        $simErr = Join-Path $runDir ('sim-' + $leg.endpoint + '-stderr.txt')
        $simArgs = @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',$simulator,
            '-LocalIp','127.0.0.1',
            '-RecorderIp','127.0.0.1',
            '-RtspPort','8654',
            '-RecorderRtpPort',[string]$leg.rtp,
            '-LocalRtpPort',[string]$leg.local_rtp,
            '-EndpointId',$leg.endpoint,
            '-ServiceId',$serviceId,
            '-ServiceType','telephone',
            '-MediaFlow','mono',
            '-BurstCount','1',
            '-BurstMs',[string]$CallMs,
            '-SilenceMs','0',
            '-PausedProbePackets','0',
            '-KeepaliveIntervalMs','100',
            '-ToneHz',[string]$leg.tone,
            '-ToneLevelDbfs','-12',
            '-RouteKey',$leg.route,
            '-InteractionId',$interactionId,
            '-LegId',$leg.leg,
            '-InitialAudioEvent','RING',
            '-NoPauseAfterBurst'
        )
        if ($leg.answer) {
            $simArgs += @('-AnswerAfterMs',[string]$AnswerAfterMs,'-SendHangupEvent')
        }
        $handle = Start-NativeProcessRedirected -FilePath $powershell -Arguments $simArgs -StdOutPath $simOut -StdErrPath $simErr -WorkingDirectory $root
        $running += [pscustomobject]@{ leg=$leg; handle=$handle }
    }

    foreach ($item in $running) {
        $result = Complete-NativeProcessRedirected -Handle $item.handle -TimeoutMs 30000
        if ($result.ExitCode -ne 0 -or [string]$result.StdOut -notmatch 'SERVICE MONO SIMULATOR: PASS') {
            throw "Event simulator failed for $($item.leg.endpoint): exit=$($result.ExitCode) stderr=$($result.StdErr)"
        }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        $finalFiles = @(Get-ChildItem -LiteralPath $recordingRoot -Filter '*.mxf' -File -Recurse -ErrorAction SilentlyContinue)
        $partials = @(Get-ChildItem -LiteralPath $recordingRoot -Filter '*.partial' -File -Recurse -ErrorAction SilentlyContinue)
        if ($finalFiles.Count -eq 2 -and $partials.Count -eq 0) { break }
        if ($recorder.Process.HasExited) {
            throw "Event recorder exited while waiting for event-file finalization. code=$($recorder.Process.ExitCode)"
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)

    $finalFiles = @(Get-ChildItem -LiteralPath $recordingRoot -Filter '*.mxf' -File -Recurse)
    if ($finalFiles.Count -ne 2) {
        throw "Expected exactly 2 event MXFs, got $($finalFiles.Count)."
    }
    if (@(Get-ChildItem -LiteralPath $recordingRoot -Filter '*.partial' -File -Recurse).Count -ne 0) {
        throw 'Event-file .partial remained after leg finalization.'
    }

    $events = @(
        Get-Content -LiteralPath $audit |
            Where-Object { $_.Trim() } |
            ForEach-Object { $_ | ConvertFrom-Json }
    )
    $opens = @($events | Where-Object { $_.event -eq 'EVENT_FILE_OPEN' })
    $answers = @($events | Where-Object { $_.event -eq 'ANSWER' })
    $closes = @($events | Where-Object { $_.event -eq 'EVENT_FILE_CLOSED' })
    $loserClosures = @($events | Where-Object {
        $_.event -eq 'EVENT_FILE_CLOSE_QUEUED' -and $_.event_state -eq 'RING_NOT_ANSWERED'
    })

    if ($opens.Count -ne 2) { throw "Expected 2 EVENT_FILE_OPEN records, got $($opens.Count)." }
    if ($answers.Count -ne 1) { throw "Expected 1 ANSWER record, got $($answers.Count)." }
    if ($loserClosures.Count -lt 1) { throw 'No sibling RING_NOT_ANSWERED closure was recorded.' }
    if ($closes.Count -lt 2) { throw "Expected at least 2 EVENT_FILE_CLOSED records, got $($closes.Count)." }

    foreach ($open in $opens) {
        if ([string]$open.interaction_id -ne $interactionId) {
            throw "Event file interaction mismatch: $($open.interaction_id)"
        }
        if (-not [string]$open.media_start_utc) {
            throw 'EVENT_FILE_OPEN missing media_start_utc.'
        }
        $mediaStart = [DateTimeOffset]::Parse([string]$open.media_start_utc)
        $expectedDir = $recordingRoot
        foreach ($part in @(
            $mediaStart.ToString('yyyy'),
            $mediaStart.ToString('MM'),
            $mediaStart.ToString('dd'),
            $mediaStart.ToString('HH'),
            $serviceId
        )) {
            $expectedDir = Join-Path $expectedDir $part
        }
        if (-not (Test-Path -LiteralPath $expectedDir)) {
            throw "Time/service directory missing: $expectedDir"
        }
        $legFile = @(Get-ChildItem -LiteralPath $expectedDir -Filter ('*_' + [string]$open.leg_id + '.mxf') -File)
        if ($legFile.Count -ne 1) {
            throw "Expected one file for leg $($open.leg_id) in $expectedDir, got $($legFile.Count)."
        }
    }

    $lab = @(
        (Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),
        (Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $lab) { throw 'mxf-lab.exe was not built.' }

    foreach ($file in $finalFiles) {
        & $lab inspect $file.FullName '--expected-tracks' '1' '--timeout-ms' '15000' '--expected-alaw-8k-mono'
        if ($LASTEXITCODE -ne 0) {
            throw "Event MXF structural inspection failed: $($file.FullName)"
        }
    }

    Set-Content -LiteralPath $shutdown -Value 'shutdown' -Encoding ascii
    $recorderResult = Complete-NativeProcessRedirected -Handle $recorder -TimeoutMs 30000
    if ($recorderResult.ExitCode -ne 0) {
        throw "Event recorder shutdown failed: exit=$($recorderResult.ExitCode) stderr=$($recorderResult.StdErr)"
    }

    Write-Host ('EVENT FILE E2E: PASS interaction={0} files={1} answer_events={2} loser_closures={3} root={4}' -f
        $interactionId,$finalFiles.Count,$answers.Count,$loserClosures.Count,$recordingRoot) -ForegroundColor Green
}
finally {
    if (-not $recorder.Process.HasExited) {
        try {
            Set-Content -LiteralPath $shutdown -Value 'shutdown' -Encoding ascii
            [void]$recorder.Process.WaitForExit(10000)
        } catch {}
        if (-not $recorder.Process.HasExited) {
            try { $recorder.Process.Kill() } catch {}
        }
    }
}
