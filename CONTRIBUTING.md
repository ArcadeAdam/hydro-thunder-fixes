# Contributing

Keep changes narrow and retain the exact build/signature guards. The supported
target is the original arcade Hydro Thunder 01.01b through the documented x86
ThunderGlide/TeknoParrot configuration. Unrecognized builds must fail safely.

## Build and tests

On Windows, install Visual Studio Build Tools with the x86 C++ toolchain and
Windows SDK, then run:

```bat
source\build.cmd
```

The script finds Visual Studio with `vswhere`; an explicit `vcvarsall.bat` path
can be its first argument. It builds HydroSave with a static runtime and runs
27 synthetic storage/guard/recovery tests plus the 8 KiB stack smoke test. It
writes local output to `build`, `tests/results`, and `payload/HydroSave.dll`.
Include the compiler/SDK versions and test result in change reports.

`tests/Test-Installer.ps1` additionally needs your own supported original
`Glide2x.dll` and bezel image. Pass their local paths through `-OriginalGlide` and
`-BezelPath`, and choose a new private `-WorkDirectory`. These fixtures are not
included in the repository and must not be committed. The optional faster-runtime
builder likewise requires your own local donor installations; use `-CheckOnly`
first. Keep full runtime-copy tests outside this repository.

Synthetic tests cannot prove real cabinet rendering, wheel feedback, native score
entry, or restart retention. Report which live checks were performed and which
remain untested. Do not describe a build as fully reproducible merely because it
uses `/Brepro`: compiler/SDK versions also matter, and release archive timestamps
must be normalized separately for byte-for-byte ZIP reproduction.

## Reports and submissions

Include the pack version, relevant game/wrapper/loader/core/FFB versions, display
resolution, symptoms, and minimal steps to reproduce. Share only sanitized logs.
Never submit account credentials, ParrotData.xml, personal profiles/controller
identifiers, scores, game or wrapper binaries, or artwork. Use synthetic fixtures
for new tests and preserve existing saves on every failure path.

Retain the scoped MIT notice and ReShade's separate license. ReShade is bundled
unmodified; do not imply its authors or TeknoParrot endorse this project. Existing
release assets stay immutable; subsequent code changes require a new release
and regenerated checksums.
