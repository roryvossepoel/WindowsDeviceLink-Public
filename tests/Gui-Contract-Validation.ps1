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
if ($command.Parameters['Tenants'].ParameterType -ne [hashtable]) {
    throw 'FAIL: Show-WindowsDeviceLink -Tenants must remain a hashtable.'
}

$methodParameter = $command.Parameters['Method']
$validateSet = @($methodParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1)
if (-not $validateSet -or 'Interactive' -notin $validateSet.ValidValues) {
    throw 'FAIL: Show-WindowsDeviceLink -Method must continue to support Interactive.'
}

$paramBlockText = $command.ScriptBlock.Ast.ParamBlock.Extent.Text
if ($paramBlockText -notmatch "\[string\]\$Method\s*=\s*'Interactive'") {
    throw 'FAIL: Show-WindowsDeviceLink must keep Interactive as the default authentication method.'
}


foreach ($required in @(
    'System.Windows.Forms',
    'ShowDialog',
    'MiniNT',
    'Get-WindowsDeviceLinkLocalAssociation',
    'Get-WindowsDeviceLinkStatus',
    'Get-WindowsDeviceLink',
    'Initialize-WindowsDeviceLink',
    'Remove-WindowsDeviceLinkAssociation',
    'Reset-WindowsDeviceLinkFirmwareState',
    'CompleteAssociation',
    'Full DeviceLink offboarding'
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

Write-Host 'PASS: Show-WindowsDeviceLink is exported, WinPE-guarded, WinForms-based, and delegates lifecycle actions to existing cmdlets.'
