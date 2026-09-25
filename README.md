# Hydro Thunder: bezel and high-score fixes — 1.1.0

**[Download the installer ZIP](https://github.com/ArcadeAdam/hydro-thunder-fixes/releases/download/v1.1.0/HydroThunder-Fixes-1.1.0.zip)**
| [Release page and checksum](https://github.com/ArcadeAdam/hydro-thunder-fixes/releases/tag/v1.1.0)

For installation, download `HydroThunder-Fixes-1.1.0.zip` and its matching
`.zip.sha256` file from the Releases page above. See
[RELEASE-NOTES-v1.1.0.md](RELEASE-NOTES-v1.1.0.md) for the verified checksum.
This source tree also includes build/test guidance in [CONTRIBUTING.md](CONTRIBUTING.md).

This pack is for the **1999 arcade Hydro Thunder, version 01.01b**, running through TeknoParrot with **ThunderGlide2x v1.10 D3D11**. It is an independent compatibility fix, not an official TeknoParrot release.

The main installer provides two changes:

- A sharp 1920×1080 bezel drawn by ReShade at the final output resolution. The persistent ReShade welcome/tutorial is disabled.
- A file-based CMOS backend that loads and saves the game's real scores, settings and audits in `CMOS.bin` beside the game executable.

Version 1.1.0 also includes an **optional faster-runtime setup script**. Using the recipient's own compatible TeknoParrot installations, it creates a separate Hydro runtime. The tested combination reduced startup from about 267 to 172 seconds with physical force feedback confirmed. See [FASTER-RUNTIME.md](FASTER-RUNTIME.md) for required versions, setup, and a Hydro-only LaunchBox assignment. No TeknoParrot runtime or private configuration is bundled.

## Before installing

- Close Hydro Thunder and TeknoParrot.
- Your game folder must already contain the supported `Glide2x.dll` and a **1920×1080 `bezel.png` with a transparent center**.
- This pack contains no game executable, game assets, bezel artwork, saved scores, accounts, controller bindings or cabinet network settings.
- A different existing `d3d11.dll` is not overwritten. The installer also rejects unknown Glide wrappers.

The supported original Glide SHA-256 is:

`006697e503e838fb14f913f845f16d9dde5d4f9d4e27347e3f821f81d0cd4674`

The game is 32-bit even when its filename contains `_x64`. The included DLLs are deliberately x86. Do not use this pack with the Windows retail port, console versions, Hydro Thunder Hurricane, or a different Glide backend.

## Install

Extract the ZIP into its own folder. Run `INSTALL.cmd` and enter:

1. The Hydro Thunder game folder containing `Glide2x.dll`.
2. The TeknoParrot folder containing `TeknoParrotUi.exe`.

Alternatively, from PowerShell:

```powershell
.\Install-HydroFixes.ps1 -GameDirectory "C:\Games\Hydro Thunder" -TeknoParrotDirectory "C:\Emulators\TeknoParrot"
```

Add `-CheckOnly` to validate without changing game files. To install just one component, add `-Components Save` or `-Components Bezel`. The saving-only component does not require the TeknoParrot folder.

The installer creates a timestamped backup folder and an installation manifest in the game folder, including backup copies of any existing CMOS and recovery files. It disables only the native bezel field in the HydroThunder profile, and installs the supplied ReShade preset. It does not change game executables, scores, controller bindings, force-feedback settings or network configuration. Existing matching ReShade configuration files are backed up before this preset replaces them.

Launch the game normally through TeknoParrot or your existing frontend. No alternate game launcher or background save watcher is required.

## Verify

- The bezel should look sharp at 1920×1080. **Ctrl+F10** toggles it; **Home** opens ReShade.
- ReShade may show its brief startup/loading status. The welcome message should no longer remain throughout gameplay.
- Existing initials should still appear after boot.
- Enter a new qualifying time, finish the initials screen, and let the game return to its normal screens. `CMOS.bin` should be updated before you exit.
- Restart and confirm the new initials remain.

`HydroSave.log` records whether the existing save was loaded, was absent, was recovered from a recognized TeknoParrot metadata change, or was unsafe to read. A missing `CMOS.bin` permits the game to create its defaults. An unreadable file or unrecognized corruption blocks this helper's writes for that launch; preserve the file and investigate it rather than deleting it.

`HydroSave.last-good.bin` is a validated recovery copy created during native saves. Keep it with `CMOS.bin` when backing up scores. The helper does not resurrect this recovery copy when `CMOS.bin` is deliberately removed. If no `HydroSave.log` appears after the game reaches attract mode, the helper may have rejected an unsupported executable or hook signature; do not assume saving is active.

The invalid-file safeguards apply to this helper's writes. TeknoParrot also performs its own boot-time file write, which is why the validated recovery copy and preinstall backup are retained.

## What changes

The bezel uses the official standard ReShade 6.8.0 DLL and a single standalone shader. It does not resize the game, change its field of view, or introduce additional pillarboxing. The existing artwork is copied without modifying its pixels. The preset expects a 1920×1080 output frame.

The save helper replaces two obsolete raw-disk CMOS calls in process memory. It verifies the executable name, x86 image/base and both 32-byte function signatures before installing either hook. Both loading and writing are required: a write-only replacement could overwrite an existing score file during startup.

The helper accepts the known 32,000-byte CMOS layout and validates its game checksum. TeknoParrot can change two player/network fields at boot without updating the checksum. Recovery is limited to that exact change: every other byte, including the stored checksum, must match a validated recovery copy. Other corruption is rejected. The same strict comparison against the game's valid live CMOS handles stale staging metadata during a native save.

Writes use same-folder temporary files, flush them, then replace the destination. The recovery copy is written first, followed by `CMOS.bin`; these are two atomic replacements, not one combined transaction. A valid primary remains authoritative on the next launch. The installer adds one import to the local Glide wrapper to load this helper. Existing renderer code and exports are preserved. The original wrapper is kept in the backup.

## Uninstall

Close Hydro Thunder and TeknoParrot, run `UNINSTALL.cmd`, and enter the game folder. Or:

```powershell
.\Uninstall-HydroFixes.ps1 -GameDirectory "C:\Games\Hydro Thunder"
```

The uninstaller restores previous files, removes files introduced by the installer, and restores only the profile's previous native-bezel setting. Later controller/profile changes are retained. ReShade configuration changed during play is preserved in the backup before restoration. Modified binaries or artwork are not blindly overwritten; if they changed after installation, the uninstaller stops and identifies the file for manual review.

**Uninstalling never restores or deletes `CMOS.bin` or `HydroSave.last-good.bin`.** Keep the timestamped backup folder until you are satisfied with the result.

## Source, tests and licenses

- `Source/`: save-helper source and build script; rebuild requires Visual C++ Build Tools with the x86 toolchain and Windows SDK.
- `Tools/PatchGlide.cs`: hash-pinned PE import patcher, compiled by PowerShell during installation.
- `Tests/`: synthetic file-backend tests and installation/rollback tests. No personal save data is included.
- `Licenses/`: ReShade's redistribution license. ReShade's source is at https://github.com/crosire/reshade/tree/v6.8.0 and official releases are at https://reshade.me/.

The new helper, shader, patcher and scripts are supplied with source for inspection and adaptation. Check `VALIDATION.md` for the tested configuration and remaining limits. The base bezel/save installation is unchanged from 1.0.0. Startup improvement requires the separate, optional runtime setup; it is not a universal loading-time guarantee.
