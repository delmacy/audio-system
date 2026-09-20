@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-MultiCwpRoutingSmoke.ps1"
exit /b %ERRORLEVEL%
