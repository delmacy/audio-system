@echo off
setlocal
cd /d "%~dp0\..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\playback\Invoke-RealPlaybackSegmentExport.ps1 -Mode only_audio
if errorlevel 1 exit /b %errorlevel%
echo PLAYBACK SEGMENT EXPORT FROM CLOSED MXF: PASS
