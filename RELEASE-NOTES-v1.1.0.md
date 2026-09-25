# Hydro Thunder Fixes 1.1.0

Sharp bezel rendering, persistent high scores, and an optional faster Hydro-only
runtime setup for the supported arcade version 01.01b.

- The bezel/save installer payloads are unchanged from 1.0.0.
- The new optional builder uses your own compatible runtime files; it downloads
  nothing and does not modify your donors, game/saves, or frontend configuration.
- The tested separate runtime reached graphics in 172–173 seconds versus about
  267 seconds previously, with physical force feedback confirmed. Performance
  varies; this is not an instant-loading or universal compatibility claim.

Download and extract **HydroThunder-Fixes-1.1.0.zip**. Follow `README.md` for the
bezel/save installer and `FASTER-RUNTIME.md` for the optional runtime builder.
Close the game and TeknoParrot before installation. Preserve your score backups.

Release assets:

- `HydroThunder-Fixes-1.1.0.zip` — 1,912,238 bytes.
- `HydroThunder-Fixes-1.1.0.zip.sha256` — companion SHA-256 file.

SHA-256 of the ZIP:

```text
1d55172a1e0ddd2323beb33aa0719fae9a0b4edc122fa0a5f1ef75449eb025c8
```

The archive contains no game files, bezel artwork, scores, account data, profiles,
or proprietary TeknoParrot/FFB runtime binaries. The included ReShade DLL has its
redistribution license. The original ZIP and its internal checksums are unchanged
by the repository's additional contribution and publication documentation.
