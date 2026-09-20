. "$PSScriptRoot\Common-MediaBank.ps1"
$root = Get-RepoRoot
& "$PSScriptRoot\Initialize-MediaBank.ps1"
& "$PSScriptRoot\Invoke-AudioDetectSegments.ps1" -InputFolder 'media-bank/raw' -OutputManifest 'media-bank/manifests/clips-manifest.csv'
& "$PSScriptRoot\Invoke-ConversationGenerate.ps1" -Manifest 'media-bank/manifests/clips-manifest.csv' -OutputScenario 'scenarios/generated/conversation-scenario.json'
$scenario = Join-Root $root 'scenarios/generated/conversation-scenario.json'
if (-not (Test-Path -LiteralPath $scenario)) { throw 'Scenario not created.' }
$json = Get-Content -Raw -LiteralPath $scenario | ConvertFrom-Json
if ($json.media_flow -ne 'mono') { throw 'Scenario media_flow is not mono.' }
if ($json.recorder_track_policy -ne 'one_service_one_mono_track') { throw 'Invalid recorder track policy.' }
Write-Host 'MEDIA BANK SMOKE: PASS'
