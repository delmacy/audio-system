param(
    [Parameter(Mandatory=$true)][string]$Manifest,
    [string]$OutputDirectory = '',
    [string]$Ffmpeg = 'ffmpeg'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\recorder\Common-Recorder.ps1')

if (-not (Test-Path -LiteralPath $Manifest)) {
    throw "Injection manifest not found: $Manifest"
}

$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$manifestRoot = Split-Path -Parent $manifestPath
$config = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$tracks = @($config.tracks)

if ($tracks.Count -eq 0) {
    throw 'Injection manifest must contain at least one track.'
}

if (-not $OutputDirectory) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputDirectory = Join-Path (Get-ProjectRoot) "runs\audio-injection\$stamp"
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$ffmpegCommand = Get-Command $Ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpegCommand) {
    throw "FFmpeg was not found. Install it or pass -Ffmpeg <path>."
}

$simulator = Join-Path $PSScriptRoot '..\cwp\Invoke-ServiceMonoSessionSimulator.ps1'
$psExe = (Get-Command powershell.exe).Source
$prepared = @()
$portKeys = @{}

foreach ($track in $tracks) {
    $name = [string]$track.name
    if (-not $name) { throw 'Every track needs a name.' }

    $source = [string]$track.source_audio
    if (-not [IO.Path]::IsPathRooted($source)) {
        $source = Join-Path $manifestRoot $source
    }
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Source audio not found for ${name}: $source"
    }
    $source = (Resolve-Path -LiteralPath $source).Path

    $localRtpPort = [int]$track.local_rtp_port
    $recorderRtpPort = [int]$track.recorder_rtp_port
    $portKey = "$localRtpPort->$recorderRtpPort"
    if ($portKeys.ContainsKey($portKey)) {
        throw "Duplicate RTP port pair in manifest: $portKey"
    }
    $portKeys[$portKey] = $true

    $pcmaPath = Join-Path $OutputDirectory ($name + '.pcma')
    $ffmpegArgs = @(
        '-hide_banner','-loglevel','error','-y',
        '-i',$source,
        '-ac','1',
        '-ar','8000',
        '-f','alaw',
        $pcmaPath
    )

    Write-Host "Preparing $name -> $pcmaPath" -ForegroundColor Cyan
    & $ffmpegCommand.Source @ffmpegArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pcmaPath)) {
        throw "FFmpeg conversion failed for $name."
    }

    $prepared += [pscustomobject]@{
        name = $name
        source_audio = $source
        pcma_file = $pcmaPath
        local_ip = [string]$track.local_ip
        recorder_ip = [string]$track.recorder_ip
        rtsp_port = [int]$track.rtsp_port
        recorder_rtp_port = $recorderRtpPort
        local_rtp_port = $localRtpPort
        endpoint_id = [string]$track.endpoint_id
        service_id = [string]$track.service_id
        service_type = [string]$track.service_type
        media_flow = if ($track.PSObject.Properties.Name -contains 'media_flow') { [string]$track.media_flow } else { 'mono' }
        burst_count = if ($track.PSObject.Properties.Name -contains 'burst_count') { [int]$track.burst_count } else { 1 }
        burst_ms = if ($track.PSObject.Properties.Name -contains 'burst_ms') { [int]$track.burst_ms } else { 5000 }
        silence_ms = if ($track.PSObject.Properties.Name -contains 'silence_ms') { [int]$track.silence_ms } else { 200 }
        keepalive_interval_ms = if ($track.PSObject.Properties.Name -contains 'keepalive_interval_ms') { [int]$track.keepalive_interval_ms } else { 100 }
        paused_probe_packets = if ($track.PSObject.Properties.Name -contains 'paused_probe_packets') { [int]$track.paused_probe_packets } else { 0 }
    }
}

$running = @()
foreach ($track in $prepared) {
    $stdout = Join-Path $OutputDirectory ($track.name + '-stdout.txt')
    $stderr = Join-Path $OutputDirectory ($track.name + '-stderr.txt')
    $args = @(
        '-NoProfile','-ExecutionPolicy','Bypass',
        '-File',$simulator,
        '-LocalIp',$track.local_ip,
        '-RecorderIp',$track.recorder_ip,
        '-RtspPort',[string]$track.rtsp_port,
        '-RecorderRtpPort',[string]$track.recorder_rtp_port,
        '-LocalRtpPort',[string]$track.local_rtp_port,
        '-EndpointId',$track.endpoint_id,
        '-ServiceId',$track.service_id,
        '-ServiceType',$track.service_type,
        '-MediaFlow',$track.media_flow,
        '-BurstCount',[string]$track.burst_count,
        '-BurstMs',[string]$track.burst_ms,
        '-SilenceMs',[string]$track.silence_ms,
        '-KeepaliveIntervalMs',[string]$track.keepalive_interval_ms,
        '-PausedProbePackets',[string]$track.paused_probe_packets,
        '-PcmaFile',$track.pcma_file
    )

    Write-Host ("Injecting {0}: {1}/{2} from {3}" -f $track.name,$track.endpoint_id,$track.service_id,$track.source_audio) -ForegroundColor Yellow
    $handle = Start-NativeProcessRedirected -FilePath $psExe -Arguments $args -StdOutPath $stdout -StdErrPath $stderr -WorkingDirectory (Get-ProjectRoot)
    $running += [pscustomobject]@{ track=$track; handle=$handle; stdout=$stdout; stderr=$stderr }
}

$results = @()
foreach ($run in $running) {
    $result = Complete-NativeProcessRedirected -Handle $run.handle -TimeoutMs 120000
    $passed = $result.ExitCode -eq 0 -and [string]$result.StdOut -match 'SERVICE MONO SIMULATOR: PASS'
    $results += [pscustomobject]@{
        name = $run.track.name
        endpoint_id = $run.track.endpoint_id
        service_id = $run.track.service_id
        service_type = $run.track.service_type
        source_audio = $run.track.source_audio
        pcma_file = $run.track.pcma_file
        exit_code = $result.ExitCode
        passed = $passed
        stdout = [string]$result.StdOut
        stderr = [string]$result.StdErr
    }
}

$report = [ordered]@{
    schema = 'audio-system.multi-track-audio-injection.v1'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    tracks = $results
    passed = @($results | Where-Object passed).Count
    failed = @($results | Where-Object { -not $_.passed }).Count
}

$reportPath = Join-Path $OutputDirectory 'injection-report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($report.failed -gt 0) {
    Write-Error "MULTI TRACK AUDIO INJECTION: FAIL passed=$($report.passed) failed=$($report.failed) report=$reportPath"
    exit 7
}

Write-Host "MULTI TRACK AUDIO INJECTION: PASS tracks=$($report.passed) report=$reportPath" -ForegroundColor Green
