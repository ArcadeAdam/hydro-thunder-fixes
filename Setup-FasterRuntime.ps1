#requires -Version 5.1
<#
.SYNOPSIS
Builds the optional, tested Hydro-only runtime from your own local installations.
.DESCRIPTION
No downloads, game files, saves, or LaunchBox edits. Donor files are read only.
The new destination contains YOUR private configuration and must not be shared.
Exact tested binary hashes are checked before any destination write.
.EXAMPLE
.\Setup-FasterRuntime.ps1 -OlderRuntimePath C:\Emulators\TP-2078 -CurrentRuntimePath C:\Emulators\TeknoParrot -DestinationPath C:\Emulators\TeknoParrot-Hydro -CheckOnly
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $true)][string]$OlderRuntimePath,
    [Parameter(Mandatory = $true)][string]$CurrentRuntimePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [switch]$CheckOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AbsolutePath([string]$Path) {
    if ($Path -notmatch '^(?:[A-Za-z]:[\\/]|\\\\)') { throw 'Use fully qualified Windows paths.' }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}
function Assert-Directory([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected an ordinary directory: $Path"
    }
}
function Assert-DonorFile([string]$Root, [string]$Relative) {
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    $prefix = $Root + '\'
    if (!$path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Donor path escaped its root.' }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected an ordinary donor file: $Relative"
    }
    $parent = $item.DirectoryName
    while ($parent.Length -gt $Root.Length) {
        Assert-Directory $parent
        $parent = Split-Path -Parent $parent
    }
    return $item
}
function Get-Target([string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative)) { throw 'Rooted relative path rejected.' }
    $target = [IO.Path]::GetFullPath((Join-Path $destination $Relative))
    if (!$target.StartsWith(($destination + '\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Destination path escaped the new runtime.'
    }
    return $target
}
function Read-PrivateXml([string]$Path) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($Path, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.PreserveWhitespace = $true
        $document.XmlResolver = $null
        $document.Load($reader)
        return ,$document
    } catch {
        throw 'Private XML could not be safely parsed; no configuration values are displayed.'
    } finally { if ($reader) { $reader.Dispose() } }
}

$older = Get-AbsolutePath $OlderRuntimePath
$current = Get-AbsolutePath $CurrentRuntimePath
$destination = Get-AbsolutePath $DestinationPath
Assert-Directory $older
Assert-Directory $current
if (Test-Path -LiteralPath $destination) { throw 'Destination already exists. Choose a new directory; nothing will be overwritten.' }
Assert-Directory (Split-Path -Parent $destination)
foreach ($root in @($older, $current)) {
    if ($destination.StartsWith(($root + '\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Create the destination outside both donor runtimes.'
    }
}

# Only the component combination actually tested is supported. Never silently
# substitute the obsolete loader/FFB pair that booted quickly without feedback.
$requirements = @(
    @{ Donor = 'Older'; Root = $older; Relative = 'TeknoParrotUi.exe'; Version = '1.0.0.2078'; Hash = '6AED90158B5AFA96AD8CBC4C9E0A8F6D832D90BE1627F9DEEDCEF2D02BDB97E8' },
    @{ Donor = 'Older'; Root = $older; Relative = 'TeknoParrot\TeknoParrot.dll'; Version = '1.0.0.3742'; Hash = '01E668D048F9C10D34FE7E93001B058B3CAD6EEC71C1731925C4B2560D553D67' },
    @{ Donor = 'Current'; Root = $current; Relative = 'OpenParrotWin32\OpenParrotLoader.exe'; Version = $null; Hash = '2296185E0AFA9DAC0F6963A5BB76CBF28750EF02845CAC3C7D89C9F56304B5C7' },
    @{ Donor = 'Current'; Root = $current; Relative = 'FFBBlaster\x86\FFBBlaster.dll'; Version = '0.0.0.200'; Hash = '2E51FF66A00A4CC3D1A05956F1AF44D6CF0942438898D1F056FD22E32D6CA80F' },
    @{ Donor = 'Current'; Root = $current; Relative = 'FFBBlaster\x86\SDL2.dll'; Version = $null; Hash = 'D29EB00AB05BC747B94DF79CA1ED67677B586797DD032CEF7B83FEF068B4F230' },
    @{ Donor = 'Current'; Root = $current; Relative = 'FFBBlaster\x86\SDL3.dll'; Version = $null; Hash = '938646DF47E7828B16625F22E9927A781316C1F8129B5FC1A4A05BBA1B8642A1' }
)
$baseline = New-Object 'System.Collections.Generic.List[object]'
foreach ($required in $requirements) {
    $item = Assert-DonorFile $required.Root $required.Relative
    $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    if ($hash -cne $required.Hash -or ($required.Version -and $item.VersionInfo.FileVersion -cne $required.Version)) {
        throw "Unsupported $($required.Donor) component: $($required.Relative). See FASTER-RUNTIME.md; no destination was created."
    }
    $baseline.Add([pscustomobject]@{ RelativePath = $required.Relative; Donor = $required.Donor;
        FileVersion = $item.VersionInfo.FileVersion; Bytes = $item.Length; SHA256 = $hash })
}

$candidates = New-Object 'System.Collections.Generic.List[object]'
function Add-Candidate([string]$Root, [string]$Relative, [string]$Donor) {
    $candidates.Add([pscustomobject]@{ Root = $Root; Relative = $Relative; Donor = $Donor })
}
foreach ($relative in @('TeknoParrotUi.exe', 'TeknoParrotUi.exe.config', 'Utf8Json.dll',
                       'ParrotData.xml', 'HookedWindows.txt', 'GameProfiles\HydroThunder.xml',
                       'Metadata\HydroThunder.json')) { Add-Candidate $older $relative 'Older' }

# Traverse libraries conservatively, pruning browser cache before entering it.
$directories = New-Object 'System.Collections.Generic.Stack[string]'
$directories.Push((Join-Path $older 'libs'))
while ($directories.Count -gt 0) {
    $directory = $directories.Pop()
    Assert-Directory $directory
    foreach ($item in (Get-ChildItem -LiteralPath $directory -Force)) {
        $relative = $item.FullName.Substring($older.Length + 1)
        if ($item.PSIsContainer) {
            if ($relative -ieq 'libs\CefSharp\Cache') { continue }
            Assert-Directory $item.FullName
            $directories.Push($item.FullName)
        } elseif ($item.Extension -ine '.pdb' -and $item.Name -ine 'debug.log') {
            Add-Candidate $older $relative 'Older'
        }
    }
}
foreach ($name in @('bngrw.dll', 'iDmacDrv32.dll', 'OpenParrot.dll', 'OpenParrotKonamiLoader.exe')) {
    Add-Candidate $older ('OpenParrotWin32\' + $name) 'Older'
}
Add-Candidate $current 'OpenParrotWin32\OpenParrotLoader.exe' 'Current'
foreach ($name in @('FFBBlaster.dll', 'SDL2.dll', 'SDL3.dll')) {
    Add-Candidate $current ('FFBBlaster\x86\' + $name) 'Current'
}
foreach ($item in (Get-ChildItem -LiteralPath (Join-Path $older 'TeknoParrot') -File -Filter '*.dll')) {
    if ($item.Name -iin @('TeknoParrot64.dll', 'TeknoDraw64.dll', 'ScoreSubmission64.dll')) { continue }
    Add-Candidate $older ('TeknoParrot\' + $item.Name) 'Older'
}
Add-Candidate $current 'UserProfiles\HydroThunder.xml' 'Current'
Add-Candidate $current 'Icons\HydroThunder.png' 'Current'

$plan = New-Object 'System.Collections.Generic.List[object]'
$names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$totalBytes = [int64]0
foreach ($candidate in ($candidates | Sort-Object Relative)) {
    if (!$names.Add($candidate.Relative)) { throw 'Duplicate copy target in plan.' }
    $item = Assert-DonorFile $candidate.Root $candidate.Relative
    $totalBytes += $item.Length
    $plan.Add([pscustomobject]@{
        RelativePath = $candidate.Relative; Donor = $candidate.Donor;
        SourcePath = $item.FullName; DestinationPath = (Get-Target $candidate.Relative);
        SourceSHA256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash;
        SourceBytes = $item.Length
    })
}
foreach ($binary in $baseline) {
    $planned = $plan | Where-Object { $_.RelativePath -eq $binary.RelativePath }
    if ($planned.SourceSHA256 -cne $binary.SHA256) { throw 'Source binary changed during validation.' }
}
$config = Read-PrivateXml (Join-Path $older 'ParrotData.xml')
if ($config.SelectNodes('//*[local-name()="CheckForUpdates"]').Count -ne 1) {
    throw 'Older ParrotData.xml must contain exactly one CheckForUpdates node.'
}
$null = Read-PrivateXml (Join-Path $current 'UserProfiles\HydroThunder.xml')
Write-Host ("Validated {0} local files ({1:N2} MiB); all six tested component hashes match." -f $plan.Count, ($totalBytes / 1MB))
if ($CheckOnly) { Write-Host 'CheckOnly: no files or settings changed.'; return }
if ($WhatIfPreference) {
    $null = $PSCmdlet.ShouldProcess($destination, 'Create private Hydro runtime from validated local donors')
    return
}
if (@(Get-Process -Name 'TeknoParrotUi', 'HYDRO', 'HYDRO_x64', 'HYDRO_x64_LAN', 'HYDRO_x86' -ErrorAction SilentlyContinue).Count) {
    throw 'Close TeknoParrot and Hydro Thunder before creating the runtime.'
}
if (!$PSCmdlet.ShouldProcess($destination, 'Create private Hydro runtime from validated local donors')) { return }
if (Test-Path -LiteralPath $destination) { throw 'Destination appeared during validation; refusing to overwrite it.' }
$null = New-Item -ItemType Directory -Path $destination
$marker = Get-Target 'SETUP-INCOMPLETE.txt'
[IO.File]::WriteAllText($marker, 'Setup is incomplete. Do not launch this runtime. Donors, LaunchBox, game files and saves were not modified.')
try {
    $records = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $plan) {
        $parent = Split-Path -Parent $file.DestinationPath
        if (!(Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent }
        Copy-Item -LiteralPath $file.SourcePath -Destination $file.DestinationPath
        $hash = (Get-FileHash -LiteralPath $file.DestinationPath -Algorithm SHA256).Hash
        if ($hash -cne $file.SourceSHA256) { throw "Copy consistency check failed: $($file.RelativePath)" }
        $records.Add([pscustomobject]@{
            RelativePath = $file.RelativePath; Donor = $file.Donor;
            SourcePath = $file.SourcePath; DestinationPath = $file.DestinationPath;
            SourceSHA256 = $file.SourceSHA256; DestinationSHA256 = $hash;
            SourceBytes = $file.SourceBytes; DestinationBytes = (Get-Item -LiteralPath $file.DestinationPath).Length;
            Transformation = $null
        })
    }
    $configPath = Get-Target 'ParrotData.xml'
    $copiedConfig = Read-PrivateXml $configPath
    $before = $copiedConfig.CloneNode($true)
    $node = $copiedConfig.SelectSingleNode('//*[local-name()="CheckForUpdates"]')
    $originalValue = $node.InnerText
    $node.InnerText = 'false'
    $copiedConfig.Save($configPath)
    $verification = Read-PrivateXml $configPath
    $verifiedNode = $verification.SelectSingleNode('//*[local-name()="CheckForUpdates"]')
    if (!$verifiedNode -or $verifiedNode.InnerText -cne 'false') { throw 'Copied update-check setting did not verify.' }
    $verifiedNode.InnerText = $originalValue
    if ($verification.DocumentElement.OuterXml -cne $before.DocumentElement.OuterXml) {
        throw 'Unexpected copied XML settings change; do not use this runtime.'
    }
    $record = $records | Where-Object { $_.RelativePath -eq 'ParrotData.xml' }
    $record.DestinationSHA256 = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
    $record.DestinationBytes = (Get-Item -LiteralPath $configPath).Length
    $record.Transformation = 'Only CheckForUpdates=false; other private settings preserved.'
    $manifest = [ordered]@{
        SchemaVersion = 1; PackageVersion = '1.1.0'; CreatedUtc = [DateTime]::UtcNow.ToString('o');
        OlderRuntimePath = $older; CurrentRuntimePath = $current; DestinationPath = $destination;
        Privacy = 'PRIVATE local runtime. Configuration/profile/artwork came from the recipient. Do not redistribute.';
        Baseline = @($baseline.ToArray()); Files = @($records.ToArray())
    }
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Get-Target 'FasterRuntime-manifest.json'), ($manifest | ConvertTo-Json -Depth 6), $utf8)
    $restore = @'
PRIVATE LOCAL RUNTIME: do not redistribute this folder or its account/profile data.

Setup did not change either donor, LaunchBox, game files, controls, or saved scores.
To revert, close this runtime and use the original TeknoParrot runtime. If you later
assign Hydro to a separate LaunchBox emulator, change only Hydro back to its original
emulator. The original shared emulator entry must remain unchanged.

Update checks are disabled only in this copy. Account settings came from your older
donor; Hydro controls/game path came from your current donor. Sign in normally with
your own account if required. Do not publish ParrotData.xml or the generated profile.

The bezel/save helper's installer and uninstaller are independent. Reverting this
runtime does not remove either fix or restore/delete CMOS.bin or its recovery file.

To discard this runtime, verify its exact DestinationPath in FasterRuntime-manifest.json,
close all processes using it, then archive/remove only that verified directory.
This script performs no recursive deletion and no move.
'@
    [IO.File]::WriteAllText((Get-Target 'RESTORE-README.txt'), $restore, $utf8)
    Remove-Item -LiteralPath $marker
    Write-Host ("Created: {0}" -f $destination)
    Write-Host 'LaunchBox and game/save files are unchanged. Follow FASTER-RUNTIME.md to test and assign only Hydro.'
} catch {
    Write-Warning 'Setup failed; the new folder remains marked incomplete. Donors, LaunchBox and saves were not modified.'
    throw
}
