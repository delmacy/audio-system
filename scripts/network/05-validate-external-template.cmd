@echo off
setlocal
cd /d "%~dp0\..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\network\Validate-NetworkProfile.ps1" -Profile ".\config\profiles\external-recorder-template.ini"
pause
