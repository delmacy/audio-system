$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source = Get-ChildItem -LiteralPath (Join-Path $root 'runs\export') -Directory | Sort-Object Name -Descending |
  Where-Object { $_.Name -match '^evidence-bundle-\d{8}-\d{9}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'evidence-bundle-report.json')) } | Select-Object -First 1
if (-not $source) { throw 'No real recorded-media export bundle found.' }
$bundleReport = Get-Content -LiteralPath (Join-Path $source.FullName 'evidence-bundle-report.json') -Raw | ConvertFrom-Json
if ($bundleReport.result -ne 'PASS' -or $bundleReport.scope -ne 'recorded_mxf_decode_bundle_integrity') { throw 'Source bundle is not a recorded-media bundle.' }
$bundle = [string]$bundleReport.bundle
$hashFile = Join-Path $bundle 'hashes\file-hashes.sha256'
$packageHashPath = Join-Path $bundle 'hashes\package-hash.txt'
$sourceManifestPath = Join-Path $bundle 'manifest\source-recording-files.json'
$exportManifestPath = Join-Path $bundle 'manifest\export-manifest.json'
$planPath = Join-Path $bundle 'manifest\historical-playback-plan.json'
function Sha256Hex([string]$path) {
  $sha = [Security.Cryptography.SHA256]::Create(); $stream = [IO.File]::OpenRead($path)
  try { [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
  finally { $stream.Dispose(); $sha.Dispose() }
}
$verifiedFiles = 0
foreach ($line in Get-Content -LiteralPath $hashFile) {
  if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "Malformed hash line: $line" }
  $expected = $Matches[1]; $relative = $Matches[2]; $target = Join-Path $bundle $relative
  if (-not (Test-Path -LiteralPath $target) -or (Sha256Hex $target) -ne $expected) { throw "Bundle hash mismatch: $relative" }
  $verifiedFiles++
}
$packageHash = (Get-Content -LiteralPath $packageHashPath -Raw).Trim()
if ($packageHash -ne (Sha256Hex $hashFile)) { throw 'Package hash mismatch.' }
$sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw | ConvertFrom-Json
$exportManifest = Get-Content -LiteralPath $exportManifestPath -Raw | ConvertFrom-Json
$plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
if ($sourceManifest.schema -ne 'recorder-poc.source-recording-files.v1' -or $exportManifest.source_scope -ne 'real_closed_mxf_verified_track_decode' -or $plan.source_scope -ne 'sqlite_temporal_index_from_closed_mxf') { throw 'Manifest chain scope mismatch.' }
if ($exportManifest.mode -ne 'only_audio' -or $exportManifest.synthetic_silence_is_evidence) { throw 'Audio evidence policy mismatch.' }
$ffprobe = (Get-Command ffprobe.exe -ErrorAction Stop).Source
$verifiedSources = 0
foreach ($file in @($sourceManifest.files)) {
  if (-not (Test-Path -LiteralPath $file.mxf_path) -or (Sha256Hex $file.mxf_path) -ne $file.mxf_sha256) { throw "Source MXF hash mismatch: $($file.file_id)" }
  $matchingPlan = @($plan.items | Where-Object { $_.kind -eq 'media' -and $_.file_id -eq $file.file_id -and $_.track_instance_uuid -eq $file.track_instance_uuid -and $_.logical_track_uuid -eq $file.logical_track_uuid -and [int]$_.track_index -eq [int]$file.track_index })
  if ($matchingPlan.Count -eq 0) { throw "File identity missing from playback plan: $($file.file_id)" }
  $probeRaw = & $ffprobe -v error -show_entries 'stream=index:stream_tags=track_name' -of json $file.mxf_path
  if ($LASTEXITCODE -ne 0) { throw "Could not inspect source MXF: $($file.file_id)" }
  $streams = @((($probeRaw | Out-String | ConvertFrom-Json).streams))
  $physical = @($streams | Where-Object { [int]$_.index -eq [int]$file.track_index })
  if ($physical.Count -ne 1) { throw "Physical TrackIndex missing: $($file.file_id)" }
  $name = [string]$physical[0].tags.track_name
  if (-not $name.Contains('LT=' + [string]$file.logical_track_uuid) -or -not $name.Contains('TI=' + [string]$file.track_instance_uuid)) { throw "Embedded identity mismatch: $($file.file_id)" }
  $verifiedSources++
}
if ($verifiedSources -lt 1 -or $verifiedFiles -lt 1) { throw 'No source or bundle file was verified.' }
$wav = Join-Path $bundle 'audio\export.wav'
if ((Sha256Hex $wav) -ne $exportManifest.wav_sha256) { throw 'Export WAV hash mismatch.' }
$sourceMap = Join-Path $bundle 'manifest\source-map.csv'
if ((Sha256Hex $sourceMap) -ne $exportManifest.source_map_sha256) { throw 'Source map hash mismatch.' }
$runDir = Join-Path $root ('runs\integrity\real-manifest-chain-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$report = [ordered]@{
  schema='recorder-poc.integrity-verification-report.v2';result='PASS';scope='closed_mxf_index_plan_decode_bundle_hash_chain'
  source_bundle=$bundle;verified_source_mxfs=$verifiedSources;verified_bundle_files=$verifiedFiles
  embedded_lt_ti_track_index_verified=$true;source_map_hash_verified=$true;export_wav_hash_verified=$true;package_hash_verified=$true
  recorder_generated_file_manifests_verified=$false;integrated_acceptance_complete=$false
}
$reportPath = Join-Path $runDir 'integrity-verification-report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host "REAL MXF/INDEX/EXPORT INTEGRITY CHAIN: PASS sources=$verifiedSources bundle_files=$verifiedFiles"
Write-Host "Report: $reportPath"
