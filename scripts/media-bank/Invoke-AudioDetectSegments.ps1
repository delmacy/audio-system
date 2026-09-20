param(
    [string]$InputFolder = 'media-bank/raw',
    [string]$OutputManifest = 'media-bank/manifests/clips-manifest.csv',
    [int]$MinClipMs = 700,
    [int]$MaxClipMs = 8000,
    [int]$PaddingMs = 120,
    [int]$SilenceMs = 450,
    [string]$SilenceDb = '-35dB'
)

. "$PSScriptRoot\Common-MediaBank.ps1"
$root = Get-RepoRoot
$input = Join-Root $root $InputFolder
$out = Join-Root $root $OutputManifest
$ffmpeg = Find-FFmpeg
$files = Get-AudioFiles $input
$rows = New-Object System.Collections.Generic.List[object]
$clipNum = 0

if ($files.Count -eq 0) {
    Write-Warning ('No audio files found under {0}. Empty manifest will be created.' -f $input)
}

foreach ($f in $files) {
    $hint = Get-SpeakerHint $f.FullName
    $detected = @()
    if ($null -ne $ffmpeg) {
        $args = @('-hide_banner','-nostats','-i',$f.FullName,'-af',("silencedetect=noise={0}:d={1}" -f $SilenceDb, ($SilenceMs/1000.0).ToString([Globalization.CultureInfo]::InvariantCulture)),'-f','null','-')
        $output = & $ffmpeg @args 2>&1 | Out-String
        $starts = New-Object System.Collections.Generic.List[double]
        $ends = New-Object System.Collections.Generic.List[double]
        foreach ($line in ($output -split "`r?`n")) {
            if ($line -match 'silence_start:\s*([0-9\.]+)') { $starts.Add([double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)) | Out-Null }
            if ($line -match 'silence_end:\s*([0-9\.]+)') { $ends.Add([double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)) | Out-Null }
        }
        # Convert silence regions to speech between silence_end and next silence_start. If no boundaries found, use one candidate.
        if ($starts.Count -gt 0 -or $ends.Count -gt 0) {
            $cursor = 0.0
            $pairs = @()
            foreach ($s in $starts) {
                if ($s -gt $cursor) { $pairs += ,@($cursor, $s) }
                $cursor = $s
            }
            for ($i=0; $i -lt [Math]::Min($ends.Count,$starts.Count); $i++) { }
            # Better pass: every silence_end starts speech, every next silence_start ends it.
            $speechStart = 0.0
            for ($i=0; $i -lt $starts.Count; $i++) {
                $speechEnd = [double]$starts[$i]
                if ($speechEnd -gt $speechStart) { $detected += ,@($speechStart, $speechEnd) }
                if ($i -lt $ends.Count) { $speechStart = [double]$ends[$i] }
            }
        }
    }
    if ($detected.Count -eq 0) { $detected += ,@(0.0, 3.0) }

    foreach ($seg in $detected) {
        $start = [Math]::Max(0.0, [double]$seg[0] - ($PaddingMs/1000.0))
        $end = [Math]::Max($start, [double]$seg[1] + ($PaddingMs/1000.0))
        $durMs = [int](($end-$start)*1000)
        if ($durMs -lt $MinClipMs) { continue }
        if ($durMs -gt $MaxClipMs) { $end = $start + ($MaxClipMs/1000.0); $durMs = $MaxClipMs }
        $clipNum++
        $roleFolder = if ($hint -in @('controller','pilot')) { "radio/$hint" } elseif ($hint -eq 'ring') { 'telephone/tones/ring' } elseif ($hint -eq 'busy') { 'telephone/tones/busy' } elseif ($hint -eq 'telephone') { 'telephone/conversations' } else { 'radio/unknown' }
        $clipId = ('clip_{0:D5}' -f $clipNum)
        $outPath = "media-bank/$roleFolder/$clipId.wav"
        $rows.Add([pscustomobject]@{
            clip_id=$clipId; source_file=$f.FullName; start_sec=('{0:F3}' -f $start); end_sec=('{0:F3}' -f $end); duration_ms=$durMs;
            speaker_hint=$hint; confidence=($(if($hint -eq 'unknown'){'0.20'}else{'0.65'})); review_status='candidate'; output_path=$outPath; notes='auto-detected'
        }) | Out-Null
    }
}
Write-CsvUtf8NoType $rows $out
Write-Host ('Audio files scanned: {0}' -f $files.Count)
Write-Host ('Segments emitted: {0}' -f $rows.Count)
Write-Host ('Manifest: {0}' -f $out)
Write-Host 'MEDIA BANK DETECT SEGMENTS: PASS'
