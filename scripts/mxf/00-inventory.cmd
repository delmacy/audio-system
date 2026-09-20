@echo off
setlocal
set SCRIPT_DIR=%~dp0
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Get-MxfInventory.ps1"
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" echo Inventory returned exit code %RC%.
pause
exit /b %RC%
