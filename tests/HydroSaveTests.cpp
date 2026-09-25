#include "../source/HydroSaveCore.h"
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <functional>
#include <stdexcept>
#include <string>
#include <vector>

#define REQUIRE(condition) do { if (!(condition)) { \
    std::printf("  FAIL line %d: %s\n", __LINE__, #condition); \
    throw std::runtime_error(#condition); } } while (false)

static std::vector<BYTE> Fixture(DWORD score) {
    std::vector<BYTE> data(hydro::kCMOSBytes, 0);
    DWORD* words = reinterpret_cast<DWORD*>(data.data());
    words[0] = 1; words[1] = 0xFEDCBA98; words[2] = 1; words[4] = 0x59;
    // Synthetic payload only: not the user's save or initials.
    words[0x120 / 4] = score;
    for (DWORD index = 0; index < hydro::kCMOSBytes / 4; ++index)
        if (index != 3) words[3] += words[index];
    return data;
}

static void SetWord(std::vector<BYTE>& data, size_t offset, DWORD value) {
    std::memcpy(data.data() + offset, &value, sizeof(value));
}

static void UpdateChecksum(std::vector<BYTE>& data) {
    DWORD sum = 0;
    for (size_t offset = 0; offset < data.size(); offset += 4) {
        if (offset == 12) continue;
        DWORD word; std::memcpy(&word, data.data() + offset, sizeof(word)); sum += word;
    }
    SetWord(data, 12, sum);
}

static std::wstring SidecarPath(const std::wstring& path) {
    return path.substr(0, path.find_last_of(L'\\') + 1) + L"HydroSave.last-good.bin";
}

static std::wstring CasePath(const std::wstring& root, const wchar_t* name) {
    const std::wstring directory = root + L"\\" + name;
    REQUIRE(CreateDirectoryW(directory.c_str(), nullptr) != FALSE);
    return directory + L"\\CMOS.bin";
}

static void RawWrite(const std::wstring& path, const std::vector<BYTE>& data) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
    REQUIRE(file != INVALID_HANDLE_VALUE);
    DWORD count = 0;
    const BOOL written = WriteFile(file, data.data(), static_cast<DWORD>(data.size()), &count, nullptr);
    const BOOL closed = CloseHandle(file);
    REQUIRE(written && closed && count == data.size());
}

static std::vector<BYTE> RawRead(const std::wstring& path) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    REQUIRE(file != INVALID_HANDLE_VALUE);
    LARGE_INTEGER size;
    REQUIRE(GetFileSizeEx(file, &size) && size.QuadPart >= 0 && size.QuadPart <= 100000);
    std::vector<BYTE> data(static_cast<size_t>(size.QuadPart));
    DWORD count = 0;
    const BOOL read = ReadFile(file, data.data(), static_cast<DWORD>(data.size()), &count, nullptr);
    const BOOL closed = CloseHandle(file);
    REQUIRE(read && closed && count == data.size());
    return data;
}

static bool NoTemporaryFiles(const std::wstring& path) {
    WIN32_FIND_DATAW item;
    HANDLE found = FindFirstFileW((path + L".HydroSave-*.tmp").c_str(), &item);
    if (found == INVALID_HANDLE_VALUE) return GetLastError() == ERROR_FILE_NOT_FOUND;
    FindClose(found);
    return false;
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 3) {
        std::puts("Usage: HydroSaveTests.exe absolute-test-output-directory absolute-HydroSave.dll");
        return 2;
    }
    std::wstring root = argv[1];
    if (!CreateDirectoryW(root.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return 2;
    wchar_t suffix[80];
    swprintf_s(suffix, L"\\Hydro Save Tests %lu %lu", GetCurrentProcessId(), GetTickCount());
    root += suffix;
    REQUIRE(CreateDirectoryW(root.c_str(), nullptr) != FALSE);
    const auto initial = Fixture(12345);
    const auto updated = Fixture(67890);
    std::vector<std::pair<const char*, std::function<void()>>> cases;

    cases.emplace_back("valid fixture checksum and headers", [&] {
        REQUIRE(hydro::ValidateCMOS(initial.data(), static_cast<DWORD>(initial.size())));
        for (DWORD header : {0u, 4u, 8u, 16u}) {
            auto broken = initial; broken[header] ^= 1;
            REQUIRE(!hydro::ValidateCMOS(broken.data(), static_cast<DWORD>(broken.size())));
        }
    });
    cases.emplace_back("atomic create, reload, overwrite, and spaces in paths", [&] {
        const auto path = CasePath(root, L"good writes with spaces");
        DWORD error = ~0u;
        REQUIRE(hydro::PersistCMOS(path.c_str(), initial.data(), hydro::kCMOSBytes, &error));
        REQUIRE(error == ERROR_SUCCESS && RawRead(path) == initial);
        REQUIRE(hydro::PersistCMOS(path.c_str(), updated.data(), hydro::kCMOSBytes, &error));
        REQUIRE(error == ERROR_SUCCESS && RawRead(path) == updated && NoTemporaryFiles(path));
    });
    cases.emplace_back("invalid checksum cannot overwrite last good save", [&] {
        const auto path = CasePath(root, L"bad checksum"); RawWrite(path, initial);
        auto corrupt = updated; corrupt[0x120] ^= 0x01;
        DWORD error;
        REQUIRE(!hydro::PersistCMOS(path.c_str(), corrupt.data(), hydro::kCMOSBytes, &error));
        REQUIRE(error == ERROR_INVALID_DATA && RawRead(path) == initial && NoTemporaryFiles(path));
    });
    cases.emplace_back("truncated and oversized inputs cannot overwrite", [&] {
        const auto path = CasePath(root, L"wrong buffer sizes"); RawWrite(path, initial);
        REQUIRE(!hydro::PersistCMOS(path.c_str(), updated.data(), hydro::kCMOSBytes - 1));
        REQUIRE(!hydro::PersistCMOS(path.c_str(), updated.data(), hydro::kCMOSBytes + 1));
        REQUIRE(!hydro::PersistCMOS(path.c_str(), nullptr, hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == initial && NoTemporaryFiles(path));
    });
    cases.emplace_back("failed atomic replacement preserves existing save and removes temp", [&] {
        const auto path = CasePath(root, L"locked destination"); RawWrite(path, initial);
        HANDLE lock = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
        REQUIRE(lock != INVALID_HANDLE_VALUE);
        DWORD error;
        const bool result = hydro::PersistCMOS(path.c_str(), updated.data(), hydro::kCMOSBytes, &error);
        CloseHandle(lock);
        REQUIRE(!result && error != ERROR_SUCCESS && RawRead(path) == initial && NoTemporaryFiles(path));
    });
    cases.emplace_back("unavailable directory reports write failure", [&] {
        const auto path = root + L"\\missing directory\\CMOS.bin";
        DWORD error;
        REQUIRE(!hydro::PersistCMOS(path.c_str(), updated.data(), hydro::kCMOSBytes, &error));
        REQUIRE(error == ERROR_PATH_NOT_FOUND);
    });
    cases.emplace_back("relative paths are rejected", [&] {
        REQUIRE(!hydro::PersistCMOS(L"CMOS.bin", initial.data(), hydro::kCMOSBytes));
        REQUIRE(!hydro::PersistCMOS(L"C:CMOS.bin", initial.data(), hydro::kCMOSBytes));
    });
    cases.emplace_back("startup loads saved payload before unconditional flush", [&] {
        const auto path = CasePath(root, L"saved startup"); RawWrite(path, updated);
        hydro::Session session;
        auto nativeStaging = initial;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), nativeStaging.data(), hydro::kCMOSBytes) == hydro::Loaded);
        REQUIRE(nativeStaging == updated && session.state == hydro::WriteAllowed);
        // This mirrors the native init sequence: valid staging becomes active CMOS,
        // then native init flushes that same active CMOS unconditionally.
        const auto nativeActive = nativeStaging;
        REQUIRE(hydro::WriteForSession(session, path.c_str(), nativeActive.data(), hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == updated);
        hydro::Session secondLaunch;
        std::fill(nativeStaging.begin(), nativeStaging.end(), static_cast<BYTE>(0));
        REQUIRE(hydro::ReadForSession(secondLaunch, path.c_str(), nativeStaging.data(), hydro::kCMOSBytes) == hydro::Loaded);
        REQUIRE(nativeStaging == updated);
    });
    cases.emplace_back("missing save permits initial defaults and later scores", [&] {
        const auto path = CasePath(root, L"first startup");
        hydro::Session session;
        auto staging = updated;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Missing);
        REQUIRE(std::all_of(staging.begin(), staging.end(), [](BYTE b) { return b == 0; }));
        REQUIRE(hydro::WriteForSession(session, path.c_str(), initial.data(), hydro::kCMOSBytes));
        REQUIRE(hydro::WriteForSession(session, path.c_str(), updated.data(), hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == updated);
    });
    cases.emplace_back("write before read is refused", [&] {
        const auto path = CasePath(root, L"early write"); RawWrite(path, updated);
        hydro::Session session;
        REQUIRE(!hydro::WriteForSession(session, path.c_str(), initial.data(), hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == updated);
    });
    cases.emplace_back("corrupt existing save blocks writes for entire launch", [&] {
        const auto path = CasePath(root, L"corrupt existing");
        auto corrupt = updated; corrupt[0x120] ^= 1; RawWrite(path, corrupt);
        hydro::Session session;
        auto staging = initial;
        DWORD error;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes, &error) == hydro::Unsafe);
        REQUIRE(error == ERROR_INVALID_DATA && session.state == hydro::WriteBlocked);
        REQUIRE(std::all_of(staging.begin(), staging.end(), [](BYTE b) { return b == 0; }));
        REQUIRE(!hydro::WriteForSession(session, path.c_str(), initial.data(), hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == corrupt);
        // Even a later readable valid file must not silently clear the latch.
        RawWrite(path, updated);
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Loaded);
        REQUIRE(session.state == hydro::WriteBlocked);
        REQUIRE(!hydro::WriteForSession(session, path.c_str(), initial.data(), hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == updated);
    });
    cases.emplace_back("truncated existing save preserved and writes blocked", [&] {
        const auto path = CasePath(root, L"truncated existing");
        auto truncated = updated; truncated.resize(31999); RawWrite(path, truncated);
        hydro::Session session;
        auto staging = initial;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Unsafe);
        REQUIRE(!hydro::WriteForSession(session, path.c_str(), initial.data(), hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == truncated);
    });
    cases.emplace_back("unreadable existing save preserved and writes blocked", [&] {
        const auto path = CasePath(root, L"unreadable existing"); RawWrite(path, updated);
        HANDLE lock = CreateFileW(path.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, 0, nullptr);
        REQUIRE(lock != INVALID_HANDLE_VALUE);
        hydro::Session session;
        auto staging = initial;
        DWORD error;
        const auto result = hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes, &error);
        CloseHandle(lock);
        REQUIRE(result == hydro::Unsafe && error == ERROR_SHARING_VIOLATION);
        REQUIRE(!hydro::WriteForSession(session, path.c_str(), initial.data(), hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == updated);
    });
    cases.emplace_back("known TP metadata-only startup mutation is recovered exactly", [&] {
        const auto path = CasePath(root, L"TP metadata recovery");
        auto mutated = updated; SetWord(mutated, 20, 3); SetWord(mutated, 24, 1);
        REQUIRE(!hydro::ValidateCMOS(mutated.data(), hydro::kCMOSBytes));
        RawWrite(path, mutated); RawWrite(SidecarPath(path), updated);
        hydro::Session session; auto staging = initial; DWORD error;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes, &error) == hydro::Recovered);
        auto expected = mutated; UpdateChecksum(expected);
        REQUIRE(error == ERROR_SUCCESS && staging == expected && session.state == hydro::WriteAllowed);
        REQUIRE(RawRead(path) == mutated); // Recovery read itself never rewrites the primary.
        REQUIRE(hydro::WriteForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == expected && RawRead(SidecarPath(path)) == expected);
    });
    cases.emplace_back("score or stored-checksum corruption cannot use valid sidecar", [&] {
        for (const size_t offset : {static_cast<size_t>(0x120), static_cast<size_t>(12)}) {
            const auto path = CasePath(root, offset == 12 ? L"checksum corruption" : L"score corruption");
            auto corrupt = updated; SetWord(corrupt, 24, 1); corrupt[offset] ^= 0x40;
            RawWrite(path, corrupt); RawWrite(SidecarPath(path), updated);
            hydro::Session session; auto staging = initial;
            REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Unsafe);
            REQUIRE(!hydro::WriteForSession(session, path.c_str(), initial.data(), hydro::kCMOSBytes));
            REQUIRE(RawRead(path) == corrupt && RawRead(SidecarPath(path)) == updated);
        }
    });
    cases.emplace_back("stale sidecar cannot recover a newer mismatched payload", [&] {
        const auto path = CasePath(root, L"stale sidecar");
        auto corrupt = updated; SetWord(corrupt, 24, 1);
        RawWrite(path, corrupt); RawWrite(SidecarPath(path), initial);
        hydro::Session session; auto staging = initial;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Unsafe);
        REQUIRE(RawRead(path) == corrupt && session.state == hydro::WriteBlocked);
    });
    cases.emplace_back("out-of-range player and link metadata are never repaired", [&] {
        for (const size_t offset : {static_cast<size_t>(20), static_cast<size_t>(24)}) {
            const auto path = CasePath(root, offset == 20 ? L"player range" : L"link range");
            auto corrupt = updated; SetWord(corrupt, offset, offset == 20 ? 4 : 2);
            RawWrite(path, corrupt); RawWrite(SidecarPath(path), updated);
            hydro::Session session; auto staging = initial;
            REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Unsafe);
            REQUIRE(RawRead(path) == corrupt);
        }
    });
    cases.emplace_back("invalid or unreadable recovery sidecar cannot repair primary", [&] {
        for (unsigned type = 0; type < 3; ++type) {
            const auto path = CasePath(root, type == 0 ? L"bad sidecar checksum" :
                                             type == 1 ? L"short sidecar" : L"unreadable sidecar");
            auto primary = updated; SetWord(primary, 24, 1); RawWrite(path, primary);
            auto companion = updated;
            if (type == 0) companion[12] ^= 0x40;
            if (type == 1) companion.resize(hydro::kCMOSBytes - 1);
            RawWrite(SidecarPath(path), companion);
            HANDLE lock = INVALID_HANDLE_VALUE;
            if (type == 2) {
                lock = CreateFileW(SidecarPath(path).c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, 0, nullptr);
                REQUIRE(lock != INVALID_HANDLE_VALUE);
            }
            hydro::Session session; auto staging = initial;
            const auto result = hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes);
            if (lock != INVALID_HANDLE_VALUE) CloseHandle(lock);
            REQUIRE(result == hydro::Unsafe && session.state == hydro::WriteBlocked);
            REQUIRE(RawRead(path) == primary && RawRead(SidecarPath(path)) == companion);
        }
    });
    cases.emplace_back("missing primary honors reset and never resurrects sidecar", [&] {
        const auto path = CasePath(root, L"intentional reset"); RawWrite(SidecarPath(path), updated);
        hydro::Session session; auto staging = updated;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Missing);
        REQUIRE(std::all_of(staging.begin(), staging.end(), [](BYTE b) { return b == 0; }));
        REQUIRE(hydro::WriteForSession(session, path.c_str(), initial.data(), hydro::kCMOSBytes));
        REQUIRE(RawRead(path) == initial && RawRead(SidecarPath(path)) == initial);
    });
    cases.emplace_back("valid primary wins over newer or unreadable sidecar", [&] {
        const auto path = CasePath(root, L"primary priority"); RawWrite(path, initial);
        RawWrite(SidecarPath(path), updated);
        HANDLE lock = CreateFileW(SidecarPath(path).c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, 0, nullptr);
        REQUIRE(lock != INVALID_HANDLE_VALUE);
        hydro::Session session; auto staging = updated;
        const auto result = hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes);
        CloseHandle(lock);
        REQUIRE(result == hydro::Loaded && staging == initial);
    });
    cases.emplace_back("first native TP staging mismatch uses only validated authority", [&] {
        const auto path = CasePath(root, L"native staging reconcile");
        RawWrite(path, initial); hydro::Session session; auto staging = initial;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Loaded);
        auto authoritative = updated; SetWord(authoritative, 20, 3); SetWord(authoritative, 24, 1);
        UpdateChecksum(authoritative);
        staging = authoritative; SetWord(staging, 20, 0); SetWord(staging, 24, 0);
        const auto originalStaging = staging;
        REQUIRE(!hydro::ValidateCMOS(staging.data(), hydro::kCMOSBytes));
        bool reconciled; DWORD error;
        REQUIRE(!hydro::WriteForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes, &error));
        REQUIRE(error == ERROR_INVALID_DATA && RawRead(path) == initial);
        REQUIRE(hydro::WriteForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes,
                                       &error, authoritative.data(), &reconciled));
        REQUIRE(error == ERROR_SUCCESS && reconciled && staging == originalStaging);
        REQUIRE(RawRead(path) == authoritative && RawRead(SidecarPath(path)) == authoritative);
    });
    cases.emplace_back("native reconciliation rejects data, checksum, or authority corruption", [&] {
        const auto path = CasePath(root, L"reject unsafe native reconcile"); RawWrite(path, initial);
        hydro::Session session; auto buffer = initial;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), buffer.data(), hydro::kCMOSBytes) == hydro::Loaded);
        auto authoritative = updated; SetWord(authoritative, 24, 1); UpdateChecksum(authoritative);
        for (const size_t offset : {static_cast<size_t>(0x120), static_cast<size_t>(12)}) {
            auto staging = authoritative; SetWord(staging, 24, 0); staging[offset] ^= 0x40;
            bool reconciled = true;
            REQUIRE(!hydro::WriteForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes,
                                            nullptr, authoritative.data(), &reconciled));
            REQUIRE(!reconciled && RawRead(path) == initial);
        }
        auto staging = authoritative; SetWord(staging, 24, 0);
        authoritative[0x120] ^= 0x40;
        REQUIRE(!hydro::WriteForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes,
                                        nullptr, authoritative.data()));
        REQUIRE(RawRead(path) == initial);
    });
    cases.emplace_back("sidecar write failure prevents primary update", [&] {
        const auto path = CasePath(root, L"sidecar lock"); RawWrite(path, initial);
        RawWrite(SidecarPath(path), initial);
        hydro::Session session; auto staging = initial;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Loaded);
        HANDLE lock = CreateFileW(SidecarPath(path).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
        REQUIRE(lock != INVALID_HANDLE_VALUE); DWORD error;
        const bool saved = hydro::WriteForSession(session, path.c_str(), updated.data(), hydro::kCMOSBytes, &error);
        CloseHandle(lock);
        REQUIRE(!saved && error != ERROR_SUCCESS && RawRead(path) == initial && RawRead(SidecarPath(path)) == initial);
        REQUIRE(NoTemporaryFiles(path) && NoTemporaryFiles(SidecarPath(path)));
    });
    cases.emplace_back("native reconciliation rejects either out-of-range metadata", [&] {
        const auto path = CasePath(root, L"native metadata ranges"); RawWrite(path, initial);
        hydro::Session session; auto staging = initial;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Loaded);
        for (const size_t offset : {static_cast<size_t>(20), static_cast<size_t>(24)}) {
            const DWORD invalid = offset == 20 ? 4 : 2;
            auto authority = updated; SetWord(authority, offset, invalid); UpdateChecksum(authority);
            staging = authority; SetWord(staging, offset, 0);
            REQUIRE(!hydro::WriteForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes,
                                            nullptr, authority.data()));
            authority = updated; staging = authority; SetWord(staging, offset, invalid);
            REQUIRE(!hydro::WriteForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes,
                                            nullptr, authority.data()));
            REQUIRE(RawRead(path) == initial);
        }
    });
    cases.emplace_back("primary write failure leaves old valid primary authoritative", [&] {
        const auto path = CasePath(root, L"primary lock with sidecar ahead"); RawWrite(path, initial);
        RawWrite(SidecarPath(path), initial);
        hydro::Session session; auto staging = initial;
        REQUIRE(hydro::ReadForSession(session, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Loaded);
        HANDLE lock = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
        REQUIRE(lock != INVALID_HANDLE_VALUE);
        const bool saved = hydro::WriteForSession(session, path.c_str(), updated.data(), hydro::kCMOSBytes);
        CloseHandle(lock);
        REQUIRE(!saved && RawRead(path) == initial && RawRead(SidecarPath(path)) == updated);
        hydro::Session nextLaunch;
        REQUIRE(hydro::ReadForSession(nextLaunch, path.c_str(), staging.data(), hydro::kCMOSBytes) == hydro::Loaded);
        REQUIRE(staging == initial && NoTemporaryFiles(path) && NoTemporaryFiles(SidecarPath(path)));
    });
    cases.emplace_back("host, image, and both code signatures strictly guarded", [&] {
        REQUIRE(hydro::IsSupportedHostName(L"HYDRO_x64_LAN.exe"));
        REQUIRE(hydro::IsSupportedHostName(L"hydro.exe"));
        REQUIRE(!hydro::IsSupportedHostName(L"OtherGame.exe"));
        REQUIRE(!hydro::IsSupportedHostName(L"HydroSaveTests.exe"));
        REQUIRE(hydro::IsSupportedImage(0x100000, IMAGE_FILE_MACHINE_I386, 0x10B, 0x100000, 0x800000));
        REQUIRE(!hydro::IsSupportedImage(0x400000, IMAGE_FILE_MACHINE_I386, 0x10B, 0x100000, 0x800000));
        REQUIRE(!hydro::IsSupportedImage(0x100000, IMAGE_FILE_MACHINE_AMD64, 0x20B, 0x100000, 0x800000));
        REQUIRE(!hydro::IsSupportedImage(0x100000, IMAGE_FILE_MACHINE_I386, 0x10B, 0x100000, 0x10000));
        for (const BYTE* expected : {hydro::kReadSignature, hydro::kWriteSignature}) {
            BYTE test[hydro::kSignatureBytes]; std::memcpy(test, expected, sizeof(test));
            REQUIRE(hydro::IsSupportedSignature(test, sizeof(test), expected));
            for (size_t index = 0; index < sizeof(test); ++index) {
                test[index] ^= 1;
                REQUIRE(!hydro::IsSupportedSignature(test, sizeof(test), expected));
                test[index] ^= 1;
            }
            REQUIRE(!hydro::IsSupportedSignature(test, sizeof(test) - 1, expected));
        }
    });
    cases.emplace_back("real DLL attaches to foreign host without patch or save writes", [&] {
        const auto path = CasePath(root, L"foreign dll host");
        const auto directory = path.substr(0, path.find_last_of(L'\\'));
        wchar_t previous[32768]; REQUIRE(GetCurrentDirectoryW(_countof(previous), previous));
        REQUIRE(SetCurrentDirectoryW(directory.c_str()));
        HMODULE dll = LoadLibraryW(argv[2]);
        REQUIRE(dll != nullptr);
        using Getter = LONG (__cdecl*)();
        using Init = void (__cdecl*)();
        auto status = reinterpret_cast<Getter>(GetProcAddress(dll, "HydroSave_GetHookStatus"));
        auto writes = reinterpret_cast<Getter>(GetProcAddress(dll, "HydroSave_GetSuccessfulWrites"));
        auto init = reinterpret_cast<Init>(GetProcAddress(dll, "HydroSave_Init"));
        REQUIRE(status && writes && init);
        init();
        REQUIRE(status() == hydro::UnsupportedHost && writes() == 0);
        REQUIRE(GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES);
        REQUIRE(FreeLibrary(dll));
        REQUIRE(SetCurrentDirectoryW(previous));
    });

    unsigned passed = 0;
    for (const auto& test : cases) {
        std::printf("TEST %s\n", test.first);
        try { test.second(); ++passed; std::puts("  PASS"); }
        catch (const std::exception&) { break; }
    }
    std::printf("RESULT %u/%zu passed\n", passed, cases.size());
    std::wprintf(L"Synthetic test artifacts: %s\n", root.c_str());
    return passed == cases.size() ? 0 : 1;
}
