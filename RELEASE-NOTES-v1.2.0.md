# Hydro Thunder Fixes 1.2.0 - bezel included

This release includes the actual **1920 x 1080 bezel PNG** and installs it
automatically with the existing sharp ReShade bezel and high-score fixes.

## Install

Download and extract **HydroThunder-Fixes-1.2.0.zip**, close Hydro Thunder and
TeknoParrot, and run **INSTALL.cmd**. Select the game and TeknoParrot folders.
You no longer need to find or copy a bezel image yourself.

The bezel is installed as `bezel.png` beside the game and in ReShade's texture
folder. Existing images are backed up; uninstall restores them. An optional
`-BezelPath` argument lets you use your own compatible image instead.

## Upgrade from an earlier pack

Close the game and TeknoParrot. Use the earlier pack's `UNINSTALL.cmd` first,
then run the new `INSTALL.cmd`. Uninstall preserves `CMOS.bin` and
`HydroSave.last-good.bin`. Keep your score backups. If you use the optional
dedicated faster runtime, select that TeknoParrot folder during installation.

The save-helper and ReShade binaries are unchanged. The optional faster-runtime
builder is still included and uses your own compatible TeknoParrot files.

The bundled bezel was created by **ArcadeAdam** and is included with the
author's permission. The artwork has a separate notice in
`Licenses/Bezel-NOTICE.md`; the project's MIT license does not cover it.
No game executable, account data, personal scores, controller profiles, or
proprietary TeknoParrot/FFB runtime is included.

Use the accompanying `.zip.sha256` file to verify the archive. The archive also
contains `SHA256SUMS.txt` for its individual files.
