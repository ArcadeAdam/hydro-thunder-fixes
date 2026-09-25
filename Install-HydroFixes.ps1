[CmdletBinding()]
param(
    [string]$GameDirectory,
    [string]$TeknoParrotDirectory,
    [string]$BezelPath,
    [ValidateSet('Bezel','Save')][string[]]$Components = @('Bezel','Save'),
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
if (-not $GameDirectory) { $GameDirectory = Read-Host 'Hydro Thunder game folder (contains Glide2x.dll)' }
$gameDir = (Resolve-Path -LiteralPath $GameDirectory).Path.TrimEnd('\')
$packageDir = $PSScriptRoot
$payloadDir = Join-Path $packageDir 'Payload'
$manifestPath = Join-Path $gameDir 'HydroFixes.install.json'
if (Test-Path -LiteralPath $manifestPath) { throw 'A Hydro Fixes installation already exists. Use Uninstall-HydroFixes.ps1 before reinstalling.' }
$runningGames = Get-Process -Name 'HYDRO','HYDRO_x64','HYDRO_x86','HYDRO_x64_LAN' -ErrorAction SilentlyContinue
if ($runningGames) { throw 'Close Hydro Thunder before installing.' }
if (($Components -contains 'Bezel') -and (Get-Process -Name 'TeknoParrotUi' -ErrorAction SilentlyContinue)) { throw 'Close TeknoParrot before changing its bezel setting.' }

$changes = New-Object 'System.Collections.Generic.List[object]'
function Add-Change([string]$Target, [byte[]]$Bytes) {
    $changes.Add([pscustomobject]@{ Target=$Target; Bytes=$Bytes })
}
function Assert-BezelPng([byte[]]$Bytes) {
    if (-not ('HydroBezelPng' -as [type])) {
        Add-Type -ReferencedAssemblies System.Drawing,System.IO.Compression -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Text;

public static class HydroBezelPng {
    private static readonly uint[] CrcTable = MakeCrcTable();
    private static uint[] MakeCrcTable() {
        uint[] table = new uint[256];
        for (uint i = 0; i < 256; i++) {
            uint value = i;
            for (int bit = 0; bit < 8; bit++)
                value = (value & 1) != 0 ? 0xEDB88320U ^ (value >> 1) : value >> 1;
            table[i] = value;
        }
        return table;
    }
    private static uint Read32(byte[] data, int offset) {
        return ((uint)data[offset] << 24) | ((uint)data[offset + 1] << 16) |
               ((uint)data[offset + 2] << 8) | data[offset + 3];
    }
    private static uint Crc(byte[] data, int offset, int length) {
        uint value = 0xFFFFFFFFU;
        for (int i = offset; i < offset + length; i++)
            value = CrcTable[(value ^ data[i]) & 255] ^ (value >> 8);
        return value ^ 0xFFFFFFFFU;
    }
    private static void ValidatePixels(byte[] data, List<ArraySegment<byte>> chunks, int depth, int color, int interlace) {
        byte[] zlib;
        using (MemoryStream concatenated = new MemoryStream()) {
            foreach (ArraySegment<byte> chunk in chunks) concatenated.Write(data, chunk.Offset, chunk.Count);
            zlib = concatenated.ToArray();
        }
        if (zlib.Length < 6 || (zlib[0] & 15) != 8 || (zlib[0] >> 4) > 7 ||
            (((int)zlib[0] << 8) + zlib[1]) % 31 != 0 || (zlib[1] & 32) != 0)
            throw new InvalidDataException("Invalid PNG zlib header.");
        int channels = color == 2 ? 3 : color == 4 ? 2 : color == 6 ? 4 : 1;
        int bitsPerPixel = channels * depth;
        int[] startX = { 0, 4, 0, 2, 0, 1, 0 }, startY = { 0, 0, 4, 0, 2, 0, 1 };
        int[] stepX = { 8, 8, 4, 4, 2, 2, 1 }, stepY = { 8, 8, 8, 4, 4, 2, 2 };
        byte[] row = new byte[(1920 * bitsPerPixel + 7) / 8];
        uint a = 1, b = 0;
        using (MemoryStream compressed = new MemoryStream(zlib, 2, zlib.Length - 6, false))
        using (DeflateStream pixels = new DeflateStream(compressed, CompressionMode.Decompress)) {
            int passes = interlace == 0 ? 1 : 7;
            for (int pass = 0; pass < passes; pass++) {
                int width = interlace == 0 ? 1920 : (1920 - startX[pass] + stepX[pass] - 1) / stepX[pass];
                int height = interlace == 0 ? 1080 : (1080 - startY[pass] + stepY[pass] - 1) / stepY[pass];
                int rowBytes = (width * bitsPerPixel + 7) / 8;
                for (int y = 0; y < height; y++) {
                    int filter = pixels.ReadByte();
                    if (filter < 0 || filter > 4) throw new InvalidDataException("Invalid or truncated PNG scanline.");
                    a = (a + (uint)filter) % 65521; b = (b + a) % 65521;
                    int count = 0;
                    while (count < rowBytes) {
                        int read = pixels.Read(row, count, rowBytes - count);
                        if (read == 0) throw new InvalidDataException("PNG pixel data is truncated.");
                        count += read;
                    }
                    for (int x = 0; x < rowBytes; x++) { a = (a + row[x]) % 65521; b = (b + a) % 65521; }
                }
            }
            if (pixels.ReadByte() != -1) throw new InvalidDataException("PNG contains excess pixel data.");
        }
        if ((b << 16 | a) != Read32(zlib, zlib.Length - 4)) throw new InvalidDataException("PNG pixel checksum failed.");
    }
    public static void Validate(byte[] data) {
        byte[] signature = { 137, 80, 78, 71, 13, 10, 26, 10 };
        if (data == null || data.Length < 57) throw new InvalidDataException("Bezel PNG is truncated.");
        for (int i = 0; i < signature.Length; i++)
            if (data[i] != signature[i]) throw new InvalidDataException("Bezel input is not a PNG.");
        int position = 8, bitDepth = 0, colorType = 0, interlace = 0;
        List<ArraySegment<byte>> imageChunks = new List<ArraySegment<byte>>();
        bool header = false, palette = false, idat = false, idatEnded = false, ended = false;
        long compressedBytes = 0;
        while (position < data.Length) {
            if (data.Length - position < 12) throw new InvalidDataException("Truncated PNG chunk.");
            uint length = Read32(data, position);
            long next = (long)position + 12 + length;
            if (length > Int32.MaxValue || next > data.Length) throw new InvalidDataException("PNG chunk exceeds the file.");
            for (int i = position + 4; i < position + 8; i++)
                if (!((data[i] >= 65 && data[i] <= 90) || (data[i] >= 97 && data[i] <= 122)))
                    throw new InvalidDataException("Invalid PNG chunk type.");
            if ((data[position + 6] & 32) != 0) throw new InvalidDataException("Invalid PNG reserved chunk bit.");
            string kind = Encoding.ASCII.GetString(data, position + 4, 4);
            if (Crc(data, position + 4, (int)length + 4) != Read32(data, position + 8 + (int)length))
                throw new InvalidDataException("PNG chunk checksum failed.");
            if (!header && kind != "IHDR") throw new InvalidDataException("PNG must begin with IHDR.");
            if (kind == "IHDR") {
                if (header || position != 8 || length != 13) throw new InvalidDataException("Invalid PNG header.");
                if (Read32(data, position + 8) != 1920 || Read32(data, position + 12) != 1080)
                    throw new InvalidDataException("This bezel preset requires a 1920x1080 PNG.");
                bitDepth = data[position + 16]; colorType = data[position + 17];
                interlace = data[position + 20];
                bool validDepth = (colorType == 0 && (bitDepth == 1 || bitDepth == 2 || bitDepth == 4 || bitDepth == 8 || bitDepth == 16)) ||
                    (colorType == 3 && (bitDepth == 1 || bitDepth == 2 || bitDepth == 4 || bitDepth == 8)) ||
                    ((colorType == 2 || colorType == 4 || colorType == 6) && (bitDepth == 8 || bitDepth == 16));
                if (!validDepth || data[position + 18] != 0 || data[position + 19] != 0 || data[position + 20] > 1)
                    throw new InvalidDataException("Unsupported PNG header format.");
                header = true;
            } else if (kind == "PLTE") {
                if (palette || idat || length == 0 || length > 768 || length % 3 != 0 || colorType == 0 || colorType == 4 ||
                    (colorType == 3 && length / 3 > (1 << bitDepth))) throw new InvalidDataException("Invalid PNG palette.");
                palette = true;
            } else if (kind == "IDAT") {
                if (idatEnded || (colorType == 3 && !palette)) throw new InvalidDataException("Invalid PNG image data order.");
                idat = true; compressedBytes += length;
                imageChunks.Add(new ArraySegment<byte>(data, position + 8, (int)length));
            } else if (kind == "IEND") {
                if (length != 0 || !idat || compressedBytes == 0 || next != data.Length)
                    throw new InvalidDataException("Invalid PNG end chunk.");
                ended = true;
            } else if ((data[position + 4] & 32) == 0) {
                throw new InvalidDataException("Unknown critical PNG chunk.");
            }
            if (idat && kind != "IDAT") idatEnded = true;
            position = (int)next;
        }
        if (!ended) throw new InvalidDataException("PNG end chunk is missing.");
        ValidatePixels(data, imageChunks, bitDepth, colorType, interlace);
        // Decode in memory as well; validated structure alone cannot prove the
        // compressed pixels are usable. The original bytes are never re-encoded.
        using (MemoryStream stream = new MemoryStream(data, false))
        using (Image image = Image.FromStream(stream, false, true)) {
            if (image.Width != 1920 || image.Height != 1080)
                throw new InvalidDataException("Decoded bezel dimensions are invalid.");
        }
    }
}
'@
    }
    [HydroBezelPng]::Validate($Bytes)
}
if ($Components -contains 'Save') {
    $glide = Join-Path $gameDir 'Glide2x.dll'
    if (-not (Test-Path -LiteralPath $glide)) { throw 'Glide2x.dll is missing.' }
    if (Test-Path -LiteralPath (Join-Path $gameDir 'HydroSave.dll')) { throw 'HydroSave.dll already exists; no files changed.' }
    Add-Type -Path (Join-Path $packageDir 'Tools\PatchGlide.cs')
    $patched = [HydroGlidePatch]::Apply([IO.File]::ReadAllBytes($glide))
    Add-Change $glide $patched
    Add-Change (Join-Path $gameDir 'HydroSave.dll') ([IO.File]::ReadAllBytes((Join-Path $payloadDir 'HydroSave.dll')))
}
if ($Components -contains 'Bezel') {
    if (-not $TeknoParrotDirectory) { $TeknoParrotDirectory = Read-Host 'TeknoParrot folder (contains TeknoParrotUi.exe)' }
    $tpDir = (Resolve-Path -LiteralPath $TeknoParrotDirectory).Path.TrimEnd('\')
    $profile = Join-Path $tpDir 'UserProfiles\HydroThunder.xml'
    $profileBytes = [IO.File]::ReadAllBytes($profile)
    $profileText = [Text.Encoding]::UTF8.GetString($profileBytes)
    $profileXml = New-Object System.Xml.XmlDocument
    $profileXml.LoadXml($profileText.TrimStart([char]0xFEFF))
    $configuredGame = [IO.Path]::GetFullPath($profileXml.GameProfile.GamePath)
    if (-not [string]::Equals([IO.Path]::GetDirectoryName($configuredGame).TrimEnd('\'), $gameDir, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The HydroThunder profile points to a different game folder. No files changed.'
    }
    $bezelPattern = '(<CategoryName>Bezel</CategoryName>\s*<FieldName>Enable</FieldName>\s*<FieldValue>)[01](</FieldValue>)'
    if ([regex]::Matches($profileText,$bezelPattern).Count -ne 1) { throw 'Expected exactly one native Bezel setting.' }
    $newProfile = [regex]::Replace($profileText,$bezelPattern,'${1}0${2}')
    Add-Change $profile ([Text.Encoding]::UTF8.GetBytes($newProfile))
    $pngPath = if ($BezelPath) { (Resolve-Path -LiteralPath $BezelPath).Path } else { Join-Path $payloadDir 'bezel.png' }
    $png = [IO.File]::ReadAllBytes($pngPath)
    Assert-BezelPng $png
    $proxy = Join-Path $gameDir 'd3d11.dll'
    $payloadProxy = Join-Path $payloadDir 'd3d11.dll'
    if ((Test-Path -LiteralPath $proxy) -and ((Get-FileHash -LiteralPath $proxy).Hash -ne (Get-FileHash -LiteralPath $payloadProxy).Hash)) {
        throw 'A different d3d11.dll already exists. This installer will not replace another graphics proxy.'
    }
    foreach($relative in @('d3d11.dll','ReShade.ini','HydroBezel.ini','reshade-shaders\Shaders\HydroBezel.fx')) {
        Add-Change (Join-Path $gameDir $relative) ([IO.File]::ReadAllBytes((Join-Path $payloadDir $relative)))
    }
    Add-Change (Join-Path $gameDir 'bezel.png') $png
    Add-Change (Join-Path $gameDir 'reshade-shaders\Textures\bezel.png') $png
}

Write-Host 'Validated changes:'
$changes | ForEach-Object { Write-Host ('  ' + $_.Target) }
Write-Host 'CMOS.bin, game executables, controls and network settings are not modified by this installer.'
if ($CheckOnly) { Write-Host 'Check complete; no files changed.'; return }

$backupDir = Join-Path $gameDir ('HydroFixes-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backupDir | Out-Null
foreach($saveName in @('CMOS.bin','HydroSave.last-good.bin')) {
    $saveSource=Join-Path $gameDir $saveName
    if(Test-Path -LiteralPath $saveSource) { Copy-Item -LiteralPath $saveSource -Destination (Join-Path $backupDir ($saveName+'.preinstall')) }
}
$entries = New-Object 'System.Collections.Generic.List[object]'
$applied = New-Object 'System.Collections.Generic.List[object]'
try {
    $index=0
    foreach($change in $changes) {
        $exists=Test-Path -LiteralPath $change.Target
        $backup=$null
        if($exists) { $backup=Join-Path $backupDir ('{0:D2}-{1}' -f $index,[IO.Path]::GetFileName($change.Target)); Copy-Item -LiteralPath $change.Target -Destination $backup }
        $entry=[pscustomobject]@{ Target=$change.Target; Existed=$exists; Backup=$backup; InstalledSha256=$null }
        $entries.Add($entry)
        New-Item -ItemType Directory -Path (Split-Path -Parent $change.Target) -Force | Out-Null
        $applied.Add($entry)
        [IO.File]::WriteAllBytes($change.Target,$change.Bytes)
        $entry.InstalledSha256=(Get-FileHash -LiteralPath $change.Target).Hash
        $index++
    }
    $manifest=[pscustomobject]@{ Version='1.2.0'; InstalledUtc=(Get-Date).ToUniversalTime().ToString('o'); GameDirectory=$gameDir; BackupDirectory=$backupDir; Components=$Components; Files=$entries }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Host 'Installed. Launch Hydro Thunder normally through TeknoParrot.'
    Write-Host ('Backup: ' + $backupDir)
} catch {
    for($i=$applied.Count-1;$i -ge 0;$i--) {
        $entry=$applied[$i]
        if($entry.Existed) { Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force }
        elseif(Test-Path -LiteralPath $entry.Target) { Remove-Item -LiteralPath $entry.Target }
    }
    throw
}
