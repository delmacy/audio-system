. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
$root = Get-ProjectRoot

function Test-PathBool([string]$p) { return [bool]($p -and (Test-Path -LiteralPath $p)) }

$gstBin = Find-GStreamerBin
$gstRoot = $null
if ($env:GSTREAMER_ROOT_X86_64 -and (Test-Path $env:GSTREAMER_ROOT_X86_64)) {
    $gstRoot = $env:GSTREAMER_ROOT_X86_64
} elseif ($gstBin) {
    $gstRoot = Split-Path $gstBin -Parent
}

$gstHeader = if ($gstRoot) { Join-Path $gstRoot 'include\gstreamer-1.0\gst\gst.h' } else { $null }
$gstProps  = if ($gstRoot) { Join-Path $gstRoot 'share\vs\2010\libs\gstreamer-1.0.props' } else { $null }

$vswhere = $null
if (${env:ProgramFiles(x86)}) {
    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $candidate) { $vswhere = $candidate }
}

$vsInstall = $null
$msbuild = Find-Executable @('MSBuild.exe','msbuild')
$vcTools = $null
$windowsSdk = $null
$vsVersion = $null
$platformToolset = $null

if ($vswhere) {
    $vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    $vsVersion = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion | Select-Object -First 1)
    if (-not $vsInstall) {
        $vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Workload.VCTools -property installationPath | Select-Object -First 1)
        $vsVersion = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Workload.VCTools -property installationVersion | Select-Object -First 1)
    }
    if ($vsInstall) {
        $candidateMsbuild = Join-Path $vsInstall 'MSBuild\Current\Bin\MSBuild.exe'
        if ((-not $msbuild) -and (Test-Path $candidateMsbuild)) { $msbuild = $candidateMsbuild }
        $vcRoot = Join-Path $vsInstall 'VC\Tools\MSVC'
        if (Test-Path $vcRoot) {
            $vcTools = Get-ChildItem -LiteralPath $vcRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
        }
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
if (-not $platformToolset -and $vsInstall) {
    if ($vsInstall -match '\\2019\\') { $platformToolset = 'v142' }
    elseif ($vsInstall -match '\\2022\\') { $platformToolset = 'v143' }
}

$kitsRoot = ${env:ProgramFiles(x86)}
if ($kitsRoot) {
    $kitsInclude = Join-Path $kitsRoot 'Windows Kits\10\Include'
    if (Test-Path $kitsInclude) {
        $windowsSdk = Get-ChildItem -LiteralPath $kitsInclude -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
    }
}

$rows = @(
    [pscustomobject]@{ Check='GStreamer runtime'; Required=$true;  Present=[bool]$gstBin; Detail=$gstBin },
    [pscustomobject]@{ Check='GStreamer dev header gst.h'; Required=$true; Present=(Test-PathBool $gstHeader); Detail=$gstHeader },
    [pscustomobject]@{ Check='GStreamer VS property sheet'; Required=$true; Present=(Test-PathBool $gstProps); Detail=$gstProps },
    [pscustomobject]@{ Check='vswhere'; Required=$false; Present=[bool]$vswhere; Detail=$vswhere },
    [pscustomobject]@{ Check='Visual C++ x64/x86 tools'; Required=$true; Present=[bool]$vcTools; Detail=$vcTools },
    [pscustomobject]@{ Check='Platform toolset'; Required=$true; Present=[bool]$platformToolset; Detail=$platformToolset },
    [pscustomobject]@{ Check='MSBuild'; Required=$true; Present=[bool]$msbuild; Detail=$msbuild },
    [pscustomobject]@{ Check='Windows SDK'; Required=$true; Present=[bool]$windowsSdk; Detail=$windowsSdk }
)

Write-Host '=== Native MXF-Lab prerequisites ===' -ForegroundColor Cyan
$rows | Format-Table -AutoSize

$runDir = Ensure-RunDirectory
$out = Join-Path $runDir ('native-prereqs-' + (Get-Date -Format yyyyMMdd-HHmmss) + '.json')
[ordered]@{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    gstreamer_root = $gstRoot
    vs_install = $vsInstall
    vs_version = $vsVersion
    platform_toolset = $platformToolset
    msbuild = $msbuild
    vc_tools = $vcTools
    windows_sdk = $windowsSdk
    checks = $rows
} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $out
Write-Host "Inventory written to: $out"

$missing = @($rows | Where-Object { $_.Required -and -not $_.Present })
if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host 'NATIVE BUILD PREREQUISITES: NOT READY' -ForegroundColor Yellow
    foreach ($m in $missing) { Write-Host ('  MISSING: ' + $m.Check) -ForegroundColor Yellow }
    Write-Host ''
    Write-Host 'Required Visual Studio workload: Desktop development with C++ / Microsoft.VisualStudio.Workload.VCTools'
    Write-Host 'Required GStreamer package: 64-bit MSVC Development files matching the installed runtime.'
    exit 2
}

Write-Host 'NATIVE BUILD PREREQUISITES: PASS' -ForegroundColor Green
exit 0
