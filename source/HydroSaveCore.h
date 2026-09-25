#pragma once
#include <windows.h>
#include <cstddef>
#include <cstdlib>

namespace hydro {
constexpr DWORD kCMOSBytes = 32000;
constexpr DWORD kMainBase = 0x00100000;
constexpr DWORD kWriteAddress = 0x0018E3B0;
constexpr DWORD kReadAddress = 0x0018E5D0;
constexpr DWORD kNativeStaging = 0x0055DCA0;
constexpr DWORD kAuthoritativeCMOS = 0x00555F80;
constexpr size_t kSignatureBytes = 32;
extern const BYTE kWriteSignature[kSignatureBytes];
extern const BYTE kReadSignature[kSignatureBytes];

enum HookStatus : LONG {
    NotAttempted = 0,
    Installed = 1,
    UnsupportedHost = 2,
    UnsupportedImage = 3,
    SignatureMismatch = 4,
    PatchFailed = 5
};

// These checks intentionally reject every unrecognized executable/build.
bool IsSupportedHostName(const wchar_t* leafName);
bool IsSupportedImage(DWORD actualBase, WORD machine, WORD optionalMagic,
                      DWORD preferredBase, DWORD imageBytes);
bool IsSupportedSignature(const BYTE* signature, size_t bytes, const BYTE* expected);
bool ValidateCMOS(const void* data, DWORD bytes);

// Atomically replaces exactly one CMOS.bin. Existing data survives failures.
// absolutePath must name a fully qualified destination on a local filesystem.
bool PersistCMOS(const wchar_t* absolutePath, const void* data, DWORD bytes,
                 DWORD* errorOut = nullptr);

enum ReadResult : LONG { Missing = 1, Loaded = 2, Unsafe = 3, Recovered = 4 };
enum SessionState : LONG { NotRead = 0, WriteAllowed = 1, WriteBlocked = 2 };
struct Session { volatile LONG state = NotRead; };
// Zeroes destination before reading; invalid or unreadable files latch WriteBlocked.
ReadResult ReadForSession(Session& session, const wchar_t* absolutePath, void* destination,
                          DWORD bytes, DWORD* errorOut = nullptr);
bool WriteForSession(Session& session, const wchar_t* absolutePath, const void* data,
                     DWORD bytes, DWORD* errorOut = nullptr,
                     const void* authoritativeCMOS = nullptr, bool* reconciledOut = nullptr);
}
