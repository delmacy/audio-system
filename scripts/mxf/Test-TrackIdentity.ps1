Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
Assert-GStreamerMxf

$runDir = Ensure-RunDirectory
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $runDir ("identity-3-tracks-$stamp.mxf")

Write-Host '=== Track identity spike ==='
Write-Host 'Creating a 3-track MXF with a mandatory semantic sidecar manifest.'
Write-Host "MXF: $out"

& (Join-Path $PSScriptRoot 'Invoke-GstMxf.ps1') -Tracks 3 -Seconds 5 -Output $out -KeepPipelineText
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not (Test-Path -LiteralPath $out)) { throw "MXF was not created: $out" }

$defs = @(
    [ordered]@{ track_index = 1; track_uid = ('TRK-' + ([guid]::NewGuid().ToString().ToUpperInvariant())); display_name = 'CWP-A01 / RADIO-A / RX'; endpoint_id = 'CWP-A01'; service_id = 'RADIO-A'; direction = 'RX' },
    [ordered]@{ track_index = 2; track_uid = ('TRK-' + ([guid]::NewGuid().ToString().ToUpperInvariant())); display_name = 'CWP-A01 / RADIO-A / TX'; endpoint_id = 'CWP-A01'; service_id = 'RADIO-A'; direction = 'TX' },
    [ordered]@{ track_index = 3; track_uid = ('TRK-' + ([guid]::NewGuid().ToString().ToUpperInvariant())); display_name = 'CWP-A02 / TEL-01 / RX'; endpoint_id = 'CWP-A02'; service_id = 'TEL-01'; direction = 'RX' }
)

$gstInspect = Get-GstTool 'gst-inspect-1.0.exe'
$inspectText = (& $gstInspect mxfmux 2>&1 | Out-String)
$tagSetterAdvertised = $inspectText -match 'GstTagSetter'

$ffprobe = Find-Executable @('ffprobe.exe','ffprobe')
$streams = @()
if ($ffprobe) {
    $probeJson = & $ffprobe -v error -show_entries 'stream=index,codec_name,codec_type,sample_rate,channels:stream_tags' -of json $out
    if ($LASTEXITCODE -eq 0 -and $probeJson) {
        try {
            $probe = ($probeJson | Out-String | ConvertFrom-Json)
            if ($probe.streams) {
                $streams = @($probe.streams | ForEach-Object {
                    [ordered]@{
                        ffprobe_index = $_.index
                        codec_name = $_.codec_name
                        codec_type = $_.codec_type
                        sample_rate = $_.sample_rate
                        channels = $_.channels
                        tags = $_.tags
                    }
                })
            }
        } catch {
            Write-Warning "ffprobe JSON could not be parsed: $($_.Exception.Message)"
        }
    }
}

$manifest = [ordered]@{
    schema = 'recorder-poc.track-map.v1'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    file = $out
    identity_policy = [ordered]@{
        track_index = 'required-local-to-file'
        track_uid = 'required-stable-identity'
        display_name = 'required-human-readable'
        display_name_is_key = $false
    }
    mxfmux = [ordered]@{
        gst_tag_setter_advertised = [bool]$tagSetterAdvertised
        note = 'This only detects a generic tag-writing interface. It does not prove per-track human-readable naming inside MXF.'
    }
    tracks = $defs
    ffprobe_streams = $streams
}

$manifestPath = $out + '.tracks.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $manifestPath

Write-Host ''
Write-Host 'Semantic track map:'
$defs | ForEach-Object {
    Write-Host ("  #{0,-3} {1} | {2}" -f $_.track_index, $_.track_uid, $_.display_name)
}
Write-Host ''
Write-Host ("mxfmux advertises GstTagSetter: {0}" -f $tagSetterAdvertised)
Write-Host ("ffprobe streams found: {0}" -f @($streams).Count)
Write-Host ("Track manifest: {0}" -f $manifestPath)

if (@($streams).Count -eq 3) {
    Write-Host 'TRACK IDENTITY SIDECAR: PASS (3 MXF streams + 3 semantic identities)' -ForegroundColor Green
    exit 0
}

Write-Warning ("Expected 3 streams but ffprobe reported {0}. The semantic manifest was still created; inspect the MXF before accepting this gate." -f @($streams).Count)
exit 3
