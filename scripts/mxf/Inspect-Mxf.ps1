param([Parameter(Mandatory=$true)][string]$Path)
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path (Get-ProjectRoot) $Path }
$Path = [IO.Path]::GetFullPath($Path)
if (-not (Test-Path $Path)) { throw "MXF not found: $Path" }

$ffprobe = Find-Executable @('ffprobe.exe','ffprobe')
if ($ffprobe) {
    Write-Host 'Inspector: ffprobe'
    & $ffprobe -v error -show_entries stream=index,codec_name,codec_type,sample_rate,channels -of json $Path
    exit $LASTEXITCODE
}

$discover = Get-GstTool 'gst-discoverer-1.0.exe'
if ($discover) {
    Write-Host 'Inspector: gst-discoverer-1.0'
    & $discover -v $Path
    exit $LASTEXITCODE
}

Write-Warning 'No ffprobe or gst-discoverer found. Build the native mxf-lab harness and use: mxf-lab.exe inspect <file.mxf>'
exit 2
