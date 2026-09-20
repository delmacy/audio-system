param(
    [string]$Manifest = 'media-bank/manifests/clips-manifest.csv',
    [switch]$OnlyAccepted,
    [switch]$Normalize
)

. "$PSScriptRoot\Common-MediaBank.ps1"
$root = Get-RepoRoot
$manifestPath = Join-Root $root $Manifest
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }
$ffmpeg = Find-FFmpeg
if ($null -eq $ffmpeg) { throw 'ffmpeg.exe not found. Install FFmpeg at C:\ffmpeg\bin or add it to PATH.' }
$rows = @(Import-Csv -LiteralPath $manifestPath)
if ($OnlyAccepted) { $rows = @($rows | Where-Object { $_.review_status -eq 'accepted' }) }
$cut = 0
foreach ($r in $rows) {
    $src = [string]$r.source_file
    if (-not (Test-Path -LiteralPath $src)) { Write-Warning "Missing source: $src"; continue }
    $dest = Join-Root $root ([string]$r.output_path)
    Ensure-Dir (Split-Path -Parent $dest) | Out-Null
    $start = [double]::Parse([string]$r.start_sec,[Globalization.CultureInfo]::InvariantCulture)
    $end = [double]::Parse([string]$r.end_sec,[Globalization.CultureInfo]::InvariantCulture)
    $dur = [Math]::Max(0.05, $end-$start)
    $af = 'aresample=8000,aformat=channel_layouts=mono'
    if ($Normalize) { $af = 'loudnorm=I=-20:TP=-2:LRA=11,' + $af }
    $args = @('-y','-hide_banner','-nostats','-ss',('{0:F3}' -f $start),'-t',('{0:F3}' -f $dur),'-i',$src,'-vn','-ac','1','-ar','8000','-af',$af,'-c:a','pcm_s16le',$dest)
    & $ffmpeg @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg failed for $src -> $dest" }
    $cut++
}
Write-Host ('Manifest rows: {0}' -f $rows.Count)
Write-Host ('Clips cut: {0}' -f $cut)
Write-Host 'MEDIA BANK CUT MANIFEST: PASS'
