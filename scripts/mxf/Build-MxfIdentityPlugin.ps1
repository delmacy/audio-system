Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
$root = Get-ProjectRoot
$pluginRoot = Join-Path $root 'src\mxf-identity-plugin'
$proj = Join-Path $pluginRoot 'mxfidentity.vcxproj'
& (Join-Path $pluginRoot 'Fetch-And-Patch.ps1')

$gstRoot = $env:GSTREAMER_ROOT_X86_64
if (-not $gstRoot) { $bin = Find-GStreamerBin; if ($bin) { $gstRoot = Split-Path $bin -Parent } }
if (-not $gstRoot) { throw 'GStreamer not found.' }
$env:GSTREAMER_ROOT_X86_64 = $gstRoot

foreach ($props in @('gstreamer-1.0.props','gstreamer-base-1.0.props','gstreamer-audio-1.0.props','gstreamer-video-1.0.props')) {
    $p = Join-Path $gstRoot ('share\vs\2010\libs\' + $props)
    if (-not (Test-Path $p)) { throw "Missing GStreamer Development property sheet: $p" }
}

$vswhere = $null
if (${env:ProgramFiles(x86)}) {
    $v = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $v) { $vswhere = $v }
}
$msbuild = Find-Executable @('MSBuild.exe','msbuild')
$vsVersion = $null
if ($vswhere) {
    $install = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    $vsVersion = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion | Select-Object -First 1)
    if (-not $msbuild -and $install) {
        $candidate = Join-Path $install 'MSBuild\Current\Bin\MSBuild.exe'
        if (Test-Path $candidate) { $msbuild = $candidate }
    }
}
if (-not $msbuild) { throw 'MSBuild/C++ Build Tools not found.' }
$toolset = if ($vsVersion -and ([int](($vsVersion -split '\.')[0])) -ge 17) { 'v143' } else { 'v142' }

Write-Host "GStreamer root: $gstRoot"
Write-Host "MSBuild: $msbuild"
Write-Host "PlatformToolset: $toolset"
& $msbuild $proj /m /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=$toolset
if ($LASTEXITCODE -ne 0) { throw "MXF identity plugin build failed: $LASTEXITCODE" }

$dll = Join-Path $pluginRoot 'bin\gstmxfidentity.dll'
if (-not (Test-Path $dll)) { throw "Build returned success but plugin was not found: $dll" }
$gstBin = Join-Path $gstRoot 'bin'
if (-not (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\') -ieq $gstBin.TrimEnd('\') })) { $env:PATH = $gstBin + ';' + $env:PATH }
$env:GST_PLUGIN_PATH = (Split-Path $dll -Parent)
$registryDir = Ensure-RunDirectory -Name 'mxf-identity'
$env:GST_REGISTRY_1_0 = Join-Path $registryDir 'registry-identity-2.0.14.bin'
$inspect = Get-GstTool 'gst-inspect-1.0.exe'
& $inspect mxfidmux
if ($LASTEXITCODE -ne 0) { throw 'gstmxfidentity.dll built but mxfidmux was not discoverable.' }
Write-Host "Built isolated plugin: $dll"
Write-Host 'MXF IDENTITY PLUGIN BUILD: PASS' -ForegroundColor Green
