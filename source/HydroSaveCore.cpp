#include "HydroSaveCore.h"
#include <cstring>
#include <cwchar>

namespace hydro {
const BYTE kWriteSignature[kSignatureBytes] = {
    0x55,0x8B,0xEC,0x51,0x53,0x56,0x57,0x33,
    0xC0,0xB9,0x00,0x80,0x00,0x00,0xBF,0xE8,
    0x14,0x5C,0x00,0xF3,0xAB,0xA1,0x00,0x15,
    0x60,0x00,0x85,0xC0,0x0F,0x84,0xF5,0x01
};
const BYTE kReadSignature[kSignatureBytes] = {
    0xA1,0x00,0x15,0x60,0x00,0x85,0xC0,0x56,
    0x57,0x75,0x0E,0xB9,0x00,0x80,0x00,0x00,
    0x33,0xC0,0xBF,0xE8,0x14,0x5C,0x00,0xF3,
    0xAB,0x8B,0x74,0x24,0x10,0x85,0xF6,0x76
};
static volatile LONG gTempSequence = 0;

static wchar_t* AppendHex(wchar_t* output, DWORD value) {
    static const wchar_t digits[] = L"0123456789ABCDEF";
    for (int shift = 28; shift >= 0; shift -= 4) *output++ = digits[(value >> shift) & 15];
    return output;
}

bool IsSupportedHostName(const wchar_t* name) {
    return name && (lstrcmpiW(name, L"HYDRO_x64_LAN.exe") == 0 ||
                    lstrcmpiW(name, L"HYDRO_x64.exe") == 0 ||
                    lstrcmpiW(name, L"HYDRO_x86.exe") == 0 ||
                    lstrcmpiW(name, L"HYDRO.EXE") == 0);
}

bool IsSupportedImage(DWORD actualBase, WORD machine, WORD optionalMagic,
                      DWORD preferredBase, DWORD imageBytes) {
    return actualBase == kMainBase && preferredBase == kMainBase &&
           machine == IMAGE_FILE_MACHINE_I386 &&
           optionalMagic == IMAGE_NT_OPTIONAL_HDR32_MAGIC &&
           imageBytes >= (kNativeStaging - kMainBase + kCMOSBytes);
}

bool IsSupportedSignature(const BYTE* signature, size_t bytes, const BYTE* expected) {
    return signature && expected && bytes >= kSignatureBytes &&
           std::memcmp(signature, expected, kSignatureBytes) == 0;
}

static DWORD CalculateChecksum(const BYTE* raw) {
    DWORD sum = 0;
    for (DWORD offset = 0; offset < kCMOSBytes; offset += sizeof(DWORD)) {
        if (offset == 0x0C) continue;
        DWORD word;
        std::memcpy(&word, raw + offset, sizeof(word));
        sum += word; // Deliberate modulo 2^32, matching Hydro Thunder.
    }
    return sum;
}

bool ValidateCMOS(const void* data, DWORD bytes) {
    if (!data || bytes != kCMOSBytes) return false;
    const BYTE* raw = static_cast<const BYTE*>(data);
    DWORD words[5];
    std::memcpy(words, raw, sizeof(words));
    return words[0] == 1 && words[1] == 0xFEDCBA98 && words[2] == 1 && words[4] == 0x59 &&
           CalculateChecksum(raw) == words[3];
}

static bool ValidMetadata(const BYTE* data) {
    DWORD playerId, linkFlag;
    std::memcpy(&playerId, data + 20, sizeof(playerId));
    std::memcpy(&linkFlag, data + 24, sizeof(linkFlag));
    return playerId <= 3 && linkFlag <= 1;
}

static bool SameExceptMetadata(const BYTE* left, const BYTE* right) {
    // Includes the stored checksum at 0x0C. Never accept checksum guessing,
    // score changes, stale backup payload, or any difference outside these 8 bytes.
    return std::memcmp(left, right, 20) == 0 &&
           std::memcmp(left + 28, right + 28, kCMOSBytes - 28) == 0;
}

static bool MetadataDifferenceProven(const BYTE* invalid, const BYTE* valid) {
    return !ValidateCMOS(invalid, kCMOSBytes) && ValidateCMOS(valid, kCMOSBytes) &&
           ValidMetadata(invalid) && ValidMetadata(valid) && SameExceptMetadata(invalid, valid);
}

static bool CopyCallerBuffer(void* snapshot, const void* data) {
    __try {
        std::memcpy(snapshot, data, kCMOSBytes);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

static bool IsAbsolutePath(const wchar_t* path) {
    if (!path) return false;
    // Accept drive-rooted paths and UNC/extended paths; reject drive-relative C:foo.
    return (path[0] && path[1] == L':' && (path[2] == L'\\' || path[2] == L'/')) ||
           (path[0] == L'\\' && path[1] == L'\\');
}

bool PersistCMOS(const wchar_t* path, const void* data, DWORD bytes, DWORD* errorOut) {
    DWORD error = ERROR_SUCCESS;
    BYTE* snapshot = nullptr;
    HANDLE output = INVALID_HANDLE_VALUE;
    wchar_t* temporary = nullptr;
    bool ownsTemporary = false;
    bool success = false;
    size_t pathLength = 0;

    do {
        if (bytes != kCMOSBytes || !data || !IsAbsolutePath(path)) {
            error = ERROR_INVALID_PARAMETER; break;
        }
        pathLength = wcsnlen_s(path, 32768);
        if (pathLength == 0 || pathLength > 32768 - 96) {
            error = ERROR_FILENAME_EXCED_RANGE; break;
        }
        snapshot = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), 0, kCMOSBytes));
        if (!snapshot) { error = ERROR_NOT_ENOUGH_MEMORY; break; }
        if (!CopyCallerBuffer(snapshot, data) || !ValidateCMOS(snapshot, bytes)) {
            error = ERROR_INVALID_DATA; break;
        }
        temporary = static_cast<wchar_t*>(HeapAlloc(GetProcessHeap(), 0, (pathLength + 96) * sizeof(wchar_t)));
        if (!temporary) { error = ERROR_NOT_ENOUGH_MEMORY; break; }
        std::memcpy(temporary, path, pathLength * sizeof(wchar_t));
        const wchar_t suffix[] = L".HydroSave-";
        std::memcpy(temporary + pathLength, suffix, (sizeof(suffix) - sizeof(wchar_t)));
        wchar_t* suffixEnd = temporary + pathLength + _countof(suffix) - 1;
        for (unsigned attempt = 0; attempt < 64; ++attempt) {
            const DWORD sequence = static_cast<DWORD>(InterlockedIncrement(&gTempSequence));
            wchar_t* cursor = AppendHex(suffixEnd, GetCurrentProcessId());
            *cursor++ = L'-'; cursor = AppendHex(cursor, GetTickCount());
            *cursor++ = L'-'; cursor = AppendHex(cursor, sequence);
            std::memcpy(cursor, L".tmp", 5 * sizeof(wchar_t));
            output = CreateFileW(temporary, GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                                 FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH, nullptr);
            if (output != INVALID_HANDLE_VALUE) { ownsTemporary = true; break; }
            error = GetLastError();
            if (error != ERROR_FILE_EXISTS && error != ERROR_ALREADY_EXISTS) break;
        }
        if (output == INVALID_HANDLE_VALUE) break;
        DWORD written = 0;
        if (!WriteFile(output, snapshot, kCMOSBytes, &written, nullptr)) {
            error = GetLastError(); break;
        }
        if (written != kCMOSBytes) { error = ERROR_WRITE_FAULT; break; }
        if (!FlushFileBuffers(output)) { error = GetLastError(); break; }
        if (!CloseHandle(output)) {
            error = GetLastError(); output = INVALID_HANDLE_VALUE; break;
        }
        output = INVALID_HANDLE_VALUE;
        if (!MoveFileExW(temporary, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
            error = GetLastError(); break;
        }
        ownsTemporary = false;
        success = true;
        error = ERROR_SUCCESS;
    } while (false);

    if (output != INVALID_HANDLE_VALUE) CloseHandle(output);
    if (ownsTemporary) DeleteFileW(temporary);
    if (temporary) HeapFree(GetProcessHeap(), 0, temporary);
    if (snapshot) HeapFree(GetProcessHeap(), 0, snapshot);
    if (errorOut) *errorOut = error;
    return success;
}

static bool ZeroCallerBuffer(void* destination) {
    __try { std::memset(destination, 0, kCMOSBytes); return true; }
    __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

static wchar_t* MakeSidecarPath(const wchar_t* path) {
    const size_t length = wcsnlen_s(path, 32768);
    if (!length || length >= 32768) return nullptr;
    const wchar_t* slash = std::wcsrchr(path, L'\\');
    const wchar_t* forwardSlash = std::wcsrchr(path, L'/');
    if (!slash || (forwardSlash && forwardSlash > slash)) slash = forwardSlash;
    if (!slash) return nullptr;
    const size_t prefix = static_cast<size_t>(slash - path + 1);
    static const wchar_t leaf[] = L"HydroSave.last-good.bin";
    if (prefix + _countof(leaf) >= 32768) return nullptr;
    auto* result = static_cast<wchar_t*>(HeapAlloc(GetProcessHeap(), 0,
                                                (prefix + _countof(leaf)) * sizeof(wchar_t)));
    if (!result) return nullptr;
    std::memcpy(result, path, prefix * sizeof(wchar_t));
    std::memcpy(result + prefix, leaf, sizeof(leaf));
    return result;
}

static bool ReadExactSnapshot(const wchar_t* path, BYTE* snapshot, DWORD& error) {
    HANDLE input = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (input == INVALID_HANDLE_VALUE) { error = GetLastError(); return false; }
    bool success = false;
    do {
        LARGE_INTEGER length;
        if (!GetFileSizeEx(input, &length)) { error = GetLastError(); break; }
        if (length.QuadPart != kCMOSBytes) { error = ERROR_INVALID_DATA; break; }
        DWORD count = 0;
        if (!ReadFile(input, snapshot, kCMOSBytes, &count, nullptr)) { error = GetLastError(); break; }
        if (count != kCMOSBytes) { error = ERROR_INVALID_DATA; break; }
        success = true;
        error = ERROR_SUCCESS;
    } while (false);
    CloseHandle(input);
    return success;
}

ReadResult ReadForSession(Session& session, const wchar_t* path, void* destination,
                         DWORD bytes, DWORD* errorOut) {
    DWORD error = ERROR_SUCCESS;
    ReadResult result = Unsafe;
    BYTE* snapshot = nullptr;
    BYTE* sidecar = nullptr;
    wchar_t* sidecarPath = nullptr;
    do {
        if (bytes != kCMOSBytes || !destination || !IsAbsolutePath(path)) {
            error = ERROR_INVALID_PARAMETER; break;
        }
        if (!ZeroCallerBuffer(destination)) { error = ERROR_NOACCESS; break; }
        snapshot = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), 0, kCMOSBytes));
        if (!snapshot) { error = ERROR_NOT_ENOUGH_MEMORY; break; }
        if (!ReadExactSnapshot(path, snapshot, error)) {
            if (error == ERROR_FILE_NOT_FOUND) { result = Missing; error = ERROR_SUCCESS; }
            break;
        }
        const bool initiallyValid = ValidateCMOS(snapshot, kCMOSBytes);
        if (!initiallyValid) {
            error = ERROR_INVALID_DATA;
            sidecarPath = MakeSidecarPath(path);
            if (!sidecarPath) break;
            sidecar = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), 0, kCMOSBytes));
            if (!sidecar) { error = ERROR_NOT_ENOUGH_MEMORY; break; }
            DWORD sidecarError;
            if (!ReadExactSnapshot(sidecarPath, sidecar, sidecarError) ||
                !MetadataDifferenceProven(snapshot, sidecar)) break;
            // Every non-metadata byte, including the old checksum, is proven
            // identical. Retain primary metadata and calculate its exact checksum.
            const DWORD corrected = CalculateChecksum(snapshot);
            std::memcpy(snapshot + 12, &corrected, sizeof(corrected));
            if (!ValidateCMOS(snapshot, kCMOSBytes)) break;
        }
        if (!CopyCallerBuffer(destination, snapshot)) { error = ERROR_NOACCESS; break; }
        result = initiallyValid ? Loaded : Recovered;
        error = ERROR_SUCCESS;
    } while (false);
    if (sidecarPath) HeapFree(GetProcessHeap(), 0, sidecarPath);
    if (sidecar) HeapFree(GetProcessHeap(), 0, sidecar);
    if (snapshot) HeapFree(GetProcessHeap(), 0, snapshot);
    if (result == Unsafe) InterlockedExchange(&session.state, WriteBlocked);
    else InterlockedCompareExchange(&session.state, WriteAllowed, NotRead);
    if (errorOut) *errorOut = error;
    return result;
}

bool WriteForSession(Session& session, const wchar_t* path, const void* data,
                     DWORD bytes, DWORD* errorOut, const void* authoritativeCMOS, bool* reconciledOut) {
    if (reconciledOut) *reconciledOut = false;
    if (InterlockedCompareExchange(&session.state, NotRead, NotRead) != WriteAllowed) {
        if (errorOut) *errorOut = ERROR_ACCESS_DENIED;
        return false;
    }
    DWORD error = ERROR_SUCCESS;
    BYTE* snapshot = nullptr;
    BYTE* authoritative = nullptr;
    wchar_t* sidecarPath = nullptr;
    bool success = false;
    do {
        if (bytes != kCMOSBytes || !data || !IsAbsolutePath(path)) {
            error = ERROR_INVALID_PARAMETER; break;
        }
        snapshot = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), 0, kCMOSBytes));
        if (!snapshot) { error = ERROR_NOT_ENOUGH_MEMORY; break; }
        if (!CopyCallerBuffer(snapshot, data)) { error = ERROR_NOACCESS; break; }
        if (!ValidateCMOS(snapshot, bytes)) {
            error = ERROR_INVALID_DATA;
            if (!authoritativeCMOS) break;
            authoritative = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), 0, kCMOSBytes));
            if (!authoritative) { error = ERROR_NOT_ENOUGH_MEMORY; break; }
            if (!CopyCallerBuffer(authoritative, authoritativeCMOS) ||
                !MetadataDifferenceProven(snapshot, authoritative)) break;
            std::memcpy(snapshot, authoritative, kCMOSBytes);
            if (reconciledOut) *reconciledOut = true;
        }
        sidecarPath = MakeSidecarPath(path);
        if (!sidecarPath) { error = ERROR_NOT_ENOUGH_MEMORY; break; }
        // Sidecar is committed first. If it fails, the primary is untouched.
        // A valid old primary still wins if the second replacement fails.
        if (!PersistCMOS(sidecarPath, snapshot, bytes, &error)) break;
        if (!PersistCMOS(path, snapshot, bytes, &error)) break;
        success = true;
    } while (false);
    if (sidecarPath) HeapFree(GetProcessHeap(), 0, sidecarPath);
    if (authoritative) HeapFree(GetProcessHeap(), 0, authoritative);
    if (snapshot) HeapFree(GetProcessHeap(), 0, snapshot);
    if (errorOut) *errorOut = error;
    return success;
}
}
