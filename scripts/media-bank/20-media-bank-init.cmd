@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Initialize-MediaBank.ps1" %*
exit /b %ERRORLEVEL%
