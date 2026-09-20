@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%\..\..") do set "ROOT=%%~fI"
set "PROFILE=%ROOT%\config\profiles\local-poc.ini"

echo Recorder PoC - Phase 1 network setup
echo Project root: %ROOT%
echo Profile: %PROFILE%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Setup-PocNetwork.ps1" -Profile "%PROFILE%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo Setup failed with exit code %RC%.
  echo If the message says the terminal is not elevated, reopen PowerShell with "Run as administrator".
)
pause
exit /b %RC%
