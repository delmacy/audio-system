. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')

$runDir = Ensure-RunDirectory
$gstBin = Find-GStreamerBin
$gstLaunch = Get-GstTool 'gst-launch-1.0.exe'
$gstInspect = Get-GstTool 'gst-inspect-1.0.exe'
$gstDiscoverer = Get-GstTool 'gst-discoverer-1.0.exe'
$ffmpeg = Find-Executable @('ffmpeg.exe','ffmpeg')
$ffprobe = Find-Executable @('ffprobe.exe','ffprobe')
$cl = Find-Executable @('cl.exe','cl')
$msbuild = Find-Executable @('MSBuild.exe','msbuild')

$plugins = [ordered]@{}
if ($gstInspect) {
    foreach ($p in @('mxfmux','mxfdemux','alawenc','alawdec','audiotestsrc','rawaudioparse')) {
        & $gstInspect $p *> $null
        $plugins[$p] = ($LASTEXITCODE -eq 0)
    }
}

$version = $null
if ($gstLaunch) {
    $version = (& $gstLaunch --version 2>&1 | Out-String).Trim()
}

$inventory = [ordered]@{
    TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
    Hostname = $env:COMPUTERNAME
    PowerShell = $PSVersionTable.PSVersion.ToString()
    GStreamerBin = $gstBin
    GstLaunch = $gstLaunch
    GstInspect = $gstInspect
    GstDiscoverer = $gstDiscoverer
    GStreamerVersion = $version
    Plugins = $plugins
    FFmpeg = $ffmpeg
    FFprobe = $ffprobe
    CL = $cl
    MSBuild = $msbuild
    GStreamerRootX64 = $env:GSTREAMER_ROOT_X86_64
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $runDir "phase2-$stamp-inventory.json"
$inventory | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $out
$inventory | Format-List
Write-Host "`nInventory written to: $out"

if (-not $gstLaunch) {
    Write-Host "`nGStreamer runtime was NOT found." -ForegroundColor Yellow
    Write-Host 'Install the official 64-bit MSVC GStreamer Runtime. For the native 500/1000-track harness, also install Development files and MSVC Build Tools.'
    exit 2
}

if (-not ($plugins['mxfmux'] -and $plugins['mxfdemux'] -and $plugins['alawenc'])) {
    Write-Host "`nGStreamer is installed, but the required MXF/A-law plugins are incomplete." -ForegroundColor Yellow
    exit 3
}

Write-Host "`nPHASE-2 PREREQUISITES: PASS" -ForegroundColor Green
