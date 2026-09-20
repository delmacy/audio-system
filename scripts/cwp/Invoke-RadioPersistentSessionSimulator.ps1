param(
    [Parameter(Mandatory=$true)][string]$LocalIp,
    [Parameter(Mandatory=$true)][string]$RecorderIp,
    [int]$RtspPort = 8554,
    [int]$RecorderRtpPort = 20000,
    [int]$LocalRtpPort = 21000,
    [string]$EndpointId = 'CWP-A17',
    [string]$ServiceId = '121500',
    [ValidateSet('RX','TX')][string]$Direction = 'RX',
    [int]$BurstCount = 4,
    [int]$BurstMs = 300,
    [int]$SilenceMs = 600,
    [int]$KeepaliveIntervalMs = 200,
    [int]$PausedProbePackets = 1
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
    $lines.Add('User-Agent: recorder-poc-radio/4.0.0')
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
function Send-RtpPackets {
    param(
        [System.Net.Sockets.Socket]$Udp,
        [System.Net.IPEndPoint]$Target,
        [int]$PacketCount,
        [ref]$Sequence,
        [ref]$Timestamp,
        [uint32]$Ssrc,
        [switch]$Realtime
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    for ($i=0; $i -lt $PacketCount; $i++) {
        if ($Realtime) {
            $targetMs = $i * 20
            while ($sw.ElapsedMilliseconds -lt $targetMs) {
                $remaining = $targetMs - $sw.ElapsedMilliseconds
                if ($remaining -gt 2) { Start-Sleep -Milliseconds ([Math]::Min(5,$remaining-1)) }
            }
        }
        $packet = New-Object byte[] 172
        $packet[0] = 0x80
        $packet[1] = 8
        Set-UInt16BE $packet 2 ([uint16]$Sequence.Value)
        Set-UInt32BE $packet 4 ([uint32]$Timestamp.Value)
        Set-UInt32BE $packet 8 $Ssrc
        for ($j=0; $j -lt 160; $j++) { $packet[12+$j] = [byte](0xD5 -bxor (($i + $j) -band 0x1F)) }
        [void]$Udp.SendTo($packet,$Target)
        $Sequence.Value = [uint16](($Sequence.Value + 1) -band 0xFFFF)
        $Timestamp.Value = [uint32](($Timestamp.Value + 160) -band 0xFFFFFFFFL)
    }
}

if ($BurstCount -lt 2) { throw 'BurstCount must be >= 2 for persistent-session proof.' }
if ($BurstMs -lt 20 -or ($BurstMs % 20) -ne 0) { throw 'BurstMs must be a positive multiple of 20.' }
if ($SilenceMs -lt $KeepaliveIntervalMs) { throw 'SilenceMs must be >= KeepaliveIntervalMs.' }

$tcp = New-Socket ([System.Net.Sockets.SocketType]::Stream) ([System.Net.Sockets.ProtocolType]::Tcp)
$udp = New-Socket ([System.Net.Sockets.SocketType]::Dgram) ([System.Net.Sockets.ProtocolType]::Udp)
$keepalives = 0
$activePackets = 0
$pausedPackets = 0
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
    if (-not $script:Session) { throw 'SETUP did not establish an RTSP Session.' }

    $seq = [uint16]4000
    $ts = [uint32]64000
    $ssrc = [uint32]0x24681357
    $burstPackets = [int]($BurstMs / 20)
    for ($burst=1; $burst -le $BurstCount; $burst++) {
        [void](Invoke-Rtsp $tcp 'RECORD' $uri)
        Send-RtpPackets $udp $target $burstPackets ([ref]$seq) ([ref]$ts) $ssrc -Realtime
        $activePackets += $burstPackets
        [void](Invoke-Rtsp $tcp 'PAUSE' $uri)

        $elapsed = 0
        $probeSent = 0
        while ($elapsed -lt $SilenceMs) {
            $sleep = [Math]::Min($KeepaliveIntervalMs,$SilenceMs-$elapsed)
            Start-Sleep -Milliseconds $sleep
            $elapsed += $sleep
            [void](Invoke-Rtsp $tcp 'GET_PARAMETER' $uri)
            $keepalives++
            if ($probeSent -lt $PausedProbePackets) {
                Send-RtpPackets $udp $target 1 ([ref]$seq) ([ref]$ts) $ssrc
                $pausedPackets++
                $probeSent++
            }
        }
        $remainingSilenceMs = [Math]::Max(0,$SilenceMs - ($PausedProbePackets * 20))
        $ts = [uint32](($ts + [uint32]($remainingSilenceMs * 8)) -band 0xFFFFFFFFL)
    }
    [void](Invoke-Rtsp $tcp 'TEARDOWN' $uri)

    Write-Host ('RADIO PERSISTENT SIMULATOR: PASS session={0} direction={1} bursts={2} active_packets={3} paused_probe_packets={4} keepalives={5}' -f $script:InitialSession,$Direction,$BurstCount,$activePackets,$pausedPackets,$keepalives) -ForegroundColor Green
} finally {
    try { $tcp.Close() } catch {}
    try { $udp.Close() } catch {}
}
