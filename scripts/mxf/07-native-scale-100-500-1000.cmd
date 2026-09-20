@echo off
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-NativeScale.ps1"
set RC=%ERRORLEVEL%
pause
exit /b %RC%
