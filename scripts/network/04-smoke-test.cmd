@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%\..\..") do set "ROOT=%%~fI"
set "PROFILE=%ROOT%\config\profiles\local-poc.ini"
set "OUT=%ROOT%\runs\network-smoke"

echo Recorder PoC - Phase 1 smoke test
echo Project root: %ROOT%
echo Profile: %PROFILE%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Invoke-Phase1Smoke.ps1" -Profile "%PROFILE%" -OutputDirectory "%OUT%"
set "RC=%ERRORLEVEL%"
exit /b %RC%
