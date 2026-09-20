@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-ServicePerspectiveMatrixSmoke.ps1" %*
exit /b %ERRORLEVEL%
