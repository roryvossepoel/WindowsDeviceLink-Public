<#
Validates that the Discover/Link research probes parse in Windows PowerShell 5.1.
The tools are intentionally not executed in CI because the hosted runner is not a controlled
DeviceLink research target.
#>
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'

$files=@(
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkRuntimeInventory.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkRuntimeRegistration.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkCspInventory.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkIidBinaryContext.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkManagerRuntimeInventory.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkManagerVtableInventory.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkManagerVtableTargetInventory.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkWinRtMetadataInventory.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkRoMetadataContract.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Invoke-DeviceLinkDiscoveryResearch.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Invoke-DeviceLinkConfigureResearch.ps1')
)

foreach($file in $files){
    $resolved=(Resolve-Path -LiteralPath $file).Path
    $tokens=$null
    $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $resolved,
        [ref]$tokens,
        [ref]$errors
    )
    if($errors.Count -gt 0){
        $detail=($errors|ForEach-Object{"$($_.Extent.Text): $($_.Message)"}) -join '; '
        throw "FAIL: research tool '$file' contains parser errors: $detail"
    }

    $source=[IO.File]::ReadAllText($resolved)
    if($source -match '(?i)\$matches\b'){
        throw "FAIL: research tool '$file' uses `$matches, which collides with PowerShell's automatic `$Matches variable."
    }

    Write-Host "PASS: parsed $([IO.Path]::GetFileName($file)) without automatic-Matches collisions"
}

Write-Host ''
Write-Host 'Research tool syntax validation passed.'
