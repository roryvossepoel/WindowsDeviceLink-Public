# WindowsDeviceLink Azure Automation receiver

`Register-WindowsDeviceLinkWebhook.ps1` is an optional Azure Automation receiver for `Register-WindowsDeviceLink -Method Webhook`.

The endpoint receives a DeviceLink generated locally on Windows/WinPE and performs the tenant-side pre-association. Graph credentials remain in Azure instead of on the endpoint.

For the Azure Function alternative and common backend architecture, see [../docs/AZURE-BACKEND.md](../docs/AZURE-BACKEND.md).

A Deploy to Azure template for the Automation backend is available in [../infrastructure/automation](../infrastructure/automation). It creates the account, PowerShell 7.4 Runtime Environment, Graph authentication package, runbook and configuration assets. The webhook is intentionally created afterwards because its URL is a secret.

## Runtime Environment

Use an Azure Automation Runtime Environment with PowerShell 7.4 and `Microsoft.Graph.Authentication`.

The runbook uses:

```text
Connect-MgGraph
Invoke-MgGraphRequest
```

## Client usage

The module already supports the two routing/security values required by the receiver:

```powershell
$deviceLink = Get-WindowsDeviceLink

$deviceLink | Register-WindowsDeviceLink `
    -Method Webhook `
    -WebhookUri '<azure-automation-webhook-url>' `
    -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
    -TenantId '<target-tenant-id>'
```

- `WebhookApiKey` is sent only in `X-WindowsDeviceLink-Key`.
- `TenantId` is routing information in webhook schema v1.
- No Graph credential is stored on Windows/WinPE.

## Automation variables

### `WindowsDeviceLinkDefaultTenantId`

Optional when the request includes `tenantId`.

Useful for a single-tenant receiver where the client does not need to supply `-TenantId`.

### `WindowsDeviceLinkWebhookApiKey`

Optional encrypted Automation Variable in the sample code, but strongly recommended unless equivalent request protection exists in front of the webhook.

If configured, every request must contain the same value in:

```text
X-WindowsDeviceLink-Key
```

Do not hard-code a real API key in source control.

### `WindowsDeviceLinkTenantConfiguration`

Optional JSON Automation Variable used for tenant routing/authentication.

Example:

```json
{
  "11111111-1111-1111-1111-111111111111": {
    "authMethod": "ManagedIdentity"
  },
  "22222222-2222-2222-2222-222222222222": {
    "authMethod": "Certificate",
    "clientId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "certificateAssetName": "WindowsDeviceLinkBackend"
  }
}
```

## Authentication models

### Managed Identity

Use Managed Identity when the Automation Account and target Graph tenant are the same tenant and that managed identity has the required Graph application role.

Managed identity is not the general cross-tenant model.

### Certificate

Use certificate authentication for cross-tenant routing.

The recommended design is one multitenant Entra application with:

```text
Microsoft Graph application permission:
DeviceManagementServiceConfig.ReadWrite.All
```

and admin consent in every target tenant.

The certificate asset contains the private key used by the Automation runbook.

See:

- [../docs/APP-REGISTRATION.md](../docs/APP-REGISTRATION.md)
- [../docs/MULTITENANT-CONSENT.md](../docs/MULTITENANT-CONSENT.md)

## Required Graph permission

Whichever application identity the runbook uses in a target tenant requires:

```text
DeviceManagementServiceConfig.ReadWrite.All
```

as an **application** permission with admin consent.

## Webhook payload

The receiver implements [webhook schema v1](../docs/WEBHOOK-SCHEMA-v1.md).

Only:

```text
device.deviceLink
```

is submitted to the Graph import action.

Other request fields are for routing, correlation and diagnostics.

Treat the DeviceLink payload and related identity fields as sensitive operational data. Do not write the full request body to unrestricted logs.

## Graph operation

The receiver calls:

```text
POST https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice
```

HTTP 409 is surfaced as an existing/conflicting DeviceLink pre-association.

## Single-tenant example

```powershell
Get-WindowsDeviceLink |
    Register-WindowsDeviceLink `
        -Method Webhook `
        -WebhookUri '<azure-automation-webhook-url>' `
        -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY
```

Configure `WindowsDeviceLinkDefaultTenantId` in Automation.

## Multi-tenant example

```powershell
Get-WindowsDeviceLink |
    Register-WindowsDeviceLink `
        -Method Webhook `
        -WebhookUri '<azure-automation-webhook-url>' `
        -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
        -TenantId '<target-tenant-id>'
```

The receiver resolves the matching entry in `WindowsDeviceLinkTenantConfiguration`.

## Security notes

- Prefer certificate authentication for cross-tenant use.
- Do not put Graph credentials in the webhook request.
- Do not log the complete DeviceLink payload.
- Keep webhook API keys in encrypted Automation Variables or another secret store.
- Keep certificate private keys in Automation certificate assets.
- Unknown target tenants should fail closed rather than silently falling back to another tenant.

## Related documentation

- [Azure backend architecture](../docs/AZURE-BACKEND.md)
- [App registration](../docs/APP-REGISTRATION.md)
- [Multitenant consent](../docs/MULTITENANT-CONSENT.md)
- [Webhook schema v1](../docs/WEBHOOK-SCHEMA-v1.md)
