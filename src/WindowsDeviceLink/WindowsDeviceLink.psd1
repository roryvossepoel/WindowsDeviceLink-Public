@{
    RootModule        = 'WindowsDeviceLink.psm1'
    ModuleVersion     = '0.4.4'
    GUID              = '776a2252-d4f4-495d-9445-ac3195ebbf46'
    Author            = 'Rory Vossepoel'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026 Rory Vossepoel. MIT License.'
    Description       = 'Generate TPM-backed DeviceLink identity information, inspect and reset local DeviceLink firmware state, export the official Windows-generated .devicelink.csv, query/pre-associate/remove Microsoft Intune Device Association records for Windows Autopilot Device Preparation, and provide combined local/cloud diagnostics and non-destructive health assessment. Local DeviceLink identity, firmware state, and tenant-side Device Association are exposed as explicit separate operations.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop')
    FunctionsToExport = @(
        'Connect-WindowsDeviceLink'
        'Export-WindowsDeviceLinkCsv'
        'Get-WindowsDeviceLink'
        'Get-WindowsDeviceLinkAssociation'
        'Get-WindowsDeviceLinkFirmwareState'
        'Get-WindowsDeviceLinkStatus'
        'Register-WindowsDeviceLink'
        'Remove-WindowsDeviceLinkAssociation'
        'Reset-WindowsDeviceLinkFirmwareState'
        'Test-WindowsDeviceLinkHealth'
        'Test-WindowsDeviceLinkSupport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Windows', 'WinPE', 'Intune', 'Autopilot', 'DevicePreparation', 'DeviceLink', 'DeviceAssociation', 'Firmware', 'UEFI', 'Webhook')
            LicenseUri = 'https://github.com/roryvossepoel/WindowsDeviceLink-Public/blob/main/LICENSE'
            ProjectUri = 'https://github.com/roryvossepoel/WindowsDeviceLink-Public'
            Prerelease = 'preview1'
        }
    }
}
