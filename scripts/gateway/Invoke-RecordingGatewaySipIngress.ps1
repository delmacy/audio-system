param(
    [Parameter(Mandatory=$true)][string]$LocalIp,
    [Parameter(Mandatory=$true)][string]$RecorderIp,
    [int]$RtspPort = 8554,
    [int]$RecorderRtpPort = 41080,
    [int]$LocalRtpPort = 42000,
    [string]$EndpointId = 'CWP-A17',
    [string]$ServiceId = 'TEL-01',
    [string]$Direction = 'RX',
    [string]$CallLegId = 'LEG-POC-0001',
    [string]$SipCallIdRaw = 'call-poc-0001@example.invalid',
    [string]$SipFromRaw = 'sip:1001@poc.invalid',
    [string]$SipToRaw = 'sip:2001@poc.invalid',
    [int]$RingingMs = 250,
    [int]$AnsweredMediaMs = 1200,
    [string]$AuditPath = $null,
    [string]$CorrelationPath = $null
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-GatewayEvent([string]$Event,[hashtable]$Fields=@{}) {
    $o = [ordered]@{ ts_utc = ([DateTime]::UtcNow).ToString('o'); event = $Event; gateway_id = 'GATEWAY-POC-01'; call_leg_id = $CallLegId; sip_call_id_raw = $SipCallIdRaw }
    foreach($k in $Fields.Keys){ $o[$k] = $Fields[$k] }
    $line = ($o | ConvertTo-Json -Depth 6 -Compress)
    if($AuditPath){ Add-Content -LiteralPath $AuditPath -Value $line -Encoding UTF8 }
    Write-Host $line
}

function New-Socket([System.Net.Sockets.SocketType]$Type,[System.Net.Sockets.ProtocolType]$Protocol) {
    return New-Object System.Net.Sockets.Socket -ArgumentList @([System.Net.Sockets.AddressFamily]::InterNetwork,$Type,$Protocol)
}
function Send-All([System.Net.Sockets.Socket]$Socket,[byte[]]$Bytes) {
    $offset = 0
    while ($offset -lt $Bytes.Length) {
        $sent = $Socket.Send($Bytes,$offset,$Bytes.Length-$offset,[System.Net.Sockets.SocketFlags]::None)
        if ($sent -le 0) { throw 'Socket send returned zero.' }
        $offset += $sent
    }
}
$script:CSeq = 0
$script:Session = $null
function Invoke-Rtsp {
    param([System.Net.Sockets.Socket]$Socket,[string]$Method,[string]$Uri,[string]$Body = '',[hashtable]$Headers = @{})
    $script:CSeq++
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("$Method $Uri RTSP/1.0")
    $lines.Add("CSeq: $script:CSeq")
    $lines.Add('User-Agent: recorder-poc-gateway/8.0.0')
    if ($script:Session -and $Method -notin @('OPTIONS','ANNOUNCE')) { $lines.Add("Session: $script:Session") }
    foreach ($k in $Headers.Keys) { $lines.Add(('{0}: {1}' -f $k,$Headers[$k])) }
    if ($Body) {
        $bodyBytes = [Text.Encoding]::ASCII.GetBytes($Body)
        if (-not $Headers.ContainsKey('Content-Type')) { $lines.Add('Content-Type: application/sdp') }
        $lines.Add("Content-Length: $($bodyBytes.Length)")
    } else { $lines.Add('Content-Length: 0') }
    $request = (($lines -join "`r`n") + "`r`n`r`n" + $Body)
    Send-All $Socket ([Text.Encoding]::ASCII.GetBytes($request))
    $buffer = New-Object byte[] 8192
    $text = ''
    do {
        $n = $Socket.Receive($buffer)
        if ($n -le 0) { throw "RTSP socket closed during $Method" }
        $text += [Text.Encoding]::ASCII.GetString($buffer,0,$n)
    } while ($text -notmatch "`r`n`r`n")
    $statusLine = ($text -split "`r`n")[0]
    if ($statusLine -notmatch '^RTSP/1\.0\s+200\b') { throw "$Method failed: $statusLine`n$text" }
    if ($text -match '(?im)^Session:\s*([^;\r\n]+)') { $script:Session = $Matches[1].Trim() }
    Write-GatewayEvent 'GATEWAY_RTSP_METHOD_OK' @{ method=$Method; rtsp_session_id=$script:Session; status=$statusLine }
    return $text
}
function Set-UInt16BE([byte[]]$Buffer,[int]$Offset,[uint16]$Value) { $Buffer[$Offset]=[byte](($Value -shr 8)-band 0xff); $Buffer[$Offset+1]=[byte]($Value -band 0xff) }
function Set-UInt32BE([byte[]]$Buffer,[int]$Offset,[uint32]$Value) { $Buffer[$Offset]=[byte](($Value -shr 24)-band 0xff); $Buffer[$Offset+1]=[byte](($Value -shr 16)-band 0xff); $Buffer[$Offset+2]=[byte](($Value -shr 8)-band 0xff); $Buffer[$Offset+3]=[byte]($Value -band 0xff) }
function Send-RtpPcma {
    param([System.Net.Sockets.Socket]$Udp,[System.Net.IPEndPoint]$Target,[int]$DurationMs,[ref]$Sequence,[ref]$Timestamp,[uint32]$Ssrc)
    $packetCount = [int][Math]::Floor($DurationMs / 20)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    for($i=0;$i -lt $packetCount;$i++){
        $targetMs = $i*20
        while($sw.ElapsedMilliseconds -lt $targetMs){ $remaining=$targetMs-$sw.ElapsedMilliseconds; if($remaining -gt 2){ Start-Sleep -Milliseconds ([Math]::Min(5,$remaining-1)) } }
        $packet = New-Object byte[] 172
        $packet[0]=0x80; $packet[1]=8
        Set-UInt16BE $packet 2 ([uint16]$Sequence.Value)
        Set-UInt32BE $packet 4 ([uint32]$Timestamp.Value)
        Set-UInt32BE $packet 8 $Ssrc
        for($j=0;$j -lt 160;$j++){ $packet[12+$j]=[byte](0xD5 -bxor (($i+$j) -band 0x3f)) }
        [void]$Udp.SendTo($packet,$Target)
        $Sequence.Value=[uint16](($Sequence.Value+1)-band 0xffff)
        $Timestamp.Value=[uint32](($Timestamp.Value+160)-band 0xffffffffL)
    }
    return $packetCount
}

if($AuditPath){ New-Item -ItemType Directory -Force -Path (Split-Path -Parent $AuditPath) | Out-Null; if(Test-Path $AuditPath){ Remove-Item -LiteralPath $AuditPath -Force } }
$tcp = New-Socket ([System.Net.Sockets.SocketType]::Stream) ([System.Net.Sockets.ProtocolType]::Tcp)
$udp = New-Socket ([System.Net.Sockets.SocketType]::Dgram) ([System.Net.Sockets.ProtocolType]::Udp)
try {
    Write-GatewayEvent 'SIP_INVITE_RECEIVED' @{ sip_from_raw=$SipFromRaw; sip_to_raw=$SipToRaw; endpoint_id=$EndpointId; service_id=$ServiceId; direction=$Direction }
    Start-Sleep -Milliseconds $RingingMs
    Write-GatewayEvent 'SIP_RINGING' @{ ringing_ms=$RingingMs }
    Write-GatewayEvent 'SIP_ANSWERED' @{}

    $tcp.ReceiveTimeout = 5000; $tcp.SendTimeout = 5000
    $tcp.Bind((New-Object System.Net.IPEndPoint -ArgumentList @([Net.IPAddress]::Parse($LocalIp),0)))
    $tcp.Connect((New-Object System.Net.IPEndPoint -ArgumentList @([Net.IPAddress]::Parse($RecorderIp),$RtspPort)))
    $udp.Bind((New-Object System.Net.IPEndPoint -ArgumentList @([Net.IPAddress]::Parse($LocalIp),$LocalRtpPort)))
    $target = New-Object System.Net.IPEndPoint -ArgumentList @([Net.IPAddress]::Parse($RecorderIp),$RecorderRtpPort)

    $uri = "rtsp://${RecorderIp}:$RtspPort/record/telephone/$ServiceId/$EndpointId/$Direction/$CallLegId"
    Write-GatewayEvent 'GATEWAY_RECORDING_SESSION_OPENING' @{ recorder_rtsp_uri=$uri; recorder_rtp_port=$RecorderRtpPort; local_rtp_port=$LocalRtpPort }
    [void](Invoke-Rtsp $tcp 'OPTIONS' $uri)
    $label = ('telephone-{0}-{1}-{2}-{3}' -f $ServiceId,$EndpointId,$Direction,$CallLegId).ToLowerInvariant()
    $sdp = (@(
        'v=0',
        ("o=GATEWAY-POC-01 1 1 IN IP4 $LocalIp"),
        ("s=TELEPHONE $ServiceId $EndpointId $Direction $CallLegId"),
        ("c=IN IP4 $RecorderIp"),
        't=0 0',
        ("m=audio $RecorderRtpPort RTP/AVP 8"),
        'a=rtpmap:8 PCMA/8000',
        ("a=label:$label"),
        'a=mid:audio0',
        ("a=x-sip-call-id:$SipCallIdRaw"),
        ("a=x-gateway-call-leg:$CallLegId")
    ) -join "`r`n") + "`r`n"
    [void](Invoke-Rtsp $tcp 'ANNOUNCE' $uri $sdp @{'Content-Type'='application/sdp'})
    [void](Invoke-Rtsp $tcp 'SETUP' $uri '' @{'Transport'="RTP/AVP;unicast;client_port=$LocalRtpPort-$($LocalRtpPort+1);mode=record"})
    Write-GatewayEvent 'GATEWAY_RECORDING_SESSION_READY' @{ rtsp_session_id=$script:Session }
    [void](Invoke-Rtsp $tcp 'RECORD' $uri)
    Write-GatewayEvent 'GATEWAY_RTP_FORWARD_STARTED' @{ codec='PCMA'; payload_type=8; passthrough=$true }
    $seq=[uint16]7000; $ts=[uint32]96000; $ssrc=[uint32]0x71108208
    $packets = Send-RtpPcma $udp $target $AnsweredMediaMs ([ref]$seq) ([ref]$ts) $ssrc
    [void](Invoke-Rtsp $tcp 'PAUSE' $uri)
    Write-GatewayEvent 'GATEWAY_RTP_FORWARD_STOPPED' @{ packets=$packets; payload_bytes=($packets*160) }
    Write-GatewayEvent 'SIP_BYE_RECEIVED' @{}
    Write-GatewayEvent 'GATEWAY_RECORDING_SESSION_CLOSING' @{ rtsp_session_id=$script:Session }
    [void](Invoke-Rtsp $tcp 'TEARDOWN' $uri)
    Write-GatewayEvent 'GATEWAY_RECORDING_SESSION_CLOSED' @{ rtsp_session_id=$script:Session }
    Write-GatewayEvent 'GATEWAY_CALL_CLOSED' @{ packets=$packets; payload_bytes=($packets*160) }
    if($CorrelationPath){
        $corr=[ordered]@{ schema='recorder-poc.phase8.gateway-correlation.v1'; gateway_id='GATEWAY-POC-01'; call_leg_id=$CallLegId; sip_call_id_raw=$SipCallIdRaw; rtsp_session_id=$script:Session; endpoint_id=$EndpointId; service_id=$ServiceId; direction=$Direction; packets=$packets; payload_bytes=($packets*160); codec='PCMA'; payload_type=8 }
        $corr | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $CorrelationPath -Encoding UTF8
    }
    Write-Host ('RECORDING GATEWAY SIP INGRESS: PASS packets={0} bytes={1} session={2}' -f $packets,($packets*160),$script:Session) -ForegroundColor Green
} finally { try { $tcp.Close() } catch {}; try { $udp.Close() } catch {} }
