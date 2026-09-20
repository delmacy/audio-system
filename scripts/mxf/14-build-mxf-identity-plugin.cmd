@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-MxfIdentityPlugin.ps1"
set rc=%ERRORLEVEL%
exit /b %rc%
