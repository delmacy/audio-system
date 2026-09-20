@echo off
setlocal
cd /d "%~dp0\..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\network\Get-NetworkInventory.ps1" -OutputJson ".\runs\network-smoke\inventory.json"
pause
