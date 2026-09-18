<#
WindowsDeviceLink public module contract and Gallery-package regression validation.

This test is hardware-independent. It validates the exact staged module artifact and
must not require DeviceLink-capable hardware, firmware access, Graph credentials, or
a tenant.
#>

[CmdletBinding()]
param(
    [string]$ModulePath,
    [string]$PackageRoot
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Assert-EqualSet {
    param(
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string[]]$Actual,
        [Parameter(Mandatory)][string]$Name
    )

    $expectedSorted = @($Expected | Sort-Object -Unique)
    $actualSorted = @($Actual | Sort-Object -Unique)
    $difference = @(Compare-Object -ReferenceObject $expectedSorted -DifferenceObject $actualSorted)
    if ($difference.Count -gt 0) {
        $detail = ($difference | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; '
        throw "FAIL: $Name differs from the expected contract: $detail"
    }
}

if (-not $ModulePath) {
    $ModulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
}
$resolvedModulePath = (Resolve-Path -LiteralPath $ModulePath).Path

if (-not $PackageRoot) {
    $PackageRoot = Split-Path -Parent $resolvedModulePath
}
$resolvedPackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path

$expectedFunctions = @(
    'Complete-WindowsDeviceLinkAssociation'
    'Connect-WindowsDeviceLink'
    'Export-WindowsDeviceLinkCsv'
    'Get-WindowsDeviceLink'
    'Get-WindowsDeviceLinkAssociation'
    'Get-WindowsDeviceLinkFirmwareState'
    'Get-WindowsDeviceLinkDiscoveryPrerequisites'
    'Get-WindowsDeviceLinkRepairPlan'
    'Get-WindowsDeviceLinkStatus'
    'Get-WindowsDeviceLinkDiscoveryTrace'
    'Initialize-WindowsDeviceLink'
    'Register-WindowsDeviceLink'
    'Remove-WindowsDeviceLinkAssociation'
    'Reset-WindowsDeviceLinkFirmwareState'
    'Test-WindowsDeviceLinkAssociationJwt'
    'Test-WindowsDeviceLinkDiscovery'
    'Test-WindowsDeviceLinkHealth'
    'Test-WindowsDeviceLinkManagerRuntime'
    'Test-WindowsDeviceLinkPreflight'
    'Test-WindowsDeviceLinkRuntime'
    'Test-WindowsDeviceLinkSupport'
)

$manifest = Test-ModuleManifest -Path $resolvedModulePath -ErrorAction Stop
Assert-True ($manifest.PowerShellVersion -eq [version]'5.1') 'manifest PowerShellVersion must remain 5.1.'
Assert-EqualSet -Expected $expectedFunctions -Actual @($manifest.ExportedFunctions.Keys) -Name 'manifest exported functions'
Write-Host 'PASS: module manifest and exported function contract'

$forbiddenDll = Join-Path $resolvedPackageRoot 'Runtime\Windows.Management.Service.dll'
Assert-True (-not (Test-Path -LiteralPath $forbiddenDll)) 'Gallery/staged package contains forbidden Windows.Management.Service.dll.'
Assert-True (Test-Path -LiteralPath (Join-Path $resolvedPackageRoot 'Runtime\README.md') -PathType Leaf) 'Runtime README is missing from the staged package.'
Write-Host 'PASS: package runtime safety boundary'

Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModulePath -Force -ErrorAction Stop
$loaded = Get-Module WindowsDeviceLink | Select-Object -First 1
Assert-True ($null -ne $loaded) 'WindowsDeviceLink did not load.'
$expectedRootModulePath = (Join-Path $resolvedPackageRoot 'WindowsDeviceLink.psm1')
Assert-True ($loaded.ModuleBase -eq $resolvedPackageRoot) "loaded module base '$($loaded.ModuleBase)' does not match staged package root '$resolvedPackageRoot'."
Assert-True ($loaded.Path -eq $expectedRootModulePath) "loaded root module '$($loaded.Path)' does not match staged root module '$expectedRootModulePath'."
Write-Host 'PASS: exact requested module artifact imported'

$actualFunctions = @(Get-Command -Module WindowsDeviceLink -CommandType Function | Select-Object -ExpandProperty Name)
Assert-EqualSet -Expected $expectedFunctions -Actual $actualFunctions -Name 'runtime exported functions'
Write-Host 'PASS: runtime public command set'

$getLocal = Get-Command Get-WindowsDeviceLink
Assert-True (-not $getLocal.Parameters.ContainsKey('Online')) 'Get-WindowsDeviceLink unexpectedly exposes -Online.'
Write-Host 'PASS: local DeviceLink retrieval has no -Online parameter'

foreach ($name in @('Get-WindowsDeviceLinkDiscoveryPrerequisites','Get-WindowsDeviceLinkRepairPlan','Test-WindowsDeviceLinkPreflight','Test-WindowsDeviceLinkAssociationJwt','Test-WindowsDeviceLinkDiscovery','Test-WindowsDeviceLinkRuntime','Test-WindowsDeviceLinkManagerRuntime')) {
    $command = Get-Command $name
    Assert-True (-not $command.Parameters.ContainsKey('WhatIf')) "$name must remain read-only and must not expose -WhatIf."
    Assert-True (-not $command.Parameters.ContainsKey('Confirm')) "$name must remain read-only and must not expose -Confirm."
}
Write-Host 'PASS: planner, preflight, JWT validation, discovery, and runtime probe remain read-only'

$writeCommands = @(
    'Complete-WindowsDeviceLinkAssociation'
    'Initialize-WindowsDeviceLink'
    'Register-WindowsDeviceLink'
    'Remove-WindowsDeviceLinkAssociation'
    'Reset-WindowsDeviceLinkFirmwareState'
)
foreach ($name in $writeCommands) {
    $command = Get-Command $name
    Assert-True ($command.Parameters.ContainsKey('WhatIf')) "$name does not expose -WhatIf / SupportsShouldProcess."
    Assert-True ($command.Parameters.ContainsKey('Confirm')) "$name does not expose -Confirm / SupportsShouldProcess."
}
Write-Host 'PASS: state-changing commands expose ShouldProcess controls'

$secureParameters = @(
    @{ Command='Connect-WindowsDeviceLink'; Parameter='AccessToken' },
    @{ Command='Get-WindowsDeviceLinkAssociation'; Parameter='AccessToken' },
    @{ Command='Get-WindowsDeviceLinkStatus'; Parameter='AccessToken' },
    @{ Command='Initialize-WindowsDeviceLink'; Parameter='AccessToken' },
    @{ Command='Register-WindowsDeviceLink'; Parameter='AccessToken' },
    @{ Command='Remove-WindowsDeviceLinkAssociation'; Parameter='AccessToken' }
)
foreach ($item in $secureParameters) {
    $command = Get-Command $item.Command
    Assert-True ($command.Parameters.ContainsKey($item.Parameter)) "$($item.Command) is missing -$($item.Parameter)."
    Assert-True ($command.Parameters[$item.Parameter].ParameterType -eq [securestring]) "$($item.Command) -$($item.Parameter) must remain SecureString."
}
Write-Host 'PASS: access-token parameters remain SecureString'

$moduleData = Import-PowerShellDataFile -Path $resolvedModulePath
Assert-True ([string]$moduleData.PrivateData.PSData.ProjectUri -eq 'https://github.com/roryvossepoel/WindowsDeviceLink-Public') 'ProjectUri does not point to the canonical public repository.'
Assert-True ([string]$moduleData.PrivateData.PSData.LicenseUri -like 'https://github.com/roryvossepoel/WindowsDeviceLink-Public/*') 'LicenseUri does not point to the canonical public repository.'
Write-Host 'PASS: package provenance metadata points to the public repository'

Write-Host ''
Write-Host 'Public module contract regression set passed.'
