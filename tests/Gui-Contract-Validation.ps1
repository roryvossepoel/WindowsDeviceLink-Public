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
    'Association is not available in Windows PE',
    'btnAssociateHost',
    'Get-WindowsDeviceLinkLocalAssociation',
    'Get-GuiOperationParameters',
    'Get-WindowsDeviceLinkStatus',
    'Get-WindowsDeviceLink',
    'Initialize-WindowsDeviceLink',
    'Remove-WindowsDeviceLinkAssociation',
    'Reset-WindowsDeviceLinkFirmwareState',
    'Associate',
    'Full DeviceLink offboarding',
    'No cloud association was found. Nothing was removed.',
    'Set-WindowsDeviceLinkTenant',
    'RepairExistingAssociation',
    'Same-tenant repair required',
    'Invoke-WindowsDeviceLinkBackendOffboard',
    'Cloud offboarding completed and verified',
    'Full offboarding completed and verified',
    '$offboardingStatePresent = $cloudPresent -or $localAssociated',
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
    "'Caption:Endpoint'",
    'Device association',
    'Status',
    'Export',
    'Offboarding',
    'Last checked',
    'Activity log copied to clipboard.',
    '[System.Windows.Forms.Clipboard]::SetText($consoleBox.Text)',
    'Target tenant',
    'Pre-associate',
    'Associate',
    'Remove cloud',
    'Reset local',
    'Remove both',
    'Sign in',
    'Sign out',
    'Signing in...',
    'Waiting for sign-in...',
    '[switch]$Warning',
    'The sign-in window may open behind this window',
    "select 'No, this app only' to avoid registering this device",
    'Actions will target the signed-in tenant.',
    'Disconnect-MgGraph',
    'The authenticated tenant does not match the selected target tenant.',
    '$usesInteractiveUserAuthentication',
    'Non-interactive',
    'Invoke-GuiSignIn',
    'Signed out',
    'Interactive authentication did not complete.',
    'No authenticated Microsoft Graph context was returned.',
    'Signed in; cloud association check failed',
    'Signed in; cloud association loaded',
    'Local state loaded; sign in to check the cloud association',
    'WdlGuiSessionAccessToken',
    'WdlGuiSessionTenantId',
    'WdlGuiSessionAccountName',
    'WdlGuiSessionExpiresUtc',
    'Clear-GuiSessionAuthentication',
    'Clear-GuiSessionAuthentication -ForceGraphDisconnect',
    '[switch]$ForceGraphDisconnect',
    "Method = 'AccessToken'",
    "Write-GuiConsole -Message 'Authenticating once for this Direct-mode UI session.'",
    'the in-memory token will be reused for cloud actions.',
    'Target tenant changed; sign in again to create a Direct-mode session for the selected tenant.',
    'Select a target tenant before signing in or performing a cloud action.',
    'Direct mode uses either one explicit -TenantId or a tenant catalog; do not combine them.',
    '$hasDirectTenantCatalog',
    '$showTenantSelector',
    'Sign in to select the destination tenant.',
    '$targetTenantRow.Controls.Add($btnSignIn)',
    '$interactiveTenantReady',
    '-not ($usesInteractiveUserAuthentication -and $script:WdlGuiSessionAuthenticated)',
    '$targetTenantValue.Width = [Math]::Max(220,$targetValueRight - $targetTenantValue.Left)',
    '$activityCard.Height = $activityHeight',
    '$btnAssign.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard',
    'New-GuiFont',
    '$colorCardTint',
    '$colorCardAccent',
    "'Tahoma'",
    "'Assets\WindowsDeviceLink.ico'"
)) {
    if ($source -notmatch [regex]::Escape($required)) {
        throw "FAIL: Show-WindowsDeviceLink is missing expected GUI/delegation contract '$required'."
    }
}

$runtimeHelperPattern = '(?s)function\s+Get-GuiRuntimeParameters\s*\{(?<Body>.*?)\n\s*\}'
$runtimeHelperMatch = [regex]::Match($source,$runtimeHelperPattern)
if (-not $runtimeHelperMatch.Success) {
    throw 'FAIL: GUI runtime-parameter helper was not found.'
}
if ($runtimeHelperMatch.Groups['Body'].Value -match 'TimeoutSeconds') {
    throw 'FAIL: Runtime-only parameters must not pass -TimeoutSeconds to Test-WindowsDeviceLinkSupport.'
}

$operationHelperPattern = '(?s)function\s+Get-GuiOperationParameters\s*\{(?<Body>.*?)\n\s*\}'
$operationHelperMatch = [regex]::Match($source,$operationHelperPattern)
if (-not $operationHelperMatch.Success -or $operationHelperMatch.Groups['Body'].Value -notmatch 'TimeoutSeconds') {
    throw 'FAIL: Operation parameters must include the caller-selected timeout.'
}

foreach ($offboardingEnableContract in @(
    '$btnCloudOffboard.Enabled = $runtimeReady -and $cloudPresent',
    '$btnLocalOffboard.Enabled = $runtimeReady -and $localStatePresent -and $cloudKnownAbsent',
    '$btnFullOffboard.Enabled = $runtimeReady -and $offboardingStatePresent'
)) {
    if ($source -notmatch [regex]::Escape($offboardingEnableContract)) {
        throw "FAIL: GUI offboarding availability must be based on known removable state: '$offboardingEnableContract'."
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

foreach ($inconsistentCloudPlaceholder in @('Not checked yet','Not yet')) {
    if ($source -match [regex]::Escape($inconsistentCloudPlaceholder)) {
        throw "FAIL: Cloud association placeholders must consistently use 'Not checked', not '$inconsistentCloudPlaceholder'."
    }
}

foreach ($cloudField in @('CloudState','CloudTenant','CloudId','CloudChecked')) {
    if ($source -notmatch [regex]::Escape("`$ui.$cloudField.Text = `$cloudPendingText")) {
        throw "FAIL: Cloud association field '$cloudField' must use the shared pending state during lookup."
    }
}

foreach ($cloudPendingState in @('Waiting for sign-in...','Checking...')) {
    if ($source -notmatch [regex]::Escape($cloudPendingState)) {
        throw "FAIL: Cloud association pending state '$cloudPendingState' is missing."
    }
}

foreach ($localField in @('LocalState','Firmware','LinkId','LocalCreated')) {
    if ($source -notmatch [regex]::Escape("`$ui.$localField.Text = 'Not checked'")) {
        throw "FAIL: Local association field '$localField' must use the shared initial 'Not checked' state."
    }
    if ($source -notmatch [regex]::Escape("`$ui.$localField.Text = 'Checking...'")) {
        throw "FAIL: Local association field '$localField' must show the shared 'Checking...' state during refresh."
    }
}

if ($source -notmatch [regex]::Escape("-Title 'Status' -Description 'Refresh local or cloud state.' -Y 92 -Buttons @('Refresh cloud','Refresh local')")) {
    throw 'FAIL: Status actions must contain only cloud and local refresh, in the same order as Offboarding.'
}

if ($source -notmatch [regex]::Escape("-Title 'Export' -Description 'Export DeviceLink CSV for manual import in Intune.' -Y 138 -Buttons @('Export CSV')")) {
    throw 'FAIL: CSV export must use its own compact action row with the manual Intune import explanation.'
}

foreach ($layoutContract in @(
    '$targetTenantRow.Size = [System.Drawing.Size]::new(1030,46)',
    '$btnSignIn.Size = [System.Drawing.Size]::new(118,28)',
    '$assignmentRow.Size = [System.Drawing.Size]::new(1030,46)',
    '$tenantSelector.ItemHeight = 22',
    '$tenantSelector.Size = [System.Drawing.Size]::new(220,28)',
    '$actionsPanel.Height = 230'
)) {
    if ($source -notmatch [regex]::Escape($layoutContract)) {
        throw "FAIL: Unified action-row layout contract is missing '$layoutContract'."
    }
}

$associationGuardPattern = '(?s)\$canAssociate\s*=\s*\$runtimeReady\s*-and\s*\[string\]\$support\.Environment\s*-ne\s*''WindowsPE'''
if ($source -notmatch $associationGuardPattern) {
    throw 'FAIL: Association must remain capability-disabled in Windows PE.'
}

if ($source -notmatch '(?s)\$btnAssociate\.Enabled\s*=.*\$canAssociate') {
    throw 'FAIL: Associate button must use the Windows PE-aware association capability.'
}

if ($source -notmatch '(?s)if \(\$backendMode\).*Set-WindowsDeviceLinkTenant.*Complete-WindowsDeviceLinkAssociation') {
    throw 'FAIL: Backend association must ensure tenant assignment before completing the local association.'
}

foreach ($requiredPolish in @(
    'cloudKnownAbsent',
    'alreadyAssociated',
    "-Caption 'Link ID'",
    "-Caption 'Created'",
    "'RegistrationResult'",
    "'BeforeStatus'",
    "'AfterStatus'",
    "'AssociationDetails'"
)) {
    if ($source -notmatch [regex]::Escape($requiredPolish)) {
        throw "FAIL: Show-WindowsDeviceLink is missing expected GUI polish contract '$requiredPolish'."
    }
}

Write-Host 'PASS: Show-WindowsDeviceLink is exported, WinPE-aware, WinForms-based, runtime-path capable, and delegates lifecycle actions to existing cmdlets.'
