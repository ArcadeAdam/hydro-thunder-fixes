#include "HydroSaveCore.h"
#include <cstring>
#include <cwchar>

#if !defined(_M_IX86)
#error HydroSave must be compiled for x86.
#endif

static volatile LONG gHookStatus = hydro::NotAttempted;
static volatile LONG gLastSaveError = ERROR_SUCCESS;
static volatile LONG gSuccessfulWrites = 0;
static hydro::Session gSession;
static volatile LONG gReadLogged = 0;
static volatile LONG gWriteFailureLogged = 0;
static volatile LONG gReconcileLogged = 0;
// The original Hydro executable reserves only 8 KiB of stack. Keep all full-size
// paths in static storage and all CMOS snapshots / temporary paths on the heap.
static wchar_t gHostPath[32768];
static wchar_t gSavePath[32768];
static wchar_t gLogPath[32768];

static bool PrepareStoragePaths() {
    const wchar_t* leaf = std::wcsrchr(gHostPath, L'\\');
    if (!leaf) return false;
    const size_t prefixLength = static_cast<size_t>(leaf - gHostPath + 1);
    if (prefixLength + 13 >= _countof(gSavePath)) return false;
    std::memcpy(gSavePath, gHostPath, prefixLength * sizeof(wchar_t));
    std::memcpy(gLogPath, gHostPath, prefixLength * sizeof(wchar_t));
    std::memcpy(gSavePath + prefixLength, L"CMOS.bin", 9 * sizeof(wchar_t));
    std::memcpy(gLogPath + prefixLength, L"HydroSave.log", 14 * sizeof(wchar_t));
    return true;
}

static char* AppendHex(char* output, DWORD value) {
    static const char digits[] = "0123456789ABCDEF";
    for (int shift = 28; shift >= 0; shift -= 4) *output++ = digits[(value >> shift) & 15];
    return output;
}

static void LogStorageOnce(volatile LONG& flag, const char* event, DWORD detail, DWORD error) {
    if (InterlockedCompareExchange(&flag, 1, 0) != 0) return;
    if (!gLogPath[0]) return;
    char line[256] = "HydroSave 1.1 pid=0x";
    char* cursor = AppendHex(line + std::strlen(line), GetCurrentProcessId());
    *cursor++ = ' ';
    const size_t eventBytes = std::strlen(event);
    if (eventBytes > 128) return;
    std::memcpy(cursor, event, eventBytes); cursor += eventBytes;
    std::memcpy(cursor, " detail=0x", 10); cursor += 10;
    cursor = AppendHex(cursor, detail);
    std::memcpy(cursor, " win32_error=0x", 15); cursor += 15;
    cursor = AppendHex(cursor, error);
    *cursor++ = '\r'; *cursor++ = '\n';
    const DWORD length = static_cast<DWORD>(cursor - line);
    HANDLE log = CreateFileW(gLogPath, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (log == INVALID_HANDLE_VALUE) return;
    DWORD written;
    WriteFile(log, line, length, &written, nullptr);
    CloseHandle(log);
}

// Replaces wrs_WriteCMOSBlockToDisk(const void*, int), whose ABI is cdecl.
// Callers receive the same 1=success / 0=failure convention as the original.
extern "C" int __cdecl HydroSave_WriteCMOS(const void* data, int bytes) {
    if (bytes != static_cast<int>(hydro::kCMOSBytes)) {
        InterlockedExchange(&gLastSaveError, ERROR_INVALID_PARAMETER);
        return 0;
    }
    if (!gSavePath[0]) {
        InterlockedExchange(&gLastSaveError, ERROR_BAD_PATHNAME);
        return 0;
    }
    DWORD error = ERROR_SUCCESS;
    // TP can change player/link metadata without syncing the native staging copy.
    // Consult the authoritative buffer only for the exact guarded native source.
    const void* authoritative = reinterpret_cast<DWORD>(data) == hydro::kNativeStaging ?
                                    reinterpret_cast<const void*>(hydro::kAuthoritativeCMOS) : nullptr;
    bool reconciled = false;
    const bool success = hydro::WriteForSession(gSession, gSavePath, data, static_cast<DWORD>(bytes),
                                                &error, authoritative, &reconciled);
    InterlockedExchange(&gLastSaveError, static_cast<LONG>(error));
    if (success) InterlockedIncrement(&gSuccessfulWrites);
    else LogStorageOnce(gWriteFailureLogged, "write refused/failed; previous save retained", 0, error);
    if (reconciled) LogStorageOnce(gReconcileLogged, "native metadata reconciled from validated authoritative CMOS", 1, error);
    return success ? 1 : 0;
}

// Replaces wrs_ReadCMOSBlock(void*, int), also cdecl. Driver initialization
// must load existing scores before the game's unconditional startup flush.
extern "C" void __cdecl HydroSave_ReadCMOS(void* destination, int bytes) {
    if (bytes != static_cast<int>(hydro::kCMOSBytes) || !gSavePath[0]) {
        InterlockedExchange(&gSession.state, hydro::WriteBlocked);
        InterlockedExchange(&gLastSaveError, ERROR_INVALID_PARAMETER);
        return;
    }
    DWORD error = ERROR_SUCCESS;
    const auto result = hydro::ReadForSession(gSession, gSavePath, destination, static_cast<DWORD>(bytes), &error);
    InterlockedExchange(&gLastSaveError, static_cast<LONG>(error));
    LogStorageOnce(gReadLogged, result == hydro::Unsafe ? "read unsafe; writes BLOCKED for this launch" :
                       "read ready (1=missing, 2=loaded, 4=metadata recovered)", static_cast<DWORD>(result), error);
}

static void MakeJump(BYTE* jump, DWORD targetAddress, DWORD replacementAddress) {
    jump[0] = 0xE9;
    const DWORD displacement = replacementAddress - (targetAddress + 5);
    std::memcpy(jump + 1, &displacement, sizeof(displacement));
}

static hydro::HookStatus InstallHook() {
    const DWORD copied = GetModuleFileNameW(nullptr, gHostPath, _countof(gHostPath));
    if (!copied || copied >= _countof(gHostPath)) return hydro::UnsupportedHost;
    const wchar_t* leaf = std::wcsrchr(gHostPath, L'\\');
    if (!leaf || !hydro::IsSupportedHostName(leaf + 1)) return hydro::UnsupportedHost;
    if (!PrepareStoragePaths()) return hydro::UnsupportedHost;

    BYTE* base = reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
    __try {
        const IMAGE_DOS_HEADER* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if (!base || reinterpret_cast<DWORD>(base) != hydro::kMainBase ||
            dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < static_cast<LONG>(sizeof(IMAGE_DOS_HEADER)) ||
            dos->e_lfanew > 0x100000) return hydro::UnsupportedImage;
        const IMAGE_NT_HEADERS32* nt = reinterpret_cast<const IMAGE_NT_HEADERS32*>(base + dos->e_lfanew);
        if (nt->Signature != IMAGE_NT_SIGNATURE ||
            !hydro::IsSupportedImage(reinterpret_cast<DWORD>(base), nt->FileHeader.Machine,
                                     nt->OptionalHeader.Magic, nt->OptionalHeader.ImageBase,
                                     nt->OptionalHeader.SizeOfImage)) return hydro::UnsupportedImage;
        BYTE* writeTarget = reinterpret_cast<BYTE*>(hydro::kWriteAddress);
        BYTE* readTarget = reinterpret_cast<BYTE*>(hydro::kReadAddress);
        if (!hydro::IsSupportedSignature(writeTarget, hydro::kSignatureBytes, hydro::kWriteSignature) ||
            !hydro::IsSupportedSignature(readTarget, hydro::kSignatureBytes, hydro::kReadSignature))
            return hydro::SignatureMismatch;
        // The installed jumps must remain valid even if the renderer unloads.
        // Pin only after all host/build guards have succeeded.
        HMODULE pinnedModule = nullptr;
        if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                                reinterpret_cast<LPCWSTR>(&HydroSave_WriteCMOS), &pinnedModule))
            return hydro::PatchFailed;
        BYTE writeJump[5], readJump[5];
        MakeJump(writeJump, hydro::kWriteAddress, reinterpret_cast<DWORD>(&HydroSave_WriteCMOS));
        MakeJump(readJump, hydro::kReadAddress, reinterpret_cast<DWORD>(&HydroSave_ReadCMOS));
        // Both sites occupy this single native code page; validate both first.
        BYTE* page = reinterpret_cast<BYTE*>(0x0018E000);
        const SIZE_T pageBytes = 0x1000;
        DWORD oldProtection = 0;
        if (!VirtualProtect(page, pageBytes, PAGE_EXECUTE_READWRITE, &oldProtection))
            return hydro::PatchFailed;
        std::memcpy(writeTarget, writeJump, sizeof(writeJump));
        std::memcpy(readTarget, readJump, sizeof(readJump));
        const BOOL flushed = FlushInstructionCache(GetCurrentProcess(), page, pageBytes);
        DWORD ignored = 0;
        if (!flushed || !VirtualProtect(page, pageBytes, oldProtection, &ignored)) {
            std::memcpy(writeTarget, hydro::kWriteSignature, sizeof(writeJump));
            std::memcpy(readTarget, hydro::kReadSignature, sizeof(readJump));
            FlushInstructionCache(GetCurrentProcess(), page, pageBytes);
            VirtualProtect(page, pageBytes, oldProtection, &ignored);
            return hydro::PatchFailed;
        }
        return hydro::Installed;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return hydro::UnsupportedImage;
    }
}

// The import causes Windows to load this DLL. It need not call this export.
extern "C" void __cdecl HydroSave_Init() {}
extern "C" DWORD __cdecl HydroSave_GetVersion() { return 0x00010001; }
extern "C" LONG __cdecl HydroSave_GetHookStatus() { return InterlockedCompareExchange(&gHookStatus, 0, 0); }
extern "C" DWORD __cdecl HydroSave_GetLastSaveError() {
    return static_cast<DWORD>(InterlockedCompareExchange(&gLastSaveError, 0, 0));
}
extern "C" LONG __cdecl HydroSave_GetSuccessfulWrites() {
    return InterlockedCompareExchange(&gSuccessfulWrites, 0, 0);
}
extern "C" LONG __cdecl HydroSave_GetStorageStatus() {
    return InterlockedCompareExchange(&gSession.state, 0, 0);
}

BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        // Synchronous: no worker thread, file I/O, log, or CMOS write under loader lock.
        // This import is installed in Glide2x.dll so initialization follows TP setup.
        InterlockedExchange(&gHookStatus, InstallHook());
    }
    return TRUE;
}
