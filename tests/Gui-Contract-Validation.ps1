<#
WindowsDeviceLink GUI contract validation.

This test is hardware-independent and does not open the GUI.
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

$command = Get-Command Show-WindowsDeviceLink -Module WindowsDeviceLink -ErrorAction Stop
$source = $command.ScriptBlock.ToString()

if ($command.Parameters.ContainsKey('WhatIf') -or $command.Parameters.ContainsKey('Confirm')) {
    throw 'FAIL: Show-WindowsDeviceLink itself must not expose mutation controls; state-changing actions are delegated to guarded cmdlets after explicit GUI confirmation.'
}

if (-not $command.Parameters.ContainsKey('Method')) {
    throw 'FAIL: Show-WindowsDeviceLink must expose -Method.'
}
if (-not $command.Parameters.ContainsKey('Tenants')) {
    throw 'FAIL: Show-WindowsDeviceLink must expose -Tenants.'
}
if (-not $command.Parameters.ContainsKey('TenantsUri')) {
    throw 'FAIL: Show-WindowsDeviceLink must expose -TenantsUri.'
}
if (-not $command.Parameters.ContainsKey('TenantsPath')) {
    throw 'FAIL: Show-WindowsDeviceLink must expose -TenantsPath.'
}
if (-not $command.Parameters.ContainsKey('WindowsManagementServicePath')) {
    throw 'FAIL: Show-WindowsDeviceLink must expose -WindowsManagementServicePath for Windows PE runtime selection.'
}
foreach ($parameterName in @('BackendUri','BackendApiKey','ViewMode')) {
    if (-not $command.Parameters.ContainsKey($parameterName)) { throw "FAIL: Show-WindowsDeviceLink must expose -$parameterName." }
}
if ($command.Parameters['BackendApiKey'].ParameterType -ne [securestring]) {
    throw 'FAIL: Show-WindowsDeviceLink -BackendApiKey must be SecureString.'
}
if ($command.Parameters['Tenants'].ParameterType -ne [hashtable]) {
    throw 'FAIL: Show-WindowsDeviceLink -Tenants must remain a hashtable.'
}
if ($command.Parameters['TenantsUri'].ParameterType -ne [uri]) {
    throw 'FAIL: Show-WindowsDeviceLink -TenantsUri must remain a URI.'
}

$methodParameter = $command.Parameters['Method']
$validateSet = @($methodParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1)
if (-not $validateSet -or 'Interactive' -notin $validateSet.ValidValues) {
    throw 'FAIL: Show-WindowsDeviceLink -Method must continue to support Interactive.'
}

$methodParameterAst = $command.ScriptBlock.Ast.FindAll(
    {
        param($ast)

        $ast -is [System.Management.Automation.Language.ParameterAst] -and
        $ast.Name.VariablePath.UserPath -eq 'Method'
    },
    $true
) | Select-Object -First 1

if (-not $methodParameterAst) {
    throw 'FAIL: Show-WindowsDeviceLink Method parameter AST could not be resolved.'
}

if ($methodParameterAst.DefaultValue) {
    throw 'FAIL: Show-WindowsDeviceLink -Method must not have a static parameter default; the GUI resolves the default by environment.'
}

$environmentAwareDefault = '$Method = if ($isWinPE) { ''DeviceCode'' } else { ''Interactive'' }'
if ($source -notmatch [regex]::Escape($environmentAwareDefault)) {
    throw 'FAIL: Show-WindowsDeviceLink must default to DeviceCode in Windows PE and Interactive on full Windows when -Method is omitted.'
}


foreach ($required in @(
    'System.Windows.Forms',
    'ShowDialog',
    'MiniNT',
    'Get-GuiRuntimeParameters',
    'Set-GuiCapabilities',
    'TenantsUri',
    'TenantsPath',
    'Get-WindowsDeviceLinkTenantCatalog',
    'WindowsManagementServicePath',
    'Windows PE',
    'Full registration is not available in Windows PE',
    'Get-WindowsDeviceLinkLocalAssociation',
    'Get-WindowsDeviceLinkStatus',
    'Get-WindowsDeviceLink',
    'Initialize-WindowsDeviceLink',
    'Remove-WindowsDeviceLinkAssociation',
    'Reset-WindowsDeviceLinkFirmwareState',
    'FullAssociation',
    'Full DeviceLink offboarding',
    'No cloud association was found. Nothing was removed.',
    'Set-WindowsDeviceLinkTenant',
    'Get-WindowsDeviceLinkBackendTenant',
    'Backend mode',
    'Direct mode',
    'Tenant determined by sign-in',
    'Local association',
    'Cloud association',
    "-Title 'Connection'",
    "-Caption 'Manufacturer'",
    "-Caption 'Operating system'",
    "-Caption 'Tenant scope'",
    'Tenant assignment',
    'Status and export',
    'Offboarding',
    'Last checked',
    'Target tenant',
    'Pre-register',
    'Full register',
    'Remove cloud',
    'Reset local',
    'Remove both',
    'Sign in',
    'Switch account',
    '$usesInteractiveUserAuthentication',
    'Non-interactive',
    'Invoke-GuiSignIn',
    'Signed out',
    'Signed in; cloud association loaded',
    'Local state loaded; sign in to check the cloud association',
    'WdlGuiSessionAccessToken',
    'WdlGuiSessionTenantId',
    'WdlGuiSessionExpiresUtc',
    'Clear-GuiSessionAuthentication',
    "Method = 'AccessToken'",
    'Authenticating once for this Direct-mode UI session.',
    'the in-memory token will be reused for cloud actions.',
    'Target tenant changed; sign in again to create a Direct-mode session for the selected tenant.',
    'Select a target tenant before signing in or performing a cloud action.',
    'Direct mode uses either one explicit -TenantId or a tenant catalog; do not combine them.',
    '$hasDirectTenantCatalog',
    '$showTenantSelector',
    'The destination tenant is determined by sign-in',
    '$activityCard.Height = $activityHeight',
    '$btnAssign.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard',
    'New-GuiFont',
    '$colorDeviceTint',
    '$colorCloudTint',
    '$colorConnectionAccent',
    '$colorLocalAccent',
    "'Tahoma'",
    "'Assets\WindowsDeviceLink.ico'"
)) {
    if ($source -notmatch [regex]::Escape($required)) {
        throw "FAIL: Show-WindowsDeviceLink is missing expected GUI/delegation contract '$required'."
    }
}

foreach ($forbidden in @(
    'Invoke-MgGraphRequest',
    'Invoke-WindowsDeviceLinkGraphGet',
    'SetFirmwareEnvironmentVariable',
    'importTenantAssociatedDevice'
)) {
    if ($source -match [regex]::Escape($forbidden)) {
        throw "FAIL: Show-WindowsDeviceLink contains direct lifecycle/backend implementation '$forbidden' instead of delegating to public cmdlets."
    }
}

if ($source -match [regex]::Escape('PlaceholderText')) {
    throw 'FAIL: GUI uses TextBox.PlaceholderText, which is not compatible with Windows PowerShell 5.1 / .NET Framework WinForms.'
}

if ($source -match [regex]::Escape('Show-WindowsDeviceLink is not supported in Windows PE yet')) {
    throw 'FAIL: Show-WindowsDeviceLink must not hard-block Windows PE.'
}

$fullAssociationGuardPattern = '(?s)\$canFullAssociation\s*=\s*\$runtimeReady\s*-and\s*\[string\]\$support\.Environment\s*-ne\s*''WindowsPE'''
if ($source -notmatch $fullAssociationGuardPattern) {
    throw 'FAIL: Full association must remain capability-disabled in Windows PE.'
}

if ($source -notmatch '(?s)\$btnFullAssociate\.Enabled\s*=.*\$canFullAssociation') {
    throw 'FAIL: Full register button must use the Windows PE-aware full-association capability.'
}

if ($source -notmatch '(?s)if \(\$backendMode\).*Set-WindowsDeviceLinkTenant.*Complete-WindowsDeviceLinkAssociation') {
    throw 'FAIL: Backend full registration must ensure tenant assignment before completing the local association.'
}

foreach ($requiredPolish in @(
    'cloudKnownAbsent',
    'alreadyFullyAssociated',
    "-Caption 'Link ID'",
    "-Caption 'Created'",
    "'RegistrationResult'",
    "'BeforeStatus'",
    "'AfterStatus'",
    "'FullAssociationDetails'"
)) {
    if ($source -notmatch [regex]::Escape($requiredPolish)) {
        throw "FAIL: Show-WindowsDeviceLink is missing expected GUI polish contract '$requiredPolish'."
    }
}

Write-Host 'PASS: Show-WindowsDeviceLink is exported, WinPE-aware, WinForms-based, runtime-path capable, and delegates lifecycle actions to existing cmdlets.'
