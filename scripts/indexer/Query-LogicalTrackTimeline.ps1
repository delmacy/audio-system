[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$LogicalTrackUUID,
 [Parameter(Mandatory)][datetime]$FromUtc,
 [Parameter(Mandatory)][datetime]$ToUtc,
 [string]$DatabasePath = (Join-Path $PSScriptRoot '..\..\runs\index\recorder-index.sqlite')
)
$ErrorActionPreference='Stop'
$sqlite=Get-Command sqlite3.exe -ErrorAction Stop
$db=[IO.Path]::GetFullPath($DatabasePath)
$q=@"
.mode json
SELECT ti.logical_track_uuid, ti.track_instance_uuid, ti.track_index,
       rf.file_id, rf.relative_path, ti.valid_from_utc, ti.valid_to_utc,
       rf.recording_window_start_utc, rf.segment_sequence
FROM track_instance ti
JOIN recording_file rf ON rf.file_id=ti.file_id
WHERE ti.logical_track_uuid='$($LogicalTrackUUID.Replace("'","''"))'
  AND ti.valid_from_utc < '$($ToUtc.ToUniversalTime().ToString('o'))'
  AND COALESCE(ti.valid_to_utc,'9999-12-31T23:59:59Z') > '$($FromUtc.ToUniversalTime().ToString('o'))'
ORDER BY rf.recording_window_start_utc, rf.segment_sequence, ti.valid_from_utc;
"@
$q | & $sqlite.Source $db
