param([Parameter(Mandatory=$true)][string]$OriginalGlide,[string]$BezelPath,[Parameter(Mandatory=$true)][string]$WorkDirectory)
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
$bundled=Join-Path $package 'payload\bezel.png'
$bundledHash=(Get-FileHash -LiteralPath $bundled).Hash
if(-not $BezelPath) { $BezelPath=$bundled }
if(Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new empty test directory.' }
$work=[IO.Path]::GetFullPath($WorkDirectory)
New-Item -ItemType Directory -Path $work | Out-Null
$game=Join-Path $work 'Game with spaces'
$tp=Join-Path $work 'TeknoParrot with spaces'
New-Item -ItemType Directory -Path $game,(Join-Path $tp 'UserProfiles') | Out-Null
Copy-Item -LiteralPath $OriginalGlide -Destination (Join-Path $game 'Glide2x.dll')
Copy-Item -LiteralPath $BezelPath -Destination (Join-Path $game 'bezel.png')
$originalBezelHash=(Get-FileHash -LiteralPath (Join-Path $game 'bezel.png')).Hash
$profile=Join-Path $tp 'UserProfiles\HydroThunder.xml'
$xml='<GameProfile><GamePath>'+[Security.SecurityElement]::Escape((Join-Path $game 'HYDRO_x64_LAN.exe'))+'</GamePath><ConfigValues><FieldInformation><CategoryName>Bezel</CategoryName><FieldName>Enable</FieldName><FieldValue>1</FieldValue></FieldInformation></ConfigValues><ControlBinding>KEEP</ControlBinding></GameProfile>'
[IO.File]::WriteAllText($profile,$xml)
$save=Join-Path $game 'CMOS.bin'
[IO.File]::WriteAllBytes($save,[Text.Encoding]::ASCII.GetBytes('Synthetic untouched save sentinel'))
$saveHash=(Get-FileHash -LiteralPath $save).Hash
$recovery=Join-Path $game 'HydroSave.last-good.bin'
[IO.File]::WriteAllBytes($recovery,[Text.Encoding]::ASCII.GetBytes('Synthetic untouched recovery sentinel'))
$recoveryHash=(Get-FileHash -LiteralPath $recovery).Hash
$glideHash=(Get-FileHash -LiteralPath (Join-Path $game 'Glide2x.dll')).Hash
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Check([bool]$Condition,[string]$Name) { if(-not $Condition) { throw ('FAIL: '+$Name) }; $checks.Add($Name); Write-Host ('PASS: '+$Name) }
# These isolated fixture folders contain no running programs. Mock only the
# process-presence preflight; actual installation and restoration use the real filesystem.
function Get-Process { param($Name,$ErrorAction); return @() }
& (Join-Path $package 'Install-HydroFixes.ps1') -GameDirectory $game -TeknoParrotDirectory $tp -CheckOnly
Assert-Check (-not (Test-Path -LiteralPath (Join-Path $game 'HydroFixes.install.json'))) 'Preflight creates no installation'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $game 'Glide2x.dll')).Hash -eq $glideHash) 'Preflight preserves wrapper'
& (Join-Path $package 'Install-HydroFixes.ps1') -GameDirectory $game -TeknoParrotDirectory $tp
Assert-Check ((Get-FileHash -LiteralPath $save).Hash -eq $saveHash) 'Install never touches saved scores'
$installedManifest=Get-Content -LiteralPath (Join-Path $game 'HydroFixes.install.json') -Raw | ConvertFrom-Json
Assert-Check ($installedManifest.Version -eq '1.2.0') 'Manifest records release 1.2.0'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $installedManifest.BackupDirectory 'CMOS.bin.preinstall')).Hash -eq $saveHash) 'Existing scores backed up before installation'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $installedManifest.BackupDirectory 'HydroSave.last-good.bin.preinstall')).Hash -eq $recoveryHash) 'Existing recovery copy backed up before installation'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $game 'Glide2x.dll')).Hash -ne $glideHash) 'Save import installed'
Assert-Check ((Get-Content -LiteralPath $profile -Raw).Contains('<FieldValue>0</FieldValue>')) 'Native bezel disabled'
Assert-Check ((Get-Content -LiteralPath $profile -Raw).Contains('<ControlBinding>KEEP</ControlBinding>')) 'Controls preserved'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $game 'bezel.png')).Hash -eq $bundledHash) 'Bundled artwork installed unchanged in game root'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $game 'reshade-shaders\Textures\bezel.png')).Hash -eq $bundledHash) 'Bundled artwork installed unchanged as texture'
$rejected=$false
try { & (Join-Path $package 'Install-HydroFixes.ps1') -GameDirectory $game -Components Save } catch { $rejected=$true }
Assert-Check $rejected 'Double installation rejected'
# Normal application rewrites must not make rollback destroy later control edits.
[IO.File]::AppendAllText((Join-Path $game 'ReShade.ini'),"`r`n; normal application rewrite`r`n")
[IO.File]::WriteAllText($profile,(Get-Content -LiteralPath $profile -Raw).Replace('KEEP','LATER-CONTROLS'))
& (Join-Path $package 'Uninstall-HydroFixes.ps1') -GameDirectory $game
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $game 'Glide2x.dll')).Hash -eq $glideHash) 'Original wrapper restored'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $game 'bezel.png')).Hash -eq $originalBezelHash) 'Original root artwork restored'
Assert-Check ((Get-Content -LiteralPath $profile -Raw).Contains('<FieldValue>1</FieldValue>')) 'Previous native bezel restored'
Assert-Check ((Get-Content -LiteralPath $profile -Raw).Contains('LATER-CONTROLS')) 'Later control edits preserved on uninstall'
Assert-Check (-not (Test-Path -LiteralPath (Join-Path $game 'HydroSave.dll'))) 'Only added save helper removed'
Assert-Check (-not (Test-Path -LiteralPath (Join-Path $game 'd3d11.dll'))) 'Only added ReShade proxy removed'
Assert-Check ((Get-FileHash -LiteralPath $save).Hash -eq $saveHash) 'Uninstall never touches saved scores'
Assert-Check ((Get-FileHash -LiteralPath $recovery).Hash -eq $recoveryHash) 'Uninstall preserves the recovery copy'
Assert-Check (@(Get-ChildItem -LiteralPath $game -Recurse -Filter 'ReShade.ini.postinstall-*').Count -eq 1) 'ReShade runtime settings preserved in backup'
# An unsupported wrapper must fail before creating a backup or helper.
$glidePath=Join-Path $game 'Glide2x.dll'
$bad=[IO.File]::ReadAllBytes($glidePath);$bad[100]=$bad[100] -bxor 1;[IO.File]::WriteAllBytes($glidePath,$bad)
$rejected=$false
try { & (Join-Path $package 'Install-HydroFixes.ps1') -GameDirectory $game -Components Save } catch { $rejected=$true }
Assert-Check $rejected 'Unknown wrapper rejected'
Assert-Check (-not (Test-Path -LiteralPath (Join-Path $game 'HydroSave.dll'))) 'Rejected installation makes no helper'

# New 1.2.0 artwork cases use only synthetic images and isolated fixture folders.
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path).Hash }
function Snapshot([string]$Root) {
    return (@(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $relative=$_.FullName.Substring($Root.Length)
        if($_.PSIsContainer) { 'DIR '+$relative } else { 'FILE '+$relative+' '+(Hash $_.FullName) }
    }) -join "`n")
}
function New-Fixture([string]$Name) {
    $root=Join-Path $work $Name
    $fixtureGame=Join-Path $root 'Game with spaces'
    $fixtureTp=Join-Path $root 'TeknoParrot with spaces'
    New-Item -ItemType Directory -Path $fixtureGame,(Join-Path $fixtureTp 'UserProfiles') -Force | Out-Null
    Copy-Item -LiteralPath $OriginalGlide -Destination (Join-Path $fixtureGame 'Glide2x.dll')
    $fixtureProfile=Join-Path $fixtureTp 'UserProfiles\HydroThunder.xml'
    $fixtureXml='<GameProfile><GamePath>'+[Security.SecurityElement]::Escape((Join-Path $fixtureGame 'HYDRO_x64_LAN.exe'))+'</GamePath><ConfigValues><FieldInformation><CategoryName>Bezel</CategoryName><FieldName>Enable</FieldName><FieldValue>1</FieldValue></FieldInformation></ConfigValues><ControlBinding>KEEP</ControlBinding></GameProfile>'
    [IO.File]::WriteAllText($fixtureProfile,$fixtureXml)
    $fixtureSave=Join-Path $fixtureGame 'CMOS.bin'
    [IO.File]::WriteAllBytes($fixtureSave,[Text.Encoding]::ASCII.GetBytes('Synthetic untouched score sentinel'))
    return [pscustomobject]@{
        Root=$root; Game=$fixtureGame; TP=$fixtureTp; Profile=$fixtureProfile; ProfileHash=(Hash $fixtureProfile);
        RootBezel=(Join-Path $fixtureGame 'bezel.png'); TextureBezel=(Join-Path $fixtureGame 'reshade-shaders\Textures\bezel.png');
        Save=$fixtureSave; SaveHash=(Hash $fixtureSave)
    }
}
function New-PngFixture([string]$Path,[int]$Width,[int]$Height,[System.Drawing.Color]$Color) {
    $bitmap=New-Object System.Drawing.Bitmap($Width,$Height)
    $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
    try { $graphics.Clear($Color); $bitmap.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
}
$installer=Join-Path $package 'Install-HydroFixes.ps1'
$uninstaller=Join-Path $package 'Uninstall-HydroFixes.ps1'
Add-Type -AssemblyName System.Drawing
$fixtureImages=Join-Path $work 'Synthetic images'
New-Item -ItemType Directory -Path $fixtureImages | Out-Null
$custom=Join-Path $fixtureImages 'custom 1920x1080.png'
$previousRoot=Join-Path $fixtureImages 'previous root.png'
$previousTexture=Join-Path $fixtureImages 'previous texture.png'
$wrongSize=Join-Path $fixtureImages 'wrong 1280x720.png'
New-PngFixture $custom 1920 1080 ([System.Drawing.Color]::Magenta)
New-PngFixture $previousRoot 1920 1080 ([System.Drawing.Color]::Red)
New-PngFixture $previousTexture 1920 1080 ([System.Drawing.Color]::Blue)
New-PngFixture $wrongSize 1280 720 ([System.Drawing.Color]::Transparent)
$customHash=Hash $custom
$rootHash=Hash $previousRoot
$textureHash=Hash $previousTexture

$fresh=New-Fixture 'Fresh bundled artwork'
$before=Snapshot $fresh.Root
& $installer -GameDirectory $fresh.Game -TeknoParrotDirectory $fresh.TP -CheckOnly
Assert-Check ((Snapshot $fresh.Root) -ceq $before) 'Fresh CheckOnly creates no files, directories, root bezel, or profile edits'
& $installer -GameDirectory $fresh.Game -TeknoParrotDirectory $fresh.TP
Assert-Check ((Hash $fresh.RootBezel) -eq $bundledHash -and (Hash $fresh.TextureBezel) -eq $bundledHash) 'Fresh install supplies both missing artwork files from bundled PNG'
& $uninstaller -GameDirectory $fresh.Game
Assert-Check (!(Test-Path -LiteralPath $fresh.RootBezel) -and !(Test-Path -LiteralPath $fresh.TextureBezel)) 'Uninstall removes both newly introduced artwork files'

$existing=New-Fixture 'Existing different artwork'
New-Item -ItemType Directory -Path (Split-Path -Parent $existing.TextureBezel) -Force | Out-Null
Copy-Item -LiteralPath $previousRoot -Destination $existing.RootBezel
Copy-Item -LiteralPath $previousTexture -Destination $existing.TextureBezel
$before=Snapshot $existing.Root
& $installer -GameDirectory $existing.Game -TeknoParrotDirectory $existing.TP -Components Bezel -CheckOnly
Assert-Check ((Snapshot $existing.Root) -ceq $before) 'Existing images and profile unchanged by preflight'
& $installer -GameDirectory $existing.Game -TeknoParrotDirectory $existing.TP -Components Bezel
$manifest=Get-Content -LiteralPath (Join-Path $existing.Game 'HydroFixes.install.json') -Raw | ConvertFrom-Json
$rootEntry=$manifest.Files | Where-Object { $_.Target -eq $existing.RootBezel }
$textureEntry=$manifest.Files | Where-Object { $_.Target -eq $existing.TextureBezel }
Assert-Check ($rootEntry.Existed -and (Hash $rootEntry.Backup) -eq $rootHash) 'Existing root image backed up exactly'
Assert-Check ($textureEntry.Existed -and (Hash $textureEntry.Backup) -eq $textureHash) 'Existing texture image backed up exactly in separate backup'
& $uninstaller -GameDirectory $existing.Game
Assert-Check ((Hash $existing.RootBezel) -eq $rootHash -and (Hash $existing.TextureBezel) -eq $textureHash) 'Uninstall restores both different previous images'

$customCase=New-Fixture 'Custom image option'
& $installer -GameDirectory $customCase.Game -TeknoParrotDirectory $customCase.TP -Components Bezel -BezelPath $custom
Assert-Check ($customHash -ne $bundledHash -and (Hash $customCase.RootBezel) -eq $customHash -and (Hash $customCase.TextureBezel) -eq $customHash) 'Custom BezelPath overrides bundled PNG exactly at both targets'
Copy-Item -LiteralPath $previousRoot -Destination $customCase.RootBezel -Force
$before=Snapshot $customCase.Root; $rejected=$false
try { & $uninstaller -GameDirectory $customCase.Game } catch { $rejected=$true }
Assert-Check ($rejected -and (Snapshot $customCase.Root) -ceq $before) 'Changed root artwork refuses uninstall before any restoration'
Copy-Item -LiteralPath $custom -Destination $customCase.RootBezel -Force
Copy-Item -LiteralPath $previousTexture -Destination $customCase.TextureBezel -Force
$before=Snapshot $customCase.Root; $rejected=$false
try { & $uninstaller -GameDirectory $customCase.Game } catch { $rejected=$true }
Assert-Check ($rejected -and (Snapshot $customCase.Root) -ceq $before) 'Changed texture artwork refuses uninstall before any restoration'
Copy-Item -LiteralPath $custom -Destination $customCase.TextureBezel -Force
& $uninstaller -GameDirectory $customCase.Game
Assert-Check (!(Test-Path -LiteralPath $customCase.RootBezel) -and !(Test-Path -LiteralPath $customCase.TextureBezel)) 'Uninstall removes unmodified custom images it introduced'

$invalidCase=New-Fixture 'Invalid PNG rejection'
$invalidFiles=New-Object 'System.Collections.Generic.List[object]'
$path=Join-Path $fixtureImages 'not png.bin'; [IO.File]::WriteAllText($path,'Not a PNG')
$invalidFiles.Add([pscustomobject]@{Path=$path;Name='Non-PNG input'})
$path=Join-Path $fixtureImages 'signature only.png'; [IO.File]::WriteAllBytes($path,[byte[]](137,80,78,71,13,10,26,10))
$invalidFiles.Add([pscustomobject]@{Path=$path;Name='Truncated PNG'})
$bytes=[IO.File]::ReadAllBytes($custom); $bytes[29]=$bytes[29] -bxor 1
$path=Join-Path $fixtureImages 'bad crc.png'; [IO.File]::WriteAllBytes($path,$bytes)
$invalidFiles.Add([pscustomobject]@{Path=$path;Name='Corrupt PNG chunk checksum'})
$bytes=[IO.File]::ReadAllBytes($custom)
$path=Join-Path $fixtureImages 'missing end.png'; [IO.File]::WriteAllBytes($path,$bytes[0..($bytes.Length-13)])
$invalidFiles.Add([pscustomobject]@{Path=$path;Name='PNG missing IEND'})
$invalidFiles.Add([pscustomobject]@{Path=$wrongSize;Name='Wrong PNG dimensions'})
$path=Join-Path $fixtureImages 'undecodable image.png'
# Independently generated PNG framing/CRCs, but an invalid zlib image payload.
[IO.File]::WriteAllBytes($path,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAB4AAAAQ4CAYAAADo08FDAAAACElEQVQAAAAAAAAAAO5IXYcAAAAASUVORK5CYII='))
$invalidFiles.Add([pscustomobject]@{Path=$path;Name='Undecodable PNG with valid chunk framing and checksums'})
foreach($invalid in $invalidFiles) {
    $before=Snapshot $invalidCase.Root; $rejected=$false
    try { & $installer -GameDirectory $invalidCase.Game -TeknoParrotDirectory $invalidCase.TP -BezelPath $invalid.Path } catch { $rejected=$true }
    Assert-Check ($rejected -and (Snapshot $invalidCase.Root) -ceq $before) ($invalid.Name+' rejected before any write')
}

$saveOnly=New-Fixture 'Save only preserves artwork'
New-Item -ItemType Directory -Path (Split-Path -Parent $saveOnly.TextureBezel) -Force | Out-Null
Copy-Item -LiteralPath $previousRoot -Destination $saveOnly.RootBezel
Copy-Item -LiteralPath $previousTexture -Destination $saveOnly.TextureBezel
& $installer -GameDirectory $saveOnly.Game -Components Save -BezelPath (Join-Path $work 'does-not-exist.png')
Assert-Check ((Hash $saveOnly.RootBezel) -eq $rootHash -and (Hash $saveOnly.TextureBezel) -eq $textureHash) 'Save-only never reads or changes bezel files'
Assert-Check ((Hash $saveOnly.Profile) -eq $saveOnly.ProfileHash -and (Hash $saveOnly.Save) -eq $saveOnly.SaveHash) 'Save-only preserves controls/profile and saved scores'
& $uninstaller -GameDirectory $saveOnly.Game
Assert-Check ((Hash $saveOnly.RootBezel) -eq $rootHash -and (Hash $saveOnly.TextureBezel) -eq $textureHash) 'Save-only uninstall leaves both artwork files untouched'
Assert-Check ((Hash $bundled) -eq $bundledHash -and (Hash $OriginalGlide) -eq $glideHash) 'Bundled artwork and original reference wrapper remain unchanged'
$checks | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $work 'results.json') -Encoding UTF8
Write-Host ($checks.Count.ToString()+' installer checks passed.')
