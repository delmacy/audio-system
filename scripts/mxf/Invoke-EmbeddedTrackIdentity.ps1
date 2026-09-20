Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
. (Join-Path $PSScriptRoot 'Track-Identity.ps1')

$root = Get-ProjectRoot
$pluginRoot = Join-Path $root 'src\mxf-identity-plugin'
$dll = Join-Path $pluginRoot 'bin\gstmxfidentity.dll'
if (-not (Test-Path $dll)) { throw 'Identity plugin not built. Run 14-build-mxf-identity-plugin.cmd first.' }
$gstRoot = $env:GSTREAMER_ROOT_X86_64
if (-not $gstRoot) { $bin=Find-GStreamerBin; if($bin){$gstRoot=Split-Path $bin -Parent} }
if (-not $gstRoot) { throw 'GStreamer not found.' }
$gstBin=Join-Path $gstRoot 'bin'; if(-not (($env:PATH -split ';')|Where-Object{$_.TrimEnd('\') -ieq $gstBin.TrimEnd('\')})){$env:PATH=$gstBin+';'+$env:PATH}
$customPluginDir = Split-Path $dll -Parent
$runDir=Ensure-RunDirectory -Name 'mxf-identity'
$inspect=Get-GstTool 'gst-inspect-1.0.exe'

# Keep writer and reader plugin discovery isolated. The custom DLL contains a
# patched GstMXFMux type; loading it in the same process/plugin registry as the
# stock MXF plugin can prevent the official mxfdemux factory from registering.
$writerRegistry = Join-Path $runDir 'registry-identity-writer-2.0.15.bin'
$readerRegistry = Join-Path $runDir 'registry-identity-reader-2.0.15.bin'
Remove-Item -LiteralPath $writerRegistry,$readerRegistry -Force -ErrorAction SilentlyContinue

$originalPluginPath = $env:GST_PLUGIN_PATH
$originalPluginPath10 = $env:GST_PLUGIN_PATH_1_0
$originalRegistry = $env:GST_REGISTRY_1_0

function Set-IdentityWriterEnvironment {
    # Keep discovery on the stock/system plugins only. mxf-lab loads the
    # identity DLL explicitly by absolute path with gst_plugin_load_file().
    $env:GST_PLUGIN_PATH = ''
    $env:GST_PLUGIN_PATH_1_0 = ''
    $env:GST_REGISTRY_1_0 = $writerRegistry
}
function Set-OfficialReaderEnvironment {
    # Empty additional path: use only the normal/system GStreamer plugin path.
    $env:GST_PLUGIN_PATH = ''
    $env:GST_PLUGIN_PATH_1_0 = ''
    $env:GST_REGISTRY_1_0 = $readerRegistry
}
function Restore-GstEnvironment {
    $env:GST_PLUGIN_PATH = $originalPluginPath
    $env:GST_PLUGIN_PATH_1_0 = $originalPluginPath10
    $env:GST_REGISTRY_1_0 = $originalRegistry
}

# Writer no longer depends on registry discovery of mxfidmux.
Set-IdentityWriterEnvironment

$exeCandidates=@((Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),(Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe'))
$exe=$exeCandidates|Where-Object{Test-Path $_}|Select-Object -First 1
if(-not $exe){throw 'mxf-lab.exe missing. Re-run 06-build-native.cmd after applying 2.0.15.'}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$caseDir=Join-Path $runDir ('embedded-'+$stamp);New-Item -ItemType Directory -Force -Path $caseDir|Out-Null
$outFile=Join-Path $caseDir 'embedded-identity.mxf';$tsv=Join-Path $caseDir 'identity-input.tsv'
$defs=@(
 [ordered]@{service_type='radio';service_id='121500';endpoint_id='CWP-A17';direction='RX';sdp_service='RADIO 121.500';label='radio-121500-rx';mid='r1'},
 [ordered]@{service_type='radio';service_id='121500';endpoint_id='CWP-A17';direction='TX';sdp_service='RADIO 121.500';label='radio-121500-tx';mid='r2'},
 [ordered]@{service_type='telephone';service_id='TEL-01';endpoint_id='CWP-A17';direction='RX';sdp_service='TEL-01';label='tel-01-rx';mid='t1'},
 [ordered]@{service_type='radio';service_id='132700';endpoint_id='CWP-A18';direction='RX';sdp_service='RADIO 132.700';label='radio-132700-rx';mid='r4'}
)
$rows=@();$lines=@()
foreach($d in $defs){
 $id=New-LogicalTrackIdentity -ServiceType $d.service_type -ServiceId $d.service_id -EndpointId $d.endpoint_id -Direction $d.direction -SdpServiceNameRaw $d.sdp_service -SdpLabelRaw $d.label -SdpMidRaw $d.mid
 $embedded=('{0} | LT={1} | TI={2}' -f $id.display_name,$id.logical_track_uuid,$id.track_instance_uuid)
 $rows += [ordered]@{display_name=$id.display_name;logical_track_uuid=$id.logical_track_uuid;track_instance_uuid=$id.track_instance_uuid;embedded_track_name=$embedded;canonical_identity=$id.canonical_identity}
 $lines += ($id.display_name + "`t" + $id.logical_track_uuid + "`t" + $id.track_instance_uuid)
}
# Write UTF-8 without BOM so the native parser sees the first label exactly.
[IO.File]::WriteAllLines($tsv,$lines,(New-Object Text.UTF8Encoding($false)))

Write-Host '=== Embedded MXF Track Identity Gate ==='
Set-IdentityWriterEnvironment
$write=Invoke-NativeProcessCapture -FilePath $exe -Arguments @('write-identity','--out',$outFile,'--identity-file',$tsv,'--plugin-dll',$dll,'--seconds','2') -TimeoutMs 30000
$write.StdOut|Write-Host;if($write.StdErr){$write.StdErr|Write-Host}
if($write.ExitCode -ne 0){Restore-GstEnvironment; throw "write-identity failed: $($write.ExitCode)"}

$ffprobe=Find-Executable @('ffprobe.exe','ffprobe');if(-not $ffprobe){throw 'ffprobe required.'}
$probeJson=& $ffprobe -v error -select_streams a -show_entries stream=index -of json $outFile
if($LASTEXITCODE -ne 0){throw 'ffprobe failed.'};$streamCount=@((($probeJson|Out-String|ConvertFrom-Json).streams)).Count

# Readback deliberately runs without the custom plugin. This proves that the
# identity is persisted in standard MXF TrackName metadata and can be recovered
# by the stock GStreamer 1.28.7 mxfdemux.
Set-OfficialReaderEnvironment
$officialFilesrc = Invoke-NativeProcessCapture -FilePath $inspect -Arguments @('filesrc') -TimeoutMs 10000
$officialDemux = Invoke-NativeProcessCapture -FilePath $inspect -Arguments @('mxfdemux') -TimeoutMs 10000
if($officialFilesrc.ExitCode -ne 0 -or $officialDemux.ExitCode -ne 0){
    Restore-GstEnvironment
    throw ("Official reader prerequisites missing: filesrc={0} mxfdemux={1}" -f $officialFilesrc.ExitCode,$officialDemux.ExitCode)
}
$read=Invoke-NativeProcessCapture -FilePath $exe -Arguments @('inspect-identity',$outFile,'--timeout-ms','15000') -TimeoutMs 20000
Restore-GstEnvironment

# gst_structure_to_string() serializes nested GstStructure values with multiple
# escaping layers.  TrackName is already present in the MXF, but a literal
# Contains() against the serialized form therefore returns false.  Normalize
# only the serialization escape character before comparing semantic identity.
$readerStdOutPath = Join-Path $caseDir 'reader-stdout.txt'
$readerStdErrPath = Join-Path $caseDir 'reader-stderr.txt'
[IO.File]::WriteAllText($readerStdOutPath,[string]$read.StdOut,(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($readerStdErrPath,[string]$read.StdErr,(New-Object Text.UTF8Encoding($false)))
$normalizedRead = ([string]$read.StdOut) -replace '\\',''

# Keep the noisy stock-mxfdemux teardown diagnostics in the evidence file, but
# do not confuse them with identity-read failure.  Any other stderr remains
# visible to the operator.
$stderrLines = @(([string]$read.StdErr -split "`r?`n") | Where-Object { $_ -and $_.Trim() })
$knownTeardown = @($stderrLines | Where-Object { $_ -match 'finalized while still in-construction' })
$otherStderr = @($stderrLines | Where-Object { $_ -notmatch 'finalized while still in-construction' })
if($otherStderr.Count -gt 0){ $otherStderr | ForEach-Object { Write-Host $_ } }
if($knownTeardown.Count -gt 0){ Write-Host ('Reader teardown diagnostics captured: {0} known GLib lines (non-fatal for identity gate).' -f $knownTeardown.Count) -ForegroundColor Yellow }

$found=@();$allPass=$true
foreach($r in $rows){
 $nameOk=$normalizedRead.Contains([string]$r.display_name)
 $logicalOk=$normalizedRead.Contains(('LT='+[string]$r.logical_track_uuid))
 $instanceOk=$normalizedRead.Contains(('TI='+[string]$r.track_instance_uuid))
 $ok=$nameOk -and $logicalOk -and $instanceOk
 if(-not $ok){$allPass=$false}
 $found += [ordered]@{display_name=$r.display_name;logical_track_uuid=$r.logical_track_uuid;track_instance_uuid=$r.track_instance_uuid;name_found=$nameOk;logical_found=$logicalOk;instance_found=$instanceOk;pass=$ok}
}
$result=if($write.ExitCode -eq 0 -and $read.ExitCode -eq 0 -and $streamCount -eq $rows.Count -and $allPass){'PASS'}else{'FAIL'}
$report=[ordered]@{
 schema='recorder-poc.embedded-track-identity.v3';result=$result;file=$outFile;streams=$streamCount;expected_tracks=$rows.Count;
 writer_exit=$write.ExitCode;reader_exit=$read.ExitCode;readback_source='MXF via isolated official mxfdemux mxf-structure tags';readback_parser='normalized gst_structure_to_string escaping';sidecar_required_for_readback=$false;writer_registry=$writerRegistry;reader_registry=$readerRegistry;reader_stdout=$readerStdOutPath;reader_stderr=$readerStdErrPath;known_teardown_diagnostic_lines=$knownTeardown.Count;
 tracks=$found;track_name_format='<DisplayName> | LT=<LogicalTrackUUID> | TI=<TrackInstanceUUID>';
 structural_ids_overloaded=$false;plugin='gstmxfidentity.dll / mxfidmux (explicit gst_plugin_load_file)';upstream='GStreamer 1.28.7'
}
$reportPath=Join-Path $caseDir 'embedded-identity-report.json';$report|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 -LiteralPath $reportPath
Write-Host "Streams: $streamCount / $($rows.Count)";foreach($f in $found){Write-Host ('  {0} | name={1} LT={2} TI={3}' -f $f.display_name,$f.name_found,$f.logical_found,$f.instance_found)}
Write-Host "Report: $reportPath"
if($result -eq 'PASS'){Write-Host 'EMBEDDED MXF TRACK IDENTITY: PASS' -ForegroundColor Green;exit 0}
Write-Error 'EMBEDDED MXF TRACK IDENTITY: FAIL';exit 7
