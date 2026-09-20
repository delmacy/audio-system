@echo off
setlocal
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-TrackIdentity.ps1"
set RC=%ERRORLEVEL%
pause
exit /b %RC%
