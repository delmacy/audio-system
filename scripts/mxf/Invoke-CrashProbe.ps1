param([int]$Tracks=50,[int]$Seconds=60,[int]$CrashAfterMs=3000)
. (Join-Path $PSScriptRoot 'Common-Mxf.ps1')
$root=Get-ProjectRoot
$exe=@((Join-Path $root 'src\mxf-lab\x64\Release\mxf-lab.exe'),(Join-Path $root 'src\mxf-lab\Release\mxf-lab.exe'))|Where-Object{Test-Path $_}|Select-Object -First 1
if(-not $exe){throw 'mxf-lab.exe not built. Run 06-build-native.cmd first.'}
$runDir=Ensure-RunDirectory
$out=Join-Path $runDir ('crash-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.mxf')
Write-Host "Intentionally terminating writer after $CrashAfterMs ms. Exit 77 is EXPECTED."
& $exe write --tracks $Tracks --seconds $Seconds --out $out --crash-after-ms $CrashAfterMs
$writerRc=$LASTEXITCODE
Write-Host "Writer exit: $writerRc"
if(Test-Path $out){Write-Host "Partial bytes: $((Get-Item $out).Length)"}else{throw 'Crash probe produced no file.'}
Write-Host 'Attempting demux/reopen of incomplete file...'
& $exe inspect $out
$inspectRc=$LASTEXITCODE
$result=[ordered]@{file=$out;writer_exit=$writerRc;inspect_exit=$inspectRc;bytes=(Get-Item $out).Length;tracks=$Tracks;crash_after_ms=$CrashAfterMs}
$result|ConvertTo-Json|Set-Content -Encoding UTF8 ($out+'.crash.json')
Write-Host "Crash probe complete. inspect_exit=$inspectRc"
Write-Host 'NOTE: inspect failure is a finding, not automatically a failed spike. It tells us what recovery strategy the Recorder must implement.'
