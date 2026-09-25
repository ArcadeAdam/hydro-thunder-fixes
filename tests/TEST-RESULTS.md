# HydroSave storage and guard verification

The x86 build succeeded with MSVC 14.51.36231, `/W4 /WX /O2 /MT`, and both test
executables completed successfully on the local Windows machine.

`HydroSaveTests.exe`: **27/27 passed**.

1. Valid checksum and required header fields.
2. File creation, complete reload, replacement, and paths with spaces.
3. Invalid checksum preserves the previous save.
4. Truncated, oversized, and null input buffers are rejected.
5. An actual Windows sharing violation during replacement preserves the prior
   save and removes the temporary file.
6. Unavailable destination directory reports failure.
7. Relative and drive-relative paths are rejected.
8. Startup reads the saved synthetic payload before the unconditional flush;
   a second session reloads the same bytes.
9. Missing save permits initial defaults and later updates.
10. Writes before the initial read are refused.
11. Corrupt existing save blocks writes throughout that launch.
12. Truncated existing save remains intact and blocks writes.
13. Unreadable existing save remains intact and blocks writes.
14. Host filename, image architecture/base/bounds, and every byte of both
    expected native signatures are checked.
15. The actual DLL loads into a foreign host, rejects it, and performs no save
    write or hook installation.

The additional metadata-recovery tests cover:

16. Exact TP metadata-only startup mutation recovery, retaining primary player
    and link settings, including the permitted endpoints (player 3 / link 1).
17. Rejection of any score-byte or stored-checksum corruption despite a valid sidecar.
18. Rejection of a stale sidecar whose payload does not exactly match.
19. Rejection of out-of-range primary player/link metadata.
20. Rejection of checksum-invalid, truncated, or unreadable recovery sidecars.
21. Missing primary honors reset and never resurrects a sidecar.
22. Valid primary wins even when the sidecar is newer or unreadable.
23. Invalid native staging can use only the validated, matching authoritative
    snapshot; original staging memory is unchanged.
24. Native reconciliation rejects score, checksum, or authoritative corruption.
25. Sidecar write failure leaves the primary untouched.
26. Native reconciliation rejects out-of-range metadata in either copy.
27. Failed primary replacement leaves the old valid primary authoritative over
    the newer sidecar on the next launch.

`SmallStackSmoke.exe`: **passed**. Its PE stack reserve and commit are both
8,192 bytes, matching the original Hydro executable. It exercises DLL attach,
missing-file read, atomic write, and complete validated reload.

Assembly inspection found no `__chkstk` calls in the production source output.
The largest explicit local stack allocation is 268 bytes. Large pathname and
CMOS buffers use static or heap storage.

All data in these tests is synthetic. No real cabinet score file or initials
are test fixtures. The tests do not constitute a native game restart test.
