param(
    [double]$FrequencyHz = 1000,
    [double]$DurationSeconds = 2,
    [double]$LevelDbfs = -12,
    [string]$OutputPcma = '',
    [string]$PreviewWav = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\recorder\Common-Recorder.ps1')

$root = Get-ProjectRoot
$generator = Join-Path $PSScriptRoot 'audio_generator.py'
if (-not (Test-Path -LiteralPath $generator)) { throw "Audio generator not found: $generator" }

if (-not $OutputPcma) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    $outDir = Join-Path $root ('runs\audio-generator\' + $stamp)
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $safeFreq = [Math]::Round($FrequencyHz, 2).ToString([Globalization.CultureInfo]::InvariantCulture).Replace('.','p')
    $OutputPcma = Join-Path $outDir ('tone-' + $safeFreq + 'Hz.pcma')
}
if (-not $PreviewWav) {
    $PreviewWav = [IO.Path]::ChangeExtension($OutputPcma, '.wav')
}

$args = @(
    $generator,
    '--frequency', $FrequencyHz.ToString([Globalization.CultureInfo]::InvariantCulture),
    '--duration', $DurationSeconds.ToString([Globalization.CultureInfo]::InvariantCulture),
    '--level-dbfs', $LevelDbfs.ToString([Globalization.CultureInfo]::InvariantCulture),
    '--pcma', $OutputPcma,
    '--wav', $PreviewWav
)

$result = & python @args
if ($LASTEXITCODE -ne 0) { throw "Audio generator failed with exit code $LASTEXITCODE" }
Write-Host $result
Write-Host ("TEST TONE READY: {0} Hz, {1}s, {2} dBFS" -f $FrequencyHz,$DurationSeconds,$LevelDbfs) -ForegroundColor Green
Write-Host ("PCMA: " + (Resolve-Path $OutputPcma).Path)
Write-Host ("WAV:  " + (Resolve-Path $PreviewWav).Path)
