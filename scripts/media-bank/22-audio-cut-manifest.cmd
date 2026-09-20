@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-AudioCutManifest.ps1" %*
exit /b %ERRORLEVEL%
