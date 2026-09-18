@{
    RootModule        = 'WindowsDeviceLink.psm1'
    ModuleVersion     = '0.5.1'
    GUID              = '776a2252-d4f4-495d-9445-ac3195ebbf46'
    Author            = 'Rory Vossepoel'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026 Rory Vossepoel. MIT License.'
    Description       = 'Generate TPM-backed DeviceLink identity information, inspect and reset local DeviceLink firmware state, export the official Windows-generated .devicelink.csv, query/pre-associate/remove Microsoft Intune Device Association records for Windows Autopilot Device Preparation, test native DeviceLink discovery, complete device-side association with guarded post-state verification, and provide combined diagnostics, health assessment, non-destructive repair planning, readiness preflight, safe Association JWT validation, and safe idempotent initialization. Local DeviceLink identity, firmware state, native association completion, and tenant-side Device Association are exposed as explicit separate operations.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop')
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Windows', 'WinPE', 'Intune', 'Autopilot', 'DevicePreparation', 'DeviceLink', 'DeviceAssociation', 'Firmware', 'UEFI', 'Webhook', 'TPM', 'JWT')
            LicenseUri = 'https://github.com/roryvossepoel/WindowsDeviceLink-Public/blob/main/LICENSE'
            ProjectUri = 'https://github.com/roryvossepoel/WindowsDeviceLink-Public'
            Prerelease = 'preview1'
        }
    }
}
