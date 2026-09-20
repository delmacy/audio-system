@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-AudioDetectSegments.ps1" %*
exit /b %ERRORLEVEL%
