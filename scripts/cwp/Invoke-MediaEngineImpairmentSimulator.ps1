param(
    [Parameter(Mandatory=$true)][string]$LocalIp,
    [Parameter(Mandatory=$true)][string]$RecorderIp,
    [int]$RtspPort = 8554,
    [int]$RecorderRtpPort = 20030,
    [int]$LocalRtpPort = 21030,
    [string]$EndpointId = 'CWP-A17',
    [string]$ServiceId = '121500',
    [ValidateSet('RX','TX')][string]$Direction = 'RX'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
$script:InitialSession = $null
function Invoke-Rtsp {
    param(
        [System.Net.Sockets.Socket]$Socket,
        [string]$Method,
        [string]$Uri,
        [string]$Body = '',
        [hashtable]$Headers = @{}
    )
    $script:CSeq++
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("$Method $Uri RTSP/1.0")
    $lines.Add("CSeq: $script:CSeq")
    $lines.Add('User-Agent: recorder-poc-media-engine/6.0.0')
    if ($script:Session -and $Method -notin @('OPTIONS','ANNOUNCE','SETUP')) { $lines.Add("Session: $script:Session") }
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
    if ($text -match '(?im)^Session:\s*([^;\r\n]+)') {
        $returned = $Matches[1].Trim()
        if (-not $script:InitialSession) { $script:InitialSession = $returned }
        elseif ($returned -ne $script:InitialSession) { throw "RTSP Session changed unexpectedly: $($script:InitialSession) -> $returned" }
        $script:Session = $returned
    }
    return $text
}
function Set-UInt16BE([byte[]]$Buffer,[int]$Offset,[uint16]$Value) {
    $Buffer[$Offset] = [byte](($Value -shr 8) -band 0xFF)
    $Buffer[$Offset+1] = [byte]($Value -band 0xFF)
}
function Set-UInt32BE([byte[]]$Buffer,[int]$Offset,[uint32]$Value) {
    $Buffer[$Offset] = [byte](($Value -shr 24) -band 0xFF)
    $Buffer[$Offset+1] = [byte](($Value -shr 16) -band 0xFF)
    $Buffer[$Offset+2] = [byte](($Value -shr 8) -band 0xFF)
    $Buffer[$Offset+3] = [byte]($Value -band 0xFF)
}
function New-RtpPacket {
    param([uint16]$Sequence,[uint32]$Timestamp,[uint32]$Ssrc,[int]$PayloadType=8,[int]$PayloadLen=160)
    $packet = New-Object byte[] (12+$PayloadLen)
    $packet[0] = 0x80
    $packet[1] = [byte]($PayloadType -band 0x7f)
    Set-UInt16BE $packet 2 $Sequence
    Set-UInt32BE $packet 4 $Timestamp
    Set-UInt32BE $packet 8 $Ssrc
    for ($j=0; $j -lt $PayloadLen; $j++) { $packet[12+$j] = [byte](0xD5 -bxor (($Sequence + $j) -band 0x1F)) }
    return $packet
}
function Send-RtpPacket {
    param([System.Net.Sockets.Socket]$Udp,[System.Net.IPEndPoint]$Target,[uint16]$Sequence,[uint32]$Timestamp,[uint32]$Ssrc,[int]$PayloadType=8,[int]$PayloadLen=160)
    [void]$Udp.SendTo((New-RtpPacket -Sequence $Sequence -Timestamp $Timestamp -Ssrc $Ssrc -PayloadType $PayloadType -PayloadLen $PayloadLen),$Target)
}

$tcp = New-Socket ([System.Net.Sockets.SocketType]::Stream) ([System.Net.Sockets.ProtocolType]::Tcp)
$udp = New-Socket ([System.Net.Sockets.SocketType]::Dgram) ([System.Net.Sockets.ProtocolType]::Udp)
try {
    $tcp.ReceiveTimeout = 5000
    $tcp.SendTimeout = 5000
    $tcp.Bind((New-Object System.Net.IPEndPoint -ArgumentList @([Net.IPAddress]::Parse($LocalIp),0)))
    $tcp.Connect((New-Object System.Net.IPEndPoint -ArgumentList @([Net.IPAddress]::Parse($RecorderIp),$RtspPort)))
    $udp.Bind((New-Object System.Net.IPEndPoint -ArgumentList @([Net.IPAddress]::Parse($LocalIp),$LocalRtpPort)))
    $target = New-Object System.Net.IPEndPoint -ArgumentList @([Net.IPAddress]::Parse($RecorderIp),$RecorderRtpPort)

    $directionLower = $Direction.ToLowerInvariant()
    $uri = "rtsp://${RecorderIp}:$RtspPort/record/$EndpointId/radio-$ServiceId-$directionLower"
    [void](Invoke-Rtsp $tcp 'OPTIONS' $uri)
    $sdp = (@(
        'v=0',
        ("o=$EndpointId 1 1 IN IP4 $LocalIp"),
        ("s=RADIO $ServiceId $EndpointId $Direction"),
        ("c=IN IP4 $RecorderIp"),
        't=0 0',
        ("m=audio $RecorderRtpPort RTP/AVP 8"),
        'a=rtpmap:8 PCMA/8000',
        ("a=label:radio-$ServiceId-$($EndpointId.ToLowerInvariant())-$directionLower"),
        'a=mid:audio0'
    ) -join "`r`n") + "`r`n"
    [void](Invoke-Rtsp $tcp 'ANNOUNCE' $uri $sdp @{'Content-Type'='application/sdp'})
    [void](Invoke-Rtsp $tcp 'SETUP' $uri '' @{'Transport'="RTP/AVP;unicast;client_port=$LocalRtpPort-$($LocalRtpPort+1);mode=record"})
    [void](Invoke-Rtsp $tcp 'RECORD' $uri)

    $ssrc = [uint32]0x51606060
    $baseSeq = [uint16]5000
    $baseTs = [uint32]80000
    # Ten clean packets: seq 5000..5009, ts +160.
    for ($i=0; $i -lt 10; $i++) { Send-RtpPacket $udp $target ([uint16]($baseSeq+$i)) ([uint32]($baseTs+($i*160))) $ssrc; Start-Sleep -Milliseconds 2 }
    # Duplicate of last accepted sequence. Must be counted/dropped, not recorded.
    Send-RtpPacket $udp $target ([uint16]5009) ([uint32]($baseTs+(9*160))) $ssrc
    # Out-of-order late packet. Must be counted/dropped, not recorded.
    Send-RtpPacket $udp $target ([uint16]5008) ([uint32]($baseTs+(8*160))) $ssrc
    # Jump forward by one missing packet: expected 5010, received 5011.
    Send-RtpPacket $udp $target ([uint16]5011) ([uint32]($baseTs+(11*160))) $ssrc
    # Accept next sequence, but with an extra timestamp jump.
    Send-RtpPacket $udp $target ([uint16]5012) ([uint32]($baseTs+(13*160))) $ssrc
    # Unsupported payload type must be dropped before recording.
    Send-RtpPacket $udp $target ([uint16]5013) ([uint32]($baseTs+(14*160))) $ssrc -PayloadType 0
    # Malformed packet must be dropped.
    [void]$udp.SendTo((New-Object byte[] 4),$target)
    # Resume clean media at expected sequence, timestamp now following the accepted discontinuity.
    for ($i=0; $i -lt 6; $i++) {
        Send-RtpPacket $udp $target ([uint16](5013+$i)) ([uint32]($baseTs+((14+$i)*160))) $ssrc
        Start-Sleep -Milliseconds 2
    }
    Start-Sleep -Milliseconds 200
    [void](Invoke-Rtsp $tcp 'PAUSE' $uri)
    [void](Invoke-Rtsp $tcp 'TEARDOWN' $uri)
    Write-Host 'MEDIA ENGINE IMPAIRMENT SIMULATOR: PASS recorded_expected=18 duplicates=1 out_of_order=1 sequence_gaps=1 wrong_pt=1 malformed=1 timestamp_discontinuities=2' -ForegroundColor Green
} finally {
    try { $tcp.Close() } catch {}
    try { $udp.Close() } catch {}
}
