<#
Validates that Function backend requests receive the caller-selected timeout.
#>
[CmdletBinding()]
param([string]$ModulePath = (Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'))

$ErrorActionPreference = 'Stop'
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }

Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force
$module = Get-Module WindowsDeviceLink -ErrorAction Stop

$observed = & $module {
    $script:ObservedLookupTimeout = $null
    $response = Invoke-WindowsDeviceLinkBackendLookup `
        -BackendUri 'https://example.test/api/devicelink' `
        -BackendApiKey 'test-key' `
        -SerialNumber 'TEST-SERIAL' `
        -TimeoutSeconds 37 `
        -RequestScript {
            param($Uri,$Headers,$TimeoutSeconds)
            $script:ObservedLookupTimeout = $TimeoutSeconds
            [pscustomobject]@{ success=$true; matches=@(); tenants=@() }
        }
    [pscustomobject]@{ Timeout=$script:ObservedLookupTimeout; Success=$response.success }
}

Assert-True ($observed.Timeout -eq 37) 'Backend lookup did not pass -TimeoutSeconds to its request transport.'
Assert-True ($observed.Success -eq $true) 'Backend lookup timeout probe did not return its synthetic response.'

$lookupSource = & $module { (Get-Command Invoke-WindowsDeviceLinkBackendLookup).ScriptBlock.ToString() }
$catalogSource = & $module { (Get-Command Invoke-WindowsDeviceLinkBackendTenantCatalog).ScriptBlock.ToString() }
$reconcileSource = & $module { (Get-Command Invoke-WindowsDeviceLinkBackendReconcile).ScriptBlock.ToString() }
$offboardSource = & $module { (Get-Command Invoke-WindowsDeviceLinkBackendOffboard).ScriptBlock.ToString() }
$statusSource = & $module { (Get-Command Get-WindowsDeviceLinkBackendStatus).ScriptBlock.ToString() }
$assignmentSource = (Get-Command Set-WindowsDeviceLinkTenant -Module WindowsDeviceLink).ScriptBlock.ToString()
$guiSource = (Get-Command Show-WindowsDeviceLink -Module WindowsDeviceLink).ScriptBlock.ToString()

foreach ($contract in @(
    @{ Name='lookup'; Source=$lookupSource },
    @{ Name='tenant catalog'; Source=$catalogSource },
    @{ Name='reconcile'; Source=$reconcileSource },
    @{ Name='offboard'; Source=$offboardSource }
)) {
    Assert-True ($contract.Source -match 'TimeoutSec\s+\$TimeoutSeconds') "Backend $($contract.Name) transport doesn't apply -TimeoutSeconds to Invoke-RestMethod."
}

Assert-True ($statusSource -match 'TimeoutSeconds\s*=\s*\$TimeoutSeconds') 'Backend status does not forward its timeout to lookup.'
Assert-True ($assignmentSource -match 'Invoke-WindowsDeviceLinkBackendLookup[^\r\n]+-TimeoutSeconds\s+\$TimeoutSeconds') 'Tenant assignment does not forward its timeout to lookup.'
Assert-True ($assignmentSource -match 'reconcileParameters[^}]+TimeoutSeconds\s*=\s*\$TimeoutSeconds') 'Tenant assignment does not forward its timeout to reconcile.'
Assert-True ($guiSource -match '\[int\]\$TimeoutSeconds\s*=\s*120') 'The GUI does not expose a bounded backend timeout.'

Write-Host 'PASS: Function backend lookup, catalog, reconcile, offboarding, status, tenant assignment and GUI timeout contracts are wired.'
