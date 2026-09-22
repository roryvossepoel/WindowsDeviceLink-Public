<#
WindowsDeviceLink authentication orchestration contract tests.
These are structural, hardware- and tenant-independent, and perform no authentication or network activity.
The behavioral DeviceCode reuse path is covered by the documented live smoke test.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'
function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force -ErrorAction Stop

$initialize=(Get-Command Initialize-WindowsDeviceLink -Module WindowsDeviceLink).ScriptBlock.ToString()
$connect=(Get-Command Connect-WindowsDeviceLink -Module WindowsDeviceLink).ScriptBlock.ToString()

$tokenAcquisitionCount=([regex]::Matches($initialize,'Get-WindowsDeviceLinkDeviceCodeToken')).Count
Assert-True ($tokenAcquisitionCount -eq 1) "Initializer must contain exactly one DeviceCode token acquisition; found $tokenAcquisitionCount."
Assert-True ($initialize -match "effectiveMethod\s*=\s*'AccessToken'") 'Initializer does not switch DeviceCode orchestration to AccessToken mode.'
Assert-True ($initialize -match 'effectiveAccessToken') 'Initializer does not retain the acquired token for reuse.'
Assert-True ($initialize -match 'commonOnline\.AccessToken\s*=\s*\$effectiveAccessToken') 'Initializer does not place the acquired token in the shared online parameter set.'
Assert-True ($initialize -match 'foreach\s*\(\$key\s+in\s+\$commonOnline\.Keys\)') 'Initializer does not copy the shared online parameter set into downstream operations.'
Assert-True ($initialize -match 'statusParameters\[\$key\]\s*=\s*\$commonOnline\[\$key\]') 'Status lookups do not inherit the shared AccessToken parameters.'
Assert-True ($initialize -match 'registerParameters\[\$key\]\s*=\s*\$commonOnline\[\$key\]') 'Registration does not inherit the shared AccessToken parameters.'
Assert-True (([regex]::Matches($initialize,'Get-WindowsDeviceLinkStatus')).Count -ge 2) 'Initializer must perform both pre-action and verification status reads.'
Assert-True ($initialize -match "ParameterSetName\s*=\s*'Backend'") 'Initializer is missing the Function backend parameter set.'
Assert-True ($initialize -match 'Get-WindowsDeviceLinkBackendStatus') 'Function-backed initialization does not use the backend status adapter.'
Assert-True ($initialize -match 'Resolve-WindowsDeviceLinkBackendEndpoint') 'Function-backed initialization does not resolve the preassociate endpoint from the backend base URI.'
Assert-True ($initialize -match 'AssociationInDifferentTenant') 'Function-backed initialization must explicitly block target-tenant mismatch.'
Write-Host 'PASS: DeviceCode initializer structural contract enforces single acquisition and shared AccessToken reuse'

Assert-True ($connect -match 'CertificateThumbprint') 'CertificateThumbprint parameter path is missing.'
Assert-True ($connect -match 'CertificateSubjectName') 'CertificateSubjectName parameter path is missing.'
Assert-True ($connect -match 'ClientSecretCredential') 'ClientSecret is not wrapped as ClientSecretCredential for SDK authentication.'
Assert-True ($connect -match 'System\.Management\.Automation\.PSCredential') 'ClientSecret credential wrapping is missing.'
Assert-True ($connect -match 'Identity\s*=\s*\$true') 'ManagedIdentity path does not set Identity.'
Assert-True ($connect -match 'Invoke-WindowsDeviceLinkGraphConnect') 'Connect-WindowsDeviceLink is not routed through the hardened SDK connection helper.'
Assert-True ($connect -notmatch '\$parameters\.ClientSecret\s*=') 'Plain ClientSecret is assigned directly into Connect-MgGraph parameters.'
Write-Host 'PASS: SDK authentication routing uses explicit safe parameter shapes'

Write-Host ''
Write-Host 'Authentication orchestration contract regression set passed.'
