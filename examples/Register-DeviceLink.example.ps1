$modulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
Import-Module $modulePath -Force

# Validate local DeviceLink support
Test-WindowsDeviceLinkSupport | Format-List *

# Obtain the local DeviceLink identity only
$deviceLink = Get-WindowsDeviceLink
$deviceLink | Format-List *

# Export official Windows-generated CSV
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'

# Explicit tenant-side pre-association using delegated device-code flow
$registration = $deviceLink | Register-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
$registration | Format-List *

# Explicitly query the tenant-side Device Association
Get-WindowsDeviceLinkAssociation `
    -SerialNumber $deviceLink.SerialNumber `
    -Method DeviceCode `
    -TenantId '<tenant-id>' | Format-List *

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
