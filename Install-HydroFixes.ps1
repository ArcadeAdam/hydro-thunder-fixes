[CmdletBinding()]
param(
    [string]$GameDirectory,
    [string]$TeknoParrotDirectory,
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
    $pngPath = Join-Path $gameDir 'bezel.png'
    $png = [IO.File]::ReadAllBytes($pngPath)
    $pngSignature = [byte[]](137,80,78,71,13,10,26,10)
    for($i=0;$i -lt 8;$i++) { if($png[$i] -ne $pngSignature[$i]) { throw 'bezel.png is not a PNG.' } }
    $width = [int]$png[16]*16777216+[int]$png[17]*65536+[int]$png[18]*256+[int]$png[19]
    $height = [int]$png[20]*16777216+[int]$png[21]*65536+[int]$png[22]*256+[int]$png[23]
    if ($width -ne 1920 -or $height -ne 1080) { throw 'This bezel preset requires a 1920x1080 bezel.png.' }
    $proxy = Join-Path $gameDir 'd3d11.dll'
    $payloadProxy = Join-Path $payloadDir 'd3d11.dll'
    if ((Test-Path -LiteralPath $proxy) -and ((Get-FileHash -LiteralPath $proxy).Hash -ne (Get-FileHash -LiteralPath $payloadProxy).Hash)) {
        throw 'A different d3d11.dll already exists. This installer will not replace another graphics proxy.'
    }
    foreach($relative in @('d3d11.dll','ReShade.ini','HydroBezel.ini','reshade-shaders\Shaders\HydroBezel.fx')) {
        Add-Change (Join-Path $gameDir $relative) ([IO.File]::ReadAllBytes((Join-Path $payloadDir $relative)))
    }
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
    $manifest=[pscustomobject]@{ Version='1.0.0'; InstalledUtc=(Get-Date).ToUniversalTime().ToString('o'); GameDirectory=$gameDir; BackupDirectory=$backupDir; Components=$Components; Files=$entries }
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
