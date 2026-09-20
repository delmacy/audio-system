@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-LogicalTrackContinuity.ps1"
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" echo Logical track continuity gate failed with exit code %RC%.
pause
exit /b %RC%
