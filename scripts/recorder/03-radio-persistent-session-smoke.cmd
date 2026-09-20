@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-RadioPersistentSessionSmoke.ps1"
exit /b %ERRORLEVEL%
