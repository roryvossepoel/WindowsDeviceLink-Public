$modulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
Import-Module $modulePath -Force

# Validate support
Test-WindowsDeviceLinkSupport | Format-List *

# Generate only
$deviceLink = Get-WindowsDeviceLink
$deviceLink | Format-List *

# Export official Windows-generated CSV
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'

# Delegated device-code flow
Get-WindowsDeviceLink `
    -Online `
    -Method DeviceCode `
    -TenantId '<tenant-id>'

# App-only example with a client secret
$secret = Read-Host 'Client secret' -AsSecureString
Get-WindowsDeviceLink `
    -Online `
    -Method ClientSecret `
    -TenantId '<tenant-id>' `
    -ClientId '<app-id>' `
    -ClientSecret $secret

# Webhook flow. TenantId is optional and can be used for multi-tenant routing.
# Obtain the API key from your deployment/configuration/secrets mechanism.
$webhookKey = $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY
Get-WindowsDeviceLink `
    -Online `
    -Method Webhook `
    -WebhookUri '<webhook-url>' `
    -WebhookApiKey $webhookKey `
    -TenantId '<optional-target-tenant-id>'
