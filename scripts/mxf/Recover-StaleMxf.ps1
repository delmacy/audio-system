param([string]$LockPath)
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
. (Join-Path $PSScriptRoot 'Mxf-FileLifecycle.ps1')

$runDir = Ensure-RunDirectory 'mxf-integrity'
if (-not $LockPath) {
    $candidate = Get-ChildItem -LiteralPath $runDir -Filter '*.mxf.lock' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $candidate) { throw 'No stale *.mxf.lock found in runs\mxf-integrity.' }
    $LockPath = $candidate.FullName
}
$lock = Read-MxfLock -Path $LockPath
$disp = Get-MxfLockDisposition -Lock $lock
if ($disp -ne 'STALE_LOCK') { throw "Refusing recovery: lock is $disp, not STALE_LOCK." }

$partial = [string]$lock.partial_path
$final = [string]$lock.final_path
if (-not (Test-Path -LiteralPath $partial)) { throw "Stale lock exists but partial file is missing: $partial" }

$ffprobe = Find-Executable @('ffprobe.exe','ffprobe')
$ffprobeExit = $null
$streams = $null
$probeText = $null
if ($ffprobe) {
    $r = Invoke-NativeProcessCapture -FilePath $ffprobe -Arguments @('-v','error','-select_streams','a','-show_entries','stream=index','-of','csv=p=0',$partial) -TimeoutMs 20000
    $ffprobeExit = $r.ExitCode
    $probeText = ($r.StdOut + $r.StdErr).Trim()
    if ($r.ExitCode -eq 0) {
        $streams = @($r.StdOut -split "`r?`n" | Where-Object { $_.Trim() -ne '' }).Count
    }
}

$bytes = (Get-Item -LiteralPath $partial).Length
$recoveryStatus = if ($ffprobeExit -eq 0 -and $streams -gt 0) { 'RECOVERABLE_INCOMPLETE' } else { 'RECOVERY_REQUIRED' }
$recoveryPath = $partial + '.recovery.json'
$obj = [ordered]@{
    schema = 'recorder-poc.mxf-recovery-assessment.v1'
    file_id = $lock.file_id
    original_state = $lock.state
    detected_state = 'STALE_LOCK'
    recovery_status = $recoveryStatus
    partial_path = $partial
    intended_final_path = $final
    bytes = $bytes
    ffprobe_exit = $ffprobeExit
    ffprobe_audio_streams = $streams
    ffprobe_detail = $probeText
    assessed_utc = [DateTime]::UtcNow.ToString('o')
    note = 'PoC assessment only. A stale/incomplete MXF is never promoted to CLOSED_COMPLETE without a successful recovery/finalization algorithm.'
}
Write-JsonAtomic -Object $obj -Path $recoveryPath

Write-Host "Detected: STALE_LOCK"
Write-Host "Recovery status: $recoveryStatus"
Write-Host "Bytes: $bytes"
Write-Host "ffprobe exit: $ffprobeExit | audio streams: $streams"
Write-Host "Assessment: $recoveryPath"
Write-Host 'The .lock is intentionally retained until a future recovery implementation explicitly resolves it.'
