[CmdletBinding()]
param(
  [string]$PlanPath = '',
  [ValidateSet('only_audio','continuous')][string]$Mode = 'only_audio',
  [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $PlanPath) {
  $source = Get-ChildItem -LiteralPath (Join-Path $root 'runs\playback') -Directory | Sort-Object Name -Descending |
    Where-Object { $_.Name -match '^historical-playback-\d{8}-\d{9}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'historical-playback-plan.json')) } | Select-Object -First 1
  if (-not $source) { throw 'No executed historical playback plan found.' }
  $PlanPath = Join-Path $source.FullName 'historical-playback-plan.json'
}
if (-not $OutDir) { $OutDir = Join-Path $root ('runs\playback\real-segment-export-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff')) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
if ($plan.schema -ne 'recorder-poc.historical-playback-plan.v1' -or $plan.source_scope -ne 'sqlite_temporal_index_from_closed_mxf') { throw 'A real SQLite-backed playback plan is required.' }
$ffprobe = (Get-Command ffprobe.exe -ErrorAction Stop).Source
$ffmpeg = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
function Sha256Hex([string]$path) {
  $sha = [Security.Cryptography.SHA256]::Create(); $stream = [IO.File]::OpenRead($path)
  try { [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
  finally { $stream.Dispose(); $sha.Dispose() }
}
function FullSourcePath([string]$path) {
  if ([IO.Path]::IsPathRooted($path)) { return $path }
  return Join-Path $root $path
}
function WriteWav([string]$path,[byte[]]$pcm) {
  $stream = [IO.File]::Open($path,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try {
    $writer = New-Object IO.BinaryWriter($stream)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([uint32](36 + $pcm.Length))
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $writer.Write([uint32]16)
    $writer.Write([uint16]1); $writer.Write([uint16]1); $writer.Write([uint32]8000)
    $writer.Write([uint32]16000); $writer.Write([uint16]2); $writer.Write([uint16]16)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('data')); $writer.Write([uint32]$pcm.Length)
    $writer.Write($pcm); $writer.Flush()
  } finally { $stream.Dispose() }
}
$decoded = @{}
$resultBytes = New-Object 'System.Collections.Generic.List[byte]'
$manifestItems = New-Object 'System.Collections.Generic.List[object]'
$sourceRows = New-Object 'System.Collections.Generic.List[string]'
$gapRows = New-Object 'System.Collections.Generic.List[object]'
$ordinal = 0
foreach ($item in @($plan.items)) {
  $ordinal++
  if ($item.kind -eq 'gap') {
    $gapRows.Add([pscustomobject]@{from_utc=$item.from_utc;to_utc=$item.to_utc;reason=$item.reason;recorded_audio=$false})
    if ($Mode -eq 'continuous') {
      $silenceBytes = [int][Math]::Round([double]$item.duration_ms * 16.0)
      $resultBytes.AddRange((New-Object byte[] $silenceBytes))
      $manifestItems.Add([pscustomobject]@{kind='synthetic_gap_silence';ordinal=$ordinal;bytes=$silenceBytes;not_evidence_audio=$true})
    } else {
      $manifestItems.Add([pscustomobject]@{kind='omitted_gap';ordinal=$ordinal;bytes=0;not_evidence_audio=$true})
    }
    continue
  }
  if ($item.kind -ne 'media') { throw "Unsupported playback item kind: $($item.kind)" }
  $path = FullSourcePath ([string]$item.path)
  if (-not (Test-Path -LiteralPath $path)) { throw "Source MXF missing: $path" }
  $actualHash = Sha256Hex $path
  if ($actualHash -ne [string]$item.mxf_sha256) { throw "Source MXF hash mismatch: $path" }
  $key = [string]$item.file_id
  if (-not $decoded.ContainsKey($key)) {
    $probeRaw = & $ffprobe -v error -show_entries 'stream=index,codec_name,channels,sample_rate:stream_tags=track_name' -of json $path
    if ($LASTEXITCODE -ne 0) { throw "ffprobe failed: $path" }
    $streams = @((($probeRaw | Out-String | ConvertFrom-Json).streams))
    $selected = @($streams | Where-Object { [int]$_.index -eq [int]$item.track_index })
    if ($selected.Count -ne 1 -or $selected[0].codec_name -ne 'pcm_alaw' -or [int]$selected[0].channels -ne 1 -or [int]$selected[0].sample_rate -ne 8000) { throw "Physical audio track mismatch: $path" }
    $trackName = [string]$selected[0].tags.track_name
    if (-not $trackName.Contains('LT=' + [string]$item.logical_track_uuid) -or -not $trackName.Contains('TI=' + [string]$item.track_instance_uuid)) { throw "Embedded LT/TI mismatch: $path" }
    $rawPath = Join-Path $OutDir ("decoded-$($item.file_id).pcm")
    & $ffmpeg -y -v error -i $path -map "0:$($item.track_index)" -ac 1 -ar 8000 -c:a pcm_s16le -f s16le $rawPath
    if ($LASTEXITCODE -ne 0) { throw "MXF decode failed: $path" }
    $raw = [IO.File]::ReadAllBytes($rawPath)
    $decoded[$key] = [pscustomobject]@{raw=$raw;path=$rawPath;track_name=$trackName;source_hash=$actualHash;decoded_hash=(Sha256Hex $rawPath)}
  }
  $base = [int64]$item.file_payload_byte_base
  $offset = [int64]$item.start_payload_byte_offset - $base
  $length = [int64]$item.end_payload_byte_offset - [int64]$item.start_payload_byte_offset
  $rawBytes = [byte[]]$decoded[$key].raw
  if ($offset -lt 0 -or $length -le 0 -or (2 * ($offset + $length)) -gt $rawBytes.Length) { throw "Recorded byte range outside decoded track: $key" }
  $clip = New-Object byte[] ([int](2 * $length))
  [Array]::Copy($rawBytes,[int](2 * $offset),$clip,0,$clip.Length)
  $resultBytes.AddRange($clip)
  $manifestItems.Add([pscustomobject]@{
    kind='decoded_media';ordinal=$ordinal;file_id=$key;logical_track_uuid=$item.logical_track_uuid;track_instance_uuid=$item.track_instance_uuid;track_index=$item.track_index
    valid_from_utc=$item.valid_from_utc;valid_to_utc=$item.valid_to_utc;source_payload_byte_from=$item.start_payload_byte_offset;source_payload_byte_to=$item.end_payload_byte_offset
    decoded_pcm_bytes=$clip.Length;decoder='ffmpeg_mxf_pcm_alaw_to_pcm_s16le';embedded_identity_verified=$true;source_sha256=$actualHash
  })
  $sourceRows.Add(('media,{0},{1},{2},{3},{4},{5},{6},{7},{8}' -f $ordinal,$key,$item.logical_track_uuid,$item.track_instance_uuid,$item.track_index,$item.start_payload_byte_offset,$item.end_payload_byte_offset,$item.valid_from_utc,$item.valid_to_utc))
}
if ($decoded.Count -eq 0 -or $resultBytes.Count -eq 0) { throw 'No recorded media decoded.' }
$wavPath = Join-Path $OutDir 'export.wav'; WriteWav $wavPath $resultBytes.ToArray()
$sourceMapPath = Join-Path $OutDir 'source-map.csv'
@('kind,ordinal,file_id,logical_track_uuid,track_instance_uuid,track_index,start_payload_byte_offset,end_payload_byte_offset,valid_from_utc,valid_to_utc') + $sourceRows.ToArray() | Set-Content -LiteralPath $sourceMapPath -Encoding UTF8
$gapsPath = Join-Path $OutDir 'gaps.jsonl'; $gapRows.ToArray() | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $gapsPath -Encoding UTF8
$eventsPath = Join-Path $OutDir 'events.jsonl'; @($plan.events) | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $eventsPath -Encoding UTF8
$manifest = [ordered]@{
  schema='recorder-poc.playback-segment-export.v2'; result='PASS'; source_scope='real_closed_mxf_verified_track_decode'
  generated_utc=[datetime]::UtcNow.ToString('o');mode=$Mode;plan_path=$PlanPath;export_wav=$wavPath;wav_sha256=(Sha256Hex $wavPath)
  source_map_path=$sourceMapPath;source_map_sha256=(Sha256Hex $sourceMapPath);gaps_path=$gapsPath;events_path=$eventsPath
  synthetic_silence_is_evidence=$false;recorded_evidence_bundle_verified=$false;sample_rate_hz=8000;channels=1
  decoded_files=@($decoded.Keys | Sort-Object);decoded_media_items=($manifestItems.ToArray() | Where-Object kind -eq 'decoded_media' | Measure-Object).Count
  gaps=$gapRows.Count;items=$manifestItems.ToArray()
}
$manifestPath = Join-Path $OutDir 'export-manifest.json'
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host "REAL PLAYBACK SEGMENT EXPORT: PASS files=$($decoded.Count) intervals=$($manifest.decoded_media_items) gaps=$($manifest.gaps)"
Write-Host "Report: $manifestPath"
