@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-WebPlayerShellSmoke.ps1" %*
exit /b %ERRORLEVEL%
