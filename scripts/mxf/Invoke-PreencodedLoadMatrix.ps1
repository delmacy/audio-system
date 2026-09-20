param(
    [int]$DeclaredTracks = 1000,
    [int[]]$ActiveCounts = @(0,50,100,250,500,1000),
    [int]$Seconds = 5,
    [int]$ChunkMs = 100,
    [int]$AnchorMs = 20,
    [int]$WriterTimeoutMs = 180000
)

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

$ffmpeg = Find-Executable @('ffmpeg.exe','ffmpeg')
$ffprobe = Find-Executable @('ffprobe.exe','ffprobe')
if (-not $ffmpeg) { throw 'ffmpeg not found; it is needed once to prepare the PCMA sample.' }
if (-not $ffprobe) { throw 'ffprobe not found; it is needed to validate stream cardinality.' }

$generatedDir = Join-Path $root 'media\generated'
New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null
$pcma = Join-Path $generatedDir 'pcma-tone-100ms.alaw'
if (-not (Test-Path $pcma) -or (Get-Item $pcma).Length -lt 800) {
    Write-Host "Preparing reusable 100 ms / 8 kHz / mono G.711 A-law sample..." -ForegroundColor Cyan
    $gen = Invoke-NativeProcessCapture -FilePath $ffmpeg -Arguments @(
        '-y','-v','error',
        '-f','lavfi','-i','sine=frequency=1000:sample_rate=8000:duration=0.1',
        '-ac','1','-ar','8000','-c:a','pcm_alaw','-f','alaw',$pcma
    ) -TimeoutMs 30000
    if ($gen.ExitCode -ne 0) { throw ("ffmpeg sample generation failed: {0}" -f $gen.StdErr) }
}

$sampleBytes = (Get-Item $pcma).Length
Write-Host "mxf-lab: $exe"
Write-Host "PCMA sample: $pcma ($sampleBytes bytes)"
Write-Host "Declared tracks per run: $DeclaredTracks"
Write-Host "Active matrix: $($ActiveCounts -join ', ')"
Write-Host "Duration: $Seconds s | Chunk: $ChunkMs ms | Inactive anchor: $AnchorMs ms"
Write-Host ''

$self = Invoke-NativeProcessCapture -FilePath $exe -Arguments @('selftest') -TimeoutMs 15000
if ($self.StdOut) { $self.StdOut.TrimEnd() -split "`r?`n" | ForEach-Object { Write-Host $_ } }
if ($self.StdErr) { $self.StdErr.TrimEnd() -split "`r?`n" | ForEach-Object { Write-Host "[stderr] $_" -ForegroundColor DarkYellow } }
if ($self.ExitCode -ne 0) { throw ("mxf-lab runtime self-test failed with exit code {0}" -f $self.ExitCode) }

$runDir = Ensure-RunDirectory
$rows = @()
foreach ($active in $ActiveCounts) {
    if ($active -lt 0 -or $active -gt $DeclaredTracks) {
        throw "Active count $active is outside 0..$DeclaredTracks"
    }

    $out = Join-Path $runDir ("preencoded-d{0}-a{1}.mxf" -f $DeclaredTracks,$active)
    $log = Join-Path $runDir ("preencoded-d{0}-a{1}.log" -f $DeclaredTracks,$active)
    if (Test-Path $out) { Remove-Item -Force $out }
    if (Test-Path $log) { Remove-Item -Force $log }

    Write-Host ("`n=== Preencoded MXF: declared={0} active={1} ===" -f $DeclaredTracks,$active) -ForegroundColor Cyan
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $write = Invoke-NativeProcessCapture -FilePath $exe -Arguments @(
        'write-preencoded',
        '--tracks',[string]$DeclaredTracks,
        '--active',[string]$active,
        '--seconds',[string]$Seconds,
        '--out',$out,
        '--pcma',$pcma,
        '--chunk-ms',[string]$ChunkMs,
        '--anchor-ms',[string]$AnchorMs
    ) -TimeoutMs $WriterTimeoutMs
    $sw.Stop()

    if ($write.StdOut) { $write.StdOut.TrimEnd() -split "`r?`n" | Tee-Object -FilePath $log | ForEach-Object { Write-Host $_ } }
    if ($write.StdErr) { $write.StdErr.TrimEnd() -split "`r?`n" | Tee-Object -FilePath $log -Append | ForEach-Object { Write-Host "[stderr] $_" -ForegroundColor DarkYellow } }

    $exists = Test-Path $out
    $bytes = if ($exists) { (Get-Item $out).Length } else { 0 }
    $activePayload = [int64]$active * [int64]$Seconds * 8000L
    $anchorPayload = [int64]($DeclaredTracks - $active) * [int64]$AnchorMs * 8L
    $estimatedPayload = $activePayload + $anchorPayload

    $ffCount = $null
    $ffMs = $null
    $ffExit = $null
    if ($exists) {
        $ffsw = [Diagnostics.Stopwatch]::StartNew()
        $ff = Invoke-NativeProcessCapture -FilePath $ffprobe -Arguments @(
            '-v','error','-select_streams','a','-show_entries','stream=index','-of','csv=p=0',$out
        ) -TimeoutMs 120000
        $ffsw.Stop()
        $ffMs = $ffsw.ElapsedMilliseconds
        $ffExit = $ff.ExitCode
        if ($ff.ExitCode -eq 0) {
            $ffLines = @($ff.StdOut -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
            $ffCount = $ffLines.Count
        }
    }

    $result = 'PASS'
    $detail = 'preencoded write + ffprobe count passed'
    if ($write.ExitCode -ne 0) {
        $result = 'WRITE_FAIL'
        $detail = (@(($write.StdErr + "`n" + $write.StdOut) -split "`r?`n" | Select-Object -Last 8) -join ' | ')
    } elseif (-not $exists) {
        $result = 'NO_FILE'
        $detail = 'writer returned success but output file is absent'
    } elseif ($ffExit -ne 0) {
        $result = 'FFPROBE_FAIL'
        $detail = 'ffprobe could not inspect the output'
    } elseif ($ffCount -ne $DeclaredTracks) {
        $result = 'COUNT_MISMATCH'
        $detail = ("ffprobe found {0} tracks; expected {1}" -f $ffCount,$DeclaredTracks)
    }

    $overheadBytes = if ($bytes -gt 0) { [int64]$bytes - $estimatedPayload } else { 0 }
    $overheadPct = if ($estimatedPayload -gt 0 -and $bytes -gt 0) { [math]::Round(($overheadBytes / [double]$estimatedPayload) * 100.0, 2) } else { 0 }
    $writerMiBs = if ($sw.ElapsedMilliseconds -gt 0 -and $bytes -gt 0) { [math]::Round(($bytes / 1MB) / ($sw.ElapsedMilliseconds / 1000.0), 2) } else { 0 }
    $peakMiB = [math]::Round(($write.PeakWorkingSet64 / 1MB), 1)

    $row = [pscustomobject]@{
        DeclaredTracks = $DeclaredTracks
        ActiveTracks = $active
        Result = $result
        ExitCode = $write.ExitCode
        FfprobeStreams = $ffCount
        WriterMs = $sw.ElapsedMilliseconds
        FfprobeMs = $ffMs
        CpuMs = $write.TotalProcessorMs
        PeakWorkingSetMiB = $peakMiB
        Bytes = $bytes
        EstimatedPayloadBytes = $estimatedPayload
        OverheadBytes = $overheadBytes
        OverheadPct = $overheadPct
        WriterMiBs = $writerMiBs
        ChunkMs = $ChunkMs
        AnchorMs = $AnchorMs
        File = $out
        Log = $log
        Detail = $detail
    }
    $rows += $row

    Write-Host ("Result={0} writer={1} ms CPU={2} ms peakRAM={3} MiB file={4} bytes ffprobe={5}/{6}" -f `
        $result,$row.WriterMs,$row.CpuMs,$row.PeakWorkingSetMiB,$row.Bytes,$row.FfprobeStreams,$DeclaredTracks)
}

Write-Host "`n=== PREENCODED LOAD MATRIX ===" -ForegroundColor Green
$rows | Format-Table ActiveTracks,Result,FfprobeStreams,WriterMs,CpuMs,PeakWorkingSetMiB,Bytes,EstimatedPayloadBytes,OverheadPct,WriterMiBs -AutoSize

$stamp = Get-Date -Format yyyyMMdd-HHmmss
$json = Join-Path $runDir ("preencoded-load-matrix-{0}.json" -f $stamp)
$csv = Join-Path $runDir ("preencoded-load-matrix-{0}.csv" -f $stamp)
@($rows) | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $json
@($rows) | Export-Csv -NoTypeInformation -Encoding UTF8 $csv
Write-Host "JSON report: $json"
Write-Host "CSV report:  $csv"

$failures = @($rows | Where-Object { $_.Result -ne 'PASS' })
if ($failures.Count -gt 0) { exit 1 }
Write-Host 'PREENCODED LOAD MATRIX: PASS' -ForegroundColor Green
