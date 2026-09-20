[CmdletBinding()]
param([string]$BaseUrl = 'http://127.0.0.1:8765')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$catalog = Invoke-RestMethod "$BaseUrl/api/catalog"
$rows = @($catalog.tracks | ForEach-Object {
    $track = $_.logical_track_uuid
    $_.occurrences | Where-Object { $_.state -eq 'CLOSED_COMPLETE' } | ForEach-Object {
        [pscustomobject]@{ logical_track_uuid = $track; track_instance_uuid = $_.track_instance_uuid }
    }
})
$result = [System.Collections.Generic.List[object]]::new()
foreach ($row in $rows) {
    $body = $row | ConvertTo-Json -Compress
    try {
        $response = Invoke-RestMethod "$BaseUrl/api/preview" -Method Post -ContentType 'application/json' -Body $body
        $result.Add([pscustomobject]@{ logical_track_uuid=$row.logical_track_uuid; track_instance_uuid=$row.track_instance_uuid; cache_hit=[bool]$response.cache.hit; wav_bytes=$response.wav_bytes; result='PASS' })
    } catch {
        $result.Add([pscustomobject]@{ logical_track_uuid=$row.logical_track_uuid; track_instance_uuid=$row.track_instance_uuid; cache_hit=$false; wav_bytes=0; result='FAIL'; error=$_.Exception.Message })
    }
}
$outDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'runs\web-player-cache'
New-Item -ItemType Directory -Force $outDir | Out-Null
$report = [ordered]@{ schema='recorder-poc.web-player-cache-warm.v1'; retention_days=7; requested=$rows.Count; warmed=@($result | Where-Object result -eq 'PASS').Count; failed=@($result | Where-Object result -eq 'FAIL').Count; cache_hits=@($result | Where-Object cache_hit).Count; checked_at_utc=(Get-Date).ToUniversalTime().ToString('o'); items=$result }
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $outDir 'cache-warm-report.json')
Write-Host "Cache warm: $($report.warmed)/$($report.requested) MXFs; hits=$($report.cache_hits); failures=$($report.failed); retention=7 days"
if ($report.failed -gt 0) { exit 1 }
