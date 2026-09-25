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
`Glide2x.dll`. Pass its local path through `-OriginalGlide` and choose a new private
`-WorkDirectory`. The bundled bezel is available to the tests; the game wrapper
fixture is not included and must not be committed. The optional faster-runtime
builder likewise requires your own local donor installations; use `-CheckOnly`
first. Keep full runtime-copy tests outside this repository.

Synthetic tests cannot prove real cabinet rendering, wheel feedback, native score
entry, or restart retention. Report which live checks were performed and which
remain untested. Do not describe a build as fully reproducible merely because it
uses `/Brepro`: compiler/SDK versions also matter, and release archive timestamps
must be normalized separately for byte-for-byte ZIP reproduction.

## Reports and submissions

Be respectful of other users, maintainers, and upstream developers. Search
existing issues before filing a duplicate, keep one problem per report, and
describe observations without assigning blame. Credit prior work and keep
proposed changes focused. Contributions and support are voluntary; a donation
does not establish a support deadline.

Include the pack version, relevant game/wrapper/loader/core/FFB versions, display
resolution, symptoms, and minimal steps to reproduce. Share only sanitized logs.
Never submit account credentials, ParrotData.xml, personal profiles/controller
identifiers, scores, game or wrapper binaries, or artwork. Use synthetic fixtures
for new tests and preserve existing saves on every failure path.

Retain the scoped MIT notice, ReShade's separate license, and the artwork notice.
Only the explicitly included `payload/bezel.png` is tracked; do not add other
artwork without documenting its source and permission. ReShade is bundled
unmodified; do not imply its authors or TeknoParrot endorse this project. Existing
release assets stay immutable; subsequent code changes require a new release
and regenerated checksums.
