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
if (-not $command.Parameters.ContainsKey('WindowsManagementServicePath')) {
    throw 'FAIL: Show-WindowsDeviceLink must expose -WindowsManagementServicePath for Windows PE runtime selection.'
}
if ($command.Parameters['Tenants'].ParameterType -ne [hashtable]) {
    throw 'FAIL: Show-WindowsDeviceLink -Tenants must remain a hashtable.'
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

$methodDefault = if ($methodParameterAst.DefaultValue) {
    $methodParameterAst.DefaultValue.Extent.Text.Trim()
}
else {
    $null
}

if ($methodDefault -ne "'Interactive'") {
    throw "FAIL: Show-WindowsDeviceLink must keep Interactive as the default authentication method. Observed default: '$methodDefault'."
}


foreach ($required in @(
    'System.Windows.Forms',
    'ShowDialog',
    'MiniNT',
    'Get-GuiRuntimeParameters',
    'Set-GuiCapabilities',
    'WindowsManagementServicePath',
    'Windows PE',
    'Full association is not currently supported in Windows PE',
    'Get-WindowsDeviceLinkLocalAssociation',
    'Get-WindowsDeviceLinkStatus',
    'Get-WindowsDeviceLink',
    'Initialize-WindowsDeviceLink',
    'Remove-WindowsDeviceLinkAssociation',
    'Reset-WindowsDeviceLinkFirmwareState',
    'FullAssociation',
    'Full DeviceLink offboarding',
    'No cloud association was found. Nothing was removed.'
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

if ($source -notmatch '(?s)\$btnFullAssociate\.Enabled\s*=\s*\$canFullAssociation') {
    throw 'FAIL: Full associate button must use the Windows PE-aware full-association capability.'
}

Write-Host 'PASS: Show-WindowsDeviceLink is exported, WinPE-aware, WinForms-based, runtime-path capable, and delegates lifecycle actions to existing cmdlets.'
