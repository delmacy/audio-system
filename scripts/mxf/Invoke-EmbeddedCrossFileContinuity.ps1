Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
. (Join-Path $PSScriptRoot 'Track-Identity.ps1')

$root = Get-ProjectRoot
$pluginRoot = Join-Path $root 'src\mxf-identity-plugin'
$dll = Join-Path $pluginRoot 'bin\gstmxfidentity.dll'
if (-not (Test-Path $dll)) { throw 'Identity plugin not built. Run 14-build-mxf-identity-plugin.cmd first.' }

$gstRoot = $env:GSTREAMER_ROOT_X86_64
if (-not $gstRoot) { $bin = Find-GStreamerBin; if ($bin) { $gstRoot = Split-Path $bin -Parent } }
if (-not $gstRoot) { throw 'GStreamer not found.' }
$gstBin = Join-Path $gstRoot 'bin'
if (-not (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\') -ieq $gstBin.TrimEnd('\') })) { $env:PATH = $gstBin + ';' + $env:PATH }

$exeCandidates = @(
    (Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),
    (Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')
)
$exe = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { throw 'mxf-lab.exe missing. Run 06-build-native.cmd first.' }

$inspect = Get-GstTool 'gst-inspect-1.0.exe'
$ffprobe = Find-Executable @('ffprobe.exe','ffprobe')
if (-not $ffprobe) { throw 'ffprobe is required for this gate.' }

$runDir = Ensure-RunDirectory -Name 'mxf-identity'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$caseDir = Join-Path $runDir ('embedded-cross-file-' + $stamp)
New-Item -ItemType Directory -Force -Path $caseDir | Out-Null

$writerRegistryA = Join-Path $caseDir 'registry-writer-a.bin'
$writerRegistryB = Join-Path $caseDir 'registry-writer-b.bin'
$readerRegistry = Join-Path $caseDir 'registry-reader.bin'
$originalPluginPath = $env:GST_PLUGIN_PATH
$originalPluginPath10 = $env:GST_PLUGIN_PATH_1_0
$originalRegistry = $env:GST_REGISTRY_1_0

function Set-WriterEnvironment {
    param([string]$RegistryPath)
    $env:GST_PLUGIN_PATH = ''
    $env:GST_PLUGIN_PATH_1_0 = ''
    $env:GST_REGISTRY_1_0 = $RegistryPath
}
function Set-ReaderEnvironment {
    $env:GST_PLUGIN_PATH = ''
    $env:GST_PLUGIN_PATH_1_0 = ''
    $env:GST_REGISTRY_1_0 = $readerRegistry
}
function Restore-GstEnvironment {
    $env:GST_PLUGIN_PATH = $originalPluginPath
    $env:GST_PLUGIN_PATH_1_0 = $originalPluginPath10
    $env:GST_REGISTRY_1_0 = $originalRegistry
}

# Deliberately reorder all three shared logical tracks. One service disappears
# and one new service appears in segment B.
$topologyA = @(
    [ordered]@{ service_type='radio'; service_id='121500'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='RADIO 121.500'; label='radio-121500-rx'; mid='r1' },
    [ordered]@{ service_type='radio'; service_id='121500'; endpoint_id='CWP-A17'; direction='TX'; sdp_service='RADIO 121.500'; label='radio-121500-tx'; mid='r2' },
    [ordered]@{ service_type='telephone'; service_id='TEL-01'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='TEL-01'; label='tel-01-rx'; mid='t1' },
    [ordered]@{ service_type='radio'; service_id='118100'; endpoint_id='CWP-A18'; direction='RX'; sdp_service='RADIO 118.100'; label='radio-118100-rx'; mid='r3' }
)
$topologyB = @(
    [ordered]@{ service_type='telephone'; service_id='TEL-01'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='TEL-01'; label='tel-01-rx'; mid='t1' },
    [ordered]@{ service_type='radio'; service_id='132700'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='RADIO 132.700'; label='radio-132700-rx'; mid='r4' },
    [ordered]@{ service_type='radio'; service_id='121500'; endpoint_id='CWP-A17'; direction='TX'; sdp_service='RADIO 121.500'; label='radio-121500-tx'; mid='r2' },
    [ordered]@{ service_type='radio'; service_id='121500'; endpoint_id='CWP-A17'; direction='RX'; sdp_service='RADIO 121.500'; label='radio-121500-rx'; mid='r1' }
)

function New-WriterRows {
    param([object[]]$Topology)
    $rows = @()
    foreach ($d in $Topology) {
        $id = New-LogicalTrackIdentity -ServiceType $d.service_type -ServiceId $d.service_id -EndpointId $d.endpoint_id -Direction $d.direction -SdpServiceNameRaw $d.sdp_service -SdpLabelRaw $d.label -SdpMidRaw $d.mid
        $rows += [ordered]@{
            display_name = $id.display_name
            logical_track_uuid = $id.logical_track_uuid
            track_instance_uuid = $id.track_instance_uuid
            canonical_identity = $id.canonical_identity
        }
        Start-Sleep -Milliseconds 1
    }
    return @($rows)
}

function Write-IdentityTsv {
    param([object[]]$Rows,[string]$Path)
    $lines = @($Rows | ForEach-Object { $_.display_name + "`t" + $_.logical_track_uuid + "`t" + $_.track_instance_uuid })
    [IO.File]::WriteAllLines($Path,$lines,(New-Object Text.UTF8Encoding($false)))
}

function Get-AudioCount {
    param([string]$Path)
    $json = & $ffprobe -v error -select_streams a -show_entries stream=index -of json $Path
    if ($LASTEXITCODE -ne 0) { throw "ffprobe failed: $Path" }
    return @((($json | Out-String | ConvertFrom-Json).streams)).Count
}

function Parse-MxfIdentityFromReaderOutput {
    param([string]$Text,[string]$File,[int]$SegmentOrder)

    # gst_structure_to_string() escapes every nested structure layer. Removing
    # only the serialization backslashes gives us the standard field text that
    # mxfdemux produced from the MXF metadata. We then select source-package
    # essence tracks by requiring a non-zero TrackNumber.
    $normalized = ([string]$Text) -replace '\\',''
    $trackPattern = 'track-id=\(uint\)(?<trackid>\d+), track-number=\(uint\)(?<tracknum>\d+), track-name=\(string\)"(?<trackname>[^"]+)"'
    $namePattern = '^(?<display>.+?) \| LT=(?<lt>[0-9a-fA-F-]{36}) \| TI=(?<ti>[0-9a-fA-F-]{36})$'
    $seen = @{}
    $found = @()

    foreach ($m in [regex]::Matches($normalized,$trackPattern)) {
        $trackNumber = [uint64]$m.Groups['tracknum'].Value
        if ($trackNumber -eq 0) { continue } # material package / timecode
        $trackName = $m.Groups['trackname'].Value
        $nm = [regex]::Match($trackName,$namePattern)
        if (-not $nm.Success) { continue }
        $trackId = [int]$m.Groups['trackid'].Value
        $lt = $nm.Groups['lt'].Value.ToLowerInvariant()
        $ti = $nm.Groups['ti'].Value.ToLowerInvariant()
        $key = '{0}|{1}|{2}' -f $trackId,$lt,$ti
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $found += [ordered]@{
            file = $File
            segment_order = $SegmentOrder
            mxf_track_id = $trackId
            mxf_track_number = $trackNumber
            display_name = $nm.Groups['display'].Value
            logical_track_uuid = $lt
            track_instance_uuid = $ti
            embedded_track_name = $trackName
        }
    }

    $sorted = @($found | Sort-Object { [int]$_['mxf_track_id'] })
    for ($i=0; $i -lt $sorted.Count; $i++) { $sorted[$i]['track_index'] = $i + 1 }
    return @($sorted)
}

function Read-IdentityMxf {
    param([string]$Path,[int]$SegmentOrder,[string]$Label)
    $read = Invoke-NativeProcessCapture -FilePath $exe -Arguments @('inspect-identity',$Path,'--timeout-ms','15000') -TimeoutMs 20000
    $stdoutPath = Join-Path $caseDir ($Label + '-reader-stdout.txt')
    $stderrPath = Join-Path $caseDir ($Label + '-reader-stderr.txt')
    [IO.File]::WriteAllText($stdoutPath,[string]$read.StdOut,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($stderrPath,[string]$read.StdErr,(New-Object Text.UTF8Encoding($false)))
    if ($read.ExitCode -ne 0) { throw "Official mxfdemux readback failed for $Label with exit code $($read.ExitCode). See $stderrPath" }

    $stderrLines = @(([string]$read.StdErr -split "`r?`n") | Where-Object { $_ -and $_.Trim() })
    $known = @($stderrLines | Where-Object { $_ -match 'finalized while still in-construction' })
    $other = @($stderrLines | Where-Object { $_ -notmatch 'finalized while still in-construction' })
    if ($other.Count -gt 0) { $other | ForEach-Object { Write-Host ("{0} reader: {1}" -f $Label,$_) } }
    if ($known.Count -gt 0) { Write-Host ("{0} reader teardown diagnostics: {1} known GLib lines." -f $Label,$known.Count) -ForegroundColor Yellow }

    return [ordered]@{
        tracks = @(Parse-MxfIdentityFromReaderOutput -Text ([string]$read.StdOut) -File $Path -SegmentOrder $SegmentOrder)
        stdout = $stdoutPath
        stderr = $stderrPath
        known_teardown_lines = $known.Count
    }
}

Write-Host '=== Embedded Cross-File Continuity Gate ==='
$fileA = Join-Path $caseDir 'segment-001.mxf'
$fileB = Join-Path $caseDir 'segment-002.mxf'
$tsvA = Join-Path $caseDir 'writer-a.tsv'
$tsvB = Join-Path $caseDir 'writer-b.tsv'
$writerRowsA = @(New-WriterRows -Topology $topologyA)
$writerRowsB = @(New-WriterRows -Topology $topologyB)
Write-IdentityTsv -Rows $writerRowsA -Path $tsvA
Write-IdentityTsv -Rows $writerRowsB -Path $tsvB

try {
    Set-WriterEnvironment -RegistryPath $writerRegistryA
    Write-Host 'Writing segment A...'
    $wa = Invoke-NativeProcessCapture -FilePath $exe -Arguments @('write-identity','--out',$fileA,'--identity-file',$tsvA,'--plugin-dll',$dll,'--seconds','2') -TimeoutMs 30000
    $wa.StdOut | Write-Host
    if ($wa.StdErr) { $wa.StdErr | Write-Host }
    if ($wa.ExitCode -ne 0) { throw "segment A write failed: $($wa.ExitCode)" }

    Set-WriterEnvironment -RegistryPath $writerRegistryB
    Write-Host 'Writing segment B with reordered/add/remove topology...'
    $wb = Invoke-NativeProcessCapture -FilePath $exe -Arguments @('write-identity','--out',$fileB,'--identity-file',$tsvB,'--plugin-dll',$dll,'--seconds','2') -TimeoutMs 30000
    $wb.StdOut | Write-Host
    if ($wb.StdErr) { $wb.StdErr | Write-Host }
    if ($wb.ExitCode -ne 0) { throw "segment B write failed: $($wb.ExitCode)" }

    $countA = Get-AudioCount $fileA
    $countB = Get-AudioCount $fileB

    # Important proof condition: remove the writer-side identity inputs before
    # reconstruction. Everything below this point builds its index from MXF
    # metadata returned by the stock mxfdemux only.
    Remove-Item -LiteralPath $tsvA,$tsvB -Force
    $writerInputsDeleted = (-not (Test-Path $tsvA)) -and (-not (Test-Path $tsvB))
    # Drop writer-side semantic structures too. The reconstruction code below
    # has access only to file paths plus metadata returned by mxfdemux.
    $writerRowsA = $null; $writerRowsB = $null; $topologyA = $null; $topologyB = $null

    Set-ReaderEnvironment
    $officialFilesrc = Invoke-NativeProcessCapture -FilePath $inspect -Arguments @('filesrc') -TimeoutMs 10000
    $officialDemux = Invoke-NativeProcessCapture -FilePath $inspect -Arguments @('mxfdemux') -TimeoutMs 10000
    if ($officialFilesrc.ExitCode -ne 0 -or $officialDemux.ExitCode -ne 0) {
        throw ("Official reader prerequisites missing: filesrc={0} mxfdemux={1}" -f $officialFilesrc.ExitCode,$officialDemux.ExitCode)
    }

    Write-Host 'Reconstructing segment A from MXF only...'
    $ra = Read-IdentityMxf -Path $fileA -SegmentOrder 1 -Label 'segment-001'
    Write-Host 'Reconstructing segment B from MXF only...'
    $rb = Read-IdentityMxf -Path $fileB -SegmentOrder 2 -Label 'segment-002'
}
finally {
    Restore-GstEnvironment
}

$tracksA = @($ra.tracks)
$tracksB = @($rb.tracks)
$all = @($tracksA) + @($tracksB)

# Reconstructed index: this is the shape the future SQLite recording_track
# materialization can consume. It was not produced from the writer TSVs.
$reconstructedIndex = Join-Path $caseDir 'reconstructed-track-index-from-mxf.json'
$all | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $reconstructedIndex

$byA = @{}
foreach ($t in $tracksA) { if (-not $byA.ContainsKey($t.logical_track_uuid)) { $byA[$t.logical_track_uuid] = @() }; $byA[$t.logical_track_uuid] += $t }
$byB = @{}
foreach ($t in $tracksB) { if (-not $byB.ContainsKey($t.logical_track_uuid)) { $byB[$t.logical_track_uuid] = @() }; $byB[$t.logical_track_uuid] += $t }

$duplicateLogicalA = @($byA.Keys | Where-Object { @($byA[$_]).Count -ne 1 })
$duplicateLogicalB = @($byB.Keys | Where-Object { @($byB[$_]).Count -ne 1 })
$allInstances = @($all | ForEach-Object { $_.track_instance_uuid })
$instanceUnique = @($allInstances | Sort-Object -Unique).Count -eq $allInstances.Count

$shared = @($byA.Keys | Where-Object { $byB.ContainsKey($_) } | Sort-Object)
$events = @()
foreach ($lt in $byA.Keys) {
    $a = @($byA[$lt])[0]
    if ($byB.ContainsKey($lt)) {
        $b = @($byB[$lt])[0]
        if ($a.track_index -ne $b.track_index) {
            $events += [ordered]@{ event='TRACK_RELOCATED'; logical_track_uuid=$lt; display_name=$a.display_name; from_track_index=$a.track_index; to_track_index=$b.track_index; from_mxf_track_id=$a.mxf_track_id; to_mxf_track_id=$b.mxf_track_id; from_segment=1; to_segment=2 }
        }
    } else {
        $events += [ordered]@{ event='TRACK_REMOVED'; logical_track_uuid=$lt; display_name=$a.display_name; from_track_index=$a.track_index; from_segment=1; to_segment=2 }
    }
}
foreach ($lt in $byB.Keys) {
    if (-not $byA.ContainsKey($lt)) {
        $b = @($byB[$lt])[0]
        $events += [ordered]@{ event='TRACK_ADDED'; logical_track_uuid=$lt; display_name=$b.display_name; to_track_index=$b.track_index; from_segment=1; to_segment=2 }
    }
}

$eventPath = Join-Path $caseDir 'topology-events-from-mxf.jsonl'
$events | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 6 } | Set-Content -Encoding UTF8 -LiteralPath $eventPath

# Player rows are grouped only by LogicalTrackUUID recovered from the files.
$logicalGroups = @{}
foreach ($t in $all) { if (-not $logicalGroups.ContainsKey($t.logical_track_uuid)) { $logicalGroups[$t.logical_track_uuid] = @() }; $logicalGroups[$t.logical_track_uuid] += $t }
$playerRows = @()
foreach ($lt in ($logicalGroups.Keys | Sort-Object)) {
    $segments = @($logicalGroups[$lt] | Sort-Object { [int]$_['segment_order'] } | ForEach-Object {
        [ordered]@{
            segment_order = $_.segment_order
            file = $_.file
            track_index = $_.track_index
            mxf_track_id = $_.mxf_track_id
            mxf_track_number = $_.mxf_track_number
            track_instance_uuid = $_.track_instance_uuid
        }
    })
    $first = @($logicalGroups[$lt] | Sort-Object { [int]$_['segment_order'] })[0]
    $playerRows += [ordered]@{ logical_track_uuid=$lt; display_name=$first.display_name; segments=$segments }
}
$playerPath = Join-Path $caseDir 'player-logical-timeline-from-mxf.json'
$playerRows | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $playerPath

# Deterministic ordering is part of the player contract. Shared logical tracks
# must always be emitted oldest-to-newest regardless of Hashtable / parser order.
$timelineChronological = $true
foreach ($row in $playerRows) {
    $orders = @($row['segments'] | ForEach-Object { [int]$_['segment_order'] })
    for ($i=1; $i -lt $orders.Count; $i++) {
        if ($orders[$i] -lt $orders[$i-1]) { $timelineChronological = $false; break }
    }
    if (-not $timelineChronological) { break }
}

# TrackIndex is a derived, file-local ordinal. Recompute it only from MXF TrackID
# so parser encounter order can never alter the physical mapping presented to SQLite/player.
$trackIndexDeterministic = $true
foreach ($segment in 1,2) {
    $segmentTracks = @($all | Where-Object { [int]$_['segment_order'] -eq $segment } | Sort-Object { [int]$_['mxf_track_id'] })
    for ($i=0; $i -lt $segmentTracks.Count; $i++) {
        if ([int]$segmentTracks[$i]['track_index'] -ne ($i + 1)) { $trackIndexDeterministic = $false; break }
    }
    if (-not $trackIndexDeterministic) { break }
}

$moved = @($events | Where-Object { $_.event -eq 'TRACK_RELOCATED' })
$added = @($events | Where-Object { $_.event -eq 'TRACK_ADDED' })
$removed = @($events | Where-Object { $_.event -eq 'TRACK_REMOVED' })
$sharedInstanceDistinct = $true
foreach ($lt in $shared) {
    $a = @($byA[$lt])[0]; $b = @($byB[$lt])[0]
    if ($a.track_instance_uuid -eq $b.track_instance_uuid) { $sharedInstanceDistinct = $false }
}

# Acceptance expectations describe the scenario only. The reconstructed index,
# events and player rows above are all derived from readback of the two MXFs.
$pass = (
    $countA -eq 4 -and $countB -eq 4 -and
    $tracksA.Count -eq 4 -and $tracksB.Count -eq 4 -and
    $writerInputsDeleted -and
    $duplicateLogicalA.Count -eq 0 -and $duplicateLogicalB.Count -eq 0 -and
    $instanceUnique -and $sharedInstanceDistinct -and
    $shared.Count -eq 3 -and $moved.Count -eq 3 -and
    $added.Count -eq 1 -and $removed.Count -eq 1 -and
    $timelineChronological -and $trackIndexDeterministic
)

$reportObj = [ordered]@{
    schema = 'recorder-poc.embedded-cross-file-continuity.v2'
    result = if ($pass) { 'PASS' } else { 'FAIL' }
    identity_source_for_reconstruction = 'MXF TrackName read by isolated stock GStreamer 1.28.7 mxfdemux'
    sidecar_or_sqlite_used_for_reconstruction = $false
    writer_identity_inputs_deleted_before_readback = $writerInputsDeleted
    segment_a_streams = $countA
    segment_b_streams = $countB
    segment_a_recovered_tracks = $tracksA.Count
    segment_b_recovered_tracks = $tracksB.Count
    shared_logical_tracks = $shared.Count
    relocated_tracks = $moved.Count
    added_tracks = $added.Count
    removed_tracks = $removed.Count
    duplicate_logical_track_uuid_in_segment_a = $duplicateLogicalA.Count
    duplicate_logical_track_uuid_in_segment_b = $duplicateLogicalB.Count
    track_instance_uuid_globally_unique = $instanceUnique
    shared_logical_tracks_have_distinct_instances = $sharedInstanceDistinct
    timeline_segments_chronologically_sorted = $timelineChronological
    track_index_reconstructed_deterministically = $trackIndexDeterministic
    reconstructed_index = $reconstructedIndex
    player_timeline = $playerPath
    topology_events = $eventPath
    reader_evidence = [ordered]@{
        segment_a_stdout = $ra.stdout
        segment_a_stderr = $ra.stderr
        segment_b_stdout = $rb.stdout
        segment_b_stderr = $rb.stderr
        known_teardown_lines = ([int]$ra.known_teardown_lines + [int]$rb.known_teardown_lines)
    }
}
$reportPath = Join-Path $caseDir 'embedded-cross-file-continuity-report.json'
$reportObj | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $reportPath

Write-Host ''
Write-Host ('A streams/recovered: {0}/{1} | B streams/recovered: {2}/{3}' -f $countA,$tracksA.Count,$countB,$tracksB.Count)
Write-Host ('shared: {0} | relocated: {1} | added: {2} | removed: {3}' -f $shared.Count,$moved.Count,$added.Count,$removed.Count)
foreach ($e in $events) {
    if ($e.event -eq 'TRACK_RELOCATED') { Write-Host ('  MOVE LT={0} #{1} -> #{2} | {3}' -f $e.logical_track_uuid,$e.from_track_index,$e.to_track_index,$e.display_name) }
    elseif ($e.event -eq 'TRACK_ADDED') { Write-Host ('  ADD  LT={0} -> #{1} | {2}' -f $e.logical_track_uuid,$e.to_track_index,$e.display_name) }
    elseif ($e.event -eq 'TRACK_REMOVED') { Write-Host ('  DEL  LT={0} <- #{1} | {2}' -f $e.logical_track_uuid,$e.from_track_index,$e.display_name) }
}
Write-Host ('Writer TSVs deleted before reconstruction: {0}' -f $writerInputsDeleted)
Write-Host ('Instance UUIDs globally unique: {0}' -f $instanceUnique)
Write-Host ('Timeline segments chronologically sorted: {0}' -f $timelineChronological)
Write-Host ('TrackIndex reconstructed deterministically: {0}' -f $trackIndexDeterministic)
Write-Host ('Player timeline: {0}' -f $playerPath)
Write-Host ('Reconstructed index: {0}' -f $reconstructedIndex)
Write-Host ('Report: {0}' -f $reportPath)

if ($pass) {
    Write-Host 'EMBEDDED CROSS-FILE CONTINUITY: PASS' -ForegroundColor Green
    exit 0
}
Write-Error 'EMBEDDED CROSS-FILE CONTINUITY: FAIL'
exit 7
