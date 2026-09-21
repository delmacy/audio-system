param(
    [int]$MediaMs = 9000
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
$runDir = Join-Path $root ('runs\operational-recorder\' + $stamp)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$final = Join-Path $runDir 'ci-growing-shared.mxf'
$partial = $final + '.partial'
$lock = $final + '.lock'
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$stdout = Join-Path $runDir 'recorder-stdout.txt'
$stderr = Join-Path $runDir 'recorder-stderr.txt'
$shutdown = Join-Path $runDir 'shutdown.signal'
$sessionMap = Join-Path $runDir 'session-map.tsv'
$statePath = Join-Path $runDir 'operational-recorder-state.json'
$fileId = 'CI-GROWING-' + [Guid]::NewGuid().ToString()
$windowStart = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:00:00.000Z')
$tab = [char]9

$tracks = @(
    [ordered]@{
        endpoint='CI-CWP-01'; service='121500'; route='/record/CI-CWP-01/radio-121500';
        rtp=20500; local_rtp=21500; logical=[Guid]::NewGuid().ToString(); instance=[Guid]::NewGuid().ToString();
        track_index=0; tone_hz=440
    },
    [ordered]@{
        endpoint='CI-CWP-02'; service='118700'; route='/record/CI-CWP-02/radio-118700';
        rtp=20501; local_rtp=21501; logical=[Guid]::NewGuid().ToString(); instance=[Guid]::NewGuid().ToString();
        track_index=1; tone_hz=660
    },
    [ordered]@{
        endpoint='CI-CWP-03'; service='119900'; route='/record/CI-CWP-03/radio-119900';
        rtp=20502; local_rtp=21502; logical=[Guid]::NewGuid().ToString(); instance=[Guid]::NewGuid().ToString();
        track_index=2; tone_hz=880
    }
)

$header = @(
    'route_key','endpoint_id','service_id','media_flow','activity_signal','display_name',
    'logical_uuid','instance_uuid','file_id','output_partial','output_final','lock_path',
    'rtp_port','window_start_utc','segment_sequence','session_kind'
) -join $tab
$rows = @($header)
foreach ($track in $tracks) {
    $rows += (@(
        $track.route,$track.endpoint,$track.service,'mono','squ',
        ('CI RADIO ' + $track.service),$track.logical,$track.instance,$fileId,
        $partial,$final,$lock,[string]$track.rtp,$windowStart,'0','radio'
    ) -join $tab)
}
[IO.File]::WriteAllLines($sessionMap,[string[]]$rows,(New-Object Text.UTF8Encoding($false)))

$stateTracks = @()
foreach ($track in $tracks) {
    $stateTracks += [ordered]@{
        category='radio'
        service_type='radio'
        service_id=$track.service
        endpoint_id=$track.endpoint
        logical_track_uuid=$track.logical
        track_instance_uuid=$track.instance
        file_id=$fileId
        final_mxf=$final
        track_index=[int]$track.track_index
        route_key=$track.route
        rtp_port=[int]$track.rtp
    }
}
$state = [ordered]@{
    schema='audio-system.ci-growing-mxf.v1'
    status='RECORDING'
    scope='shared_category_mxf'
    started_utc=[DateTime]::UtcNow.ToString('o')
    run_dir=$runDir
    shared_mxf=$true
    files=[ordered]@{
        radio=[ordered]@{
            category='radio';file_id=$fileId;path=$final;partial=$partial;lock=$lock;track_count=3
        }
    }
    tracks=$stateTracks
    audit=$audit
}
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8
Set-Content -LiteralPath (Join-Path $root 'runs\operational-recorder\current-run.txt') -Value $runDir -Encoding utf8

$recorderArgs = @(
    '--bind-ip','127.0.0.1',
    '--rtsp-port','8554',
    '--session-map',$sessionMap,
    '--audit',$audit,
    '--ready-file',$ready,
    '--plugin-dll',$plugin,
    '--recorder-id','RECORDER-CI-GROWING',
    '--max-seconds','30',
    '--shared-mxf-by-output',
    '--shutdown-watch-file',$shutdown
)
$recorder = Start-NativeProcessRedirected -FilePath $exe -Arguments $recorderArgs -StdOutPath $stdout -StdErrPath $stderr -WorkingDirectory $root

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($recorder.Process.HasExited) {
            throw "Recorder exited before READY with code $($recorder.Process.ExitCode)"
        }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Recorder did not reach READY.' }
        Start-Sleep -Milliseconds 100
    }

    $scenarioPath = Join-Path $runDir 'ci-tone-scenario.json'
    $resolvedScenarioPath = Join-Path $runDir 'ci-tone-scenario-resolved.json'
    [ordered]@{
        schema='audio-system.tone-scenario.v1'
        duration_ms=$MediaMs
        seed=48291
        tracks=@(
            [ordered]@{
                logical_track_uuid=$tracks[0].logical
                mode='continuous'
                frequency_hz=440
                level_dbfs=-12
            },
            [ordered]@{
                logical_track_uuid=$tracks[1].logical
                mode='pulsed'
                frequency_hz=660
                level_dbfs=-12
                start_offset_ms=300
                on_ms=700
                off_ms=500
            },
            [ordered]@{
                logical_track_uuid=$tracks[2].logical
                mode='random_pulsed'
                frequency_hz=880
                level_dbfs=-12
                random_start=[ordered]@{min_ms=0;max_ms=800}
                random_on=[ordered]@{min_ms=300;max_ms=1200}
                random_off=[ordered]@{min_ms=200;max_ms=900}
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $scenarioPath -Encoding utf8

    $planner = Join-Path $root 'scripts\generator\audio_scenario.py'
    & python $planner '--scenario' $scenarioPath '--output' $resolvedScenarioPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CI tone scenario resolution failed.' }
    $resolvedScenario = Get-Content -LiteralPath $resolvedScenarioPath -Raw | ConvertFrom-Json

    $simulator = Join-Path $root 'scripts\cwp\Invoke-ServiceMonoSessionSimulator.ps1'
    $powershell = (Get-Command powershell.exe).Source
    $running = @()
    foreach ($track in $tracks) {
        $definition = @($resolvedScenario.tracks | Where-Object {
            [string]$_.logical_track_uuid -eq [string]$track.logical
        }) | Select-Object -First 1
        if (-not $definition) { throw "Resolved tone schedule missing for track $($track.track_index)." }
        $schedulePath = Join-Path $runDir ('schedule-' + $track.track_index + '.json')
        [ordered]@{
            schema='audio-system.tone-track-schedule.v1'
            seed=[int64]$definition.seed
            mode=[string]$definition.mode
            start_offset_ms=[int]$definition.start_offset_ms
            bursts=@($definition.bursts)
            expected_intervals=@($definition.expected_intervals)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $schedulePath -Encoding utf8
        $simOut = Join-Path $runDir ('sim-' + $track.track_index + '-stdout.txt')
        $simErr = Join-Path $runDir ('sim-' + $track.track_index + '-stderr.txt')
        $simArgs = @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',$simulator,
            '-LocalIp','127.0.0.1',
            '-RecorderIp','127.0.0.1',
            '-RtspPort','8554',
            '-RecorderRtpPort',[string]$track.rtp,
            '-LocalRtpPort',[string]$track.local_rtp,
            '-EndpointId',$track.endpoint,
            '-ServiceId',$track.service,
            '-ServiceType','radio',
            '-MediaFlow','mono',
            '-KeepaliveIntervalMs','100',
            '-PausedProbePackets','0',
            '-ToneHz',[string]$definition.frequency_hz,
            '-ToneLevelDbfs',[string]$definition.level_dbfs,
            '-ScheduleFile',$schedulePath,
            '-RouteKey',$track.route
        )
        $handle = Start-NativeProcessRedirected -FilePath $powershell -Arguments $simArgs -StdOutPath $simOut -StdErrPath $simErr -WorkingDirectory $root
        $running += [pscustomobject]@{ track=$track; handle=$handle }
    }

    $first = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    while (-not $first) {
        if ($recorder.Process.HasExited) { throw 'Recorder exited before publishing a read-safe watermark.' }
        if (Test-Path -LiteralPath $lock) {
            try {
                $candidate = Get-Content -LiteralPath $lock -Raw | ConvertFrom-Json
                if ($candidate.read_safe -and [uint64]$candidate.committed_position_ns -gt 0 -and
                    [uint64]$candidate.flushed_bytes -gt 0) {
                    $first = $candidate
                }
            } catch {}
        }
        if (-not $first) {
            if ([DateTime]::UtcNow -gt $deadline) { throw 'Timed out waiting for first growing-MXF watermark.' }
            Start-Sleep -Milliseconds 100
        }
    }

    if (-not (Test-Path -LiteralPath $partial)) { throw 'Growing MXF partial does not exist at first watermark.' }
    if (Test-Path -LiteralPath $final) { throw 'Final MXF exists before EOS; growing test is not exercising an open file.' }
    if ($recorder.Process.HasExited) { throw 'Recorder is not alive during growing playback probe.' }

    $probe = Join-Path $root 'scripts\player\growing_mxf_live_probe.py'
    $probe1 = Join-Path $runDir 'probe-first.wav'
    & python $probe '--logical-track-uuid' $tracks[0].logical '--output' $probe1 '--min-generation' ([string]$first.commit_generation)
    if ($LASTEXITCODE -ne 0) { throw 'First growing-MXF playback probe failed.' }

    $second = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    while (-not $second) {
        if ($recorder.Process.HasExited) { throw 'Recorder exited before watermark advancement could be observed.' }
        try {
            $candidate = Get-Content -LiteralPath $lock -Raw | ConvertFrom-Json
            if ([uint64]$candidate.commit_generation -gt [uint64]$first.commit_generation -and
                [uint64]$candidate.committed_position_ns -gt [uint64]$first.committed_position_ns) {
                $second = $candidate
            }
        } catch {}
        if (-not $second) {
            if ([DateTime]::UtcNow -gt $deadline) { throw 'Growing-MXF watermark did not advance.' }
            Start-Sleep -Milliseconds 100
        }
    }

    $probe2 = Join-Path $runDir 'probe-second.wav'
    & python $probe '--logical-track-uuid' $tracks[1].logical '--output' $probe2 '--min-generation' ([string]$second.commit_generation)
    if ($LASTEXITCODE -ne 0) { throw 'Second growing-MXF playback probe failed.' }

    if ((Get-Item -LiteralPath $probe2).Length -le (Get-Item -LiteralPath $probe1).Length) {
        Write-Host 'NOTE: per-track WAV lengths are not ordered; watermark advancement is asserted directly.' -ForegroundColor Yellow
    }

    foreach ($item in $running) {
        $result = Complete-NativeProcessRedirected -Handle $item.handle -TimeoutMs 20000
        if ($result.ExitCode -ne 0 -or [string]$result.StdOut -notmatch 'SERVICE MONO SIMULATOR: PASS') {
            throw "Simulator failed for track $($item.track.track_index): exit=$($result.ExitCode) stderr=$($result.StdErr)"
        }
    }

    Set-Content -LiteralPath $shutdown -Value 'shutdown' -Encoding ascii
    $recorderResult = Complete-NativeProcessRedirected -Handle $recorder -TimeoutMs 30000
    if ($recorderResult.ExitCode -ne 0) {
        throw "Recorder finalization failed: exit=$($recorderResult.ExitCode) stderr=$($recorderResult.StdErr)"
    }

    if (-not (Test-Path -LiteralPath $final)) { throw 'Final MXF was not promoted after graceful shutdown.' }
    if (Test-Path -LiteralPath $partial) { throw 'Partial MXF still exists after graceful finalization.' }
    if (Test-Path -LiteralPath $lock) { throw 'Lock sidecar still exists after graceful finalization.' }

    $lab = @(
        (Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),
        (Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $lab) { throw 'mxf-lab.exe was not built.' }

    & $lab inspect $final '--expected-tracks' '3' '--timeout-ms' '15000'
    if ($LASTEXITCODE -ne 0) { throw 'Final shared MXF structural inspection failed.' }

    Write-Host ('GROWING MXF E2E: PASS first_generation={0} second_generation={1} first_ns={2} second_ns={3} final={4}' -f
        $first.commit_generation,$second.commit_generation,$first.committed_position_ns,$second.committed_position_ns,$final) -ForegroundColor Green
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
