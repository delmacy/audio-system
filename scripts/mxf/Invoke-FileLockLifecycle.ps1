param(
    [int]$Tracks = 50,
    [int]$Seconds = 8
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
$base = Join-Path $runDir ("lifecycle-$stamp")
$partial = $base + '.mxf.partial'
$final = $base + '.mxf'
$lock = $base + '.mxf.lock'
$manifest = $base + '.manifest.json'
$stdout = $base + '.writer.stdout.log'
$stderr = $base + '.writer.stderr.log'
$fileId = 'FILE-' + ([guid]::NewGuid().ToString('N'))

$guard = $null
$proc = $null
try {
    $guard = Open-MxfDeleteGuard -Path $partial
    $record = New-MxfLifecycleRecord -FileId $fileId -PartialPath $partial -FinalPath $final -LockPath $lock -ExpectedTracks $Tracks
    Write-JsonAtomic -Object $record -Path $lock

    $args = @('write','--tracks',"$Tracks",'--seconds',"$Seconds",'--out',$partial)
    $proc = Start-Process -FilePath $exe -ArgumentList $args -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Update-MxfLifecycleRecord -Record $record -LockPath $lock -State 'RECORDING_LOCKED' -WriterPid $proc.Id

    Start-Sleep -Milliseconds 350
    $probe = Test-DeleteRenameBlocked -PartialPath $partial
    Write-Host "Delete blocked while recording: $($probe.DeleteBlocked)"
    Write-Host "Rename blocked while recording: $($probe.RenameBlocked)"
    if (-not $probe.DeleteBlocked -or -not $probe.RenameBlocked) {
        throw 'OS-level delete/rename guard did not hold.'
    }

    while (-not $proc.HasExited) {
        Update-MxfLifecycleRecord -Record $record -LockPath $lock -State 'RECORDING_LOCKED' -WriterPid $proc.Id
        Start-Sleep -Milliseconds 500
        $proc.Refresh()
    }
    if ($proc.ExitCode -ne 0) { throw "Writer failed with exit code $($proc.ExitCode). See $stderr" }

    Update-MxfLifecycleRecord -Record $record -LockPath $lock -State 'FINALIZING' -WriterPid $proc.Id
    $bytes = (Get-Item -LiteralPath $partial).Length
    $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()

    # The delete-denying handle must be released immediately before the controlled rename.
    $guard.Dispose(); $guard = $null
    Move-Item -LiteralPath $partial -Destination $final -Force

    $manifestObj = [ordered]@{
        schema = 'recorder-poc.mxf-file-manifest.v1'
        file_id = $fileId
        state = 'CLOSED_COMPLETE'
        final_path = [IO.Path]::GetFullPath($final)
        expected_tracks = $Tracks
        bytes = $bytes
        sha256 = $hash
        finalized_utc = [DateTime]::UtcNow.ToString('o')
        delete_guard_verified = $probe.DeleteBlocked
        rename_guard_verified = $probe.RenameBlocked
    }
    Write-JsonAtomic -Object $manifestObj -Path $manifest
    Remove-Item -LiteralPath $lock -Force

    Write-Host 'FILE LIFECYCLE: PASS'
    Write-Host "Final: $final"
    Write-Host "Manifest: $manifest"
    Write-Host 'Lock removed after CLOSED_COMPLETE.'
} finally {
    if ($guard) { $guard.Dispose() }
}
