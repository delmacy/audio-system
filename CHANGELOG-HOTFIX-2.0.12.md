# 2.0.12 — Active MXF file lifecycle / lock gate

Adds the file-integrity subgate requested before crash/recovery:

- active file naming: `.mxf.partial`;
- durable sidecar state: `.mxf.lock`;
- Windows delete/rename guard using `CreateFileW` without `FILE_SHARE_DELETE`;
- lock heartbeat with recorder/writer PIDs;
- normal lifecycle test: RECORDING_LOCKED -> FINALIZING -> CLOSED_COMPLETE;
- crash test leaving a stale `.lock` + `.partial`;
- next-boot stale-lock detection;
- conservative recovery assessment that never upgrades an incomplete file to CLOSED_COMPLETE without proof.

New commands:

- `10-file-lock-lifecycle.cmd`
- `11-stale-lock-crash.cmd`
- `12-recover-stale-lock.cmd`
