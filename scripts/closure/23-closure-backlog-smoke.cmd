@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-ClosureBacklogSmoke.ps1" %*
exit /b %ERRORLEVEL%
