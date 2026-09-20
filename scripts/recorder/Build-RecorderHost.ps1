Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\mxf\Common-Mxf.ps1')

$root = Get-ProjectRoot
$proj = Join-Path $root 'src\recorder-host\recorder-host.vcxproj'
$pluginDll = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'

$gstRoot = $env:GSTREAMER_ROOT_X86_64
if (-not $gstRoot) {
    $bin = Find-GStreamerBin
    if ($bin) { $gstRoot = Split-Path $bin -Parent }
}
if (-not $gstRoot) { throw 'GStreamer runtime not found. Run the Phase 2 inventory first.' }
$gstHeader = Join-Path $gstRoot 'include\gstreamer-1.0\gst\gst.h'
$gstProps = Join-Path $gstRoot 'share\vs\2010\libs\gstreamer-1.0.props'
if (-not (Test-Path $gstHeader) -or -not (Test-Path $gstProps)) {
    throw 'GStreamer Development files are required for recorder-host.'
}
$env:GSTREAMER_ROOT_X86_64 = $gstRoot
$env:GSTREAMER_1_0_ROOT_MSVC_X86_64 = $gstRoot

$vswhere = $null
if (${env:ProgramFiles(x86)}) {
    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $candidate) { $vswhere = $candidate }
}
$msbuild = Find-Executable @('MSBuild.exe','msbuild')
$install = $null
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

$toolset = $null
if ($vsVersion) {
    $major = 0
    if ([int]::TryParse(($vsVersion -split '\.' | Select-Object -First 1), [ref]$major)) {
        if ($major -ge 17) { $toolset = 'v143' }
        elseif ($major -eq 16) { $toolset = 'v142' }
        elseif ($major -eq 15) { $toolset = 'v141' }
    }
}
if (-not $toolset) {
    if ($msbuild -match '\\2019\\') { $toolset = 'v142' }
    elseif ($msbuild -match '\\2022\\') { $toolset = 'v143' }
}
if (-not $toolset) { throw 'Could not determine Visual C++ PlatformToolset.' }
if (-not (Test-Path $pluginDll)) { throw 'gstmxfidentity.dll missing. Phase 2 gate 14 must already have been built.' }

Write-Host '=== Build Recorder Host ==='
Write-Host "GStreamer root: $gstRoot"
Write-Host "MSBuild: $msbuild"
Write-Host "PlatformToolset: $toolset"
& $msbuild $proj /m /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=$toolset
if ($LASTEXITCODE -ne 0) { throw "recorder-host MSBuild failed: $LASTEXITCODE" }

$exeCandidates = @(
    (Join-Path $root 'src\recorder-host\x64\Release\recorder-host.exe'),
    (Join-Path $root 'src\recorder-host\Release\recorder-host.exe')
)
$exe = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { throw 'recorder-host.exe not found after successful build.' }

$gstBin = Join-Path $gstRoot 'bin'
if (-not (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\') -ieq $gstBin.TrimEnd('\') })) {
    $env:PATH = $gstBin + ';' + $env:PATH
}

& $exe selftest --plugin-dll $pluginDll
if ($LASTEXITCODE -ne 0) { throw "recorder-host selftest failed: $LASTEXITCODE" }
Write-Host "Built: $exe"
Write-Host 'RECORDER HOST BUILD: PASS' -ForegroundColor Green
