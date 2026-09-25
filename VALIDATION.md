# Validation status

Release 1.2.0 bundles the exact bezel image from the verified cabinet and adds automatic artwork installation with backup/restoration. The ReShade/save-helper/shader payloads and optional 1.1.0 faster-runtime builder remain unchanged. Bezel appearance, welcome-banner dismissal, native score writing and score retention after restarting were verified on the tested cabinet.

## Release 1.2.0 installer validation

- 44 isolated installer checks passed, covering fresh folders without a bezel,
  automatic bundled-image installation, both existing image backups/restoration,
  custom `-BezelPath`, non-writing preflight, malformed or incorrectly sized PNG
  rejection before writes, save-only behavior, and changed-artwork uninstall
  refusal. Existing score/recovery sentinels and later controller edits survived.
- The bundled image is byte-identical to the original and live ReShade texture:
  SHA-256 `13ea7dd654e4065362c255b04d8733edda797dfbec826308690d87782f02ff7a`.
  It is 1920 x 1080 RGBA with a transparent gameplay area; no pixels were changed.
- PNG validation covers chunk structure/CRCs, dimensions, decompressed scanline
  bounds/filter bytes and zlib checksum using the existing Windows frameworks.
- Tests exercised real filesystem writes/restoration in isolated fixtures. Only
  the running-process preflight was mocked; no live game or profile was changed.
- This release changes installation of already verified artwork, not rendering
  code or native score hooks. No new live gameplay run was needed for the copy.

## Earlier gameplay and runtime validation

Live configuration: original arcade Hydro Thunder 01.01b (`HYDRO_x64_LAN.exe`, x86), ThunderGlide2x v1.10 D3D11, TeknoParrot UI 1.0.0.2156 / core 1.0.0.3755, ReShade 6.8.0, and a 1920x1080 output frame. Other executable names must pass the same runtime code guards; they were not separately play-tested.

- Original Hydro Thunder 01.01b x86 code and CMOS format inspected.
- Observed a real score in valid runtime CMOS and staging buffers while the disk file remained unchanged, including after exit.
- Original 1920×1080 bezel image verified intact; the user confirmed the ReShade result looked perfect.
- ReShade log confirmed a 1920×1080 D3D11 output frame and successful shader compilation in 0.008 seconds.
- Persistent tutorial disabled with the source-verified `OVERLAY/TutorialProgress=4` setting; the user confirmed that only the brief startup banner appears and then disappears.
- HydroSave 1.1 passed 27 storage/guard/recovery tests and the 8 KiB stack smoke test. Cases cover validation, overwrite, failure preservation, startup loading, exact metadata recovery, stale/invalid recovery copies, intentional resets and unrelated corruption refusal.
- 20 installer/rollback checks passed, including unchanged saves, preinstall score/recovery backups, preserved controller edits, normal ReShade configuration rewrites, unsupported wrappers and duplicate installs.
- Independent review verified both hook signatures and calling conventions, checksum, startup read/write ordering, and PE import addition.
- The PE patch preserves original renderer code, exports and import thunks; changes are confined to headers plus one appended 512-byte section.

The first live launch loaded the helper successfully and retained the existing score in the active game table. A new qualifying time was then written automatically to disk before exit. Disk, authoritative CMOS and staging buffers were byte-for-byte identical, the checksum was valid, and the native dirty flag cleared. Both the existing and new scores remained on disk after closing. No manual score-file restoration was used for this test.

The same launch exposed a further TeknoParrot behavior before gameplay: the loader changed a network metadata DWORD without updating the checksum. HydroSave 1.1 recovers only this exact, independently verified metadata change against a validated copy. Normal native score writing repaired that checksum during the initial test; the recovery path also covers a launch followed by exit without setting a score.

The enhanced helper passed independent source and assembly review. Its SHA-256 is `B6F8EAD4DABF340565DEF6C826250B84DEFFA1AC675CAA54BE1119ECADF19DC0`.

The final 1.1 helper loaded the saved data on restart. Both qualifying scores were present in the active game table, staging held the exact valid saved bytes, and the helper created its valid recovery copy. TP again changed only the network metadata DWORD in the primary file; comparison with the recovery copy confirmed that it exactly meets the narrowly permitted repair condition.

Test scope: the original helper performed the observed new-score write; the final 1.1 helper performed the observed restart/load and native startup write. Recovery after a boot-only exit and preventive stale-staging handling are covered by the storage tests, rather than a further gameplay cycle. No personal score data is included in this release.

The base bezel/save installer does not change startup performance. Measurements located the delay in FFBBlaster and TeknoParrot core initialization before graphics. A temporary performance-core affinity test did not materially reduce it and was reverted automatically.

The optional 1.1.0 runtime recipe uses UI 1.0.0.2078 and core 1.0.0.3742 with the tested current 173,056-byte x86 OpenParrotLoader, FFBBlaster 0.0.0.200, SDL2 2.32.52.0, and SDL3 3.2.6.0. It reached graphics in 172.3 seconds versus 266.7 seconds for the measured current-runtime baseline. The user confirmed physical wheel force feedback works. The 27-second old-loader/FFB194 test lacked feedback and was rejected. Results vary by cabinet, and the FFB initialization delay remains.

A second launch from the permanent dedicated runtime reached graphics in 172.8 seconds. Its phase observations closely matched the earlier test: FFBBlaster appeared at 4.0 seconds, the core at 153.8 seconds, both SDL modules at 160.8 seconds, and graphics at 172.8 seconds. This also verified the explicit profile-path launch used by the separate frontend configuration.

`Setup-FasterRuntime.ps1` passed PowerShell parsing and a read-only `-CheckOnly` run against the actual compatible donors: 231 files, 525.36 MiB, all six required binary hashes matched, and no destination was created. Independent review found no donor, game/save, or frontend write path. Only the newly copied account XML's update-check setting changes during an actual setup. The script rejects an existing destination and mismatched component builds before writing. The shared archive includes the builder and guide, not donor binaries, local profiles, account data, saves, or artwork.

A complete setup was then exercised in a fresh private diagnostics directory, outside the shared package and live runtime. All 231 destination hashes matched the generated manifest, all donor hashes remained unchanged, copied CheckForUpdates was false, and ParrotData.xml was the sole intentional content difference. Only the process-presence check was mocked for this isolated copy test because the separate live runtime was open; real copying, XML editing, and hash verification ran normally. The private output is not included in the archive.
