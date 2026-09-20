Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
. (Join-Path $PSScriptRoot 'Track-Identity.ps1')
Assert-GStreamerMxf

$runDir = Ensure-RunDirectory -Name 'mxf-identity'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$caseDir = Join-Path $runDir ('continuity-' + $stamp)
New-Item -ItemType Directory -Force -Path $caseDir | Out-Null

# Two adjacent recording fragments with deliberately different physical track orders.
# Shared semantic identities MUST retain the same LogicalTrackUUID.
$topology1 = @(
    [ordered]@{ service_type='radio'; service_id='121500'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='RADIO 121.500'; label='radio-121500-rx'; mid='r1' },
    [ordered]@{ service_type='radio'; service_id='121500'; endpoint_id='CWP-A17'; direction='TX'; sdp_service='RADIO 121.500'; label='radio-121500-tx'; mid='r2' },
    [ordered]@{ service_type='telephone'; service_id='TEL-01'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='TEL-01'; label='tel-01-rx'; mid='t1' },
    [ordered]@{ service_type='radio'; service_id='118100'; endpoint_id='CWP-A18'; direction='RX'; sdp_service='RADIO 118.100'; label='radio-118100-rx'; mid='r3' }
)
$topology2 = @(
    [ordered]@{ service_type='telephone'; service_id='TEL-01'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='TEL-01'; label='tel-01-rx'; mid='t1' },
    [ordered]@{ service_type='radio'; service_id='132700'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='RADIO 132.700'; label='radio-132700-rx'; mid='r4' },
    [ordered]@{ service_type='radio'; service_id='121500'; endpoint_id='CWP-A17'; direction='TX'; sdp_service='RADIO 121.500'; label='radio-121500-tx'; mid='r2' },
    [ordered]@{ service_type='radio'; service_id='121500'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='RADIO 121.500'; label='radio-121500-rx'; mid='r1' }
)

function Build-Map {
    param([object[]]$Topology,[int]$Version,[string]$FileId,[datetime]$ValidFrom,[datetime]$ValidTo)
    $rows = @()
    for ($i=0; $i -lt $Topology.Count; $i++) {
        $d = $Topology[$i]
        $id = New-LogicalTrackIdentity -ServiceType $d.service_type -ServiceId $d.service_id -EndpointId $d.endpoint_id -Direction $d.direction -SdpServiceNameRaw $d.sdp_service -SdpLabelRaw $d.label -SdpMidRaw $d.mid
        $rows += [ordered]@{
            topology_version = $Version
            file_id = $FileId
            track_index = $i + 1
            mxf_track_id = $i + 2 # current mxfmux reserves TrackID 1 for timecode
            logical_track_uuid = $id.logical_track_uuid
            track_instance_uuid = $id.track_instance_uuid
            track_name = $id.track_name
            display_name = $id.display_name
            canonical_identity = $id.canonical_identity
            service_type = $d.service_type
            service_id = $d.service_id
            endpoint_id = $d.endpoint_id
            direction = $d.direction
            sdp_service_name_raw = $d.sdp_service
            sdp_label_raw = $d.label
            sdp_mid_raw = $d.mid
            valid_from_utc = $ValidFrom.ToUniversalTime().ToString('o')
            valid_to_utc = $ValidTo.ToUniversalTime().ToString('o')
        }
        Start-Sleep -Milliseconds 1 # make UUIDv7 ordering visible in this spike
    }
    return @($rows)
}

$file1 = Join-Path $caseDir 'topology-v1.mxf'
$file2 = Join-Path $caseDir 'topology-v2.mxf'
$from1 = [datetime]::UtcNow
$to1 = $from1.AddHours(1)
$from2 = $to1
$to2 = $from2.AddHours(1)
$fileId1 = 'FILE-' + (New-UuidV7).ToString()
$fileId2 = 'FILE-' + (New-UuidV7).ToString()

Write-Host '=== Logical Track Continuity Gate ==='
Write-Host 'Writing topology v1...'
& (Join-Path $PSScriptRoot 'Invoke-GstMxf.ps1') -Tracks $topology1.Count -Seconds 2 -Output $file1 | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'Writing topology v2 with reordered/added/removed tracks...'
& (Join-Path $PSScriptRoot 'Invoke-GstMxf.ps1') -Tracks $topology2.Count -Seconds 2 -Output $file2 | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$map1 = Build-Map -Topology $topology1 -Version 1 -FileId $fileId1 -ValidFrom $from1 -ValidTo $to1
$map2 = Build-Map -Topology $topology2 -Version 2 -FileId $fileId2 -ValidFrom $from2 -ValidTo $to2

$ffprobe = Find-Executable @('ffprobe.exe','ffprobe')
if (-not $ffprobe) { throw 'ffprobe is required for this gate.' }
function Get-AudioCount([string]$Path) {
    $json = & $ffprobe -v error -select_streams a -show_entries stream=index -of json $Path
    if ($LASTEXITCODE -ne 0) { throw "ffprobe failed: $Path" }
    return @((($json | Out-String | ConvertFrom-Json).streams)).Count
}
$count1 = Get-AudioCount $file1
$count2 = Get-AudioCount $file2

# Persist the exact map that a later SQLite recording_track table will contain.
$manifest1 = [ordered]@{
    schema='recorder-poc.track-map.v2'; file=$file1; file_id=$fileId1; topology_version=1;
    valid_from_utc=$from1.ToString('o'); valid_to_utc=$to1.ToString('o'); tracks=$map1
}
$manifest2 = [ordered]@{
    schema='recorder-poc.track-map.v2'; file=$file2; file_id=$fileId2; topology_version=2;
    valid_from_utc=$from2.ToString('o'); valid_to_utc=$to2.ToString('o'); tracks=$map2
}
$manifest1 | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath ($file1 + '.tracks.json')
$manifest2 | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath ($file2 + '.tracks.json')

$byLogical1 = @{}
foreach ($r in $map1) { $byLogical1[$r.logical_track_uuid] = $r }
$byLogical2 = @{}
foreach ($r in $map2) { $byLogical2[$r.logical_track_uuid] = $r }

$events = @()
foreach ($uuid in $byLogical1.Keys) {
    if ($byLogical2.ContainsKey($uuid)) {
        $a = $byLogical1[$uuid]; $b = $byLogical2[$uuid]
        if ($a.track_index -ne $b.track_index) {
            $events += [ordered]@{ event='TRACK_RELOCATED'; logical_track_uuid=$uuid; display_name=$a.display_name; from_track_index=$a.track_index; to_track_index=$b.track_index; from_topology=1; to_topology=2 }
        }
    } else {
        $a = $byLogical1[$uuid]
        $events += [ordered]@{ event='TRACK_REMOVED'; logical_track_uuid=$uuid; display_name=$a.display_name; from_track_index=$a.track_index; from_topology=1; to_topology=2 }
    }
}
foreach ($uuid in $byLogical2.Keys) {
    if (-not $byLogical1.ContainsKey($uuid)) {
        $b = $byLogical2[$uuid]
        $events += [ordered]@{ event='TRACK_ADDED'; logical_track_uuid=$uuid; display_name=$b.display_name; to_track_index=$b.track_index; from_topology=1; to_topology=2 }
    }
}

$eventPath = Join-Path $caseDir 'topology-events.jsonl'
$events | ForEach-Object { ($_ | ConvertTo-Json -Compress -Depth 6) } | Set-Content -Encoding UTF8 -LiteralPath $eventPath

# Player resolution proof: concatenate physical segments by LogicalTrackUUID, never by TrackIndex.
$all = @($map1) + @($map2)
$playerRows = @()
foreach ($g in ($all | Group-Object logical_track_uuid)) {
    $segments = @($g.Group | Sort-Object valid_from_utc | ForEach-Object {
        [ordered]@{ file_id=$_.file_id; track_index=$_.track_index; topology_version=$_.topology_version; from=$_.valid_from_utc; to=$_.valid_to_utc }
    })
    $first = $g.Group[0]
    $playerRows += [ordered]@{
        logical_track_uuid=$g.Name
        display_name=$first.display_name
        segments=$segments
    }
}
$playerPath = Join-Path $caseDir 'player-logical-timeline.json'
$playerRows | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $playerPath

$indexPath = Join-Path $caseDir 'recording-track-index.json'
$all | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $indexPath

$shared = @($byLogical1.Keys | Where-Object { $byLogical2.ContainsKey($_) })
$moved = @($events | Where-Object { $_.event -eq 'TRACK_RELOCATED' })
$added = @($events | Where-Object { $_.event -eq 'TRACK_ADDED' })
$removed = @($events | Where-Object { $_.event -eq 'TRACK_REMOVED' })

# UUIDv5 must be stable; UUIDv7 instance IDs must be unique.
$stable = $true
foreach ($uuid in $shared) {
    if ($byLogical1[$uuid].canonical_identity -ne $byLogical2[$uuid].canonical_identity) { $stable = $false }
}
$instances = @($all | ForEach-Object { $_.track_instance_uuid })
$uniqueInstances = @($instances | Sort-Object -Unique).Count -eq $instances.Count

$result = [ordered]@{
    result = if ($count1 -eq 4 -and $count2 -eq 4 -and $shared.Count -eq 3 -and $moved.Count -ge 1 -and $added.Count -eq 1 -and $removed.Count -eq 1 -and $stable -and $uniqueInstances) { 'PASS' } else { 'FAIL' }
    topology_v1_streams = $count1
    topology_v2_streams = $count2
    shared_logical_tracks = $shared.Count
    relocated_tracks = $moved.Count
    added_tracks = $added.Count
    removed_tracks = $removed.Count
    logical_uuid_stable = $stable
    instance_uuid_unique = $uniqueInstances
    embedded_track_name = 'PENDING_CUSTOM_MXFMUX_EXTENSION'
    index = $indexPath
    player_timeline = $playerPath
    topology_events = $eventPath
}
$report = Join-Path $caseDir 'continuity-report.json'
$result | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $report

Write-Host ''
Write-Host ('v1 streams: {0} | v2 streams: {1}' -f $count1,$count2)
Write-Host ('shared logical tracks: {0} | relocated: {1} | added: {2} | removed: {3}' -f $shared.Count,$moved.Count,$added.Count,$removed.Count)
foreach ($e in $events) {
    if ($e.event -eq 'TRACK_RELOCATED') { Write-Host ('  MOVE {0}: #{1} -> #{2} | {3}' -f $e.logical_track_uuid,$e.from_track_index,$e.to_track_index,$e.display_name) }
    elseif ($e.event -eq 'TRACK_ADDED') { Write-Host ('  ADD  {0}: #{1} | {2}' -f $e.logical_track_uuid,$e.to_track_index,$e.display_name) }
    elseif ($e.event -eq 'TRACK_REMOVED') { Write-Host ('  DEL  {0}: #{1} | {2}' -f $e.logical_track_uuid,$e.from_track_index,$e.display_name) }
}
Write-Host ('Player timeline: {0}' -f $playerPath)
Write-Host ('Report: {0}' -f $report)

if ($result.result -eq 'PASS') {
    Write-Host 'LOGICAL TRACK CONTINUITY: PASS' -ForegroundColor Green
    Write-Host 'NOTE: stock GStreamer mxfmux still does not expose per-track TrackName/UUID setters; embedding is the next muxer-extension gate.' -ForegroundColor Yellow
    exit 0
}
Write-Error 'LOGICAL TRACK CONTINUITY: FAIL'
exit 7
