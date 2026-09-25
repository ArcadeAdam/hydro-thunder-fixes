#include "../source/HydroSaveCore.h"
#include <cstdio>
#include <cstring>
#include <cwchar>

// This executable is linked with the original game's 8192-byte stack reserve
// and commit. Keep its own fixture and path buffers off that stack as well.
int wmain(int argc, wchar_t** argv) {
    if (argc != 3) return 2;
    auto* path = static_cast<wchar_t*>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 65536));
    auto* original = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, hydro::kCMOSBytes));
    auto* reloaded = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, hydro::kCMOSBytes));
    if (!path || !original || !reloaded) return 2;
    if (swprintf_s(path, 32768, L"%s\\small-stack-%lu.bin", argv[1], GetCurrentProcessId()) < 0) return 2;
    DWORD* words = reinterpret_cast<DWORD*>(original);
    words[0] = 1; words[1] = 0xFEDCBA98; words[2] = 1; words[4] = 0x59;
    words[0x120 / 4] = 0x12345678;
    for (DWORD index = 0; index < hydro::kCMOSBytes / 4; ++index)
        if (index != 3) words[3] += words[index];
    hydro::Session session;
    if (hydro::ReadForSession(session, path, reloaded, hydro::kCMOSBytes) != hydro::Missing) return 1;
    if (!hydro::WriteForSession(session, path, original, hydro::kCMOSBytes)) return 1;
    if (hydro::ReadForSession(session, path, reloaded, hydro::kCMOSBytes) != hydro::Loaded) return 1;
    if (std::memcmp(original, reloaded, hydro::kCMOSBytes)) return 1;
    HMODULE dll = LoadLibraryW(argv[2]);
    if (!dll) return 1;
    using Getter = LONG (__cdecl*)();
    auto status = reinterpret_cast<Getter>(GetProcAddress(dll, "HydroSave_GetHookStatus"));
    if (!status || status() != hydro::UnsupportedHost) return 1;
    FreeLibrary(dll);
    HeapFree(GetProcessHeap(), 0, reloaded);
    HeapFree(GetProcessHeap(), 0, original);
    HeapFree(GetProcessHeap(), 0, path);
    std::puts("PASS: 8192-byte PE stack reserve/commit: DLL attach + missing read + atomic write + reload");
    return 0;
}
