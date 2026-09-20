param([switch]$ForceBuild)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\recorder\Common-Recorder.ps1')
. (Join-Path $PSScriptRoot '..\mxf\Track-Identity.ps1')

$root = Get-ProjectRoot
$source = Join-Path $root 'src\mxf-lab\mxf_lab.c'
$build = Join-Path $root 'scripts\mxf\Build-NativeMxfLab.ps1'
$exeCandidates = @(
    (Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),
    (Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')
)
$exe = $exeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$needsBuild = $ForceBuild -or -not $exe
if ($exe -and (Get-Item -LiteralPath $source).LastWriteTimeUtc -gt (Get-Item -LiteralPath $exe).LastWriteTimeUtc) { $needsBuild = $true }
if ($needsBuild) {
    Write-Host 'Building updated mxf-lab...' -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $build
    if ($LASTEXITCODE -ne 0) { throw 'mxf-lab build failed.' }
    $exe = $exeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $exe) { throw 'mxf-lab.exe not found after build.' }

$plugin = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path -LiteralPath $plugin)) { throw 'gstmxfidentity.dll missing. Build the MXF identity plugin first.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ('runs\operational-recorder\' + $stamp)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$mxf = Join-Path $runDir 'tone-multitrack.mxf'
$identityTsv = Join-Path $runDir 'track-identities.tsv'
$audit = Join-Path $runDir 'recorder-audit.jsonl'
$statePath = Join-Path $runDir 'operational-recorder-state.json'
$tab = [char]9

$definitions = @(
    [ordered]@{name='radio-121500';endpoint='CWP-TONE-01';service='121500';type='radio';frequency=440;track_index=0;intervals=@(@{start=0;duration=400},@{start=1000;duration=400},@{start=2000;duration=400},@{start=3000;duration=400})},
    [ordered]@{name='radio-118700';endpoint='CWP-TONE-02';service='118700';type='radio';frequency=440;track_index=1;intervals=@(@{start=500;duration=700},@{start=2100;duration=700},@{start=3700;duration=700})},
    [ordered]@{name='tel-050';endpoint='TEL-TONE-01';service='050';type='telephone';frequency=660;track_index=2;intervals=@(@{start=1200;duration=1000},@{start=3500;duration=1000})}
)

$baseUtc = [DateTime]::UtcNow
$tracks = @()
$identityRows = @()
$auditRows = New-Object System.Collections.Generic.List[string]
function IsoAt([int]$Milliseconds) { return $baseUtc.AddMilliseconds($Milliseconds).ToString('yyyy-MM-ddTHH:mm:ss.fffZ',[Globalization.CultureInfo]::InvariantCulture) }

foreach ($d in $definitions) {
    $identity = New-ServiceLogicalTrackIdentity -ServiceType $d.type -ServiceId $d.service -EndpointId $d.endpoint -MediaFlow 'mono'
    $durationMs = 0
    foreach ($interval in $d.intervals) { $durationMs += [int]$interval.duration }
    $identityRows += (@([string]$identity.display_name,[string]$identity.logical_track_uuid,[string]$identity.track_instance_uuid,[string]$d.frequency,[string]$durationMs) -join $tab)
    $tracks += [ordered]@{
        name=$d.name;endpoint_id=$d.endpoint;service_id=$d.service;service_type=$d.type;
        logical_track_uuid=[string]$identity.logical_track_uuid;track_instance_uuid=[string]$identity.track_instance_uuid;
        track_index=[int]$d.track_index;frequency_hz=[int]$d.frequency;final_mxf=$mxf;file_id=('TONE-SINGLE-MXF-' + $stamp)
    }
    foreach ($interval in $d.intervals) {
        $start = IsoAt ([int]$interval.start)
        $end = IsoAt ([int]$interval.start + [int]$interval.duration)
        $auditRows.Add(([ordered]@{ts_utc=$start;event='MEDIA_START';file_id=('TONE-SINGLE-MXF-' + $stamp);logical_track_uuid=[string]$identity.logical_track_uuid;track_instance_uuid=[string]$identity.track_instance_uuid;detail=('single_mxf track_index=' + $d.track_index)} | ConvertTo-Json -Compress))
        $auditRows.Add(([ordered]@{ts_utc=$end;event='MEDIA_END';file_id=('TONE-SINGLE-MXF-' + $stamp);logical_track_uuid=[string]$identity.logical_track_uuid;track_instance_uuid=[string]$identity.track_instance_uuid;detail=('single_mxf track_index=' + $d.track_index)} | ConvertTo-Json -Compress))
    }
    $closeAt = IsoAt 5000
    $auditRows.Add(([ordered]@{ts_utc=$closeAt;event='WINDOW_CLOSED_COMPLETE';file_id=('TONE-SINGLE-MXF-' + $stamp);logical_track_uuid=[string]$identity.logical_track_uuid;track_instance_uuid=[string]$identity.track_instance_uuid;detail=('single shared MXF closed track_index=' + $d.track_index)} | ConvertTo-Json -Compress))
    $auditRows.Add(([ordered]@{ts_utc=$closeAt;event='MEDIA_COMMIT';file_id=('TONE-SINGLE-MXF-' + $stamp);logical_track_uuid=[string]$identity.logical_track_uuid;track_instance_uuid=[string]$identity.track_instance_uuid;detail=('single shared MXF committed track_index=' + $d.track_index)} | ConvertTo-Json -Compress))
}

[IO.File]::WriteAllLines($identityTsv,[string[]]$identityRows,(New-Object Text.UTF8Encoding($false)))
Write-Host 'Creating ONE MXF with 3 logical audio tracks...' -ForegroundColor Cyan
& $exe write-identity --out $mxf --identity-file $identityTsv --plugin-dll $plugin --seconds 2
if ($LASTEXITCODE -ne 0) { throw ('mxf-lab write-identity failed with exit code ' + $LASTEXITCODE) }

Write-Host 'Inspecting shared MXF structure...' -ForegroundColor Cyan
& $exe inspect $mxf --expected-tracks 3 --timeout-ms 15000
if ($LASTEXITCODE -ne 0) { throw ('MXF structural inspection failed with exit code ' + $LASTEXITCODE) }

[IO.File]::WriteAllLines($audit,[string[]]$auditRows,(New-Object Text.UTF8Encoding($false)))
$state = [ordered]@{
    schema='audio-system.single-mxf-tone-lab.v1';status='CLOSED_COMPLETE';scope='single_mxf_multiple_logical_tracks';
    generated_utc=[DateTime]::UtcNow.ToString('o');run_dir=$runDir;file_id=('TONE-SINGLE-MXF-' + $stamp);
    final_mxf=$mxf;shared_mxf=$true;track_count=$tracks.Count;tracks=$tracks;audit=$audit
}
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8
Set-Content -LiteralPath (Join-Path $root 'runs\operational-recorder\current-run.txt') -Value $runDir -Encoding utf8

Write-Host ''
Write-Host 'SINGLE MXF TONE TEST: PASS' -ForegroundColor Green
Write-Host ('MXF: ' + $mxf)
Write-Host ('Tracks inside same file: ' + $tracks.Count)
foreach ($track in $tracks) { Write-Host ('  track_index=' + $track.track_index + ' ' + $track.endpoint_id + '/' + $track.service_id + ' ' + $track.frequency_hz + 'Hz') }
Write-Host ('State: ' + $statePath)
