@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-MediaEngineSmoke.ps1"
exit /b %ERRORLEVEL%
