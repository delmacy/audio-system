param(
    [Parameter(Mandatory=$true)]
    [string]$ScenarioPath,
    [string]$RecorderState = '',
    [string]$LocalIp = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\recorder\Common-Recorder.ps1')

$root = Get-ProjectRoot
$planner = Join-Path $PSScriptRoot 'audio_scenario.py'
$simulator = Join-Path $PSScriptRoot '..\cwp\Invoke-ServiceMonoSessionSimulator.ps1'
if (-not (Test-Path -LiteralPath $planner)) { throw "Tone scenario planner not found: $planner" }
if (-not (Test-Path -LiteralPath $simulator)) { throw "Session simulator not found: $simulator" }
if (-not (Test-Path -LiteralPath $ScenarioPath)) { throw "Scenario not found: $ScenarioPath" }

if (-not $RecorderState) {
    $current = Join-Path $root 'runs\operational-recorder\current-run.txt'
    if (-not (Test-Path -LiteralPath $current)) { throw 'No current recorder run is registered.' }
    $runDir = (Get-Content -LiteralPath $current -Raw).Trim()
    $RecorderState = Join-Path $runDir 'operational-recorder-state.json'
}
if (-not (Test-Path -LiteralPath $RecorderState)) { throw "Recorder state not found: $RecorderState" }

$state = Get-Content -LiteralPath $RecorderState -Raw | ConvertFrom-Json
$recorderIp = [string]$state.rtsp_ip
$rtspPort = [int]$state.rtsp_port
if (-not $recorderIp) { throw 'Recorder state does not expose rtsp_ip.' }
if ($rtspPort -le 0) { throw 'Recorder state does not expose a valid rtsp_port.' }

if (-not $LocalIp) {
    if ($recorderIp -eq '127.0.0.1' -or $recorderIp -eq '::1') {
        $LocalIp = '127.0.0.1'
    } else {
        $profile = Read-IniFile (Join-Path $root 'config\profiles\local-poc.ini')
        $LocalIp = [string]$profile['cwp-a']['ip_start']
    }
}

$executionDir = Join-Path $root ('runs\tone-scenario\' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
New-Item -ItemType Directory -Force -Path $executionDir | Out-Null
$resolvedPath = Join-Path $executionDir 'resolved-scenario.json'

& python $planner '--scenario' $ScenarioPath '--output' $resolvedPath | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $resolvedPath)) {
    throw 'Tone scenario resolution failed.'
}
$resolved = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json
$recorderTracks = @($state.tracks)
if ($recorderTracks.Count -le 0) { throw 'Recorder state contains no tracks.' }

function Get-ObjectProperty {
    param($Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Find-RecorderTrack {
    param($Definition)
    $matches = @()
    $logical = Get-ObjectProperty $Definition 'logical_track_uuid'
    $routeSelector = Get-ObjectProperty $Definition 'route_key'
    $trackIndex = Get-ObjectProperty $Definition 'track_index'
    $category = Get-ObjectProperty $Definition 'category'
    $endpoint = Get-ObjectProperty $Definition 'endpoint_id'
    $service = Get-ObjectProperty $Definition 'service_id'

    if ($logical) {
        $matches = @($recorderTracks | Where-Object {
            [string](Get-ObjectProperty $_ 'logical_track_uuid') -eq [string]$logical
        })
    } elseif ($routeSelector) {
        $matches = @($recorderTracks | Where-Object {
            $route = Get-ObjectProperty $_ 'route_key'
            if (-not $route) { $route = Get-ObjectProperty $_ 'route' }
            [string]$route -eq [string]$routeSelector
        })
    } elseif ($null -ne $trackIndex -and $category) {
        $matches = @($recorderTracks | Where-Object {
            [string](Get-ObjectProperty $_ 'category') -eq [string]$category -and
            [int](Get-ObjectProperty $_ 'track_index') -eq [int]$trackIndex
        })
    } elseif ($endpoint -and $service) {
        $matches = @($recorderTracks | Where-Object {
            [string](Get-ObjectProperty $_ 'endpoint_id') -eq [string]$endpoint -and
            [string](Get-ObjectProperty $_ 'service_id') -eq [string]$service
        })
    } else {
        throw 'Each scenario track must select a recorder track by logical_track_uuid, route_key, category+track_index, or endpoint_id+service_id.'
    }
    if ($matches.Count -ne 1) {
        throw "Scenario selector resolved to $($matches.Count) recorder tracks; exactly one is required."
    }
    return $matches[0]
}

$powerShell = (Get-Command powershell.exe).Source
$running = @()
$ordinal = 0

foreach ($definition in @($resolved.tracks)) {
    $target = Find-RecorderTrack $definition
    $routeKey = Get-ObjectProperty $target 'route_key'
    if (-not $routeKey) { $routeKey = Get-ObjectProperty $target 'route' }
    $routeKey = [string]$routeKey
    if (-not $routeKey) { throw 'Selected recorder track has no route key.' }

    $schedulePath = Join-Path $executionDir ('schedule-' + $ordinal + '.json')
    [ordered]@{
        schema='audio-system.tone-track-schedule.v1'
        seed=[int64]$definition.seed
        mode=[string]$definition.mode
        audio_format=$definition.audio_format
        start_offset_ms=[int]$definition.start_offset_ms
        bursts=@($definition.bursts)
        expected_intervals=@($definition.expected_intervals)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $schedulePath -Encoding utf8

    $stdout = Join-Path $executionDir ('track-' + $ordinal + '-stdout.txt')
    $stderr = Join-Path $executionDir ('track-' + $ordinal + '-stderr.txt')
    $localRtpPort = 22000 + ($ordinal * 2)
    $serviceType = Get-ObjectProperty $target 'service_type'
    if (-not $serviceType) { $serviceType = Get-ObjectProperty $target 'category' }
    if (-not $serviceType) { $serviceType = 'radio' }
    $serviceType = [string]$serviceType

    $args = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$simulator,
        '-LocalIp',$LocalIp,
        '-RecorderIp',$recorderIp,
        '-RtspPort',[string]$rtspPort,
        '-RecorderRtpPort',[string](Get-ObjectProperty $target 'rtp_port'),
        '-LocalRtpPort',[string]$localRtpPort,
        '-EndpointId',[string](Get-ObjectProperty $target 'endpoint_id'),
        '-ServiceId',[string](Get-ObjectProperty $target 'service_id'),
        '-ServiceType',$serviceType,
        '-MediaFlow','mono',
        '-PausedProbePackets','0',
        '-ToneHz',[string]$definition.frequency_hz,
        '-ToneLevelDbfs',[string]$definition.level_dbfs,
        '-ScheduleFile',$schedulePath,
        '-RouteKey',$routeKey
    )

    Write-Host ("TRACK {0}: {1} mode={2} tone={3}Hz start={4}ms seed={5}" -f
        $ordinal,$routeKey,$definition.mode,$definition.frequency_hz,$definition.start_offset_ms,$definition.seed) -ForegroundColor Cyan

    $handle = Start-NativeProcessRedirected -FilePath $powerShell -Arguments $args -StdOutPath $stdout -StdErrPath $stderr -WorkingDirectory $root
    $running += [pscustomobject]@{
        ordinal=$ordinal
        target=$target
        definition=$definition
        schedule=$schedulePath
        handle=$handle
    }
    $ordinal++
}

$timeoutMs = ([int]$resolved.duration_ms + 30000)
$results = @()
$failures = 0
foreach ($item in $running) {
    $result = Complete-NativeProcessRedirected -Handle $item.handle -TimeoutMs $timeoutMs
    $ok = $result.ExitCode -eq 0 -and [string]$result.StdOut -match 'SERVICE MONO SIMULATOR: PASS'
    if (-not $ok) { $failures++ }
    $reportedRoute = Get-ObjectProperty $item.target 'route_key'
    if (-not $reportedRoute) { $reportedRoute = Get-ObjectProperty $item.target 'route' }
    $results += [ordered]@{
        ordinal=$item.ordinal
        logical_track_uuid=[string](Get-ObjectProperty $item.target 'logical_track_uuid')
        route_key=[string]$reportedRoute
        mode=[string]$item.definition.mode
        frequency_hz=[double]$item.definition.frequency_hz
        start_offset_ms=[int]$item.definition.start_offset_ms
        seed=[int64]$item.definition.seed
        schedule=$item.schedule
        success=$ok
        exit_code=$result.ExitCode
        stdout=[string]$result.StdOut
        stderr=[string]$result.StdErr
    }
}

$reportPath = Join-Path $executionDir 'tone-scenario-report.json'
[ordered]@{
    schema='audio-system.tone-scenario-execution.v1'
    generated_utc=[DateTime]::UtcNow.ToString('o')
    scenario=(Resolve-Path $ScenarioPath).Path
    resolved_scenario=$resolvedPath
    recorder_state=(Resolve-Path $RecorderState).Path
    duration_ms=[int]$resolved.duration_ms
    audio_format=$resolved.audio_format
    seed=[int64]$resolved.seed
    track_count=@($resolved.tracks).Count
    success=($failures -eq 0)
    results=$results
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8

if ($failures -gt 0) { throw "Tone scenario failed on $failures track(s). Report: $reportPath" }
Write-Host ("TONE SCENARIO: PASS tracks={0} duration={1}ms seed={2}" -f @($resolved.tracks).Count,$resolved.duration_ms,$resolved.seed) -ForegroundColor Green
Write-Host ("Resolved: " + $resolvedPath)
Write-Host ("Report:   " + $reportPath)
