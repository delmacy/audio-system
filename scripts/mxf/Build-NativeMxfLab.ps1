. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
$root = Get-ProjectRoot
$proj = Join-Path $root 'src\mxf-lab\mxf-lab.vcxproj'

$gstRoot = $env:GSTREAMER_ROOT_X86_64
if (-not $gstRoot) {
    $bin = Find-GStreamerBin
    if ($bin) { $gstRoot = Split-Path $bin -Parent }
}
if (-not $gstRoot) { throw 'GStreamer runtime not found. Run 00-inventory.cmd.' }

$gstHeader = Join-Path $gstRoot 'include\gstreamer-1.0\gst\gst.h'
$gstProps = Join-Path $gstRoot 'share\vs\2010\libs\gstreamer-1.0.props'
if (-not (Test-Path $gstHeader) -or -not (Test-Path $gstProps)) {
    throw 'GStreamer Development files were not found. Install the matching 64-bit MSVC Development package.'
}
$env:GSTREAMER_ROOT_X86_64 = $gstRoot

$msbuild = Find-Executable @('MSBuild.exe','msbuild')
$vswhere = $null
if (${env:ProgramFiles(x86)}) {
    $candidateVswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $candidateVswhere) { $vswhere = $candidateVswhere }
}
if (-not $msbuild -and $vswhere) {
    $install = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if (-not $install) {
        $install = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Workload.VCTools -property installationPath | Select-Object -First 1)
    }
    if ($install) {
        $candidate = Join-Path $install 'MSBuild\Current\Bin\MSBuild.exe'
        if (Test-Path $candidate) { $msbuild = $candidate }
    }
}
if (-not $msbuild) { throw 'MSBuild/C++ Build Tools not found. Install Visual Studio Build Tools with Desktop development with C++.' }

# Pick the PlatformToolset that matches the Visual Studio/Build Tools installation.
# VS 2019 (16.x) => v142; VS 2022 (17.x) => v143.
$platformToolset = $null
$vsVersion = $null
if ($vswhere) {
    $vsVersion = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion | Select-Object -First 1)
    if (-not $vsVersion) {
        $vsVersion = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Workload.VCTools -property installationVersion | Select-Object -First 1)
    }
}
if ($vsVersion) {
    $major = 0
    if ([int]::TryParse(($vsVersion -split '\.' | Select-Object -First 1), [ref]$major)) {
        if ($major -ge 17) { $platformToolset = 'v143' }
        elseif ($major -eq 16) { $platformToolset = 'v142' }
        elseif ($major -eq 15) { $platformToolset = 'v141' }
    }
}
if (-not $platformToolset) {
    # Conservative fallback from the selected MSBuild path.
    if ($msbuild -match '\\2019\\') { $platformToolset = 'v142' }
    elseif ($msbuild -match '\\2022\\') { $platformToolset = 'v143' }
}
if (-not $platformToolset) {
    throw 'Could not determine the installed Visual C++ PlatformToolset.'
}

Write-Host "GStreamer root: $env:GSTREAMER_ROOT_X86_64"
Write-Host "MSBuild: $msbuild"
Write-Host "PlatformToolset: $platformToolset"
& $msbuild $proj /m /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=$platformToolset
if ($LASTEXITCODE -ne 0) { throw ("MSBuild failed with exit code {0}" -f $LASTEXITCODE) }

$exeCandidates = @(
    (Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),
    (Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')
)
$exe = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { throw 'MSBuild returned success but mxf-lab.exe was not found.' }
Write-Host "Built: $exe"

# Runtime loader/plugin self-test. Compilation alone does not prove that the
# GStreamer DLLs can be resolved when the EXE is launched.
$gstBin = Join-Path $gstRoot 'bin'
$pathParts = @($env:PATH -split ';')
if (-not ($pathParts | Where-Object { $_.TrimEnd('\\') -ieq $gstBin.TrimEnd('\\') })) {
    $env:PATH = $gstBin + ';' + $env:PATH
}
Write-Host "Runtime PATH includes: $gstBin"
& $exe selftest
if ($LASTEXITCODE -ne 0) { throw ("mxf-lab runtime self-test failed with exit code {0}" -f $LASTEXITCODE) }

Write-Host 'NATIVE MXF-LAB BUILD: PASS' -ForegroundColor Green
