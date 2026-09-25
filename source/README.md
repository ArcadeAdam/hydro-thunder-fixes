# HydroSave 1.1 source

This x86 DLL replaces the native Hydro Thunder 1.01b CMOS disk backend with a
validated `CMOS.bin` backend. It is loaded through an added `HydroSave_Init`
import in the existing Glide2x.dll. The installer performs that import change;
no replacement game executable is distributed.

Both native entry points are guarded before either is patched:

- `wrs_WriteCMOSBlockToDisk(const void*, int)` at `0x0018E3B0`, cdecl, returns 1
  for success and 0 for failure.
- `wrs_ReadCMOSBlock(void*, int)` at `0x0018E5D0`, cdecl, returns void.

The checks require a recognized executable filename, x86 PE32, main image base
`0x00100000`, sufficient image bounds, and both exact 32-byte code signatures.
The five-byte jumps are installed synchronously during DLL attach. No thread,
CMOS write, file read, or log write is started from DllMain.
After the guards pass, the helper is pinned for the process lifetime so a
renderer unload cannot leave native jumps targeting an unloaded DLL.

The read hook is essential: the native driver loads CMOS and then flushes during
initialization. Installing only a write hook could save factory defaults before
the existing score file has been loaded.

CMOS files must be exactly 32,000 bytes, with DWORD header fields
`[0]=1, [1]=0xFEDCBA98, [2]=1, [4]=0x59`. DWORD `[3]` contains the modulo-2^32
sum of all other 7,999 DWORDs. Reads validate a heap snapshot before copying it
to the native staging buffer. A missing file permits initial defaults; an
existing unreadable or unrecognized invalid file blocks saves for the rest of
that launch and preserves that file. Writes are also refused until a safe
initial read. The narrowly verified metadata exception is described below.

Writes validate another snapshot, create a unique same-directory temporary
file, write and flush all 32,000 bytes, close it, and replace CMOS.bin with
`MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`. Failed replacement removes the
temporary file and retains the previous CMOS.bin. The executable directory
determines the path; the current working directory does not affect it.

## TeknoParrot metadata repair

TeknoParrot's startup writer can change the player ID and link flag at bytes
20..27 without updating the CMOS checksum. A startup followed by exit before
another native save can therefore leave a score-intact but invalid CMOS.bin.

Each validated native save first atomically writes `HydroSave.last-good.bin`
in the game directory, then atomically replaces `CMOS.bin`. If the sidecar
write fails, the primary is untouched. If only the primary replacement fails,
its previous valid version remains authoritative on the next launch. The two
file replacements are separate operations, not a single transaction.

A valid primary always wins. A missing primary is treated as an intentional
reset; the sidecar cannot resurrect it. An invalid primary is repairable only
when it has the exact required size, the sidecar is fully valid, and every byte
outside 20..27 matches the sidecar, including the stored checksum and all score
bytes. Both copies must have player ID 0..3 and link flag 0..1. In that one case,
the read snapshot retains the primary's metadata and recalculates its checksum.
The result is reported as `Recovered` (4); the read itself does not rewrite disk.
Any score, header, checksum, size, or other discrepancy still blocks writes.

A preventive native-write safeguard also handles an invalid staging buffer
only when the caller points to the guarded staging address `0x0055DCA0` and the
authoritative CMOS at `0x00555F80` is fully valid and identical outside 20..27,
again including the stored checksum and bounded metadata. The helper persists
that validated authoritative snapshot. It does not change live staging memory.
The live score-save test did not need this preventive path.

The game's PE reserves only 8 KiB of stack. Full-size paths are static and file
buffers are heap allocated. The generated assembly's largest explicit local
stack allocation in the production sources is 268 bytes (the diagnostic log).

`HydroSave.log` records the initial read, first write failure, and first native
metadata reconciliation per launch,
outside DLL attach. Numeric fields in this log are hexadecimal. No score data
or initials are logged. The DLL has only a KERNEL32.dll runtime dependency.

## Rebuild and test

Install Visual Studio Build Tools with the x86 C++ tools. From a command prompt:

```bat
Source\build.cmd
```

If automatic tool discovery is unavailable, pass the full `vcvarsall.bat` path
as the first argument. The build uses x86, a static C runtime, warnings as
errors, CFG, ASLR, and NX. It creates `Build`, writes the distributable DLL to
`Payload\HydroSave.dll`, then runs both test executables. Generated test data
is synthetic and stored under `Tests\results`; no cabinet save is included.

The unit tests validate storage and guards. They do not replace a native game
restart test: the game's own reconstruction of table blocks and loader order
must also be verified on the supported game/loader version.

## Diagnostic exports

- `HydroSave_Init`: empty import anchor.
- `HydroSave_GetVersion`: `0x00010001`.
- `HydroSave_GetHookStatus`: 0 not attempted, 1 installed, 2 unsupported host,
  3 unsupported image, 4 signature mismatch, 5 patch failure.
- `HydroSave_GetStorageStatus`: 0 initial read not observed, 1 writes allowed,
  2 writes blocked for this launch.
- `HydroSave_GetLastSaveError`: latest Win32 storage error.
- `HydroSave_GetSuccessfulWrites`: number of successful saves this launch.
