@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-WindowRotationSmoke.ps1" %*
exit /b %ERRORLEVEL%
