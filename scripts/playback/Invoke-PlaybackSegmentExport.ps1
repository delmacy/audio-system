[CmdletBinding()]
param(
  [string]$PlanPath = "",
  [ValidateSet("only_audio","continuous","evidence_bundle")]
  [string]$Mode = "only_audio",
  [string]$OutDir = "runs/playback/segment-export-smoke",
  [int]$SampleRateHz = 8000,
  [int]$MsPerPlanSecond = 10,
  [int]$MaxItemRenderMs = 2500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Utc([string]$s) {
  return [DateTime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
}
function Iso([DateTime]$d) { return $d.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [Globalization.CultureInfo]::InvariantCulture) }
function MsBetween([DateTime]$a,[DateTime]$b) { return [Math]::Round((($b.ToUniversalTime().Ticks - $a.ToUniversalTime().Ticks) / [TimeSpan]::TicksPerMillisecond),3) }

function Write-WavPcm16Mono([string]$Path, [int[]]$Samples, [int]$SampleRate) {
  $dir = Split-Path -Parent $Path
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $dataBytes = $Samples.Count * 2
  $riffSize = 36 + $dataBytes
  $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
  try {
    $bw = New-Object System.IO.BinaryWriter($fs, [Text.Encoding]::ASCII, $false)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $bw.Write([UInt32]$riffSize)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
    $bw.Write([Text.Encoding]::ASCII.GetBytes('fmt '))
    $bw.Write([UInt32]16)
    $bw.Write([UInt16]1)       # PCM
    $bw.Write([UInt16]1)       # mono
    $bw.Write([UInt32]$SampleRate)
    $bw.Write([UInt32]($SampleRate * 2))
    $bw.Write([UInt16]2)
    $bw.Write([UInt16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('data'))
    $bw.Write([UInt32]$dataBytes)
    foreach ($s in $Samples) { $bw.Write([Int16]$s) }
  } finally { $fs.Dispose() }
}

function Add-Tone([System.Collections.Generic.List[int]]$Samples, [int]$DurationMs, [int]$SampleRate, [double]$Hz, [double]$Amp) {
  $n = [Math]::Max(1, [int][Math]::Round($DurationMs * $SampleRate / 1000.0))
  $start = $Samples.Count
  for ($i=0; $i -lt $n; $i++) {
    $v = [Math]::Sin(2.0 * [Math]::PI * $Hz * (($start + $i) / [double]$SampleRate)) * $Amp
    $Samples.Add([int][Math]::Round($v))
  }
}
function Add-Silence([System.Collections.Generic.List[int]]$Samples, [int]$DurationMs, [int]$SampleRate) {
  $n = [Math]::Max(1, [int][Math]::Round($DurationMs * $SampleRate / 1000.0))
  for ($i=0; $i -lt $n; $i++) { $Samples.Add(0) }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ([string]::IsNullOrWhiteSpace($PlanPath)) {
  $planObj = & (Join-Path $PSScriptRoot 'Invoke-HistoricalPlaybackPlan.ps1') -Mode continuous -OutDir $OutDir
  $PlanPath = Join-Path $OutDir 'historical-playback-plan.json'
} else {
  if (-not (Test-Path -LiteralPath $PlanPath)) { throw "PlanPath not found: $PlanPath" }
  $planObj = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json
  Copy-Item -LiteralPath $PlanPath -Destination (Join-Path $OutDir 'historical-playback-plan.json') -Force
}

# Re-read normalized JSON to avoid mixed stdout/object pipeline surprises.
$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json
if ($plan.schema -ne 'recorder-poc.historical-playback-plan.v1') { throw "Unsupported plan schema: $($plan.schema)" }

$samples = New-Object 'System.Collections.Generic.List[int]'
$sourceRows = New-Object 'System.Collections.Generic.List[string]'
$manifestItems = New-Object 'System.Collections.Generic.List[object]'
$renderCursorMs = 0
$itemOrdinal = 0
foreach ($item in @($plan.items)) {
  $itemOrdinal++
  $durationPlanMs = [double]$item.duration_ms
  $renderMs = [int][Math]::Min($MaxItemRenderMs, [Math]::Max(1, [Math]::Round(($durationPlanMs / 1000.0) * $MsPerPlanSecond)))
  if ($item.kind -eq 'media') {
    # Construction harness: deterministic tone represents decoded media from the resolved MXF track.
    # Production replaces this with MXF/TrackInstanceUUID decode.
    $freq = 420 + (($itemOrdinal * 37) % 260)
    Add-Tone -Samples $samples -DurationMs $renderMs -SampleRate $SampleRateHz -Hz $freq -Amp 6000
    $manifestItems.Add([pscustomobject]@{
      kind='decoded_media'; ordinal=$itemOrdinal; render_from_ms=$renderCursorMs; render_to_ms=($renderCursorMs+$renderMs);
      logical_track_uuid=$item.logical_track_uuid; file_id=$item.file_id; path=$item.path; track_instance_uuid=$item.track_instance_uuid; track_index=$item.track_index;
      valid_from_utc=$item.valid_from_utc; valid_to_utc=$item.valid_to_utc; plan_duration_ms=$item.duration_ms; render_duration_ms=$renderMs; decoder='phase14_harness_tone'
    })
    $sourceRows.Add(('media,{0},{1},{2},{3},{4},{5},{6}' -f $itemOrdinal,$item.file_id,$item.track_instance_uuid,$item.track_index,$item.valid_from_utc,$item.valid_to_utc,$item.path))
    $renderCursorMs += $renderMs
  } elseif ($item.kind -eq 'gap') {
    $includeGapSilence = ($Mode -eq 'continuous' -or $Mode -eq 'evidence_bundle')
    if ($includeGapSilence) {
      Add-Silence -Samples $samples -DurationMs $renderMs -SampleRate $SampleRateHz
      $manifestItems.Add([pscustomobject]@{
        kind='synthetic_gap_silence'; ordinal=$itemOrdinal; render_from_ms=$renderCursorMs; render_to_ms=($renderCursorMs+$renderMs);
        reason=$item.reason; from_utc=$item.from_utc; to_utc=$item.to_utc; plan_duration_ms=$item.duration_ms; render_duration_ms=$renderMs;
        source='no_recorded_media_gap'; not_evidence_audio=$true
      })
      $sourceRows.Add(('gap,{0},,,,,{1},{2}' -f $itemOrdinal,$item.from_utc,$item.to_utc))
      $renderCursorMs += $renderMs
    } else {
      $manifestItems.Add([pscustomobject]@{
        kind='omitted_gap'; ordinal=$itemOrdinal; reason=$item.reason; from_utc=$item.from_utc; to_utc=$item.to_utc; plan_duration_ms=$item.duration_ms; render_duration_ms=0; not_evidence_audio=$true
      })
      $sourceRows.Add(('gap_omitted,{0},,,,,{1},{2}' -f $itemOrdinal,$item.from_utc,$item.to_utc))
    }
  }
}

$wavPath = Join-Path $OutDir 'export.wav'
Write-WavPcm16Mono -Path $wavPath -Samples $samples -SampleRate $SampleRateHz

$eventsPath = Join-Path $OutDir 'events.jsonl'
@($plan.events) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } | Set-Content -Encoding UTF8 $eventsPath

$sourceMapPath = Join-Path $OutDir 'source-map.csv'
@('kind,ordinal,file_id,track_instance_uuid,track_index,valid_from_utc,valid_to_utc,path') + @($sourceRows) | Set-Content -Encoding UTF8 $sourceMapPath

$exportManifest = [ordered]@{
  schema='recorder-poc.playback-segment-export.v1'
  generated_utc=Iso ([DateTime]::UtcNow)
  mode=$Mode
  sample_rate_hz=$SampleRateHz
  channels=1
  output_codec='PCM_S16LE'
  output_container='WAV'
  source_codec='PCMA'
  plan_path=(Join-Path $OutDir 'historical-playback-plan.json')
  export_wav=$wavPath
  fabricate_recorded_silence=$false
  gap_policy= if ($Mode -eq 'only_audio') { 'omit_from_audio_keep_in_manifest' } else { 'synthesize_silence_marked_not_evidence' }
  items=@($manifestItems)
  summary=[ordered]@{
    rendered_items=@($manifestItems).Count
    decoded_media_items=@($manifestItems | Where-Object kind -eq 'decoded_media').Count
    synthetic_gap_silence_items=@($manifestItems | Where-Object kind -eq 'synthetic_gap_silence').Count
    omitted_gap_items=@($manifestItems | Where-Object kind -eq 'omitted_gap').Count
    distinct_files=@(@($manifestItems | Where-Object kind -eq 'decoded_media' | Select-Object -ExpandProperty file_id -Unique)).Count
    distinct_track_instances=@(@($manifestItems | Where-Object kind -eq 'decoded_media' | Select-Object -ExpandProperty track_instance_uuid -Unique)).Count
    rendered_duration_ms=$renderCursorMs
    sample_count=$samples.Count
  }
}
$manifestPath = Join-Path $OutDir 'export-manifest.json'
$exportManifest | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $manifestPath

Write-Host "Playback export bundle: $OutDir"
Write-Host "Export WAV: $wavPath"
Write-Host ("Decoded media={0} synthetic_gap_silence={1} omitted_gaps={2} files={3} track_instances={4}" -f $exportManifest.summary.decoded_media_items,$exportManifest.summary.synthetic_gap_silence_items,$exportManifest.summary.omitted_gap_items,$exportManifest.summary.distinct_files,$exportManifest.summary.distinct_track_instances)
Write-Output $exportManifest
