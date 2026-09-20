EDITING QUICK GUIDE
===================

1. For the local notebook PoC, edit:
   profiles\local-poc.ini

2. For an authorized external recorder, copy:
   profiles\external-recorder-template.ini
   to a new file such as:
   profiles\training-recorder.ini

3. Edit only the INI file in Notepad. The executable must not need recompilation.

4. External mode will eventually support:
   generator interfaces
   generator validate <profile>
   generator dry-run <profile>
   generator run <profile>

5. Exact device-specific ED-137/RTSP parameters are intentionally added only after they are known and validated.
