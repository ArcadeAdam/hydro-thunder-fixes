[CmdletBinding()]
param([string]$GameDirectory)
$ErrorActionPreference='Stop'
if(-not $GameDirectory) { $GameDirectory=Read-Host 'Hydro Thunder game folder' }
$gameDir=(Resolve-Path -LiteralPath $GameDirectory).Path.TrimEnd('\')
if(Get-Process -Name 'HYDRO','HYDRO_x64','HYDRO_x86','HYDRO_x64_LAN','TeknoParrotUi' -ErrorAction SilentlyContinue) { throw 'Close Hydro Thunder and TeknoParrot before uninstalling.' }
$manifestPath=Join-Path $gameDir 'HydroFixes.install.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if(-not [string]::Equals($manifest.GameDirectory,$gameDir,[StringComparison]::OrdinalIgnoreCase)) { throw 'Installation manifest does not match this folder.' }
$backupRoot=[IO.Path]::GetFullPath($manifest.BackupDirectory).TrimEnd('\')
if(-not [string]::Equals([IO.Path]::GetDirectoryName($backupRoot),$gameDir,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($backupRoot).StartsWith('HydroFixes-backup-',[StringComparison]::OrdinalIgnoreCase)) { throw 'Backup directory must be an installation backup inside the game folder.' }
$allowed=@('Glide2x.dll','HydroSave.dll','d3d11.dll','ReShade.ini','HydroBezel.ini','bezel.png','reshade-shaders\Shaders\HydroBezel.fx','reshade-shaders\Textures\bezel.png')
$profileRestores=@{}
$mutableCopies=New-Object 'System.Collections.Generic.List[object]'
foreach($entry in $manifest.Files) {
    $target=[IO.Path]::GetFullPath($entry.Target)
    $isGameFile=$false
    foreach($relative in $allowed) { if([string]::Equals($target,(Join-Path $gameDir $relative),[StringComparison]::OrdinalIgnoreCase)) { $isGameFile=$true } }
    $isProfile=([IO.Path]::GetFileName($target) -eq 'HydroThunder.xml') -and ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($target)) -eq 'UserProfiles')
    if(-not $isGameFile -and -not $isProfile) { throw ('Unexpected manifest target: '+$target) }
    if($entry.Existed) {
        $backup=[IO.Path]::GetFullPath($entry.Backup)
        if(-not [string]::Equals([IO.Path]::GetDirectoryName($backup),$backupRoot,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $backup)) { throw 'Backup path is invalid or missing.' }
    }
    if($isProfile) {
        if(-not (Test-Path -LiteralPath $target)) { throw 'The current HydroThunder profile is missing; restore it manually from the backup.' }
        $pattern='(<CategoryName>Bezel</CategoryName>\s*<FieldName>Enable</FieldName>\s*<FieldValue>)([01])(</FieldValue>)'
        $oldText=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($entry.Backup))
        $currentText=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($target))
        if([regex]::Matches($oldText,$pattern).Count -ne 1 -or [regex]::Matches($currentText,$pattern).Count -ne 1) { throw 'Cannot safely restore only the native bezel setting.' }
        $previousValue=[regex]::Match($oldText,$pattern).Groups[2].Value
        $restoredText=[regex]::Replace($currentText,$pattern,('${1}'+$previousValue+'${3}'))
        $profileRestores[$target]=[Text.Encoding]::UTF8.GetBytes($restoredText)
        continue
    }
    if((Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target).Hash -ne $entry.InstalledSha256) {
        if([IO.Path]::GetFileName($target) -in @('ReShade.ini','HydroBezel.ini')) {
            $mutableCopies.Add([pscustomobject]@{Source=$target;Destination=(Join-Path $manifest.BackupDirectory ([IO.Path]::GetFileName($target)+'.postinstall-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')))})
        } else { throw ('File changed since installation; preserve it and restore manually from the backup: '+$target) }
    }
}
foreach($copy in $mutableCopies) { Copy-Item -LiteralPath $copy.Source -Destination $copy.Destination }
foreach($entry in $manifest.Files) {
    if($profileRestores.ContainsKey($entry.Target)) { [IO.File]::WriteAllBytes($entry.Target,$profileRestores[$entry.Target]) }
    elseif($entry.Existed) { Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force }
    elseif(Test-Path -LiteralPath $entry.Target) { Remove-Item -LiteralPath $entry.Target }
}
Move-Item -LiteralPath $manifestPath -Destination ($manifestPath+'.uninstalled-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
Write-Host 'Previous files restored. CMOS.bin and diagnostic backups were preserved.'
