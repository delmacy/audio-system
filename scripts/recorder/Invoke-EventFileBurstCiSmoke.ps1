param(
    [int]$LegCount = 1000,
    [int]$RingSeconds = 10,
    [double]$ToneHz = 440.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Recorder.ps1')

if ($LegCount -lt 1 -or $LegCount -gt 1800) {
    throw 'LegCount must be between 1 and 1800.'
}
if ($RingSeconds -lt 1 -or $RingSeconds -gt 16) {
    throw 'RingSeconds must be between 1 and 16 seconds for the bounded event buffer.'
}

$root = Get-ProjectRoot
$exe = Find-RecorderHostExe
if (-not $exe) { throw 'recorder-host.exe was not built.' }

$plugin = Join-Path $root 'src\mxf-identity-plugin\bin\gstmxfidentity.dll'
if (-not (Test-Path -LiteralPath $plugin)) {
    throw 'gstmxfidentity.dll was not built.'
}

$lab = @(
    (Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),
    (Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $lab) { throw 'mxf-lab.exe was not built.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$runDir = Join-Path $root ('runs\event-burst\' + $stamp)
$recordingRoot = Join-Path $runDir 'recordings'
New-Item -ItemType Directory -Force -Path $runDir,$recordingRoot | Out-Null

$pcma = Join-Path $runDir ('ring-{0:g}Hz-{1}s.pcma' -f $ToneHz,$RingSeconds)
$wav = Join-Path $runDir ('ring-{0:g}Hz-{1}s.wav' -f $ToneHz,$RingSeconds)
$generator = Join-Path $root 'scripts\generator\audio_generator.py'

$generatorArgs = @(
    $generator,
    '--frequency',[string]$ToneHz,
    '--duration',[string]$RingSeconds,
    '--level-dbfs','-12',
    '--pcma',$pcma,
    '--wav',$wav
)
& python @generatorArgs
if ($LASTEXITCODE -ne 0) {
    throw "Audio generator failed with exit code $LASTEXITCODE"
}

$expectedPayloadBytes = 8000 * $RingSeconds
$pcmaInfo = Get-Item -LiteralPath $pcma
if ($pcmaInfo.Length -ne $expectedPayloadBytes) {
    throw "Generated PCMA has $($pcmaInfo.Length) bytes; expected $expectedPayloadBytes."
}

Write-Host ('=== Event File Burst: {0} files x {1}s ===' -f $LegCount,$RingSeconds)
Write-Host ('PCMA source: {0} ({1} bytes)' -f $pcma,$pcmaInfo.Length)
Write-Host ('Recording root: {0}' -f $recordingRoot)

$nativeArgs = @(
    'event-file-burst-selftest',
    '--plugin-dll',$plugin,
    '--output-root',$recordingRoot,
    '--pcma-file',$pcma,
    '--legs',[string]$LegCount,
    '--ring-ms',[string]($RingSeconds * 1000)
)
$watch = [Diagnostics.Stopwatch]::StartNew()
$output = @(& $exe @nativeArgs 2>&1)
$exitCode = $LASTEXITCODE
$watch.Stop()
$output | ForEach-Object { Write-Host $_ }

if ($exitCode -ne 0) {
    throw "Event-file burst native test failed with exit code $exitCode."
}
if (-not ($output -match 'EVENT FILE BURST: PASS')) {
    throw 'Native burst output did not contain EVENT FILE BURST: PASS.'
}

$files = @(
    Get-ChildItem -LiteralPath $recordingRoot -Recurse -File -Filter '*.mxf' |
        Sort-Object FullName
)
if ($files.Count -ne $LegCount) {
    throw "Expected $LegCount MXF files; found $($files.Count)."
}

$partials = @(Get-ChildItem -LiteralPath $recordingRoot -Recurse -File -Filter '*.partial' -ErrorAction SilentlyContinue)
$locks = @(Get-ChildItem -LiteralPath $recordingRoot -Recurse -File -Filter '*.lock' -ErrorAction SilentlyContinue)
if ($partials.Count -ne 0) {
    throw "Expected zero .partial files after finalization; found $($partials.Count)."
}
if ($locks.Count -ne 0) {
    throw "Expected zero .lock files after finalization; found $($locks.Count)."
}

$tooSmall = @($files | Where-Object { $_.Length -le $expectedPayloadBytes })
if ($tooSmall.Count -ne 0) {
    throw "$($tooSmall.Count) MXF files are not larger than their $expectedPayloadBytes-byte PCMA payload."
}

$lastIndex = [int]$files.Count - 1
$indices = @(
    0
    [int][Math]::Floor($lastIndex * 0.25)
    [int][Math]::Floor($lastIndex * 0.50)
    [int][Math]::Floor($lastIndex * 0.75)
    $lastIndex
) | Select-Object -Unique

foreach ($index in $indices) {
    $file = $files[[int]$index]
    & $lab inspect $file.FullName '--expected-tracks' '1' '--timeout-ms' '15000' '--expected-alaw-8k-mono'
    if ($LASTEXITCODE -ne 0) {
        throw "MXF structural inspection failed for sample file: $($file.FullName)"
    }
}

$totalMxfBytes = ($files | Measure-Object -Property Length -Sum).Sum
$serviceDirs = @(
    Get-ChildItem -LiteralPath $recordingRoot -Recurse -Directory |
        Where-Object { $_.Name -eq 'BURST-RING' }
)
if ($serviceDirs.Count -lt 1) {
    throw 'No BURST-RING service directory was created.'
}

$summary = [ordered]@{
    schema = 'audio-system.event-file-burst-test.v1'
    passed = $true
    leg_count = $LegCount
    ring_seconds = $RingSeconds
    tone_hz = $ToneHz
    pcma_bytes_per_leg = $expectedPayloadBytes
    total_pcma_bytes = [int64]$expectedPayloadBytes * [int64]$LegCount
    mxf_count = $files.Count
    total_mxf_bytes = [int64]$totalMxfBytes
    elapsed_ms = [int64]$watch.ElapsedMilliseconds
    recording_root = $recordingRoot
    pcma_source = $pcma
    wav_preview = $wav
    audit = Join-Path $recordingRoot 'burst-audit.jsonl'
}
$summaryPath = Join-Path $runDir 'burst-summary.json'
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host ('EVENT FILE BURST E2E: PASS files={0} ring_seconds={1} payload_per_file={2} total_payload={3} elapsed_ms={4} root={5}' -f $files.Count,$RingSeconds,$expectedPayloadBytes,([int64]$expectedPayloadBytes * [int64]$LegCount),$watch.ElapsedMilliseconds,$recordingRoot) -ForegroundColor Green
Write-Host ('Summary: {0}' -f $summaryPath)
Write-Host ('WAV preview: {0}' -f $wav)
