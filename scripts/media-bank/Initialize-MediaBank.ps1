. "$PSScriptRoot\Common-MediaBank.ps1"
$root = Get-RepoRoot
$dirs = @(
    'media-bank/raw/radio-mixed',
    'media-bank/raw/telephone-mixed',
    'media-bank/radio/controller',
    'media-bank/radio/pilot',
    'media-bank/radio/unknown',
    'media-bank/telephone/tones/ring',
    'media-bank/telephone/tones/busy',
    'media-bank/telephone/conversations',
    'media-bank/manifests',
    'scenarios/generated',
    'runs/media-bank'
)
foreach ($d in $dirs) {
    $p = Ensure-Dir (Join-Root $root $d)
    $keep = Join-Path $p '.gitkeep'
    if (-not (Test-Path -LiteralPath $keep)) { Set-Content -LiteralPath $keep -Value '' -Encoding ASCII }
}
Write-Host 'MEDIA BANK INIT: PASS'
Write-Host ('Root: {0}' -f (Join-Path $root 'media-bank'))
