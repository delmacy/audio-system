param(
    [int]$PollSeconds = 20,
    [switch]$NoAutoSync,
    [switch]$NoFrontend,
    [switch]$NoTimelineApi
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$WebRoot = Join-Path $ProjectRoot 'web\player-app'
$NodeModulesRoot = Join-Path $ProjectRoot 'node_modules'
$TimelineApi = Join-Path $ProjectRoot 'scripts\player\timeline_api.py'
$LogRoot = Join-Path $ProjectRoot 'runs\dev-supervisor'

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$script:FrontendProcess = $null
$script:ApiProcess = $null

function Write-DevLog {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    $stamp = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$stamp] $Message" -ForegroundColor $Color
}

function Invoke-GitText {
    param([string[]]$Arguments)
    $output = & git -C $ProjectRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
}

function Test-WorkingTreeClean {
    return [string]::IsNullOrWhiteSpace((Invoke-GitText @('status','--porcelain')))
}

function Stop-ProcessTreeSafe {
    param([System.Diagnostics.Process]$Process)
    if (-not $Process) { return }
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            & taskkill.exe /PID $Process.Id /T /F *> $null
        }
    } catch {
        Write-DevLog "Could not stop process tree PID=$($Process.Id): $($_.Exception.Message)" Yellow
    }
}

function Start-TimelineApi {
    if ($NoTimelineApi) { return }
    if (-not (Test-Path -LiteralPath $TimelineApi)) {
        Write-DevLog "Timeline API script not found: $TimelineApi" Red
        return
    }

    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $python) {
        Write-DevLog 'Python was not found in PATH; timeline API not started.' Red
        return
    }

    $stdout = Join-Path $LogRoot 'timeline-api.stdout.log'
    $stderr = Join-Path $LogRoot 'timeline-api.stderr.log'
    $script:ApiProcess = Start-Process -FilePath $python.Source -ArgumentList @($TimelineApi) -WorkingDirectory $ProjectRoot -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
    Write-DevLog "Timeline API started (PID=$($script:ApiProcess.Id), :8500)." Green
}

function Start-Frontend {
    if ($NoFrontend) { return }
    if (-not (Test-Path -LiteralPath $WebRoot)) {
        Write-DevLog "Frontend directory not found: $WebRoot" Red
        return
    }

    $nodeModules = $NodeModulesRoot
    if (-not (Test-Path -LiteralPath $nodeModules)) {
        Write-DevLog 'node_modules missing; running npm install...' Cyan
        & npm.cmd --prefix $ProjectRoot install
        if ($LASTEXITCODE -ne 0) { throw 'npm install failed.' }
    }

    $stdout = Join-Path $LogRoot 'vite.stdout.log'
    $stderr = Join-Path $LogRoot 'vite.stderr.log'
    $script:FrontendProcess = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d','/s','/c','npm run dev') -WorkingDirectory $ProjectRoot -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
    Write-DevLog "Frontend started (PID=$($script:FrontendProcess.Id), normally :5173)." Green
}

function Ensure-ChildrenRunning {
    if (-not $NoFrontend) {
        $restartFrontend = $false
        if (-not $script:FrontendProcess) {
            $restartFrontend = $true
        } else {
            try {
                $script:FrontendProcess.Refresh()
                if ($script:FrontendProcess.HasExited) { $restartFrontend = $true }
            } catch { $restartFrontend = $true }
        }
        if ($restartFrontend) {
            Write-DevLog 'Frontend process is not running; starting it.' Yellow
            Start-Frontend
        }
    }

    if (-not $NoTimelineApi) {
        $restartApi = $false
        if (-not $script:ApiProcess) {
            $restartApi = $true
        } else {
            try {
                $script:ApiProcess.Refresh()
                if ($script:ApiProcess.HasExited) { $restartApi = $true }
            } catch { $restartApi = $true }
        }
        if ($restartApi) {
            Write-DevLog 'Timeline API process is not running; starting it.' Yellow
            Start-TimelineApi
        }
    }
}

function Restart-TimelineApi {
    if ($NoTimelineApi) { return }
    Write-DevLog 'Python timeline files changed; restarting timeline API...' Cyan
    Stop-ProcessTreeSafe $script:ApiProcess
    $script:ApiProcess = $null
    Start-TimelineApi
}

function Restart-Frontend {
    if ($NoFrontend) { return }
    Write-DevLog 'Frontend runtime/dependencies changed; restarting Vite...' Cyan
    Stop-ProcessTreeSafe $script:FrontendProcess
    $script:FrontendProcess = $null
    Start-Frontend
}

function Sync-Main {
    if ($NoAutoSync) { return }

    $branch = Invoke-GitText @('branch','--show-current')
    if ($branch -ne 'main') {
        Write-DevLog "Auto-sync paused: current branch is '$branch', not 'main'." Yellow
        return
    }

    & git -C $ProjectRoot fetch --quiet origin main
    if ($LASTEXITCODE -ne 0) {
        Write-DevLog 'git fetch origin main failed; will retry on next cycle.' Red
        return
    }

    $local = Invoke-GitText @('rev-parse','HEAD')
    $remote = Invoke-GitText @('rev-parse','origin/main')
    if ($local -eq $remote) { return }

    if (-not (Test-WorkingTreeClean)) {
        Write-DevLog 'Remote main changed, but local files are modified. Auto-pull skipped to protect your work.' Yellow
        return
    }

    $base = Invoke-GitText @('merge-base','HEAD','origin/main')
    if ($base -ne $local) {
        Write-DevLog 'Local main is not a fast-forward ancestor of origin/main. Auto-pull skipped.' Red
        return
    }

    $changed = Invoke-GitText @('diff','--name-only',"$local..$remote")
    $changedFiles = @($changed -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    Write-DevLog "New origin/main detected: $($local.Substring(0,7)) -> $($remote.Substring(0,7))" Cyan

    & git -C $ProjectRoot pull --ff-only --quiet origin main
    if ($LASTEXITCODE -ne 0) {
        Write-DevLog 'git pull --ff-only failed.' Red
        return
    }

    Write-DevLog 'Local main updated successfully.' Green

    $packageChanged = $changedFiles | Where-Object { $_ -in @('package.json','package-lock.json','web/player-app/package.json') }
    if ($packageChanged) {
        Write-DevLog 'Frontend dependencies changed; running npm install...' Cyan
        & npm.cmd --prefix $WebRoot install
        if ($LASTEXITCODE -ne 0) { Write-DevLog 'npm install failed after update.' Red }
    }

    $apiChanged = $changedFiles | Where-Object { $_ -like 'scripts/player/*.py' }
    if ($apiChanged) { Restart-TimelineApi }

    $frontendRuntimeChanged = $changedFiles | Where-Object { $_ -in @('package.json','package-lock.json','web/player-app/package.json','web/player-app/vite.config.ts') }
    if ($frontendRuntimeChanged) {
        Restart-Frontend
    } else {
        $frontendSourceChanged = $changedFiles | Where-Object { $_ -like 'web/player-app/src/*' -or $_ -like 'web/player-app/src/*/*' -or $_ -like 'web/player-app/src/*/*/*' }
        if ($frontendSourceChanged) {
            Write-DevLog 'Frontend source changed; Vite HMR will refresh the browser automatically.' DarkGray
        }
    }
}

Write-DevLog 'Audio System dev supervisor' Cyan
Write-DevLog "Repository: $ProjectRoot" DarkGray
Write-DevLog "Auto-sync: $(-not $NoAutoSync) every $PollSeconds s" DarkGray
Write-DevLog 'Press Ctrl+C to stop.' DarkGray

try {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'git.exe was not found in PATH.' }
    if (-not $NoFrontend -and -not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'npm.cmd was not found in PATH.' }

    Sync-Main
    Start-Frontend
    Start-TimelineApi

    while ($true) {
        Start-Sleep -Seconds ([Math]::Max(5,$PollSeconds))
        Sync-Main
        Ensure-ChildrenRunning
    }
}
finally {
    Write-DevLog 'Stopping local services...' Yellow
    Stop-ProcessTreeSafe $script:FrontendProcess
    Stop-ProcessTreeSafe $script:ApiProcess
    Write-DevLog 'Stopped.' DarkGray
}
