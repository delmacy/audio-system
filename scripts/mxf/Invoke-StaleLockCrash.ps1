param(
    [int]$Tracks = 100,
    [int]$Seconds = 120,
    [int]$CrashAfterMs = 2500
)
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
. (Join-Path $PSScriptRoot 'Mxf-FileLifecycle.ps1')

$root = Get-ProjectRoot
$exe = @((Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'), (Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { throw 'mxf-lab.exe not built. Run 06-build-native.cmd first.' }
$gstBin = Find-GStreamerBin
if (-not $gstBin) { throw 'GStreamer runtime not found.' }
$env:PATH = $gstBin + ';' + $env:PATH

$runDir = Ensure-RunDirectory 'mxf-integrity'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$base = Join-Path $runDir ("crash-$stamp")
$partial = $base + '.mxf.partial'
$final = $base + '.mxf'
$lock = $base + '.mxf.lock'
$report = $base + '.crash-report.json'
$stdout = $base + '.writer.stdout.log'
$stderr = $base + '.writer.stderr.log'
$fileId = 'FILE-' + ([guid]::NewGuid().ToString('N'))

# Parent process emulates the next Recorder boot. A child PowerShell process emulates
# the Recorder process that owns the guard, lock heartbeat, and writer.
$supervisor = Join-Path $runDir ("supervisor-$stamp.ps1")
$modulePath = Join-Path $PSScriptRoot 'Mxf-FileLifecycle.ps1'
$supervisorBody = @'
param($ModulePath,$Exe,$GstBin,$Partial,$Final,$Lock,$Stdout,$Stderr,$FileId,$Tracks,$Seconds)
. $ModulePath
$env:PATH = $GstBin + ';' + $env:PATH
$guard = $null
try {
    $guard = Open-MxfDeleteGuard -Path $Partial
    $record = New-MxfLifecycleRecord -FileId $FileId -PartialPath $Partial -FinalPath $Final -LockPath $Lock -ExpectedTracks $Tracks
    Write-JsonAtomic -Object $record -Path $Lock
    $args = @('write','--tracks',"$Tracks",'--seconds',"$Seconds",'--out',$Partial)
    $p = Start-Process -FilePath $Exe -ArgumentList $args -PassThru -NoNewWindow -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr
    Update-MxfLifecycleRecord -Record $record -LockPath $Lock -State 'RECORDING_LOCKED' -WriterPid $p.Id
    while ($true) {
        Update-MxfLifecycleRecord -Record $record -LockPath $Lock -State 'RECORDING_LOCKED' -WriterPid $p.Id
        Start-Sleep -Milliseconds 300
    }
} finally {
    if ($guard) { $guard.Dispose() }
}
'@
Set-Content -LiteralPath $supervisor -Value $supervisorBody -Encoding UTF8

$sArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$supervisor,'-ModulePath',$modulePath,'-Exe',$exe,'-GstBin',$gstBin,'-Partial',$partial,'-Final',$final,'-Lock',$lock,'-Stdout',$stdout,'-Stderr',$stderr,'-FileId',$fileId,'-Tracks',"$Tracks",'-Seconds',"$Seconds")
$sup = Start-Process -FilePath 'PowerShell.exe' -ArgumentList $sArgs -PassThru -WindowStyle Hidden

$deadline = [DateTime]::UtcNow.AddSeconds(10)
while (-not (Test-Path -LiteralPath $lock)) {
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Supervisor did not create lock within 10 seconds.' }
    Start-Sleep -Milliseconds 100
}
Start-Sleep -Milliseconds $CrashAfterMs
$before = Read-MxfLock -Path $lock
$writerPid = [int]$before.writer_pid

Write-Host "Simulating Recorder crash: supervisor PID=$($sup.Id), writer PID=$writerPid"
if (Get-Process -Id $writerPid -ErrorAction SilentlyContinue) { Stop-Process -Id $writerPid -Force }
if (Get-Process -Id $sup.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $sup.Id -Force }
Start-Sleep -Milliseconds 500

$after = Read-MxfLock -Path $lock
$disposition = Get-MxfLockDisposition -Lock $after
$partialExists = Test-Path -LiteralPath $partial
$bytes = if ($partialExists) { (Get-Item -LiteralPath $partial).Length } else { 0 }

# The OS guard must have vanished with the crashed owner. Test rename availability
# non-destructively by renaming away and immediately back.
$released = $false
if ($partialExists) {
    $probe = $partial + '.post-crash-probe'
    try {
        Move-Item -LiteralPath $partial -Destination $probe -Force -ErrorAction Stop
        Move-Item -LiteralPath $probe -Destination $partial -Force -ErrorAction Stop
        $released = $true
    } catch {
        $released = $false
    }
}

$obj = [ordered]@{
    schema = 'recorder-poc.crash-lock-report.v1'
    file_id = $fileId
    partial_path = $partial
    lock_path = $lock
    partial_exists = $partialExists
    partial_bytes = $bytes
    lock_disposition = $disposition
    os_guard_released_after_crash = $released
    recorder_pid = $after.recorder_pid
    writer_pid = $after.writer_pid
    crashed_utc = [DateTime]::UtcNow.ToString('o')
    next_action = 'RUN_12_RECOVER_STALE_LOCK'
}
Write-JsonAtomic -Object $obj -Path $report
Remove-Item -LiteralPath $supervisor -Force -ErrorAction SilentlyContinue

Write-Host "Lock disposition: $disposition"
Write-Host "Partial bytes: $bytes"
Write-Host "OS guard released after crash: $released"
Write-Host "STALE LOCK CRASH TEST: $(if($disposition -eq 'STALE_LOCK' -and $partialExists -and $released){'PASS'}else{'FAIL'})"
Write-Host "Crash report: $report"
Write-Host "Lock intentionally retained: $lock"
