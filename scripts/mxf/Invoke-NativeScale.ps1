param([int[]]$TrackCounts=@(100,500,1000), [int]$Seconds=5)
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
$root = Get-ProjectRoot
$candidates = @(
    (Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),
    (Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')
)
$exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { throw 'mxf-lab.exe not built. Run 06-build-native.cmd first.' }

$gstBin = Find-GStreamerBin
if (-not $gstBin) { throw 'GStreamer runtime bin directory not found.' }
$pathParts = @($env:PATH -split ';')
if (-not ($pathParts | Where-Object { $_.TrimEnd('\\') -ieq $gstBin.TrimEnd('\\') })) {
    $env:PATH = $gstBin + ';' + $env:PATH
}

$ffprobe = Find-Executable @('ffprobe.exe','ffprobe')

Write-Host "mxf-lab: $exe"
Write-Host "GStreamer runtime bin: $gstBin"
if ($ffprobe) { Write-Host "ffprobe: $ffprobe" }

$self = Invoke-NativeProcessCapture -FilePath $exe -Arguments @('selftest') -TimeoutMs 15000
if ($self.StdOut) { $self.StdOut.TrimEnd() -split "`r?`n" | ForEach-Object { Write-Host $_ } }
if ($self.StdErr) { $self.StdErr.TrimEnd() -split "`r?`n" | ForEach-Object { Write-Host "[stderr] $_" -ForegroundColor DarkYellow } }
if ($self.ExitCode -ne 0) { throw ("mxf-lab runtime self-test failed with exit code {0}" -f $self.ExitCode) }

$runDir = Ensure-RunDirectory
$rows = @()
foreach($n in $TrackCounts) {
    $out = Join-Path $runDir "native-$n.mxf"
    $log = Join-Path $runDir "native-$n.log"
    if (Test-Path $out) { Remove-Item -Force $out }
    if (Test-Path $log) { Remove-Item -Force $log }

    Write-Host "`n=== Native MXF write: $n tracks x $Seconds s ===" -ForegroundColor Cyan
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $writeTimeoutMs = [Math]::Max(60000, $Seconds * 10000)
    $write = Invoke-NativeProcessCapture -FilePath $exe -Arguments @('write','--tracks',[string]$n,'--seconds',[string]$Seconds,'--out',$out) -TimeoutMs $writeTimeoutMs
    $sw.Stop()
    if ($write.StdOut) { $write.StdOut.TrimEnd() -split "`r?`n" | Tee-Object -FilePath $log | ForEach-Object { Write-Host $_ } }
    if ($write.StdErr) { $write.StdErr.TrimEnd() -split "`r?`n" | Tee-Object -FilePath $log -Append | ForEach-Object { Write-Host "[stderr] $_" -ForegroundColor DarkYellow } }

    if($write.ExitCode -ne 0) {
        $tail = (@(($write.StdErr + "`n" + $write.StdOut) -split "`r?`n" | Select-Object -Last 8) -join ' | ')
        $rows += [pscustomobject]@{Tracks=$n;Result='WRITE_FAIL';ExitCode=$write.ExitCode;InspectExitCode=$null;FfprobeStreams=$null;ElapsedMs=$sw.ElapsedMilliseconds;Bytes=0;FileExists=(Test-Path $out);Log=$log;Detail=$tail}
        break
    }
    if(-not (Test-Path $out)) {
        $rows += [pscustomobject]@{Tracks=$n;Result='NO_FILE';ExitCode=$write.ExitCode;InspectExitCode=$null;FfprobeStreams=$null;ElapsedMs=$sw.ElapsedMilliseconds;Bytes=0;FileExists=$false;Log=$log;Detail='writer returned success but output file is absent'}
        break
    }

    Write-Host "=== Inspect: $n tracks ===" -ForegroundColor DarkCyan
    $inspectTimeoutMs = if ($n -le 100) { 15000 } elseif ($n -le 500) { 30000 } else { 60000 }
    $inspect = Invoke-NativeProcessCapture -FilePath $exe -Arguments @('inspect',$out,'--expected-tracks',[string]$n,'--timeout-ms',[string]$inspectTimeoutMs) -TimeoutMs ($inspectTimeoutMs + 5000)
    if ($inspect.StdOut) { $inspect.StdOut.TrimEnd() -split "`r?`n" | Tee-Object -FilePath $log -Append | ForEach-Object { Write-Host $_ } }
    if ($inspect.StdErr) { $inspect.StdErr.TrimEnd() -split "`r?`n" | Tee-Object -FilePath $log -Append | ForEach-Object { Write-Host "[inspect stderr] $_" -ForegroundColor DarkYellow } }

    $ffCount = $null
    if ($ffprobe) {
        $ff = Invoke-NativeProcessCapture -FilePath $ffprobe -Arguments @('-v','error','-select_streams','a','-show_entries','stream=index','-of','csv=p=0',$out) -TimeoutMs 60000
        if ($ff.ExitCode -eq 0) {
            $ffLines = @($ff.StdOut -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
            $ffCount = $ffLines.Count
            Write-Host ("ffprobe audio streams: {0}" -f $ffCount)
        } else {
            Write-Host ("ffprobe failed: exit={0} {1}" -f $ff.ExitCode,$ff.StdErr.Trim()) -ForegroundColor DarkYellow
        }
    }

    $f = Get-Item $out
    $inspectOk = ($inspect.ExitCode -eq 0)
    $countOk = ($null -eq $ffCount -or $ffCount -eq $n)
    $result = if($inspectOk -and $countOk){'PASS'} elseif(-not $inspectOk){'INSPECT_FAIL'} else {'COUNT_MISMATCH'}
    $detail = if($result -eq 'PASS') {'write+structural-inspect+ffprobe passed'} else {(@(($inspect.StdErr + "`n" + $inspect.StdOut) -split "`r?`n" | Select-Object -Last 10) -join ' | ')}
    $rows += [pscustomobject]@{Tracks=$n;Result=$result;ExitCode=$write.ExitCode;InspectExitCode=$inspect.ExitCode;FfprobeStreams=$ffCount;ElapsedMs=$sw.ElapsedMilliseconds;Bytes=$f.Length;FileExists=$true;Log=$log;Detail=$detail}
    if($result -ne 'PASS'){break}
}

$rows | Format-Table Tracks,Result,ExitCode,InspectExitCode,FfprobeStreams,ElapsedMs,Bytes,FileExists -AutoSize
$report = Join-Path $runDir ('native-scale-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.json')
@($rows) | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $report
Write-Host "Report: $report"

$failures = @($rows | Where-Object { $_.Result -ne 'PASS' })
if($failures.Count -gt 0){ exit 1 }
Write-Host 'NATIVE MXF SCALE: PASS' -ForegroundColor Green
