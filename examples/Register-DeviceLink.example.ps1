$modulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
Import-Module $modulePath -Force

# Validate local DeviceLink support
Test-WindowsDeviceLinkSupport | Format-List *

# Obtain the local DeviceLink identity only
$deviceLink = Get-WindowsDeviceLink
$deviceLink | Format-List *

# Export official Windows-generated CSV
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'

# Standard delegated device-code pre-association; TenantId is optional
$registration = $deviceLink | Register-WindowsDeviceLink `
    -Method DeviceCode
$registration | Format-List *

# Explicitly query the tenant-side Device Association
Get-WindowsDeviceLinkAssociation `
    -SerialNumber $deviceLink.SerialNumber `
    -Method DeviceCode | Format-List *

# Explicit tenant targeting for multi-tenant / guest scenarios
$deviceLink | Register-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<target-tenant-id>' | Format-List *

# App-only registration example with a client secret
$secret = Read-Host 'Client secret' -AsSecureString
$deviceLink | Register-WindowsDeviceLink `
    -Method ClientSecret `
    -TenantId '<tenant-id>' `
    -ClientId '<app-id>' `
    -ClientSecret $secret

# Webhook registration. TenantId is optional and can be used for multi-tenant routing.
$webhookKey = $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY
$deviceLink | Register-WindowsDeviceLink `
    -Method Webhook `
    -WebhookUri '<webhook-url>' `
    -WebhookApiKey $webhookKey `
    -TenantId '<optional-target-tenant-id>'
