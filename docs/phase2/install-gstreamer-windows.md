# GStreamer prerequisite on Windows

Use the official 64-bit **MSVC** build of GStreamer.

For tests 00–03, the Runtime package is sufficient if it contains the required plugins.
For tests 06–08, also install the Development package and Visual Studio 2022 Build Tools (Desktop development with C++).

The scripts search PATH, `GSTREAMER_ROOT_X86_64`, a standard system-wide installation, and the current GStreamer user-only installation path.

Required elements:

- mxfmux
- mxfdemux
- alawenc
- alawdec
- audiotestsrc
- queue
- filesink
- fakesink

Run `scripts\mxf\00-inventory.cmd` before changing anything else.
