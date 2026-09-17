<#
Validates that the read-only Discover/Link research probes parse in Windows PowerShell 5.1.
The tools are intentionally not executed in CI because the hosted runner is not a controlled
DeviceLink research target.
#>
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'

$files=@(
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkRuntimeInventory.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkRuntimeRegistration.ps1'),
    (Join-Path $PSScriptRoot '..\tools\Get-DeviceLinkCspInventory.ps1')
)

foreach($file in $files){
    $tokens=$null
    $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $file).Path,
        [ref]$tokens,
        [ref]$errors
    )
    if($errors.Count -gt 0){
        $detail=($errors|ForEach-Object{"$($_.Extent.Text): $($_.Message)"}) -join '; '
        throw "FAIL: research tool '$file' contains parser errors: $detail"
    }
    Write-Host "PASS: parsed $([IO.Path]::GetFileName($file))"
}

Write-Host ''
Write-Host 'Research tool syntax validation passed.'
