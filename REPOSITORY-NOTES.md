# Repository provenance

This clean source tree was imported from the verified, 27-entry
`HydroThunder-Fixes-1.1.0.zip`, SHA-256:

```text
1d55172a1e0ddd2323beb33aa0719fae9a0b4edc122fa0a5f1ef75449eb025c8
```

Every imported file was checked against the ZIP's internal hash manifest.
The five installer payload files, including both DLLs, remain byte-identical to
the release. ReShade's separate license remains included.

Repository-only changes:

- Added a short release-download note to the top of README.md.
- Added `.gitignore` and `.gitattributes` for private/generated data exclusions,
  Windows installer line endings, and binary DLL handling.
- Added CHANGELOG.md, CONTRIBUTING.md, RELEASE-NOTES-v1.1.0.md, and this note.
- Omitted the ZIP's root SHA256SUMS.txt because it describes the immutable release
  contents, not the repository after these documentation additions.

No game data, local runtime, private settings, scores, artwork, generated test
results, or diagnostic traces were imported. Existing scripts already use
parameters or portable example paths; no cabinet-specific path change was needed.
No Git remotes, workflows, or publication actions were created during preparation.

These statements describe the original 1.1.0 import. Version 1.2.0 intentionally
adds the maintainer-supplied bezel, its separate provenance notice, and installer
backup/restore support; the original DLL and shader payloads remain unchanged.

Install from an immutable release ZIP. Rebuild the helper with `source/build.cmd`.
For 1.2.0 and later, build the reviewed package with Python 3.9 or newer:

```text
python Tools/Build-Release.py
```

The builder reads `VERSION`, uses an explicit file allowlist, and creates a ZIP,
per-file manifest, and companion checksum under ignored `dist/`. It refuses to
overwrite an existing release output. Use `--output-dir` for another new output
directory. Fixed archive metadata makes repeated packaging of the same bytes
stable with the same Python/compression implementation; rebuilding the DLL still
depends on compiler and SDK versions. Git metadata, local test output, account
data, games and runtime folders are never collected by a directory-wide archive.
