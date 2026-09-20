@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-OperatorRunbookSmoke.ps1" %*
exit /b %ERRORLEVEL%
