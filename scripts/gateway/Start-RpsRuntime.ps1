[CmdletBinding()]
param([string]$GatewayId = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$proxy = Join-Path $PSScriptRoot 'rps_proxy.py'

if (-not (Test-Path -LiteralPath $proxy)) {
    throw "RPS proxy não encontrado: $proxy"
}

$args = @($proxy)
if ($GatewayId) {
    $args += @('--gateway-id', $GatewayId)
}

Write-Host 'Starting persistent Audio System RPS (SIP/UDP -> RTSP/RTP)...'
& python @args
exit $LASTEXITCODE
