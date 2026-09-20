param(
    [Parameter(Mandatory=$true)][string]$ClientManifest,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\recorder\Common-Recorder.ps1')

if (-not (Test-Path -LiteralPath $ClientManifest)) { throw "Client manifest not found: $ClientManifest" }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$manifest = Get-Content -Raw -LiteralPath $ClientManifest | ConvertFrom-Json
$clients = @($manifest.clients)
if ($clients.Count -lt 2) { throw 'Multi-CWP simulator requires at least two clients.' }

$root = Get-ProjectRoot
$scriptPath = Join-Path $PSScriptRoot 'Invoke-RadioPersistentSessionSimulator.ps1'
$psExe = (Get-Command powershell.exe).Source
$running = @()
foreach ($c in $clients) {
    $name = [string]$c.name
    $stdout = Join-Path $OutputDirectory ($name + '-stdout.txt')
    $stderr = Join-Path $OutputDirectory ($name + '-stderr.txt')
    $args = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath,
        '-LocalIp',[string]$c.local_ip,
        '-RecorderIp',[string]$c.recorder_ip,
        '-RtspPort',[string]$c.rtsp_port,
        '-RecorderRtpPort',[string]$c.recorder_rtp_port,
        '-LocalRtpPort',[string]$c.local_rtp_port,
        '-EndpointId',[string]$c.endpoint_id,
        '-ServiceId',[string]$c.service_id,
        '-Direction',[string]$c.direction,
        '-BurstCount',[string]$c.burst_count,
        '-BurstMs',[string]$c.burst_ms,
        '-SilenceMs',[string]$c.silence_ms,
        '-KeepaliveIntervalMs',[string]$c.keepalive_interval_ms,
        '-PausedProbePackets',[string]$c.paused_probe_packets
    )
    $handle = Start-NativeProcessRedirected -FilePath $psExe -Arguments $args -StdOutPath $stdout -StdErrPath $stderr -WorkingDirectory $root
    $running += [pscustomobject]@{Name=$name;Handle=$handle}
}

$failures = @()
foreach ($r in $running) {
    $result = Complete-NativeProcessRedirected -Handle $r.Handle -TimeoutMs 45000
    if ($result.ExitCode -ne 0 -or [string]$result.StdOut -notmatch 'RADIO PERSISTENT SIMULATOR: PASS') {
        $failures += [pscustomobject]@{name=$r.Name;exit_code=$result.ExitCode;stderr=[string]$result.StdErr;stdout=[string]$result.StdOut}
    }
}

$summary = [ordered]@{
    schema='recorder-poc.phase5.multi-cwp-simulator.v1'
    clients=$clients.Count
    passed=$clients.Count-$failures.Count
    failed=$failures.Count
    failures=$failures
}
$summaryPath = Join-Path $OutputDirectory 'multi-cwp-simulator-report.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
if ($failures.Count -gt 0) {
    Write-Error "MULTI-CWP SIMULATOR: FAIL ($($failures.Count)/$($clients.Count)) report=$summaryPath"
    exit 7
}
Write-Host "MULTI-CWP SIMULATOR: PASS clients=$($clients.Count) report=$summaryPath" -ForegroundColor Green
