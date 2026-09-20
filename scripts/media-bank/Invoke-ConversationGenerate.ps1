param(
    [string]$Manifest = 'media-bank/manifests/clips-manifest.csv',
    [string]$OutputScenario = 'scenarios/generated/conversation-scenario.json',
    [string]$ServiceType = 'radio',
    [string]$ServiceId = '121500',
    [string]$EndpointId = 'cwp-a01',
    [int]$Turns = 8,
    [int]$MinPauseMs = 250,
    [int]$MaxPauseMs = 1600,
    [int]$Seed = 137
)

. "$PSScriptRoot\Common-MediaBank.ps1"
$root = Get-RepoRoot
$manifestPath = Join-Root $root $Manifest
$scenarioPath = Join-Root $root $OutputScenario
$rand = [System.Random]::new($Seed)
$clips = @()
if (Test-Path -LiteralPath $manifestPath) {
    $clips = @(Import-Csv -LiteralPath $manifestPath | Where-Object { $_.output_path -and ($_.review_status -ne 'rejected') })
}
if ($clips.Count -eq 0) {
    # Placeholder mode lets the integrated scenario exist before real audio arrives.
    $clips = @(
        [pscustomobject]@{clip_id='placeholder_pilot_001'; speaker_hint='pilot'; duration_ms=1200; output_path='media-bank/radio/pilot/placeholder_pilot_001.wav'},
        [pscustomobject]@{clip_id='placeholder_controller_001'; speaker_hint='controller'; duration_ms=1400; output_path='media-bank/radio/controller/placeholder_controller_001.wav'}
    )
}
$controller = @($clips | Where-Object { $_.speaker_hint -eq 'controller' })
$pilot = @($clips | Where-Object { $_.speaker_hint -eq 'pilot' })
$unknown = @($clips | Where-Object { $_.speaker_hint -eq 'unknown' })
if ($controller.Count -eq 0) { $controller = $unknown }
if ($pilot.Count -eq 0) { $pilot = $unknown }
if ($controller.Count -eq 0) { $controller = @($clips) }
if ($pilot.Count -eq 0) { $pilot = @($clips) }
$events = New-Object System.Collections.Generic.List[object]
$t = 0
for ($i=0; $i -lt $Turns; $i++) {
    $speaker = if (($i % 2) -eq 0) { 'pilot' } else { 'controller' }
    $pool = if ($speaker -eq 'pilot') { $pilot } else { $controller }
    $clip = $pool[$rand.Next(0,$pool.Count)]
    $dur = [int]$clip.duration_ms
    if ($dur -le 0) { $dur = 1200 }
    $events.Add([pscustomobject]@{ t_ms=$t; event='SQU_ON'; speaker=$speaker; asset=$clip.output_path; clip_id=$clip.clip_id }) | Out-Null
    $events.Add([pscustomobject]@{ t_ms=($t+$dur); event='SQU_OFF'; speaker=$speaker; asset=$clip.output_path; clip_id=$clip.clip_id }) | Out-Null
    $t += $dur + $rand.Next($MinPauseMs, $MaxPauseMs+1)
}
$scenario = [ordered]@{
    schema='recorder-poc.conversation-scenario.v1'
    phase='10.0.0'
    scenario_id=('conversation-{0}-{1}' -f $ServiceType,$ServiceId)
    service_type=$ServiceType
    service_id=$ServiceId
    endpoint_id=$EndpointId
    media_flow='mono'
    recorder_track_policy='one_service_one_mono_track'
    source_roles=@('pilot','controller')
    generated_at_utc=([DateTime]::UtcNow.ToString('o'))
    seed=$Seed
    total_duration_ms=$t
    events=@($events)
}
Ensure-Dir (Split-Path -Parent $scenarioPath) | Out-Null
($scenario | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
Write-Host ('Scenario: {0}' -f $scenarioPath)
Write-Host ('Events: {0}' -f $events.Count)
Write-Host ('Duration ms: {0}' -f $t)
Write-Host 'CONVERSATION GENERATE: PASS'
