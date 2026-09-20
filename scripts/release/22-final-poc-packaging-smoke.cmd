@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-FinalPocPackagingSmoke.ps1" %*
exit /b %ERRORLEVEL%
