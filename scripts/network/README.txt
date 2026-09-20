PHASE 1 - WINDOWS NETWORK FOUNDATION

Recommended order:

01-inventory.cmd
02-install-loopback.cmd      (only if Microsoft KM-TEST Loopback Adapter is absent)
03-setup-lab.cmd             (run from Administrator terminal)
04-smoke-test.cmd

05-validate-external-template.cmd is expected to FAIL until CHANGE_ME values are replaced.
It does not send traffic.

PowerShell scripts:
- Get-NetworkInventory.ps1
- Install-PocLoopback.ps1
- Setup-PocNetwork.ps1
- Remove-PocNetwork.ps1
- Test-PocUdp.ps1
- Invoke-Phase1Smoke.ps1
- Validate-NetworkProfile.ps1

The local smoke test uses UDP ports 41001/41002 only. These are diagnostic probe ports, not SIP/RTP production ports.
