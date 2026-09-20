@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-Rc1IntegratedAcceptance.ps1" %*
exit /b %ERRORLEVEL%
