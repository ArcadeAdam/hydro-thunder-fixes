# Changelog

## 1.1.0

- Added an optional, separate Hydro runtime builder using the recipient's own
  compatible TeknoParrot installations. No proprietary runtime is redistributed.
- The tested UI 2078/core 3742 plus current loader/FFB200 combination reduced
  startup from about 267 seconds to 172–173 seconds. Physical wheel feedback was
  confirmed working. The faster 27-second test lacked feedback and was rejected.
- Added donor hash checks, read-only preflight, verified local copying, private
  manifests, and guidance for assigning only Hydro to a separate frontend entry.
- Kept the bezel and HydroSave 1.1 installer payloads unchanged from pack 1.0.0.

## 1.0.0

- Added a sharp final-resolution ReShade bezel for the supported 1920×1080 setup
  and disabled the persistent welcome/tutorial message.
- Added guarded native CMOS loading and writing, atomic saves, validated recovery
  for the known TeknoParrot metadata change, and preservation of existing scores.
- Included source, synthetic storage tests, installer/rollback tests, backup and
  uninstall support, and third-party license notices.

Repository preparation after the 1.1.0 release adds documentation and Git metadata
only. See [REPOSITORY-NOTES.md](REPOSITORY-NOTES.md); the released ZIP is unchanged.
