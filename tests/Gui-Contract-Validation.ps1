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

foreach ($required in @(
    'System.Windows.Forms',
    'ShowDialog',
    'MiniNT',
    'Get-WindowsDeviceLinkLocalAssociation',
    'Get-WindowsDeviceLinkFirmwareState',
    'Get-WindowsDeviceLink',
    'Register-WindowsDeviceLink',
    'Complete-WindowsDeviceLinkAssociation',
    'Remove-WindowsDeviceLinkAssociation',
    'Reset-WindowsDeviceLinkFirmwareState'
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
