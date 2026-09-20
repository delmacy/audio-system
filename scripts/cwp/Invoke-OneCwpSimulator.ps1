param(
    [Parameter(Mandatory=$true)][string]$LocalIp,
    [Parameter(Mandatory=$true)][string]$RecorderIp,
    [int]$RtspPort = 8554,
    [int]$RecorderRtpPort = 20000,
    [int]$LocalRtpPort = 21000,
    [string]$EndpointId = 'CWP-A01',
    [string]$ServiceId = '121500',
    [int]$FirstRecordMs = 3000,
    [int]$PauseMs = 500,
    [int]$SecondRecordMs = 2000
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
    $lines.Add('User-Agent: recorder-poc-cwp/3.0.0')
    if ($script:Session -and $Method -notin @('OPTIONS','ANNOUNCE')) { $lines.Add("Session: $script:Session") }
    foreach ($k in $Headers.Keys) { $lines.Add(('{0}: {1}' -f $k,$Headers[$k])) }
    if ($Body) {
        $bodyBytes = [Text.Encoding]::ASCII.GetBytes($Body)
        if (-not $Headers.ContainsKey('Content-Type')) { $lines.Add('Content-Type: application/sdp') }
        $lines.Add("Content-Length: $($bodyBytes.Length)")
    } else {
        $lines.Add('Content-Length: 0')
    }
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

function Send-RtpBurst {
    param(
        [System.Net.Sockets.Socket]$Udp,
        [System.Net.IPEndPoint]$Target,
        [int]$DurationMs,
        [ref]$Sequence,
        [ref]$Timestamp,
        [uint32]$Ssrc
    )
    $packetCount = [int][Math]::Floor($DurationMs / 20)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    for ($i=0; $i -lt $packetCount; $i++) {
        $targetMs = $i * 20
        while ($sw.ElapsedMilliseconds -lt $targetMs) {
            $remaining = $targetMs - $sw.ElapsedMilliseconds
            if ($remaining -gt 2) { Start-Sleep -Milliseconds ([Math]::Min(5,$remaining-1)) }
        }
        $packet = New-Object byte[] 172
        $packet[0] = 0x80
        $packet[1] = 8
        Set-UInt16BE $packet 2 ([uint16]$Sequence.Value)
        Set-UInt32BE $packet 4 ([uint32]$Timestamp.Value)
        Set-UInt32BE $packet 8 $Ssrc
        for ($j=0; $j -lt 160; $j++) {
            # Every byte is a valid G.711 A-law code.  The changing pattern is
            # deterministic and intentionally cheap; real clips arrive later
            # through the Media Engine.
            $packet[12+$j] = [byte](0xD5 -bxor (($i + $j) -band 0x1F))
        }
        [void]$Udp.SendTo($packet,$Target)
        $Sequence.Value = [uint16](($Sequence.Value + 1) -band 0xFFFF)
        $Timestamp.Value = [uint32](($Timestamp.Value + 160) -band 0xFFFFFFFFL)
    }
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

    $uri = "rtsp://${RecorderIp}:$RtspPort/record/$EndpointId/radio-$ServiceId-rx"
    [void](Invoke-Rtsp $tcp 'OPTIONS' $uri)
    $sdp = (@(
        'v=0',
        ("o=$EndpointId 1 1 IN IP4 $LocalIp"),
        ("s=RADIO $ServiceId $EndpointId RX"),
        ("c=IN IP4 $RecorderIp"),
        't=0 0',
        ("m=audio $RecorderRtpPort RTP/AVP 8"),
        'a=rtpmap:8 PCMA/8000',
        ("a=label:radio-$ServiceId-$($EndpointId.ToLowerInvariant())-rx"),
        'a=mid:audio0'
    ) -join "`r`n") + "`r`n"
    [void](Invoke-Rtsp $tcp 'ANNOUNCE' $uri $sdp @{'Content-Type'='application/sdp'})
    [void](Invoke-Rtsp $tcp 'SETUP' $uri '' @{'Transport'="RTP/AVP;unicast;client_port=$LocalRtpPort-$($LocalRtpPort+1);mode=record"})

    $seq = [uint16]1000
    $ts = [uint32]32000
    $ssrc = [uint32]0x13572468
    [void](Invoke-Rtsp $tcp 'RECORD' $uri)
    Send-RtpBurst $udp $target $FirstRecordMs ([ref]$seq) ([ref]$ts) $ssrc
    [void](Invoke-Rtsp $tcp 'PAUSE' $uri)
    Start-Sleep -Milliseconds $PauseMs
    $ts = [uint32](($ts + [uint32]($PauseMs * 8)) -band 0xFFFFFFFFL)
    [void](Invoke-Rtsp $tcp 'GET_PARAMETER' $uri)
    [void](Invoke-Rtsp $tcp 'RECORD' $uri)
    Send-RtpBurst $udp $target $SecondRecordMs ([ref]$seq) ([ref]$ts) $ssrc
    [void](Invoke-Rtsp $tcp 'TEARDOWN' $uri)

    Write-Host ('CWP SIMULATOR: PASS packets={0} media_ms={1} pause_ms={2}' -f ([int](($FirstRecordMs+$SecondRecordMs)/20)),($FirstRecordMs+$SecondRecordMs),$PauseMs) -ForegroundColor Green
} finally {
    try { $tcp.Close() } catch {}
    try { $udp.Close() } catch {}
}
