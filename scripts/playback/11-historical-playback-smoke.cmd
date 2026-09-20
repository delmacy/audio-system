@echo off
setlocal
cd /d "%~dp0\..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\playback\Invoke-HistoricalPlaybackPlan.ps1 -Mode continuous
if errorlevel 1 exit /b %errorlevel%
echo HISTORICAL PLAYBACK API: PASS
