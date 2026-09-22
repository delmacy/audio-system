param(
    [int]$SessionCount = 1000,
    [int]$ReadyTimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')

if ($SessionCount -lt 1 -or $SessionCount -gt 1800) {
    throw 'SessionCount must be between 1 and 1800 for this Windows select()-based PoC.'
}

$root = Get-ProjectRoot
$exe = Find-RecorderHostExe
if (-not $exe) { throw 'recorder-host.exe was not built.' }
$plugin = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path -LiteralPath $plugin)) { throw 'gstmxfidentity.dll was not built.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ('runs\event-capacity\' + $stamp)
$recordingRoot = Join-Path $runDir 'recordings'
New-Item -ItemType Directory -Force -Path $runDir,$recordingRoot | Out-Null

$audit = Join-Path $runDir 'recorder-audit.jsonl'
$ready = Join-Path $runDir 'recorder-ready.json'
$stdout = Join-Path $runDir 'recorder-stdout.txt'
$stderr = Join-Path $runDir 'recorder-stderr.txt'
$shutdown = Join-Path $runDir 'shutdown.signal'
$sessionMap = Join-Path $runDir 'session-map.tsv'
$tab = [char]9
$rtspPort = 8754
$baseRtpPort = 24000

if (($baseRtpPort + $SessionCount - 1) -gt 65534) {
    throw 'Requested capacity exceeds available RTP port range.'
}

$header = @(
    'route_key','endpoint_id','service_id','media_flow','activity_signal','display_name',
    'logical_uuid','instance_uuid','file_id','output_partial','output_final','lock_path',
    'rtp_port','window_start_utc','segment_sequence','session_kind'
) -join $tab
$rows = New-Object 'System.Collections.Generic.List[string]'
$rows.Add($header)

$windowStart = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:00:00.000Z')
for ($i = 0; $i -lt $SessionCount; $i++) {
    $endpoint = 'CAP-CWP-{0:D4}' -f ($i + 1)
    $service = 'CAP-TEL'
    $route = '/record/{0}/tel-cap-tel' -f $endpoint
    $placeholder = Join-Path $runDir ('placeholder-' + $endpoint + '.mxf')
    $logical = [Guid]::NewGuid().ToString()
    $instance = [Guid]::NewGuid().ToString()
    $rows.Add((@(
        $route,$endpoint,$service,'mono','none',
        ('CAPACITY TELEPHONE ' + $endpoint),$logical,$instance,
        ('PLACEHOLDER-' + $endpoint),($placeholder + '.partial'),$placeholder,($placeholder + '.lock'),
        [string]($baseRtpPort + $i),$windowStart,'0','telephone'
    ) -join $tab))
}
[IO.File]::WriteAllLines($sessionMap,[string[]]$rows,(New-Object Text.UTF8Encoding($false)))

$recorderArgs = @(
    '--bind-ip','127.0.0.1',
    '--rtsp-port',[string]$rtspPort,
    '--session-map',$sessionMap,
    '--audit',$audit,
    '--ready-file',$ready,
    '--plugin-dll',$plugin,
    '--recorder-id','RECORDER-CI-EVENT-CAPACITY',
    '--max-seconds','30',
    '--event-files',
    '--recording-root',$recordingRoot,
    '--shutdown-watch-file',$shutdown
)

$watch = [Diagnostics.Stopwatch]::StartNew()
$recorder = Start-NativeProcessRedirected -FilePath $exe -Arguments $recorderArgs -StdOutPath $stdout -StdErrPath $stderr -WorkingDirectory $root
try {
    $deadline = [DateTime]::UtcNow.AddSeconds($ReadyTimeoutSeconds)
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($recorder.Process.HasExited) {
            $err = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw } else { '' }
            throw "Capacity recorder exited before READY code=$($recorder.Process.ExitCode) stderr=$err"
        }
        if ([DateTime]::UtcNow -gt $deadline) {
            throw "Capacity recorder did not arm $SessionCount routes within $ReadyTimeoutSeconds seconds."
        }
        Start-Sleep -Milliseconds 50
    }
    $watch.Stop()

    $state = Get-Content -LiteralPath $ready -Raw | ConvertFrom-Json
    if (-not $state.ready) { throw 'Capacity recorder READY file is not ready=true.' }
    if ([int]$state.session_count -ne $SessionCount) {
        throw "READY session_count=$($state.session_count), expected=$SessionCount."
    }
    if (@($state.sessions).Count -ne $SessionCount) {
        throw "READY sessions array count=$(@($state.sessions).Count), expected=$SessionCount."
    }

    $prematureMxf = @(Get-ChildItem -LiteralPath $recordingRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.mxf' -or $_.Name.EndsWith('.partial') })
    if ($prematureMxf.Count -ne 0) {
        throw "Event mode materialized $($prematureMxf.Count) media files before any event/RTP ingress."
    }

    Set-Content -LiteralPath $shutdown -Value 'shutdown' -Encoding ascii
    $result = Complete-NativeProcessRedirected -Handle $recorder -TimeoutMs 30000
    if ($result.ExitCode -ne 0) {
        throw "Capacity recorder shutdown failed: exit=$($result.ExitCode) stderr=$($result.StdErr)"
    }

    Write-Host ('EVENT ROUTE CAPACITY: PASS sessions={0} ready_ms={1} lazy_media_files=0' -f
        $SessionCount,[int]$watch.ElapsedMilliseconds) -ForegroundColor Green
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
