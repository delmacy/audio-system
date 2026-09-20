[CmdletBinding()]
param(
    [string]$AddressA = '10.20.1.101',
    [string]$AddressB = '10.20.2.101',
    [int]$PortA = 41001,
    [int]$PortB = 41002,
    [int]$PacketsEachDirection = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-BoundUdp([string]$Address, [int]$Port) {
    $ip = [System.Net.IPAddress]::Parse($Address)
    $ep = [System.Net.IPEndPoint]::new($ip, $Port)
    $client = [System.Net.Sockets.UdpClient]::new()
    $client.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket,
        [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    $client.Client.Bind($ep)
    $client.Client.ReceiveTimeout = 3000
    return $client
}

function Send-And-Receive {
    param(
        [System.Net.Sockets.UdpClient]$Sender,
        [System.Net.Sockets.UdpClient]$Receiver,
        [string]$DestinationAddress,
        [int]$DestinationPort,
        [string]$Label,
        [int]$Count
    )

    $dest = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($DestinationAddress), $DestinationPort)
    for ($i = 1; $i -le $Count; $i++) {
        $payloadText = "RECORDER-POC|PHASE1|$Label|SEQ=$i|UTC=$([DateTime]::UtcNow.ToString('o'))"
        $payload = [System.Text.Encoding]::ASCII.GetBytes($payloadText)
        [void]$Sender.Send($payload, $payload.Length, $dest)
    }

    $received = 0
    $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
    for ($i = 1; $i -le $Count; $i++) {
        try {
            $bytes = $Receiver.Receive([ref]$remote)
            $text = [System.Text.Encoding]::ASCII.GetString($bytes)
            if ($text -like "RECORDER-POC|PHASE1|$Label|*") { $received++ }
        } catch {
            break
        }
    }
    return $received
}

Write-Host "Binding A = $AddressA`:$PortA" -ForegroundColor Cyan
Write-Host "Binding B = $AddressB`:$PortB" -ForegroundColor Cyan

$a = New-BoundUdp $AddressA $PortA
$b = New-BoundUdp $AddressB $PortB
try {
    $ba = Send-And-Receive -Sender $b -Receiver $a -DestinationAddress $AddressA -DestinationPort $PortA -Label 'B_TO_A' -Count $PacketsEachDirection
    $ab = Send-And-Receive -Sender $a -Receiver $b -DestinationAddress $AddressB -DestinationPort $PortB -Label 'A_TO_B' -Count $PacketsEachDirection

    Write-Host ''
    Write-Host "B -> A received: $ba / $PacketsEachDirection"
    Write-Host "A -> B received: $ab / $PacketsEachDirection"

    if ($ba -eq $PacketsEachDirection -and $ab -eq $PacketsEachDirection) {
        Write-Host 'UDP BIND TEST: PASS' -ForegroundColor Green
        return $true
    }

    Write-Host 'UDP BIND TEST: FAIL' -ForegroundColor Red
    throw 'UDP bind test did not receive all expected datagrams.'
} finally {
    $a.Close()
    $b.Close()
}
