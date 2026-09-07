@{
    RootModule        = 'WindowsDeviceLink.psm1'
    ModuleVersion     = '0.4.0'
    GUID              = '776a2252-d4f4-495d-9445-ac3195ebbf46'
    Author            = 'Rory Vossepoel'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026 Rory Vossepoel. MIT License.'
    Description       = 'Generate DeviceLink identity, export the official CSV, and pre-associate physical Windows devices for Windows Autopilot Device Preparation Device Association from AMD64 Windows 11 and Windows PE.'
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
