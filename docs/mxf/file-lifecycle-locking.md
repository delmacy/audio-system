# MXF active-file lifecycle and locking

## Rule

An active recording is never exposed as a finalized `.mxf`.

While recording:

- `foo.mxf.partial` — physical MXF being written.
- `foo.mxf.lock` — operational state/heartbeat sidecar.
- Windows delete-denying guard handle — physical protection against delete/rename.

On normal close:

1. Stop accepting media for the file/partition.
2. Let the MXF writer finalize indexes/footer and close.
3. Move state to `FINALIZING`.
4. Compute file size/hash and final integrity metadata.
5. Release the delete-denying guard immediately before the controlled rename.
6. Rename `foo.mxf.partial` to `foo.mxf`.
7. Persist manifest state `CLOSED_COMPLETE`.
8. Remove `foo.mxf.lock`.

## Windows handle rule

The PoC guard opens the active `.partial` with desired access `0`, shares READ and WRITE, and deliberately omits `FILE_SHARE_DELETE`. This allows the MXF writer to keep writing while preventing subsequent opens that request delete access. On Windows, delete access also governs rename operations.

The `.lock` file is not the physical lock. It is durable operational evidence used for discovery and crash recovery.

## Crash path

A Recorder crash releases all OS handles automatically but leaves:

- `foo.mxf.partial`
- `foo.mxf.lock`

At next startup, if the lock's recorder/writer PIDs are no longer alive, it is classified as `STALE_LOCK`.

A stale partial must never be silently treated as silence and must never be renamed to a normal `.mxf` merely because it exists. It enters recovery assessment first.

## States

`ALLOCATED -> RECORDING_LOCKED -> FINALIZING -> CLOSED_COMPLETE`

Crash path:

`RECORDING_LOCKED -> STALE_LOCK -> RECOVERY_REQUIRED | RECOVERABLE_INCOMPLETE -> future recovery implementation`

The PoC recovery assessment intentionally does not claim `CLOSED_COMPLETE` for a crashed file unless a later explicit recovery algorithm proves/finalizes it.
