@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-PreencodedLoadMatrix.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" echo PREENCODED LOAD MATRIX returned exit code %EXITCODE%.
pause
exit /b %EXITCODE%
