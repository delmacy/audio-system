Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Recorder PoC namespace. This value is immutable once recordings exist.
$script:RecorderLogicalTrackNamespace = [Guid]'a6d0a6d5-7a56-4ea4-a3f5-4963d91d7d64'

function Convert-GuidToNetworkBytes {
    param([Parameter(Mandatory=$true)][Guid]$Guid)
    $b = $Guid.ToByteArray()
    return [byte[]]@(
        $b[3],$b[2],$b[1],$b[0],
        $b[5],$b[4],
        $b[7],$b[6],
        $b[8],$b[9],$b[10],$b[11],$b[12],$b[13],$b[14],$b[15]
    )
}

function Convert-NetworkBytesToGuid {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    if ($Bytes.Length -ne 16) { throw 'A UUID must contain exactly 16 bytes.' }
    $b = [byte[]]@(
        $Bytes[3],$Bytes[2],$Bytes[1],$Bytes[0],
        $Bytes[5],$Bytes[4],
        $Bytes[7],$Bytes[6],
        $Bytes[8],$Bytes[9],$Bytes[10],$Bytes[11],$Bytes[12],$Bytes[13],$Bytes[14],$Bytes[15]
    )
    return New-Object Guid (,$b)
}

function New-UuidV5 {
    param(
        [Parameter(Mandatory=$true)][Guid]$Namespace,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $ns = Convert-GuidToNetworkBytes $Namespace
    $nameBytes = [Text.Encoding]::UTF8.GetBytes($Name)
    $input = New-Object byte[] ($ns.Length + $nameBytes.Length)
    [Array]::Copy($ns,0,$input,0,$ns.Length)
    [Array]::Copy($nameBytes,0,$input,$ns.Length,$nameBytes.Length)
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try { $hash = $sha1.ComputeHash($input) } finally { $sha1.Dispose() }
    $uuid = New-Object byte[] 16
    [Array]::Copy($hash,0,$uuid,0,16)
    $uuid[6] = [byte](($uuid[6] -band 0x0F) -bor 0x50) # version 5
    $uuid[8] = [byte](($uuid[8] -band 0x3F) -bor 0x80) # RFC variant
    return (Convert-NetworkBytesToGuid $uuid)
}

function New-UuidV7 {
    # RFC 9562 UUIDv7 layout: 48-bit Unix epoch milliseconds + random bits.
    $ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $b = New-Object byte[] 16
    for ($i = 5; $i -ge 0; $i--) {
        $b[$i] = [byte]($ms -band 0xFF)
        $ms = [math]::Floor($ms / 256)
    }
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rnd = New-Object byte[] 10
        $rng.GetBytes($rnd)
    } finally { $rng.Dispose() }
    [Array]::Copy($rnd,0,$b,6,10)
    $b[6] = [byte](($b[6] -band 0x0F) -bor 0x70)
    $b[8] = [byte](($b[8] -band 0x3F) -bor 0x80)
    return (Convert-NetworkBytesToGuid $b)
}

function Get-CanonicalTrackIdentity {
    param(
        [Parameter(Mandatory=$true)][string]$ServiceType,
        [Parameter(Mandatory=$true)][string]$ServiceId,
        [Parameter(Mandatory=$true)][string]$EndpointId,
        [Parameter(Mandatory=$true)][ValidateSet('RX','TX','MIX','BIDIR')][string]$Direction
    )
    # Keep this canonicalization deliberately boring and versioned.
    # Never derive it from TrackIndex, RTP port, SSRC, file name or mutable display labels.
    $parts = @(
        'identity-v1',
        ('service_type=' + $ServiceType.Trim().ToLowerInvariant()),
        ('service_id=' + $ServiceId.Trim().ToLowerInvariant()),
        ('endpoint_id=' + $EndpointId.Trim().ToLowerInvariant()),
        ('direction=' + $Direction.Trim().ToLowerInvariant())
    )
    return ($parts -join '|')
}

function New-LogicalTrackIdentity {
    param(
        [Parameter(Mandatory=$true)][string]$ServiceType,
        [Parameter(Mandatory=$true)][string]$ServiceId,
        [Parameter(Mandatory=$true)][string]$EndpointId,
        [Parameter(Mandatory=$true)][ValidateSet('RX','TX','MIX','BIDIR')][string]$Direction,
        [string]$SdpServiceNameRaw = '',
        [string]$SdpLabelRaw = '',
        [string]$SdpMidRaw = ''
    )
    $canonical = Get-CanonicalTrackIdentity -ServiceType $ServiceType -ServiceId $ServiceId -EndpointId $EndpointId -Direction $Direction
    $logical = New-UuidV5 -Namespace $script:RecorderLogicalTrackNamespace -Name $canonical
    $instance = New-UuidV7
    $human = ('{0} {1} | {2} | {3}' -f $ServiceType.ToUpperInvariant(),$ServiceId,$EndpointId,$Direction)
    $trackName = ('{0} | LT={1}' -f $human,$logical.ToString())
    return [ordered]@{
        canonical_identity = $canonical
        logical_track_uuid = $logical.ToString()
        track_instance_uuid = $instance.ToString()
        track_name = $trackName
        display_name = $human
        service_type = $ServiceType
        service_id = $ServiceId
        endpoint_id = $EndpointId
        direction = $Direction
        sdp_service_name_raw = $SdpServiceNameRaw
        sdp_label_raw = $SdpLabelRaw
        sdp_mid_raw = $SdpMidRaw
    }
}


function New-ServiceLogicalTrackIdentity {
    param(
        [Parameter(Mandatory=$true)][string]$ServiceType,
        [Parameter(Mandatory=$true)][string]$ServiceId,
        [Parameter(Mandatory=$true)][string]$EndpointId,
        [string]$MediaFlow = 'mono',
        [string]$SdpServiceNameRaw = '',
        [string]$SdpLabelRaw = '',
        [string]$SdpMidRaw = '',
        [string]$CallLegId = ''
    )
    $parts = @(
        'identity-v1',
        ('service_type=' + $ServiceType.Trim().ToLowerInvariant()),
        ('service_id=' + $ServiceId.Trim().ToLowerInvariant()),
        ('endpoint_id=' + $EndpointId.Trim().ToLowerInvariant()),
        ('media_flow=' + $MediaFlow.Trim().ToLowerInvariant())
    )
    if ($CallLegId) { $parts += ('call_leg_id=' + $CallLegId.Trim().ToLowerInvariant()) }
    $canonical = $parts -join '|'
    $logical = (New-UuidV5 -Namespace $script:RecorderLogicalTrackNamespace -Name $canonical).ToString()
    $instance = (New-UuidV7).ToString()
    $display = if ($ServiceType.Trim().ToLowerInvariant() -eq 'telephone' -and $CallLegId) {
        ('{0} {1} / {2} / {3}' -f $EndpointId.ToUpperInvariant(), $ServiceId.ToUpperInvariant(), $MediaFlow.ToUpperInvariant(), $CallLegId)
    } else {
        ('{0} / {1} / {2}' -f $EndpointId.ToUpperInvariant(), $ServiceId.ToUpperInvariant(), $MediaFlow.ToUpperInvariant())
    }
    $trackName = ('{0} | LT={1} | TI={2}' -f $display, $logical, $instance)
    return [ordered]@{
        canonical_identity = $canonical
        display_name = $display
        track_name = $trackName
        logical_track_uuid = $logical
        track_instance_uuid = $instance
        service_type = $ServiceType
        service_id = $ServiceId
        endpoint_id = $EndpointId
        media_flow = $MediaFlow
        call_leg_id = $CallLegId
        sdp_service_name_raw = $SdpServiceNameRaw
        sdp_label_raw = $SdpLabelRaw
        sdp_mid_raw = $SdpMidRaw
    }
}
