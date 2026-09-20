@echo off
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Recover-StaleMxf.ps1"
set RC=%ERRORLEVEL%
pause
exit /b %RC%
