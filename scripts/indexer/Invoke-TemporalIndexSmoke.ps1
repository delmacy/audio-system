$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sqlite = (Get-Command sqlite3.exe -ErrorAction Stop).Source
$source = Get-ChildItem -LiteralPath (Join-Path $root 'runs\phase7-window-rotation') -Directory |
  Sort-Object Name -Descending | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'phase7-window-rotation-report.json') } | Select-Object -First 1
if (-not $source) { throw 'A completed Phase 7 rotation run is required.' }
$recording = Get-Content -LiteralPath (Join-Path $source.FullName 'phase7-window-rotation-report.json') -Raw | ConvertFrom-Json
if ($recording.result -ne 'PASS') { throw 'Phase 7 source report is not PASS.' }
$events = @(Get-Content -LiteralPath $recording.audit | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
$lt = [string]$recording.logical_track_uuid
$runDir = Join-Path $root ('runs\index\temporal-index-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$db = Join-Path $runDir 'recorder-index.sqlite'
Get-Content -LiteralPath (Join-Path $root 'db\temporal-index-schema.sql') -Raw | & $sqlite $db
if ($LASTEXITCODE -ne 0) { throw 'Schema initialization failed.' }
function Q([string]$value) { "'" + $value.Replace("'", "''") + "'" }
function U([datetime]$value) { $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
function Query([string]$sql) {
  $output = & $sqlite -json $db $sql
  if ($LASTEXITCODE -ne 0) { throw "SQLite query failed: $sql" }
  if (-not $output) { return @() }
  return ($output | Out-String | ConvertFrom-Json)
}
function FileHash([string]$path) {
  $sha = [Security.Cryptography.SHA256]::Create(); $stream = [IO.File]::OpenRead($path)
  try { [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
  finally { $stream.Dispose(); $sha.Dispose() }
}
$segments = @(); $intervals = @()
for ($n = 0; $n -lt 2; $n++) {
  $path = if ($n -eq 0) { [string]$recording.segment0 } else { [string]$recording.segment1 }
  if (-not (Test-Path -LiteralPath $path)) { throw "Closed MXF missing: $path" }
  $media = @($events | Where-Object { $_.event -in @('MEDIA_START','MEDIA_END') -and [string]$_.file_id -match ('-seg{0:D3}$' -f $n) })
  $starts = @($media | Where-Object event -eq 'MEDIA_START'); $ends = @($media | Where-Object event -eq 'MEDIA_END')
  $fileIds = @($media | Select-Object -ExpandProperty file_id -Unique); $tis = @($media | Select-Object -ExpandProperty track_instance_uuid -Unique)
  if ($starts.Count -eq 0 -or $starts.Count -ne $ends.Count -or $fileIds.Count -ne 1 -or $tis.Count -ne 1) { throw "Ambiguous interval/file identity for segment $n" }
  for ($i = 0; $i -lt $starts.Count; $i++) {
    $start = U ([datetime]$starts[$i].ts_utc); $end = U ([datetime]$ends[$i].ts_utc)
    if ($end -le $start) { throw "Invalid interval ordering for segment $n" }
    $startMatch = [regex]::Match([string]$starts[$i].detail, 'recorded_payload_bytes=(\d+)')
    $endMatch = [regex]::Match([string]$ends[$i].detail, 'recorded_payload_bytes=(\d+)')
    if (-not $startMatch.Success -or -not $endMatch.Success) { throw "Missing recorded byte offsets for segment $n interval $i" }
    $startByte = [int64]$startMatch.Groups[1].Value; $endByte = [int64]$endMatch.Groups[1].Value
    if ($endByte -le $startByte) { throw "Invalid recorded byte offsets for segment $n interval $i" }
    $intervals += [pscustomobject]@{ file_id=[string]$fileIds[0]; ti=[string]$tis[0]; start=$start; end=$end; ordinal=$i; start_byte=$startByte; end_byte=$endByte }
  }
  $segments += [pscustomobject]@{
    file_id=[string]$fileIds[0]; ti=[string]$tis[0]; path=$path; sequence=$n
    start=(U ([datetime]$starts[0].ts_utc)); end=(U ([datetime]$ends[-1].ts_utc))
    bytes=(Get-Item -LiteralPath $path).Length; hash=(FileHash $path)
  }
}
if ($segments[0].ti -eq $segments[1].ti -or $segments[0].end -gt $segments[1].start) { throw 'Physical segment identity or time ordering invalid.' }
$sql = New-Object System.Collections.Generic.List[string]
$sql.Add('BEGIN TRANSACTION;'); $sql.Add('PRAGMA foreign_keys=ON;')
$canonical = 'identity-v1|service_type=radio|service_id=121500|endpoint_id=cwp-a17|direction=rx'
$sql.Add("INSERT OR IGNORE INTO logical_track(logical_track_uuid,identity_version,service_type,service_id,endpoint_id,media_flow,display_name,canonical_identity,created_utc) VALUES ($(Q $lt),1,'radio','121500','cwp-a17','mono','Phase 7 legacy radio route',$(Q $canonical),$(Q $segments[0].start));")
foreach ($segment in $segments) {
  $relative = $segment.path.Substring($root.Length + 1).Replace('\','/')
  $sql.Add("INSERT OR IGNORE INTO recording_file(file_id,recorder_id,relative_path,state,recording_window_start_utc,recording_window_end_utc,segment_sequence,topology_version,first_media_utc,last_media_utc,closed_utc,size_bytes,sha256) VALUES ($(Q $segment.file_id),'RECORDER-POC-01',$(Q $relative),'CLOSED_COMPLETE',$(Q $segment.start),$(Q $segment.end),$($segment.sequence),1,$(Q $segment.start),$(Q $segment.end),$(Q $segment.end),$($segment.bytes),$(Q $segment.hash));")
  $trackName = "RADIO 121500 | LT=$lt | TI=$($segment.ti)"
  $sql.Add("INSERT OR IGNORE INTO track_instance(track_instance_uuid,logical_track_uuid,file_id,track_index,track_name,valid_from_utc,valid_to_utc,codec,sample_rate_hz,channels) VALUES ($(Q $segment.ti),$(Q $lt),$(Q $segment.file_id),0,$(Q $trackName),$(Q $segment.start),$(Q $segment.end),'PCMA',8000,1);")
}
foreach ($interval in $intervals) {
  $id = "$($interval.file_id)-media-$($interval.ordinal)"
  $sql.Add("INSERT OR IGNORE INTO media_interval(media_interval_id,logical_track_uuid,track_instance_uuid,file_id,start_utc,end_utc,start_payload_byte_offset,end_payload_byte_offset,state) VALUES ($(Q $id),$(Q $lt),$(Q $interval.ti),$(Q $interval.file_id),$(Q $interval.start),$(Q $interval.end),$($interval.start_byte),$($interval.end_byte),'CLOSED');")
}
$lastEventId = ''
for ($i = 0; $i -lt $events.Count; $i++) {
  $e = $events[$i]; $lastEventId = "phase7-$($source.Name)-event-$i"
  $payload = $e | ConvertTo-Json -Compress -Depth 5
  $sql.Add("INSERT OR IGNORE INTO recording_event(event_id,event_utc,event_type,severity,logical_track_uuid,track_instance_uuid,file_id,session_id,payload_json) VALUES ($(Q $lastEventId),$(Q (U ([datetime]$e.ts_utc))),$(Q ([string]$e.event)),'INFO',$(Q ([string]$e.logical_track_uuid)),$(Q ([string]$e.track_instance_uuid)),$(Q ([string]$e.file_id)),$(Q ([string]$e.session_id)),$(Q $payload));")
}
$sourceBytes = (Get-Item -LiteralPath $recording.audit).Length
$sql.Add("INSERT INTO ingestion_checkpoint(source_id,source_path,byte_offset,last_event_id,updated_utc) VALUES ('phase7-audit',$(Q ([string]$recording.audit)),$sourceBytes,$(Q $lastEventId),$(Q (U ([datetime]::UtcNow)))) ON CONFLICT(source_id) DO UPDATE SET byte_offset=excluded.byte_offset,last_event_id=excluded.last_event_id,updated_utc=excluded.updated_utc;")
$sql.Add('COMMIT;')
$sqlPath = Join-Path $runDir 'ingest.sql'
[IO.File]::WriteAllLines($sqlPath, [string[]]$sql, (New-Object Text.UTF8Encoding($false)))
function Ingest {
  Get-Content -LiteralPath $sqlPath -Raw | & $sqlite $db
  if ($LASTEXITCODE -ne 0) { throw 'SQLite ingestion failed.' }
}
$countsSql = 'SELECT (SELECT count(*) FROM recording_file) AS files,(SELECT count(*) FROM track_instance) AS instances,(SELECT count(*) FROM media_interval) AS intervals,(SELECT count(*) FROM recording_event) AS events,(SELECT count(*) FROM ingestion_checkpoint) AS checkpoints;'
Ingest; $before = @(Query $countsSql)
Ingest; $after = @(Query $countsSql)
$from = U (([datetime]$segments[0].start).AddSeconds(-1)); $to = U (([datetime]$segments[1].end).AddSeconds(1))
$timeline = @(Query "SELECT ti.logical_track_uuid,ti.track_instance_uuid,ti.track_index,rf.file_id,rf.relative_path,ti.valid_from_utc,ti.valid_to_utc,rf.recording_window_start_utc,rf.segment_sequence FROM track_instance ti JOIN recording_file rf ON rf.file_id=ti.file_id WHERE ti.logical_track_uuid=$(Q $lt) AND ti.valid_from_utc < $(Q $to) AND ti.valid_to_utc > $(Q $from) ORDER BY rf.recording_window_start_utc,rf.segment_sequence,ti.valid_from_utc;")
$overlay = @(Query "SELECT event_type,count(*) AS event_count FROM recording_event WHERE logical_track_uuid=$(Q $lt) GROUP BY event_type ORDER BY event_type;")
$journal = (& $sqlite $db 'PRAGMA journal_mode;').Trim()
$idempotent = ($before | ConvertTo-Json -Compress) -eq ($after | ConvertTo-Json -Compress)
$ordered = $timeline.Count -eq 2 -and [int]$timeline[0].segment_sequence -eq 0 -and [int]$timeline[1].segment_sequence -eq 1 -and $timeline[0].track_instance_uuid -ne $timeline[1].track_instance_uuid
$gap = $intervals.Count -eq 4 -and $intervals[0].end -lt $intervals[1].start
$eventTypes = @($overlay | Select-Object -ExpandProperty event_type)
$eventsOk = 'SQU_ON' -in $eventTypes -and 'SQU_OFF' -in $eventTypes -and 'WINDOW_ROTATED' -in $eventTypes
$pass = $journal -eq 'wal' -and $idempotent -and $ordered -and $gap -and $eventsOk -and $after[0].files -eq 2 -and $after[0].instances -eq 2 -and $after[0].intervals -eq 4 -and $after[0].checkpoints -eq 1
$report = [ordered]@{
  schema='recorder-poc.phase11.temporal-index-smoke.v1'; result=if($pass){'PASS'}else{'FAIL'}
  source_scope='real_closed_phase7_mxf_legacy_rx_route'; source_run=$source.FullName
  database=$db; journal_mode=$journal; logical_track_uuid=$lt; timeline=$timeline; media_intervals=$intervals; event_overlay=$overlay
  counts_before_reingest=$before[0]; counts_after_reingest=$after[0]; idempotent=$idempotent; ordered=$ordered; gap_explicit=$gap; event_overlay_ok=$eventsOk
  recorder_was_independent_of_indexer=$true; indexer_process_restart_tested=$false
}
$reportPath = Join-Path $runDir 'temporal-index-smoke-report.json'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host "TEMPORAL INDEX: $($report.result)"
Write-Host "Report: $reportPath"
if (-not $pass) { exit 1 }
