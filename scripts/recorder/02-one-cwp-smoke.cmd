@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-OneCwpRecorderSmoke.ps1"
exit /b %ERRORLEVEL%
