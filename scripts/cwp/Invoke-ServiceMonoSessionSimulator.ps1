
param(
    [string]$LocalIp = '10.20.1.101',
    [string]$RecorderIp = '10.20.0.10',
    [int]$RtspPort = 8554,
    [int]$RecorderRtpPort = 20000,
    [int]$LocalRtpPort = 21000,
    [string]$EndpointId = 'CWP-A01',
    [string]$ServiceId = '121500',
    [string]$ServiceType = 'radio',
    [string]$MediaFlow = 'mono',
    [int]$BurstCount = 2,
    [int]$BurstMs = 240,
    [int]$SilenceMs = 300,
    [int]$KeepaliveIntervalMs = 150,
    [int]$PausedProbePackets = 1,
    [int]$StartDelayMs = 0,
    [string]$PcmaFile = '',
    [double]$ToneHz = 0,
    [double]$ToneLevelDbfs = -12
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\recorder\Common-Recorder.ps1')

function Send-RtspRequest {
    param([Net.Sockets.TcpClient]$Client,[string]$Request)
    $bytes = [Text.Encoding]::ASCII.GetBytes($Request)
    $stream = $Client.GetStream()
    $stream.Write($bytes,0,$bytes.Length)
    $buffer = New-Object byte[] 8192
    $read = $stream.Read($buffer,0,$buffer.Length)
    if ($read -le 0) { throw 'No RTSP response.' }
    return [Text.Encoding]::ASCII.GetString($buffer,0,$read)
}
function Get-SessionIdFromResponse { param([string]$Response)
    if ($Response -match '(?im)^Session:\s*([^;\r\n]+)') { return $Matches[1].Trim() }
    return $null
}
function New-RtpPacket { param([int]$Seq,[uint32]$Timestamp,[byte[]]$Payload)
    $packet = New-Object byte[] (12 + $Payload.Length)
    $packet[0] = 0x80; $packet[1] = 8
    $packet[2] = [byte](($Seq -shr 8) -band 0xff); $packet[3] = [byte]($Seq -band 0xff)
    $packet[4] = [byte](($Timestamp -shr 24) -band 0xff); $packet[5] = [byte](($Timestamp -shr 16) -band 0xff)
    $packet[6] = [byte](($Timestamp -shr 8) -band 0xff); $packet[7] = [byte]($Timestamp -band 0xff)
    $ssrc = 0x53455256
    $packet[8] = [byte](($ssrc -shr 24) -band 0xff); $packet[9] = [byte](($ssrc -shr 16) -band 0xff)
    $packet[10] = [byte](($ssrc -shr 8) -band 0xff); $packet[11] = [byte]($ssrc -band 0xff)
    [Array]::Copy($Payload,0,$packet,12,$Payload.Length)
    return $packet
}

if ($StartDelayMs -gt 0) { Start-Sleep -Milliseconds $StartDelayMs }

$generatedPcma = $null
if ($ToneHz -gt 0) {
    if ($PcmaFile) { throw 'Use either -PcmaFile or -ToneHz, not both.' }
    $generator = Join-Path $PSScriptRoot '..\generator\audio_generator.py'
    if (-not (Test-Path -LiteralPath $generator)) { throw "Audio generator not found: $generator" }
    $generatedPcma = Join-Path ([IO.Path]::GetTempPath()) ('audio-system-tone-' + [Guid]::NewGuid().ToString('N') + '.pcma')
    $durationSeconds = [Math]::Max(1.0, ([double]$BurstMs / 1000.0))
    & python $generator '--frequency' $ToneHz.ToString([Globalization.CultureInfo]::InvariantCulture) '--duration' $durationSeconds.ToString([Globalization.CultureInfo]::InvariantCulture) '--level-dbfs' $ToneLevelDbfs.ToString([Globalization.CultureInfo]::InvariantCulture) '--pcma' $generatedPcma
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $generatedPcma)) {
        throw 'Failed to generate temporary PCMA tone for simulator.'
    }
    $PcmaFile = $generatedPcma
}

$client = New-Object Net.Sockets.TcpClient
$client.Connect($RecorderIp,$RtspPort)
$udp = New-Object Net.Sockets.UdpClient ([Net.IPEndPoint]::new([Net.IPAddress]::Parse($LocalIp),$LocalRtpPort))
$remote = [Net.IPEndPoint]::new([Net.IPAddress]::Parse($RecorderIp),$RecorderRtpPort)
$cseq = 1
$serviceSlug = if ($ServiceType.ToLowerInvariant() -eq 'telephone') { 'tel-' + $ServiceId.ToLowerInvariant() } else { 'radio-' + $ServiceId.ToLowerInvariant() }
$uri = "rtsp://${RecorderIp}:$RtspPort/record/$EndpointId/$serviceSlug"
$sdp = @(
    'v=0',
    ('o=- 0 0 IN IP4 {0}' -f $LocalIp),
    ('s={0} {1} {2} {3}' -f $ServiceType.ToUpperInvariant(), $ServiceId, $EndpointId, $MediaFlow.ToUpperInvariant()),
    ('c=IN IP4 {0}' -f $RecorderIp),
    't=0 0',
    'm=audio 0 RTP/AVP 8',
    'a=rtpmap:8 PCMA/8000',
    ('a=label:{0}-{1}-{2}' -f $serviceSlug, $EndpointId.ToLowerInvariant(), $MediaFlow.ToLowerInvariant()),
    'a=mid:audio0',
    ''
) -join "`r`n"

try {
    $resp = Send-RtspRequest $client ("OPTIONS $uri RTSP/1.0`r`nCSeq: $cseq`r`n`r`n"); $cseq++
    $resp = Send-RtspRequest $client ("ANNOUNCE $uri RTSP/1.0`r`nCSeq: $cseq`r`nContent-Type: application/sdp`r`nContent-Length: $([Text.Encoding]::ASCII.GetByteCount($sdp))`r`n`r`n$sdp"); $cseq++
    $session = Get-SessionIdFromResponse $resp
    if (-not $session) { throw "ANNOUNCE did not return Session. response=$resp" }
    $resp = Send-RtspRequest $client ("SETUP $uri RTSP/1.0`r`nCSeq: $cseq`r`nSession: $session`r`nTransport: RTP/AVP;unicast;client_port=$LocalRtpPort-$($LocalRtpPort+1);mode=record`r`n`r`n"); $cseq++
    $payload = New-Object byte[] 160
    for($i=0;$i -lt $payload.Length;$i++){ $payload[$i]=0xD5 }
    $pcma = if ($PcmaFile) { [IO.File]::ReadAllBytes($PcmaFile) } else { $null }
    if ($pcma -and $pcma.Length -lt 160) { throw "PCMA source too short: $PcmaFile" }
    $audioOffset = 0
    $seq = 1000; [uint32]$ts = 0; $activePackets = 0; $pausedPackets = 0; $keepalives = 0
    foreach($b in 1..$BurstCount){
        $resp = Send-RtspRequest $client ("RECORD $uri RTSP/1.0`r`nCSeq: $cseq`r`nSession: $session`r`n`r`n"); $cseq++
        $packetCount = [Math]::Max(1,[int]($BurstMs / 20))
        for($p=0;$p -lt $packetCount;$p++){
            if ($pcma) {
                if ($audioOffset + 160 -gt $pcma.Length) { $audioOffset = 0 }
                [Array]::Copy($pcma,$audioOffset,$payload,0,160)
                $audioOffset += 160
            }
            $pkt = New-RtpPacket -Seq $seq -Timestamp $ts -Payload $payload
            [void]$udp.Send($pkt,$pkt.Length,$remote); $seq++; $ts += 160; $activePackets++; Start-Sleep -Milliseconds 20
        }
        $resp = Send-RtspRequest $client ("PAUSE $uri RTSP/1.0`r`nCSeq: $cseq`r`nSession: $session`r`n`r`n"); $cseq++
        for($q=0;$q -lt $PausedProbePackets;$q++){
            $pkt = New-RtpPacket -Seq $seq -Timestamp $ts -Payload $payload
            [void]$udp.Send($pkt,$pkt.Length,$remote); $seq++; $ts += 160; $pausedPackets++
        }
        $elapsed=0
        while($elapsed -lt $SilenceMs){
            Start-Sleep -Milliseconds $KeepaliveIntervalMs
            $elapsed += $KeepaliveIntervalMs
            $resp = Send-RtspRequest $client ("GET_PARAMETER $uri RTSP/1.0`r`nCSeq: $cseq`r`nSession: $session`r`n`r`n"); $cseq++; $keepalives++
        }
    }
    $resp = Send-RtspRequest $client ("TEARDOWN $uri RTSP/1.0`r`nCSeq: $cseq`r`nSession: $session`r`n`r`n"); $cseq++
    Write-Host ('SERVICE MONO SIMULATOR: PASS session={0} service={1} media_flow={2} bursts={3} active_packets={4} paused_probe_packets={5} keepalives={6}' -f $session,$ServiceId,$MediaFlow,$BurstCount,$activePackets,$pausedPackets,$keepalives) -ForegroundColor Green
} finally {
    if($udp){$udp.Close()}
    if($client){$client.Close()}
    if($generatedPcma -and (Test-Path -LiteralPath $generatedPcma)){
        Remove-Item -LiteralPath $generatedPcma -Force -ErrorAction SilentlyContinue
    }
}
