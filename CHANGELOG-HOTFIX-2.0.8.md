# Hotfix 2.0.8

- Replaced direct PowerShell native-process redirection in the scale runner with `System.Diagnostics.Process` capture.
- Prevents PowerShell 5.1 + `ErrorActionPreference=Stop` from converting benign/native stderr into terminating `NativeCommandError`.
- Captures and logs stdout, stderr and exit code separately for self-test, writer and inspector.
- Adds independent `ffprobe` audio-stream count to each 100/500/1000-track gate.
- Keeps the writer unchanged: the previous 100-track native write already completed successfully.
