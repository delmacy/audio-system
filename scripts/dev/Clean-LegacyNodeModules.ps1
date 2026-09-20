param(
    [switch]$StopProjectNode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LegacyNodeModules = Join-Path $ProjectRoot 'web\player-app\node_modules'

function Write-CleanLog {
    param([string]$Message,[ConsoleColor]$Color=[ConsoleColor]::Gray)
    Write-Host "[cleanup] $Message" -ForegroundColor $Color
}

if (-not (Test-Path -LiteralPath $LegacyNodeModules)) {
    Write-CleanLog 'Legacy web/player-app/node_modules is already absent.' Green
    exit 0
}

if ($StopProjectNode) {
    Write-CleanLog 'Stopping Node processes whose command line belongs to this repository...' Yellow
    $escapedRoot = [Regex]::Escape($ProjectRoot)
    $projectNodes = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -ieq 'node.exe' -and $_.CommandLine -and $_.CommandLine -match $escapedRoot
    }

    foreach ($proc in $projectNodes) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            Write-CleanLog "Stopped node.exe PID=$($proc.ProcessId)" DarkYellow
        } catch {
            Write-CleanLog "Could not stop PID=$($proc.ProcessId): $($_.Exception.Message)" Red
        }
    }

    Start-Sleep -Milliseconds 500
}

try {
    Remove-Item -LiteralPath $LegacyNodeModules -Recurse -Force -ErrorAction Stop
    Write-CleanLog 'Removed legacy web/player-app/node_modules.' Green
} catch {
    Write-CleanLog 'Could not remove legacy node_modules. A process is probably still holding a native module.' Red
    Write-CleanLog 'Stop the dev supervisor/Vite, then rerun with -StopProjectNode.' Yellow
    throw
}

Write-CleanLog 'Root node_modules is the only dependency tree expected now.' Green
