param([Parameter(Mandatory=$true)][string]$OriginalGlide,[Parameter(Mandatory=$true)][string]$BezelPath,[Parameter(Mandatory=$true)][string]$WorkDirectory)
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
if(Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new empty test directory.' }
$work=[IO.Path]::GetFullPath($WorkDirectory)
New-Item -ItemType Directory -Path $work | Out-Null
$game=Join-Path $work 'Game with spaces'
$tp=Join-Path $work 'TeknoParrot with spaces'
New-Item -ItemType Directory -Path $game,(Join-Path $tp 'UserProfiles') | Out-Null
Copy-Item -LiteralPath $OriginalGlide -Destination (Join-Path $game 'Glide2x.dll')
Copy-Item -LiteralPath $BezelPath -Destination (Join-Path $game 'bezel.png')
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
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $installedManifest.BackupDirectory 'CMOS.bin.preinstall')).Hash -eq $saveHash) 'Existing scores backed up before installation'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $installedManifest.BackupDirectory 'HydroSave.last-good.bin.preinstall')).Hash -eq $recoveryHash) 'Existing recovery copy backed up before installation'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $game 'Glide2x.dll')).Hash -ne $glideHash) 'Save import installed'
Assert-Check ((Get-Content -LiteralPath $profile -Raw).Contains('<FieldValue>0</FieldValue>')) 'Native bezel disabled'
Assert-Check ((Get-Content -LiteralPath $profile -Raw).Contains('<ControlBinding>KEEP</ControlBinding>')) 'Controls preserved'
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $game 'reshade-shaders\Textures\bezel.png')).Hash -eq (Get-FileHash -LiteralPath $BezelPath).Hash) 'Original artwork copied exactly'
$rejected=$false
try { & (Join-Path $package 'Install-HydroFixes.ps1') -GameDirectory $game -Components Save } catch { $rejected=$true }
Assert-Check $rejected 'Double installation rejected'
# Normal application rewrites must not make rollback destroy later control edits.
[IO.File]::AppendAllText((Join-Path $game 'ReShade.ini'),"`r`n; normal application rewrite`r`n")
[IO.File]::WriteAllText($profile,(Get-Content -LiteralPath $profile -Raw).Replace('KEEP','LATER-CONTROLS'))
& (Join-Path $package 'Uninstall-HydroFixes.ps1') -GameDirectory $game
Assert-Check ((Get-FileHash -LiteralPath (Join-Path $game 'Glide2x.dll')).Hash -eq $glideHash) 'Original wrapper restored'
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
$checks | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $work 'results.json') -Encoding UTF8
Write-Host ($checks.Count.ToString()+' installer checks passed.')
