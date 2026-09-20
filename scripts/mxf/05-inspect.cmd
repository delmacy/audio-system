@echo off
setlocal
if "%~1"=="" (
  echo Usage: 05-inspect.cmd ^<path-to-mxf^>
  exit /b 2
)
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Inspect-Mxf.ps1" -Path "%~1"
exit /b %ERRORLEVEL%
