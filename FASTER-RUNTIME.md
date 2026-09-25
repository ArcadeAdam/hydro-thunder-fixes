# Optional faster Hydro runtime — package 1.2.0

On the tested cabinet, this separate runtime reduced time to graphics from about
**267 seconds to 172 seconds**, a saving of about **95 seconds (36%)**. The user
confirmed that physical wheel force feedback still works. Loading is still slow,
and results will vary with the cabinet and its devices.

This is an optional addition to the bezel/save fixes. `INSTALL.cmd` does not build
or switch runtimes. The shared ZIP contains only this setup script and guide for
the runtime change: **no TeknoParrot/FFB/SDL binaries, account data, user profiles,
controls, game files, or saved scores are redistributed** by the runtime builder.
The separate bezel installer now includes its PNG; see `Licenses/Bezel-NOTICE.md`.

## Required local donors

You need your own complete, compatible TeknoParrot installations:

| Component | Source | Tested version |
| --- | --- | --- |
| TeknoParrot UI and matching libraries | Older installation | 1.0.0.2078 |
| x86 TeknoParrot core and matching dependencies | Older installation | 1.0.0.3742 |
| x86 OpenParrotLoader.exe | Current installation | Tested 173,056-byte build |
| FFBBlaster.dll | Current installation | 0.0.0.200 |
| FFB SDL2.dll / SDL3.dll | Current installation | 2.32.52.0 / 3.2.6.0 |
| Hydro user profile, controls, game path, and icon | Current installation | Your existing configuration |
| ParrotData.xml and other UI configuration | Older installation | Your own local settings/account |

The script checks the exact SHA-256 of the six tested UI/core/loader/FFB/SDL
binaries before creating a destination. The full hashes are visible in the
script. A different newer build is not silently substituted. If your donors do
not match, the script stops; the bezel/save fixes remain usable independently.
It does not download or obtain older proprietary files for you.

The old loader/FFB194 combination reached graphics in about 27 seconds but lacked
force feedback. That result was rejected. Keep the tested loader, FFB200, and
both SDL dependencies together.

## Build a private copy

Close Hydro Thunder and TeknoParrot before creating the runtime. Choose a new
destination outside both donor folders; its parent directory must already exist.
Expect roughly 525 MiB for the tested installation.

From PowerShell in the extracted fix package, first validate your paths:

```powershell
.\Setup-FasterRuntime.ps1 `
  -OlderRuntimePath "C:\Emulators\TeknoParrot-2078" `
  -CurrentRuntimePath "C:\Emulators\TeknoParrot" `
  -DestinationPath "C:\Emulators\TeknoParrot-Hydro" `
  -CheckOnly
```

`-CheckOnly` hashes and validates the local donors without writing anything.
`-WhatIf` is also supported. To create the copy, run the same command without
`-CheckOnly`. An existing destination is always rejected.

The script copies the older UI/core dependencies, replaces the loader selection
with the tested current loader, copies the current FFB/SDL files, and takes only
Hydro's user profile and icon from your current installation. Browser caches,
debug logs, PDB files, unrelated emulator folders, and the three x64 TeknoParrot
DLLs are excluded. No game directory or score file is copied or changed.

Only the copied `ParrotData.xml` gets `CheckForUpdates=false`, so an automatic
update does not silently change this tested combination. Every other setting is
preserved. The copied account configuration comes from your older donor; sign in
normally with your own account if required. Do not share the resulting runtime
folder: it contains your private local account/profile data. The generated
`FasterRuntime-manifest.json` records paths, versions, sizes, and hashes without
recording configuration values.

## Test before assigning it to a frontend

Launch the copied `TeknoParrotUi.exe`, select Hydro Thunder, and confirm its game
path, controls, and force-feedback settings are still your intended values.
Launch Hydro and confirm wheel forces during gameplay, the sharp bezel, and
retained scores. Also test a new qualifying score and restart.

For a direct launch, the tested argument form is:

```text
--profile="C:\Emulators\TeknoParrot-Hydro\UserProfiles\HydroThunder.xml"
```

If you have already installed the bezel/save fixes, the copied current profile
retains its bezel setting and the same game folder retains the helper. If you
are installing the fixes afterward, supply the new dedicated runtime directory
when `INSTALL.cmd` asks for the TeknoParrot folder. The game-folder save backend
is independent of which compatible TeknoParrot runtime launches the game.

## Assign only Hydro in LaunchBox

Back up LaunchBox's configuration before editing. Create a **separate emulator
entry**, for example `TeknoParrot - Hydro`, pointing to the new runtime's
`TeknoParrotUi.exe`. Keep the original shared TeknoParrot entry and platform
defaults unchanged; do not make the new entry the platform's default emulator.
Preserve your existing startup, pause, and other frontend options.

Assign only the Hydro Thunder game to the new emulator entry. A compatible
profile-path arrangement uses these values:

| Setting | Value |
| --- | --- |
| New emulator executable | Full path to the dedicated `TeknoParrotUi.exe` |
| Default emulator command line | `--profile=` |
| Space before appended file path | Disabled (`NoSpace=true`) |
| Quote the file path | Enabled (`NoQuotes=false`) |
| Strip path and extension from filename | Disabled (`FileNameWithoutExtensionAndPath=false`) |
| Hydro's application/ROM path | Full path to the dedicated `UserProfiles\HydroThunder.xml` |
| Hydro's extra command line | Empty |
| New emulator as platform default | Disabled |

This constructs the quoted `--profile="...\HydroThunder.xml"` argument above.
The field names in parentheses are LaunchBox's stored setting names; labels may
vary between UI versions. The direct command and stored configuration were
checked; the LaunchBox GUI itself was not separately exercised for this guide.
Do not add a second `--profile` argument or change every game's shared emulator.

## Revert

Close the dedicated runtime and assign only Hydro back to its previous emulator
and profile path, using your frontend backup if needed. Both donor installations
remain unchanged. The generated `RESTORE-README.txt` gives the same local rollback
information and identifies the manifest to consult before discarding the copy.

Reverting this runtime does not uninstall the bezel/save fixes. Their existing
uninstaller remains independent and continues to preserve `CMOS.bin` and
`HydroSave.last-good.bin`.
