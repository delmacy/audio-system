$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source = Get-ChildItem -LiteralPath (Join-Path $root 'runs\playback') -Directory | Sort-Object Name -Descending |
  Where-Object { $_.Name -match '^real-segment-export-\d{8}-\d{9}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'export-manifest.json')) } | Select-Object -First 1
if (-not $source) { throw 'No real decoded playback export found.' }
$decoded = Get-Content -LiteralPath (Join-Path $source.FullName 'export-manifest.json') -Raw | ConvertFrom-Json
if ($decoded.result -ne 'PASS' -or $decoded.source_scope -ne 'real_closed_mxf_verified_track_decode' -or $decoded.mode -ne 'only_audio') { throw 'Export source must be verified recorded media in only_audio mode.' }
function Sha256Hex([string]$path) {
  $sha = [Security.Cryptography.SHA256]::Create(); $stream = [IO.File]::OpenRead($path)
  try { [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
  finally { $stream.Dispose(); $sha.Dispose() }
}
if ((Sha256Hex $decoded.export_wav) -ne $decoded.wav_sha256 -or (Sha256Hex $decoded.source_map_path) -ne $decoded.source_map_sha256) { throw 'Decoded export hash mismatch.' }
$plan = Get-Content -LiteralPath $decoded.plan_path -Raw | ConvertFrom-Json
if ($plan.source_scope -ne 'sqlite_temporal_index_from_closed_mxf') { throw 'Playback plan did not originate from SQLite.' }
$runDir = Join-Path $root ('runs\export\evidence-bundle-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
$bundle = Join-Path $runDir 'export-bundle'
$audioDir = Join-Path $bundle 'audio'; $manifestDir = Join-Path $bundle 'manifest'; $hashDir = Join-Path $bundle 'hashes'
New-Item -ItemType Directory -Force -Path $audioDir,$manifestDir,$hashDir | Out-Null
Copy-Item -LiteralPath $decoded.export_wav -Destination (Join-Path $audioDir 'export.wav')
Copy-Item -LiteralPath $decoded.source_map_path -Destination (Join-Path $manifestDir 'source-map.csv')
Copy-Item -LiteralPath $decoded.gaps_path -Destination (Join-Path $manifestDir 'gaps.jsonl')
Copy-Item -LiteralPath $decoded.events_path -Destination (Join-Path $manifestDir 'timeline-events.jsonl')
Copy-Item -LiteralPath (Join-Path $source.FullName 'export-manifest.json') -Destination (Join-Path $manifestDir 'export-manifest.json')
Copy-Item -LiteralPath $decoded.plan_path -Destination (Join-Path $manifestDir 'historical-playback-plan.json')
$files = @()
foreach ($item in @($plan.items | Where-Object kind -eq 'media')) {
  if (@($files | Where-Object file_id -eq $item.file_id).Count -gt 0) { continue }
  $path = if ([IO.Path]::IsPathRooted([string]$item.path)) { [string]$item.path } else { Join-Path $root ([string]$item.path) }
  if (-not (Test-Path -LiteralPath $path)) { throw "Source MXF missing: $path" }
  $hash = Sha256Hex $path
  if ($hash -ne [string]$item.mxf_sha256) { throw "Source MXF hash mismatch: $path" }
  $files += [pscustomobject]@{
    file_id=$item.file_id; mxf_path=$path; mxf_sha256=$hash; logical_track_uuid=$item.logical_track_uuid
    track_instance_uuid=$item.track_instance_uuid; track_index=$item.track_index; segment_sequence=$item.segment_sequence
  }
}
if ($files.Count -eq 0) { throw 'Evidence bundle has no recorded MXF source.' }
$sourceManifestPath = Join-Path $manifestDir 'source-recording-files.json'
[ordered]@{schema='recorder-poc.source-recording-files.v1';files=$files} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sourceManifestPath -Encoding UTF8
$readme = Join-Path $bundle 'README-EVIDENCE.txt'
@'
Recorder PoC recorded-media export bundle.
The WAV comes from closed MXF tracks whose LT/TI and hashes were verified before decoding.
Gaps are listed in manifest/gaps.jsonl and omitted from the WAV.
Live buffers, fixtures and synthetic silence are not recorded evidence.
The source MXFs remain at the paths in manifest/source-recording-files.json.
'@ | Set-Content -LiteralPath $readme -Encoding UTF8
$hashFile = Join-Path $hashDir 'file-hashes.sha256'
$hashLines = @()
Get-ChildItem -LiteralPath $bundle -File -Recurse | Where-Object { $_.FullName -notlike "$hashDir*" } | Sort-Object FullName | ForEach-Object {
  $relative = $_.FullName.Substring($bundle.Length + 1).Replace('\','/')
  $hashLines += ('{0}  {1}' -f (Sha256Hex $_.FullName),$relative)
}
$hashLines | Set-Content -LiteralPath $hashFile -Encoding ASCII
$packageHash = Sha256Hex $hashFile
$packageHashPath = Join-Path $hashDir 'package-hash.txt'
$packageHash | Set-Content -LiteralPath $packageHashPath -Encoding ASCII
foreach ($line in Get-Content -LiteralPath $hashFile) {
  if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "Malformed hash line: $line" }
  $target = Join-Path $bundle $Matches[2]
  if ((Sha256Hex $target) -ne $Matches[1]) { throw "Bundle file hash mismatch: $target" }
}
if ((Get-Content -LiteralPath $packageHashPath -Raw).Trim() -ne (Sha256Hex $hashFile)) { throw 'Package hash mismatch.' }
$report = [ordered]@{
  schema='recorder-poc.evidence-bundle-smoke.v2';result='PASS';scope='recorded_mxf_decode_bundle_integrity'
  bundle=$bundle;source_mxf_count=$files.Count;source_mxf_hashes_verified=$true;decoded_wav_hash_verified=$true
  bundle_files_verified=$hashLines.Count;package_hash=$packageHash;gaps_omitted_from_wav=$true
  recorder_file_manifests_present=$false;integrated_acceptance_complete=$false
}
$reportPath = Join-Path $runDir 'evidence-bundle-report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host "RECORDED-MEDIA EXPORT BUNDLE: PASS sources=$($files.Count) files=$($hashLines.Count)"
Write-Host "Report: $reportPath"
