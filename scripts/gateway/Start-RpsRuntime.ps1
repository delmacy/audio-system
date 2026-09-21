[CmdletBinding()]
param([int]$PollSeconds = 2)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runtime = Join-Path $root 'runs\system-runtime'
$statePath = Join-Path $runtime 'rps-state.json'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

Write-Host 'RPS runtime supervisor started.'
Write-Host 'Current stage: configuration/runtime supervision. Persistent SIP listener is not implemented yet.'

while ($true) {
  $gateways = @()
  $apiOnline = $false
  try {
    $response = Invoke-RestMethod -Uri 'http://127.0.0.1:8500/api/gateways' -TimeoutSec 2
    $apiOnline = $true
    if ($response.gateways) { $gateways = @($response.gateways) }
  } catch {}

  $enabled = @($gateways | Where-Object { $_.enabled -eq $true })
  $status = if (-not $apiOnline) { 'WAITING_API' } elseif ($enabled.Count -eq 0) { 'WAITING_CONFIG' } else { 'CONFIG_READY' }

  [ordered]@{
    schema='audio-system.rps-runtime.v1'
    checked_utc=[DateTime]::UtcNow.ToString('o')
    status=$status
    mode='gateway_runtime'
    configured_rps=$enabled.Count
    proxy_listener_available=$false
    note='Persistent SIP listener/translator is not implemented in this runtime yet.'
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding utf8

  Start-Sleep -Seconds ([Math]::Max(1,$PollSeconds))
}
