# Hotfix 2.0.6

- Removed `LanguageStandard=stdc17` from `mxf-lab.vcxproj`.
- The native harness does not require C17; it now uses the default C language mode supplied by the selected MSVC toolset.
- This restores compatibility with Visual Studio 2019 Build Tools / PlatformToolset v142 without requiring Visual Studio 2022.
