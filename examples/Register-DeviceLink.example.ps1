$modulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
Import-Module $modulePath -Force

Test-WindowsDeviceLinkSupport | Format-List *

# Generate only
$deviceLink = Get-WindowsDeviceLink
$deviceLink | Format-List *

# Export official Windows-generated CSV
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'

# Preferred online flow
Get-WindowsDeviceLink `
    -Online `
    -TenantId '<tenant-id>' `
    -UseDeviceCode

# App-only example with a client secret
$secret = Read-Host 'Client secret' -AsSecureString
Get-WindowsDeviceLink `
    -Online `
    -TenantId '<tenant-id>' `
    -ClientId '<app-id>' `
    -ClientSecret $secret
