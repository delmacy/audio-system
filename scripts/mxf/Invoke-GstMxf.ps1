param(
    [ValidateRange(1,200)][int]$Tracks = 2,
    [ValidateRange(1,600)][int]$Seconds = 10,
    [string]$Output,
    [switch]$KeepPipelineText
)
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
Assert-GStreamerMxf

$gst = Get-GstTool 'gst-launch-1.0.exe'
$runDir = Ensure-RunDirectory
if (-not $Output) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Output = Join-Path $runDir ("gst-$Tracks-tracks-$stamp.mxf")
} elseif (-not [IO.Path]::IsPathRooted($Output)) {
    $Output = Join-Path (Get-ProjectRoot) $Output
}
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path (Split-Path $Output -Parent) | Out-Null

# 160 samples at 8 kHz = 20 ms per buffer; 50 buffers per second.
$buffers = $Seconds * 50
$args = New-Object System.Collections.Generic.List[string]
$args.Add('-e')
$gstOutput = $Output -replace '\\','/'
$args.Add('mxfmux'); $args.Add('name=m')
$args.Add('!'); $args.Add('filesink'); $args.Add("location=$gstOutput")

for ($i=0; $i -lt $Tracks; $i++) {
    $freq = 300 + (($i * 37) % 900)
    $args.Add('audiotestsrc')
    $args.Add('is-live=false')
    $args.Add("num-buffers=$buffers")
    $args.Add('samplesperbuffer=160')
    $args.Add("freq=$freq")
    $args.Add('!')
    $args.Add('audio/x-raw,format=S16LE,rate=8000,channels=1')
    $args.Add('!'); $args.Add('alawenc')
    $args.Add('!'); $args.Add('queue')
    $args.Add('max-size-buffers=100')
    $args.Add('!'); $args.Add('m.')
}

$pipelineText = ($args -join ' ')
if ($KeepPipelineText) {
    Set-Content -Encoding UTF8 -Path ($Output + '.pipeline.txt') -Value $pipelineText
}

Write-Host "Creating MXF: $Output"
Write-Host "Tracks: $Tracks | Duration: $Seconds s | Expected A-law payload: $([math]::Round($Tracks * $Seconds * 8000 / 1MB, 3)) MiB"
$sw = [Diagnostics.Stopwatch]::StartNew()
& $gst @args
$rc = $LASTEXITCODE
$sw.Stop()
if ($rc -ne 0) { throw "gst-launch failed with exit code $rc" }

if (-not (Test-Path -LiteralPath $Output)) {
    throw ("gst-launch returned success but MXF was not created: {0}`nPipeline: {1}" -f $Output, $pipelineText)
}
$file = Get-Item -LiteralPath $Output
$result = [ordered]@{
    tracks = $Tracks
    seconds = $Seconds
    elapsed_ms = $sw.ElapsedMilliseconds
    file_bytes = $file.Length
    output = $Output
}
$result | ConvertTo-Json | Set-Content -Encoding UTF8 ($Output + '.json')
$result | Format-List
Write-Host 'GST MXF WRITE: PASS' -ForegroundColor Green
