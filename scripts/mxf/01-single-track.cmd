@echo off
setlocal
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-GstMxf.ps1" -Tracks 1 -Seconds 10 -KeepPipelineText
set RC=%ERRORLEVEL%
pause
exit /b %RC%
