<#
WindowsDeviceLink local tenant-correlation regression tests.

These tests are hardware-independent. They validate correlation precedence and
fail-closed behavior without reading firmware, registry state, or Microsoft Graph.
#>

[CmdletBinding()]
param([string]$ModulePath)

$ErrorActionPreference = 'Stop'

if (-not $ModulePath) {
    $ModulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
}

$resolvedModulePath = (Resolve-Path -LiteralPath $ModulePath).Path
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModulePath -Force -ErrorAction Stop
$module = Get-Module WindowsDeviceLink | Select-Object -First 1
if (-not $module) { throw 'FAIL: WindowsDeviceLink did not load.' }

$tenantA = '11111111-1111-1111-1111-111111111111'
$tenantB = '22222222-2222-2222-2222-222222222222'

$cases = @(
    @{ Name='BothMatch'; Registry=$tenantA; Jwt=$tenantA; Tenant=$tenantA; Match=$true; Source='RegistryAndAssociationJwt'; Trust='CorrelatedLocalSources'; Conflict=$false },
    @{ Name='RegistryOnly'; Registry=$tenantA; Jwt=$null; Tenant=$tenantA; Match=$null; Source='CurrentLinkIdRegistryHint'; Trust='LocalRegistryHint'; Conflict=$false },
    @{ Name='JwtOnly'; Registry=$null; Jwt=$tenantA; Tenant=$tenantA; Match=$null; Source='AssociationJwt'; Trust='StructurallyObservedJwtClaim'; Conflict=$false },
    @{ Name='Conflict'; Registry=$tenantA; Jwt=$tenantB; Tenant=$null; Match=$false; Source='Conflict'; Trust='Conflict'; Conflict=$true },
    @{ Name='Unavailable'; Registry=$null; Jwt=$null; Tenant=$null; Match=$null; Source='Unavailable'; Trust='Unavailable'; Conflict=$false }
)

foreach ($case in $cases) {
    $result = & $module {
        param($Registry,$Jwt)
        Resolve-WindowsDeviceLinkLocalTenantCorrelation -RegistryTenantId $Registry -JwtTenantId $Jwt
    } $case.Registry $case.Jwt

    if ($result.TenantId -ne $case.Tenant) { throw "FAIL: $($case.Name) TenantId mismatch." }
    if ($result.SourcesMatch -ne $case.Match) { throw "FAIL: $($case.Name) SourcesMatch mismatch." }
    if ($result.Source -ne $case.Source) { throw "FAIL: $($case.Name) Source mismatch." }
    if ($result.TrustLevel -ne $case.Trust) { throw "FAIL: $($case.Name) TrustLevel mismatch." }
    if ([bool]$result.Conflict -ne [bool]$case.Conflict) { throw "FAIL: $($case.Name) Conflict mismatch." }
    Write-Host "PASS: $($case.Name) -> $($result.Source) [$($result.TrustLevel)]"
}

$command = Get-Command Get-WindowsDeviceLinkLocalAssociation -Module WindowsDeviceLink -ErrorAction Stop
if ($command.Parameters.ContainsKey('WhatIf') -or $command.Parameters.ContainsKey('Confirm')) {
    throw 'FAIL: Get-WindowsDeviceLinkLocalAssociation must remain read-only.'
}

$scriptText = $command.ScriptBlock.ToString()
if ($scriptText -match 'Get-WindowsDeviceLinkAssociation\s' -or $scriptText -match 'Invoke-MgGraphRequest' -or $scriptText -match 'Connect-MgGraph') {
    throw 'FAIL: Get-WindowsDeviceLinkLocalAssociation unexpectedly contains a cloud/Graph path.'
}

Write-Host 'PASS: public local-association command remains read-only and cloud-independent'
Write-Host ''
Write-Host 'Local association regression set passed.'
