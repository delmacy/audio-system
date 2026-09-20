@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-EmbeddedCrossFileContinuity.ps1"
set rc=%ERRORLEVEL%
exit /b %rc%
