@echo off
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-NativeMxfLab.ps1"
set RC=%ERRORLEVEL%
pause
exit /b %RC%
