@{
    RootModule        = 'WindowsDeviceLink.psm1'
    ModuleVersion     = '0.4.0'
    GUID              = '776a2252-d4f4-495d-9445-ac3195ebbf46'
    Author            = 'Rory Vossepoel'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026 Rory Vossepoel. MIT License.'
    Description       = 'Generate TPM-backed DeviceLink identity information, export the official Windows-generated .devicelink.csv, and pre-associate physical Windows devices with Microsoft Intune for Windows Autopilot Device Preparation Device Association. Supports AMD64 Windows 11 and Windows PE, multiple online authentication methods, and optional webhook-based registration for unattended and multi-tenant automation.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop')
    FunctionsToExport = @(
        'Connect-WindowsDeviceLink'
        'Export-WindowsDeviceLinkCsv'
        'Get-WindowsDeviceLink'
        'Register-WindowsDeviceLink'
        'Test-WindowsDeviceLinkSupport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Windows', 'WinPE', 'Intune', 'Autopilot', 'DevicePreparation', 'DeviceLink', 'DeviceAssociation', 'Webhook')
            LicenseUri = 'https://github.com/roryvossepoel/WindowsDeviceLink-Public/blob/main/LICENSE'
            ProjectUri = 'https://github.com/roryvossepoel/WindowsDeviceLink-Public'
            Prerelease = 'preview1'
        }
    }
}
