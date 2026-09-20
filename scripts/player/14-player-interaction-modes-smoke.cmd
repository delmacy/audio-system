@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-PlayerInteractionModesSmoke.ps1" %*
exit /b %ERRORLEVEL%
