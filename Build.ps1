param(
    [Parameter(Mandatory = $true)]
    [string]$DivinePath,
    [string]$Destination = (Join-Path $PSScriptRoot 'RemoteResurrection_397de034-e6ad-4aad-8b89-1dbb7b5bda9a.pak')
)
$ErrorActionPreference = 'Stop'
$packer = (Resolve-Path -LiteralPath $DivinePath).Path
$sourceMods = Join-Path $PSScriptRoot 'source\Mods'
if (-not (Test-Path -LiteralPath $sourceMods)) { throw 'The source\Mods folder is missing.' }
$stage = Join-Path $PSScriptRoot ('work\build-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -LiteralPath $sourceMods -Destination $stage -Recurse
$output = [System.IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
# LSLib 1.15.15's CLI omits the AllowMemoryMapping flag used by the game's
# published add-ons. Use that release's library API to set it explicitly.
$toolDirectory = Split-Path -Parent $packer
Add-Type -Path (Join-Path $toolDirectory 'LZ4.dll')
Add-Type -Path (Join-Path $toolDirectory 'LSLib.dll')
$modPackageOptions = New-Object LSLib.LS.PackageCreationOptions
$modPackageOptions.Version = [LSLib.LS.Enums.PackageVersion]::V13
$modPackageOptions.Compression = [LSLib.LS.Enums.CompressionMethod]::LZ4
$modPackageOptions.Flags = [LSLib.LS.PackageFlags]::AllowMemoryMapping
$modPackager = New-Object LSLib.LS.Packager
$modPackager.CreatePackage($output, $stage, $modPackageOptions)
Write-Host "Created $output"
Write-Host "Build staging files remain in $stage"
