[CmdletBinding()]
param(
  [string]$IndexPath = "",
  [string]$LogicalTrackUuid = "",
  [string]$FromUtc = "",
  [string]$ToUtc = "",
  [ValidateSet("continuous","only_audio","event_overlay")]
  [string]$Mode = "continuous",
  [string]$OutDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Utc([string]$s) {
  return [DateTime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
}
function Iso([DateTime]$d) { return $d.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [Globalization.CultureInfo]::InvariantCulture) }
function MsBetween([DateTime]$a,[DateTime]$b) { return [Math]::Round((($b.ToUniversalTime().Ticks - $a.ToUniversalTime().Ticks) / [TimeSpan]::TicksPerMillisecond),3) }

if (-not $OutDir) { $OutDir = 'runs/playback/historical-playback-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$sqlite = (Get-Command sqlite3.exe -ErrorAction Stop).Source
if (-not $IndexPath) {
  $candidate = Get-ChildItem -LiteralPath 'runs/index' -Directory | Sort-Object Name -Descending |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'recorder-index.sqlite') } | Select-Object -First 1
  if (-not $candidate) { throw 'No executed temporal index database found.' }
  $IndexPath = Join-Path $candidate.FullName 'recorder-index.sqlite'
}
if (-not (Test-Path -LiteralPath $IndexPath)) { throw "Temporal index not found: $IndexPath" }
function SqlLit([string]$value) { return "'" + $value.Replace("'", "''") + "'" }
function Query([string]$sql) {
  $raw = & $sqlite -json $IndexPath $sql
  if ($LASTEXITCODE -ne 0) { throw "SQLite query failed: $sql" }
  if (-not $raw) { return @() }
  return ($raw | Out-String | ConvertFrom-Json)
}
if (-not $LogicalTrackUuid) {
  $track = @(Query 'SELECT logical_track_uuid FROM logical_track ORDER BY created_utc LIMIT 1;')
  if ($track.Count -ne 1) { throw 'Temporal index has no logical track.' }
  $LogicalTrackUuid = [string]$track[0].logical_track_uuid
}
$rows = @(Query "SELECT 'media' AS kind,mi.file_id,rf.relative_path AS path,mi.track_instance_uuid,ti.track_index,rf.recording_window_start_utc AS window_start,rf.segment_sequence,mi.start_utc AS start,mi.end_utc AS end,mi.start_payload_byte_offset AS start_byte,mi.end_payload_byte_offset AS end_byte,(SELECT MIN(first.start_payload_byte_offset) FROM media_interval first WHERE first.file_id=mi.file_id) AS file_byte_base,rf.sha256 AS mxf_sha256 FROM media_interval mi JOIN track_instance ti ON ti.track_instance_uuid=mi.track_instance_uuid JOIN recording_file rf ON rf.file_id=mi.file_id WHERE mi.logical_track_uuid=$(SqlLit $LogicalTrackUuid) AND rf.state='CLOSED_COMPLETE' ORDER BY rf.recording_window_start_utc,rf.segment_sequence,mi.start_utc;")
if ($rows.Count -eq 0) { throw "No closed media intervals for LogicalTrackUUID $LogicalTrackUuid" }
if (-not $FromUtc) { $FromUtc = [string]$rows[0].start }
if (-not $ToUtc) { $ToUtc = [string]$rows[-1].end }
$from = Utc $FromUtc; $to = Utc $ToUtc
if ($to -le $from) { throw 'ToUtc must be greater than FromUtc.' }
$events = @(Query "SELECT event_type AS event,event_utc AS t_utc,logical_track_uuid,'recording_event' AS source FROM recording_event WHERE logical_track_uuid=$(SqlLit $LogicalTrackUuid) AND event_utc >= $(SqlLit (Iso $from)) AND event_utc <= $(SqlLit (Iso $to)) ORDER BY event_utc,event_id;")

$items = New-Object System.Collections.Generic.List[object]
$cursor = $from
foreach ($r in $rows) {
  $s = Utc $r.start; $e = Utc $r.end
  if ($e -le $from -or $s -ge $to) { continue }
  if ($s -lt $from) { $s = $from }
  if ($e -gt $to) { $e = $to }
  if ($s -ne (Utc $r.start) -or $e -ne (Utc $r.end)) { throw 'Partial interval clipping lacks sample-accurate timestamp mapping.' }
  if ($Mode -ne 'only_audio' -and $s -gt $cursor) {
    $items.Add([pscustomobject]@{ kind='gap'; reason='no_recorded_media'; from_utc=Iso $cursor; to_utc=Iso $s; duration_ms=MsBetween $cursor $s })
  }
  $items.Add([pscustomobject]@{
    kind='media'; file_id=$r.file_id; path=$r.path; logical_track_uuid=$LogicalTrackUuid; track_instance_uuid=$r.track_instance_uuid; track_index=$r.track_index;
    recording_window_start_utc=$r.window_start; segment_sequence=$r.segment_sequence; valid_from_utc=Iso $s; valid_to_utc=Iso $e; duration_ms=MsBetween $s $e;
    start_payload_byte_offset=$r.start_byte; end_payload_byte_offset=$r.end_byte; file_payload_byte_base=$r.file_byte_base; mxf_sha256=$r.mxf_sha256
  })
  if ($e -gt $cursor) { $cursor = $e }
}
if ($Mode -ne 'only_audio' -and $cursor -lt $to) {
  $items.Add([pscustomobject]@{ kind='gap'; reason='no_recorded_media'; from_utc=Iso $cursor; to_utc=Iso $to; duration_ms=MsBetween $cursor $to })
}

$eventOut = @()
if ($Mode -eq 'event_overlay' -or $Mode -eq 'continuous') {
  $eventOut = @($events | Where-Object { (Utc $_.t_utc) -ge $from -and (Utc $_.t_utc) -le $to })
}

$plan = [ordered]@{
  schema='recorder-poc.historical-playback-plan.v1'
  generated_utc=Iso ([DateTime]::UtcNow)
  index_path=$IndexPath
  source_scope='sqlite_temporal_index_from_closed_mxf'
  logical_track_uuid=$LogicalTrackUuid
  from_utc=Iso $from
  to_utc=Iso $to
  mode=$Mode
  fabricate_silence=$false
  items=$items.ToArray()
  events=@($eventOut)
  summary=[ordered]@{
    media_items=@($items | Where-Object kind -eq 'media').Count
    gap_items=@($items | Where-Object kind -eq 'gap').Count
    distinct_files=@(@($items | Where-Object kind -eq 'media' | Select-Object -ExpandProperty file_id -Unique)).Count
    distinct_track_instances=@(@($items | Where-Object kind -eq 'media' | Select-Object -ExpandProperty track_instance_uuid -Unique)).Count
    total_media_ms=[Math]::Round((@($items | Where-Object kind -eq 'media' | Measure-Object -Property duration_ms -Sum).Sum),3)
    total_gap_ms=[Math]::Round((@($items | Where-Object kind -eq 'gap' | Measure-Object -Property duration_ms -Sum).Sum),3)
  }
}

if ($plan.summary.media_items -eq 0) { throw 'Playback query returned no closed media.' }
foreach ($item in $items) {
  if ($item.kind -eq 'media' -and -not (Test-Path -LiteralPath $item.path)) { throw "Indexed MXF missing: $($item.path)" }
}

$planPath = Join-Path $OutDir 'historical-playback-plan.json'
$plan | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $planPath
Write-Host "Historical playback plan: $planPath"
Write-Host ("Items: media={0} gaps={1} files={2} track_instances={3}" -f $plan.summary.media_items,$plan.summary.gap_items,$plan.summary.distinct_files,$plan.summary.distinct_track_instances)
Write-Output $plan
