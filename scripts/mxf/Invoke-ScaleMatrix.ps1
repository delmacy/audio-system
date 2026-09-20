param(
    [int[]]$TrackCounts = @(2,10,50,100),
    [ValidateRange(1,120)][int]$Seconds = 5
)
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
$runDir = Ensure-RunDirectory
$writer = Join-Path $PSScriptRoot 'Invoke-GstMxf.ps1'
$rows = @()
foreach ($n in $TrackCounts) {
    if ($n -gt 200) { throw 'gst-launch scale runner is intentionally capped at 200 tracks. Use the native mxf-lab harness for 500/1000.' }
    $out = Join-Path $runDir ("scale-$n.mxf")
    try {
        & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $writer -Tracks $n -Seconds $Seconds -Output $out
        $rc = $LASTEXITCODE
        if ($rc -ne 0) { throw "writer exit $rc" }
        $f = Get-Item $out
        $rows += [pscustomobject]@{Tracks=$n; Result='PASS'; Bytes=$f.Length; File=$out}
    } catch {
        $rows += [pscustomobject]@{Tracks=$n; Result='FAIL'; Bytes=0; File=$out; Error=$_.Exception.Message}
        break
    }
}
$rows | Format-Table -AutoSize
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rows | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $runDir "scale-$stamp.json")
if (($rows | Where-Object Result -eq 'FAIL').Count -gt 0) { exit 1 }
Write-Host 'GST SCALE MATRIX: PASS' -ForegroundColor Green
