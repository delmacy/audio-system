@echo off
setlocal
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-NativePrereqs.ps1"
set RC=%ERRORLEVEL%
pause
exit /b %RC%
