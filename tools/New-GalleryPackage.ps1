[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\src\WindowsDeviceLink'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\out')
)

$ErrorActionPreference = 'Stop'

$source = (Resolve-Path -LiteralPath $SourcePath).Path
$outputRootFull = [IO.Path]::GetFullPath($OutputRoot)
$packagePath = Join-Path $outputRootFull 'WindowsDeviceLink'

if (Test-Path -LiteralPath $packagePath) {
    Remove-Item -LiteralPath $packagePath -Recurse -Force
}

New-Item -ItemType Directory -Path $packagePath -Force | Out-Null

Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
    if ($_.Name -eq 'Runtime') {
        $runtimeDestination = Join-Path $packagePath 'Runtime'
        New-Item -ItemType Directory -Path $runtimeDestination -Force | Out-Null

        $runtimeReadme = Join-Path $_.FullName 'README.md'
        if (Test-Path -LiteralPath $runtimeReadme) {
            Copy-Item -LiteralPath $runtimeReadme -Destination $runtimeDestination -Force
        }
        return
    }

    Copy-Item -LiteralPath $_.FullName -Destination $packagePath -Recurse -Force
}

$forbiddenDll = Join-Path $packagePath 'Runtime\Windows.Management.Service.dll'
if (Test-Path -LiteralPath $forbiddenDll) {
    throw 'Packaging safety check failed: Windows.Management.Service.dll is present in the Gallery package.'
}

$manifest = Join-Path $packagePath 'WindowsDeviceLink.psd1'
Test-ModuleManifest -Path $manifest -ErrorAction Stop | Out-Null

Write-Host "Gallery package prepared: $packagePath"
Write-Host 'Verified: Windows.Management.Service.dll is NOT included.'
Write-Host ''
Write-Host 'Publish with:'
Write-Host "Publish-Module -Path '$packagePath' -Repository PSGallery -NuGetApiKey <api-key>"
